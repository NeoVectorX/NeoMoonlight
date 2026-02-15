//
//  RealityKitStreamView.swift
//  Moonlight Vision
//
//  Created by tht7 on 29/12/2024.
//  Copyright 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import GameController
import RealityKit
import SwiftUI
import simd
import UIKit
import Metal
import QuartzCore

let COOL_NUMBER: Float = 2.79945612 // 3.8
let MAX_WIDTH_METERS: Float = 2

@objc
class DummyControllerDelegate: NSObject, ControllerSupportDelegate {
    func gamepadPresenceChanged() {}

    func mousePresenceChanged() {}

    func streamExitRequested() {}
}

struct RealityKitStreamView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow // Keep this
    @Binding var streamConfig: StreamConfiguration?
    var needsHdr: Bool
    
    // @EnvironmentObject private var viewModel: MainViewModel // Not needed here
    
    var body: some View {
        if streamConfig != nil {
            _RealityKitStreamView(streamConfig: Binding<StreamConfiguration>(
                get: { streamConfig ?? StreamConfiguration() },
                set: { streamConfig = $0 }
            ), needsHdr: needsHdr) {
                
                // This is the ORIGINAL closeAction passed down.
                // It's used when the view disappears for other reasons (like backgrounding)
                // OR if the disconnect fails and we need to force close.
                
                // We keep the original logic here for safety/cleanup.
                dismissWindow()
                streamConfig = nil
            }
        } else {
            ProgressView().onAppear { dismissWindow() }
        }
    }
}

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

    @State private var controlsHighlighted = false

    @State private var hideTimer: Timer?
    
    @State private var spatialAudioMode: Bool = true
    
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?

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
        let bytesPerPixel = needsHdr ? 8 : 4  // HDR is 64-bit (8 bytes), SDR is 32-bit (4 bytes)
        let data = Data.init(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height)) // Dummy data
        self.texture = try! TextureResource(
            dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
            format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb), // Doesn't matter, dummy data
            contents: .init(
                mipmapLevels: [
                    .mip(data: data, bytesPerRow: bytesPerPixel * Int(streamConfig.wrappedValue.width)),
                ]
            )
        )
    }

    private func rkPresetName(_ v: Int32) -> String {
        switch v {
        case 0: return "FILTER: Default"
        case 1: return "FILTER: Cinematic"
        case 2: return "FILTER: Vi\u{200A}vid"  // Hair space between I and V
        case 3: return "FILTER: Realistic"
        default: return "FILTER: Default"
        }
    }

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let mesh = try! _RealityKitStreamView.generateCurvedPlane(width: MAX_WIDTH_METERS, aspectRatio: aspectRatio, resulotion: (100,100), curveMagnitude: 0)
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
                    screen.model?.materials = [UnlitMaterial(texture: texture)]
                }

                screen.collision = CollisionComponent(shapes: [
                    colBox
                ], mode: .colliding)
                screen.components.set(InputTargetComponent())
                content.add(screen)
            } update: { content in
                let mesh = try! _RealityKitStreamView.generateCurvedPlane(width: MAX_WIDTH_METERS, aspectRatio: aspectRatio, resulotion: (100,100), curveMagnitude: 0)
                let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                screen.transform.scale = .init(repeating: size.extents.x / 2)
                screen.transform.translation = SIMD3<Float>(0, height, 1.0)
                try! screen.model!.mesh.replace(with: mesh.contents)
            }
            .handlesGameControllerEvents(matching: .gamepad)
        }
        .persistentSystemOverlays(hideControls ? .hidden : .visible)
        .overlay {
            if viewModel.streamSettings.statsOverlay && !statsOverlayText.isEmpty {
                VStack {
                    HStack {
                        Text(statsOverlayText)
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
        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .center) {
            HStack(spacing: 24) {
                Button {
                    if hideControls && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    pushWindow(id: "mainView")
                    startHideTimer()
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
                .labelStyle(.iconOnly)
                
                Button {
                    if hideControls && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    videoMode = videoMode == .standard2D ? .sideBySide3D : .standard2D
                    if videoMode == .sideBySide3D {
                        screen.model?.materials = [surfaceMaterial!]
                    } else {
                        screen.model?.materials = [UnlitMaterial(texture: texture)]
                    }
                    startHideTimer()
                } label: {
                    Label(videoMode == .standard2D ? "Standard Display" : "3D",
                          systemImage: videoMode == .standard2D ? "rectangle" : "rectangle.split.2x1")
                }
                .labelStyle(.iconOnly)
                
                Button {
                    if hideControls && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    spatialAudioMode.toggle()
                    if spatialAudioMode {
                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                    } else {
                        AudioHelpers.fixAudioForDirectStereo()
                    }
                    startHideTimer()
                } label: {
                    Label(spatialAudioMode ? "Spatial" : "Direct",
                          systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                }
                .labelStyle(.iconOnly)
                
                Button {
                    if hideControls && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideControls = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    let all: [Int32] = [0, 1, 2, 3]
                    let cur = viewModel.streamSettings.uikitPreset
                    let next = all[(all.firstIndex(of: cur) ?? -1 + 1) % all.count]
                    viewModel.streamSettings.uikitPreset = next
                    LiRequestIdrFrame()
                    startHideTimer()
                } label: {
                    Label("Preset: \(rkPresetName(viewModel.streamSettings.uikitPreset))", systemImage: "camera.filters")
                }
                .labelStyle(.iconOnly)
            }
            .opacity(hideControls ? 0.05 : (controlsHighlighted ? 1.0 : 0.5))
            .animation(.easeInOut(duration: 0.3), value: hideControls)
            .allowsHitTesting(true)
            .padding()
        }
        .onAppear {
            if !viewModel.activelyStreaming {
                hideControls = false
                hideTimer?.invalidate()
                openWindow(id: "mainView")
                self.closeAction()
                return
            }
            
            dismissWindow(id: "mainView")
            dismissWindow(id: "dummy")
            
            hideControls = false
            spatialAudioMode = true
            
            self._streamMan = StreamManager(
                config: self.streamConfig,
                rendererProvider: {
                    DrawableVideoDecoder(
                        texture: self.texture,
                        callbacks: self.connectionCallbacks,
                        aspectRatio: Float(self.streamConfig.width) / Float(self.streamConfig.height),
                        useFramePacing: self.streamConfig.useFramePacing,
                        enableHDR: self.viewModel.streamSettings.enableHdr,
                        hdrSettingsProvider: nil,
                        enhancementsProvider: {
                            let p = self.viewModel.streamSettings.uikitPreset
                            let warmth: Float = self.viewModel.streamSettings.enableHdr ? 0.03 : 0.0
                            switch p {
                            case 0: return (1.0, 1.0, warmth)     // Default
                            case 1: return (1.15, 1.0, warmth)    // Cinematic
                            case 2: return (1.25, 1.0, warmth)    // Vivid
                            case 3: return (0.90, 1.05, warmth)   // Realistic
                            default: return (1.0, 1.0, warmth)
                            }
                        }
                    ) { texture, correctedResultion in
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
            
            if viewModel.streamSettings.statsOverlay {
                startStatsTimer()
            }
        }
        .onDisappear {
            if viewModel.activelyStreaming {
                viewModel.activelyStreaming = false
            }
            if let sm = _streamMan {
                _streamMan = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    sm.stopStream()
                }
            }
            controllerSupport?.cleanup()
            controllerSupport = nil

            NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
        }
        .onChange(of: shouldClose) { _, shouldClose in
            if shouldClose {
                hideControls = false
                hideTimer?.invalidate()
                pushWindow(id: "mainView")
                dismissWindow()
            }
        }
        .onChange(of: viewModel.activelyStreaming) { _, isActive in
            if !isActive {
                hideControls = false
                hideTimer?.invalidate()
                pushWindow(id: "mainView")
                self.closeAction()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                break
            case .inactive:
                break
            case .background:
                hideControls = false
                hideTimer?.invalidate()
                viewModel.activelyStreaming = false
                _streamMan?.stopStream()
                _streamMan = nil
                controllerSupport?.cleanup()
                if !shouldClose {
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
    }
    
    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if viewModel.activelyStreaming {
                withAnimation(.easeOut(duration: 0.3)) {
                    hideControls = true
                    controlsHighlighted = false
                }
            }
        }
    }

    private func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                controlsHighlighted = false
                hideControls = true
            }
        }
    }
    
    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let streamMan = _streamMan, let stats = streamMan.getStatsOverlayText() {
                statsOverlayText = stats
            }
        }
        statsTimer?.fire()
    }
}

struct _RealityKitStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow

    @Binding var streamConfig: StreamConfiguration

    @State var curveMagnitudeMemory: Float = 0
    @State var curveAnimationMultiplier: Float = 1
    @State var controllerSupport: ControllerSupport?
    @State var height: Float = 0
    
    @State private var depthOffset: Float = 1.0
    
    @State private var shouldClose: Bool = false
    
    @State private var hideOrnament = false

    @State private var controlsHighlighted = false

    @State private var showHint = true
    
    @State private var hasSeenHint: Bool = UserDefaults.standard.bool(forKey: "hasSeenControlsHint")
    
    @State private var hideTimer: Timer?
    
    @State private var showRestoreButton = false
    
    @State private var isHoveringRestoreButton = false
    
    @State private var spatialAudioMode: Bool = true
    
    @StateObject private var hdrParams = HDRTestParams()
    @State private var showModeLabel: Bool = false
    @State private var modeLabelTimer: Timer?
    @State private var showPresetLabel: Bool = false
    @State private var presetLabelTimer: Timer?
    @State private var presetLabelText: String = ""
    
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)

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
    

    @State var animationTimer: Timer?

    @State var _streamMan: StreamManager?
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()

    @State var enlarge = false

    @State var texture: TextureResource
    @State var screen: ModelEntity = ModelEntity()
    
    let closeAction: () -> Void

    @State var videoMode: VideoMode = .standard2D

    @State private var surfaceMaterial: ShaderGraphMaterial?

    // Stats overlay state
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?

    private func rkPresetName(_ v: Int32) -> String {
        switch v {
        case 0: return "FILTER: Default"
        case 1: return "FILTER: Cinematic"
        case 2: return "FILTER: Vi\u{200A}vid"  // Hair space between I and V
        case 3: return "FILTER: Realistic"
        default: return "FILTER: Default"
        }
    }

    init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool, closeAction: @escaping () -> Void) {
        self.closeAction = closeAction
        self._streamConfig = streamConfig
        self.controllerSupport = ControllerSupport(config: streamConfig.wrappedValue, delegate: DummyControllerDelegate())
        let bytesPerPixel = needsHdr ? 8 : 4  // HDR is 64-bit (8 bytes), SDR is 32-bit (4 bytes)
        let data = Data.init(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height)) // Dummy data
        self.texture = try! TextureResource(
            dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
            format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb), // Doesn't matter, dummy data
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
                    let mesh = try! _RealityKitStreamView.generateCurvedPlane(width: MAX_WIDTH_METERS, aspectRatio: aspectRatio, resulotion: (100,100), curveMagnitude: viewModel.streamSettings.realitykitRendererCurvature * curveAnimationMultiplier)
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
                        screen.model?.materials = [UnlitMaterial(texture: texture)]
                    }

                    screen.collision = CollisionComponent(shapes: [
                        colBox
                    ], mode: .colliding)
                    screen.components.set(InputTargetComponent())
                    content.add(screen)
                } update: { content in
                    let mesh = try! _RealityKitStreamView.generateCurvedPlane(width: MAX_WIDTH_METERS, aspectRatio: aspectRatio, resulotion: (100,100), curveMagnitude: viewModel.streamSettings.realitykitRendererCurvature * curveAnimationMultiplier)
                    if !screenLocked {
                        let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                        screen.transform.scale = .init(repeating: size.extents.x / 2)
                        screen.transform.translation = SIMD3<Float>(0, height, depthOffset)
                    }
                    try! screen.model!.mesh.replace(with: mesh.contents)
                }
                .handlesGameControllerEvents(matching: .gamepad)
        }
        .persistentSystemOverlays(hideOrnament ? .hidden : .visible)
        .overlay {
            VStack {
                Spacer().frame(height: 80)
                
                ZStack {
                    // HDR Mode Label (unchanged)
                    if showModeLabel {
                        VStack(spacing: 12) {
                            Image(systemName: hdrModeIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [brandViolet, brandPurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text(hdrModeName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [brandViolet.opacity(0.45), brandViolet.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: brandViolet.opacity(0.25), radius: 20, x: 0, y: 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Spacer()
            }
            .allowsHitTesting(false)
            
            if showPresetLabel {
                PresetPopupView(text: presetLabelText)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
            }
            
            if !hasSeenHint && hideOrnament {
                // ... existing hint code ...
            }
            
            if viewModel.streamSettings.statsOverlay {
                // ... existing stats code ...
            }
        }
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
            HStack(spacing: 16) {
                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    pushWindow(id: "mainView")
                    startHideTimer()
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
                .labelStyle(.iconOnly)

                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    spatialAudioMode.toggle()
                    if spatialAudioMode {
                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                    } else {
                        AudioHelpers.fixAudioForDirectStereo()
                    }
                    startHideTimer()
                } label: {
                    Label(spatialAudioMode ? "Spatial Audio" : "Direct Audio",
                          systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                }
                .labelStyle(.iconOnly)

                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    hdrParams.mode = (hdrParams.mode + 1) % 3
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showModeLabel = true
                    }
                    modeLabelTimer?.invalidate()
                    modeLabelTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            showModeLabel = false
                        }
                    }
                    startHideTimer()
                } label: {
                    Label("HDR Mode", systemImage: hdrModeIcon)
                }
                .labelStyle(.iconOnly)

                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    let all: [Int32] = [0, 1, 2, 3]
                    let cur = viewModel.streamSettings.uikitPreset
                    let next = all[(all.firstIndex(of: cur) ?? -1 + 1) % all.count]
                    viewModel.streamSettings.uikitPreset = next

                    presetLabelText = "Preset: \(rkPresetName(next))"
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPresetLabel = true
                    }
                    presetLabelTimer?.invalidate()
                    presetLabelTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPresetLabel = false
                        }
                    }
                    
                    LiRequestIdrFrame()
                    startHideTimer()
                } label: {
                    Label("Preset", systemImage: "camera.filters")
                }
                .labelStyle(.iconOnly)

                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    screenLocked.toggle()
                    UserDefaults.standard.set(screenLocked, forKey: "rkScreenLocked")
                    startHideTimer()
                } label: {
                    Label(screenLocked ? "Locked" : "Unlocked",
                          systemImage: screenLocked ? "lock.fill" : "lock.open.fill")
                }
                .labelStyle(.iconOnly)
            }
            .opacity(hideOrnament ? 0.03 : (controlsHighlighted ? 1.0 : 0.5))
            .animation(.easeInOut(duration: 0.3), value: hideOrnament)
            .allowsHitTesting(true)
            .padding()
        }
        // The entire block starting with:
        // .ornament(visibility: showControlPanel ? .visible : .hidden, attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
        //     VStack(alignment: .leading, spacing: 20) {
        //         ...
        //     }
        // }
        .onAppear {
            if viewModel.streamSettings.statsOverlay {
                startStatsTimer()
            }
        }
        .onDisappear {
            statsTimer?.invalidate()
            statsTimer = nil
        }
    }
    
    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if viewModel.activelyStreaming {
                withAnimation(.easeOut(duration: 0.3)) {
                    hideOrnament = true
                    controlsHighlighted = false
                }
            }
        }
    }

    private func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                controlsHighlighted = false
                hideOrnament = true
            }
        }
    }
    
    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let streamMan = _streamMan, let stats = streamMan.getStatsOverlayText() {
                DispatchQueue.main.async {
                    self.statsOverlayText = stats
                }
            }
        }
        statsTimer?.fire()
    }

    static func generateCurvedPlane(
        width: Float, // Chord width
        aspectRatio: Float,
        resulotion: (UInt32, UInt32),
        curveMagnitude: Float // Value from 0 (flat) to 1 (max curve)
    ) throws -> MeshResource {

        var descr = MeshDescriptor(name: "curved_plane_inward")
        let height = width * aspectRatio
        let vertexCount = Int(resulotion.0 * resulotion.1)
        // Correct calculation for number of triangles and indices
        let numQuadsX = resulotion.0 - 1
        let numQuadsY = resulotion.1 - 1
        let triangleCount = Int(numQuadsX * numQuadsY * 2)
        let indexCount = triangleCount * 3

        var positions: [SIMD3<Float>] = .init(repeating: .zero, count: vertexCount)
        var textureCoordinates: [SIMD2<Float>] = .init(repeating: .zero, count: vertexCount)
        var indices: [UInt32] = .init(repeating: 0, count: indexCount)

        // --- Angle and Radius Calculation ---
        let maxCurveAngle: Float = (5.5 * .pi / 6.0) // Max curve: 120 degrees. Adjust as needed.
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 1.0))

        let radius: Float
        let halfAngle = currentAngle / 2.0

        if abs(halfAngle) < 0.0001 {
            radius = .infinity // Flat case
        } else {
            radius = width / (2.0 * sin(halfAngle))
        }
        // --- End Calculation ---

        var vertexIndex: Int = 0
        var indicesIndex: Int = 0

        for y_v in 0 ..< resulotion.1 {
            // v_geo goes 0 for the first row (y_v=0) to 1 for the last row
            let v_geo = Float(y_v) / Float(resulotion.1 - 1)

            // Y position: higher Y for lower v_geo (top of screen)
            let yPosition = (0.5 - v_geo) * height

            // Texture V coordinate: Flipped - V=1 at the top, V=0 at the bottom
            let v_tex = 1.0 - v_geo

            for x_v in 0 ..< resulotion.0 {
                // u goes 0 (left) to 1 (right)
                let u = Float(x_v) / Float(resulotion.0 - 1)

                let xPosition: Float
                let zPosition: Float

                if radius.isFinite && radius > 0 && currentAngle > 0.0001 {
                    // Curved Plane Case
                    let theta = (u - 0.5) * currentAngle // Angle from center: -halfAngle to +halfAngle

                    // X position on the circular arc
                    xPosition = radius * sin(theta)

                    // Z position: Make center positive Z (further away), edges Z=0
                    zPosition = radius * (cos(halfAngle) - cos(theta))

                } else {
                    // Flat Plane Case
                    xPosition = (u - 0.5) * width
                    zPosition = 0.0
                }

                // Assign vertex position (Y is up, +Z is away from viewer)
                positions[vertexIndex] = [xPosition, yPosition, zPosition]

                // Assign texture coordinate (U=horizontal, V=vertical, V=0 is bottom)
                textureCoordinates[vertexIndex] = [u, v_tex] // Use the flipped v_tex

                // Add indices for the quad ending SE of this vertex
                if x_v < numQuadsX && y_v < numQuadsY {
                    let current = UInt32(vertexIndex)
                    let nextRow = current + resulotion.0

                    let topLeft = current
                    let topRight = topLeft + 1
                    let bottomLeft = nextRow
                    let bottomRight = bottomLeft + 1

                    // Triangle 1: Top-Left, Bottom-Left, Bottom-Right
                    indices[indicesIndex + 0] = topLeft
                    indices[indicesIndex + 1] = bottomLeft
                    indices[indicesIndex + 2] = bottomRight

                    // Triangle 2: Top-Left, Bottom-Right, Top-Right
                    indices[indicesIndex + 3] = topLeft
                    indices[indicesIndex + 4] = bottomRight
                    indices[indicesIndex + 5] = topRight

                    indicesIndex += 6
                }
                vertexIndex += 1
            }
        }

        descr.positions = MeshBuffer(positions)
        descr.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        descr.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descr])
    }

    var hdrModeName: String {
        switch hdrParams.mode {
        case 0: return "Power Curve"
        case 1: return "ACES Filmic"
        case 2: return "ACES + Vibrance"
        default: return "Unknown"
        }
    }
    
    var hdrModeIcon: String {
        switch hdrParams.mode {
        case 0: return "bolt.fill"
        case 1: return "film.fill"
        case 2: return "sparkles"
        default: return "wand.and.stars"
        }
    }

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

    // MARK: - Subviews
    
    @ViewBuilder
    var controlIcons: some View {
        ZStack {
            HStack(spacing: 16) {
                // Home Button
                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    pushWindow(id: "mainView")
                    startHideTimer()
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
                .labelStyle(.iconOnly)
                
                // Spatial Audio Button
                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    spatialAudioMode.toggle()
                    if spatialAudioMode {
                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                    } else {
                        AudioHelpers.fixAudioForDirectStereo()
                    }
                    startHideTimer()
                } label: {
                    Label(spatialAudioMode ? "Spatial Audio" : "Direct Audio", 
                          systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                }
                .labelStyle(.iconOnly)
                
                // HDR Mode Button
                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    // Cycle HDR modes
                    hdrParams.mode = (hdrParams.mode + 1) % 3
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showModeLabel = true
                    }
                    modeLabelTimer?.invalidate()
                    modeLabelTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            showModeLabel = false
                        }
                    }
                    startHideTimer()
                } label: {
                    Label("HDR Mode", systemImage: hdrModeIcon)
                }
                .labelStyle(.iconOnly)
                
                // Control Panel Button
                Button {
                    if hideOrnament && !controlsHighlighted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hideOrnament = false
                            controlsHighlighted = true
                            hideTimer?.invalidate()
                            startHighlightTimer()
                        }
                        return
                    }
                    // Always toggle control panel regardless of hideOrnament state
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControlPanel.toggle()
                    }
                    startHideTimer()
                } label: {
                    Label("Controls", systemImage: "slider.horizontal.3")
                }
                .labelStyle(.iconOnly)
            }
            .opacity(hideOrnament ? 0.03 : (controlsHighlighted ? 1.0 : 0.5))
            .animation(.easeInOut(duration: 0.3), value: hideOrnament)
            .allowsHitTesting(true)
            .padding()
        }
    }

    @State private var screenLocked: Bool = UserDefaults.standard.bool(forKey: "rkScreenLocked")

    @State private var showControlPanel: Bool = false
}

private struct PresetPopupView: View {
    var text: String
    
    var body: some View {
        let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
        let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
        let radius: CGFloat = 18
        let pillWidth: CGFloat = 380
        let pillHeight: CGFloat = 56
        
        HStack(spacing: 10) {
            Image(systemName: "camera.filters")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [brandViolet, brandPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(text)
                .font(.custom("Fredoka-SemiBold", size: 14))
                .tracking(1.2)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(width: pillWidth, height: pillHeight, alignment: .center)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.25).opacity(0.40))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .compositingGroup()
        .shadow(color: brandViolet.opacity(0.4), radius: 20, x: 0, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}