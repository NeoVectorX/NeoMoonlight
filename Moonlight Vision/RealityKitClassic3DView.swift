//
//  RealityKitClassic3DView.swift
//  Moonlight Vision
//
//  Created by Alex on 1/27/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import GameController
import RealityKit
import SwiftUI
import simd

struct RealityKitClassic3DView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Binding var streamConfig: StreamConfiguration?
    var needsHdr: Bool
    
    var body: some View {
        if streamConfig != nil {
            _RealityKitClassic3DView(streamConfig: Binding<StreamConfiguration>(
                get: { streamConfig ?? StreamConfiguration() },
                set: { streamConfig = $0 }
            ), needsHdr: needsHdr) {
                dismissWindow()
                streamConfig = nil
            }
        } else {
            ProgressView().onAppear { dismissWindow() }
        }
    }
}

struct _RealityKitClassic3DView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow

    @Binding var streamConfig: StreamConfiguration

    @State var controllerSupport: ControllerSupport?
    @State var height: Float = 0
    
    @State var shouldClose: Bool = false
    
    @State private var hideControls = false
    
    @State private var hideTimer: Timer?
    
    @State private var spatialAudioMode: Bool = true

    var isSBSVideo: Bool {
        let ratio = Float(streamConfig.width) / Float(streamConfig.height)
        return abs(ratio - (32.0 / 9.0)) < 0.01 
    }

    var aspectRatio: Float {
        if videoMode == .sideBySide3D && isSBSVideo {
            return Float(streamConfig.height) / Float(streamConfig.width / 2)
        } else {
            return Float(streamConfig.height) / Float(streamConfig.width)
        }
    }

    @State var _streamMan: StreamManager?
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()

    @State var texture: TextureResource
    @State var screen: ModelEntity = ModelEntity()
    
    let closeAction: () -> Void

    @State var videoMode: VideoMode = .standard2D

    @State private var surfaceMaterial: ShaderGraphMaterial?

    init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool, closeAction: @escaping () -> Void) {
        self.closeAction = closeAction
        self._streamConfig = streamConfig
        self.controllerSupport = ControllerSupport(config: streamConfig.wrappedValue, delegate: DummyControllerDelegate())
        let bytesPerPixel = needsHdr ? 8 : 4
        let data = Data.init(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height))
        self.texture = try! TextureResource(
            dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
            format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb),
            contents: .init(
                mipmapLevels: [
                    .mip(data: data, bytesPerRow: bytesPerPixel * Int(streamConfig.wrappedValue.width)),
                ]
            )
        )
    }

    var body: some View {
        GeometryReader3D { proxy in
                RealityView { content in
                    // Create a flat plane (curvature locked to 0)
                    let mesh = try! _RealityKitStreamView.generateCurvedPlane(
                        width: MAX_WIDTH_METERS, 
                        aspectRatio: aspectRatio, 
                        resulotion: (100, 100), 
                        curveMagnitude: 0  // Always flat
                    )
                    let colBox = ShapeResource.generateBox(width: 2, height: 2 * aspectRatio, depth: 0.001).offsetBy(translation: .init(x: 0, y: -0.43, z: 1))
                    screen = ModelEntity(mesh: mesh, materials: [])

                    // Initialize material if needed
                    if surfaceMaterial == nil {
                        surfaceMaterial = try! await ShaderGraphMaterial(
                            named: "/Root/SBSMaterial",
                            from: "SBSMaterial.usda"
                        )

                        try! surfaceMaterial!.setParameter(
                            name: "texture",
                            value: .textureResource(self.texture)
                        )
                    }

                    if videoMode == .sideBySide3D {
                        screen.model?.materials = [surfaceMaterial!]
                    } else {
                        screen.model?.materials = [UnlitMaterial(texture: self.texture)]
                    }

                    screen.collision = CollisionComponent(shapes: [colBox], mode: .colliding)
                    screen.components.set(InputTargetComponent())
                    content.add(screen)
                } update: { content in
                    let mesh = try! _RealityKitStreamView.generateCurvedPlane(
                        width: MAX_WIDTH_METERS, 
                        aspectRatio: aspectRatio, 
                        resulotion: (100, 100), 
                        curveMagnitude: 0  // Always flat
                    )
                    let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    screen.transform.scale = .init(repeating: size.extents.x / 2)
                    screen.transform.translation = SIMD3<Float>(0, height, 1.0)  // Fixed depth
                    try! screen.model!.mesh.replace(with: mesh.contents)
                }
                .handlesGameControllerEvents(matching: .gamepad)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissWindow(id: "mainView")
            if self.spatialAudioMode {
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            } else {
                AudioHelpers.fixAudioForDirectStereo()
            }
        }
        .persistentSystemOverlays(hideControls ? .hidden : .visible)
        .ornament(visibility: connectionCallbacks.showAlert ? .visible :  .hidden , attachmentAnchor: .scene(.bottomFront), contentAlignment: .bottom) {
            VStack(alignment: .center) {
                Image(systemName: "exclamationmark.triangle")
                Text("Stream error")
                    .font(.title)
                Text(connectionCallbacks.errorMessage ?? "Unknown error")
                Button("Close") {
                    shouldClose.toggle()
                    dismissWindow()
                }
            }
            .padding()
            .glassBackgroundEffect()
        }
        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
            HStack(spacing: 24) {
                // Home button (left)
                Button {
                    if hideControls {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            hideTimer?.invalidate()
                            startHideTimer()
                        }
                    } else {
                        pushWindow(id: "mainView")
                    }
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
                .labelStyle(.iconOnly)
                
                // 3D/SBS toggle (center)
                Button {
                    if hideControls {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            hideTimer?.invalidate()
                            startHideTimer()
                        }
                    } else {
                        videoMode = videoMode == .standard2D ? .sideBySide3D : .standard2D
                        if videoMode == .sideBySide3D {
                            screen.model?.materials = [surfaceMaterial!]
                        } else {
                            screen.model?.materials = [UnlitMaterial(texture: texture)]
                        }
                    }
                } label: {
                    Label(videoMode == .standard2D ? "Standard Display" : "3D", 
                          systemImage: videoMode == .standard2D ? "rectangle" : "rectangle.split.2x1")
                }
                .labelStyle(.iconOnly)
                
                // Spatial Audio toggle (right)
                Button {
                    if hideControls {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            hideTimer?.invalidate()
                            startHideTimer()
                        }
                    } else {
                        spatialAudioMode.toggle()
                        if spatialAudioMode {
                            AudioHelpers.fixAudioForSurroundForCurrentWindow()
                        } else {
                            AudioHelpers.fixAudioForDirectStereo()
                        }
                    }
                } label: {
                    Label(spatialAudioMode ? "Spatial Audio" : "Direct Audio", 
                          systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                }
                .labelStyle(.iconOnly)
            }
            .opacity(hideControls ? 0.03 : 0.5)
            .animation(.easeInOut(duration: 0.3), value: hideControls)
            .allowsHitTesting(true)
            .hoverEffect { effect, isActive, _ in
                if isActive && hideControls {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideControls = false
                        hideTimer?.invalidate()
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if !viewModel.activelyStreaming {
                print("_RealityKitClassic3DView: Detected appearance without active stream state. Closing stream window and opening main view.")
                hideControls = false
                hideTimer?.invalidate()
                openWindow(id: "mainView")
                self.closeAction()
                return
            }

            NotificationCenter.default.addObserver(
                forName: Notification.Name("ResumeStreamFromMenu"),
                object: nil,
                queue: .main
            ) { _ in
                dismissWindow(id: "mainView")
                if self.spatialAudioMode {
                    AudioHelpers.fixAudioForSurroundForCurrentWindow()
                } else {
                    AudioHelpers.fixAudioForDirectStereo()
                }
            }
            
            dismissWindow(id: "mainView")
            dismissWindow(id: "dummy")
            
            hideControls = false
            spatialAudioMode = true
            
            self._streamMan = StreamManager(
                config: self.streamConfig,
                rendererProvider: {
                    DrawableVideoDecoder(texture: self.texture, callbacks: self.connectionCallbacks, aspectRatio: Float(self.streamConfig.width) / Float(self.streamConfig.height), useFramePacing: self.streamConfig.useFramePacing, enableHDR: self.viewModel.streamSettings.enableHdr) { texture, correctedResultion in
                        DispatchQueue.main.async {
                            if let correctedResultion = correctedResultion {
                                streamConfig.width = Int32(correctedResultion.0)
                                streamConfig.height = Int32(correctedResultion.1)
                            }
                            self.texture.replace(withDrawables: texture)
                            self.controllerSupport!.connectionEstablished()
                            
                            startHideTimer()
                        }
                    }
                },
                connectionCallbacks: self.connectionCallbacks
            )
            let operationQueue = OperationQueue()
            operationQueue.addOperation(_streamMan!)
        }
        .onDisappear {
            if viewModel.activelyStreaming {
                viewModel.activelyStreaming = false
            }
            if let sm = _streamMan {
                _streamMan = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    print("[RK Classic 3D] onDisappear -> calling stopStream()")
                    sm.stopStream()
                }
            }
            controllerSupport?.cleanup()
            controllerSupport = nil

            print("[RK Classic 3D] Posting RKStreamDidTeardown (onDisappear)")
            NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
        }
        .onChange(of: shouldClose) { _, shouldClose in
            if shouldClose {
                hideControls = false
                hideTimer?.invalidate()
                print("[RK Classic 3D] shouldClose -> pushing mainView")
                pushWindow(id: "mainView")
                dismissWindow()
            }
        }
        .onChange(of: viewModel.activelyStreaming) { _, isActive in
            // Black Screen Recovery: Handle stream state changes
            if !isActive {
                print("[RealityKit Classic 3D] Stream became inactive, cleaning up...")
                hideControls = false
                hideTimer?.invalidate()
                print("[RK Classic 3D] activelyStreaming=false -> pushing mainView")
                pushWindow(id: "mainView")
                self.closeAction()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: break
            case .inactive: print("inactive")
            case .background:
                print("background")
                hideControls = false
                hideTimer?.invalidate()
                viewModel.activelyStreaming = false
                _streamMan?.stopStream()
                _streamMan = nil
                controllerSupport?.cleanup()
                if !shouldClose {
                    print("[RK Classic 3D] background -> pushing mainView")
                    pushWindow(id: "mainView")
                }
                self.closeAction()
            @unknown default: 
                break
            }
        }
        .preferredSurroundingsEffect(viewModel.streamSettings.dimPassthrough ? .systemDark : nil)
        .volumeBaseplateVisibility(viewModel.streamSettings.dimPassthrough ? .hidden : .automatic)
        .supportedVolumeViewpoints(.front)
        .overlay {
            // Stats Overlay - show when enabled (even if empty)
            if viewModel.streamSettings.statsOverlay {
                VStack {
                    HStack {
                        Text(statsOverlayText.isEmpty ? "Collecting stats..." : statsOverlayText)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.7))
                            .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
                .allowsHitTesting(false)
            }
        }
    }
    
    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if viewModel.activelyStreaming {
                withAnimation(.easeOut(duration: 0.3)) {
                    hideControls = true
                }
            }
        }
    }
    
    // Rebind material helper
    private func rebindScreenMaterial() {
        if videoMode == .sideBySide3D {
            if var mat = surfaceMaterial {
                try? mat.setParameter(name: "texture", value: .textureResource(self.texture))
                surfaceMaterial = mat
                screen.model?.materials = [mat]
            } else {
                screen.model?.materials = [UnlitMaterial(texture: self.texture)]
            }
        } else {
            screen.model?.materials = [UnlitMaterial(texture: self.texture)]
        }
    }

    private func stopStreamAndCleanupClassic() {
        hideControls = false
        hideTimer?.invalidate()

        if let sm = _streamMan {
            _streamMan = nil
            DispatchQueue.global(qos: .userInitiated).async {
                sm.stopStream()
            }
        }

        controllerSupport?.cleanup()
        controllerSupport = nil

        openWindow(id: "mainView")
        self.closeAction()
    }
}