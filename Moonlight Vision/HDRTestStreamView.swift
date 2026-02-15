//
//  HDRTestStreamView.swift
//  NeoMoonlight - HDR Test Renderer
//
//  Flat 2D RealityKit window with enhanced HDR parameters
//  Matches UIKit behavior: rounded corners, ghosted icons, plain window
//

import SwiftUI
import RealityKit
import simd

// MARK: - HDR Test Wrapper View

struct HDRTestStreamView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Binding var streamConfig: StreamConfiguration?
    
    var body: some View {
        if streamConfig != nil {
            _HDRTestStreamView(
                streamConfig: Binding<StreamConfiguration>(
                    get: { streamConfig ?? StreamConfiguration() },
                    set: { streamConfig = $0 }
                )
            ) {
                dismissWindow(id: "hdrTestWindow")
                streamConfig = nil
            }
        } else {
            ProgressView().onAppear {
                dismissWindow(id: "hdrTestWindow")
            }
        }
    }
}

// MARK: - Main HDR Test View

struct _HDRTestStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    
    @Binding var streamConfig: StreamConfiguration
    let closeAction: () -> Void
    
    @State private var controllerSupport: ControllerSupport?
    @State private var streamMan: StreamManager?
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()
    
    @State private var texture: TextureResource
    @State private var screen: ModelEntity = ModelEntity()
    @State private var videoMode: VideoMode = .standard2D
    @State private var surfaceMaterial: ShaderGraphMaterial?
    
    // NeoMoonlight Custom HDR Settings
    @StateObject private var hdrSettings = HDRTestParams()
    
    @State private var showModeLabel: Bool = false
    @State private var modeLabelTimer: Timer?
    
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    
    var hdrModeName: String {
        switch hdrSettings.mode {
        case 0: return "Power Curve"
        case 1: return "ACES Filmic"
        case 2: return "ACES + Vibrance"
        default: return "Unknown"
        }
    }
    
    var hdrModeIcon: String {
        switch hdrSettings.mode {
        case 0: return "bolt.fill"
        case 1: return "film.fill"
        case 2: return "sparkles"
        default: return "wand.and.stars"
        }
    }
    
    @State private var hideOrnament = false
    @State private var hideTimer: Timer?
    @State private var spatialAudioMode: Bool = true
    @State private var shouldClose: Bool = false
    @State private var controlsHighlighted: Bool = false
    
    var aspectRatio: Float {
        if videoMode == .sideBySide3D && isSBSVideo {
            return Float(streamConfig.height) / Float(streamConfig.width / 2)
        } else {
            return Float(streamConfig.height) / Float(streamConfig.width)
        }
    }
    
    var isSBSVideo: Bool {
        let ratio = Float(streamConfig.width) / Float(streamConfig.height)
        return abs(ratio - (32.0 / 9.0)) < 0.01
    }
    
    init(streamConfig: Binding<StreamConfiguration>, closeAction: @escaping () -> Void) {
        self.closeAction = closeAction
        self._streamConfig = streamConfig
        self.controllerSupport = ControllerSupport(config: streamConfig.wrappedValue, delegate: DummyControllerDelegate())
        
        let bytesPerPixel = 8
        let data = Data(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height))
        
        self.texture = try! TextureResource(
            dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
            format: .raw(pixelFormat: .rgba16Float),
            contents: .init(
                mipmapLevels: [
                    .mip(data: data, bytesPerRow: bytesPerPixel * Int(streamConfig.wrappedValue.width)),
                ]
            )
        )
    }
    
    var body: some View {
        ZStack {
            if viewModel.activelyStreaming {
                GeometryReader3D { proxy in
                    RealityView { content in
                        setupRealityView(content: content)
                    } update: { content in
                        updateRealityView(content: content, proxy: proxy)
                    }
                }
            } else {
                streamStoppedOverlay
            }
        }
        .task {
            await setupMaterial()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .persistentSystemOverlays(hideOrnament ? .hidden : .visible)
        .ornament(visibility: connectionCallbacks.showAlert ? .visible : .hidden, 
                  attachmentAnchor: .scene(.bottomFront), contentAlignment: .bottom) {
            errorOrnament
        }
        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
            VStack {
                controlIcons
                Spacer()
            }
            .padding(.top, 8)
        }
        .onAppear {
            if !viewModel.activelyStreaming {
                print("[HDR Test] Detected appearance without active stream state")
                openWindow(id: "mainView")
                self.closeAction()
            } else {
                startStream()
            }
        }
        .onChange(of: shouldClose) { _, val in
            if val { triggerClose() }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
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
                    // FIXED: Don't dismiss/reopen mainView, just open it once
                    openWindow(id: "mainView")
                    startHideTimer()
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
                .labelStyle(.iconOnly)
                
                // Spatial Audio Toggle
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
                
                // SBS 3D Toggle
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
                    videoMode = videoMode == .standard2D ? .sideBySide3D : .standard2D
                    updateScreenMaterial()
                    startHideTimer()
                } label: {
                    Label(videoMode == .standard2D ? "2D" : "3D",
                          systemImage: videoMode == .standard2D ? "rectangle" : "rectangle.split.2x1")
                }
                .labelStyle(.iconOnly)
                
                // HDR Mode Toggle (NEW)
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
                    // Cycle through modes: 0 → 1 → 2 → 0
                    hdrSettings.mode = (hdrSettings.mode + 1) % 3
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
            }
            .padding()
            .opacity(hideOrnament ? 0.03 : (controlsHighlighted ? 1.0 : 0.5))
            .animation(.easeInOut(duration: 0.3), value: hideOrnament)
            .allowsHitTesting(true)
            
            // HDR Mode Label (appears below icons)
            if showModeLabel {
                VStack {
                    Spacer().frame(height: 70)
                    
                    HStack(spacing: 10) {
                        Image(systemName: hdrModeIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [brandViolet, brandPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(hdrModeName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            // Glow
                            RoundedRectangle(cornerRadius: 12)
                                .fill(brandViolet.opacity(0.3))
                                .blur(radius: 12)
                            
                            // Glass card
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        }
                    )
                    .shadow(color: brandViolet.opacity(0.4), radius: 20, x: 0, y: 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
    
    @ViewBuilder
    var errorOrnament: some View {
        VStack(alignment: .center) {
            Image(systemName: "exclamationmark.triangle")
            Text("Stream Error").font(.title)
            Text(connectionCallbacks.errorMessage ?? "Unknown error")
            Button("Close") {
                viewModel.activelyStreaming = false
                shouldClose.toggle()
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
    
    @ViewBuilder
    var streamStoppedOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text("Stream Stopped").font(.title2)
            Text("The stream has ended or disconnected.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                triggerClose()
            } label: {
                Label("Open Main Menu", systemImage: "house.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .frame(width: 600, height: 400)
        .padding()
        .glassBackgroundEffect()
    }
    
    // MARK: - RealityKit Setup
    
    func setupRealityView(content: RealityViewContent) {
        let planeWidth: Float = 2.0
        let planeHeight: Float = planeWidth * aspectRatio
        let cornerRadius: Float = max(0.01, planeHeight * 0.018)
        let mesh = try! Self.generateRoundedRectPlane(
            width: planeWidth,
            height: planeHeight,
            cornerRadius: cornerRadius,
            resolution: (160, 160)
        )
        
        screen = ModelEntity(mesh: mesh, materials: [])
        
        if videoMode == .sideBySide3D, let material = surfaceMaterial {
            screen.model?.materials = [material]
        } else {
            screen.model?.materials = [UnlitMaterial(texture: self.texture)]
        }
        
        screen.collision = CollisionComponent(
            shapes: [ShapeResource.generateBox(width: 2, height: 2 * aspectRatio, depth: 0.001)],
            mode: .trigger
        )
        screen.components.set(InputTargetComponent())
        
        content.add(screen)

        // Ensure a visible initial scale (avoid zero-size race before first layout)
        screen.transform.scale = .init(repeating: 1.0)
        screen.position = [0, 0, 0]

        // --- Move the ornament bar and controls inline with the screen (not floating in Z) ---
        // Example for a grab bar (replace with your true bar entity if you have one):
        // If you use ornaments, switch to placing the bar as a child:
        // let barEntity = ModelEntity(...) (make bar shape)
        // barEntity.position = [0, -height / 2 - 0.07, 0.001] (just in front of screen)
        // screen.addChild(barEntity)
        // Repeat for icons row: if you can build as ModelEntities, add as children of "screen"

        // If you must use ornaments, tweak their z-position: RealityKit ornaments may support "zOffset" or similar (often undocumented!)
        // Alternatively, after this suggestion let me know your ornament implementation and I can give code to place the controls in the same z-plane as the video.
    }
    
    func updateRealityView(content: RealityViewContent, proxy: GeometryProxy3D) {
        let planeWidth: Float = 2.0
        let planeHeight: Float = planeWidth * aspectRatio
        let cornerRadius: Float = max(0.01, planeHeight * 0.018)
        if let mesh = try? Self.generateRoundedRectPlane(
            width: planeWidth,
            height: planeHeight,
            cornerRadius: cornerRadius,
            resolution: (160, 160)
        ) {
            try? screen.model!.mesh.replace(with: mesh.contents)
        }
        let size = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
        // Guard against zero extents during early layout to prevent invisible screen
        if size.extents.x > 0.001 {
            screen.transform.scale = .init(repeating: size.extents.x / 2)
        }
        // Keep at origin in plain window space
        screen.position = [0, 0, 0]
    }
    
    func updateScreenMaterial() {
        if videoMode == .sideBySide3D, let material = surfaceMaterial {
            screen.model?.materials = [material]
        } else {
            screen.model?.materials = [UnlitMaterial(texture: texture)]
        }
    }
    
    func setupMaterial() async {
        if surfaceMaterial == nil {
            do {
                var material = try await ShaderGraphMaterial(named: "/Root/SBSMaterial", from: "SBSMaterial.usda")
                try material.setParameter(name: "texture", value: .textureResource(self.texture))
                self.surfaceMaterial = material
            } catch {
                print("[HDR Test] Material error: \(error)")
            }
        }
    }
    
    // MARK: - Stream Management
    
    func startStream() {
        dismissWindow(id: "mainView")
        dismissWindow(id: "dummy")
        
        hideOrnament = false
        spatialAudioMode = true
        
        self.streamMan = StreamManager(
            config: self.streamConfig,
            rendererProvider: {
                DrawableVideoDecoder(
                    texture: self.texture,
                    callbacks: self.connectionCallbacks,
                    aspectRatio: Float(self.streamConfig.width) / Float(self.streamConfig.height),
                    useFramePacing: self.streamConfig.useFramePacing,
                    enableHDR: true,
                    hdrSettingsProvider: { [hdrSettings] in
                        return HDRParams(
                            boost: hdrSettings.boost,
                            contrast: hdrSettings.contrast,
                            saturation: hdrSettings.saturation,
                            brightness: 0.0,
                            mode: hdrSettings.mode
                        )
                    },
                    callbackToRender: { texture, correctedResolution in
                        DispatchQueue.main.async {
                            if let correctedResolution = correctedResolution {
                                streamConfig.width = Int32(correctedResolution.0)
                                streamConfig.height = Int32(correctedResolution.1)
                            }
                            self.texture.replace(withDrawables: texture)
                            self.controllerSupport?.connectionEstablished()
                            
                            startHideTimer()
                        }
                    }
                )
            },
            connectionCallbacks: self.connectionCallbacks
        )
        
        let operationQueue = OperationQueue()
        operationQueue.addOperation(streamMan!)

        // Proactively request IDR to ensure the first frame arrives promptly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { LiRequestIdrFrame() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { LiRequestIdrFrame() }
    }
    
    func triggerClose() {
        openWindow(id: "mainView")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.closeAction()
        }
    }
    
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            viewModel.activelyStreaming = false
            streamMan?.stopStream()
            streamMan = nil
            controllerSupport?.cleanup()
            if !shouldClose { openWindow(id: "mainView") }
            self.closeAction()
        default:
            break
        }
    }
    
    func startHideTimer() {
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
    
    func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                controlsHighlighted = false
                hideOrnament = true
            }
        }
    }
    
    // MARK: - Flat Plane Generation
    
    static func generateFlatPlane(
        width: Float,
        aspectRatio: Float,
        resolution: (UInt32, UInt32)
    ) throws -> MeshResource {
        var descr = MeshDescriptor(name: "hdr_test_flat_plane")
        let height = width * aspectRatio
        
        let vertexCount = Int(resolution.0 * resolution.1)
        let triangleCount = Int((resolution.0 - 1) * (resolution.1 - 1) * 2)
        
        var positions: [SIMD3<Float>] = .init(repeating: .zero, count: vertexCount)
        var textureCoordinates: [SIMD2<Float>] = .init(repeating: .zero, count: vertexCount)
        var indices: [UInt32] = .init(repeating: 0, count: triangleCount * 3)
        
        var vertexIndex = 0
        var indicesIndex = 0
        
        for y_v in 0..<resolution.1 {
            let v_geo = Float(y_v) / Float(resolution.1 - 1)
            let yPosition = (0.5 - v_geo) * height
            let v_tex = 1.0 - v_geo
            
            for x_v in 0..<resolution.0 {
                let u = Float(x_v) / Float(resolution.0 - 1)
                let xPosition = (u - 0.5) * width
                let zPosition: Float = 0.0
                
                positions[vertexIndex] = [xPosition, yPosition, zPosition]
                textureCoordinates[vertexIndex] = [u, v_tex]
                
                if x_v < (resolution.0 - 1) && y_v < (resolution.1 - 1) {
                    let current = UInt32(vertexIndex)
                    let nextRow = current + resolution.0
                    indices[indicesIndex...] = [current, nextRow, nextRow+1, current, nextRow+1, current+1]
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

    // MARK: - Rounded Rectangle Plane Mesh Generator

    static func generateRoundedRectPlane(
        width: Float,
        height: Float,
        cornerRadius: Float = 0.08,
        resolution: (UInt32, UInt32) = (100, 100)
    ) throws -> MeshResource {
        var descr = MeshDescriptor(name: "hdr_test_rounded_plane")
        let vertexCount = Int(resolution.0 * resolution.1)
        let triangleCount = Int((resolution.0 - 1) * (resolution.1 - 1) * 2)
        var positions: [SIMD3<Float>] = .init(repeating: .zero, count: vertexCount)
        var textureCoordinates: [SIMD2<Float>] = .init(repeating: .zero, count: vertexCount)
        var indices: [UInt32] = .init(repeating: 0, count: triangleCount * 3)

        let corner = cornerRadius
        let x0 = -width / 2
        let y0 = -height / 2

        var vertexIndex = 0
        var indicesIndex = 0

        for y_v in 0..<resolution.1 {
            let v_frac = Float(y_v) / Float(resolution.1 - 1)
            let y = y0 + v_frac * height

            for x_v in 0..<resolution.0 {
                let u_frac = Float(x_v) / Float(resolution.0 - 1)
                let x = x0 + u_frac * width

                // Rounded mask logic:
                var nx = x, ny = y

                // Corners (avoid sharp corners by moving vertices inward to an arc)
                if x < x0 + corner && y < y0 + corner {
                    let dx = x - (x0 + corner)
                    let dy = y - (y0 + corner)
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist > corner {
                        let scale = corner / dist
                        nx = (x0 + corner) + dx * scale
                        ny = (y0 + corner) + dy * scale
                    }
                } else if x > x0 + width - corner && y < y0 + corner {
                    let dx = x - (x0 + width - corner)
                    let dy = y - (y0 + corner)
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist > corner {
                        let scale = corner / dist
                        nx = (x0 + width - corner) + dx * scale
                        ny = (y0 + corner) + dy * scale
                    }
                } else if x < x0 + corner && y > y0 + height - corner {
                    let dx = x - (x0 + corner)
                    let dy = y - (y0 + height - corner)
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist > corner {
                        let scale = corner / dist
                        nx = (x0 + corner) + dx * scale
                        ny = (y0 + height - corner) + dy * scale
                    }
                } else if x > x0 + width - corner && y > y0 + height - corner {
                    let dx = x - (x0 + width - corner)
                    let dy = y - (y0 + height - corner)
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist > corner {
                        let scale = corner / dist
                        nx = (x0 + width - corner) + dx * scale
                        ny = (y0 + height - corner) + dy * scale
                    }
                }

                positions[vertexIndex] = [nx, ny, 0]
                textureCoordinates[vertexIndex] = [u_frac, 1.0 - v_frac]

                if x_v < (resolution.0 - 1) && y_v < (resolution.1 - 1) {
                    let current = UInt32(vertexIndex)
                    let nextRow = current + resolution.0
                    indices[indicesIndex...] = [current, nextRow, nextRow+1, current, nextRow+1, current+1]
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
}

final class HDRTestParams: ObservableObject {
    @Published var boost: Float = 1.0
    @Published var contrast: Float = 1.0
    @Published var saturation: Float = 1.0
    @Published var mode: Int32 = 1
}
