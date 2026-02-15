import SwiftUI
import RealityKit
import simd
import GameController
import ARKit
import UIKit
import AVFoundation
import QuartzCore
import ImageIO
import os



final class ThreadSafeHDRSettings: @unchecked Sendable {
    private var params: HDRParams
    private let lock = NSLock()
    init(params: HDRParams) { self.params = params }
    var value: HDRParams {
        get { lock.lock(); defer { lock.unlock() }; return params }
        set { lock.lock(); defer { lock.unlock() }; params = newValue }
    }
}

// MARK: - Frame Mailbox (Thread-Safe Handoff)

final class FrameMailbox: @unchecked Sendable {
   
    private let lock = OSAllocatedUnfairLock<TextureResource.DrawableQueue?>(initialState: nil)
    
    // Decoder calls this to drop off a frame (Background Thread)
    func deposit(_ drawable: TextureResource.DrawableQueue) {
        lock.withLock { $0 = drawable }
    }
    
 
    func collect() -> TextureResource.DrawableQueue? {
        lock.withLock {
            let d = $0
            $0 = nil // Empty the box so we don't draw the same frame twice
            return d
        }
    }
}

class HeadPositionStorage {
    var positionInScreenSpace: SIMD3<Float> = .zero
}

struct InputCaptureView: UIViewRepresentable {
    let controllerSupport: ControllerSupport
    @Binding var showKeyboard: Bool
    var isControllerMode: Bool  // True only when inputMode == .controller
    var curvature: Float
    var streamConfig: StreamConfiguration
    let headStorage: HeadPositionStorage
    
    func makeUIView(context: Context) -> InputCaptureUIView {
        let view = InputCaptureUIView()
        view.curvature = curvature
        view.controllerSupport = controllerSupport
        view.streamConfig = streamConfig
        view.headStorage = headStorage
        view.allowTouchPassthrough = !showKeyboard && !isControllerMode
        
        view.isMultipleTouchEnabled = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        
        return view
    }
    
    func updateUIView(_ uiView: InputCaptureUIView, context: Context) {
        uiView.curvature = curvature
        uiView.streamConfig = streamConfig
        uiView.headStorage = headStorage
        uiView.allowTouchPassthrough = !showKeyboard && !isControllerMode
        uiView.showVirtualKeyboard = showKeyboard
        
        // ALWAYS aggressively reclaim first responder (needed for controller input)
        if !uiView.isFirstResponder {
            _ = uiView.becomeFirstResponder()
            
            // Double-check and force if needed
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    _ = uiView.becomeFirstResponder()
                }
            }
        }
    }
}

class InputCaptureUIView: UIView, UIKeyInput {
    var controllerSupport: ControllerSupport?
    var curvature: Float = 0.0
    var streamConfig: StreamConfiguration?
    var headStorage: HeadPositionStorage?
    var allowTouchPassthrough: Bool = true
    var firstResponderCheckTimer: Timer?
    var showVirtualKeyboard: Bool = false {
        didSet {
            if oldValue != showVirtualKeyboard {
                reloadInputViews()
            }
        }
    }
    
    private let maxCurveAngle: Float = 1.3
    
    // Suppress software keyboard if showVirtualKeyboard is false, but still allow hardware input
    override var inputView: UIView? {
        return showVirtualKeyboard ? nil : UIView()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
        startFirstResponderMonitoring()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
        startFirstResponderMonitoring()
    }
    
    private func startFirstResponderMonitoring() {
        // Periodically check and reclaim first responder if lost (needed for controller input)
        firstResponderCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isFirstResponder {
                _ = self.becomeFirstResponder()
            }
        }
    }
    
    deinit {
        firstResponderCheckTimer?.invalidate()
    }
    
    private func setupGestures() {
        // From commit 12250ee: Attach GCEventInteraction for reliable controller input
        DispatchQueue.main.async {
            self.controllerSupport?.attachGCEventInteraction(to: self)
        }
    }
    
    // CRITICAL: Override hitTest to allow touches to pass through to RealityKit when needed
    // Controller input still works because it's handled via first responder status
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // When keyboard is shown, handle touches. Otherwise, pass through.
        if allowTouchPassthrough {
            return nil  // Touches pass through to RealityKit
        }
        return super.hitTest(point, with: event)
    }
    
    override var canBecomeFocused: Bool { true }
    override var canBecomeFirstResponder: Bool { true }
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
    
    // Handle special keys like Return/Enter
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        
        for press in presses {
            if KeyboardSupport.sendKeyEvent(for: press, down: true) {
                handled = true
            }
        }
        
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        
        for press in presses {
            if KeyboardSupport.sendKeyEvent(for: press, down: false) {
                handled = true
            }
        }
        
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }
}

let CURVED_MAX_WIDTH_METERS: Float = 2.0
let CURVED_MAX_ANGLE: Float = 1.3
let GAZE_VERTICAL_OFFSET: Float = 0.015  // Small upward offset to compensate for eye-to-cursor alignment

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

// MARK: - Input Mode for Curved Display

enum InputMode: Int, CaseIterable {
    case screenMove = 0
    case controller = 1
    case gazeControl = 2
    
    var displayName: String {
        switch self {
        case .screenMove: return "Screen Adjust Mode"
        case .controller: return "Controller Mode"
        case .gazeControl: return "Gaze Control Mode"
        }
    }
    
    var icon: String {
        switch self {
        case .screenMove: return "arrow.up.and.down.and.arrow.left.and.right"
        case .controller: return "gamecontroller.fill"
        case .gazeControl: return "eye.fill"
        }
    }
    
    func next() -> InputMode {
        let allCases = InputMode.allCases
        let idx = allCases.firstIndex(of: self) ?? 0
        return allCases[(idx + 1) % allCases.count]
    }
}

// MARK: - Gaze Input Controller
// Created by NeoVectorX - January 2025
// Implements raycast-to-UV mapping and gesture handling for curved screen geometry.
//
// "Shoot First" Logic: Matches FlatInputCaptureUIView behavior exactly.
// Click happens on pinch START (not release), making interactions feel instant.

class GazeInputController {
    // Timing constants (Matching FlatInputCaptureUIView)
    private let longPressActivationDelay: TimeInterval = 0.650
    private let doubleTapDeadZoneDelay: TimeInterval = 0.250  // 250ms
    private let doubleTapDeadZoneDelta: Float = 0.025  // 2.5% of screen (normalized)
    // Threshold to cancel long press (roughly size of a button in UV space)
    private let movementTolerance: Float = 0.015

    // State
    private(set) var pinchActive = false
    private var longPressTimer: Timer?
    private var startUV: SIMD2<Float> = .zero
    private var isRightClickMode = false  // Track if we swapped to right-click
    private var lastClickTime: TimeInterval = 0  // Track last click for double-tap detection
    private var lastClickUV: SIMD2<Float> = .zero  // Track last click position

    var streamConfig: StreamConfiguration?
    
    // Button Constants (matching moonlight-common-c)
    private let ACTION_PRESS: Int8 = 0x07
    private let ACTION_RELEASE: Int8 = 0x08
    private let BUTTON_LEFT: Int32 = 0x01
    private let BUTTON_RIGHT: Int32 = 0x03
    
    func onPinchBegan(at uv: SIMD2<Float>) {
        guard !pinchActive else { return }
        pinchActive = true
        startUV = uv
        isRightClickMode = false

        // Check if we're in the double-tap dead zone
        let now = CACurrentMediaTime()
        let timeSinceLastClick = now - lastClickTime
        
        // Calculate distance from last click
        let dx = uv.x - lastClickUV.x
        let dy = uv.y - lastClickUV.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Don't reposition mouse for clicks within the double-tap deadzone
        // This is critical for double-clicking to work properly
        if timeSinceLastClick > doubleTapDeadZoneDelay || distance > doubleTapDeadZoneDelta {
            sendMousePosition(uv: uv)
        }

        // Press Left Button Immediately ("Shoot First")
        // This makes clicks instant and drags seamless.
        sendMouseButton(action: ACTION_PRESS, button: BUTTON_LEFT)

        // Start Long Press Timer (for Right Click)
        // Always start the timer - it will be cancelled if we're dragging
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressActivationDelay, repeats: false) { [weak self] _ in
            self?.triggerLongPress()
        }
        
        lastClickTime = now
        lastClickUV = uv
    }
    
    func onPinchChanged(at uv: SIMD2<Float>) {
        // Always update position (Dragging happens naturally because Left is already Down)
        sendMousePosition(uv: uv)
        
        // Check distance to see if we should cancel the "Right Click" timer
        if longPressTimer != nil {
            let dx = uv.x - startUV.x
            let dy = uv.y - startUV.y
            let dist = sqrt(dx*dx + dy*dy)
            
            if dist > movementTolerance {
                // Moved too far, user is dragging. Cancel Right Click timer.
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
        }
    }
    
    func onPinchEnded() {
        guard pinchActive else { return }
        pinchActive = false
        
        // Cancel timer if it hasn't fired yet
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        // Release buttons based on what mode we're in
        if isRightClickMode {
            // Release Right Button
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_RIGHT)
        } else {
            // Release Left Button (Standard Click / Drag End)
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
        }
        
        isRightClickMode = false
    }
    
    private func triggerLongPress() {
        // User held still! Swap Left Click for Right Click.
        isRightClickMode = true
        
        // 1. Release Left (Cancel the click/drag we started)
        sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
        
        // 2. Press Right
        sendMouseButton(action: ACTION_PRESS, button: BUTTON_RIGHT)
    }
    
    private func sendMousePosition(uv: SIMD2<Float>) {
        guard let config = streamConfig else { return }
        let x = Int16(uv.x * Float(config.width))
        let y = Int16(uv.y * Float(config.height))
        LiSendMousePositionEvent(x, y, Int16(config.width), Int16(config.height))
    }
    
    // MARK: - Touch Mode (Relative Mouse Movement)
    // For trackpad-style cursor control
    // Works like a real trackpad:
    // - Drag = move cursor only (no click)
    // - Quick tap = click
    // - Tap + hold + drag = click and drag
    
    private var lastTouchPosition: SIMD3<Float>? = nil
    private var touchStartPosition: SIMD3<Float>? = nil
    private var touchStartTime: TimeInterval = 0
    private var hasMovedInTouch = false
    private var touchClickTimer: Timer? = nil
    private var touchModeInitialized = false  // Track if cursor has been centered
    private let touchTapThreshold: Float = 0.01  // 1cm movement = drag, not tap
    private let touchTapTimeThreshold: TimeInterval = 0.2  // 200ms = quick tap
    
    func onTouchDragBegan(at worldPos: SIMD3<Float>) {
        guard !pinchActive else { return }
        pinchActive = true
        lastTouchPosition = worldPos
        touchStartPosition = worldPos
        touchStartTime = CACurrentMediaTime()
        hasMovedInTouch = false
        isRightClickMode = false
        
        // On first touch in Touch mode, center the cursor
        if !touchModeInitialized {
            forceCursorToCenter()
            touchModeInitialized = true
        }
        
        // DON'T press any button yet - wait to see if it's a tap or drag
        // Start a timer to detect "tap and hold" for click-drag
        touchClickTimer?.invalidate()
        touchClickTimer = Timer.scheduledTimer(withTimeInterval: touchTapTimeThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // If still holding after 200ms and haven't moved much, it's a click-drag
            if !self.hasMovedInTouch {
                self.sendMouseButton(action: self.ACTION_PRESS, button: self.BUTTON_LEFT)
            }
        }
    }
    
    func onTouchDragChanged(at worldPos: SIMD3<Float>) {
        guard let lastPos = lastTouchPosition,
              let startPos = touchStartPosition else { return }
        
        // Calculate delta in world space
        let delta = worldPos - lastPos
        
        // Check if we've moved significantly from start
        let totalDelta = worldPos - startPos
        let totalDist = simd_length(totalDelta)
        
        if totalDist > touchTapThreshold {
            hasMovedInTouch = true
            // Cancel the click timer - this is a drag, not a tap
            touchClickTimer?.invalidate()
            touchClickTimer = nil
        }
        
        // Convert 3D delta to 2D screen movement
        // Scale factor: adjust sensitivity (higher = more sensitive)
        let sensitivity: Float = 800.0
        let deltaX = delta.x * sensitivity
        let deltaY = -delta.y * sensitivity  // Invert Y for natural movement
        
        // Send relative mouse movement (cursor moves, no button pressed)
        sendRelativeMouseMovement(dx: deltaX, dy: deltaY)
        
        lastTouchPosition = worldPos
    }
    
    func onTouchDragEnded() {
        guard pinchActive else { return }
        pinchActive = false
        
        let now = CACurrentMediaTime()
        let holdDuration = now - touchStartTime
        
        // Cancel timers
        touchClickTimer?.invalidate()
        touchClickTimer = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        // Determine what kind of gesture this was
        if !hasMovedInTouch && holdDuration < touchTapTimeThreshold {
            // Quick tap without movement = CLICK
            sendMouseButton(action: ACTION_PRESS, button: BUTTON_LEFT)
            // Release after a tiny delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.sendMouseButton(action: self?.ACTION_RELEASE ?? 0x08, button: self?.BUTTON_LEFT ?? 0x01)
            }
        } else if !hasMovedInTouch && holdDuration >= touchTapTimeThreshold {
            // Held still for a while = click was already sent by timer, now release
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
        } else {
            // Movement happened = just cursor movement, no click needed
            // (unless click timer fired for click-drag, in which case release it)
            if holdDuration >= touchTapTimeThreshold {
                sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
            }
        }
        
        lastTouchPosition = nil
        touchStartPosition = nil
        hasMovedInTouch = false
        isRightClickMode = false
    }
    
    private var currentMouseX: Int16 = 0
    private var currentMouseY: Int16 = 0
    
    private func sendRelativeMouseMovement(dx: Float, dy: Float) {
        guard let config = streamConfig else { return }
        
        // Update internal cursor position
        currentMouseX = Int16(max(0, min(Float(config.width), Float(currentMouseX) + dx)))
        currentMouseY = Int16(max(0, min(Float(config.height), Float(currentMouseY) + dy)))
        
        LiSendMousePositionEvent(currentMouseX, currentMouseY, Int16(config.width), Int16(config.height))
    }
    
    func forceCursorToCenter() {
        guard let config = streamConfig else { return }
        
        // Calculate exact center pixels
        let centerX = Int16(config.width / 2)
        let centerY = Int16(config.height / 2)
        
        // Update internal tracking
        currentMouseX = centerX
        currentMouseY = centerY
        
        print("🎯 Forcing Mouse to Center: \(centerX), \(centerY)")
        LiSendMousePositionEvent(centerX, centerY, Int16(config.width), Int16(config.height))
    }

    private func sendMouseButton(action: Int8, button: Int32) {
        LiSendMouseButtonEvent(action, button)
    }
    
    func cleanup() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        touchClickTimer?.invalidate()
        touchClickTimer = nil
        lastTouchPosition = nil
        touchStartPosition = nil
        touchModeInitialized = false  // Reset for next time
        if pinchActive {
            // Safety release both buttons
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_RIGHT)
        }
        pinchActive = false
        isRightClickMode = false
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
            // SESSION TOKEN GUARD: If this view's sessionUUID doesn't match the
            // ViewModel's activeSessionToken, this is a "ghost" view from a dying
            // window. Render black and skip all logic to prevent resource collision.
            if config.sessionUUID == viewModel.activeSessionToken {
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
                // CRITICAL SAFETY NET: Force SwiftUI to destroy the inner view (which holds
                // all @State including streamMan) when sessionUUID changes. This prevents
                // "ghost" views from persisting with stale state after a session change.
                .id(config.sessionUUID)
            } else {
                // Ghost view detected - render black and do nothing
                Color.black
                    .ignoresSafeArea()
                    .onAppear {
                        debugLog("👻 Ghost view detected (UUID \(config.sessionUUID) != active \(viewModel.activeSessionToken)). Suppressing.")
                    }
            }
        } else {
            // During window transition (dismiss -> wait -> open), config may be nil.
            // Show black screen to prevent zombie view from initializing.
            Color.black.ignoresSafeArea()
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
    @StateObject private var coopCoordinator = CoopSessionCoordinator.shared
    
    @State private var texture: TextureResource
    @State private var screen: ModelEntity = ModelEntity()
    @State private var videoMode: VideoMode = .standard2D
    @State private var surfaceMaterial: ShaderGraphMaterial?
    
    @State private var curveAnimationMultiplier: Float = 1.0
    @State private var animationTimer: Timer?
    
    @State private var curvaturePreset: CurvaturePreset = .curved
    @State private var tiltAngle: Float = 0.0
    @State private var tiltDirection: Int = 1
    
    @State private var screenPosition: SIMD3<Float> = SIMD3<Float>(0, 1.1, -1.0)
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
    
    // Particle Manager for Nebula preset
    @State private var particleManager = ParticleManager()
    
    // Frame Mailbox for stutter-free, dizziness-free video display
    private let frameMailbox = FrameMailbox()
    
    // Keyboard Override State
    @State private var keyboardInput: String = ""
    @State private var previousKeyboardInput: String = ""
    @FocusState private var isKeyboardFocused: Bool
    
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
    
    @State private var showEnvironmentPicker = false
    @State private var showDimmingPicker = false
    @State private var inputMode: InputMode = .gazeControl // Three-mode input toggle (default: gaze control)
    @State private var gazeController = GazeInputController()

    private let headStorage = HeadPositionStorage()
    
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
    @State private var environmentFadeTimer: Timer?
    
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
    @State private var lastAppliedDimLevel: Int = -1
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
    @State private var presetCooldownUntil: Date? = nil
    
    // Co-op invite button state
    @State private var inviteButtonSent: Bool = false
    @State private var showDisconnectConfirm: Bool = false
    
    @State private var isHDRTexture: Bool = false
    
    @State private var currentAmbientColor: UIColor = .black
    @State private var targetReactiveColor: UIColor = .black
    @State private var reactiveLerpTimer: Timer?
    
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
    
    @State private var builtinSkyboxTextures: [String: TextureResource] = [:]
    @State private var newsetSkyboxTextures: [String: TextureResource] = [:]
    @State private var newsetLevel: Int = 0
    
    var isSBSVideo: Bool {
        let ratio = Float(streamConfig.width) / Float(streamConfig.height)
        return abs(ratio - (32.0 / 9.0)) < 0.01
    }
    
    @State private var firstFrameReceived = false
    @State private var idrWatchdogTimer1: Timer?
    @State private var idrWatchdogTimer2: Timer?
    @State private var postFirstFrameRebindTimer: Timer?
    @State private var guestAggressiveIDRTimer: Timer?
    
    var allowedScaleMax: Float { 8.0 }
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
    
    @State private var lastGeneratedCurve: Float?
    @State private var lastGeneratedAspect: Float?
    
    var body: some View {
        let baseView = mainContent
            .overlay(alignment: .bottom) { scaleHUDOverlay }
            .overlay { swapOverlay }
            .overlay { swapConfirmAttachment }
            .overlay { sbsConfirmAttachment }
            .overlay { disconnectConfirmAttachment }
            .overlay { presetPopupOverlay }
        
        let lifecycleApplied = baseView
            .task { await setupMaterial() }
            .onAppear(perform: setupScene)
            .onDisappear(perform: teardownScene)
            .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
                if shouldClose && !hasPerformedTeardown {
                    triggerCloseSequence()
                }
            }
            .onChange(of: scenePhase) { oldValue, newValue in
                if newValue == .background {
                    if viewModel.activelyStreaming, streamMan != nil {
                        print("Suspending stream due to background")
                        needsResume = true
                        streamMan?.stopStream()
                        streamMan = nil
                        controllerSupport?.cleanup()
                        controllerSupport = nil
                    }
                } else if newValue == .active {
                    if needsResume {
                        print("Resuming stream from background")
                        needsResume = false
                        self.renderGateOpen = true
                        controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
                        connectionCallbacks.controllerSupport = controllerSupport
                        startStreamIfNeeded()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            fixAudioForCurrentMode()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            self.refreshAfterResume()
                        }
                    } else if viewModel.activelyStreaming {
                        // Health check: If stream should be running but isn't, restart it
                        if streamMan == nil {
                            print("[CurvedDisplay] Stream died while inactive - restarting")
                            self.renderGateOpen = true
                            controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
                            connectionCallbacks.controllerSupport = controllerSupport
                            startStreamIfNeeded()
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            fixAudioForCurrentMode()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refreshAfterResume() }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .curvedScreenWakeRequested)) { _ in
                guard viewModel.activelyStreaming && !showMenuPanel && !showSwapConfirm && !showDisconnectConfirm && !showCurvedTutorial else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                fixAudioForCurrentMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resumeStreamFromMenu)) { _ in
                guard viewModel.activelyStreaming else { return }
                dismissWindow(id: "mainView")
                isMenuOpen = false
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
            .onReceive(NotificationCenter.default.publisher(for: .ambientAverageColorUpdated)) { notification in
                guard dimLevel == 2 || dimLevel == 10 || dimLevel == 12 else { return }  // Only process in Reactive V1, V2, and Starfield modes
                if let r = notification.userInfo?["r"] as? Float,
                   let g = notification.userInfo?["g"] as? Float,
                   let b = notification.userInfo?["b"] as? Float {
                    // Boost saturation and brightness for more dramatic effect (1.3x)
                    let boostedR = min(1.0, r * 1.3)
                    let boostedG = min(1.0, g * 1.3)
                    let boostedB = min(1.0, b * 1.3)
                    // Set target color - the lerp timer will smoothly interpolate to it
                    targetReactiveColor = UIColor(red: CGFloat(boostedR), green: CGFloat(boostedG), blue: CGFloat(boostedB), alpha: 1.0)
                    
                    // Update particle system for Starfield mode
                    if dimLevel == 12 {
                        // Use the "max" channel as a proxy for brightness/loudness
                        let brightness = max(r, max(g, b))
                        let uiColor = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
                        particleManager.update(color: uiColor, brightness: brightness)
                    }
                }
            }
        
        let stateChangesApplied = lifecycleApplied
            .onChange(of: viewModel.streamSettings.statsOverlay) { oldValue, newValue in 
                handleStatsOverlay(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: viewModel.activelyStreaming) { oldValue, newValue in 
                self.renderGateOpen = true
                handleActiveStreaming(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: videoMode) { _, _ in updateScreenMaterial() }
            .onChange(of: showMenuPanel) { _, _ in updateScreenInteractivity() }
            .onChange(of: showSwapConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: show3DConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: showDisconnectConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: inputMode) { _, _ in updateScreenInteractivity() }
            .onChange(of: viewModel.streamSettings.swapABXYButtons) { _, newValue in
                controllerSupport?.setSwapABXYButtons(newValue)
            }
        
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
    private var presetPopupOverlay: some View {
        EmptyView()
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
            
           
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                if let newFrame = frameMailbox.collect() {
                    texture.replace(withDrawables: newFrame)
                }
            }
            
        } update: { content, attachments in
            updateDimmerDomes(content: content)
            updateEnvironment360(content: content)
            updateRealityView(content: content, attachments: attachments)
        } attachments: {
            Attachment(id: "controls") { topControlsBar }
            Attachment(id: "inputOverlay") { inputCaptureAttachment }
            Attachment(id: "swapConfirm") { swapConfirmAttachment }
            Attachment(id: "sbsConfirm") { sbsConfirmAttachment }
            Attachment(id: "disconnectConfirm") { disconnectConfirmAttachment }
            Attachment(id: "envPicker") { environmentPickerAttachment }
            Attachment(id: "dimPicker") { dimmingPickerAttachment }
            Attachment(id: "stats") { statsAttachment }
            Attachment(id: "tutorial") { tutorialAttachment }
            Attachment(id: "presetPopup") {
                if showInlinePresetOverlay {
                    CenterPresetPopup(text: presetOverlayText, icon: presetOverlayIcon)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "coopJoinNotification") {
                if coopCoordinator.friendJoinedNotification {
                    CenterPresetPopup(text: "Guest Joined!", icon: "person.badge.plus.fill")
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "coopDisconnectNotification") {
                if coopCoordinator.disconnectNotification {
                    CenterPresetPopup(text: coopCoordinator.disconnectMessage, icon: "person.badge.minus.fill")
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "coopConnectingOverlay") {
                // Show for co-op guests while waiting for video stream
                if viewModel.isCoopSession &&
                   viewModel.assignedControllerSlot == 1 &&
                   viewModel.streamState == .starting {
                    CoopConnectingPopup()
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "keyboardTextField") {
                if showVirtualKeyboard {
                    TextField("", text: $keyboardInput)
                        .focused($isKeyboardFocused)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(width: 180)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        )
                        .onAppear {
                            // Force focus when TextField appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isKeyboardFocused = true
                            }
                        }
                        .onSubmit {
                            // When user hits return, send Return key to PC, then close keyboard
                            print("[Keyboard] Submit detected, sending Return key and closing keyboard")
                            
                            // Send Return key (keycode 0x0D = 13)
                            LiSendKeyboardEvent(0x0D, 0x03, 0)  // Key down
                            usleep(50 * 1000)
                            LiSendKeyboardEvent(0x0D, 0x04, 0)  // Key up
                            
                            showVirtualKeyboard = false
                            isKeyboardFocused = false
                            keyboardInput = ""
                            previousKeyboardInput = ""
                        }
                        .onChange(of: keyboardInput) { oldValue, newValue in
                            handleKeyboardInput(newValue)
                        }
                        .onChange(of: isKeyboardFocused) { oldValue, newValue in
                            if !newValue && showVirtualKeyboard {
                                print("[Keyboard] Focus lost, closing keyboard")
                                showVirtualKeyboard = false
                                keyboardInput = ""
                                previousKeyboardInput = ""
                            }
                        }
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "micButton") {
                if viewModel.streamSettings.showMicButton {
                    FloatingMicButton()
                        .frame(width: 200, height: 80)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
        }
        .upperLimbVisibility(shouldHideHands ? .hidden : .automatic)
        // Unified drag handles both Screen Move and Gaze Drag to prevent conflicts
        // Magnify and drag run simultaneously to allow pinch-to-zoom
        .gesture(magnifyGesture.simultaneously(with: unifiedDragGesture))
        // NOTE: gazeTapGesture disabled - DragGesture(minimumDistance: 0) handles all pinch
        // interactions including quick taps. Having both gestures causes conflicts.
        // .gesture(gazeTapGesture, isEnabled: inputMode == .gazeControl)
        .onTapGesture {
            guard viewModel.activelyStreaming && !showMenuPanel && !showSwapConfirm && !showDisconnectConfirm && !showCurvedTutorial else { return }
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
    private var disconnectConfirmAttachment: some View {
        if showDisconnectConfirm {
            let brandRed = Color(red: 0.9, green: 0.3, blue: 0.3)
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandRed, brandRed.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: brandRed.opacity(0.4), radius: 12, x: 0, y: 8)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Leave Co-op Session?")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("This will disconnect you from the session and end the stream.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 12) {
                    Button {
                        showDisconnectConfirm = false
                        Task { @MainActor in
                            // userDidRequestDisconnect handles quit request + co-op cleanup + endSession
                            viewModel.userDidRequestDisconnect()
                            openWindow(id: "mainView")
                            await dismissImmersiveSpace()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text("Leave Session")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [brandRed, brandRed.opacity(0.85)],
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
                        .shadow(color: brandRed.opacity(0.35), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDisconnectConfirm = false
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
        
       
        print("[CurvedDisplay] Re-initializing ControllerSupport with slotOffset: \(streamConfig.controllerSlotOffset)")
        self.controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
        connectionCallbacks.controllerSupport = self.controllerSupport
        
        hasPerformedTeardown = false
        renderGateOpen = true
        
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
        
        // Initialize input mode from user preference
        let defaultMode = UserDefaults.standard.integer(forKey: "curved.defaultControlMode")
        inputMode = InputMode(rawValue: defaultMode) ?? .gazeControl
        print("[CurvedDisplay] Initialized input mode from settings: \(inputMode.displayName)")
        
        // Initialize gaze controller with stream config
        gazeController.streamConfig = streamConfig
        
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
            ensureHDRTextureMatchesSetting()
        }
        
        if let sceneID = UIApplication.shared.connectedScenes.first?.session.persistentIdentifier {
            self.immersiveSpaceSceneID = sceneID
        }
        
        restoreSavedTransform()
        // Force unlock - lock feature is not currently implemented in UI
        self.isLocked = false
        UserDefaults.standard.set(false, forKey: kCurvedLockedKey)
        
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
        stopReactiveLerp()
        
        if !hasPerformedTeardown {
            performCompleteTeardown()
        }
        saveCurrentTransform()
    }
    
    // MARK: - onChange Handlers

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
    
    /// Unified drag gesture to prevent conflict between Screen Move and Gaze Control
    /// Both modes use drag, so we combine them into a single gesture that routes based on inputMode
    var unifiedDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)  // 0 for instant gaze response
            .targetedToEntity(screen)
            .onChanged { value in
                // DISPATCHER: Route logic based on active mode
                switch inputMode {
                case .screenMove:
                    // --- SCREEN MOVE LOGIC ---
                    guard !hideControls else { return }
                    hideTimer?.invalidate()
                    if startDragPosition == nil { startDragPosition = screenPosition }
                    let translation = value.convert(value.translation3D, from: .local, to: .scene)
                    var proposed = startDragPosition! + simd_float3(translation.x, translation.y, translation.z)
                    proposed.x = min(max(proposed.x, -allowedLateralMax), allowedLateralMax)
                    screenPosition = proposed
                    lastDragTime = CACurrentMediaTime()
                    
                case .gazeControl:
                    // --- GAZE CONTROL LOGIC ---
                    // Check if using Touch mode (hand drag) or Gaze mode (eye tracking)
                    if viewModel.streamSettings.curvedGazeUseTouchMode {
                        // TOUCH MODE: Relative mouse movement (trackpad style)
                        let worldPos = value.convert(value.location3D, from: .local, to: .scene)
                        if !gazeController.pinchActive {
                            gazeController.onTouchDragBegan(at: worldPos)
                        } else {
                            gazeController.onTouchDragChanged(at: worldPos)
                        }
                    } else {
                        // GAZE MODE: Eye tracking (current implementation)
                        let uv = hitToUV(value)
                        if !gazeController.pinchActive {
                            gazeController.onPinchBegan(at: uv)
                        } else {
                            gazeController.onPinchChanged(at: uv)
                        }
                    }
                    
                case .controller:
                    break  // Let input fall through to InputCaptureView
                }
            }
            .onEnded { _ in
                // CLEANUP DISPATCHER
                switch inputMode {
                case .screenMove:
                    startDragPosition = nil
                    controlsHighlighted = false
                    startHighlightTimer()
                    
                case .gazeControl:
                    // Always cleanup gaze state
                    if gazeController.pinchActive {
                        if viewModel.streamSettings.curvedGazeUseTouchMode {
                            gazeController.onTouchDragEnded()
                        } else {
                            gazeController.onPinchEnded()
                        }
                    }
                    
                case .controller:
                    break
                }
            }
    }
    
    var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(screen)
            .onChanged { value in
                // Allow screen scaling when controls are visible
                guard !hideControls else { return }
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
                controlsHighlighted = false
                startHighlightTimer()
            }
    }
    
    // MARK: - Gaze Control Gestures
    
    var gazeTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(screen)
            .onEnded { value in
                guard inputMode == .gazeControl else {
                    print("[Gaze] Tap ignored - not in gaze control mode (current: \(inputMode))")
                    return
                }
                let uv = hitToUV(value)
                print("[Gaze] Tap detected at UV: \(uv)")
                gazeController.onPinchBegan(at: uv)
                gazeController.onPinchEnded()
            }
    }
    
   
   
    
    // MARK: - "World Space" Gaze Calculation
    // Bypasses local coordinate glitches by calculating vector projection in absolute room space.
    
    private func hitToUV(_ value: EntityTargetValue<SpatialTapGesture.Value>) -> SIMD2<Float> {
        // 1. Get Touch in World Space
        // We bypass local coordinate confusion entirely.
        let touchWorld = value.convert(value.location3D, from: .local, to: .scene)
        
        return calculateUV(touchWorld: touchWorld)
    }

    private func hitToUV(_ value: EntityTargetValue<DragGesture.Value>) -> SIMD2<Float> {
        // 1. Get Touch in World Space
        // We bypass local coordinate confusion entirely.
        let touchWorld = value.convert(value.location3D, from: .local, to: .scene)
        
        return calculateUV(touchWorld: touchWorld)
    }
    
    private func calculateUV(touchWorld: SIMD3<Float>) -> SIMD2<Float> {
        // 1. GET SCREEN BASIS VECTORS (Orientation)
        // This handles rotation/tilt.
        let screenTransform = screen.transformMatrix(relativeTo: nil)
        let rightDir = simd_normalize(SIMD3<Float>(screenTransform.columns.0.x, screenTransform.columns.0.y, screenTransform.columns.0.z))
        let upDir    = simd_normalize(SIMD3<Float>(screenTransform.columns.1.x, screenTransform.columns.1.y, screenTransform.columns.1.z))
        let center   = SIMD3<Float>(screenTransform.columns.3.x, screenTransform.columns.3.y, screenTransform.columns.3.z)
        
        // 2. PROJECT TOUCH (Get Distance in Meters)
        let delta = touchWorld - center
        let meterX = simd_dot(delta, rightDir) // e.g., 4.0 meters
        let meterY = simd_dot(delta, upDir)
        
       
        let globalScale = screen.scale(relativeTo: nil).x
        let safeScale = globalScale > 0 ? globalScale : 1.0
        
    
        let baseWidth = CURVED_MAX_WIDTH_METERS // 2.0
        let physicalWidth = baseWidth * safeScale
        let physicalHeight = physicalWidth * screenAspect
        
       
        let curveMagnitude = curvaturePreset.value * curveAnimationMultiplier
        let maxAngle = CURVED_MAX_ANGLE
        let currentAngle = maxAngle * max(0.0, min(curveMagnitude, 2.0))
        
        var u: Float = 0.5
        
      
        if currentAngle < 0.001 {
            // Flat Mode
            u = (meterX / physicalWidth) + 0.5
        } else {
           
            let scaledRadius = physicalWidth / currentAngle
            let maxTheoreticalX = scaledRadius * sin(currentAngle / 2.0)
            
            let clampedX = max(-maxTheoreticalX, min(maxTheoreticalX, meterX))
            let theta = asin(clampedX / scaledRadius)
            
            u = (theta / currentAngle) + 0.5
        }

      
        let v = 0.5 - (meterY / physicalHeight) - GAZE_VERTICAL_OFFSET
        
        
        let offsetX = Float(viewModel.streamSettings.gazeCursorOffsetX) / Float(streamConfig.width)
        let offsetY = -Float(viewModel.streamSettings.gazeCursorOffsetY) / Float(streamConfig.height)
        
        let calibratedU = u + offsetX
        let calibratedV = v + offsetY
        
        return SIMD2<Float>(
            max(0, min(1, calibratedU)),
            max(0, min(1, calibratedV))
        )
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
                isControllerMode: inputMode == .controller,
                curvature: curvaturePreset.value * curveAnimationMultiplier,
                streamConfig: streamConfig,
                headStorage: headStorage
            )
            .frame(width: 1920, height: 1920 / CGFloat(screenAspect))
            .opacity(0.01)
            // Input Mode handling:
            // - Controller mode: allowsHitTesting(true) → Controller works
            // - Other modes: allowsHitTesting(false) → RealityKit gestures work
            .allowsHitTesting(showVirtualKeyboard || inputMode == .controller)
        }
    }

    @ViewBuilder
    private var environmentPickerAttachment: some View {
        if showEnvironmentPicker {
            EnvironmentPickerView(
                environmentSphereLevel: Binding(
                    get: { environmentSphereLevel },
                    set: { val in
                        environmentSphereLevel = val
                        // Side effects when selection changes
                        dimLevel = 0
                        environmentUSDZLevel = 0
                        withAnimation(.easeInOut(duration: 0.25)) { viewModel.streamSettings.dimPassthrough = (val != 0) }
                        updateEnvironmentState()
                        updateDimmerDomesState()
                    }
                ),
                newsetLevel: Binding(
                    get: { newsetLevel },
                    set: { val in
                        newsetLevel = val
                        // Side effects when selection changes
                        dimLevel = 0
                        environmentUSDZLevel = 0
                        withAnimation(.easeInOut(duration: 0.25)) { viewModel.streamSettings.dimPassthrough = (val != 0) }
                        updateNewsetState()
                        updateDimmerDomesState()
                    }
                ),
                isPresented: $showEnvironmentPicker,
                dimLevel: Binding(
                    get: { dimLevel },
                    set: { val in
                        dimLevel = val
                        viewModel.streamSettings.dimPassthrough = (val != 0)
                        UserDefaults.standard.set(val, forKey: "ambient.dimming.level")
                        updateDimmerDomesState()
                    }
                ),
                extraSkyboxNames: extraSkyboxNames
            )
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var dimmingPickerAttachment: some View {
        if showDimmingPicker {
            DimmingPickerView(
                dimLevel: Binding(
                    get: { dimLevel },
                    set: { val in
                        dimLevel = val
                        viewModel.streamSettings.dimPassthrough = (val != 0)
                        UserDefaults.standard.set(val, forKey: "ambient.dimming.level")
                        
                        // Don't enable dimmer if environment is active - let environment binding handle it after fade
                        if environmentDome?.isEnabled != true {
                            updateDimmerDomesState()
                        }
                        
                        // Handle Reactive modes (V1, V2, and V3)
                        if val == 2 || val == 10 || val == 13 {
                            stopMoonlightCycle()
                            startReactiveLerp()
                        } else {
                            stopMoonlightCycle()
                            stopReactiveLerp()
                        }
                    }
                ),
                isPresented: $showDimmingPicker,
                environmentSphereLevel: Binding(
                    get: { environmentSphereLevel },
                    set: { newValue in
                        environmentSphereLevel = newValue
                        
                        // If disabling environment while dimming is active, wait for fade before enabling dimmer
                        if newValue == 0 && dimLevel != 0 {
                            updateEnvironmentState()
                            
                            // Wait for environment fade to complete (0.5s + small buffer)
                            Task {
                                try? await Task.sleep(for: .milliseconds(600))
                                await MainActor.run {
                                    updateDimmerDomesState()
                                }
                            }
                        } else {
                            updateEnvironmentState()
                        }
                    }
                ),
                newsetLevel: Binding(
                    get: { newsetLevel },
                    set: { newValue in
                        newsetLevel = newValue
                        updateNewsetState()
                    }
                )
            )
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }

    private func handleKeyboardInput(_ newValue: String) {
        let oldValue = previousKeyboardInput
        
        if newValue.count > oldValue.count {
            // Character(s) added - send the new characters
            let newChars = String(newValue.suffix(newValue.count - oldValue.count))
            for char in newChars {
                let text = String(char)
                let cString = text.cString(using: .utf8)
                cString?.withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        LiSendUtf8TextEvent(base, UInt32(text.utf8.count))
                    }
                }
            }
        } else if newValue.count < oldValue.count {
            // Character(s) removed - send backspace for each removed character
            let removedCount = oldValue.count - newValue.count
            for _ in 0..<removedCount {
                LiSendKeyboardEvent(0x08, 0x03, 0) // Backspace Down
                usleep(50 * 1000)
                LiSendKeyboardEvent(0x08, 0x04, 0) // Backspace Up
            }
        }
        
        // Update previous value for next comparison
        previousKeyboardInput = newValue
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
    
    var topControlsBar: some View {
        HStack(spacing: 16) {
            // 1. Home
            LongPressControlBtn(
                label: "Home",
                systemImage: "house.fill",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
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
                },
                longPressAction: {
                    handleWindowClose()
                }
            )

            // 2. Spatial Audio
            LongPressControlBtn(
                label: spatialAudioMode ? "Spatial Audio" : "Direct Audio",
                systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                spatialAudioMode.toggle()
                fixAudioForCurrentMode()
                presetOverlayText = spatialAudioMode ? "Audio: Spatial" : "Audio: Stereo"
                presetOverlayIcon = spatialAudioMode ? "person.spatialaudio.fill" : "headphones"
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                },
                longPressAction: {
                    fixAudioForCurrentMode()
                }
            )

            // 3. Curvature
            LongPressControlBtn(
                label: curvaturePreset.displayName,
                systemImage: curvaturePreset.icon,
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                curvaturePreset = curvaturePreset.next()
                presetOverlayText = curvatureText(for: curvaturePreset.displayName)
                presetOverlayIcon = curvaturePreset.icon
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                    startHideTimer()
                },
                longPressAction: {
                    curvaturePreset = .curved
                    presetOverlayText = curvatureText(for: curvaturePreset.displayName)
                    presetOverlayIcon = curvaturePreset.icon
                    showInlinePresetOverlay = true
                    
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            showInlinePresetOverlay = false
                        }
                    }
                }
            )

            // 4. Tilt
            LongPressControlBtn(
                label: "\(Int(tiltAngle))°",
                systemImage: "bed.double.fill",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                cycleTiltAngle()
                presetOverlayText = "TILT: \(Int(tiltAngle))°"
                presetOverlayIcon = "bed.double.fill"
                showInlinePresetOverlay = true
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                    startHideTimer()
                },
                longPressAction: {
                    tiltAngle = 0.0
                    presetOverlayText = "TILT: \(Int(tiltAngle))°"
                    presetOverlayIcon = "bed.double.fill"
                    showInlinePresetOverlay = true
                    
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            showInlinePresetOverlay = false
                        }
                    }
                }
            )

            // 5. Dim
            LongPressControlBtn(
                label: dimButtonTitle,
                systemImage: dimButtonIcon,
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                // Short press: toggle dimming picker
                showDimmingPicker.toggle()
                if showDimmingPicker {
                    // Close environment picker if it's open
                    showEnvironmentPicker = false
                    stopMoonlightCycle()
                    stopReactiveLerp()
                }
                },
                longPressAction: {
                    // Long press: reset to Off
                    dimLevel = 0
                    viewModel.streamSettings.dimPassthrough = false
                    updateDimmerDomesState()
                    stopMoonlightCycle()
                    stopReactiveLerp()
                    showDimPresetOverlay()
                }
            )

            // 6. Preset
            makeControlButton(label: "Preset", systemImage: "camera.filters") {
                guard canChangePreset() else {
                    print("[CurvedDisplay] Preset change on cooldown, ignoring")
                    return
                }
                
                let allowed: [Int32] = [0, 1, 2, 3]
                let cur = viewModel.streamSettings.uikitPreset
                let idx = allowed.firstIndex(of: cur) ?? 0
                let next = allowed[(idx + 1) % allowed.count]
                viewModel.streamSettings.uikitPreset = next
                applyCurvedUIKitPreset(next)
                
                presetCooldownUntil = Date().addingTimeInterval(0.3)
                
                presetOverlayText = presetName(for: next)
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

            // 8. Sphere Environment (Picker)
            LongPressControlBtn(
                label: environmentSphereButtonTitle,
                systemImage: "photo",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                    // Toggle the picker overlay
                    showEnvironmentPicker.toggle()

                    // If opening, ensure dimming logic is correct
                    if showEnvironmentPicker {
                        // Close dimming picker if it's open
                        showDimmingPicker = false
                        // Stop cycling/lerping if it was running
                        stopMoonlightCycle()
                        stopReactiveLerp()
                    }
                    
                    startHideTimer()
                },
                longPressAction: {
                    // Long press still clears the environment
                    environmentSphereLevel = 0
                    newsetLevel = 0
                    showEnvironmentPicker = false
                    updateEnvironmentState()
                    updateNewsetState()
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.streamSettings.dimPassthrough = false }
                }
            )

            // 9. Stats
            makeControlButton(label: viewModel.streamSettings.statsOverlay ? "Hide Stats" : "Show Stats", systemImage: "wifi") {
                viewModel.streamSettings.statsOverlay.toggle()
            }
            
            // 10. Keyboard Toggle
            makeControlButton(
                label: showVirtualKeyboard ? "Hide Keyboard" : "Show Keyboard",
                systemImage: showVirtualKeyboard ? "keyboard.fill" : "keyboard"
            ) {
                // If opening keyboard while in controller mode, automatically switch to screen adjust mode
                if inputMode == .controller && !showVirtualKeyboard {
                    print("[Keyboard] Auto-switching from Controller Mode to Screen Adjust Mode for keyboard")
                    gazeController.cleanup()
                    inputMode = .screenMove
                    updateScreenInteractivity()
                    
                    presetOverlayText = "Switched to Screen Adjust Mode"
                    presetOverlayIcon = "arrow.up.and.down.and.arrow.left.and.right"
                    showInlinePresetOverlay = true
                    
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            showInlinePresetOverlay = false
                        }
                    }
                }
                
                showVirtualKeyboard.toggle()
                
                // Delay focus to ensure TextField is rendered
                if showVirtualKeyboard {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isKeyboardFocused = true
                    }
                } else {
                    isKeyboardFocused = false
                }
                
                print("[Keyboard] Toggle pressed, showVirtualKeyboard is now: \(showVirtualKeyboard)")
                startHighlightTimer()
            }
            
            // 11. Input Mode Toggle (Screen Adjust / Controller / Gaze Control)
            makeControlButton(
                label: {
                    // Use Touch label if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "Touch Control Mode"
                    }
                    return inputMode.displayName
                }(),
                systemImage: {
                    // Use Touch icon if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "hand.point.up.left.fill"
                    }
                    return inputMode.icon
                }()
            ) {
                gazeController.cleanup()  // Reset gaze state on mode change
                inputMode = inputMode.next()
                print("[InputMode] Changed to: \(inputMode) (\(inputMode.displayName))")
                
                // CRITICAL FIX: When switching to Controller mode, ensure keyboard is closed
                // and first responder is properly reclaimed for controller input
                if inputMode == .controller {
                    showVirtualKeyboard = false
                    isKeyboardFocused = false
                    print("[InputMode] Switched to Controller mode - keyboard closed, first responder will be reclaimed")
                    
                    // Force first responder reclaim after a brief delay to ensure TextField releases it
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // The InputCaptureUIView timer will reclaim first responder
                        print("[InputMode] Controller mode delay complete - first responder should be active")
                    }
                }
                
                // Update gaze controller with current stream config
                if inputMode == .gazeControl {
                    gazeController.streamConfig = streamConfig
                }
                
                presetOverlayText = {
                    // Use Touch label if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "Touch Control Mode"
                    }
                    return inputMode.displayName
                }()
                presetOverlayIcon = {
                    // Use Touch icon if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "hand.point.up.left.fill"
                    }
                    return inputMode.icon
                }()
                showInlinePresetOverlay = true

                // Update gaze controller with current stream config
                gazeController.streamConfig = streamConfig
                print("[InputMode] GazeController streamConfig set: \(streamConfig != nil)")
                
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        showInlinePresetOverlay = false
                    }
                }
                startHighlightTimer()
            }
            
            // 11. Co-op Indicator (if in co-op session)
            if viewModel.isCoopSession {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("2P")
                        .font(.system(size: 14, weight: .bold))
                    
                    // Participant counter
                    let coordinator = CoopSessionCoordinator.shared
                    let participantCount = coordinator.participants.count
                    Text("(\(participantCount)/2)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.3))
                )
            }
            
            // 12. Co-op Invite Button (only when hosting and guest is missing)
            if viewModel.isCoopSession {
                let coordinator = CoopSessionCoordinator.shared
                if coordinator.isHosting && coordinator.participants.count < 2 {
                    coopInviteButton
                }
            }
            
            // 13. Co-op Disconnect Button (always show when in co-op)
            if viewModel.isCoopSession {
                coopDisconnectButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                // Dynamic background opacity: different values for black modes vs reactive
                .opacity(!hideControls ? 0.7 : (dimLevel == 4 || dimLevel == 12 ? 0.005 : (dimLevel == 10 ? 0.015 : 0.0)))
        }
        // Dynamic opacity floor: lower for black modes (Eclipse, Starfield), slightly higher for Reactive V2/V3
        .opacity(!hideControls ? (controlsHighlighted ? 1.0 : 0.5) : (dimLevel == 4 || dimLevel == 12 ? 0.005 : (dimLevel == 10 ? 0.015 : 0.05)))
        .animation(Animation.easeInOut(duration: 0.35), value: controlsHighlighted)
        .animation(Animation.easeInOut(duration: 0.35), value: hideControls)
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
            // Keep controlsHighlighted = true during action execution
            // This prevents state flicker that breaks drag gesture recognition
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
    
    private var coopInviteButton: some View {
        Button {
            if !controlsHighlighted {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            
            // Create a fresh activity with a new session ID and broadcast it.
            // We can't just re-activate the existing activity because the guest
            // already leave()'d that session -- SharePlay won't let them re-join it.
            // A fresh session ID forces a new GroupSession object on the guest side.
            let coordinator = CoopSessionCoordinator.shared
            Task {
                await coordinator.reInviteGuest()
            }
            
            // Show "Sent" feedback for 3 seconds
            inviteButtonSent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                inviteButtonSent = false
            }
            
            startHideTimer()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: inviteButtonSent ? "checkmark" : "paperplane")
                    .font(.system(size: 14, weight: .medium))
                Text(inviteButtonSent ? "Sent" : "Invite")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.clear))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: inviteButtonSent)
    }
    
    private var coopDisconnectButton: some View {
        Button {
            if !controlsHighlighted {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            
            showDisconnectConfirm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                Text("Leave")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.clear))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dimButtonTitle: String {
        switch dimLevel {
        case 0: "Dimming Off"
        case 1: "Night"
        case 2: "Reactive V1"
        case 4: "Eclipse"
        case 5: "Midnight"
        case 6: "Twilight"
        case 7: "Dawn"
        case 8: "Sunrise"
        case 9: "Woodland"
        case 10: "Reactive V2"
        case 12: "Starfield"
        case 14: "Desert"
        default: "Dimming Off"
        }
    }

    private var dimButtonIcon: String {
        "lightbulb.fill"
    }
    
    private var environmentSphereButtonTitle: String {
        if environmentSphereLevel == 0 { return "Environment Off" }
        let builtinNames = SkyboxCatalog.builtinNames
        let idx = environmentSphereLevel - 1
        if idx < builtinNames.count {
            let id = builtinNames[idx]
            return SkyboxCatalog.displayNames[id] ?? id.uppercased()
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
    
    private var shouldHideHands: Bool {
        environmentSphereLevel > 0 && viewModel.streamSettings.hideHandsIn360Environment
    }
    
    private var newsetButtonTitle: String {
        if newsetLevel == 0 { return "Newset Off" }
        let idx = newsetLevel - 1
        let newsetNames = SkyboxCatalog.newsetNames
        let name = newsetNames[idx]
        return name.uppercased()
    }

    private func nextNewsetLevel(from current: Int) -> Int {
        let total = SkyboxCatalog.newsetNames.count
        if total <= 0 { return 0 }
        if current >= total { return 0 }
        return current + 1
    }

    private func nextEnvironmentLevel(from current: Int) -> Int {
        let total = SkyboxCatalog.builtinNames.count + extraSkyboxNames.count
        if total <= 0 { return 0 }
        if current >= total { return 0 }
        return current + 1
    }
    
    private func nextDimLevel(from current: Int) -> Int {
        let order = [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 12]
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
                params.saturation = 1.05
                params.contrast = 1.005
                params.brightness = 0.0
            case 2:
                hdrParams.mode = 1
                params.boost = 1.05
                params.saturation = 1.15
                params.contrast = 1.01
                params.brightness = 0.0
            case 3:
                hdrParams.mode = 2
                params.boost = 0.99
                params.saturation = 0.87
                params.contrast = 1.005
                params.brightness = 0.01
            default:
                hdrParams.mode = 1
                params.boost = 1.00
                params.saturation = 1.00
                params.contrast = 1.00
                params.brightness = 0.00
            }
            let hrBoost = hdrHeadroomBoost()
            params.boost = Swift.min(Swift.max(params.boost * hrBoost, 1.0), 1.50)
            params.contrast = Swift.min(Swift.max(params.contrast, 1.00), 1.20)
            params.saturation = Swift.min(Swift.max(params.saturation, 0.85), 1.15)
            params.brightness = 0.0
        } else {
            switch preset {
            case 1:
                params.boost = 0.98
                params.saturation = 1.05
                params.contrast = 1.002
                params.brightness = 0.0
                params.mode = 1
            case 2:
                params.boost = 1.05
                params.saturation = 1.15
                params.contrast = 1.005
                params.brightness = 0.0
                params.mode = 1
            case 3:
                params.boost = 1.02
                params.saturation = 0.90
                params.contrast = 1.005
                params.brightness = 0.0
                params.mode = 1
            default:
                params.boost = 1.00
                params.saturation = 1.00
                params.contrast = 1.00
                params.brightness = 0.00
                params.mode = 0
            }
        }
        safeHDRSettings.value = params
        
        // HDR params are applied via hdrSettingsProvider on every frame - no IDR needed

    }

    private func hdrHeadroomBoost() -> Float { 1.40 }

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
            params.boost = Swift.min(Swift.max(params.boost * hrBoost, 1.0), 1.50)
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

    // MARK: - Debug Calibration
    
    /// Adds colored spheres at known UV positions for calibration
    private func addDebugCalibrationSpheres(to parent: Entity) {
        let sphereRadius: Float = 0.02  // 2cm spheres
        
        // Dynamic Z offset based on curvature (less offset for extreme curves)
        let currentCurveMagnitude = curvaturePreset.value * curveAnimationMultiplier
        let zOffset: Float = 0.05 * (1.0 - currentCurveMagnitude * 0.5)  // Reduced at high curvature
        
        // Standard calibration positions (disabled by default)
        let calibrationPoints: [(SIMD2<Float>, UIColor, String)] = [
            (SIMD2(0.15, 0.15), .red, "TOP-LEFT"),
            (SIMD2(0.85, 0.15), .green, "TOP-RIGHT"),
            (SIMD2(0.5, 0.5), .blue, "CENTER"),
            (SIMD2(0.15, 0.85), .yellow, "BOTTOM-LEFT"),
            (SIMD2(0.85, 0.85), .magenta, "BOTTOM-RIGHT")
        ]
        
        for (uv, color, name) in calibrationPoints {
            // Convert UV to 3D position on curved mesh
            let position3D = uvTo3DPosition(uv: uv)
            
            // Create sphere
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: sphereRadius),
                materials: [UnlitMaterial(color: color)]
            )
            
            sphere.position = position3D + SIMD3(0, 0, zOffset)
            sphere.name = "DEBUG_\(name)"
            
            parent.addChild(sphere)
            
            print("[DEBUG] Added \(name) sphere at UV \(uv) → 3D position \(position3D)")
        }
    }
    
    /// Convert UV coordinates (0-1) to 3D position on the curved mesh (in mesh-local space)
    private func uvTo3DPosition(uv: SIMD2<Float>) -> SIMD3<Float> {
        let width = CURVED_MAX_WIDTH_METERS
        let height = width * screenAspect
        let curveMagnitude = curvaturePreset.value * curveAnimationMultiplier
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))
        
        // Convert UV to mesh coordinates
        // U: 0 = left edge, 1 = right edge
        // V: 0 = top edge, 1 = bottom edge
        
        var x: Float
        var z: Float
        
        if currentAngle < 0.0001 {
            // Flat mode
            x = (uv.x - 0.5) * width
            z = 0
        } else {
            // Curved mode
            let radius = width / currentAngle
            let theta = (uv.x - 0.5) * currentAngle
            
            x = radius * sin(theta)
            z = radius * (1.0 - cos(theta))
        }
        
        // Y is straightforward (flipped because V=0 is top)
        let y = (0.5 - uv.y) * height
        
        return SIMD3(x, y, z)
    }

    // MARK: - RealityView Setup

    func setupRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        // Safe mesh generation with fallback
        let mesh: MeshResource
        do {
            mesh = try generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (512, 512),
                curveMagnitude: curvaturePreset.value * curveAnimationMultiplier,
                cornerRadiusFraction: cornerRadiusFraction
            )
        } catch {
            print("⚠️ Failed to generate curved mesh: \(error). Using flat fallback.")
            mesh = .generatePlane(width: CURVED_MAX_WIDTH_METERS, height: CURVED_MAX_WIDTH_METERS * screenAspect)
        }
        
        if videoMode == .standard2D {
            screen = ModelEntity(mesh: mesh, materials: [UnlitMaterial(texture: texture)])
        } else {
            let material = UnlitMaterial(texture: texture)
            screen = ModelEntity(mesh: mesh, materials: [material])
        }

        // Generate curved collision mesh that matches visual geometry
        let collisionMesh: MeshResource
        do {
            collisionMesh = try generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (256, 256),
                curveMagnitude: curvaturePreset.value * curveAnimationMultiplier,
                cornerRadiusFraction: 0
            )
        } catch {
            print("⚠️ Failed to generate collision mesh: \(error). Using flat fallback.")
            collisionMesh = .generatePlane(width: CURVED_MAX_WIDTH_METERS, height: CURVED_MAX_WIDTH_METERS * screenAspect)
        }
        
        Task {
            if let collisionShape = try? await ShapeResource.generateStaticMesh(from: collisionMesh) {
                await MainActor.run {
                    screen.components.set(CollisionComponent(
                        shapes: [collisionShape],
                        filter: CollisionFilter(
                            group: .screenEntity,
                            mask: .all
                        )
                    ))
                }
            }
        }
        
        screen.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        screen.position = SIMD3<Float>(0, 0, -1.5)
        
        content.add(screen)
        
        // DEBUG: Spheres disabled - using corner gaze calibration instead
        // addDebugCalibrationSpheres(to: screen)

        let head = AnchorEntity(.head)
        content.add(head)
        self.headAnchor = head

        if !hasInitializedPosition {
            screen.position = SIMD3<Float>(0.0, 1.5, -5.0)
            hasInitializedPosition = true
            screenPosition = screen.position
            screenScale = 4.0
        }
        
        if let controls = attachments.entity(for: "controls") {
            self.controlsEntity = controls
            if controls.parent !== screen { screen.addChild(controls) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            // Restore controls to original 0.05 position
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
        
        // Co-op join notification (centered, same as presetPopup)
        if let joinEnt = attachments.entity(for: "coopJoinNotification") {
            if joinEnt.parent !== screen { screen.addChild(joinEnt) }
            joinEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = joinEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(joinEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                joinEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op disconnect notification (centered, same as presetPopup)
        if let disconnectEnt = attachments.entity(for: "coopDisconnectNotification") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            disconnectEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = disconnectEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                disconnectEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op connecting overlay (centered, same as presetPopup)
        if let connectingEnt = attachments.entity(for: "coopConnectingOverlay") {
            if connectingEnt.parent !== screen { screen.addChild(connectingEnt) }
            connectingEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = connectingEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(connectingEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                connectingEnt.scale = [scale, scale, scale]
            }
        }
        
        // Keyboard TextField - positioned below screen, centered
        if let keyboardEnt = attachments.entity(for: "keyboardTextField") {
            if keyboardEnt.parent !== screen { screen.addChild(keyboardEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below screen - if mic button is showing, keyboard goes above it
            let keyboardOffset: Float = viewModel.streamSettings.showMicButton ? 0.16 : 0.08
            keyboardEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(keyboardOffset), Float(0.05)]
            
            let bounds = keyboardEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(keyboardEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                keyboardEnt.scale = [scale, scale, scale]
            }
        }
        
        // Mic Button - positioned below keyboard (if keyboard is showing) or below screen
        if let micEnt = attachments.entity(for: "micButton") {
            if micEnt.parent !== screen { screen.addChild(micEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below keyboard if keyboard is showing, otherwise below screen
            let micOffset: Float = showVirtualKeyboard ? 0.24 : 0.08
            micEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(micOffset), Float(0.05)]

            let bounds = micEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(micEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.30
                let scale = desiredLocalWidth / unscaledWidth
                micEnt.scale = [scale, scale, scale]
            }
        }
    }

    func updateRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        let currentCurve = curvaturePreset.value * curveAnimationMultiplier
        
        // OPTIMIZATION: Only regenerate mesh if curve or aspect ratio changed significantly
        let needsMeshUpdate: Bool
        if let lastCurve = lastGeneratedCurve, let lastAspect = lastGeneratedAspect {
            needsMeshUpdate = abs(currentCurve - lastCurve) > 0.001 || abs(screenAspect - lastAspect) > 0.001
        } else {
            needsMeshUpdate = true
        }
        
        if needsMeshUpdate {
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
                
                // Also update collision mesh for accurate gaze hit detection
                if let collisionMesh = try? generateCurvedRoundedPlane(
                    width: CURVED_MAX_WIDTH_METERS,
                    aspectRatio: screenAspect,
                    resolution: (256, 256),
                    curveMagnitude: currentCurve,
                    cornerRadiusFraction: 0
                ) {
                    Task {
                        if let collisionShape = try? await ShapeResource.generateStaticMesh(from: collisionMesh) {
                            await MainActor.run {
                                self.screen.components.set(CollisionComponent(
                                    shapes: [collisionShape],
                                    filter: CollisionFilter(
                                        group: .screenEntity,
                                        mask: .all
                                    )
                                ))
                            }
                        }
                    }
                    
                    // Update trackers
                    DispatchQueue.main.async {
                        self.lastGeneratedCurve = currentCurve
                        self.lastGeneratedAspect = self.screenAspect
                    }
                }
            }
        }
        
        screen.scale = [screenScale, screenScale, screenScale]
        screen.position = screenPosition
        let tiltRadians = tiltAngle * .pi / 180.0
        let tiltRotation = simd_quatf(angle: tiltRadians, axis: SIMD3<Float>(1, 0, 0))
        screen.transform.rotation = tiltRotation
        
        if let head = headAnchor {
            let p = head.position(relativeTo: nil)
            
            // UPDATE: Efficiently feed head position to the input system
            // This is "lazy" - we push the data, but SwiftUI doesn't redraw
            // We need head relative to the screen
            let localHead = screen.convert(position: .zero, from: head)
            headStorage.positionInScreenSpace = localHead
            
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
            // Keep input overlay just in front of the screen to avoid blocking controls
            inputEnt.position = [0.0 as Float, 0.0 as Float, Float(0.01)]
            
            let bounds = inputEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(inputEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = CURVED_MAX_WIDTH_METERS * 1.05
                let scale = desiredLocalWidth / unscaledWidth
                inputEnt.scale = [scale, scale, scale]
            }
        }
        
        if let pickerEnt = attachments.entity(for: "envPicker") {
            if pickerEnt.parent !== screen { screen.addChild(pickerEnt) }
            pickerEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            
            let bounds = pickerEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(pickerEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.96
                let scale = desiredLocalWidth / unscaledWidth
                pickerEnt.scale = [scale, scale, scale]
            }
        }
        
        if let dimPickerEnt = attachments.entity(for: "dimPicker") {
            if dimPickerEnt.parent !== screen { screen.addChild(dimPickerEnt) }
            dimPickerEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            
            let bounds = dimPickerEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(dimPickerEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.96
                let scale = desiredLocalWidth / unscaledWidth
                dimPickerEnt.scale = [scale, scale, scale]
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
        
        // Co-op join notification (centered, same as presetPopup)
        if let joinEnt = attachments.entity(for: "coopJoinNotification") {
            if joinEnt.parent !== screen { screen.addChild(joinEnt) }
            joinEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = joinEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(joinEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                joinEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op disconnect notification (centered, same as presetPopup)
        if let disconnectEnt = attachments.entity(for: "coopDisconnectNotification") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            disconnectEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = disconnectEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                disconnectEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op connecting overlay (centered, same as presetPopup)
        if let connectingEnt = attachments.entity(for: "coopConnectingOverlay") {
            if connectingEnt.parent !== screen { screen.addChild(connectingEnt) }
            connectingEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            
            let bounds = connectingEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(connectingEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.35
                let scale = desiredLocalWidth / unscaledWidth
                connectingEnt.scale = [scale, scale, scale]
            }
        }
        
        // Keyboard TextField - positioned below screen, centered
        if let keyboardEnt = attachments.entity(for: "keyboardTextField") {
            if keyboardEnt.parent !== screen { screen.addChild(keyboardEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below screen - if mic button is showing, keyboard goes above it
            let keyboardOffset: Float = viewModel.streamSettings.showMicButton ? 0.16 : 0.08
            keyboardEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(keyboardOffset), Float(0.05)]
            
            let bounds = keyboardEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(keyboardEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                keyboardEnt.scale = [scale, scale, scale]
            }
        }
        
        // Mic Button - positioned below keyboard (if keyboard is showing) or below screen
        if let micEnt = attachments.entity(for: "micButton") {
            if micEnt.parent !== screen { screen.addChild(micEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below keyboard if keyboard is showing, otherwise below screen
            let micOffset: Float = showVirtualKeyboard ? 0.24 : 0.08
            micEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(micOffset), Float(0.05)]

            let bounds = micEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(micEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.30
                let scale = desiredLocalWidth / unscaledWidth
                micEnt.scale = [scale, scale, scale]
            }
        }
    }

    // MARK: - Stream Management

    private func ensureStreamStartedIfNeeded() {
        startStreamIfNeeded()
    }
    
    private func startStreamIfNeeded() {
        guard streamMan == nil else {
            print("[CurvedDisplay] StreamManager already exists, skipping duplicate creation")
            needsResume = false
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.hasPerformedTeardown, self.viewModel.activelyStreaming, self.streamMan == nil else {
                print("[CurvedDisplay] Aborting stream start - Teardown: \(self.hasPerformedTeardown), Streaming: \(self.viewModel.activelyStreaming), Exists: \(self.streamMan != nil)")
                return
            }
            
            self.renderGateOpen = true
            self.firstFrameReceived = false
            self.idrWatchdogTimer1?.invalidate(); self.idrWatchdogTimer1 = nil
            self.idrWatchdogTimer2?.invalidate(); self.idrWatchdogTimer2 = nil
            self.postFirstFrameRebindTimer?.invalidate(); self.postFirstFrameRebindTimer = nil
            self.idrWatchdogTimer1 = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                if !self.firstFrameReceived { LiRequestIdrFrame() }
            }
            self.idrWatchdogTimer2 = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { _ in
                if !self.firstFrameReceived { LiRequestIdrFrame() }
            }
            
            self.ensureHDRTextureMatchesSetting()
            
            // Set controller support reference for rumble forwarding
            self.connectionCallbacks.controllerSupport = self.controllerSupport
            
            // Capture texture locally for thread-safe background access
            let localTexture = self.texture
            
            self.streamMan = StreamManager(
                config: self.streamConfig,
                rendererProvider: {
                    DrawableVideoDecoder(
                        texture: localTexture,
                        callbacks: self.connectionCallbacks,
                        aspectRatio: self.screenAspect,
                        useFramePacing: self.streamConfig.useFramePacing,
                        enableHDR: self.viewModel.streamSettings.enableHdr,
                        hdrSettingsProvider: { [safeHDRSettings] in safeHDRSettings.value },
                        enhancementsProvider: { [weak viewModel] in
                            let warmth: Float = viewModel?.streamSettings.enableHdr ?? false ? 0.03 : 0.0
                            return (1.0, 1.0, warmth)
                        },
                        callbackToRender: { textureQueue, correctedResolution in
                            guard self.renderGateOpen else { return }
                            
                            // 1. Drop frame in mailbox (Zero latency, No blocking)
                            self.frameMailbox.deposit(textureQueue)
                            
                            // 2. Dispatch UI metadata to Main Thread
                            DispatchQueue.main.async {
                                if let correctedResolution { 
                                    self.correctedResolution = correctedResolution 
                                }
                                
                                // First Frame Logic
                                if !self.firstFrameReceived {
                                    self.firstFrameReceived = true
                                    self.idrWatchdogTimer1?.invalidate(); self.idrWatchdogTimer1 = nil
                                    self.idrWatchdogTimer2?.invalidate(); self.idrWatchdogTimer2 = nil
                                    self.guestAggressiveIDRTimer?.invalidate(); self.guestAggressiveIDRTimer = nil
                                    
                                    self.postFirstFrameRebindTimer?.invalidate()
                                    self.postFirstFrameRebindTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { _ in
                                        self.rebindScreenMaterial()
                                    }
                                    
                                    self.controllerSupport?.connectionEstablished()
                                    self.startHideTimer()
                                    
                                    // FORCE UPDATE: Manually check mailbox once for the very first frame
                                    // to ensure the user sees an image immediately.
                                    if let firstFrame = self.frameMailbox.collect() {
                                        self.texture.replace(withDrawables: firstFrame)
                                    }
                                }
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
            
            // AGGRESSIVE GUEST-SIDE IDR REQUESTING
            // Co-op guests have independent streams - they must request their own IDR frames
            if self.viewModel.isCoopSession && self.viewModel.assignedControllerSlot == 1 {
                print("[CurvedDisplay] 🎮 CO-OP GUEST: Starting aggressive IDR requesting")
                var requestCount = 0
                let maxRequests = 120 // 60 seconds at 500ms intervals
                self.guestAggressiveIDRTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    requestCount += 1
                    if self.firstFrameReceived {
                        print("[CurvedDisplay] 🎮 CO-OP GUEST: First frame received! Stopping IDR requests after \(requestCount) requests")
                        timer.invalidate()
                        self.guestAggressiveIDRTimer = nil
                        return
                    }
                    if requestCount > maxRequests {
                        print("[CurvedDisplay] 🎮 CO-OP GUEST: Max IDR requests reached (\(maxRequests)), stopping")
                        timer.invalidate()
                        self.guestAggressiveIDRTimer = nil
                        return
                    }
                    print("[CurvedDisplay] 🎮 CO-OP GUEST: Requesting IDR frame #\(requestCount)")
                    LiRequestIdrFrame()
                }
            }

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
        if tiltAngle > 60.0 {
            tiltAngle = 0.0
        }
    }
    
    private func performCompleteTeardown() {
        guard !hasPerformedTeardown else { return }
        hasPerformedTeardown = true
        
        print("[CurvedDisplay] 🔴 TEARDOWN START")
        
        // CRITICAL: Close render gate BEFORE stopping stream
        renderGateOpen = false
        
        statsTimer?.invalidate()
        hideTimer?.invalidate()
        presetOverlayTimer?.invalidate()
        moonlightCycleTimer?.invalidate()
        
        idrWatchdogTimer1?.invalidate(); idrWatchdogTimer1 = nil
        idrWatchdogTimer2?.invalidate(); idrWatchdogTimer2 = nil
        postFirstFrameRebindTimer?.invalidate(); postFirstFrameRebindTimer = nil
        guestAggressiveIDRTimer?.invalidate(); guestAggressiveIDRTimer = nil
        firstFrameReceived = false
        
        controllerSupport?.cleanup()
        controllerSupport = nil
        
        // CRITICAL: Use stopStreamWithCompletion so we wait for LiStopConnection()
        // to fully finish before declaring teardown complete. Without this, a new
        // connection can start while the old one is still stopping, causing initLock
        // timeout and black screen.
        if let sm = streamMan {
            print("[CurvedDisplay] Stopping StreamManager (waiting for completion)...")
            streamMan = nil  // Clear reference now to prevent double-stop
            
            // Safety flag to ensure TEARDOWN COMPLETE fires exactly once, even if
            // both the completion callback and the safety timeout race.
            var teardownPosted = false
            let postTeardown = {
                guard !teardownPosted else { return }
                teardownPosted = true
                print("[CurvedDisplay] StreamManager stopped, clearing references")
                print("[CurvedDisplay] 🔴 TEARDOWN COMPLETE")
                NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
            }
            
            sm.stopStream(completion: {
                DispatchQueue.main.async {
                    postTeardown()
                }
            })
            
            // Safety timeout: if stopStream completion doesn't fire within 5s
            // (e.g., ENet control stream is stuck), forcibly post teardown so the
            // UI state machine isn't stuck in .stopping forever. Connection.m has
            // its own internal 10s+10s timeouts for initLock/LiStopConnection, so
            // the underlying stop will eventually complete on its own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if !teardownPosted {
                    print("[CurvedDisplay] ⚠️ StreamManager stop timed out after 5s - forcing teardown complete")
                    postTeardown()
                }
            }
        } else {
            print("[CurvedDisplay] 🔴 TEARDOWN COMPLETE (no stream to stop)")
            NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
        }
    }
    
    private func cleanupResources() {
        streamMan = nil
        controllerSupport?.cleanup()
        controllerSupport = nil
    }

    private func startEnvironmentFade(targetOpacity: Float, completion: (() -> Void)? = nil) {
        environmentFadeTimer?.invalidate()
        
        guard let dome = environmentDome else {
            completion?()
            return
        }
        
        // Ensure OpacityComponent exists
        if dome.components[OpacityComponent.self] == nil {
            dome.components.set(OpacityComponent(opacity: targetOpacity == 1.0 ? 0.0 : 1.0))
        }
        
        let startOpacity = dome.components[OpacityComponent.self]?.opacity ?? 0.0
        
        // If already close to target, just set and finish
        if abs(startOpacity - targetOpacity) < 0.01 {
            dome.components.set(OpacityComponent(opacity: targetOpacity))
            completion?()
            return
        }
        
        let duration: TimeInterval = 0.5
        let steps = 30
        let interval = duration / Double(steps)
        let stepAmount = (targetOpacity - startOpacity) / Float(steps)
        
        var currentStep = 0
        
        environmentFadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak dome] timer in
            guard let dome = dome else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let newOpacity = startOpacity + stepAmount * Float(currentStep)
            dome.components.set(OpacityComponent(opacity: newOpacity))
            
            if currentStep >= steps {
                if targetOpacity >= 1.0 {
                    // Remove OpacityComponent when fully visible to avoid interfering with controls
                    dome.components.remove(OpacityComponent.self)
                } else {
                    dome.components.set(OpacityComponent(opacity: targetOpacity))
                }
                timer.invalidate()
                // self.environmentFadeTimer = nil // Omitted to avoid self capture complexity
                completion?()
            }
        }
    }

    private func updateEnvironmentState() {
        guard let dome = environmentDome else { return }
        
        if environmentSphereLevel == 0 {
            startEnvironmentFade(targetOpacity: 0.0) {
                dome.isEnabled = false
                self.lastEnvironmentSphereLevelApplied = 0
            }
            return
        }
        
        // If already enabled, fade out first then swap
        if dome.isEnabled {
            startEnvironmentFade(targetOpacity: 0.0) {
                if let tex = self.currentSkyboxTexture() {
                    self.applySkyboxTexture(tex)
                    self.lastEnvironmentSphereLevelApplied = self.environmentSphereLevel
                    self.startEnvironmentFade(targetOpacity: 1.0)
                }
            }
            return
        }
        
        if !dome.isEnabled {
            dome.isEnabled = true
            dome.components.set(OpacityComponent(opacity: 0.0))
        }
        
        if let tex = currentSkyboxTexture() {
            applySkyboxTexture(tex)
            lastEnvironmentSphereLevelApplied = environmentSphereLevel
            startEnvironmentFade(targetOpacity: 1.0)
        }
    }
    
    private func updateNewsetState() {
        guard let dome = environmentDome else { return }
        
        if newsetLevel == 0 {
            startEnvironmentFade(targetOpacity: 0.0) {
                dome.isEnabled = false
            }
            return
        }
        
        // If already enabled, fade out first then swap
        if dome.isEnabled {
            startEnvironmentFade(targetOpacity: 0.0) {
                if let tex = self.currentNewsetTexture() {
                    self.applySkyboxTexture(tex)
                    self.startEnvironmentFade(targetOpacity: 1.0)
                }
            }
            return
        }
        
        if !dome.isEnabled {
            dome.isEnabled = true
            dome.components.set(OpacityComponent(opacity: 0.0))
        }
        
        if let tex = currentNewsetTexture() {
            applySkyboxTexture(tex)
            startEnvironmentFade(targetOpacity: 1.0)
        }
    }

    private func currentSkyboxTexture() -> TextureResource? {
        let builtinNames = SkyboxCatalog.builtinNames
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
        if idx >= 0 && idx < SkyboxCatalog.newsetNames.count {
            let name = SkyboxCatalog.newsetNames[idx]
            
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
        var mat = UnlitMaterial(texture: texture)
        // Keep the skybox material opaque when fully visible.
        // OpacityComponent drives the fade and will automatically take the entity through a transparent path while fading.
        mat.blending = .opaque
        
        dome.model = ModelComponent(mesh: dome.model?.mesh ?? .generateSphere(radius: 60.0),
                                    materials: [mat])
        
        // Apply rotation based on which set is active
        if newsetLevel > 0 {
            // Newset is active
            let idx = newsetLevel - 1
            if idx >= 0 && idx < SkyboxCatalog.newsetNames.count {
                let skyboxName = SkyboxCatalog.newsetNames[idx]
                if let rotationAngle = SkyboxCatalog.newsetRotations[skyboxName] {
                    dome.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))
                } else {
                    dome.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                }
            }
        } else if environmentSphereLevel > 0 {
            // Numbered set is active
            let idx = environmentSphereLevel - 1
            if idx >= 0 && idx < SkyboxCatalog.builtinNames.count {
                let skyboxName = SkyboxCatalog.builtinNames[idx]
                if let rotationAngle = SkyboxCatalog.rotations[skyboxName] {
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

        if dimLevel == 2 {
            // Reactive V1 - Keeps transparency (0.85), so keep .transparent
            var mat = UnlitMaterial(color: currentAmbientColor.withAlphaComponent(0.85))
            mat.blending = .transparent(opacity: 1.0)
            return (mat, nil)
        }

        if dimLevel == 10 {
            // Reactive V2 - SOLID COLOR (reactive)
            // Use .opaque for proper Z-sorting so UI icons render on top
            var mat = UnlitMaterial(color: currentAmbientColor.withAlphaComponent(1.0))
            mat.blending = .opaque
            return (mat, nil)
        }
        
        if dimLevel == 12 {
            // Starfield - Pure black background
            var mat = UnlitMaterial(color: .black)
            mat.blending = .opaque
            return (mat, nil)
        }

        let selectedTex: TextureResource?
        switch dimLevel {
        case 4: selectedTex = eclipseGradientTexture
        case 5: selectedTex = purpleGradientTexturePurpleBlack
        case 6: selectedTex = twilightGradientTexture
        case 7: selectedTex = dawnGradientTexture
        case 8: selectedTex = sunriseGradientTexture
        case 9: selectedTex = woodlandGradientTexture
        case 14: selectedTex = desertGradientTexture
        default: selectedTex = purpleGradientTextureColors
        }

        let mat: RealityKit.Material
        if let tex = selectedTex {
            var unlitMat = UnlitMaterial(texture: tex)

            // Eclipse (Level 4) is SOLID black - use .opaque for proper Z-sorting
            if dimLevel == 4 {
                unlitMat.color.tint = .white
                unlitMat.blending = .opaque
            } else {
                // All other gradients are semi-transparent
                let tintAlpha: CGFloat = {
                    switch dimLevel {
                    case 5: return 0.95
                    case 6, 7, 8, 9, 14: return 0.90
                    default: return 0.5
                    }
                }()
                unlitMat.color.tint = UIColor.white.withAlphaComponent(tintAlpha)
                unlitMat.blending = .transparent(opacity: 1.0)
            }
            mat = unlitMat
        } else {
            var fallback = UnlitMaterial(color: .purple)
            let fallbackAlpha: CGFloat = {
                switch dimLevel {
                case 4, 5: return 0.95
                case 6, 7, 8, 9, 10: return 0.90
                default: return 0.5
                }
            }()
            fallback.color.tint = UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: fallbackAlpha)
            fallback.blending = .transparent(opacity: 1.0)
            mat = fallback
        }
        return (mat, selectedTex)
    }

    private func updateDimmerDomesState() {
        dimmerDome?.isEnabled = (dimLevel == 1)
        dimmerDomePurple?.isEnabled = (dimLevel >= 2 && dimLevel <= 14)
        
        // Enable particles for Starfield (dimLevel 12) only
        // Add 0.5s warmup delay to prevent initial blink
        let shouldEnableParticles = (dimLevel == 12)
        
        if shouldEnableParticles {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.particleManager.setEnabled(true)
            }
        } else {
            particleManager.setEnabled(false)
        }
    }

    private func updateDimmerDomes(content: RealityViewContent) {
        // Only update materials if dimLevel changed OR in Reactive mode (needs continuous updates)
        let isReactiveMode = (dimLevel == 2 || dimLevel == 10 || dimLevel == 12)
        
        if dimLevel != lastAppliedDimLevel || isReactiveMode {
            lastAppliedDimLevel = dimLevel
            
            if let dome = dimmerDome {
                let targetAlpha: Float = viewModel.streamSettings.dimPassthrough ? Float(dimAlphas[1]) : Float(dimAlphas[0])
                if let comp = dome.components[OpacityComponent.self], abs(comp.opacity - targetAlpha) > 0.001 {
                    dome.components.set(OpacityComponent(opacity: targetAlpha))
                } else if dome.components[OpacityComponent.self] == nil {
                    dome.components.set(OpacityComponent(opacity: targetAlpha))
                }

                if dome.model?.materials.isEmpty ?? true {
                    var blackMat = UnlitMaterial(color: .black)
                    blackMat.blending = .transparent(opacity: 1.0)
                    dome.model = ModelComponent(mesh: dome.model?.mesh ?? .generateSphere(radius: 60.0),
                                                materials: [blackMat])
                }
            }

            if let purple = self.dimmerDomePurple {
                let (mat, _) = getDimmerMaterial()
                purple.model?.materials = [mat]
            }
        }
    }

    private func setupDimmerDomes(content: RealityViewContent) {
        let dome = ModelEntity(mesh: .generateSphere(radius: 60.0))
        dome.scale.x = -1.0
        dome.position = .zero
        var blackMat = UnlitMaterial(color: .black)
        blackMat.blending = .transparent(opacity: 1.0)
        dome.model = ModelComponent(mesh: dome.model?.mesh ?? .generateSphere(radius: 60.0),
                                    materials: [blackMat])
        dome.components.set(OpacityComponent(opacity: 0.0))
        dome.components.set(InputTargetComponent(allowedInputTypes: []))
        content.add(dome)
        self.dimmerDome = dome

        let purpleDome = ModelEntity(mesh: .generateSphere(radius: 60.0))
        purpleDome.scale.x = -1.0
        purpleDome.position = .zero
        purpleDome.components.set(InputTargetComponent(allowedInputTypes: []))
        content.add(purpleDome)
        self.dimmerDomePurple = purpleDome

        updateDimmerDomesState()
        
        // Add particle system for Nebula preset
        content.add(particleManager.rootEntity)

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
                    UIColor.black.cgColor,
                    UIColor.black.cgColor,
                    UIColor.black.cgColor,
                    UIColor.black.cgColor
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
                    UIColor(red: 0.25, green: 0.45, blue: 0.22, alpha: 0.65).cgColor,
                    UIColor(red: 0.18, green: 0.32, blue: 0.15, alpha: 0.75).cgColor,
                    UIColor(red: 0.08, green: 0.18, blue: 0.06, alpha: 0.90).cgColor,
                    UIColor(red: 0.04, green: 0.10, blue: 0.03, alpha: 0.98).cgColor
                ]
                locations = [0.0, 0.30, 0.60, 1.0]

            case .desert:
                colors = [
                    UIColor(red: 0.95, green: 0.80, blue: 0.55, alpha: 0.60).cgColor,
                    UIColor(red: 0.80, green: 0.60, blue: 0.40, alpha: 0.70).cgColor,
                    UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 0.90).cgColor,
                    UIColor(red: 0.20, green: 0.12, blue: 0.06, alpha: 0.98).cgColor
                ]
                locations = [0.0, 0.25, 0.55, 1.0]
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
        // We handle environment updates via updateEnvironmentState() triggered by Binding changes
        // to support fade animations. Automatic updates here would interfere with transitions.
    }

    private func disableEnvironmentImmediately() {
        environmentFadeTimer?.invalidate()
        environmentFadeTimer = nil

        lastEnvironmentSphereLevelApplied = 0

        guard let dome = environmentDome else { return }
        dome.components.set(OpacityComponent(opacity: 0.0))
        dome.isEnabled = false
    }
    
    internal init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool, swapAction: @escaping () -> Void) {
        self.swapAction = swapAction
        self._streamConfig = streamConfig
        self.needsHdr = needsHdr
        self.controllerSupport = ControllerSupport(config: streamConfig.wrappedValue, delegate: DummyControllerDelegate())
        
        let bytesPerPixel = needsHdr ? 8 : 4
        let data = Data(count: bytesPerPixel * Int(streamConfig.wrappedValue.width) * Int(streamConfig.wrappedValue.height))
        
        // Safe texture creation with fallback
        do {
            self.texture = try TextureResource(
                dimensions: .dimensions(width: Int(streamConfig.wrappedValue.width), height: Int(streamConfig.wrappedValue.height)),
                format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb),
                contents: .init(mipmapLevels: [.mip(data: data, bytesPerRow: bytesPerPixel * Int(streamConfig.wrappedValue.width))])
            )
            self.isHDRTexture = needsHdr
        } catch {
            print("⚠️ Failed to create main texture: \(error). Using fallback.")
            // Fallback to minimal 1x1 texture to prevent crash
            let fallbackData = Data(count: 4)
            self.texture = try! TextureResource(
                dimensions: .dimensions(width: 1, height: 1),
                format: .raw(pixelFormat: .bgra8Unorm_srgb),
                contents: .init(mipmapLevels: [.mip(data: fallbackData, bytesPerRow: 4)])
            )
            self.isHDRTexture = false
        }
    }

    private func recenterScreenToHead(head: AnchorEntity) {
        let headPos = head.position(relativeTo: nil)
        let current = screenPosition

        // Preserve current height offset
        let yOffset = current.y - headPos.y
        
        // Calculate the ACTUAL 3D distance from head to screen (not just horizontal)
        let delta = current - headPos
        let actualDistance = simd_length(delta)

        // Get head's forward direction (where you're looking)
        let q = head.transform.rotation
        var headForward = q.act(simd_float3(0, 0, -1))

        // Flatten to horizontal plane (ignore vertical component)
        var flatForward = simd_float3(headForward.x, 0, headForward.z)
        let norm = simd_length(flatForward)
        if norm < 1e-4 {
            flatForward = simd_float3(0, 0, -1)
        } else {
            flatForward /= norm
        }

        // Place screen dead center at the same 3D distance
        var newPos = simd_float3(
            headPos.x + flatForward.x * actualDistance,
            headPos.y + yOffset,
            headPos.z + flatForward.z * actualDistance
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
    
    // MARK: - Reactive Color Lerp
    
    private func startReactiveLerp() {
        reactiveLerpTimer?.invalidate()
        
        // Initialize colors if starting fresh
        if currentAmbientColor == .black && targetReactiveColor == .black {
            let initialColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
            currentAmbientColor = initialColor
            targetReactiveColor = initialColor
        }
        
        // Run at 60fps for buttery smooth interpolation
        reactiveLerpTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard (self.dimLevel == 2 || self.dimLevel == 10), let purple = self.dimmerDomePurple else { return }
            
            // Lerp factor: 0.15 = smooth but responsive (reaches 95% in ~0.2s)
            let lerpFactor: CGFloat = 0.15
            
            var currentR: CGFloat = 0, currentG: CGFloat = 0, currentB: CGFloat = 0, currentA: CGFloat = 0
            self.currentAmbientColor.getRed(&currentR, green: &currentG, blue: &currentB, alpha: &currentA)
            
            var targetR: CGFloat = 0, targetG: CGFloat = 0, targetB: CGFloat = 0, targetA: CGFloat = 0
            self.targetReactiveColor.getRed(&targetR, green: &targetG, blue: &targetB, alpha: &targetA)
            
            // Linear interpolation
            let newR = currentR + (targetR - currentR) * lerpFactor
            let newG = currentG + (targetG - currentG) * lerpFactor
            let newB = currentB + (targetB - currentB) * lerpFactor
            
            self.currentAmbientColor = UIColor(red: newR, green: newG, blue: newB, alpha: 1.0)
            
            // Update material
            let (mat, _) = self.getDimmerMaterial()
            purple.model?.materials = [mat]
        }
    }
    
    private func stopReactiveLerp() {
        reactiveLerpTimer?.invalidate()
        reactiveLerpTimer = nil
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
        case 0: "FILTER: Default"
        case 1: "FILTER: Cinematic"
        case 2: "FILTER: Vi\u{200A}vid"  // Hair space between I and V
        case 3: "FILTER: Realistic"
        default: "FILTER: Default"
        }
    }
    
    private func curvatureText(for displayName: String) -> String {
        // Hair space between R and V
        return "CUR\u{200A}VATURE: \(displayName)"
    }
    
    private func canChangePreset() -> Bool {
        guard let cooldownUntil = presetCooldownUntil else { return true }
        return Date() >= cooldownUntil
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
        // Disable screen collision when menus are showing OR when in Controller mode
        // Controller buttons map to system gestures which hit CollisionComponent
        let shouldDisableInteractions = showMenuPanel || showSwapConfirm || show3DConfirm || showDisconnectConfirm || inputMode == .controller
        if shouldDisableInteractions {
            screen.components.remove(CollisionComponent.self)
            screen.components.remove(InputTargetComponent.self)
        } else {
            // Generate curved collision mesh for accurate gaze hit detection
            if let collisionMesh = try? generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (256, 256),
                curveMagnitude: curvaturePreset.value * curveAnimationMultiplier,
                cornerRadiusFraction: 0
            ) {
                Task {
                    if let collisionShape = try? await ShapeResource.generateStaticMesh(from: collisionMesh) {
                        await MainActor.run {
                            screen.components.set(CollisionComponent(
                                shapes: [collisionShape],
                                filter: CollisionFilter(
                                    group: .screenEntity,
                                    mask: .all
                                )
                            ))
                        }
                    }
                }
            }
            screen.components.set(InputTargetComponent(allowedInputTypes: .all))
        }
    }
    
    // MARK: - Preload Skyboxes
    private func loadExtraSkyboxesFromBundle() {
        // Load skyboxes on background thread to avoid blocking main thread during view setup
        Task.detached(priority: .background) {
            let exts = ["jpg", "jpeg", "png"]
            let builtinSet = Set(SkyboxCatalog.builtinNames + ["AboveClouds", "Above_Clouds"])
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
            
            // Update state on main thread once loading is complete
            await MainActor.run {
                self.extraSkyboxNames = names
                self.extraSkyboxTextures = textures
                print("[Skybox] Loaded \(names.count) extra skyboxes in background")
            }
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let mainViewWindowClosed = Notification.Name("MainViewWindowClosed")
    static let resumeStreamFromMenu = Notification.Name("ResumeStreamFromMenu")
    static let rkStreamDidTeardown = Notification.Name("RKStreamDidTeardown")
    static let curvedScreenWakeRequested = Notification.Name("CurvedScreenWakeRequested")
}
