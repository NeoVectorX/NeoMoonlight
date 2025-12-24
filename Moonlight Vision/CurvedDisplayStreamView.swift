import SwiftUI
import RealityKit
import simd
import GameController
import ARKit
import UIKit
import AVFoundation
import QuartzCore
import ImageIO

// Existing code...

final class ThreadSafeHDRSettings: @unchecked Sendable {
    private var params: HDRParams
    private let lock = NSLock()
    init(params: HDRParams) { self.params = params }
    var value: HDRParams {
        get { lock.lock(); defer { lock.unlock() }; return params }
        set { lock.lock(); defer { lock.unlock() }; params = newValue }
    }
}

struct InputCaptureView: UIViewRepresentable {
    let controllerSupport: ControllerSupport
    @Binding var showKeyboard: Bool
    var curvature: Float
    var streamConfig: StreamConfiguration
    
    func makeUIView(context: Context) -> InputCaptureUIView {
        let view = InputCaptureUIView()
        view.curvature = curvature
        view.controllerSupport = controllerSupport
        view.streamConfig = streamConfig
        
        view.isMultipleTouchEnabled = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        
        return view
    }
    
    func updateUIView(_ uiView: InputCaptureUIView, context: Context) {
        uiView.curvature = curvature
        uiView.streamConfig = streamConfig
        
        if showKeyboard && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !showKeyboard && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}

class InputCaptureUIView: UIView, UIKeyInput {
    var controllerSupport: ControllerSupport?
    var curvature: Float = 0.0
    var streamConfig: StreamConfiguration?
    
    private let maxCurveAngle: Float = 1.3
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }
    
    private func setupGestures() {
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        self.addGestureRecognizer(hover)
        
        DispatchQueue.main.async {
            self.controllerSupport?.attachGCEventInteraction(to: self)
        }
    }
    
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        let location = gesture.location(in: self)
        sendMousePosition(x: location.x, y: location.y)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let loc = touch.location(in: self)
            sendMousePosition(x: loc.x, y: loc.y)
        }
        NotificationCenter.default.post(name: .curvedScreenWakeRequested, object: nil)

        LiSendMouseButtonEvent(0, 1)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let loc = touch.location(in: self)
            sendMousePosition(x: loc.x, y: loc.y)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        LiSendMouseButtonEvent(1, 1)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        LiSendMouseButtonEvent(1, 1)
    }
    
    private func sendMousePosition(x: CGFloat, y: CGFloat) {
        guard let config = streamConfig else { return }
        
        var finalX = x
        
        let c = max(0.0, min(curvature, 1.0))
        if c > 0.001 {
            let width = bounds.width
            let normalizedX = x / width
            let relativeX = normalizedX - 0.5
            
            let angle = maxCurveAngle * c
            let sinTheta = Float(relativeX) * 2.0 * sin(angle / 2.0)
            let clampedSin = max(-1.0, min(1.0, sinTheta))
            let theta = asin(clampedSin)
            
            let u = (theta / angle) + 0.5
            finalX = CGFloat(u) * width
        }
        
        let streamWidth = CGFloat(config.width)
        let streamHeight = CGFloat(config.height)
        
        let hostX = (finalX / bounds.width) * streamWidth
        let hostY = (y / bounds.height) * streamHeight
        
        let clampedX = min(max(hostX, 0), streamWidth)
        let clampedY = min(max(hostY, 0), streamHeight)
        
        let clampedXInt16 = Int16(clampedX)
        let clampedYInt16 = Int16(clampedY)
        let streamWidthInt16 = Int16(streamWidth)
        let streamHeightInt16 = Int16(streamHeight)
        
        LiSendMousePositionEvent(clampedXInt16, clampedYInt16, streamWidthInt16, streamHeightInt16)
    }
    
    override var canBecomeFocused: Bool { true }
    var hasText: Bool { true }
    
    func insertText(_ text: String) {
        let cString = text.cString(using: .utf8)
        cString?.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                LiSendUtf8TextEvent(base, UInt32(text.utf8.count))
            }
        }
    }
    
    func deleteBackward() {
        LiSendKeyboardEvent(0x08, 0x03, 0)
        usleep(50 * 1000)
        LiSendKeyboardEvent(0x08, 0x04, 0)
    }
}

let CURVED_MAX_WIDTH_METERS: Float = 2.0
let CURVED_MAX_ANGLE: Float = 1.3

extension CollisionGroup {
    static let screenEntity = CollisionGroup(rawValue: 1 << 0)
    static let uiElements = CollisionGroup(rawValue: 1 << 1)
}

enum CurvaturePreset: Int, CaseIterable {
    case flat = 0
    case curved = 1
    case immersive = 2
    case extreme = 3
    
    var value: Float {
        switch self {
        case .flat: return 0.0
        case .curved: return 0.4
        case .immersive: return 0.8
        case .extreme: return 1.0
        }
    }
    
    var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .curved: return "1800R"
        case .immersive: return "1000R"
        case .extreme: return "800R"
        }
    }
    
    var icon: String { "pano.fill" }
    
    func next() -> CurvaturePreset {
        let allCases = CurvaturePreset.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        return allCases[(currentIndex + 1) % allCases.count]
    }
}

struct CurvedDisplayStreamView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @EnvironmentObject private var viewModel: MainViewModel
    @Binding var streamConfig: StreamConfiguration?
    var needsHdr: Bool
    
    var body: some View {
        if let config = streamConfig {
            _CurvedDisplayStreamView(
                streamConfig: Binding<StreamConfiguration>(
                    get: { config },
                    set: { streamConfig = $0 }
                ),
                needsHdr: needsHdr,
                swapAction: {
                    Task {
                        await viewModel.performRendererSwap(
                            openWindow: openWindow,
                            openImmersiveSpace: openImmersiveSpace,
                            dismissWindow: dismissWindow,
                            dismissImmersiveSpace: dismissImmersiveSpace
                        )
                    }
                }
            )
        } else {
            Color.clear
        }
    }
}

struct _CurvedDisplayStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    @Binding var streamConfig: StreamConfiguration
    var needsHdr: Bool
    let swapAction: () -> Void
    
    @State private var streamMan: StreamManager?
    @State private var controllerSupport: ControllerSupport?
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()
    
    @State private var texture: TextureResource
    @State private var screen: ModelEntity = ModelEntity()
    @State private var videoMode: VideoMode = .standard2D
    @State private var surfaceMaterial: ShaderGraphMaterial?
    
    @State private var curveAnimationMultiplier: Float = 1.0
    @State private var animationTimer: Timer?
    
    @State private var curvaturePreset: CurvaturePreset = .curved
    @State private var tiltAngle: Float = 0.0
    @State private var tiltDirection: Int = 1
    
    @State private var screenPosition: SIMD3<Float> = SIMD3<Float>(0, 1.1, -2.0)
    @State private var screenScale: Float = 1.8
    @State private var isLocked: Bool = false
    @State private var startDragPosition: SIMD3<Float>? = nil
    @State private var hasInitializedPosition = false
    
    @State private var safeHDRSettings = ThreadSafeHDRSettings(
        params: HDRParams(boost: 1.0, contrast: 1.0, saturation: 1.0, brightness: 0.0, mode: 0)
    )
    @StateObject private var hdrParams = HDRTestParams()
    
    @State private var showVirtualKeyboard = false
    @State private var hideControls: Bool = false
    @State private var hideTimer: Timer?
    @State private var controlsEntity: Entity?
    @State private var shouldClose = false
    @State private var hasPerformedTeardown = false
    @State private var needsResume = false
    @State private var spatialAudioMode: Bool = true
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?
    @State private var showScaleHUD: Bool = false
    @State private var showModeLabel: Bool = false
    @State private var modeLabelTimer: Timer?
    @State private var controlsHighlighted: Bool = false
    @State private var immersiveSpaceSceneID: String?
    @State private var theaterEnvironmentEnabled = false
    @State private var showMenuPanel = false
    @State private var menuEntity: Entity?
    @State private var menuScaleInitialized = false
    @State private var menuBaseWidth: Float = 0
    @State private var inputScaleInitialized = false
    @State private var inputBaseWidth: Float = 0
    @State private var swapInProgress = false
    @State private var menuPanelInstanceID = UUID()
    @State private var showSwapOverlay = false
    @State private var showSwapConfirm = false
    @State private var show3DConfirm = false
    
    @State private var renderGateOpen: Bool = true
    
    // Stats attachment sizing in meters (fixed width target)
    @State private var statsScaleInitialized = false
    @State private var statsBaseWidth: Float = 0
    private let statsCardWidthMeters: Float = 0.55
    
    @State private var tutorialScaleInitialized = false
    @State private var tutorialBaseWidth: Float = 0
    private let tutorialCardWidthMeters: Float = 1.110
    
    @State private var showCurvedTutorial = false
    @State private var gestureInitialScale: Float? = nil
    @State private var targetScale: Float = 1.8
    @State private var scaleHUDFadeTimer: Timer?
    
    @State private var dimmerDome: ModelEntity?
    @State private var dimmerDomePurple: ModelEntity?
    @State private var purpleGradientTextureColors: TextureResource?
    @State private var purpleGradientTexturePurpleBlack: TextureResource?
    @State private var eclipseGradientTexture: TextureResource?
    @State private var twilightGradientTexture: TextureResource?
    @State private var dawnGradientTexture: TextureResource?
    @State private var sunriseGradientTexture: TextureResource?
    @State private var woodlandGradientTexture: TextureResource?
    @State private var desertGradientTexture: TextureResource?
    @State private var duskHDRTexture: TextureResource?
    @State private var moonlightCycleTimer: Timer?
    @State private var moonlightCyclePhase: CGFloat = 0.0
    private let dimAlphas: [CGFloat] = [0.0, 0.82]
    @State private var dimLevel: Int = 0
    @State private var environmentSphereLevel: Int = 0
    @State private var environmentUSDZLevel: Int = 0
    @State private var moonlightMaterial: UnlitMaterial?
    @State private var lastMoonlightAppliedRGB: SIMD3<Float> = .zero
    @State private var lastMoonlightUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private let moonlightCycleDurationLowPower: CGFloat = 22.0
    private let moonlightUpdateIntervalLowPower: TimeInterval = 0.22
    private let moonlightColorDeltaThresholdLowPower: Float = 0.03
    private let moonlightAlphaLowPower: CGFloat = 0.78
    
    @State private var lastEnvironmentSphereLevelApplied: Int = 0
    
    @State private var modeBannerText: String = ""
    @State private var modeBannerIcon: String = "slider.horizontal.3"
    
    @State private var showInlinePresetOverlay: Bool = false
    @State private var presetOverlayText: String = ""
    @State private var presetOverlayIcon: String = "camera.filters"
    @State private var presetOverlayTimer: Timer?
    
    @State private var isHDRTexture: Bool = false
    
    @State private var currentAmbientColor: UIColor = .black
    
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    
    @State private var isMenuOpen: Bool = false
    
    @State private var isMenuOpen1: Bool = false
    
    @State private var environmentDome: ModelEntity?
    @State private var usdzAboveTheClouds: Entity?
    @State private var usdzAnime: Entity?
    @State private var usdzJustSky: Entity?
    @State private var usdzNightTime: Entity?
    @State private var jpgAboveTheCloudsTexture: TextureResource?
    @State private var jpgAnimeTexture: TextureResource?
    @State private var jpgJustSkyTexture: TextureResource?
    @State private var jpgNightTimeTexture: TextureResource?
    @State private var jpgTest1Texture: TextureResource?
    @State private var jpgTest2Texture: TextureResource?
    @State private var jpgTest3Texture: TextureResource?
    @State private var extraSkyboxTextures: [TextureResource] = []
    @State private var extraSkyboxNames: [String] = []
    
    @State private var builtinSkyboxNames: [String] = [
        "2", "13", "15", "23", "i", "11", "5", "16", 
        "22", "f", "a", "25", "17", "d", "t", "21", "8", "7", "1", 
        "26", "3"
    ]
    @State private var builtinSkyboxTextures: [String: TextureResource] = [:]
    @State private var skyboxRotations: [String: Float] = [
        "3": Float(530.0 * .pi / 180.0),
        "5": -2.478,
        "8": Float(115.0 * .pi / 180.0),
        "11": 0.175,
        "15": -0.105,
        "16": Float(-50.0 * .pi / 180.0),
        "17": 1.867,
        "21": -1.921,
        "23": -2.007,
        "26": -0.524,
        "a": Float(150.0 * .pi / 180.0),
        "b": Float(145.0 * .pi / 180.0),
        "c": Float(125.0 * .pi / 180.0),
        "d": Float(-280.0 * .pi / 180.0),
        "f": Float(5.0 * .pi / 180.0),
        "i": Float(-90.0 * .pi / 180.0),
        "w": Float(-160.0 * .pi / 180.0),
        "y": Float(-15.0 * .pi / 180.0)
    ]
    
    @State private var skyboxDisplayNames: [String: String] = [
        "1": "Loft",
        "2": "Moonlight",
        "3": "Full Moon",
        "5": "Moondaze",
        "7": "Trackday",
        "8": "Atlantis",
        "11": "Inked",
        "13": "Jungle",
        "15": "Monolith",
        "16": "Meadow",
        "17": "Fireflies",
        "21": "Reach",
        "22": "Mistfire",
        "23": "Apocalypse",
        "25": "Rubble",
        "26": "Zenith",
        "a": "Metro",
        "b": "Stalked",
        "c": "Stalked",
        "d": "Stalked",
        "f": "Foundry",
        "i": "Station",
        "t": "Moonrise",
        "w": "NeoCity",
        "x": "Outpost",
        "y": "Outpost"
    ]

    @State private var newsetSkyboxNames: [String] = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
        "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
        "u", "v", "w", "x", "y", "z"
    ]
    @State private var newsetSkyboxTextures: [String: TextureResource] = [:]
    @State private var newsetLevel: Int = 0
    @State private var newsetSkyboxRotations: [String: Float] = [
        "a": Float(150.0 * .pi / 180.0),
        "b": Float(180.0 * .pi / 180.0),
        "c": Float(15.0 * .pi / 180.0),
        "d": Float(-160.0 * .pi / 180.0),
        "e": Float(-90.0 * .pi / 180.0),
        "f": Float(5.0 * .pi / 180.0),
        "g": Float(-100.0 * .pi / 180.0),
        "h": Float(-100.0 * .pi / 180.0),
        "i": Float(-90.0 * .pi / 180.0),
        "j": Float(-10.0 * .pi / 180.0),
        "k": Float(115.0 * .pi / 180.0),
        "l": Float(-50.0 * .pi / 180.0),
        "n": Float(30.0 * .pi / 180.0),
        "u": Float(180.0 * .pi / 180.0),
        "z": Float(20.0 * .pi / 180.0)
    ]
    
    var isSBSVideo: Bool {
        let ratio = Float(streamConfig.width) / Float(streamConfig.height)
        return abs(ratio - (32.0 / 9.0)) < 0.01
    }

    var allowedScaleMax: Float { 6.0 }
    var cornerRadiusFraction: Float { 0.018 }
    var swapCardWidthMeters: Float { 0.55 }
    
    var screenAspect: Float {
        if let (w, h) = correctedResolution {
            if videoMode == .sideBySide3D, abs(Float(w) / Float(h) - (32.0 / 9.0)) < 0.01 {
                return Float(h) / Float(w / 2)
            } else {
                return Float(h) / Float(w)
            }
        } else {
            if videoMode == .sideBySide3D && isSBSVideo {
                return Float(streamConfig.height) / Float(streamConfig.width / 2)
            } else {
                return Float(streamConfig.height) / Float(streamConfig.width)
            }
        }
    }

    @State private var correctedResolution: (Int, Int)? = nil

    var body: some View {
        let baseView = mainContent
            .overlay(alignment: .bottom) { scaleHUDOverlay }
            .overlay { swapOverlay }
            .overlay { swapConfirmAttachment }
            .overlay { sbsConfirmAttachment }
        
        let lifecycleApplied = baseView
            .task { await setupMaterial() }
            .onAppear(perform: setupScene)
            .onDisappear(perform: teardownScene)
            .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
                if shouldClose && !hasPerformedTeardown {
                    triggerCloseSequence()
                }
            }
            .onChange(of: scenePhase) { oldValue, newValue in handleScenePhaseChange(oldValue: oldValue, newValue: newValue) }
            .onReceive(NotificationCenter.default.publisher(for: .curvedScreenWakeRequested)) { _ in
                guard viewModel.activelyStreaming && !showMenuPanel && !showSwapConfirm && !showCurvedTutorial else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                fixAudioForCurrentMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mainViewWindowClosed)) { _ in
                self.handleWindowClose()
            }
            .onReceive(NotificationCenter.default.publisher(for: .forceStopRendering)) { _ in
                self.renderGateOpen = false
            }
        
        let stateChangesApplied = lifecycleApplied
            .onChange(of: viewModel.streamSettings.statsOverlay) { oldValue, newValue in 
                handleStatsOverlay(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: viewModel.activelyStreaming) { oldValue, newValue in 
                handleActiveStreaming(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: videoMode) { _, _ in updateScreenMaterial() }
            .onChange(of: showMenuPanel) { _, _ in updateScreenInteractivity() }
            .onChange(of: showSwapConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: show3DConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: hideControls) { _, _ in updateScreenInteractivity() }
        
        return stateChangesApplied
    }
    
    // MARK: - Body Subviews

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader3D { proxy in
            ZStack {
                makeRealityView(proxy: proxy)
                controlsHint
            }
        }
    }

    @ViewBuilder
    private var scaleHUD: some View {
        Text(String(format: "%.2fx", targetScale))
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.7))
            )
            .padding(.bottom, 30)
    }

    @ViewBuilder
    private var scaleHUDOverlay: some View {
        if showScaleHUD {
            scaleHUD
                .transition(.opacity)
                .zIndex(1200)
        }
    }
    
    @ViewBuilder
    private var controlsHint: some View {
        if hideControls {
            VStack {
                 HStack {
                    Spacer()
                    Text("Tap to reveal controls, tap again to select")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(8)
                        .background(.black.opacity(0.3))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 40)
                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    func makeRealityView(proxy: GeometryProxy3D) -> some View {
        RealityView { content, attachments in
            setupDimmerDomes(content: content)
            setupEnvironment360(content: content)
            setupRealityView(content: content, attachments: attachments)
        } update: { content, attachments in
            updateDimmerDomes(content: content)
            updateEnvironment360(content: content)
            updateRealityView(content: content, attachments: attachments)
        } attachments: {
            Attachment(id: "controls") { topControlsBar }
            Attachment(id: "inputOverlay") { inputCaptureAttachment }
            Attachment(id: "swapConfirm") { swapConfirmAttachment }
            Attachment(id: "sbsConfirm") { sbsConfirmAttachment }
            Attachment(id: "stats") { statsAttachment }
            Attachment(id: "tutorial") { tutorialAttachment }
            Attachment(id: "presetPopup") {
                CenterPresetPopup(text: presetOverlayText, icon: presetOverlayIcon)
                    .opacity(showInlinePresetOverlay ? 1.0 : 0.0)
            }
        }
        .gesture(dragGesture)
        .gesture(magnifyGesture)
        .onTapGesture {
            guard viewModel.activelyStreaming && !showMenuPanel && !showSwapConfirm && !showCurvedTutorial else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                hideControls = false
                controlsHighlighted = true
            }
            startHighlightTimer()
            if self.spatialAudioMode {
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            } else {
                AudioHelpers.fixAudioForDirectStereo()
            }
        }
    }

    @ViewBuilder
    private var swapOverlay: some View {
        if showSwapOverlay {
            ZStack {
                brandViolet.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(brandViolet)
                    Text("Switching Display Mode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(20)
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
            }
            .transition(.opacity)
            .zIndex(2000)
        }
    }

    @ViewBuilder
    private var swapConfirmAttachment: some View {
        if showSwapConfirm {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandViolet, brandPurple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: brandViolet.opacity(0.4), radius: 12, x: 0, y: 8)
                    Image(systemName: "rectangle.2.swap")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Swap Display Mode")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("This will stop the current stream and reconnect in the Standard Display.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 12) {
                    Button {
                        showSwapConfirm = false
                        showSwapOverlay = true
                        swapAction()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.2.swap")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Swap to Standard Display")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [brandViolet, brandPurple.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.35), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: brandViolet.opacity(0.35), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSwapConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 16)
            .frame(width: 420)
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var sbsConfirmAttachment: some View {
        if show3DConfirm {
            let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
            let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
            let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandNavy, brandNavy.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: brandOrange.opacity(0.5), radius: 18, x: 0, y: 10)
                    Image(systemName: "view.3d")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Enable SBS 3D")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Use software such as ReShade + Depth3D on your host PC to utilize SBS mode.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 12) {
                    Button {
                        show3DConfirm = false
                        videoMode = .sideBySide3D
                        updateScreenMaterial()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Enable SBS 3D")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [brandOrange, brandOrange.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: brandOrange.opacity(0.5), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        show3DConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(brandNavy.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 16)
            .frame(width: 420)
            .allowsHitTesting(true)
        }
    }

    // MARK: - Scene Setup & Teardown

    private func setupScene() {
        if !viewModel.activelyStreaming {
            Task { @MainActor in
                viewModel.userDidRequestDisconnect()
                await dismissImmersiveSpace()
            }
            return
        }
        
        // Add: Re-open render gate at setup to ensure frames are not dropped
        self.renderGateOpen = true
        
        dismissWindow(id: "mainView")
        dismissWindow(id: "dummy")
        
        isMenuOpen = false
        
        viewModel.streamSettings.statsOverlay = false
        statsTimer?.invalidate()
        statsTimer = nil
        statsOverlayText = ""
        
        dimLevel = 0
        viewModel.streamSettings.dimPassthrough = false
        
        self.targetScale = self.screenScale
        
        startStreamIfNeeded()
        spatialAudioMode = true

        let hasSeen = UserDefaults.standard.bool(forKey: tutorialSeenKey)
        if !hasSeen {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                showCurvedTutorial = true
            }
            UserDefaults.standard.set(true, forKey: tutorialSeenKey)
        }
        
        if needsHdr {
            hdrParams.mode = 1
            safeHDRSettings.value = HDRParams(
                boost: 1.35,
                contrast: 1.1,
                saturation: 1.08,
                brightness: 0.0,
                mode: 1
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { LiRequestIdrFrame() }
            startHideTimer()
        }
        
        if let sceneID = UIApplication.shared.connectedScenes.first?.session.persistentIdentifier {
            self.immersiveSpaceSceneID = sceneID
        }
        
        restoreSavedTransform()
        self.isLocked = UserDefaults.standard.bool(forKey: kCurvedLockedKey)
        
        hideTimer?.invalidate()
        hideTimer = nil
        hideControls = false
        
        openedMainAfterDisconnect = false
        
        if viewModel.streamSettings.uikitPreset != 0 {
            viewModel.streamSettings.uikitPreset = 0
        }
        applyCurvedUIKitPreset(0)

        // Setup environment
        environmentSphereLevel = 0
    }
    
    private func teardownScene() {
        statsTimer?.invalidate()
        statsTimer = nil
        stopMoonlightCycle()
        
        if !hasPerformedTeardown {
            performCompleteTeardown()
        }
        saveCurrentTransform()
    }
    
    // MARK: - onChange Handlers

    private func handleScenePhaseChange(oldValue: ScenePhase, newValue: ScenePhase) {
        handleScenePhaseChange(newValue)
        if newValue == .active && viewModel.activelyStreaming {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                fixAudioForCurrentMode()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refreshAfterResume() }
        } else if newValue == .background && viewModel.activelyStreaming {
            viewModel.userDidRequestDisconnect()
        }
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            viewModel.activelyStreaming = false
            streamMan?.stopStream()
            streamMan = nil
            controllerSupport?.cleanup()
        default:
            break
        }
    }
    
    private func handleStatsOverlay(oldValue: Bool, newValue: Bool) {
        if newValue { startStatsTimer() } else { statsTimer?.invalidate(); statsTimer = nil; statsOverlayText = "" }
    }

    private func handleActiveStreaming(oldValue: Bool, newValue: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            showMenuPanel = false
        }
        if newValue {
            ensureStreamStartedIfNeeded()
            dismissWindow(id: "mainView")
            let hasSeen = UserDefaults.standard.bool(forKey: tutorialSeenKey)
            if !hasSeen {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    showCurvedTutorial = true
                }
                UserDefaults.standard.set(true, forKey: tutorialSeenKey)
            }
        }
    }

    private func handleStreamState(oldValue: StreamLifecycleState, newValue: StreamLifecycleState) {
        if newValue == .starting {
            ensureStreamStartedIfNeeded()
        } else if(newValue == .idle) {
            self.shouldClose = false
        }
    }
    
    // MARK: - Gestures

    var dragGesture: some Gesture {
        DragGesture()
            .targetedToEntity(screen)
            .onChanged { value in
                guard !isLocked && !hideControls else { return }
                hideTimer?.invalidate()
                if startDragPosition == nil { startDragPosition = screenPosition }
                let translation = value.convert(value.translation3D, from: .local, to: .scene)
                var proposed = startDragPosition! + simd_float3(translation.x, translation.y, translation.z)
                proposed.x = min(max(proposed.x, -allowedLateralMax), allowedLateralMax)
                screenPosition = proposed
                lastDragTime = CACurrentMediaTime()
            }
            .onEnded { _ in
                startDragPosition = nil
                startHideTimer()
            }
    }
    
    var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(screen)
            .onChanged { value in
                guard !isLocked && !hideControls else { return }
                hideTimer?.invalidate()
                if gestureInitialScale == nil {
                    gestureInitialScale = screenScale
                    showScaleHUD = true
                }
                let base = gestureInitialScale ?? screenScale
                var proposed = base * Float(value.magnification)
                proposed = min(max(proposed, 0.5), allowedScaleMax)
                targetScale = proposed
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.85)) {
                    screenScale = targetScale
                }

                scaleHUDFadeTimer?.invalidate()
                scaleHUDFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        showScaleHUD = false
                    }
                }
            }
            .onEnded { _ in
                gestureInitialScale = nil
                scaleHUDFadeTimer?.invalidate()
                scaleHUDFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        showScaleHUD = false
                    }
                }
                startHideTimer()
            }
    }

    @State private var headAnchor: AnchorEntity?
    @State private var lastHeadWorldPos: SIMD3<Float> = .zero
    @State private var lastDragTime: CFTimeInterval = 0

    private let allowedLateralMax: Float = 3.0
    
    // MARK: - RealityView Attachments

    @ViewBuilder
    private var inputCaptureAttachment: some View {
        if let support = controllerSupport {
            InputCaptureView(
                controllerSupport: support,
                showKeyboard: $showVirtualKeyboard,
                curvature: curvaturePreset.value * curveAnimationMultiplier,
                streamConfig: streamConfig
            )
            .frame(width: 1920, height: 1920 / CGFloat(screenAspect))
            .opacity(0.01)
            .allowsHitTesting(viewModel.activelyStreaming && !showMenuPanel && hideControls && !isMenuOpen && !showCurvedTutorial)
        }
    }

    @ViewBuilder
    private var statsAttachment: some View {
        VStack(spacing: 6) {
            Text(statsOverlayText.isEmpty ? "Collecting stats..." : statsOverlayText)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.5))
        )
        .opacity(viewModel.streamSettings.statsOverlay ? 1 : 0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var tutorialAttachment: some View {
        if showCurvedTutorial {
            CurvedDisplayTutorialView(isPresented: $showCurvedTutorial)
                .frame(depth: 100)
                .allowsHitTesting(true)
        } else {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    var topControlsBar: some View {
        HStack(spacing: 16) {
            // 1. Home
            makeControlButton(label: "Home", systemImage: "house.fill") {
                if isMenuOpen {
                    dismissWindow(id: "mainView")
                    isMenuOpen = false
                } else {
                    pushWindow(id: "mainView")
                    isMenuOpen = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        positionMenuWindow()
                    }
                }
                
                guard viewModel.activelyStreaming && !showMenuPanel else { return }
                
                if hideControls {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideControls = false
                        controlsHighlighted = true
                    }
                    startHighlightTimer()
                    if self.spatialAudioMode {
                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                    } else {
                        AudioHelpers.fixAudioForDirectStereo()
                    }
                }
                
                if self.spatialAudioMode {
                    AudioHelpers.fixAudioForSurroundForCurrentWindow()
                } else {
                    AudioHelpers.fixAudioForDirectStereo()
                }
            }

            // 2. Spatial Audio
            makeControlButton(label: spatialAudioMode ? "Spatial Audio" : "Direct Audio", systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones") {
                spatialAudioMode.toggle()
                fixAudioForCurrentMode()
            }

            // 3. Curvature
            makeControlButton(label: curvaturePreset.displayName, systemImage: curvaturePreset.icon) {
                curvaturePreset = curvaturePreset.next()
                presetOverlayText = curvaturePreset.displayName
                presetOverlayIcon = curvaturePreset.icon
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                startHideTimer()
            }

            // 4. Tilt
            makeControlButton(label: "\(Int(tiltAngle))°", systemImage: "bed.double.fill") {
                cycleTiltAngle()
                presetOverlayText = "\(Int(tiltAngle))°"
                presetOverlayIcon = "bed.double.fill"
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                startHideTimer()
            }

            // 5. Dim
            makeControlButton(label: dimButtonTitle, systemImage: dimButtonIcon) {
                if dimInteractionLocked { return }
                dimInteractionLocked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    dimInteractionLocked = false
                }

                if environmentSphereLevel != 0 || environmentUSDZLevel != 0 {
                    environmentSphereLevel = 0
                    environmentUSDZLevel = 0
                    updateEnvironmentState()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.streamSettings.dimPassthrough = false
                    }
                }

                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    let newLevel = nextDimLevel(from: dimLevel)
                    dimLevel = newLevel
                    viewModel.streamSettings.dimPassthrough = (newLevel == 1)
                    updateDimmerDomesState()
                }

                if dimLevel == 11 { startMoonlightCycle() } else { stopMoonlightCycle() }
                
                presetOverlayText = dimButtonTitle
                presetOverlayIcon = dimButtonIcon
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
            }

            // 6. Preset
            makeControlButton(label: "Preset", systemImage: "camera.filters") {
                let allowed: [Int32] = [0, 1, 2, 3]
                let cur = viewModel.streamSettings.uikitPreset
                let idx = allowed.firstIndex(of: cur) ?? 0
                let next = allowed[(idx + 1) % allowed.count]
                viewModel.streamSettings.uikitPreset = next
                presetOverlayText = "Preset: \(presetName(for: next))"
                presetOverlayIcon = "camera.filters"
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                startHideTimer()
            }

            // 7. 3D
            makeControlButton(label: videoMode == .standard2D ? "Standard Display" : "3D", systemImage: "view.3d") {
                if videoMode == .standard2D {
                    show3DConfirm = true
                } else {
                    videoMode = .standard2D
                    updateScreenMaterial()
                }
            }

            // 8. Sphere Environment (360 JPEGs)
            makeControlButton(label: environmentSphereButtonTitle, systemImage: "photo") {
                environmentSphereLevel = nextEnvironmentLevel(from: environmentSphereLevel)
                dimLevel = 0
                environmentUSDZLevel = 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.streamSettings.dimPassthrough = (environmentSphereLevel != 0)
                }
                stopMoonlightCycle()
                updateEnvironmentState()

                updateDimmerDomesState()

                presetOverlayText = environmentSphereButtonTitle
                presetOverlayIcon = "photo"
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                startHideTimer()
            }

            // 9. Stats
            makeControlButton(label: viewModel.streamSettings.statsOverlay ? "Hide Stats" : "Show Stats", systemImage: "wifi") {
                viewModel.streamSettings.statsOverlay.toggle()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.001))
        .opacity(!hideControls ? (controlsHighlighted ? 1.0 : 0.5) : 0.05)
        .conditionalGlass(!hideControls)
        .animation(.easeInOut(duration: 0.25), value: controlsHighlighted)
        .animation(.easeInOut(duration: 0.25), value: hideControls)
        .allowsHitTesting(true)
    }
    
    private func makeControlButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            if !controlsHighlighted {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            controlsHighlighted = false
            hideControls = false
            action()
            startHideTimer()
        } label: {
            Label(label, systemImage: systemImage)
                .font(.system(size: 24.07))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 50, height: 50)
        }
        .labelStyle(.iconOnly)
    }
    
    @State private var dimInteractionLocked: Bool = false
    
    private var dimButtonTitle: String {
        switch dimLevel {
        case 0: "Off"
        case 1: "Night"
        case 2: "Eclipse"
        case 4: "Midnight"
        case 5: "Twilight"
        case 6: "Dawn"
        case 7: "Sunrise"
        case 8: "Woodland"
        case 9: "Desert"
        case 10: "Dusk"
        case 12: "Reactive"
        default: "Off"
        }
    }

    private var dimButtonIcon: String {
        (dimLevel == 0) ? "moon" : "moon.fill"
    }
    
    private var environmentSphereButtonTitle: String {
        if environmentSphereLevel == 0 { return "Environment Off" }
        let builtinNames = builtinSkyboxNames
        let idx = environmentSphereLevel - 1
        if idx < builtinNames.count {
            let id = builtinNames[idx]
            return skyboxDisplayNames[id] ?? id.uppercased()
        }
        let extraIdx = idx - builtinNames.count
        if extraIdx >= 0 && extraIdx < extraSkyboxNames.count {
            return extraSkyboxNames[extraIdx]
        }
        return "Environment Off"
    }

    private var environmentSphereButtonIcon: String {
        "photo"
    }
    
    private var newsetButtonTitle: String {
        if newsetLevel == 0 { return "Newset Off" }
        let idx = newsetLevel - 1
        let newsetNames = newsetSkyboxNames
        let name = newsetNames[idx]
        return name.uppercased()
    }

    private func nextNewsetLevel(from current: Int) -> Int {
        let total = newsetSkyboxNames.count
        if total <= 0 { return 0 }
        if current >= total { return 0 }
        return current + 1
    }

    private func nextEnvironmentLevel(from current: Int) -> Int {
        let total = builtinSkyboxNames.count + extraSkyboxNames.count
        if total <= 0 { return 0 }
        if current >= total { return 0 }
        return current + 1
    }
    
    private func nextDimLevel(from current: Int) -> Int {
        let order = [0, 1, 2, 4, 5, 6, 7, 8, 9]
        if let idx = order.firstIndex(of: current) {
            return order[(idx + 1) % order.count]
        }
        return 0
    }

    private func positionMenuWindow() {
        guard let menuScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { scene in
                scene.windows.contains(where: { window in
                    window.isKeyWindow || window.rootViewController != nil
                })
            }) else {
            return
        }
        
        let geometryRequest = UIWindowScene.GeometryPreferences.Vision(
            size: CGSize(width: 700, height: 920),
            resizingRestrictions: .none
        )
        
        menuScene.requestGeometryUpdate(geometryRequest)
    }

    private func refreshAfterResume() {
        LiRequestIdrFrame()
        rebindScreenMaterial()
    }
    
    private func rebindScreenMaterial() {
        if videoMode == .sideBySide3D {
            if var mat = surfaceMaterial {
                try? mat.setParameter(name: "texture", value: .textureResource(self.texture))
                surfaceMaterial = mat
                screen.model?.materials = [mat]
            } else {
                screen.model?.materials = [UnlitMaterial(texture: texture)]
            }
        } else {
            screen.model?.materials = [UnlitMaterial(texture: self.texture)]
        }
    }

    private func showDimPresetOverlay() {
        presetOverlayText = dimButtonTitle
        presetOverlayIcon = dimButtonIcon
        showInlinePresetOverlay = true
        
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
        }
    }

    // MARK: - HDR & Material

    private func applyCurvedUIKitPreset(_ preset: Int32) {
        var params = safeHDRSettings.value

        if viewModel.streamSettings.enableHdr {
            switch preset {
            case 1:
                hdrParams.mode = 1
                params.boost = 1.0
                params.saturation = 0.95
                params.contrast = 1.15
                params.brightness = 0.0
            case 2:
                hdrParams.mode = 1
                params.boost = 1.05
                params.saturation = 1.13
                params.contrast = 1.08
                params.brightness = 0.0
            case 3:
                hdrParams.mode = 2
                params.boost = 1.0
                params.saturation = 1.05
                params.contrast = 0.95
                params.brightness = 0.02
            default:
                hdrParams.mode = 1
                params.boost = 1.00
                params.saturation = 1.00
                params.contrast = 1.1
                params.brightness = 0.00
            }
            let hrBoost = hdrHeadroomBoost()
            params.boost = Swift.min(Swift.max(params.boost * hrBoost, 1.0), 2.50)
            params.contrast = Swift.min(Swift.max(params.contrast, 1.00), 1.65)
            params.saturation = Swift.min(Swift.max(params.saturation, 1.00), 1.50)
            params.brightness = 0.0
        } else {
            switch preset {
            case 1: params.boost = 0.95; params.saturation = 1.15; params.contrast = 1.03; params.brightness = 0.0
            case 2: params.boost = 1.15; params.saturation = 1.13; params.contrast = 1.10; params.brightness = 0.0
            case 3: params.boost = 1.05; params.saturation = 0.95; params.contrast = 1.06; params.brightness = 0.0
            default: params.boost = 1.00; params.saturation = 1.00; params.contrast = 1.00; params.brightness = 0.00
            }
        }

        params.mode = hdrParams.mode
        safeHDRSettings.value = params
        updateScreenMaterial()
        LiRequestIdrFrame()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { LiRequestIdrFrame() }

    }

    private func hdrHeadroomBoost() -> Float { 1.52 }

    private func updateHDRParams() {
        var params = HDRParams(
            boost: viewModel.streamSettings.brightness,
            contrast: viewModel.streamSettings.gamma,
            saturation: viewModel.streamSettings.saturation,
            brightness: 0.0,
            mode: hdrParams.mode
        )
        if viewModel.streamSettings.enableHdr {
            let hrBoost = hdrHeadroomBoost()
            params.boost = Swift.min(Swift.max(params.boost * hrBoost, 1.0), 2.25)
            params.brightness = 0.0
        }
        safeHDRSettings.value = params
    }
    
    private func updateScreenMaterial() {
        if videoMode == .sideBySide3D {
            if var mat = surfaceMaterial {
                try? mat.setParameter(name: "texture", value: .textureResource(self.texture))
                surfaceMaterial = mat
                screen.model?.materials = [mat]
            } else {
                screen.model?.materials = [UnlitMaterial(texture: texture)]
            }
        } else {
            screen.model?.materials = [UnlitMaterial(texture: self.texture)]
        }
    }
    
    private func setupMaterial() async {
        if surfaceMaterial == nil {
            do {
                var material = try await ShaderGraphMaterial(named: "/Root/SBSMaterial", from: "SBSMaterial.usda")
                try material.setParameter(name: "texture", value: .textureResource(self.texture))
                self.surfaceMaterial = material
            } catch {
                self.surfaceMaterial = nil
            }
        }
    }

    // MARK: - RealityView Setup

    func setupRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        let mesh = try! generateCurvedRoundedPlane(
            width: CURVED_MAX_WIDTH_METERS,
            aspectRatio: screenAspect,
            resolution: (512, 512),
            curveMagnitude: curvaturePreset.value * curveAnimationMultiplier,
            cornerRadiusFraction: cornerRadiusFraction
        )
        
        if videoMode == .standard2D {
            screen = ModelEntity(mesh: mesh, materials: [UnlitMaterial(texture: texture)])
        } else {
            let material = UnlitMaterial(texture: texture)
            screen = ModelEntity(mesh: mesh, materials: [material])
        }

        let thinCollisionShape = ShapeResource.generateBox(
            width: CURVED_MAX_WIDTH_METERS,
            height: CURVED_MAX_WIDTH_METERS * screenAspect,
            depth: 0.01  // Very thin - just 1cm depth
        )
        
        screen.components.set(CollisionComponent(
            shapes: [thinCollisionShape],
            filter: CollisionFilter(
                group: .screenEntity,
                mask: .all
            )
        ))
        
        screen.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        screen.position = SIMD3<Float>(0, 0, -1.5)
        
        content.add(screen)

        let head = AnchorEntity(.head)
        content.add(head)
        self.headAnchor = head

        if !hasInitializedPosition {
            screen.position = SIMD3<Float>(0.0, 1.5, -6.0)
            hasInitializedPosition = true
            screenPosition = screen.position
            screenScale = 4.0
        }
        
        if let controls = attachments.entity(for: "controls") {
            self.controlsEntity = controls
            if controls.parent !== screen { screen.addChild(controls) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            controls.position = [0.0 as Float, (screenHeight / 2.0) + Float(0.03), Float(0.05)]
        }
        
        if let inputEnt = attachments.entity(for: "inputOverlay") {
            if inputEnt.parent !== screen { screen.addChild(inputEnt) }
            inputEnt.position = [0.0 as Float, 0.0 as Float, Float(0.005)]
            
            let bounds = inputEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(inputEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = CURVED_MAX_WIDTH_METERS * 1.05
                let scale = desiredLocalWidth / unscaledWidth
                inputEnt.scale = [scale, scale, scale]
                inputBaseWidth = unscaledWidth
                inputScaleInitialized = true
            }
        }

        if let statsEnt = attachments.entity(for: "stats") {
            if statsEnt.parent !== screen { screen.addChild(statsEnt) }
            if !statsScaleInitialized {
                let bounds = statsEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(statsEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let targetLocalWidth = statsCardWidthMeters
                    let scale = targetLocalWidth / unscaledWidth
                    statsEnt.scale = [scale, scale, scale]
                }
            }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            statsEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(0.03), Float(0.05)]
        }

        if let tutorialEnt = attachments.entity(for: "tutorial") {
            if tutorialEnt.parent !== screen { screen.addChild(tutorialEnt) }
            tutorialEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = tutorialEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(tutorialEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let targetLocalWidth = tutorialCardWidthMeters
                let scale = targetLocalWidth / unscaledWidth
                tutorialEnt.scale = [scale, scale, scale]
            }
        }

        if let swapEnt = attachments.entity(for: "swapConfirm") {
            if swapEnt.parent !== screen { screen.addChild(swapEnt) }
            swapEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]

            let bounds = swapEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(swapEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = swapCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                swapEnt.scale = [scale, scale, scale]
            }
        }

        if let sbsEnt = attachments.entity(for: "sbsConfirm") {
            if sbsEnt.parent !== screen { screen.addChild(sbsEnt) }
            sbsEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]

            let bounds = sbsEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(sbsEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = swapCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                sbsEnt.scale = [scale, scale, scale]
            }
        }

        if let popupEnt = attachments.entity(for: "presetPopup") {
            if popupEnt.parent !== screen { screen.addChild(popupEnt) }
            popupEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = popupEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(popupEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                popupEnt.scale = [scale, scale, scale]
            }
        }
    }

    func updateRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        let currentCurve = curvaturePreset.value * curveAnimationMultiplier
        
        if let mesh = try? generateCurvedRoundedPlane(
            width: CURVED_MAX_WIDTH_METERS,
            aspectRatio: screenAspect,
            resolution: (512, 512),
            curveMagnitude: currentCurve,
            cornerRadiusFraction: cornerRadiusFraction
        ) {
            if let model = screen.model {
                try? model.mesh.replace(with: mesh.contents)
            }
        }
        
        screen.scale = [screenScale, screenScale, screenScale]
        screen.position = screenPosition
        let tiltRadians = tiltAngle * .pi / 180.0
        let tiltRotation = simd_quatf(angle: tiltRadians, axis: SIMD3<Float>(1, 0, 0))
        screen.transform.rotation = tiltRotation
        
        if let head = headAnchor {
            let p = head.position(relativeTo: nil)
            let delta = simd_length(p - lastHeadWorldPos)
            let nearOrigin = simd_length(p) < 0.1
            let wasFar = simd_length(lastHeadWorldPos) > 0.25
            let notDraggingRecently = (CACurrentMediaTime() - lastDragTime) > 0.4
            if nearOrigin && wasFar && delta > 0.25 && notDraggingRecently {
                withAnimation(.easeInOut(duration: 0.22)) {
                    recenterScreenToHead(head: head)
                }
            }
            lastHeadWorldPos = p
        }
        
        if let inputEnt = attachments.entity(for: "inputOverlay") {
            if inputEnt.parent !== screen { screen.addChild(inputEnt) }
            let bounds = inputEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(inputEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = CURVED_MAX_WIDTH_METERS * 1.05
                let scale = desiredLocalWidth / unscaledWidth
                inputEnt.scale = [scale, scale, scale]
            }
        }

        if let statsEnt = attachments.entity(for: "stats") {
            if statsEnt.parent !== screen { screen.addChild(statsEnt) }
            if !statsScaleInitialized {
                let bounds = statsEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(statsEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let targetLocalWidth = statsCardWidthMeters
                    let scale = targetLocalWidth / unscaledWidth
                    statsEnt.scale = [scale, scale, scale]
                }
            }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            statsEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(0.03), Float(0.05)]
        }

        if let tutorialEnt = attachments.entity(for: "tutorial") {
            if tutorialEnt.parent !== screen { screen.addChild(tutorialEnt) }
            tutorialEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = tutorialEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(tutorialEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let targetLocalWidth = tutorialCardWidthMeters
                let scale = targetLocalWidth / unscaledWidth
                tutorialEnt.scale = [scale, scale, scale]
            }
        }

        if let swapEnt = attachments.entity(for: "swapConfirm") {
            if swapEnt.parent !== screen { screen.addChild(swapEnt) }
            swapEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]

            let bounds = swapEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(swapEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = swapCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                swapEnt.scale = [scale, scale, scale]
            }
        }

        if let sbsEnt = attachments.entity(for: "sbsConfirm") {
            if sbsEnt.parent !== screen { screen.addChild(sbsEnt) }
            sbsEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]

            let bounds = sbsEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(sbsEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = swapCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                sbsEnt.scale = [scale, scale, scale]
            }
        }

        if let popupEnt = attachments.entity(for: "presetPopup") {
            if popupEnt.parent !== screen { screen.addChild(popupEnt) }
            popupEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = popupEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(popupEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                popupEnt.scale = [scale, scale, scale]
            }
        }
    }

    // MARK: - Stream Management

    private func ensureStreamStartedIfNeeded() {
        startStreamIfNeeded()
    }
    
    private func startStreamIfNeeded() {
        guard streamMan == nil else {
            needsResume = false
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            guard self.viewModel.activelyStreaming, self.streamMan == nil else {
                return
            }
            
            self.ensureHDRTextureMatchesSetting()
            
            self.streamMan = StreamManager(
                config: self.streamConfig,
                rendererProvider: {
                    DrawableVideoDecoder(
                        texture: self.texture,
                        callbacks: self.connectionCallbacks,
                        aspectRatio: self.screenAspect,
                        useFramePacing: self.streamConfig.useFramePacing,
                        enableHDR: self.viewModel.streamSettings.enableHdr,
                        hdrSettingsProvider: { [safeHDRSettings] in safeHDRSettings.value },
                        enhancementsProvider: { [weak viewModel] in
                            guard let vm = viewModel else { return (1.0, 1.0) }
                            // Apply additional HDR settings
                            let preset = vm.streamSettings.uikitPreset
                            switch preset {
                            case 1: return (0.95, 1.01)  // Cinematic: slight desaturation, minimal contrast
                            case 2: return (1.12, 1.02)  // Vivid: added saturation, light contrast
                            case 3: return (1.05, 1.01)  // Realistic: warmth via saturation, minimal contrast
                            default: return (1.0, 1.0)   // Default: neutral
                            }
                        },
                        callbackToRender: { texture, correctedResolution in
                            guard self.renderGateOpen else { return }
                            
                            DispatchQueue.main.async {
                                if let correctedResolution { self.correctedResolution = correctedResolution }
                                self.texture.replace(withDrawables: texture)
                                self.rebindScreenMaterial()
                                self.controllerSupport?.connectionEstablished()
                                self.startHideTimer()
                            }
                        }
                    )
                },
                connectionCallbacks: self.connectionCallbacks
            )
            let operationQueue = OperationQueue()
            if let streamMan = self.streamMan {
                operationQueue.addOperation(streamMan)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) { LiRequestIdrFrame() }
        }
    }
    
    private func ensureHDRTextureMatchesSetting() {
        let desiredHDR = viewModel.streamSettings.enableHdr
        if desiredHDR == isHDRTexture { return }
        
        let width = Int(streamConfig.width)
        let height = Int(streamConfig.height)
        let bytesPerPixel = desiredHDR ? 8 : 4
        let data = Data(count: bytesPerPixel * width * height)
        
        if let newTexture = try? TextureResource(
            dimensions: .dimensions(width: width, height: height),
            format: .raw(pixelFormat: desiredHDR ? .rgba16Float : .bgra8Unorm_srgb),
            contents: .init(mipmapLevels: [.mip(data: data, bytesPerRow: bytesPerPixel * width)])
        ) {
            self.texture = newTexture
            self.isHDRTexture = desiredHDR
            rebindScreenMaterial()
        }
    }
    
    @State private var openedMainAfterDisconnect = false
    
    private func triggerCloseSequence() {
        performCompleteTeardown()
        viewModel.activelyStreaming = false
        viewModel.shouldCloseStream = false

        Task {
            await dismissImmersiveSpace()
        }
    }
    
    private func refreshEDRHeadroomAndParams() { }
    
    private func cycleTiltAngle() {
        tiltAngle += 10.0
        if tiltAngle > 40.0 {
            tiltAngle = 0.0
        }
    }
    
    private func performCompleteTeardown() {
        guard !hasPerformedTeardown else { return }
        hasPerformedTeardown = true
        
        guard let streamManager = streamMan else {
            cleanupResources()
            postTeardownNotification()
            return
        }
        
        streamManager.stopStream(completion: { [self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.cleanupResources()
                self.postTeardownNotification()
            }
        })
    }
    
    private func cleanupResources() {
        streamMan = nil
        controllerSupport?.cleanup()
        controllerSupport = nil

        // Remove: NotificationCenter.post(name: .rkStreamDidTeardown, object: nil)
    }
    
    private func postTeardownNotification() {
        print("[Curved] Posting .rkStreamDidTeardown after verified completion + buffer")
        // Remove: NotificationCenter.post(name: .rkStreamDidTeardown, object: nil)
    }

    private func updateEnvironmentState() {
        guard let dome = environmentDome else { return }
        
        if environmentSphereLevel == 0 {
            dome.isEnabled = false
            lastEnvironmentSphereLevelApplied = 0
            return
        }
        dome.isEnabled = true
        if let tex = currentSkyboxTexture() {
            applySkyboxTexture(tex)
            lastEnvironmentSphereLevelApplied = environmentSphereLevel
        }
    }
    
    private func updateNewsetState() {
        guard let dome = environmentDome else { return }
        
        if newsetLevel == 0 {
            dome.isEnabled = false
            return
        }
        dome.isEnabled = true
        if let tex = currentNewsetTexture() {
            applySkyboxTexture(tex)
        }
    }

    private func currentSkyboxTexture() -> TextureResource? {
        let builtinNames = builtinSkyboxNames
        let idx = environmentSphereLevel - 1
        if idx >= 0 && idx < builtinNames.count {
            if let cached = builtinSkyboxTextures[builtinNames[idx]] {
                return cached
            }
            if let tex = loadTextureFromBundle(candidates: [builtinNames[idx]], subdirectory: nil) {
                builtinSkyboxTextures[builtinNames[idx]] = tex
                return tex
            }
        } else if idx >= 0 && idx - builtinNames.count < extraSkyboxTextures.count {
            return extraSkyboxTextures[idx - builtinNames.count]
        }
        return nil
    }
    
    private func currentNewsetTexture() -> TextureResource? {
        let idx = newsetLevel - 1
        if idx >= 0 && idx < newsetSkyboxNames.count {
            let name = newsetSkyboxNames[idx]
            
            if let cached = newsetSkyboxTextures[name] {
                return cached
            }
            
            // Try without subdirectory (files added as group)
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
                if let tex = try? TextureResource.load(contentsOf: url) {
                    newsetSkyboxTextures[name] = tex
                    return tex
                }
            }
        }
        return nil
    }
    
    private func applySkyboxTexture(_ texture: TextureResource) {
        guard let dome = environmentDome else { return }
        dome.model = ModelComponent(mesh: dome.model?.mesh ?? .generateSphere(radius: 60.0),
                                    materials: [UnlitMaterial(texture: texture)])
        
        // Apply rotation based on which set is active
        if newsetLevel > 0 {
            // Newset is active
            let idx = newsetLevel - 1
            if idx >= 0 && idx < newsetSkyboxNames.count {
                let skyboxName = newsetSkyboxNames[idx]
                if let rotationAngle = newsetSkyboxRotations[skyboxName] {
                    dome.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))
                } else {
                    dome.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                }
            }
        } else if environmentSphereLevel > 0 {
            // Numbered set is active
            let idx = environmentSphereLevel - 1
            if idx >= 0 && idx < builtinSkyboxNames.count {
                let skyboxName = builtinSkyboxNames[idx]
                if let rotationAngle = skyboxRotations[skyboxName] {
                    dome.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))
                } else {
                    dome.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                }
            }
        } else {
            dome.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private func loadTextureFromBundle(candidates: [String], subdirectory: String?) -> TextureResource? {
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: subdirectory) {
                do {
                    let tex = try TextureResource.load(contentsOf: url)
                    return tex
                } catch {
                    print("[Texture] Error loading \(name).jpg: \(error)")
                }
            }
        }
        return nil
    }

    // MARK: - Mesh Generation

    func generateCurvedRoundedPlane(
        width: Float,
        aspectRatio: Float,
        resolution: (UInt32, UInt32),
        curveMagnitude: Float,
        cornerRadiusFraction: Float
    ) throws -> MeshResource {
        var descr = MeshDescriptor(name: "curved_rounded_plane")
        let height = width * aspectRatio
        let vertexCount = Int(resolution.0 * resolution.1)
        let numQuadsX = resolution.0 - 1
        let numQuadsY = resolution.1 - 1
        let triangleCount = Int(numQuadsX * numQuadsY * 2)
        let indexCount = triangleCount * 3
        
        var positions = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var texcoords = [SIMD2<Float>](repeating: .zero, count: vertexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))
        let halfAngle = currentAngle / 2.0
        let isFlat = currentAngle < 0.0001
        let radius: Float = isFlat ? .infinity : (width / currentAngle)
        
        let cornerRadius = max(0.0, min(0.25, cornerRadiusFraction)) * height
        let x0 = -width / 2.0
        let y0 = -height / 2.0
        
        let texInset: Float = 0.002
        
        var vi = 0
        var ii = 0
        
        for y_v in 0 ..< resolution.1 {
            let v_geo = Float(y_v) / Float(resolution.1 - 1)
            let yFlat = (0.5 - v_geo) * height
            let v_tex = (1.0 - v_geo) * (1.0 - 2.0 * texInset) + texInset

            for x_v in 0 ..< resolution.0 {
                let u = Float(x_v) / Float(resolution.0 - 1)
                let xFlat = (u - 0.5) * width

                var xr = xFlat, yr = yFlat
                if cornerRadius > 0 {
                    if xr < x0 + cornerRadius && yr < y0 + cornerRadius {
                        let dx = xr - (x0 + cornerRadius), dy = yr - (y0 + cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (x0 + cornerRadius) + nx; yr = (y0 + cornerRadius) + ny }
                    } else if xr > -x0 - cornerRadius && yr < y0 + cornerRadius {
                        let dx = xr - (-x0 - cornerRadius), dy = yr - (y0 + cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (-x0 - cornerRadius) + nx; yr = (y0 + cornerRadius) + ny }
                    } else if xr < x0 + cornerRadius && yr > -y0 - cornerRadius {
                        let dx = xr - (x0 + cornerRadius), dy = yr - (-y0 - cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (x0 + cornerRadius) + nx; yr = (-y0 - cornerRadius) + ny }
                    } else if xr > -x0 - cornerRadius && yr > -y0 - cornerRadius {
                        let dx = xr - (-x0 - cornerRadius), dy = yr - (-y0 - cornerRadius)
                        if let (nx, ny) = normalizeAndScale(dx, dy, cornerRadius) { xr = (-x0 - cornerRadius) + nx; yr = (-y0 - cornerRadius) + ny }
                    }
                }
                
                var px = xr, pz: Float = 0.0
                if !isFlat, radius.isFinite {
                    let t = xr / (width / 2.0)
                    let theta = t * halfAngle
                    px = radius * sin(theta)
                    pz = radius - (radius * cos(theta))
                }

                positions[vi] = SIMD3<Float>(px, yr, pz)
                let u_tex = u * (1.0 - 2.0 * texInset) + texInset
                texcoords[vi] = SIMD2<Float>(u_tex, v_tex)

                if x_v < numQuadsX && y_v < numQuadsY {
                    let current = UInt32(vi), nextRow = current + resolution.0
                    indices[ii + 0] = current; indices[ii + 1] = nextRow; indices[ii + 2] = nextRow + 1
                    indices[ii + 3] = current; indices[ii + 4] = nextRow + 1; indices[ii + 5] = current + 1
                    ii += 6
                }
                vi += 1
            }
        }

        descr.positions = MeshBuffer(positions)
        descr.textureCoordinates = MeshBuffers.TextureCoordinates(texcoords)
        descr.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descr])
    }

    private func normalizeAndScale(_ dx: Float, _ dy: Float, _ cornerRadius: Float) -> (Float, Float)? {
        let dist = sqrt(dx*dx + dy*dy)
        if dist > cornerRadius {
            let s = cornerRadius / dist
            return (dx * s, dy * s)
        }
        return nil
    }
    
    private func getDimmerMaterial() -> (RealityKit.Material, TextureResource?) {
        if dimLevel == 11 {
            if let cached = moonlightMaterial {
                return (cached, nil)
            } else {
                let initial = getMoonlightCycleColor(phase: moonlightCyclePhase).withAlphaComponent(moonlightAlphaLowPower)
                var mat = moonlightMaterial ?? UnlitMaterial(color: initial)
                mat.blending = .transparent(opacity: 1.0)
                moonlightMaterial = mat
                return (mat, nil)
            }
        }

        if dimLevel == 12 {
            var mat = UnlitMaterial(color: currentAmbientColor.withAlphaComponent(0.80))
            mat.blending = .transparent(opacity: 1.0)
            return (mat, nil)
        }

        let selectedTex: TextureResource?
        switch dimLevel {
        case 2: selectedTex = eclipseGradientTexture
        case 4: selectedTex = purpleGradientTexturePurpleBlack
        case 5: selectedTex = twilightGradientTexture
        case 6: selectedTex = dawnGradientTexture
        case 7: selectedTex = sunriseGradientTexture
        case 8: selectedTex = woodlandGradientTexture
        case 9: selectedTex = desertGradientTexture
        case 10: selectedTex = duskHDRTexture
        default: selectedTex = purpleGradientTextureColors
        }

        let mat: RealityKit.Material
        if let tex = selectedTex {
            var unlitMat = UnlitMaterial(texture: tex)

            if dimLevel == 10 {
                unlitMat.color.tint = UIColor.white.withAlphaComponent(1.0)
                unlitMat.blending = .opaque
            } else {
                let tintAlpha: CGFloat = {
                    switch dimLevel {
                    case 2, 4: return 0.95
                    case 5, 6, 7, 8, 9: return 0.90
                    default: return 0.5
                    }
                }()
                unlitMat.color.tint = UIColor.white.withAlphaComponent(tintAlpha)
                unlitMat.blending = .transparent(opacity: 1.0)
            }
            mat = unlitMat
        } else {
            var fallback = UnlitMaterial(color: .purple)
            if dimLevel == 10 {
                fallback.color.tint = UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: 1.0)
                fallback.blending = .opaque
            } else {
                let fallbackAlpha: CGFloat = {
                    switch dimLevel {
                    case 2, 4: return 0.95
                    case 5, 6, 7, 8, 9: return 0.90
                    default: return 0.5
                    }
                }()
                fallback.color.tint = UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: fallbackAlpha)
                fallback.blending = .transparent(opacity: 1.0)
            }
            mat = fallback
        }
        return (mat, selectedTex)
    }

    private func updateDimmerDomesState() {
        dimmerDome?.isEnabled = (dimLevel == 1)
        dimmerDomePurple?.isEnabled = (dimLevel >= 2 && dimLevel <= 12)
    }

    private func updateDimmerDomes(content: RealityViewContent) {
        if let dome = dimmerDome {
            let targetAlpha: Float = viewModel.streamSettings.dimPassthrough ? Float(dimAlphas[1]) : Float(dimAlphas[0])
            if let comp = dome.components[OpacityComponent.self], abs(comp.opacity - targetAlpha) > 0.001 {
                dome.components.set(OpacityComponent(opacity: targetAlpha))
            } else if dome.components[OpacityComponent.self] == nil {
                dome.components.set(OpacityComponent(opacity: targetAlpha))
            }
        }

        if let purple = dimmerDomePurple {
            let (mat, _) = getDimmerMaterial()
            purple.model?.materials = [mat]
        }
    }

    private func setupDimmerDomes(content: RealityViewContent) {
        let dome = ModelEntity(mesh: .generateSphere(radius: 60.0), materials: [UnlitMaterial(color: .black)])
        dome.scale.x = -1.0
        dome.position = .zero
        content.add(dome)
        self.dimmerDome = dome

        let purpleDome = ModelEntity(mesh: .generateSphere(radius: 60.0), materials: [UnlitMaterial(color: .clear)])
        purpleDome.scale.x = -1.0
        purpleDome.position = .zero
        content.add(purpleDome)
        self.dimmerDomePurple = purpleDome

        updateDimmerDomesState()

        Task {
            purpleGradientTextureColors = try? await makeGradientTexture(size: 1024, gradient: .sunset)
            purpleGradientTexturePurpleBlack = try? await makeGradientTexture(size: 1024, gradient: .midnight)
            eclipseGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .eclipse)
            twilightGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .twilight)
            dawnGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .dawn)
            sunriseGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .sunrise)
            woodlandGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .woodland)
            desertGradientTexture = try? await makeGradientTexture(size: 1024, gradient: .desert)
            duskHDRTexture = try? await TextureResource(named: "dusk")
        }
    }

    // MARK: - Gradient Presets and Generator for Dimming Textures
    enum GradientPreset {
        case sunset
        case midnight
        case eclipse
        case twilight
        case dawn
        case sunrise
        case woodland
        case desert
    }

    func makeGradientTexture(size: Int, gradient: GradientPreset) async throws -> TextureResource? {
        let s = max(size, 32)
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))

        let img = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
            ctx.cgContext.fill(rect)

            let colors: [CGColor]
            let locations: [CGFloat]

            switch gradient {
            case .sunset:
                colors = [
                    UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: 0.50).cgColor,
                    UIColor(red: 0.95, green: 0.60, blue: 0.85, alpha: 0.45).cgColor,
                    UIColor(red: 0.95, green: 0.45, blue: 0.60, alpha: 0.42).cgColor,
                    UIColor(red: 0.976, green: 0.627, blue: 0.251, alpha: 0.38).cgColor
                ]
                locations = [0.0, 0.33, 0.65, 1.0]

            case .midnight:
                colors = [
                    UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: 0.42).cgColor,
                    UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: 0.30).cgColor,
                    UIColor(red: 0.50, green: 0.30, blue: 0.75, alpha: 0.18).cgColor,
                    UIColor.black.withAlphaComponent(0.84).cgColor,
                    UIColor.black.withAlphaComponent(0.94).cgColor,
                    UIColor.black.withAlphaComponent(1.00).cgColor
                ]
                locations = [0.00, 0.20, 0.35, 0.50, 0.80, 1.00]

            case .eclipse:
                colors = [
                    UIColor(red: 0.10, green: 0.08, blue: 0.15, alpha: 0.85).cgColor,
                    UIColor(red: 0.15, green: 0.10, blue: 0.20, alpha: 0.88).cgColor,
                    UIColor(red: 0.08, green: 0.05, blue: 0.12, alpha: 0.92).cgColor,
                    UIColor.black.withAlphaComponent(0.96).cgColor
                ]
                locations = [0.0, 0.30, 0.70, 1.0]

            case .twilight:
                colors = [
                    UIColor(red: 0.25, green: 0.20, blue: 0.40, alpha: 0.70).cgColor,
                    UIColor(red: 0.40, green: 0.25, blue: 0.50, alpha: 0.75).cgColor,
                    UIColor(red: 0.20, green: 0.15, blue: 0.30, alpha: 0.82).cgColor,
                    UIColor(red: 0.05, green: 0.03, blue: 0.10, alpha: 0.90).cgColor
                ]
                locations = [0.0, 0.35, 0.70, 1.0]

            case .dawn:
                colors = [
                    UIColor(red: 0.95, green: 0.75, blue: 0.55, alpha: 0.45).cgColor,
                    UIColor(red: 0.90, green: 0.60, blue: 0.70, alpha: 0.50).cgColor,
                    UIColor(red: 0.60, green: 0.45, blue: 0.75, alpha: 0.60).cgColor,
                    UIColor(red: 0.30, green: 0.25, blue: 0.45, alpha: 0.75).cgColor
                ]
                locations = [0.0, 0.30, 0.65, 1.0]

            case .sunrise:
                colors = [
                    UIColor(red: 1.00, green: 0.85, blue: 0.40, alpha: 0.38).cgColor,
                    UIColor(red: 0.98, green: 0.70, blue: 0.50, alpha: 0.42).cgColor,
                    UIColor(red: 0.90, green: 0.50, blue: 0.60, alpha: 0.48).cgColor,
                    UIColor(red: 0.70, green: 0.40, blue: 0.70, alpha: 0.55).cgColor
                ]
                locations = [0.0, 0.30, 0.65, 1.0]

            case .woodland:
                colors = [
                    UIColor(red: 0.20, green: 0.35, blue: 0.18, alpha: 0.50).cgColor,
                    UIColor(red: 0.25, green: 0.40, blue: 0.20, alpha: 0.58).cgColor,
                    UIColor(red: 0.30, green: 0.45, blue: 0.25, alpha: 0.68).cgColor,
                    UIColor(red: 0.15, green: 0.25, blue: 0.12, alpha: 0.80).cgColor
                ]
                locations = [0.0, 0.35, 0.70, 1.0]

            case .desert:
                colors = [
                    UIColor(red: 0.95, green: 0.80, blue: 0.50, alpha: 0.42).cgColor,
                    UIColor(red: 0.90, green: 0.65, blue: 0.45, alpha: 0.48).cgColor,
                    UIColor(red: 0.75, green: 0.50, blue: 0.40, alpha: 0.58).cgColor,
                    UIColor(red: 0.50, green: 0.35, blue: 0.30, alpha: 0.72).cgColor
                ]
                locations = [0.0, 0.30, 0.65, 1.0]
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let cgGradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) {
                let startPoint = CGPoint(x: rect.midX, y: rect.minY)
                let endPoint = CGPoint(x: rect.midX, y: rect.maxY)
                ctx.cgContext.drawLinearGradient(
                    cgGradient,
                    start: startPoint,
                    end: endPoint,
                    options: [.drawsAfterEndLocation]
                )
            }
        }

        if let cg = img.cgImage {
            return try TextureResource.generate(from: cg, options: .init(semantic: .color))
        }
        return nil
    }

    private func getMoonlightCycleColor(phase: CGFloat) -> UIColor {
        let p = phase.truncatingRemainder(dividingBy: 1.0)
        if p < 0.2 {
            return interpolateColor(from: UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 0.96), to: UIColor(red: 0.10, green: 0.06, blue: 0.16, alpha: 0.96), progress: p / 0.2)
        } else if p < 0.4 {
            return interpolateColor(from: UIColor(red: 0.10, green: 0.06, blue: 0.16, alpha: 0.96), to: UIColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.96), progress: (p - 0.2) / 0.2)
        } else if p < 0.6 {
            return interpolateColor(from: UIColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.96), to: UIColor(red: 0.20, green: 0.16, blue: 0.28, alpha: 0.96), progress: (p - 0.4) / 0.2)
        } else if p < 0.8 {
            return interpolateColor(from: UIColor(red: 0.20, green: 0.16, blue: 0.28, alpha: 0.96), to: UIColor(red: 0.22, green: 0.28, blue: 0.36, alpha: 0.96), progress: (p - 0.6) / 0.2)
        } else {
            return interpolateColor(from: UIColor(red: 0.22, green: 0.28, blue: 0.36, alpha: 0.96), to: UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 0.96), progress: (p - 0.8) / 0.2)
        }
    }

    private func interpolateColor(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * progress, green: g1 + (g2 - g1) * progress, blue: b1 + (b2 - b1) * progress, alpha: a1 + (a2 - a1) * progress)
    }
    
    private func rgb(_ color: UIColor) -> SIMD3<Float> {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    private func colorDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return simd_length(d)
    }

    @State private var lastEnvironmentDomeScale: Float = 1.0

    private func setupEnvironment360(content: RealityViewContent) {
        let sphere = ModelEntity(mesh: .generateSphere(radius: 60.0))
        sphere.scale.x = -1.0
        sphere.model = ModelComponent(mesh: sphere.model?.mesh ?? .generateSphere(radius: 60.0),
                                      materials: [UnlitMaterial(color: .clear)])
        sphere.isEnabled = false
        content.add(sphere)
        environmentDome = sphere

        if extraSkyboxTextures.isEmpty && extraSkyboxNames.isEmpty {
            loadExtraSkyboxesFromBundle()
        }
        if environmentSphereLevel != 0, let tex = currentSkyboxTexture() {
            sphere.isEnabled = true
            applySkyboxTexture(tex)
            lastEnvironmentSphereLevelApplied = environmentSphereLevel
        }
    }

    func updateEnvironment360(content: RealityViewContent) {
        guard let dome = environmentDome else { return }
        
        // Handle newset first (takes priority)
        if newsetLevel > 0 {
            dome.isEnabled = true
            if let tex = currentNewsetTexture() {
                applySkyboxTexture(tex)
            }
            return
        }
        
        // Handle regular environment spheres
        if environmentSphereLevel == 0 {
            dome.isEnabled = false
            lastEnvironmentSphereLevelApplied = 0
            return
        }
        
        if lastEnvironmentSphereLevelApplied != environmentSphereLevel {
            dome.isEnabled = true
            if let tex = currentSkyboxTexture() {
                applySkyboxTexture(tex)
            }
            lastEnvironmentSphereLevelApplied = environmentSphereLevel
        }
    }
    
    internal init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool, swapAction: @escaping () -> Void) {
        self.swapAction = swapAction
        self._streamConfig = streamConfig
        self.needsHdr = needsHdr
        self.controllerSupport = ControllerSupport(config: streamConfig.wrappedValue, delegate: DummyControllerDelegate())
        
        let bytesPerPixel = needsHdr ? 8 : 4
        let data = Data(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height))
        
        self.texture = try! TextureResource(
            dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
            format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb),
            contents: .init(mipmapLevels: [.mip(data: data, bytesPerRow: bytesPerPixel * Int(streamConfig.wrappedValue.width))])
        )
        self.isHDRTexture = needsHdr
    }

    private func recenterScreenToHead(head: AnchorEntity) {
        let headPos = head.position(relativeTo: nil)
        let current = screenPosition

        let yOffset = current.y - headPos.y

        let horizVec = simd_float3(current.x - headPos.x, 0, current.z - headPos.z)
        let horizDist = max(simd_length(horizVec), 0.01)

        let q = head.transform.rotation
        var headForward = q.act(simd_float3(0, 0, -1))

        var flatForward = simd_float3(headForward.x, 0, headForward.z)
        let norm = simd_length(flatForward)
        if norm < 1e-4 {
            flatForward = simd_float3(0, 0, -1)
        } else {
            flatForward /= norm
        }

        var newPos = simd_float3(
            headPos.x + flatForward.x * horizDist,
            headPos.y + yOffset,
            headPos.z + flatForward.z * horizDist
        )

        newPos.x = min(max(newPos.x, -allowedLateralMax), allowedLateralMax)

        screenPosition = newPos
    }

    private func saveCurrentTransform() {
        var pos = screenPosition
        let scale = screenScale
        let packed = [pos.x, pos.y, pos.z]
        UserDefaults.standard.set(packed, forKey: kCurvedPosKey)
        UserDefaults.standard.set(scale, forKey: kCurvedScaleKey)
    }

    private func restoreSavedTransform() {
        if let packed = UserDefaults.standard.array(forKey: kCurvedPosKey) as? [Float], packed.count == 3 {
            screenPosition = SIMD3<Float>(packed[0], packed[1], packed[2])
        }
        let scale = UserDefaults.standard.float(forKey: kCurvedScaleKey)
        if scale > 0 { screenScale = scale }
        tiltAngle = 0.0
    }
    
    private let kCurvedLockedKey = "curved.locked"
    private let kCurvedPosKey = "curved.pos"
    private let kCurvedScaleKey = "curved.scale"
    private let tutorialSeenKey = "hasSeenCurvedDisplayTutorial_v2"

    private func handleWindowClose() {
        isMenuOpen = false
        if let sceneID = self.immersiveSpaceSceneID {
            AudioHelpers.fixAudioForScene(identifier: sceneID)
        } else {
            fixAudioForCurrentMode()
        }
    }

    private func handleResumeFromMenu() {
        isMenuOpen = false
        withAnimation(.easeInOut) {
            self.showMenuPanel = false
        }
        if let sceneID = self.immersiveSpaceSceneID {
            AudioHelpers.fixAudioForScene(identifier: sceneID)
        } else {
            fixAudioForCurrentMode()
        }
        dismissWindow(id: "mainView")
        self.refreshAfterResume()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { self.refreshAfterResume() }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { self.refreshAfterResume() }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { self.refreshAfterResume() }
        self.controlsHighlighted = false
        self.startHideTimer()
    }

    private func startMoonlightCycle() {
        moonlightCyclePhase = 0.0
        moonlightCycleTimer?.invalidate()
        lastMoonlightUpdateTime = CACurrentMediaTime()

        if let purple = self.dimmerDomePurple {
            let initial = getMoonlightCycleColor(phase: moonlightCyclePhase).withAlphaComponent(moonlightAlphaLowPower)
            var mat = moonlightMaterial ?? UnlitMaterial(color: initial)
            mat.blending = .transparent(opacity: 1.0)
            self.moonlightMaterial = mat
            purple.model?.materials = [mat]
            self.lastMoonlightAppliedRGB = rgb(initial)
        }

        moonlightCycleTimer = Timer.scheduledTimer(withTimeInterval: moonlightUpdateIntervalLowPower, repeats: true) { _ in
            guard self.dimLevel == 11, let purple = self.dimmerDomePurple else { return }

            let now = CACurrentMediaTime()
            let dt = now - self.lastMoonlightUpdateTime
            self.lastMoonlightUpdateTime = now

            self.moonlightCyclePhase += CGFloat(dt) / self.moonlightCycleDurationLowPower
            if self.moonlightCyclePhase >= 1.0 { self.moonlightCyclePhase -= 1.0 }

            let nextColor = self.getMoonlightCycleColor(phase: self.moonlightCyclePhase).withAlphaComponent(self.moonlightAlphaLowPower)
            let rgbVal = self.rgb(nextColor)

            if self.colorDistance(rgbVal, self.lastMoonlightAppliedRGB) >= self.moonlightColorDeltaThresholdLowPower {
                if var mat = self.moonlightMaterial {
                    mat.color.tint = nextColor
                    self.moonlightMaterial = mat
                    purple.model?.materials = [mat]
                } else {
                    var mat = UnlitMaterial(color: nextColor)
                    mat.blending = .transparent(opacity: 1.0)
                    self.moonlightMaterial = mat
                    purple.model?.materials = [mat]
                }
                self.lastMoonlightAppliedRGB = rgbVal
            }
        }
    }

    private func stopMoonlightCycle() {
        moonlightCycleTimer?.invalidate()
        moonlightCycleTimer = nil
        moonlightMaterial = nil
    }

    // MARK: - Timers & State Changes

    private func startHideTimer() {
        hideTimer?.invalidate()
        hideControls = false
        controlsHighlighted = true

        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                hideControls = true
                controlsHighlighted = false
            }
        }
    }
    
    private func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                hideControls = true
                controlsHighlighted = false
            }
        }
    }

    // MARK: - UI Helpers

    private func showModeToast(text: String, icon: String) {
        modeLabelTimer?.invalidate()
        modeBannerText = text
        modeBannerIcon = icon
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showModeLabel = true
        }
        modeLabelTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                showModeLabel = false
            }
        }
    }

    private func presetName(for preset: Int32) -> String {
        switch preset {
        case 0: "Default"  
        case 1: "Cinematic"
        case 2: "Vivid"
        case 3: "Realistic"
        default: "Default"  
        }
    }
    
    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let streamMan = self.streamMan, let stats = streamMan.getStatsOverlayText() {
                self.statsOverlayText = stats
            }
        }
    }
    
    private func fixAudioForCurrentMode() {
        if self.spatialAudioMode {
            AudioHelpers.fixAudioForSurroundForCurrentWindow()
        } else {
            AudioHelpers.fixAudioForDirectStereo()
        }
    }

    private func updateScreenInteractivity() {
        guard screen.parent != nil else { return }
        let shouldDisableInteractions = showMenuPanel || showSwapConfirm || show3DConfirm
        if shouldDisableInteractions {
            screen.components.remove(CollisionComponent.self)
            screen.components.remove(InputTargetComponent.self)
        } else {
            screen.components.set(CollisionComponent(
                shapes: [ShapeResource.generateBox(
                    width: CURVED_MAX_WIDTH_METERS,
                    height: CURVED_MAX_WIDTH_METERS * screenAspect,
                    depth: 0.01
                )],
                filter: CollisionFilter(
                    group: .screenEntity,
                    mask: .all
                )
            ))
            screen.components.set(InputTargetComponent(allowedInputTypes: .all))
        }
    }
    
    // MARK: - Preload Skyboxes
    private func loadExtraSkyboxesFromBundle() {
        let exts = ["jpg", "jpeg", "png"]
        let builtinSet = Set(builtinSkyboxNames + ["AboveClouds", "Above_Clouds"])
        var names: [String] = []
        var textures: [TextureResource] = []
        
        for ext in exts {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Skyboxes") {
                for url in urls {
                    let base = url.deletingPathExtension().lastPathComponent
                    if builtinSet.contains(base) { continue }
                    if names.contains(base) { continue }
                    do {
                        let tex = try TextureResource.load(contentsOf: url)
                        names.append(base)
                        textures.append(tex)
                    } catch {
                        print("[Texture] Error loading \(base).\(ext): \(error)")
                    }
                }
            }
        }
        extraSkyboxNames = names
        extraSkyboxTextures = textures
    }
}

struct CenterPresetPopup: View {
    var text: String
    var icon: String
    
    var body: some View {
        let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
        let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
        let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)
        let radius: CGFloat = 24
        
        HStack(spacing: 12) {
            Spacer()
            // 1. Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brandOrange, brandOrange.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 83, height: 83)
                    .shadow(color: brandOrange.opacity(0.5), radius: 12, x: 0, y: 8)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            // 2. Text
            Text(text.uppercased())
                .font(.custom("Fredoka-SemiBold", size: 50))
                .tracking(1.2)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .frame(width: 713, height: 132)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(brandNavy.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 16)
        .allowsHitTesting(false)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let mainViewWindowClosed = Notification.Name("MainViewWindowClosed")
    static let resumeStreamFromMenu = Notification.Name("ResumeStreamFromMenu")
    static let rkStreamDidTeardown = Notification.Name("RKStreamDidTeardown")
    static let curvedScreenWakeRequested = Notification.Name("CurvedScreenWakeRequested")
}

// MARK: - Center Preset Popup

struct ConditionalGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassBackgroundEffect()
        } else {
            content
        }
    }
}

extension View {
    func conditionalGlass(_ enabled: Bool) -> some View {
        self.modifier(ConditionalGlass(enabled: enabled))
    }
}