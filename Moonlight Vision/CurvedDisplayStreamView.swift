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

/// SBS 3D confirmation card — proportional sizing (default × 0.8 = −20%).
private enum SBSConfirmPanelMetrics {
    static let scale: CGFloat = 0.8
    static func pt(_ base: CGFloat) -> CGFloat { base * scale }
}

class HeadPositionStorage {
    var positionInScreenSpace: SIMD3<Float> = .zero
    var lastHeadWorldPos: SIMD3<Float> = .zero
    var lastDragTime: CFTimeInterval = 0
    var lastGeneratedCurve: Float?
    var lastGeneratedAspect: Float?
    var lastMeshGenTime: Date?
    var forceCollisionRegen: Bool = false
    var statsScaleInitialized: Bool = false
    
    // Entity references (set during RealityView make/update, stored here to avoid @State warnings)
    var headAnchor: AnchorEntity?
    var controlsEntity: Entity?
    var menuEntity: Entity?
    var dimmerDome: ModelEntity?
    var dimmerDomePurple: ModelEntity?
    var environmentDome: ModelEntity?
    var chromosphereHaloEntity: ModelEntity?
    
    // Initialization tracking
    var hasInitializedPosition: Bool = false
    /// When true, next head-tracked update places the screen in front of the user (no saved `curved.pos`).
    var pendingFirstLaunchHeadPlacement: Bool = false
    /// When true, `saveCurrentTransform()` runs after deferred default head placement (Screen Adjust long-press reset).
    var saveTransformAfterDefaultPlacement: Bool = false
    /// World-tracking task that listens for Digital Crown recenter (pre–visionOS 26 fallback).
    var crownMonitorTask: Task<Void, Never>?
    var crownWorldTrackingProvider: WorldTrackingProvider?
    var crownARKitSession: ARKitSession?
    var crownReferenceWorldAnchorID: UUID?
    var lastWorldAnchorTransform: simd_float4x4?
    /// False until `setupScene` finishes restoring saved transform — blocks spurious crown recenter on launch.
    var streamTransformReady: Bool = false
    var lastCrownRecenterTime: TimeInterval = 0
    var menuScaleInitialized: Bool = false
    var inputScaleInitialized: Bool = false
    var tutorialScaleInitialized: Bool = false
    /// Controls bar local transform before peek-through reparents it off the screen entity.
    var controlsTransformBeforePeek: Transform?

    // MARK: - Follow Mode Spring State
    /// Smoothed local offset that the screen actually uses (spring catches up to headFollowLocalOffset target).
    var headFollowSmoothedOffset: SIMD3<Float>?
    /// Velocity for spring physics on offset.
    var headFollowOffsetVelocity: SIMD3<Float> = .zero
    /// Smoothed rotation for spring physics.
    var headFollowSmoothedRotation: simd_quatf?
    /// Angular velocity for rotation spring (axis-angle representation).
    var headFollowRotationVelocity: SIMD3<Float> = .zero
    /// Last update timestamp for delta time calculation.
    var headFollowLastUpdateTime: CFTimeInterval = 0
    
    // Optimization tracking (to avoid redundant updates during RealityView update closure)
    var lastAppliedDimLevel: Int = -1
    var lastEnvironmentSphereLevelApplied: Int = 0
    /// Live target from curvature slider drag; mesh pump reads this at 12 Hz.
    var curvatureDragTarget: Float?
    /// Cached RealityKit scale for the curvature pill — measured while hidden; reused after Home/Resume churn.
    var curvaturePillStableScale: Float?

    // World anchor support for room-fixed screen presets
    var presetWorldTrackingProvider: WorldTrackingProvider?
    var presetARKitSession: ARKitSession?
    var presetAnchorMonitorTask: Task<Void, Never>?
    var presetApplyRefineTask: Task<Void, Never>?
    var activePresetWorldAnchorID: UUID?
    /// While `CACurrentMediaTime()` is below this, anchor monitor/refine must not move the screen.
    var presetAnchorApplySuppressUntil: CFTimeInterval = 0
}

private enum ScreenPresetAnchorTolerance {
    static let positionMeters: Float = 0.04
    static let angleDegrees: Float = 1.25
    static let suppressAfterManualApplySeconds: TimeInterval = 1.75
    static let interactiveAnchorWaitSeconds: TimeInterval = 0.4
    static let launchAnchorWaitSeconds: TimeInterval = 0.85
}

private enum CurvaturePillScalePolicy {
    static let fallbackScale: Float = 1.85
    static let minUnscaledWidthMeters: Float = 0.35
    static let minScale: Float = 0.75
    static let maxScale: Float = 2.5
    static let desiredLocalWidthFactor: Float = 0.468
}

struct InputCaptureView: UIViewRepresentable {
    let controllerSupport: ControllerSupport
    let gamepadSession: StreamGamepadSession
    @Binding var showKeyboard: Bool
    var isControllerMode: Bool  // True only when inputMode == .controller
    var modalBlocksOverlay: Bool
    /// When true, legacy overlay must not reclaim first responder (HDR panel text fields, etc.).
    var suspendLegacyFirstResponder: Bool
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
        view.suspendLegacyFirstResponder = suspendLegacyFirstResponder
        
        view.configureForCurrentMode(isControllerMode: isControllerMode, gamepadSession: gamepadSession)
        if isControllerMode {
            gamepadSession.setControllerModeActive(true)
            gamepadSession.setModalBlocking(showKeyboard || modalBlocksOverlay)
            gamepadSession.attach(captureView: view, controllerSupport: controllerSupport)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: InputCaptureUIView, context: Context) {
        uiView.curvature = curvature
        uiView.streamConfig = streamConfig
        uiView.headStorage = headStorage
        uiView.allowTouchPassthrough = !showKeyboard && !isControllerMode
        uiView.showVirtualKeyboard = showKeyboard
        uiView.suspendLegacyFirstResponder = suspendLegacyFirstResponder
        
        uiView.configureForCurrentMode(isControllerMode: isControllerMode, gamepadSession: gamepadSession)
        if isControllerMode {
            gamepadSession.setControllerModeActive(true)
            gamepadSession.setModalBlocking(showKeyboard || modalBlocksOverlay)
            gamepadSession.attach(captureView: uiView, controllerSupport: controllerSupport)
        } else {
            gamepadSession.setControllerModeActive(false)
        }
    }
}

class InputCaptureUIView: UIView, UIKeyInput {
    var controllerSupport: ControllerSupport?
    private weak var gamepadSession: StreamGamepadSession?
    private var usesGamepadSession = false
    private var firstResponderCheckTimer: Timer?
    private var legacyGCEventAttached = false
    var curvature: Float = 0.0
    var streamConfig: StreamConfiguration?
    var headStorage: HeadPositionStorage?
    var allowTouchPassthrough: Bool = true
    var suspendLegacyFirstResponder: Bool = false {
        didSet {
            guard oldValue != suspendLegacyFirstResponder else { return }
            if suspendLegacyFirstResponder {
                pauseLegacyFirstResponderReclaim()
            } else if !usesGamepadSession {
                startLegacyGamepadHandlingIfNeeded()
            }
        }
    }
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
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        firstResponderCheckTimer?.invalidate()
    }
    
    /// Gaze / Screen Adjust use the pre-overhaul overlay path; Controller mode uses StreamGamepadSession.
    func configureForCurrentMode(isControllerMode: Bool, gamepadSession: StreamGamepadSession?) {
        if isControllerMode {
            if !usesGamepadSession {
                // Transfer ownership of GCEventInteraction to the session.
                // Do NOT detach it — the session will manage it from here.
                firstResponderCheckTimer?.invalidate()
                firstResponderCheckTimer = nil
                legacyGCEventAttached = false
                usesGamepadSession = true
                self.gamepadSession = gamepadSession
            }
        } else {
            if usesGamepadSession {
                gamepadSession?.deactivateGamepadCapture()
                usesGamepadSession = false
                self.gamepadSession = nil
            }
            startLegacyGamepadHandlingIfNeeded()
        }
    }
    
    private func startLegacyGamepadHandlingIfNeeded() {
        setupLegacyGesturesIfNeeded()
        startFirstResponderMonitoringIfNeeded()
    }
    
    private func pauseLegacyFirstResponderReclaim() {
        firstResponderCheckTimer?.invalidate()
        firstResponderCheckTimer = nil
        if isFirstResponder && !usesGamepadSession {
            resignFirstResponder()
        }
    }
    
    private func stopLegacyGamepadHandling() {
        firstResponderCheckTimer?.invalidate()
        firstResponderCheckTimer = nil
        if legacyGCEventAttached, let support = controllerSupport {
            support.detachGCEventInteraction(from: self)
            legacyGCEventAttached = false
        }
    }
    
    private func setupLegacyGesturesIfNeeded() {
        guard !legacyGCEventAttached else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.usesGamepadSession else { return }
            self.controllerSupport?.attachGCEventInteraction(to: self)
            self.legacyGCEventAttached = true
        }
    }
    
    private func startFirstResponderMonitoringIfNeeded() {
        guard !suspendLegacyFirstResponder else { return }
        guard firstResponderCheckTimer == nil else { return }
        firstResponderCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.usesGamepadSession, !self.suspendLegacyFirstResponder else { return }
            if !self.isFirstResponder {
                _ = self.becomeFirstResponder()
            }
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        if usesGamepadSession {
            gamepadSession?.captureViewDidMoveToWindow()
        } else if !suspendLegacyFirstResponder && !isFirstResponder {
            _ = becomeFirstResponder()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if usesGamepadSession {
            gamepadSession?.captureViewTouchesBegan()
        }
        super.touchesBegan(touches, with: event)
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
/// Mic pill sits below the screen bottom edge; extra clearance avoids accidental stream taps.
let CURVED_MIC_OFFSET_BELOW_SCREEN: Float = 0.07
let CURVED_MIC_OFFSET_BELOW_SCREEN_WITH_KEYBOARD: Float = 0.15

/// First curved session only (no saved `curved.pos`). Synced to `@State` so `updateRealityView` never reverts to in-your-face defaults.
private enum CurvedFirstLaunch {
    static let defaultDistance: Float = 2.75
    static let defaultScale: Float = 1.62
    /// Head Follow HUD: first-launch scale reduced 15% so controls stay in view while walking.
    static var headFollowScale: Float { defaultScale * 0.85 }
    /// Eye-level lift uses this scale so size changes don’t pull the panel higher/lower.
    static let eyeLevelLiftReferenceScale: Float = 1.35
    /// Fine-tune above computed eye-level lift (mesh origin is panel center, not your eyes).
    static let verticalOffsetFromHead: Float = 0.05
    static let maxTiltDegrees: Float = 60
    static let maxYawDegrees: Float = 60
    /// Left/right Screen Adjust handles only (clockwise / counter-clockwise from entry baseline).
    static let maxScreenAdjustSideYawDegrees: Float = 40
    static let placeholderPosition = SIMD3<Float>(0, 1.55, -defaultDistance)

    static func clampTilt(_ degrees: Float) -> Float {
        min(max(degrees, -maxTiltDegrees), maxTiltDegrees)
    }

    static func clampYaw(_ degrees: Float) -> Float {
        min(max(degrees, -maxYawDegrees), maxYawDegrees)
    }

    /// Head-local Y offset: panel center at eye height (head anchor ≈ mid-skull).
    /// Unlike world-space first launch, do not add full panel height — that pushes the screen to the ceiling.
    static let headFollowVerticalOffsetFromHead: Float = 0.06

    static var defaultHeadFollowLocalOffset: SIMD3<Float> {
        SIMD3(0, headFollowVerticalOffsetFromHead, -defaultDistance)
    }

    /// Radians of orbit rotation per meter of hand drag (yaw/pitch around the head).
    static let headFollowOrbitRadiansPerMeter: Float = 0.72
    static let headFollowOrbitMinPitch: Float = -0.38
    static let headFollowOrbitMaxPitch: Float = 1.15
    static let headFollowOrbitMaxYaw: Float = 1.45

    static var defaultHeadFollowOrbit: (yaw: Float, pitch: Float, radius: Float) {
        orbit(from: defaultHeadFollowLocalOffset)
    }

    static func orbit(from offset: SIMD3<Float>) -> (yaw: Float, pitch: Float, radius: Float) {
        let radius = max(simd_length(offset), 0.45)
        let pitch = asin(min(max(offset.y / radius, -1), 1))
        let yaw = atan2(offset.x, -offset.z)
        return (yaw, pitch, radius)
    }

    static func offset(yaw: Float, pitch: Float, radius: Float) -> SIMD3<Float> {
        let cosPitch = cos(pitch)
        return SIMD3(
            radius * cosPitch * sin(yaw),
            radius * sin(pitch),
            -radius * cosPitch * cos(yaw)
        )
    }

    static func clampedOrbit(yaw: Float, pitch: Float, radius: Float) -> (yaw: Float, pitch: Float, radius: Float) {
        (
            min(max(yaw, -headFollowOrbitMaxYaw), headFollowOrbitMaxYaw),
            min(max(pitch, headFollowOrbitMinPitch), headFollowOrbitMaxPitch),
            min(max(radius, 0.45), 4.0)
        )
    }

    // MARK: - Follow Mode Spring Constants
    /// Critically damped spring for smooth follow. Higher = snappier response.
    /// At 90 Hz, stiffness ~180 gives ~0.15s settle time (fast but smooth).
    static let headFollowSpringStiffness: Float = 180.0
    /// Critical damping = 2 * sqrt(stiffness) ≈ 26.8. Slightly under-damped for natural feel.
    static let headFollowSpringDamping: Float = 25.0
    /// Rotation spring can be slightly tighter for responsive look direction.
    static let headFollowRotationStiffness: Float = 220.0
    static let headFollowRotationDamping: Float = 28.0
    /// Maximum delta time to prevent simulation explosion after app pause.
    static let headFollowMaxDeltaTime: Float = 0.05
}

extension CollisionGroup {
    static let screenEntity = CollisionGroup(rawValue: 1 << 0)
    static let uiElements = CollisionGroup(rawValue: 1 << 1)
}

// MARK: - Input Mode for Curved Display

enum InputMode: Int, CaseIterable {
    case screenMove = 0
    case controller = 1
    case gazeControl = 2
    
    var displayName: String {
        switch self {
        case .screenMove: return "Screen Adjust Mode"
        case .controller: return "Accessory Mode"
        case .gazeControl: return "Gaze Control Mode"
        }
    }

    /// Transient pill text when cycling modes (may differ from `displayName`).
    func modeSwitchOverlayName(gazeUsesTouchMode: Bool) -> String {
        if self == .gazeControl && gazeUsesTouchMode {
            return "Touch Control Mode"
        }
        return displayName
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

private enum ScreenAdjustHandleEdge: CaseIterable {
    case top
    case bottom
    case left
    case right
    
    var systemImage: String {
        switch self {
        case .top: return "arrow.up.circle"
        case .bottom: return "arrow.down.circle"
        case .left: return "arrow.left.circle"
        case .right: return "arrow.right.circle"
        }
    }
    
    var systemImageFill: String {
        switch self {
        case .top: return "arrow.up.circle.fill"
        case .bottom: return "arrow.down.circle.fill"
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        }
    }
    
    var attachmentID: String {
        switch self {
        case .top: return "screenAdjustHandleTop"
        case .bottom: return "screenAdjustHandleBottom"
        case .left: return "screenAdjustHandleLeft"
        case .right: return "screenAdjustHandleRight"
        }
    }
}

/// Glass circle chrome behind Screen Adjust arrows — icon size unchanged; ring extends the grab target.
private enum ScreenAdjustHandleChrome {
    static let iconSize: CGFloat = 50
    static let iconFontSize: CGFloat = 24.07
    static let circleDiameter: CGFloat = 72
    
    static var ringPadding: CGFloat { (circleDiameter - iconSize) / 2 }
}

// MARK: - Gaze Input Controller
// Created by NeoVectorX - January 2025
// Implements raycast-to-UV mapping and gesture handling for curved screen geometry.
//
// Gaze pinch-drag: scroll mode (default) sends wheel events; drag mode uses shoot-first click-drag.
// Quick pinch = click; hold still = right-click.

class GazeInputController {
    // Timing constants (Matching FlatInputCaptureUIView)
    private let longPressActivationDelay: TimeInterval = 0.650
    private let doubleTapDeadZoneDelay: TimeInterval = 0.250  // 250ms
    private let doubleTapDeadZoneDelta: Float = 0.025  // 2.5% of screen (normalized)
    // Threshold to cancel long press (roughly size of a button in UV space)
    private let movementTolerance: Float = 0.015
    private let scrollMovementTolerance: Float = 0.008
    private let scrollWheelScale: Float = 2400.0

    // State
    private(set) var pinchActive = false
    private var longPressTimer: Timer?
    private var startUV: SIMD2<Float> = .zero
    private var lastScrollUV: SIMD2<Float> = .zero
    private var isRightClickMode = false  // Track if we swapped to right-click
    private var isScrolling = false
    private var leftDownSent = false
    private var lastClickTime: TimeInterval = 0  // Track last click for double-tap detection
    private var lastClickUV: SIMD2<Float> = .zero  // Track last click position

    /// true = pinch-drag scrolls (wheel); false = pinch-drag click-drags (marquee).
    var pinchDragUsesScroll: Bool = true

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
        lastScrollUV = uv
        isRightClickMode = false
        isScrolling = false
        leftDownSent = false

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

        if !pinchDragUsesScroll {
            // Drag mode: press left immediately ("shoot first") for marquee / click-drag
            sendMouseButton(action: ACTION_PRESS, button: BUTTON_LEFT)
            leftDownSent = true
        }

        // Start Long Press Timer (for Right Click)
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressActivationDelay, repeats: false) { [weak self] _ in
            self?.triggerLongPress()
        }
        
        lastClickTime = now
        lastClickUV = uv
    }
    
    func onPinchChanged(at uv: SIMD2<Float>) {
        sendMousePosition(uv: uv)
        
        let dx = uv.x - startUV.x
        let dy = uv.y - startUV.y
        let dist = sqrt(dx * dx + dy * dy)
        
        if pinchDragUsesScroll {
            let deltaU = uv.x - lastScrollUV.x
            let deltaV = uv.y - lastScrollUV.y
            
            if dist > scrollMovementTolerance {
                isScrolling = true
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
            
            if isScrolling {
                if abs(deltaV) > 0.00005 {
                    // UV y increases downward; invert so drag-down scrolls down
                    LiSendHighResScrollEvent(Int16(-deltaV * scrollWheelScale))
                }
                if abs(deltaU) > 0.00005 {
                    LiSendHighResHScrollEvent(Int16(deltaU * scrollWheelScale))
                }
            }
            lastScrollUV = uv
        } else {
            // Drag mode: cancel right-click timer when moving
            if longPressTimer != nil, dist > movementTolerance {
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
        }
    }
    
    func onPinchEnded() {
        guard pinchActive else { return }
        pinchActive = false
        
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        if isRightClickMode {
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_RIGHT)
        } else if pinchDragUsesScroll {
            if !isScrolling {
                sendMouseButton(action: ACTION_PRESS, button: BUTTON_LEFT)
                sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
            }
        } else {
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
        }
        
        isRightClickMode = false
        isScrolling = false
        leftDownSent = false
    }
    
    private func triggerLongPress() {
        isRightClickMode = true
        
        if leftDownSent {
            sendMouseButton(action: ACTION_RELEASE, button: BUTTON_LEFT)
            leftDownSent = false
        }
        
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
        isScrolling = false
        leftDownSent = false
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
                        recoverFromStaleWindow()
                    }
            }
        } else {
            // During window transition (dismiss -> wait -> open), config may be nil.
            // Show black screen to prevent zombie view from initializing.
            Color.black
                .ignoresSafeArea()
                .onAppear {
                    recoverFromStaleWindow()
                }
        }
    }
    
    private func recoverFromStaleWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !viewModel.activelyStreaming && viewModel.streamState == .idle {
                print("[CurvedDisplay] Stale window detected - dismissing and opening mainView")
                openWindow(id: "mainView")
                Task {
                    await dismissImmersiveSpace()
                    viewModel.isImmersiveSpaceOpen = false
                }
            }
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
    @State private var streamGamepadSession = StreamGamepadSession()
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()
    @ObservedObject private var coopCoordinator = CoopSessionCoordinator.shared
    
    @State private var texture: TextureResource
    @State private var screen: ModelEntity = ModelEntity()
    @State private var videoMode: VideoMode = .standard2D
    @State private var surfaceMaterial: ShaderGraphMaterial?
    
    @State private var curveAnimationMultiplier: Float = 1.0

    private var effectiveCurveMagnitude: Float {
        curveMagnitude * curveAnimationMultiplier
    }

    private func persistCurveMagnitude() {
        savedCurveMagnitude = Double(CurvedCurvatureMapping.clampMagnitude(curveMagnitude))
    }

    private func setCurveMagnitude(_ value: Float, persist: Bool = true) {
        curveMagnitude = CurvedCurvatureMapping.clampMagnitude(value)
        if persist { persistCurveMagnitude() }
    }

    private func startCurvatureDragMeshPump() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { _ in
            guard self.curvatureSliderDragging,
                  let target = self.headStorage.curvatureDragTarget else { return }
            let clamped = CurvedCurvatureMapping.clampMagnitude(target)
            guard abs(clamped - self.curveMagnitude) > 0.002 else { return }
            self.curveMagnitude = clamped
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func stopCurvatureDragMeshPump() {
        animationTimer?.invalidate()
        animationTimer = nil
        headStorage.curvatureDragTarget = nil
    }

    @State private var animationTimer: Timer?

    @AppStorage("curved.curveMagnitude") private var savedCurveMagnitude: Double = Double(CurvatureTick.defaultTick.magnitude)
    @State private var curveMagnitude: Float = CurvatureTick.defaultTick.magnitude
    @State private var curvatureSliderDragging = false
    @State private var tiltAngle: Float = CurvedFirstLaunch.clampTilt(
        Float(UserDefaults.standard.double(forKey: "curved.tiltAngle"))
    )
    @AppStorage("curved.tiltAngle") private var savedTiltAngle: Double = 0.0
    @State private var yawAngle: Float = CurvedFirstLaunch.clampYaw(
        Float(UserDefaults.standard.double(forKey: "curved.yawAngle"))
    )
    @AppStorage("curved.yawAngle") private var savedYawAngle: Double = 0.0
    @State private var screenAdjustBaselineTilt: Float = 0
    @State private var screenAdjustBaselineYaw: Float = 0
    @State private var activeScreenAdjustHandle: ScreenAdjustHandleEdge? = nil
    @State private var startTiltForDrag: Float? = nil
    @State private var startYawForDrag: Float? = nil
    @State private var screenAdjustHandleFeedbackTrigger: Int = 0
    
    @State private var screenPosition: SIMD3<Float> = CurvedFirstLaunch.placeholderPosition
    @State private var screenScale: Float = CurvedFirstLaunch.defaultScale
    @State private var isLocked: Bool = false
    @State private var headFollowLocalOffset: SIMD3<Float> = CurvedFirstLaunch.defaultHeadFollowLocalOffset
    @State private var showHeadFollowIntro = false
    @State private var inputModeBeforeHeadFollow: InputMode?
    @State private var startDragPosition: SIMD3<Float>? = nil
    /// Packed orbit at drag start: (yaw, pitch, radius) — Head Follow only.
    @State private var startHeadFollowOrbit: SIMD3<Float>? = nil
    // hasInitializedPosition moved to headStorage to avoid "Modifying state during view update"
    
    @State private var safeHDRSettings = ThreadSafeHDRSettings(
        params: HDRParams(boost: 1.0, contrast: 1.0, saturation: 1.0, brightness: 0.0, pqExposure: 1.0, mode: 0)
    )
    @StateObject private var hdrParams = HDRTestParams()
    @StateObject private var hdrPanelSettings = HDRSettings()
    @StateObject private var screenPresetSettings = ScreenPresetSettings()
    @State private var showScreenPresetPanel = false
    @State private var screenPresetRenamingActive = false

    @State private var showVirtualKeyboard = false
    @State private var hideControls: Bool = false
    @State private var controlsExpanded: Bool = false
    /// Drives the stagger animation; when expanded view appears we go false→true so icons animate in. On collapse we go true→false then hide after delay.
    @State private var expandedContentRevealed: Bool = false
    
    // Star distance preset persistence
    @AppStorage("starfield.distancePreset") private var starDistancePresetRawValue: Int = StarDistancePreset.close.rawValue
    @AppStorage("removeRoundedCorners") private var removeRoundedCorners: Bool = false
    @AppStorage("darkControlsMode") private var darkControlsMode: Bool = false
    @AppStorage("lightControlsMode") private var lightControlsMode: Bool = false
    
    private var starDistancePreset: StarDistancePreset {
        get { StarDistancePreset(rawValue: starDistancePresetRawValue) ?? .close }
    }
    
    // Particle Manager for Nebula preset
    @State private var particleManager = ParticleManager()
    
    // Reference to the video decoder for controlling reactive dimming
    @State private var videoDecoder: DrawableVideoDecoder?
    
    // Keyboard Override State
    @State private var keyboardInput: String = ""
    @State private var previousKeyboardInput: String = ""
    @FocusState private var isKeyboardFocused: Bool
    
    @State private var hideTimer: Timer?
    // controlsEntity moved to headStorage to avoid "Modifying state during view update"
    @State private var shouldClose = false
    @State private var hasPerformedTeardown = false
    @State private var needsResume = false
    @State private var spatialAudioMode: Bool = true
    @State private var soundStageSize: SoundStageSize = .medium
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?
    @State private var showScaleHUD: Bool = false
    @State private var showModeLabel: Bool = false
    @State private var modeLabelTimer: Timer?
    @State private var controlsHighlighted: Bool = false
    /// Incremented on each control tap so sensoryFeedback fires (avoids quiet spatialized system sound in curved mode).
    @State private var controlTapFeedbackTrigger: Int = 0
    @StateObject private var micChromeFade = MicChromeFadeController(style: .curved)
    @State private var immersiveSpaceSceneID: String?
    @State private var theaterEnvironmentEnabled = false
    @State private var showMenuPanel = false
    // menuEntity moved to headStorage to avoid "Modifying state during view update"
    // menuScaleInitialized moved to headStorage to avoid "Modifying state during view update"
    @State private var menuBaseWidth: Float = 0
    // inputScaleInitialized moved to headStorage to avoid "Modifying state during view update"
    @State private var inputBaseWidth: Float = 0
    @State private var swapInProgress = false
    @State private var menuPanelInstanceID = UUID()
    @State private var showSwapOverlay = false
    @State private var showSwapConfirm = false
    @State private var show3DConfirm = false
    
    @State private var showEnvironmentPicker = false
    @State private var showDimmingPicker = false
    @State private var showHDRPanel = false
    @State private var hdrPresetRenamingActive = false
    @State private var showDesktopActionsPicker = false
    /// Alt+Tab sent; picker dismissed so gaze/controller can target the Windows switcher (Alt stays on host).
    @State private var desktopAltTabInteractionActive = false
    @State private var inputModeBeforeDesktopPicker: InputMode?
    @State private var handInputDisabledBeforeDesktopPicker: Bool?
    @State private var inputMode: InputMode = .gazeControl // Three-mode input toggle (default: gaze control)
    @State private var isHandGazeInputDisabled = false // Long press in Gaze Control only — disables hand/gaze stream input
    /// Session-only override for gaze pinch-drag; nil uses Settings default.
    @State private var sessionPinchDragUsesScroll: Bool? = nil
    @State private var gazeController = GazeInputController()
    @State private var streamVolumeBeforeMute: Float = 127
    @State private var streamPeekThroughActive = false
    @State private var streamVolumeBeforePeek: Float = 127
    private let streamPeekScreenOpacity: Float = 0.05
    private let streamPeekVolumeLevel: Float = 13 // 10% of max stream volume (127)
    private let streamPeekFadeInDuration: TimeInterval = 0.55
    private let streamPeekFadeOutDuration: TimeInterval = 0.35
    @State private var passThroughFadeTimer: Timer?

    @State private var headStorage = HeadPositionStorage()
    
    @State private var renderGateOpen: Bool = true
    
    // Stats attachment sizing in meters (fixed width target)
    // Note: statsScaleInitialized moved to headStorage to avoid "Modifying state during view update"
    @State private var statsBaseWidth: Float = 0
    private let statsCardWidthMeters: Float = 0.12
    
    // tutorialScaleInitialized moved to headStorage to avoid "Modifying state during view update"
    @State private var tutorialBaseWidth: Float = 0
    private let tutorialCardWidthMeters: Float = 1.110
    
    @State private var showCurvedTutorial = false
    @State private var gestureInitialScale: Float? = nil
    @State private var targetScale: Float = CurvedFirstLaunch.defaultScale
    @State private var scaleBeforeHeadFollow: Float = CurvedFirstLaunch.defaultScale
    @State private var targetScaleBeforeHeadFollow: Float = CurvedFirstLaunch.defaultScale
    @State private var scaleHUDFadeTimer: Timer?
    @State private var environmentFadeTimer: Timer?
    
    // dimmerDome moved to headStorage to avoid "Modifying state during view update"
    // dimmerDomePurple moved to headStorage to avoid "Modifying state during view update"
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
    @State private var tideCycleTimer: Timer?
    @State private var tideCyclePhase: CGFloat = 0.0
    @State private var tideCycleStartTime: CFTimeInterval = CACurrentMediaTime()
    @State private var tideMaterial: UnlitMaterial?
    private let tideCycleDuration: CGFloat = CGFloat(TideGradientPalette.cycleDuration)
    private let tideUpdateInterval: TimeInterval = 0.12
    private let dimAlphas: [CGFloat] = [0.0, 0.82]
    @State private var dimLevel: Int = 0
    
    // Preset brightness values (user-adjustable via long-press)
    // Keys are dimLevels: 1=Night, 5=Midnight, 6=Twilight, 7=Dawn, 8=Sunrise, 9=Woodland, 10=Tide, 14=Desert
    @State private var presetBrightness: [Int: Double] = [:]
    private let defaultPresetBrightness: [Int: Double] = [
        1: 0.82,   // Night
        5: 0.95,   // Midnight
        6: 0.90,   // Twilight
        7: 0.90,   // Dawn
        8: 0.90,   // Sunrise
        9: 0.90,   // Woodland
        10: 0.90,  // Tide
        14: 0.90   // Desert
    ]
    // lastAppliedDimLevel moved to headStorage to avoid "Modifying state during view update"
    @State private var environmentSphereLevel: Int = 0
    @State private var environmentUSDZLevel: Int = 0
    @State private var moonlightMaterial: UnlitMaterial?
    @State private var lastMoonlightAppliedRGB: SIMD3<Float> = .zero
    @State private var lastMoonlightUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private let moonlightCycleDurationLowPower: CGFloat = 22.0
    private let moonlightUpdateIntervalLowPower: TimeInterval = 0.22
    private let moonlightColorDeltaThresholdLowPower: Float = 0.03
    private let moonlightAlphaLowPower: CGFloat = 0.78
    
    // lastEnvironmentSphereLevelApplied moved to headStorage to avoid "Modifying state during view update"
    
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
    // ChromaHalo / Chromosphere edge bloom — Reactive 1 (curved shell)
    @State private var chromosphereMeshEntity: ModelEntity? = nil
    @State private var chromosphereTexture: TextureResource? = nil

    private var usesChromosphereHaloPipeline: Bool { dimLevel == 2 }

    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    
    @State private var isMenuOpen: Bool = false
    
    @State private var isMenuOpen1: Bool = false
    
    // environmentDome moved to headStorage to avoid "Modifying state during view update"
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
    var cornerRadiusFraction: Float { removeRoundedCorners ? 0.0 : 0.018 }
    var swapCardWidthMeters: Float { 0.55 }
    /// SBS confirmation card only — −20% vs swap/disconnect dialogs (matches ``SBSConfirmPanelMetrics``).
    var sbsConfirmCardWidthMeters: Float { swapCardWidthMeters * Float(SBSConfirmPanelMetrics.scale) }
    
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
    
    // Note: lastGeneratedCurve and lastGeneratedAspect moved to headStorage
    // to avoid "Modifying state during view update" warnings
    
    var body: some View {
        let baseView = mainContent
            .overlay(alignment: .bottom) { scaleHUDOverlay }
            .overlay { swapOverlay }
            .overlay { swapConfirmAttachment }
            .overlay { sbsConfirmAttachment }
            .overlay { disconnectConfirmAttachment }
            .overlay { presetPopupOverlay }
            .overlay {
                if showHeadFollowIntro {
                    HeadFollowIntroView(isPresented: $showHeadFollowIntro)
                }
            }
        
        let lifecycleApplied = baseView
            .task { await setupMaterial() }
            .onAppear(perform: setupScene)
            .onDisappear(perform: teardownScene)
            .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
                if shouldClose && !hasPerformedTeardown {
                    DispatchQueue.main.async { triggerCloseSequence() }
                }
            }
            .onChange(of: scenePhase) { oldValue, newValue in
                if newValue == .background {
                    if viewModel.activelyStreaming, streamMan != nil {
                        print("Suspending stream due to background")
                        needsResume = true
                        viewModel.isSuspendingForBackground = true
                        streamMan?.stopStream()
                        streamMan = nil
                        controllerSupport?.cleanup()
                        BluetoothMouseRouting.releasePointerLock()
                        controllerSupport = nil
                    }
                } else if newValue == .active {
                    if oldValue == .inactive, viewModel.activelyStreaming, inputMode == .controller {
                        // activateGamepadCapture already restores handlers — no separate call needed
                        streamGamepadSession.activateGamepadCapture()
                    }
                    if needsResume {
                        print("Resuming stream from background")
                        viewModel.isSuspendingForBackground = false
                        needsResume = false
                        self.renderGateOpen = true
                        self.hasPerformedTeardown = false
                        controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
                        connectionCallbacks.controllerSupport = controllerSupport
                        BluetoothMouseRouting.sync()
                        startStreamIfNeeded()
                        reclaimCurvedGamepadCaptureAfterBackground()

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
                            self.hasPerformedTeardown = false
                            controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
                            connectionCallbacks.controllerSupport = controllerSupport
                            BluetoothMouseRouting.sync()
                            startStreamIfNeeded()
                        }

                        reclaimCurvedGamepadCaptureAfterBackground()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            fixAudioForCurrentMode()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refreshAfterResume() }
                    } else {
                        streamGamepadSession.onSceneBecameActive()
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
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                restoreStreamAudioAfterMenuDismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mainViewWindowClosed)) { _ in
                self.restoreStreamAudioAfterMenuDismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chromaHaloColorsUpdated)) { notification in
                // Reactive 1 (Chromosphere): decoder pipeline handles edge bloom.
                // Reactive 2 (Corona): zone colors → edge strip textures.
                // Starfield: particles from center samples.
                guard dimLevel == 2 || dimLevel == 12 else { return }

                func simd3(_ key: String) -> SIMD3<Float>? {
                    notification.userInfo?[key] as? SIMD3<Float>
                }

                func uiColor(_ key: String) -> UIColor? {
                    guard let v = simd3(key) else { return nil }
                    let boost: Float = 1.35
                    return UIColor(red:   CGFloat(min(1, v.x * boost)),
                                   green: CGFloat(min(1, v.y * boost)),
                                   blue:  CGFloat(min(1, v.z * boost)),
                                   alpha: 1.0)
                }

                // Starfield: use center color for particles
                if dimLevel == 12, let c = uiColor("center") { targetReactiveColor = c }
                if dimLevel == 12,
                   let center = simd3("center") {
                    let brightness = max(center.x, max(center.y, center.z))
                    let uiColor = UIColor(red: CGFloat(center.x), green: CGFloat(center.y), blue: CGFloat(center.z), alpha: 1.0)
                    particleManager.update(color: uiColor, brightness: brightness)
                }
            }
        
        let dimChangesApplied = lifecycleApplied
            .onChange(of: environmentSphereLevel) { _, _ in
                persistCurvedEnvironmentSelection()
            }
            .onChange(of: newsetLevel) { _, _ in
                persistCurvedEnvironmentSelection()
            }
            .onChange(of: dimLevel) { oldValue, newValue in
                AmbientDimmingPersistence.save(newValue)
                applyLightingPresetVisuals(previousLevel: oldValue)
            }
            .onChange(of: viewModel.streamSettings.statsOverlay) { oldValue, newValue in
                handleStatsOverlay(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: viewModel.activelyStreaming) { oldValue, newValue in
                self.renderGateOpen = true
                handleActiveStreaming(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: videoMode) { _, _ in updateScreenMaterial() }
        
        let interactivityChangesApplied = dimChangesApplied
            .onChange(of: showMenuPanel) { _, _ in updateScreenInteractivity() }
            .onChange(of: showSwapConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: show3DConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: showDisconnectConfirm) { _, _ in updateScreenInteractivity() }
            .onChange(of: showHDRPanel) { _, isOpen in
                if isOpen { gazeController.cleanup() }
                if !isOpen {
                    hdrPresetRenamingActive = false
                }
                updateScreenInteractivity()
            }
            .onChange(of: hdrPresetRenamingActive) { _, isRenaming in
                if isRenaming { gazeController.cleanup() }
                updateScreenInteractivity()
            }
            .onChange(of: showScreenPresetPanel) { _, isOpen in
                if isOpen { gazeController.cleanup() }
                if !isOpen {
                    screenPresetRenamingActive = false
                }
                updateScreenInteractivity()
            }
            .onChange(of: screenPresetRenamingActive) { _, isRenaming in
                if isRenaming { gazeController.cleanup() }
                updateScreenInteractivity()
            }
            .onChange(of: inputMode) { oldValue, newValue in
                if newValue == .screenMove && oldValue != .screenMove {
                    showVirtualKeyboard = false
                    isKeyboardFocused = false
                    keyboardInput = ""
                    previousKeyboardInput = ""
                    captureScreenAdjustBaselines()
                    revealScreenAdjustHandles()
                } else if oldValue == .screenMove && newValue != .screenMove {
                    stopCurvatureDragMeshPump()
                    curvatureSliderDragging = false
                    headStorage.forceCollisionRegen = true
                }
                updateScreenInteractivity()
                syncCurvedGamepadSession()
            }
            .onChange(of: curvedGamepadSyncToken) { _, _ in
                syncCurvedGamepadSession()
                updateScreenInteractivity()
            }
            .onChange(of: streamPeekThroughActive) { _, _ in
                updateScreenInteractivity()
            }

        let desktopPickerChangesApplied = interactivityChangesApplied
            .onChange(of: showDesktopActionsPicker) { wasOpen, isOpen in
                handleDesktopActionsPickerDismissed(wasOpen: wasOpen, isOpen: isOpen)
            }

        let stateChangesApplied = desktopPickerChangesApplied
            .onChange(of: viewModel.streamSettings.swapABXYButtons) { _, newValue in
                controllerSupport?.setSwapABXYButtons(newValue)
            }
            .onChange(of: viewModel.streamSettings.reportControllerAsXbox) { _, newValue in
                controllerSupport?.setReportControllerAsXbox(newValue)
            }
            .onChange(of: hdrPanelSettings.brightness)  { _, _ in updateHDRParamsFromPanel() }
            .onChange(of: hdrPanelSettings.contrast)    { _, _ in updateHDRParamsFromPanel() }
            .onChange(of: hdrPanelSettings.saturation)  { _, _ in updateHDRParamsFromPanel() }
            .onChange(of: hdrPanelSettings.pqExposure)  { _, _ in updateHDRParamsFromPanel() }
            .onChange(of: hdrPanelSettings.referenceHDR) { _, _ in updateHDRParamsFromPanel() }

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
            Attachment(id: "hdrPanel") { hdrPanelAttachment }
            Attachment(id: "screenPresetPanel") { screenPresetPanelAttachment }
            Attachment(id: "desktopPicker") { desktopActionsPickerAttachment }
            Attachment(id: "stats") { statsAttachment }
            Attachment(id: "tutorial") { tutorialAttachment }
            Attachment(id: "presetPopup") {
                if showInlinePresetOverlay {
                    CenterPresetPopup(
                        text: presetOverlayText,
                        icon: presetOverlayIcon,
                        width: presetOverlayText.contains("Input Disabled") || presetOverlayText.contains("Input Enabled") ? 713 : 713
                    )
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
                if showVirtualKeyboard && inputMode != .screenMove {
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
                if viewModel.streamSettings.showMicButton && inputMode != .screenMove {
                    FloatingMicButton(
                        chromeOpacity: curvedMicChromeOpacity(),
                        colorStyle: MicButtonColorStyle.from(raw: viewModel.streamSettings.micButtonColorStyleRaw),
                        onActionPerformed: { micChromeFade.actionPerformed() }
                    )
                    .animation(.easeInOut(duration: 0.35), value: micChromeFade.controlsHighlighted)
                    .animation(.easeInOut(duration: 0.35), value: micChromeFade.hideControls)
                    .animation(.easeInOut(duration: 0.35), value: darkControlsMode)
                    .animation(.easeInOut(duration: 0.35), value: lightControlsMode)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "screenAdjustHandleTop") {
                if inputMode == .screenMove && !isLocked {
                    screenAdjustHandle(edge: .top)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "screenAdjustHandleBottom") {
                if inputMode == .screenMove && !isLocked {
                    screenAdjustHandle(edge: .bottom)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "screenAdjustHandleLeft") {
                if inputMode == .screenMove && !isLocked {
                    screenAdjustHandle(edge: .left)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "screenAdjustHandleRight") {
                if inputMode == .screenMove && !isLocked {
                    screenAdjustHandle(edge: .right)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            Attachment(id: "screenAdjustCurvaturePill") {
                // Always mount the full pill (hidden via opacity when inactive) so Home/Resume
                // cannot swap in a 1×1 placeholder and poison visualBounds-based scaling.
                ScreenAdjustCurvaturePill(
                    magnitude: curveMagnitude,
                    opacity: screenAdjustCurvaturePillShowsContent ? screenAdjustCurvaturePillOpacity() : 0,
                    interactionEnabled: screenAdjustCurvaturePillShowsContent && screenAdjustHandlesVisible,
                    onMagnitudeChanged: { magnitude in
                        headStorage.curvatureDragTarget = magnitude
                    },
                    onDragStarted: {
                        curvatureSliderDragging = true
                        headStorage.curvatureDragTarget = curveMagnitude
                        wakeScreenAdjustChromeForInteraction()
                        startCurvatureDragMeshPump()
                    },
                    onDragEnded: { magnitude in
                        stopCurvatureDragMeshPump()
                        setCurveMagnitude(CurvedCurvatureMapping.snappedMagnitude(magnitude))
                        curvatureSliderDragging = false
                        headStorage.forceCollisionRegen = true
                        startHighlightTimer()
                    }
                )
                .allowsHitTesting(screenAdjustCurvaturePillShowsContent && screenAdjustHandlesVisible)
                .animation(.easeInOut(duration: 0.35), value: hideControls)
                .animation(.easeInOut(duration: 0.35), value: controlsHighlighted)
            }
        }
        .upperLimbVisibility(shouldHideHands ? .hidden : .automatic)
        // Unified drag handles both Screen Move and Gaze Drag to prevent conflicts
        // Magnify and drag run simultaneously to allow pinch-to-zoom
        // Fully remove gestures from recognition graph while panels are open so attachment
        // controls (HDR sliders, pickers) receive pinches without disambiguation delay.
        .gesture(
            magnifyGesture.simultaneously(with: unifiedDragGesture),
            including: (!curvedGamepadModalBlocksOverlay && !hdrPresetRenamingActive && !screenPresetRenamingActive && !streamPeekThroughActive) ? .all : .none
        )
        .gesture(
            screenRevealTapGesture,
            including: (!curvedGamepadModalBlocksOverlay && !hdrPresetRenamingActive && !screenPresetRenamingActive && !streamPeekThroughActive && inputMode != .screenMove) ? .all : .none
        )
        .curvedOnWorldRecenter { phase in
            if phase == .ended {
                handleHeadFollowWorldRecenter()
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
            .neoClearBluePanelChrome(cornerRadius: 24)
            .frame(width: 420)
            .allowsHitTesting(true)
        }
    }
    
    @ViewBuilder
    private var disconnectConfirmAttachment: some View {
        if showDisconnectConfirm {
            let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
            let brandRed = Color(red: 0.9, green: 0.3, blue: 0.3)
            
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
                        .shadow(color: brandRed.opacity(0.5), radius: 18, x: 0, y: 10)
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
                        // userDidRequestDisconnect sets shouldCloseStream, which triggers
                        // triggerCloseSequence() — that handles openWindow + dismissImmersiveSpace
                        viewModel.userDidRequestDisconnect()
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
                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: brandRed.opacity(0.5), radius: 18, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDisconnectConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(brandNavy.opacity(0.6))
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
            .neoClearBluePanelChrome(cornerRadius: 24)
            .frame(width: 420)
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var sbsConfirmAttachment: some View {
        if show3DConfirm {
            let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
            let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

            VStack(spacing: SBSConfirmPanelMetrics.pt(24)) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandNavy, brandNavy.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: SBSConfirmPanelMetrics.pt(64), height: SBSConfirmPanelMetrics.pt(64))
                        .shadow(color: brandOrange.opacity(0.5), radius: SBSConfirmPanelMetrics.pt(18), x: 0, y: SBSConfirmPanelMetrics.pt(10))
                    Image(systemName: "view.3d")
                        .font(.system(size: SBSConfirmPanelMetrics.pt(28), weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: SBSConfirmPanelMetrics.pt(8)) {
                    Text("Enable SBS 3D")
                        .font(.system(size: SBSConfirmPanelMetrics.pt(22), weight: .bold))
                        .foregroundStyle(.white)
                    Text("Use software such as ReShade + Depth3D on your host PC to utilize SBS mode.")
                        .font(.system(size: SBSConfirmPanelMetrics.pt(15), weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SBSConfirmPanelMetrics.pt(8))
                }

                VStack(spacing: SBSConfirmPanelMetrics.pt(12)) {
                    Button {
                        show3DConfirm = false
                        videoMode = .sideBySide3D
                        updateScreenMaterial()
                    } label: {
                        HStack(spacing: SBSConfirmPanelMetrics.pt(10)) {
                            Text("Enable SBS 3D")
                                .font(.system(size: SBSConfirmPanelMetrics.pt(17), weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSConfirmPanelMetrics.pt(14))
                        .background(
                            RoundedRectangle(cornerRadius: SBSConfirmPanelMetrics.pt(16), style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [brandOrange, brandOrange.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SBSConfirmPanelMetrics.pt(16), style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: SBSConfirmPanelMetrics.pt(1.5)
                                )
                        )
                        .shadow(color: brandOrange.opacity(0.5), radius: SBSConfirmPanelMetrics.pt(18), x: 0, y: SBSConfirmPanelMetrics.pt(10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        show3DConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: SBSConfirmPanelMetrics.pt(17), weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSConfirmPanelMetrics.pt(14))
                            .background(
                                RoundedRectangle(cornerRadius: SBSConfirmPanelMetrics.pt(16), style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SBSConfirmPanelMetrics.pt(16), style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: SBSConfirmPanelMetrics.pt(1)
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SBSConfirmPanelMetrics.pt(28))
            .neoClearBluePanelChrome(
                cornerRadius: SBSConfirmPanelMetrics.pt(24),
                layoutScale: SBSConfirmPanelMetrics.scale
            )
            .frame(width: SBSConfirmPanelMetrics.pt(420))
            .allowsHitTesting(true)
        }
    }

    // MARK: - Scene Setup & Teardown

    private func setupScene() {
        if !viewModel.activelyStreaming {
            Task { @MainActor in
                viewModel.userDidRequestDisconnect()
                await dismissImmersiveSpace()
                viewModel.isImmersiveSpaceOpen = false
            }
            return
        }
        
       
        print("[CurvedDisplay] Re-initializing ControllerSupport with slotOffset: \(streamConfig.controllerSlotOffset)")
        self.controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
        connectionCallbacks.controllerSupport = self.controllerSupport
        BluetoothMouseRouting.sync()
        
        hasPerformedTeardown = false
        renderGateOpen = true
        viewModel.isStreamViewAlive = true
        
        dismissWindow(id: "mainView")
        dismissWindow(id: "dummy")
        
        
        isMenuOpen = false
        
        viewModel.streamSettings.statsOverlay = false
        statsTimer?.invalidate()
        statsTimer = nil
        statsOverlayText = ""
        
        CurvedCurvatureMapping.runMigrationIfNeeded()
        curveMagnitude = Float(savedCurveMagnitude)

        restorePersistedVisualStateAtStreamStart()
        
        // Initialize input mode from user preference
        let defaultMode = UserDefaults.standard.integer(forKey: "curved.defaultControlMode")
        inputMode = InputMode(rawValue: defaultMode) ?? .gazeControl
        print("[CurvedDisplay] Initialized input mode from settings: \(inputMode.displayName)")
        streamGamepadSession.displayStyle = .curved
        syncCurvedGamepadSession()
        
        // Load saved preset brightness values from UserDefaults
        for dimLevelKey in defaultPresetBrightness.keys {
            let savedValue = UserDefaults.standard.double(forKey: "preset.brightness.\(dimLevelKey)")
            if savedValue > 0 {
                presetBrightness[dimLevelKey] = savedValue
            }
        }
        
        // Initialize gaze controller with stream config
        gazeController.streamConfig = streamConfig
        sessionPinchDragUsesScroll = nil
        syncGazePinchDragMode()
        
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
            var p = safeHDRSettings.value
            p.mode = 1
            safeHDRSettings.value = p
            updateHDRParamsFromPanel()
            ensureHDRTextureMatchesSetting()
        }
        
        if let sceneID = AudioHelpers.captureAndPinStreamAudioScene(
            preferredIdentifier: AudioHelpers.immersiveSpaceSceneIdentifier()
        ) {
            self.immersiveSpaceSceneID = sceneID
        }
        
        fixAudioForCurrentMode()
        
        let wasFollowPersisted = UserDefaults.standard.bool(forKey: kCurvedLockedKey)
        let exitedSpecialMode = UserDefaults.standard.bool(forKey: kCurvedSpecialModeExitKey)
            || wasFollowPersisted

        UserDefaults.standard.set(false, forKey: kCurvedLockedKey)
        UserDefaults.standard.set(false, forKey: kCurvedSpecialModeExitKey)
        isLocked = false
        headFollowLocalOffset = CurvedFirstLaunch.defaultHeadFollowLocalOffset

        if exitedSpecialMode {
            applyDefaultLaunchPlacement()
        } else if UserDefaults.standard.bool(forKey: "curved.restoreScreenPresetOnLaunch") {
            applyScreenPreset(slot: screenPresetSettings.activePresetSlot, showToast: false, atLaunch: true)
        } else {
            applyFirstLaunchDefaultsToState(scheduleHeadPlacement: true)
        }
        self.targetScale = self.screenScale
        headStorage.streamTransformReady = true
        
        hideTimer?.invalidate()
        hideTimer = nil
        hideControls = false
        
        openedMainAfterDisconnect = false
        
        if viewModel.streamSettings.uikitPreset != 0 {
            viewModel.streamSettings.uikitPreset = 0
        }
        applyCurvedUIKitPreset(0)
    }
    
    private func restorePersistedVisualStateAtStreamStart() {
        let lightingLevel = AmbientDimmingPersistence.load()
        let persisted = CurvedEnvironmentPersistence.load(extraSkyboxCount: extraSkyboxNames.count)

        // Lighting wins when both were persisted (e.g. crash before teardown cleared env keys).
        if lightingLevel != 0 {
            restorePersistedDimLevelAtStreamStart()
            return
        }

        if persisted.newset > 0 {
            newsetLevel = persisted.newset
            environmentSphereLevel = 0
            applyEnvironmentExclusiveVisualState()
        } else if persisted.sphere > 0 {
            environmentSphereLevel = persisted.sphere
            newsetLevel = 0
            applyEnvironmentExclusiveVisualState()
        } else {
            restorePersistedDimLevelAtStreamStart()
        }
    }

    private func applyEnvironmentExclusiveVisualState() {
        dimLevel = 0
        viewModel.streamSettings.dimPassthrough = true
        videoDecoder?.isReactiveDimmingEnabled = false
        stopMoonlightCycle()
        stopTideCycle()
        stopReactiveLerp()
        updateChromosphereMesh()
        updateDimmerDomesState()
    }

    private func restorePersistedDimLevelAtStreamStart() {
        let level = AmbientDimmingPersistence.load()
        dimLevel = level
        viewModel.streamSettings.dimPassthrough = (level != 0)
        stopMoonlightCycle()
        stopTideCycle()
        if level == 11 {
            startMoonlightCycle()
        }
        applyLightingPresetVisuals(previousLevel: 0)
    }

    /// Re-applies Chromosphere / decoder reactive flags once the stream has a first frame (and halo texture when available).
    private func syncReactiveLightingVisualsAfterFramesReady() {
        applyLightingPresetVisuals(previousLevel: dimLevel)
    }

    /// Single entry point for dim-level visuals (picker, persistence restore, first-frame sync).
    private func applyLightingPresetVisuals(previousLevel: Int) {
        videoDecoder?.isReactiveDimmingEnabled = (dimLevel == 2 || dimLevel == 12)
        videoDecoder?.chromaHaloCoronaMode = 0

        if dimLevel == 12 {
            startReactiveLerp()
        } else {
            stopReactiveLerp()
        }

        if dimLevel == 2 {
            applySavedReactive1ReachToChromospherePipeline()
        }

        if dimLevel == 10 {
            startTideCycle()
        } else {
            stopTideCycle()
        }

        updateChromosphereMesh()
        updateDimmerDomesState()
    }

    private func persistCurvedEnvironmentSelection() {
        CurvedEnvironmentPersistence.save(sphere: environmentSphereLevel, newset: newsetLevel)
    }

    private func teardownScene() {
        let exitingSpecialMode = isLocked
        if isLocked {
            setHeadFollowActive(false)
        }
        UserDefaults.standard.set(exitingSpecialMode, forKey: kCurvedSpecialModeExitKey)
        UserDefaults.standard.set(false, forKey: kCurvedLockedKey)
        inputModeBeforeHeadFollow = nil
        inputModeBeforeDesktopPicker = nil
        handInputDisabledBeforeDesktopPicker = nil
        endDesktopAltTabSession()
        clearStreamPeekThroughIfNeeded()
        AmbientDimmingPersistence.save(dimLevel)
        persistCurvedEnvironmentSelection()

        statsTimer?.invalidate()
        statsTimer = nil
        stopCurvatureDragMeshPump()
        stopMoonlightCycle()
        stopTideCycle()
        stopReactiveLerp()
        cancelReactiveSphereEnvelopeIntro(resetDomeVisuals: true)
        viewModel.isStreamViewAlive = false
        headStorage.streamTransformReady = false
        
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
            // FIX: Defer state modification to prevent "Modifying state during view update" warnings
            DispatchQueue.main.async {
                self.renderGateOpen = true
            }
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
    
    private var effectivePinchDragUsesScroll: Bool {
        sessionPinchDragUsesScroll ?? viewModel.streamSettings.gazePinchDragScrollMode
    }
    
    private func syncGazePinchDragMode() {
        gazeController.pinchDragUsesScroll = effectivePinchDragUsesScroll
    }
    
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
                    if activeScreenAdjustHandle != nil || curvatureSliderDragging { return }
                    hideTimer?.invalidate()
                    if isLocked {
                        guard let head = headStorage.headAnchor else { return }
                        if startHeadFollowOrbit == nil {
                            let orbit = CurvedFirstLaunch.orbit(from: headFollowLocalOffset)
                            startHeadFollowOrbit = SIMD3(orbit.yaw, orbit.pitch, orbit.radius)
                        }
                        let translation = value.convert(value.translation3D, from: .local, to: .scene)
                        let sceneDelta = SIMD4<Float>(translation.x, translation.y, translation.z, 0)
                        let localDelta4 = simd_inverse(head.transformMatrix(relativeTo: nil)) * sceneDelta
                        let localDelta = SIMD3<Float>(localDelta4.x, localDelta4.y, localDelta4.z)
                        headFollowLocalOffset = applyOrbitDragDelta(
                            startOrbit: startHeadFollowOrbit!,
                            localDelta: localDelta
                        )
                    } else {
                        if startDragPosition == nil {
                            startDragPosition = screenPosition
                        }
                        let translation = value.convert(value.translation3D, from: .local, to: .scene)
                        guard let startPos = startDragPosition else { break }
                        var proposed = startPos + simd_float3(translation.x, translation.y, translation.z)
                        proposed.x = min(max(proposed.x, -allowedLateralMax), allowedLateralMax)
                        screenPosition = proposed
                    }
                    headStorage.lastDragTime = CACurrentMediaTime()
                    
                case .gazeControl:
                    // --- GAZE CONTROL LOGIC ---
                    guard !isHandGazeInputDisabled else { return }
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
                    let didDrag = (startDragPosition != nil || startHeadFollowOrbit != nil)
                    startDragPosition = nil
                    startHeadFollowOrbit = nil
                    if didDrag {
                        controlsHighlighted = false
                        startHighlightTimer()
                    }
                    
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
    
    /// Degrees per drag point — attachment drags are 2D; edge axis maps seated pull-toward-you.
    private let screenAdjustHandleDragScale: Float = 0.22
    
    private var screenAdjustHandlesVisible: Bool {
        inputMode == .screenMove && !isLocked
    }
    
    private func captureScreenAdjustBaselines() {
        screenAdjustBaselineTilt = tiltAngle
        screenAdjustBaselineYaw = yawAngle
    }
    
    private func resetScreenAdjustToDefaults() {
        tiltAngle = 0
        yawAngle = 0
        savedTiltAngle = 0
        savedYawAngle = 0
        screenAdjustBaselineTilt = 0
        screenAdjustBaselineYaw = 0
        startDragPosition = nil
        
        screenScale = CurvedFirstLaunch.defaultScale
        targetScale = CurvedFirstLaunch.defaultScale
        
        // Same deferred head placement as first install / leaving Head Follow — not sync placement during long-press.
        screenPosition = CurvedFirstLaunch.placeholderPosition
        headStorage.pendingFirstLaunchHeadPlacement = true
        headStorage.saveTransformAfterDefaultPlacement = true
        
        setCurveMagnitude(CurvatureTick.r1800.magnitude)
        headStorage.forceCollisionRegen = true

        presetOverlayText = "Screen reset to default"
        presetOverlayIcon = "arrow.counterclockwise"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
        }
    }
    
    private func inputModeLongPressAction() {
        switch inputMode {
        case .screenMove:
            resetScreenAdjustToDefaults()
        case .gazeControl:
            isHandGazeInputDisabled.toggle()
            presetOverlayText = isHandGazeInputDisabled ? "Screen Input Disabled" : "Screen Input Enabled"
            presetOverlayIcon = isHandGazeInputDisabled ? "lock.fill" : (
                viewModel.streamSettings.curvedGazeUseTouchMode ? "hand.point.up.left.fill" : inputMode.icon
            )
            showInlinePresetOverlay = true
            presetOverlayTimer?.invalidate()
            presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
            }
        case .controller:
            break
        }
    }
    
    /// Side handles only — right: 40° clockwise from entry baseline; left: 40° counter-clockwise.
    private func clampScreenAdjustYawForSideHandle(_ proposed: Float, edge: ScreenAdjustHandleEdge) -> Float {
        let baseline = screenAdjustBaselineYaw
        let maxDelta = CurvedFirstLaunch.maxScreenAdjustSideYawDegrees
        switch edge {
        case .right:
            return min(max(proposed, baseline - maxDelta), baseline)
        case .left:
            return min(max(proposed, baseline), baseline + maxDelta)
        default:
            return proposed
        }
    }
    
    /// Tilt can rotate away from the Screen Adjust entry angle on one side only; pushing back stops at that baseline.
    private func clampScreenAdjustTilt(_ proposed: Float, fromTop: Bool) -> Float {
        let baseline = screenAdjustBaselineTilt
        let maxDelta = CurvedFirstLaunch.maxTiltDegrees
        if fromTop {
            return min(max(proposed, baseline), baseline + maxDelta)
        }
        return min(max(proposed, baseline - maxDelta), baseline)
    }
    
    private func commitScreenAdjustTilt(_ proposed: Float, fromTop: Bool) {
        tiltAngle = CurvedFirstLaunch.clampTilt(clampScreenAdjustTilt(proposed, fromTop: fromTop))
        savedTiltAngle = Double(tiltAngle)
    }
    
    private func commitScreenAdjustYawForSideHandle(_ proposed: Float, edge: ScreenAdjustHandleEdge) {
        yawAngle = CurvedFirstLaunch.clampYaw(clampScreenAdjustYawForSideHandle(proposed, edge: edge))
        savedYawAngle = Double(yawAngle)
    }
    
    /// Center-pivot: each edge maps drag so pulling that handle toward you rotates around screen center.
    private func centerPivotPullAmount(from translation: CGSize, edge: ScreenAdjustHandleEdge) -> Float {
        let tw = Float(translation.width)
        let th = Float(translation.height)
        switch edge {
        case .top:
            // Pull top toward chest — hand/drag moves down toward you.
            return th * screenAdjustHandleDragScale
        case .bottom:
            // Same swing as before; negate so pull-toward-you (not push) drives it.
            return -th * screenAdjustHandleDragScale
        case .right:
            // Overhead: pull yellow (right) toward you → clockwise around center → +yaw.
            return -tw * screenAdjustHandleDragScale
        case .left:
            // Mirror of right: pull left toward you → opposite yaw from right.
            return tw * screenAdjustHandleDragScale
        }
    }
    
    private func applyScreenAdjustHandleDrag(edge: ScreenAdjustHandleEdge, translation: CGSize) {
        let pull = centerPivotPullAmount(from: translation, edge: edge)
        switch edge {
        case .top:
            if startTiltForDrag == nil { startTiltForDrag = tiltAngle }
            guard let startTilt = startTiltForDrag else { return }
            commitScreenAdjustTilt(startTilt + pull, fromTop: true)
        case .bottom:
            if startTiltForDrag == nil { startTiltForDrag = tiltAngle }
            guard let startTilt = startTiltForDrag else { return }
            // Mirror of top: pull toward you decreases tilt; fromTop:false allows below baseline.
            commitScreenAdjustTilt(startTilt - pull, fromTop: false)
        case .right:
            if startYawForDrag == nil { startYawForDrag = yawAngle }
            guard let startYaw = startYawForDrag else { return }
            commitScreenAdjustYawForSideHandle(startYaw - pull, edge: .right)
        case .left:
            if startYawForDrag == nil { startYawForDrag = yawAngle }
            guard let startYaw = startYawForDrag else { return }
            commitScreenAdjustYawForSideHandle(startYaw + pull, edge: .left)
        }
    }
    
    private func wakeScreenAdjustChromeForInteraction() {
        hideTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.3)) {
            hideControls = false
            controlsHighlighted = true
        }
    }
    
    private func revealScreenAdjustHandles() {
        guard !isLocked else { return }
        wakeScreenAdjustChromeForInteraction()
        startHighlightTimer()
    }
    
    /// Matches top-bar fade tiers; grabbed handle stays full brightness on first drag frame.
    private func screenAdjustHandleDisplayOpacity(for edge: ScreenAdjustHandleEdge) -> CGFloat {
        guard screenAdjustHandlesVisible else { return 0 }
        if activeScreenAdjustHandle == edge { return 1.0 }
        if controlsHighlighted { return 1.0 }
        if !hideControls { return fadedTopControlsInactiveOpacity() }
        return fadedTopControlsDormantOpacity()
    }

    private var screenAdjustCurvaturePillShowsContent: Bool {
        inputMode == .screenMove && !isLocked
    }

    private func screenAdjustCurvaturePillOpacity() -> CGFloat {
        guard screenAdjustHandlesVisible else { return 0 }
        if curvatureSliderDragging { return 1.0 }
        if controlsHighlighted { return 1.0 }
        if !hideControls { return fadedTopControlsInactiveOpacity() }
        return fadedTopControlsDormantOpacity()
    }

    private func screenAdjustCurvaturePillLocalPosition() -> SIMD3<Float> {
        let halfHeight = CURVED_MAX_WIDTH_METERS * screenAspect * 0.5
        let uv = SIMD2<Float>(0.5, 1)
        let normal = screenAdjustSurfaceNormal(uv: uv)
        let surfaceZ = uvTo3DPosition(uv: uv).z
        let gapBelowScreen: Float = 0.035
        return SIMD3(0, -(halfHeight + gapBelowScreen), surfaceZ + normal.z * 0.06 + 0.02)
    }

    private func measureCurvaturePillScale(for pillEnt: Entity) -> Float? {
        let bounds = pillEnt.visualBounds(relativeTo: screen)
        guard bounds.extents.x > 0 else { return nil }
        let currentScaleX = max(pillEnt.scale.x, 0.0001)
        let unscaledWidth = Float(bounds.extents.x) / currentScaleX
        guard unscaledWidth >= CurvaturePillScalePolicy.minUnscaledWidthMeters else { return nil }
        let desiredLocalWidth = CURVED_MAX_WIDTH_METERS * CurvaturePillScalePolicy.desiredLocalWidthFactor
        var scale = desiredLocalWidth / unscaledWidth
        scale = min(max(scale, CurvaturePillScalePolicy.minScale), CurvaturePillScalePolicy.maxScale)
        return scale
    }

    private func positionScreenAdjustCurvaturePill(attachments: RealityViewAttachments) {
        guard let pillEnt = attachments.entity(for: "screenAdjustCurvaturePill") else { return }
        if pillEnt.parent !== screen { screen.addChild(pillEnt) }
        pillEnt.position = screenAdjustCurvaturePillLocalPosition()

        let scale: Float
        if screenAdjustHandlesVisible {
            // Never remeasure when entering Screen Adjust — use cache or fallback only.
            scale = headStorage.curvaturePillStableScale ?? CurvaturePillScalePolicy.fallbackScale
            pillEnt.components.remove(OpacityComponent.self)
        } else {
            if headStorage.curvaturePillStableScale == nil,
               let measured = measureCurvaturePillScale(for: pillEnt) {
                headStorage.curvaturePillStableScale = measured
            }
            scale = headStorage.curvaturePillStableScale ?? CurvaturePillScalePolicy.fallbackScale
            pillEnt.components.set(OpacityComponent(opacity: 0))
        }
        pillEnt.scale = [scale, scale, scale]
    }
    
    @ViewBuilder
    private func screenAdjustHandle(edge: ScreenAdjustHandleEdge) -> some View {
        let isActive = activeScreenAdjustHandle == edge
        Image(systemName: isActive ? edge.systemImageFill : edge.systemImage)
            .font(.system(size: ScreenAdjustHandleChrome.iconFontSize))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(width: ScreenAdjustHandleChrome.iconSize, height: ScreenAdjustHandleChrome.iconSize)
            .padding(ScreenAdjustHandleChrome.ringPadding)
            .glassBackgroundEffect()
            .contentShape(Circle())
            .scaleEffect(isActive ? 1.1 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isActive)
            .opacity(screenAdjustHandleDisplayOpacity(for: edge))
            .animation(.easeInOut(duration: 0.35), value: hideControls)
            .animation(.easeInOut(duration: 0.35), value: controlsHighlighted)
            .allowsHitTesting(screenAdjustHandlesVisible)
            .highPriorityGesture(screenAdjustHandleDragGesture(for: edge))
            .sensoryFeedback(.impact(weight: .medium), trigger: screenAdjustHandleFeedbackTrigger)
    }
    
    private func screenAdjustHandleDragGesture(for edge: ScreenAdjustHandleEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard screenAdjustHandlesVisible else { return }
                let wasInactive = activeScreenAdjustHandle == nil
                activeScreenAdjustHandle = edge
                if wasInactive {
                    wakeScreenAdjustChromeForInteraction()
                    screenAdjustHandleFeedbackTrigger += 1
                }
                applyScreenAdjustHandleDrag(edge: edge, translation: value.translation)
            }
            .onEnded { _ in
                activeScreenAdjustHandle = nil
                let didDrag = startTiltForDrag != nil || startYawForDrag != nil
                startTiltForDrag = nil
                startYawForDrag = nil
                if didDrag {
                    controlsHighlighted = false
                    startHighlightTimer()
                }
            }
    }
    
    private func screenAdjustSurfaceNormal(uv: SIMD2<Float>) -> SIMD3<Float> {
        let curveMagnitude = effectiveCurveMagnitude
        let maxCurveAngle: Float = CURVED_MAX_ANGLE
        let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 2.0))
        guard currentAngle >= 0.0001 else { return SIMD3(0, 0, 1) }
        let theta = (uv.x - 0.5) * currentAngle
        return simd_normalize(SIMD3(-sin(theta), 0, cos(theta)))
    }
    
    private func screenAdjustHandleLocalPosition(for edge: ScreenAdjustHandleEdge) -> SIMD3<Float> {
        let outward: Float = 0.06
        let edgeInset: Float = 0.12
        let halfHeight = CURVED_MAX_WIDTH_METERS * screenAspect * 0.5
        
        switch edge {
        case .top:
            let uv = SIMD2<Float>(0.5, 0)
            let normal = screenAdjustSurfaceNormal(uv: uv)
            let surfaceZ = uvTo3DPosition(uv: uv).z
            return SIMD3(0, halfHeight + edgeInset, surfaceZ + normal.z * outward + 0.02)
        case .bottom:
            let uv = SIMD2<Float>(0.5, 1)
            let normal = screenAdjustSurfaceNormal(uv: uv)
            let surfaceZ = uvTo3DPosition(uv: uv).z
            return SIMD3(0, -(halfHeight + edgeInset), surfaceZ + normal.z * outward + 0.02)
        case .left:
            let uv = SIMD2<Float>(0, 0.5)
            let normal = screenAdjustSurfaceNormal(uv: uv)
            let edgePoint = uvTo3DPosition(uv: uv)
            return SIMD3(edgePoint.x - edgeInset, edgePoint.y, edgePoint.z + normal.z * outward + 0.02)
        case .right:
            let uv = SIMD2<Float>(1, 0.5)
            let normal = screenAdjustSurfaceNormal(uv: uv)
            let edgePoint = uvTo3DPosition(uv: uv)
            return SIMD3(edgePoint.x + edgeInset, edgePoint.y, edgePoint.z + normal.z * outward + 0.02)
        }
    }
    
    private func scaleScreenAdjustHandleEntity(_ handleEnt: Entity, screen: Entity) {
        let bounds = handleEnt.visualBounds(relativeTo: screen)
        guard bounds.extents.y > 0.001 else { return }
        let currentScaleY = max(handleEnt.scale.y, 0.0001)
        let unscaledTotalHeight = Float(bounds.extents.y) / currentScaleY
        let layoutHeight = Float(ScreenAdjustHandleChrome.circleDiameter)
        let iconUnscaledHeight = unscaledTotalHeight * (Float(ScreenAdjustHandleChrome.iconSize) / layoutHeight)
        let targetHeight: Float = {
            if let controls = headStorage.controlsEntity {
                let controlsHeight = controls.visualBounds(relativeTo: screen).extents.y
                if controlsHeight > 0 { return controlsHeight * 0.72 }
            }
            return 0.042
        }()
        let scale = targetHeight / iconUnscaledHeight
        handleEnt.scale = [scale, scale, scale]
    }
    
    private func positionScreenAdjustHandles(attachments: RealityViewAttachments) {
        let visible = screenAdjustHandlesVisible
        
        for edge in ScreenAdjustHandleEdge.allCases {
            guard let handleEnt = attachments.entity(for: edge.attachmentID) else { continue }
            if handleEnt.parent !== screen { screen.addChild(handleEnt) }
            if visible {
                handleEnt.position = screenAdjustHandleLocalPosition(for: edge)
                scaleScreenAdjustHandleEntity(handleEnt, screen: screen)
                handleEnt.components.remove(OpacityComponent.self)
            } else {
                handleEnt.components.set(OpacityComponent(opacity: 0))
            }
        }
    }
    
    var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(screen)
            .onChanged { value in
                if hideControls && inputMode != .screenMove { return }
                if isLocked {
                    guard inputMode == .screenMove else { return }
                }
                hideTimer?.invalidate()
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
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.25)) {
                            self.showScaleHUD = false
                        }
                    }
                }
            }
            .onEnded { _ in
                gestureInitialScale = nil
                scaleHUDFadeTimer?.invalidate()
                scaleHUDFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.25)) {
                            self.showScaleHUD = false
                        }
                    }
                }
                controlsHighlighted = false
                startHighlightTimer()
            }
    }
    
    // MARK: - Gaze Control Gestures
    
    var screenRevealTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(screen)
            .onEnded { _ in
                guard inputMode != .screenMove else { return }
                guard viewModel.activelyStreaming && !showMenuPanel && !showSwapConfirm && !showDisconnectConfirm && !showCurvedTutorial else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                fixAudioForCurrentMode()
            }
    }

    var gazeTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(screen)
            .onEnded { value in
                guard inputMode == .gazeControl else {
                    print("[Gaze] Tap ignored - not in gaze control mode (current: \(inputMode))")
                    return
                }
                guard !isHandGazeInputDisabled else { return }
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
        
       
        let curveMagnitude = effectiveCurveMagnitude
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

    // headAnchor, lastHeadWorldPos, and lastDragTime moved to headStorage
    // to avoid "Modifying state during view update" warnings

    private let allowedLateralMax: Float = 3.0
    
    // MARK: - RealityView Attachments

    /// Modals / pickers where the center input overlay must not steal taps (SwiftUI hit-testing only).
    private var curvedGamepadModalBlocksOverlay: Bool {
        showHDRPanel || showScreenPresetPanel || show3DConfirm || showSwapConfirm || showDisconnectConfirm
            || showEnvironmentPicker || showDimmingPicker || showDesktopActionsPicker
            || showCurvedTutorial || showMenuPanel || streamPeekThroughActive
    }

  private var curvedGamepadSyncToken: String {
        "\(inputMode.rawValue)|\(showHDRPanel)|\(showScreenPresetPanel)|\(show3DConfirm)|\(showSwapConfirm)|\(showDisconnectConfirm)|\(showEnvironmentPicker)|\(showDimmingPicker)|\(showDesktopActionsPicker)|\(showCurvedTutorial)|\(showMenuPanel)|\(showVirtualKeyboard)|\(viewModel.activelyStreaming)"
    }

    private func syncCurvedGamepadSession() {
        streamGamepadSession.displayStyle = .curved
        streamGamepadSession.setStreamActive(viewModel.activelyStreaming)
        streamGamepadSession.setControllerModeActive(inputMode == .controller)
        streamGamepadSession.setModalBlocking(curvedGamepadModalBlocksOverlay || showVirtualKeyboard)
    }

    /// Re-attach gamepad capture after background resume or controllerSupport recreation.
    private func reclaimCurvedGamepadCaptureAfterBackground() {
        syncCurvedGamepadSession()
        guard inputMode == .controller, controllerSupport != nil else { return }
        // activateGamepadCapture already restores handlers — no separate call needed
        streamGamepadSession.activateGamepadCapture()
    }

    @ViewBuilder
    private var inputCaptureAttachment: some View {
        // Full-screen overlay steals RealityKit attachment hits; collapse it while any panel is open.
        if let support = controllerSupport, !curvedGamepadModalBlocksOverlay {
            InputCaptureView(
                controllerSupport: support,
                gamepadSession: streamGamepadSession,
                showKeyboard: $showVirtualKeyboard,
                isControllerMode: inputMode == .controller,
                modalBlocksOverlay: curvedGamepadModalBlocksOverlay,
                suspendLegacyFirstResponder: hdrPresetRenamingActive || screenPresetRenamingActive,
                curvature: effectiveCurveMagnitude,
                streamConfig: streamConfig,
                headStorage: headStorage
            )
            .frame(width: 1920, height: 1920 / CGFloat(screenAspect))
            .opacity(0.01)
            .allowsHitTesting(showVirtualKeyboard || inputMode == .controller)
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
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
                        AmbientDimmingPersistence.save(val)
                        updateDimmerDomesState()
                    }
                ),
                extraSkyboxNames: extraSkyboxNames
            )
            .allowsHitTesting(true)
            .transition(.identity)
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var hdrPanelAttachment: some View {
        if showHDRPanel {
            HDRControlPanel(
                settings: hdrPanelSettings,
                isPresented: $showHDRPanel,
                onLiveUpdate: { updateHDRParamsFromPanel() },
                attachmentLayoutScale: 1.0,
                dimInactiveGradingControlsWhenReferenceHDR: true,
                onRenamingActiveChanged: { hdrPresetRenamingActive = $0 }
            )
            .allowsHitTesting(true)
            .transition(.identity)
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var screenPresetPanelAttachment: some View {
        if showScreenPresetPanel {
            ScreenPresetPanel(
                settings: screenPresetSettings,
                isPresented: $showScreenPresetPanel,
                attachmentLayoutScale: 1.0,
                onRenamingActiveChanged: { screenPresetRenamingActive = $0 },
                onApplyPreset: { slot in
                    applyScreenPreset(slot: slot)
                },
                onSaveCurrentToActive: {
                    captureCurrentScreenToPreset(slot: screenPresetSettings.activePresetSlot)
                },
                isHeadFollowActive: isLocked
            )
            .allowsHitTesting(true)
            .transition(.identity)
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var desktopActionsPickerAttachment: some View {
        if showDesktopActionsPicker {
            DesktopActionsPickerView(
                isPresented: $showDesktopActionsPicker,
                onActionPerformed: { action in
                    handleDesktopActionPerformed(action)
                }
            )
            .allowsHitTesting(true)
            .transition(.identity)
        } else {
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
        }
    }

    private func closeStreamPickers(
        exceptDesktop: Bool = false,
        exceptHDR: Bool = false,
        exceptScreenPreset: Bool = false,
        exceptDimming: Bool = false,
        exceptEnvironment: Bool = false
    ) {
        if !exceptDesktop { showDesktopActionsPicker = false }
        if !exceptHDR { showHDRPanel = false }
        if !exceptScreenPreset { showScreenPresetPanel = false }
        if !exceptDimming { showDimmingPicker = false }
        if !exceptEnvironment { showEnvironmentPicker = false }
    }

    private func presentDesktopActionToast(_ action: DesktopAction) {
        presetOverlayText = action.toastLabel
        presetOverlayIcon = action.systemImage
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
        }
    }

    private func endDesktopAltTabSession() {
        desktopAltTabInteractionActive = false
        DesktopKeyboardSender.releaseStickyModifiersOnHost()
        restoreInputModeAfterDesktopMenuIfNeeded()
    }

    /// Desktop commands need gaze/touch on the stream — switch from controller or screen-adjust.
    private func activateHandInputForDesktopMenu() {
        guard inputMode != .gazeControl else { return }
        inputModeBeforeDesktopPicker = inputMode
        gazeController.cleanup()
        if showVirtualKeyboard {
            showVirtualKeyboard = false
            isKeyboardFocused = false
        }
        inputMode = .gazeControl
        gazeController.streamConfig = streamConfig
        if isHandGazeInputDisabled {
            handInputDisabledBeforeDesktopPicker = true
            isHandGazeInputDisabled = false
        }
        syncCurvedGamepadSession()
        updateScreenInteractivity()
    }

    private func restoreInputModeAfterDesktopMenuIfNeeded() {
        if let wasInputDisabled = handInputDisabledBeforeDesktopPicker {
            handInputDisabledBeforeDesktopPicker = nil
            isHandGazeInputDisabled = wasInputDisabled
        }
        guard let saved = inputModeBeforeDesktopPicker else { return }
        inputModeBeforeDesktopPicker = nil
        gazeController.cleanup()
        inputMode = saved
        if inputMode == .gazeControl {
            gazeController.streamConfig = streamConfig
        }
        syncCurvedGamepadSession()
        updateScreenInteractivity()
    }

    private func handleDesktopActionPerformed(_ action: DesktopAction) {
        presentDesktopActionToast(action)
        switch action {
        case .altTab, .cmdTab:
            desktopAltTabInteractionActive = true
            streamGamepadSession.clearHeldGamepadButtonsOnHost()
        case .escape:
            endDesktopAltTabSession()
            streamGamepadSession.suppressAfterDesktopAction()
        default:
            endDesktopAltTabSession()
            streamGamepadSession.suppressAfterDesktopAction()
        }
    }

    private func handleDesktopActionsPickerDismissed(wasOpen: Bool, isOpen: Bool) {
        if isOpen && !wasOpen {
            activateHandInputForDesktopMenu()
            return
        }
        guard wasOpen, !isOpen else { return }
        if desktopAltTabInteractionActive {
            streamGamepadSession.clearHeldGamepadButtonsOnHost()
            syncCurvedGamepadSession()
            return
        }
        restoreInputModeAfterDesktopMenuIfNeeded()
        DesktopKeyboardSender.releaseStickyModifiersOnHost()
        streamGamepadSession.suppressAfterDesktopAction()
    }

    private func toggleDesktopActionsPicker() {
        if showDesktopActionsPicker {
            if desktopAltTabInteractionActive {
                endDesktopAltTabSession()
            } else {
                restoreInputModeAfterDesktopMenuIfNeeded()
            }
        } else {
            activateHandInputForDesktopMenu()
        }
        showDesktopActionsPicker.toggle()
        if showDesktopActionsPicker {
            closeStreamPickers(exceptDesktop: true)
        }
        startHideTimer()
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
                        AmbientDimmingPersistence.save(val)
                        stopMoonlightCycle()
                        if val != 10 { stopTideCycle() }
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
                ),
                presetBrightness: Binding(
                    get: { presetBrightness },
                    set: { newValue in
                        presetBrightness = newValue
                        updateDimmerDomesState()
                    }
                ),
                defaultPresetBrightness: defaultPresetBrightness,
                onStarfieldTapCycle: {
                    let nextPreset = starDistancePreset.next()
                    starDistancePresetRawValue = nextPreset.rawValue
                    particleManager.updateDistancePreset(nextPreset)
                    presetOverlayText = "STAR DISTANCE: \(nextPreset.displayName.uppercased())"
                    presetOverlayIcon = "moon.stars.fill"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.15)) {
                                self.showInlinePresetOverlay = false
                            }
                        }
                    }
                },
                onReactive1TapCycle: {
                    Reactive1ChromosphereReach.advanceWrappedAndSave()
                    applySavedReactive1ReachToChromospherePipeline()
                }
            )
            .allowsHitTesting(true)
            .transition(.identity)
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(10)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.92))
        )
        .opacity(viewModel.streamSettings.statsOverlay && headStorage.statsScaleInitialized ? 1 : 0)
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
    
    /// Accordion method: icons stay in HStack; width/scale/opacity animate with staggered delays.
    private let collapsedMenuLeftCount: Int = 8
    private let collapsedMenuRightStart: Int = 8
    private let collapsedMenuExpandStep: Double = 0.05
    private let collapsedMenuCollapseStep: Double = 0.04
    /// Wait for accordion collapse to finish before fading single icon (maxDist*0.04 + spring settle).
    private let collapsedMenuHideDelay: Double = 0.8
    /// Reactive V1 Chromosphere washes the periphery — lift faded control chrome (~+20%).
    private var reactiveV1ControlOpacityInactiveBoost: CGFloat { 0.1 } // 0.5 × 20% rounded for clarity vs glow
    private var reactiveV1ControlOpacityDormantFloor: CGFloat { 0.20 } // +20 percentage points on near-zero dormant alpha
    /// Reactive V1 reach Wide+ (indexed ≥ 1): extra multiply on computed bar alpha before floors (ramped per wash step).
    private let reactiveV1ExpandedReachChromeMul: CGFloat = 1.2
    /// Baseline floors at Wide; `reactiveV1ExpandedReachWashStep()` adds more for Expanded / Maximum.
    private let reactiveV1ExpandedReachInactiveBarOpacityFloor: CGFloat = 0.955
    private let reactiveV1ExpandedReachDormantBarOpacityFloor: CGFloat = 0.66
    private let reactiveV1ExpandedReachDormantCapsuleOpacityFloor: CGFloat = 0.76
    private let reactiveV1ExpandedReachUltraThinCapsuleLight: CGFloat = 0.97
    private let reactiveV1ExpandedReachUltraThinCapsuleDark: CGFloat = 0.66
    
    /// Pass-through for original bar (when dynamic menu is off). No animation; keeps curvedControlsBarContent compiling.
    @ViewBuilder
    private func staggeredControl<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
    }

    private func reactive1UsesExpandedReachChromeBoost() -> Bool {
        dimLevel == 2 && Reactive1ChromosphereReach.clampedSavedIndex() >= 1
    }

    /// Wide / Expanded / Maximum: strong Chromosphere wash — idle and auto-hidden toolbar never dim below this (Standard & other dim modes unchanged).
    private let reactiveV1ExpandedReachMinFadedBarOpacity: CGFloat = 0.75

    private func clampBarOpacityForReactive1WidePlusChromosphere(_ opacity: CGFloat) -> CGFloat {
        guard reactive1UsesExpandedReachChromeBoost() else { return opacity }
        return max(opacity, reactiveV1ExpandedReachMinFadedBarOpacity)
    }

    /// Wide = 0, Expanded = 1, Maximum = 2 (only meaningful when `reactive1UsesExpandedReachChromeBoost()`).
    private func reactiveV1ExpandedReachWashStep() -> Int {
        guard reactive1UsesExpandedReachChromeBoost() else { return 0 }
        return min(2, max(0, Reactive1ChromosphereReach.clampedSavedIndex() - 1))
    }

    private func reactiveV1ExpandedReachInactiveBarOpacityFloorEffective() -> CGFloat {
        min(1.0, reactiveV1ExpandedReachInactiveBarOpacityFloor + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.024)
    }

    private func reactiveV1ExpandedReachDormantBarOpacityFloorEffective() -> CGFloat {
        min(1.0, reactiveV1ExpandedReachDormantBarOpacityFloor + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.085)
    }

    private func reactiveV1ExpandedReachDormantCapsuleOpacityFloorEffective() -> CGFloat {
        min(1.0, reactiveV1ExpandedReachDormantCapsuleOpacityFloor + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.075)
    }

    private func reactiveV1ExpandedReachUltraThinCapsuleLightEffective() -> CGFloat {
        min(1.0, reactiveV1ExpandedReachUltraThinCapsuleLight + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.014)
    }

    private func reactiveV1ExpandedReachUltraThinCapsuleDarkEffective() -> CGFloat {
        min(1.0, reactiveV1ExpandedReachUltraThinCapsuleDark + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.09)
    }

    private func reactiveV1ExpandedReachChromeMulEffective() -> CGFloat {
        guard reactive1UsesExpandedReachChromeBoost() else { return 1.0 }
        return min(1.45, reactiveV1ExpandedReachChromeMul + CGFloat(reactiveV1ExpandedReachWashStep()) * 0.07)
    }

    /// Reactive V1 (Chromosphere): wash periphery → stronger top chrome at wide+ reach tiers.
    private func usesReactiveAmbientControlChromeLift() -> Bool {
        dimLevel == 2
    }

    /// Strong top-bar opacity when Reactive V1 Chromosphere is at reach tier 2+ (indexed ≥ 1).
    private func applyReactiveV1ExpandedReachTopChromeFloors(barOpacity: CGFloat) -> CGFloat {
        guard reactive1UsesExpandedReachChromeBoost() else { return barOpacity }
        return min(1.0, max(barOpacity, reactiveV1ExpandedReachInactiveBarOpacityFloorEffective()))
    }

    private func applyReactiveV1ExpandedReachDormantBarFloor(_ opacity: CGFloat) -> CGFloat {
        guard reactive1UsesExpandedReachChromeBoost() else { return opacity }
        return min(1.0, max(opacity, reactiveV1ExpandedReachDormantBarOpacityFloorEffective()))
    }

    private func applyReactiveV1ExpandedReachDormantCapsuleFloor(_ opacity: CGFloat) -> CGFloat {
        guard reactive1UsesExpandedReachChromeBoost() else { return opacity }
        return min(1.0, max(opacity, reactiveV1ExpandedReachDormantCapsuleOpacityFloorEffective()))
    }

    /// `ultraThinMaterial` capsule behind the toolbar when controls are visible (not the faded-dormant state).
    private func topControlsUltraThinCapsuleOpacityWhenChromeVisible() -> CGFloat {
        if hideControls {
            return topControlsCapsuleBackgroundDormantOpacity()
        }
        if reactive1UsesExpandedReachChromeBoost() {
            let raw = darkControlsMode ? reactiveV1ExpandedReachUltraThinCapsuleDarkEffective() : reactiveV1ExpandedReachUltraThinCapsuleLightEffective()
            return clampBarOpacityForReactive1WidePlusChromosphere(raw)
        }
        if darkControlsMode {
            return 0.15
        }
        if lightControlsMode {
            return min(1, 0.7 * 1.5)
        }
        return 0.7
    }

    /// Drives `.animation` when cycling Reactive V1 reach so bar opacity snaps smoothly per tier.
    private var reactiveV1TopChromeAnimationAnchor: Int {
        dimLevel == 2 ? Reactive1ChromosphereReach.clampedSavedIndex() : -1
    }

    /// Top bar when visible but idle (Reactive V1 peripheral wash → lift faded chrome vs default 0.5).
    private func fadedTopControlsInactiveOpacity() -> CGFloat {
        let inactiveBase: CGFloat = darkControlsMode ? 0.12 : (lightControlsMode ? 1.0 : 0.5)
        if darkControlsMode || lightControlsMode || usesReactiveAmbientControlChromeLift() {
            if usesReactiveAmbientControlChromeLift() {
                let scale = inactiveBase / 0.5
                var o = min(1, inactiveBase + reactiveV1ControlOpacityInactiveBoost * scale)
                if reactive1UsesExpandedReachChromeBoost() { o = min(1, o * reactiveV1ExpandedReachChromeMulEffective()) }
                return clampBarOpacityForReactive1WidePlusChromosphere(applyReactiveV1ExpandedReachTopChromeFloors(barOpacity: o))
            }
            return inactiveBase
        }
        return 0.5
    }

    /// Top bar almost hidden (Reactive peripheral wash: dormant floor lifted; Chromosphere tiers 2–4 multiply further).
    private func fadedTopControlsDormantOpacity() -> CGFloat {
        if darkControlsMode {
            if usesReactiveAmbientControlChromeLift() {
                var o = min(1, 0.01 + reactiveV1ControlOpacityDormantFloor)
                if reactive1UsesExpandedReachChromeBoost() { o = min(1, o * reactiveV1ExpandedReachChromeMulEffective()) }
                return clampBarOpacityForReactive1WidePlusChromosphere(applyReactiveV1ExpandedReachDormantBarFloor(o))
            }
            return 0.01
        }
        if lightControlsMode {
            if usesReactiveAmbientControlChromeLift() {
                var o = min(1, 0.5 + reactiveV1ControlOpacityDormantFloor)
                if reactive1UsesExpandedReachChromeBoost() { o = min(1, o * reactiveV1ExpandedReachChromeMulEffective()) }
                return clampBarOpacityForReactive1WidePlusChromosphere(applyReactiveV1ExpandedReachDormantBarFloor(o))
            }
            return 0.5
        }
        switch dimLevel {
        case 4, 12: return 0.005
        case 2:
            var o = min(1, 0.015 + reactiveV1ControlOpacityDormantFloor)
            if reactive1UsesExpandedReachChromeBoost() { o = min(1, o * reactiveV1ExpandedReachChromeMulEffective()) }
            return clampBarOpacityForReactive1WidePlusChromosphere(applyReactiveV1ExpandedReachDormantBarFloor(o))
        default: return 0.05
        }
    }

    private func curvedMicChromeOpacity() -> CGFloat {
        if streamPeekThroughActive { return 1.0 }
        return !micChromeFade.hideControls
            ? (micChromeFade.controlsHighlighted ? 1.0 : fadedTopControlsInactiveOpacity())
            : fadedTopControlsDormantOpacity()
    }

    /// Glass pill behind icons when dormant — match bar floor so glyphs don’t flatten before the capsule.
    private func topControlsCapsuleBackgroundDormantOpacity() -> CGFloat {
        switch dimLevel {
        case 4, 12: return 0.005
        case 2:
            var o = min(1, 0.015 + reactiveV1ControlOpacityDormantFloor)
            if reactive1UsesExpandedReachChromeBoost() { o = min(1, o * reactiveV1ExpandedReachChromeMulEffective()) }
            return clampBarOpacityForReactive1WidePlusChromosphere(applyReactiveV1ExpandedReachDormantCapsuleFloor(o))
        default: return 0
        }
    }
    
    var topControlsBar: some View {
        Group {
            if viewModel.streamSettings.useCollapsedControlsMenu {
                curvedDynamicControlsBar
                    .opacity(!hideControls ? (controlsHighlighted ? 1.0 : fadedTopControlsInactiveOpacity()) : fadedTopControlsDormantOpacity())
                .animation(Animation.easeInOut(duration: 0.35), value: controlsHighlighted)
                .animation(Animation.easeInOut(duration: 0.35), value: hideControls)
                .animation(Animation.easeInOut(duration: 0.35), value: reactiveV1TopChromeAnimationAnchor)
                .animation(Animation.easeInOut(duration: 0.35), value: dimLevel)
                .animation(Animation.easeInOut(duration: 0.35), value: darkControlsMode)
                .animation(Animation.easeInOut(duration: 0.35), value: lightControlsMode)
                .sensoryFeedback(.impact(weight: .medium), trigger: controlTapFeedbackTrigger)
                .allowsHitTesting(true)
            } else {
                curvedOriginalControlsBar
            }
        }
    }
    
    /// Center button: tap to expand the dynamic menu.
    private var curvedCenterButton: some View {
        Button {
            if hideControls {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                controlsExpanded = true
            }
            startHideTimer()
            controlTapFeedbackTrigger += 1
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 24.07))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }
    
    /// Dynamic bar: collapsed = center only (no pill); expanded = full bar with pill. Both branches animate opacity/scale for smooth expand and collapse.
    private var curvedDynamicControlsBar: some View {
        ZStack {
            curvedCenterButton
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .opacity(controlsExpanded ? 0 : 1)
                .scaleEffect(controlsExpanded ? 0.88 : 1)
                .allowsHitTesting(!controlsExpanded)
            curvedControlsBarContent
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(topControlsUltraThinCapsuleOpacityWhenChromeVisible())
                }
                .opacity(controlsExpanded ? 1 : 0)
                .scaleEffect(controlsExpanded ? 1 : 0.88)
                .allowsHitTesting(controlsExpanded)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: controlsExpanded)
    }
    
    private var curvedIconHome: some View {
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
                    restoreStreamAudioAfterMenuDismiss()
                } else {
                    pushWindow(id: "mainView")
                    isMenuOpen = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { positionMenuWindow() }
                }
                guard viewModel.activelyStreaming && !showMenuPanel else { return }
                if hideControls {
                    withAnimation(.easeInOut(duration: 0.3)) { hideControls = false; controlsHighlighted = true }
                    startHighlightTimer()
                }
            },
            longPressAction: { restoreStreamAudioAfterMenuDismiss() },
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    private var curvedIconSpatialAudio: some View {
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
                    DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false } }
                }
            },
            longPressAction: {
                guard spatialAudioMode else { return }
                soundStageSize = soundStageSize.next()
                fixAudioForCurrentMode()
                presetOverlayText = "Sound Stage: \(soundStageSize.rawValue)"
                presetOverlayIcon = "person.spatialaudio.fill"
                showInlinePresetOverlay = true
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                }
            },
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    @ViewBuilder
    private var curvedIconStarDistance: some View {
        if dimLevel == 12 {
            LongPressControlBtn(
                label: starDistancePreset.displayName,
                systemImage: "moon.stars.fill",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                    let nextPreset = starDistancePreset.next()
                    starDistancePresetRawValue = nextPreset.rawValue
                    particleManager.updateDistancePreset(nextPreset)
                    presetOverlayText = "STAR DISTANCE: \(nextPreset.displayName.uppercased())"
                    presetOverlayIcon = "moon.stars.fill"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                    }
                    startHideTimer()
                },
                longPressAction: {
                    starDistancePresetRawValue = StarDistancePreset.close.rawValue
                    particleManager.updateDistancePreset(.close)
                    presetOverlayText = "STAR DISTANCE: CLOSE"
                    presetOverlayIcon = "moon.stars.fill"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                    }
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
        }
    }
    
    private var curvedIconDim: some View {
        LongPressControlBtn(
            label: dimButtonTitle,
            systemImage: dimButtonIcon,
            controlsHighlighted: $controlsHighlighted,
            hideControls: $hideControls,
            startHighlightTimer: startHighlightTimer,
            startHideTimer: startHideTimer,
            primaryAction: {
                guard !isLocked else {
                    presentHeadFollowBlockedOverlay(feature: "Lighting")
                    return
                }
                showDimmingPicker.toggle()
                if showDimmingPicker {
                    closeStreamPickers(exceptDimming: true)
                    stopMoonlightCycle()
                    stopReactiveLerp()
                }
            },
            longPressAction: {
                guard !isLocked else {
                    presentHeadFollowBlockedOverlay(feature: "Lighting")
                    return
                }
                dimLevel = 0
                videoDecoder?.isReactiveDimmingEnabled = false
                viewModel.streamSettings.dimPassthrough = false
                updateDimmerDomesState()
                stopMoonlightCycle()
                stopTideCycle()
                stopReactiveLerp()
                showDimPresetOverlay()
            },
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    private var curvedIconPreset: some View {
        makeControlButton(label: "Preset", systemImage: "camera.filters", action: {
            guard canChangePreset() else { return }
            let allowed: [Int32] = [0, 1, 2, 3]
            let cur = viewModel.streamSettings.uikitPreset
            let idx = allowed.firstIndex(of: cur) ?? 0
            let next = allowed[(idx + 1) % allowed.count]
            viewModel.streamSettings.uikitPreset = next
            applyCurvedUIKitPreset(next)
            presetCooldownUntil = Date().addingTimeInterval(0.3)
            presentFilterPresetCenterPopup(selectedPreset: next)
            startHideTimer()
        }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
    }
    
    private var curvedIcon3D: some View {
        makeControlButton(label: videoMode == .standard2D ? "Standard Display" : "3D", systemImage: "view.3d", action: {
            if videoMode == .standard2D { show3DConfirm = true }
            else { videoMode = .standard2D; updateScreenMaterial() }
        }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
    }
    
    private var curvedIconEnvironment: some View {
        LongPressControlBtn(
            label: environmentSphereButtonTitle,
            systemImage: "photo",
            controlsHighlighted: $controlsHighlighted,
            hideControls: $hideControls,
            startHighlightTimer: startHighlightTimer,
            startHideTimer: startHideTimer,
            primaryAction: {
                guard !isLocked else {
                    presentHeadFollowBlockedOverlay(feature: "Environment")
                    return
                }
                showEnvironmentPicker.toggle()
                if showEnvironmentPicker {
                    closeStreamPickers(exceptEnvironment: true)
                    stopMoonlightCycle()
                    stopReactiveLerp()
                }
                startHideTimer()
            },
            longPressAction: {
                guard !isLocked else {
                    presentHeadFollowBlockedOverlay(feature: "Environment")
                    return
                }
                environmentSphereLevel = 0
                newsetLevel = 0
                showEnvironmentPicker = false
                updateEnvironmentState()
                updateNewsetState()
                withAnimation(.easeInOut(duration: 0.25)) { viewModel.streamSettings.dimPassthrough = false }
            },
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    private var curvedIconStats: some View {
        makeControlButton(label: viewModel.streamSettings.statsOverlay ? "Hide Stats" : "Show Stats", systemImage: "wifi", action: {
            viewModel.streamSettings.statsOverlay.toggle()
        }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
    }
    
    @ViewBuilder
    private var curvedIconTaskManager: some View {
        if viewModel.streamSettings.showTaskManagerButton {
            makeControlButton(
                label: showDesktopActionsPicker ? "Close Desktop" : "Desktop",
                systemImage: "list.bullet.circle",
                action: {
                    toggleDesktopActionsPicker()
                    startHighlightTimer()
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
        }
    }
    
    private var curvedIconKeyboard: some View {
        makeControlButton(
            label: showVirtualKeyboard ? "Hide Keyboard" : "Show Keyboard",
            systemImage: showVirtualKeyboard ? "keyboard.fill" : "keyboard",
            action: {
                if inputMode == .controller && !showVirtualKeyboard {
                    gazeController.cleanup()
                    inputMode = .screenMove
                    updateScreenInteractivity()
                    presetOverlayText = "Switched to Screen Adjust Mode"
                    presetOverlayIcon = "arrow.up.and.down.and.arrow.left.and.right"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false } }
                    }
                }
                showVirtualKeyboard.toggle()
                if showVirtualKeyboard {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isKeyboardFocused = true }
                } else { isKeyboardFocused = false }
                startHighlightTimer()
            },
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    @ViewBuilder
    private var curvedIconBattery: some View {
        if viewModel.streamSettings.showControllerBattery {
            BatteryIndicatorView(
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer
            )
        }
    }
    
    private var curvedIconInputMode: some View {
        LongPressControlBtn(
            label: {
                if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode { return "Touch Control Mode" }
                return inputMode.displayName
            }(),
            systemImage: {
                if inputMode == .gazeControl && isHandGazeInputDisabled { return "lock.fill" }
                if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode { return "hand.point.up.left.fill" }
                return inputMode.icon
            }(),
            controlsHighlighted: $controlsHighlighted,
            hideControls: $hideControls,
            startHighlightTimer: startHighlightTimer,
            startHideTimer: startHideTimer,
            primaryAction: {
                gazeController.cleanup()
                inputMode = inputMode.next()
                if inputMode == .controller {
                    showVirtualKeyboard = false
                    isKeyboardFocused = false
                }
                syncCurvedGamepadSession()
                if inputMode == .gazeControl { gazeController.streamConfig = streamConfig }
                presetOverlayText = inputMode.modeSwitchOverlayName(gazeUsesTouchMode: viewModel.streamSettings.curvedGazeUseTouchMode)
                presetOverlayIcon = inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode ? "hand.point.up.left.fill" : inputMode.icon
                showInlinePresetOverlay = true
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                }
            },
            longPressAction: inputModeLongPressAction,
            onTapFeedback: { controlTapFeedbackTrigger += 1 }
        )
    }
    
    @ViewBuilder
    private var curvedIconCoopIndicator: some View {
        if viewModel.isCoopSession {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.system(size: 16, weight: .semibold))
                Text("2P").font(.system(size: 14, weight: .bold))
                Text("(\(CoopSessionCoordinator.shared.participants.count)/2)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.3)))
        }
    }
    
    @ViewBuilder
    private var curvedIconCoopInvite: some View {
        if viewModel.isCoopSession {
            let coordinator = CoopSessionCoordinator.shared
            if coordinator.isHosting && coordinator.participants.count < 2 {
                coopInviteButton
            }
        }
    }
    
    @ViewBuilder
    private var curvedIconCoopDisconnect: some View {
        if viewModel.isCoopSession {
            coopDisconnectButton
        }
    }
    
    private var curvedControlsBarContent: some View {
        HStack(spacing: 16) {
            // 1. Home
            staggeredControl(index: 0) {
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
                    restoreStreamAudioAfterMenuDismiss()
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
                }
                },
                longPressAction: {
                    restoreStreamAudioAfterMenuDismiss()
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
            }

            // 2. Spatial Audio
            staggeredControl(index: 1) {
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
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.showInlinePresetOverlay = false
                        }
                    }
                }
                },
                longPressAction: {
                    // Only cycle sound stage when spatial audio is enabled
                    guard spatialAudioMode else { return }
                    
                    soundStageSize = soundStageSize.next()
                    fixAudioForCurrentMode()
                    presetOverlayText = "Sound Stage: \(soundStageSize.rawValue)"
                    presetOverlayIcon = "person.spatialaudio.fill"
                    showInlinePresetOverlay = true
                    
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            showInlinePresetOverlay = false
                        }
                    }
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
            }

            // 3. Star Distance (only visible in Starfield mode)
            if dimLevel == 12 {
                staggeredControl(index: 4) {
                LongPressControlBtn(
                    label: starDistancePreset.displayName,
                    systemImage: "moon.stars.fill",
                    controlsHighlighted: $controlsHighlighted,
                    hideControls: $hideControls,
                    startHighlightTimer: startHighlightTimer,
                    startHideTimer: startHideTimer,
                    primaryAction: {
                        let nextPreset = starDistancePreset.next()
                        starDistancePresetRawValue = nextPreset.rawValue
                        particleManager.updateDistancePreset(nextPreset)
                        presetOverlayText = "STAR DISTANCE: \(nextPreset.displayName.uppercased())"
                        presetOverlayIcon = "moon.stars.fill"
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
                        starDistancePresetRawValue = StarDistancePreset.close.rawValue
                        particleManager.updateDistancePreset(.close)
                        presetOverlayText = "STAR DISTANCE: CLOSE"
                        presetOverlayIcon = "moon.stars.fill"
                        showInlinePresetOverlay = true
                        
                        presetOverlayTimer?.invalidate()
                        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                showInlinePresetOverlay = false
                            }
                        }
                    },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                }
            }

            // 5. Dim
            staggeredControl(index: 5) {
            LongPressControlBtn(
                label: dimButtonTitle,
                systemImage: dimButtonIcon,
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                guard !isLocked else {
                    presentHeadFollowBlockedOverlay(feature: "Lighting")
                    return
                }
                // Short press: toggle dimming picker
                showDimmingPicker.toggle()
                if showDimmingPicker {
                    closeStreamPickers(exceptDimming: true)
                    stopMoonlightCycle()
                    stopReactiveLerp()
                }
                },
                longPressAction: {
                    guard !isLocked else {
                        presentHeadFollowBlockedOverlay(feature: "Lighting")
                        return
                    }
                    // Long press: reset to Off
                    dimLevel = 0
                    
                    // Tell the decoder whether it needs to run the ambient light engine
                    videoDecoder?.isReactiveDimmingEnabled = false
                    
                    viewModel.streamSettings.dimPassthrough = false
                    updateDimmerDomesState()
                    stopMoonlightCycle()
                    stopReactiveLerp()
                    showDimPresetOverlay()
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
            }

            // 6. Preset
            staggeredControl(index: 6) {
            makeControlButton(label: "Preset", systemImage: "camera.filters", action: {
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
                presentFilterPresetCenterPopup(selectedPreset: next)
                startHideTimer()
            }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
            }

            // 7. HDR
            if viewModel.streamSettings.enableHdr {
                staggeredControl(index: 7) {
                makeControlButton(
                    label: showHDRPanel ? "Close HDR" : "HDR",
                    systemImage: "wand.and.stars",
                    action: {
                        showHDRPanel.toggle()
                        if showHDRPanel {
                            closeStreamPickers(exceptHDR: true)
                            updateHDRParamsFromPanel()
                        }
                        startHideTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                }
            }

            // 7.5 Screen Preset
            staggeredControl(index: 13) {
                LongPressControlBtn(
                    label: showScreenPresetPanel ? "Close Screen Preset" : "Screen Preset",
                    systemImage: "rectangle.fill.on.rectangle.angled.fill",
                    controlsHighlighted: $controlsHighlighted,
                    hideControls: $hideControls,
                    startHighlightTimer: startHighlightTimer,
                    startHideTimer: startHideTimer,
                    primaryAction: {
                        guard !isLocked else {
                            presentHeadFollowBlockedOverlay(feature: "Screen Preset")
                            return
                        }
                        showScreenPresetPanel.toggle()
                        if showScreenPresetPanel {
                            closeStreamPickers(exceptScreenPreset: true)
                        }
                        startHideTimer()
                    },
                    longPressAction: {
                        guard !isLocked else {
                            presentHeadFollowBlockedOverlay(feature: "Screen Preset")
                            return
                        }
                        let next = screenPresetSettings.cycleActivePreset()
                        applyScreenPreset(slot: next)
                        startHideTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
            }

            // 8. 3D
            staggeredControl(index: 8) {
            makeControlButton(label: videoMode == .standard2D ? "Standard Display" : "3D", systemImage: "view.3d", action: {
                if videoMode == .standard2D {
                    show3DConfirm = true
                } else {
                    videoMode = .standard2D
                    updateScreenMaterial()
                }
            }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
            }

            // 9. Sphere Environment (Picker)
            staggeredControl(index: 10) {
            LongPressControlBtn(
                label: environmentSphereButtonTitle,
                systemImage: "photo",
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                    guard !isLocked else {
                        presentHeadFollowBlockedOverlay(feature: "Environment")
                        return
                    }
                    showEnvironmentPicker.toggle()
                    if showEnvironmentPicker {
                        closeStreamPickers(exceptEnvironment: true)
                        stopMoonlightCycle()
                        stopReactiveLerp()
                    }
                    
                    startHideTimer()
                },
                longPressAction: {
                    guard !isLocked else {
                        presentHeadFollowBlockedOverlay(feature: "Environment")
                        return
                    }
                    // Long press still clears the environment
                    environmentSphereLevel = 0
                    newsetLevel = 0
                    showEnvironmentPicker = false
                    updateEnvironmentState()
                    updateNewsetState()
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.streamSettings.dimPassthrough = false }
                },
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
            }

            // 10. Stats
            staggeredControl(index: 11) {
            makeControlButton(label: viewModel.streamSettings.statsOverlay ? "Hide Stats" : "Show Stats", systemImage: "wifi", action: {
                viewModel.streamSettings.statsOverlay.toggle()
            }, onTapFeedback: { controlTapFeedbackTrigger += 1 })
            }
            
            // 10.5. Desktop actions (if enabled)
            if viewModel.streamSettings.showTaskManagerButton {
                staggeredControl(index: 11) {
                makeControlButton(
                    label: showDesktopActionsPicker ? "Close Desktop" : "Desktop",
                    systemImage: "list.bullet.circle",
                    action: {
                        toggleDesktopActionsPicker()
                        startHighlightTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                }
            }
            
            if viewModel.streamSettings.showStreamMuteButton {
                staggeredControl(index: 12) {
                makeControlButton(
                    label: viewModel.vol == 0 ? "Unmute Game" : "Mute Game",
                    systemImage: viewModel.vol == 0 ? "speaker.slash.fill" : "speaker.fill",
                    action: {
                        if viewModel.vol == 0 {
                            let restore = streamVolumeBeforeMute > 0 ? streamVolumeBeforeMute : 127
                            viewModel.vol = restore
                            StreamVolume.apply(Int32(restore))
                        } else {
                            streamVolumeBeforeMute = viewModel.vol
                            viewModel.vol = 0
                            StreamVolume.apply(0)
                        }
                        startHighlightTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                }
            }

            if viewModel.streamSettings.showPeekThroughButton {
                staggeredControl(index: 14) {
                    makeControlButton(
                        label: streamPeekThroughActive ? "Show Stream" : "Pass Through",
                        systemImage: streamPeekThroughActive ? "vision.pro" : "vision.pro.fill",
                        action: { toggleStreamPeekThrough() },
                        onTapFeedback: { controlTapFeedbackTrigger += 1 }
                    )
                }
            }

            if viewModel.streamSettings.showHeadFollowButton {
                staggeredControl(index: 15) {
                    makeControlButton(
                        label: isLocked ? "Follow Mode: On" : "Follow Mode: Off",
                        systemImage: isLocked ? "figure.walk.circle.fill" : "figure.walk.circle",
                        alwaysActive: true,
                        action: { toggleHeadFollow() },
                        onTapFeedback: { controlTapFeedbackTrigger += 1 }
                    )
                }
            }
            
            // 11. Keyboard Toggle
            staggeredControl(index: 16) {
            if inputMode == .screenMove {
                makeControlButton(
                    label: "Show Keyboard",
                    systemImage: "keyboard",
                    action: {
                        presetOverlayText = "Switch to Gaze or Controller for keyboard."
                        presetOverlayIcon = "keyboard"
                        showInlinePresetOverlay = true
                        presetOverlayTimer?.invalidate()
                        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    self.showInlinePresetOverlay = false
                                }
                            }
                        }
                        startHighlightTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                .opacity(0.4)
                .allowsHitTesting(true)
            } else {
                makeControlButton(
                    label: showVirtualKeyboard ? "Hide Keyboard" : "Show Keyboard",
                    systemImage: showVirtualKeyboard ? "keyboard.fill" : "keyboard",
                    action: {
                    if inputMode == .controller && !showVirtualKeyboard {
                        print("[Keyboard] Auto-switching from Controller Mode to Gaze Mode for keyboard")
                        gazeController.cleanup()
                        inputMode = .gazeControl
                        updateScreenInteractivity()
                    }

                    showVirtualKeyboard.toggle()

                    if showVirtualKeyboard {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isKeyboardFocused = true
                        }
                    } else {
                        isKeyboardFocused = false
                    }

                    print("[Keyboard] Toggle pressed, showVirtualKeyboard is now: \(showVirtualKeyboard)")
                    startHighlightTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
            }
            }
            
            if viewModel.streamSettings.showControllerBattery {
                staggeredControl(index: 14) {
                BatteryIndicatorView(
                    controlsHighlighted: $controlsHighlighted,
                    hideControls: $hideControls,
                    startHighlightTimer: startHighlightTimer,
                    startHideTimer: startHideTimer
                )
                }
            }

            if viewModel.streamSettings.showPinchDragToggle
                && inputMode == .gazeControl
                && !viewModel.streamSettings.curvedGazeUseTouchMode {
                staggeredControl(index: 15) {
                makeControlButton(
                    label: effectivePinchDragUsesScroll ? "Scroll Mode" : "Marquee",
                    systemImage: effectivePinchDragUsesScroll ? "arrow.up.and.down" : "hand.draw",
                    action: {
                        let next = !effectivePinchDragUsesScroll
                        sessionPinchDragUsesScroll = next
                        syncGazePinchDragMode()
                        presetOverlayText = next ? "Scroll Mode" : "Marquee/Drag"
                        presetOverlayIcon = next ? "arrow.up.and.down" : "hand.draw"
                        showInlinePresetOverlay = true
                        presetOverlayTimer?.invalidate()
                        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    self.showInlinePresetOverlay = false
                                }
                            }
                        }
                        startHighlightTimer()
                    },
                    onTapFeedback: { controlTapFeedbackTrigger += 1 }
                )
                }
            }
            
            // 12. Input Mode Toggle (Screen Adjust / Controller / Gaze Control)
            // Long press to disable/enable hand & gaze input
            staggeredControl(index: 15) {
            LongPressControlBtn(
                label: {
                    // Use Touch label if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "Touch Control Mode"
                    }
                    return inputMode.displayName
                }(),
                systemImage: {
                    if inputMode == .gazeControl && isHandGazeInputDisabled {
                        return "lock.fill"
                    }
                    // Use Touch icon if in Gaze Control mode and Touch mode is enabled
                    if inputMode == .gazeControl && viewModel.streamSettings.curvedGazeUseTouchMode {
                        return "hand.point.up.left.fill"
                    }
                    return inputMode.icon
                }(),
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                    gazeController.cleanup()  // Reset gaze state on mode change
                    inputMode = inputMode.next()
                    print("[InputMode] Changed to: \(inputMode) (\(inputMode.displayName))")
                    
                    // CRITICAL FIX: When switching to Controller mode, ensure keyboard is closed
                    // and first responder is properly reclaimed for controller input
                    if inputMode == .controller {
                        showVirtualKeyboard = false
                        isKeyboardFocused = false
                    }
                    syncCurvedGamepadSession()
                    
                    // Update gaze controller with current stream config
                    if inputMode == .gazeControl {
                        gazeController.streamConfig = streamConfig
                    }
                    
                    presetOverlayText = inputMode.modeSwitchOverlayName(gazeUsesTouchMode: viewModel.streamSettings.curvedGazeUseTouchMode)
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
                },
                longPressAction: inputModeLongPressAction,
                onTapFeedback: { controlTapFeedbackTrigger += 1 }
            )
            }
            
            // 13. Co-op Indicator (if in co-op session)
            if viewModel.isCoopSession {
                staggeredControl(index: 16) {
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
                .foregroundColor(.white                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.3))
                )
                }
            }
            
            // 14. Co-op Invite Button (only when hosting and guest is missing)
            if viewModel.isCoopSession {
                let coordinator = CoopSessionCoordinator.shared
                if coordinator.isHosting && coordinator.participants.count < 2 {
                    staggeredControl(index: 17) {
                    coopInviteButton
                    }
                }
            }
            
            // 15. Co-op Disconnect Button (always show when in co-op)
            if viewModel.isCoopSession {
                staggeredControl(index: 18) {
                coopDisconnectButton
                }
            }
        }
    }
    
    private var curvedExpandedControlsContent: some View {
        curvedControlsBarContent
    }
    
    private var curvedOriginalControlsBar: some View {
        curvedControlsBarContent
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(topControlsUltraThinCapsuleOpacityWhenChromeVisible())
        }
        // Dynamic opacity floor: lower for black modes (Eclipse, Starfield); Reactive V1 gets a readability lift vs glow
        .opacity(!hideControls ? (controlsHighlighted ? 1.0 : fadedTopControlsInactiveOpacity()) : fadedTopControlsDormantOpacity())
        .animation(Animation.easeInOut(duration: 0.35), value: controlsHighlighted)
        .animation(Animation.easeInOut(duration: 0.35), value: hideControls)
        .animation(Animation.easeInOut(duration: 0.35), value: reactiveV1TopChromeAnimationAnchor)
        .animation(Animation.easeInOut(duration: 0.35), value: dimLevel)
        .animation(Animation.easeInOut(duration: 0.35), value: darkControlsMode)
        .animation(Animation.easeInOut(duration: 0.35), value: lightControlsMode)
        .sensoryFeedback(.impact(weight: .medium), trigger: controlTapFeedbackTrigger)
        .allowsHitTesting(true)
    }
    
    /// Scale mic pill to the same world height as the top controls attachment.
    private func scaleMicBarAttachmentToMatchTopControls(_ micEnt: Entity, screen: Entity) {
        let bounds = micEnt.visualBounds(relativeTo: screen)
        guard bounds.extents.y > 0 else { return }
        let currentScaleY = max(micEnt.scale.y, 0.0001)
        let unscaledHeight = Float(bounds.extents.y) / currentScaleY
        let targetHeight: Float = {
            if let controls = headStorage.controlsEntity {
                let controlsHeight = controls.visualBounds(relativeTo: screen).extents.y
                if controlsHeight > 0 { return controlsHeight }
            }
            return 0.055
        }()
        let scale = targetHeight / unscaledHeight
        micEnt.scale = [scale, scale, scale]
    }

    private func makeControlButton(label: String, systemImage: String, alwaysActive: Bool = false, action: @escaping () -> Void, onTapFeedback: (() -> Void)? = nil) -> some View {
        Button {
            if !alwaysActive && !controlsHighlighted {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            hideControls = false
            controlsHighlighted = true
            onTapFeedback?()
            action()
            startHideTimer()
        } label: {
            Label(label, systemImage: systemImage)
                .font(.system(size: 24.07))
                .foregroundStyle(.white)
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
            controlTapFeedbackTrigger += 1
            
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
            print("[Leave] Button tapped - controlsHighlighted: \(controlsHighlighted)")
            if !controlsHighlighted {
                print("[Leave] Controls not highlighted, highlighting now")
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            controlTapFeedbackTrigger += 1
            
            print("[Leave] Setting showDisconnectConfirm = true")
            showDisconnectConfirm = true
            print("[Leave] showDisconnectConfirm is now: \(showDisconnectConfirm)")
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
        case 2: "Reactive"
        case 4: "Eclipse"
        case 5: "Midnight"
        case 6: "Twilight"
        case 7: "Dawn"
        case 8: "Sunrise"
        case 9: "Woodland"
        case 10: "Tide"
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
        let order = [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 14]
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
        syncCurvedGamepadSession()
        if inputMode == .controller, controllerSupport != nil {
            // activateGamepadCapture already restores handlers — no separate call needed
            streamGamepadSession.activateGamepadCapture()
        }
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

    /// Brief center toast when a stream starts with Enhanced HDR (FILTER) grading.
    private func showHDRPresetToastOnStreamStart() {
        guard viewModel.streamSettings.uikitPreset == 0 else { return }

        let label: String
        if hdrPanelSettings.referenceHDR {
            label = "HDR: Reference"
        } else {
            label = "HDR: \(hdrPanelSettings.displayName(for: hdrPanelSettings.activePresetSlot))"
        }

        presetOverlayText = label
        presetOverlayIcon = "sun.max.fill"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
        }
    }

    // MARK: - HDR & Material
    
    /// Pushes persisted HDR panel values into `safeHDRSettings` right before `DrawableVideoDecoder` is created,
    /// ensuring the first frame matches UserDefaults even if lifecycle ordering was off.
    private func syncHDRSettingsForStreamStart() {
        applyCurvedUIKitPreset(viewModel.streamSettings.uikitPreset)
    }

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
        // FILTER: Default — Enhanced HDR panel wins for brightness/sat/contrast. Without this,
        // bootstrap applies preset scaffold (e.g. SDR boost 1.0) after sync and the image flashes correct then dips dark.
        if preset == 0 {
            params.boost       = hdrPanelSettings.brightness
            params.contrast    = hdrPanelSettings.contrast
            params.saturation  = hdrPanelSettings.saturation
            params.brightness  = 0.0
            if viewModel.streamSettings.enableHdr {
                let hrB = hdrHeadroomBoost()
                params.boost       = Swift.min(Swift.max(params.boost * hrB, 1.0), 1.50)
                params.contrast    = Swift.min(Swift.max(params.contrast, 1.00), 1.20)
                params.saturation = Swift.min(Swift.max(params.saturation, 0.85), 1.15)
            }
        }
        if viewModel.streamSettings.enableHdr {
            params.mode = hdrParams.mode
        }
        params.pqExposure = hdrPanelSettings.pqExposure
        params.hdrGradeFlags = hdrPanelSettings.referenceHDR ? 1 : 0
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
            pqExposure: hdrPanelSettings.pqExposure,
            mode: hdrParams.mode,
            hdrGradeFlags: hdrPanelSettings.referenceHDR ? 1 : 0
        )
        if viewModel.streamSettings.enableHdr {
            let hrBoost = hdrHeadroomBoost()
            params.boost = Swift.min(Swift.max(params.boost * hrBoost, 1.0), 1.50)
            params.brightness = 0.0
        }
        safeHDRSettings.value = params
    }

    // Live update from HDR panel sliders — must match stream start logic for Custom preset (uikitPreset == 0)
    // to prevent image "snap" when opening HDR panel
    private func updateHDRParamsFromPanel() {
        if viewModel.streamSettings.uikitPreset == 0 {
            // Custom preset: use same HDR headroom/clamps as stream start
            applyCurvedUIKitPreset(0)
        } else {
            // Non-custom presets: raw copy from panel (legacy behavior for non-zero presets)
            var params = safeHDRSettings.value
            params.boost = hdrPanelSettings.brightness
            params.contrast = hdrPanelSettings.contrast
            params.saturation = hdrPanelSettings.saturation
            params.pqExposure = hdrPanelSettings.pqExposure
            params.brightness = 0.0
            params.hdrGradeFlags = hdrPanelSettings.referenceHDR ? 1 : 0
            safeHDRSettings.value = params
        }
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
        let currentCurveMagnitude = effectiveCurveMagnitude
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
        let curveMagnitude = effectiveCurveMagnitude
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
                resolution: (256, 256),
                curveMagnitude: effectiveCurveMagnitude,
                cornerRadiusFraction: cornerRadiusFraction
            )
        } catch {
            print("⚠️ Failed to generate curved mesh: \(error). Using flat fallback.")
            mesh = .generatePlane(width: CURVED_MAX_WIDTH_METERS, height: CURVED_MAX_WIDTH_METERS * screenAspect)
        }
        
        if videoMode == .standard2D {
            screen = ModelEntity(mesh: mesh, materials: [UnlitMaterial(texture: texture)])
        } else {
            screen = ModelEntity(mesh: mesh, materials: [UnlitMaterial(texture: texture)])
        }

        // Generate curved collision mesh that matches visual geometry
        let collisionMesh: MeshResource
        do {
            collisionMesh = try generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (64, 64),
                curveMagnitude: effectiveCurveMagnitude,
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

        // Chromosphere: bloom shell must use the **same** curve / aspect topology as the display (updated in updateRealityView).
        if chromosphereMeshEntity == nil {
            let curveNow = effectiveCurveMagnitude
            let haloMesh = (try? makeChromosphereMesh(curveMagnitude: curveNow)) ?? fallbackChromospherePlaneMesh()
            
            let haloEntity = ModelEntity(mesh: haloMesh, materials: [])
            haloEntity.components.set(OpacityComponent(opacity: 0.0))
            haloEntity.components.set(GroundingShadowComponent(castsShadow: false))
            screen.addChild(haloEntity)
            headStorage.chromosphereHaloEntity = haloEntity
            applyChromosphereHaloLocalZOffset(curveMagnitude: curveNow, entity: haloEntity)
            DispatchQueue.main.async {
                self.chromosphereMeshEntity = haloEntity
                self.replaceChromosphereMeshWithDisplayCurve(effectiveCurveMagnitude)
                self.updateChromosphereMesh()
            }
        }

        // DEBUG: Spheres disabled - using corner gaze calibration instead
        // addDebugCalibrationSpheres(to: screen)

        let head = AnchorEntity(.head)
        content.add(head)
        headStorage.headAnchor = head

        if let controls = attachments.entity(for: "controls") {
            headStorage.controlsEntity = controls
            // Keep controls on the scene root until peek-through exit fade finishes (see reparentControlsForPeekThrough).
            if !streamPeekThroughActive && headStorage.controlsTransformBeforePeek == nil && controls.parent !== screen {
                screen.addChild(controls)
            }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            // Reactive V2 translucent dome: pull toolbar slightly toward the viewer vs mesh sorting with the hemisphere.
            let controlsZLocal: Float = 0.05
            controls.position = [0.0 as Float, (screenHeight / 2.0) + Float(0.03), controlsZLocal]
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
            if !headStorage.statsScaleInitialized {
                let bounds = statsEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(statsEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let targetLocalWidth = statsCardWidthMeters
                    let scale = targetLocalWidth / unscaledWidth
                    statsEnt.scale = [scale, scale, scale]
                    headStorage.statsScaleInitialized = true
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
                let desiredLocalWidth = sbsConfirmCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                sbsEnt.scale = [scale, scale, scale]
            }
        }

        if let disconnectEnt = attachments.entity(for: "disconnectConfirm") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            disconnectEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]

            let bounds = disconnectEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth = swapCardWidthMeters
                let scale = desiredLocalWidth / unscaledWidth
                disconnectEnt.scale = [scale, scale, scale]
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
            let micOffset: Float = showVirtualKeyboard
                ? CURVED_MIC_OFFSET_BELOW_SCREEN_WITH_KEYBOARD
                : CURVED_MIC_OFFSET_BELOW_SCREEN
            micEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(micOffset), Float(0.05)]

            scaleMicBarAttachmentToMatchTopControls(micEnt, screen: screen)
        }
        
        positionScreenAdjustHandles(attachments: attachments)
        positionScreenAdjustCurvaturePill(attachments: attachments)
    }

    func updateRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        let currentCurve = effectiveCurveMagnitude

        let curveEpsilon: Float = curvatureSliderDragging ? 0.002 : 0.001
        let curveChanged: Bool
        let aspectChanged: Bool
        if let lastCurve = headStorage.lastGeneratedCurve, let lastAspect = headStorage.lastGeneratedAspect {
            curveChanged = abs(currentCurve - lastCurve) > curveEpsilon
            aspectChanged = abs(screenAspect - lastAspect) > 0.001
        } else {
            curveChanged = true
            aspectChanged = true
        }
        let geometryChanged = curveChanged || aspectChanged
        let forceFullRegen = headStorage.forceCollisionRegen

        let shouldRegenDisplay = geometryChanged || forceFullRegen

        let shouldRegenCollision = forceFullRegen || (geometryChanged && !curvatureSliderDragging)

        if shouldRegenDisplay {
            let displayResolution: (UInt32, UInt32) = curvatureSliderDragging ? (64, 64) : (256, 256)
            if let mesh = try? generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: displayResolution,
                curveMagnitude: currentCurve,
                cornerRadiusFraction: cornerRadiusFraction
            ) {
                if let model = screen.model {
                    try? model.mesh.replace(with: mesh.contents)
                }

                if !curvatureSliderDragging {
                    if let haloEnt = headStorage.chromosphereHaloEntity,
                       let haloMesh = try? makeChromosphereMesh(curveMagnitude: currentCurve),
                       let hm = haloEnt.model {
                        try? hm.mesh.replace(with: haloMesh.contents)
                    } else if let haloEnt = headStorage.chromosphereHaloEntity,
                              let hm = haloEnt.model {
                        let plane = fallbackChromospherePlaneMesh()
                        try? hm.mesh.replace(with: plane.contents)
                    }
                }

                headStorage.lastMeshGenTime = Date()
                headStorage.lastGeneratedCurve = currentCurve
                headStorage.lastGeneratedAspect = screenAspect
            }
        }

        if shouldRegenCollision {
            if let collisionMesh = try? generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (64, 64),
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
                headStorage.lastGeneratedCurve = currentCurve
                headStorage.lastGeneratedAspect = screenAspect
            }
            headStorage.forceCollisionRegen = false
        }
        
        if isLocked, let head = headStorage.headAnchor {
            if screen.parent !== head {
                attachScreenToHeadForFollow(head)
            }
            applyHeadFollowLayoutToScreen()
        } else if let head = headStorage.headAnchor, screen.parent === head {
            detachScreenFromHeadFollow()
        } else {
            let safeTilt = CurvedFirstLaunch.clampTilt(tiltAngle)
            let safeYaw = CurvedFirstLaunch.clampYaw(yawAngle)
            let tiltRadians = safeTilt * .pi / 180.0
            let yawRadians = safeYaw * .pi / 180.0
            let pitchRotation = simd_quatf(angle: tiltRadians, axis: SIMD3<Float>(1, 0, 0))
            let yawRotation = simd_quatf(angle: yawRadians, axis: SIMD3<Float>(0, 1, 0))
            screen.transform = Transform(
                scale: SIMD3(repeating: screenScale),
                rotation: yawRotation * pitchRotation,
                translation: screenPosition
            )
        }
        
        if let head = headStorage.headAnchor {
            if headStorage.pendingFirstLaunchHeadPlacement {
                headStorage.pendingFirstLaunchHeadPlacement = false
                let saveAfter = headStorage.saveTransformAfterDefaultPlacement
                headStorage.saveTransformAfterDefaultPlacement = false
                DispatchQueue.main.async {
                    if let head = self.headStorage.headAnchor {
                        self.placeScreenAtFirstInstallPosition(head: head)
                        if !self.hasCurvedSavedScale() {
                            self.screenScale = CurvedFirstLaunch.defaultScale
                            self.targetScale = CurvedFirstLaunch.defaultScale
                        }
                    }
                    if saveAfter {
                        self.saveCurrentTransform()
                    }
                }
            }

            let p = head.position(relativeTo: nil)
            
            // UPDATE: Efficiently feed head position to the input system
            // This is "lazy" - we push the data, but SwiftUI doesn't redraw
            // We need head relative to the screen
            let localHead = screen.convert(position: .zero, from: head)
            headStorage.positionInScreenSpace = localHead
            
            if !isLocked {
                if #unavailable(visionOS 26.0) {
                    let delta = simd_length(p - headStorage.lastHeadWorldPos)
                    let nearOrigin = simd_length(p) < 0.1
                    let wasFar = simd_length(headStorage.lastHeadWorldPos) > 0.25
                    let notDraggingRecently = (CACurrentMediaTime() - headStorage.lastDragTime) > 0.4
                    if headStorage.streamTransformReady,
                       nearOrigin && wasFar && delta > 0.25 && notDraggingRecently {
                        DispatchQueue.main.async {
                            self.recenterNonFollowScreenToHead(head: head)
                        }
                    }
                }
            } else {
                // Head Follow crown reset is handled by onWorldRecenter (visionOS 26+) and world-anchor monitoring.
            }
            headStorage.lastHeadWorldPos = p
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
            if showEnvironmentPicker {
                let bounds = pickerEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(pickerEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth = EnvironmentPickerView.curvedDesiredLocalWidth
                    let scale = desiredLocalWidth / unscaledWidth
                    pickerEnt.scale = [scale, scale, scale]
                }
            }
        }
        
        if let dimPickerEnt = attachments.entity(for: "dimPicker") {
            if dimPickerEnt.parent !== screen { screen.addChild(dimPickerEnt) }
            dimPickerEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            if showDimmingPicker {
                let bounds = dimPickerEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(dimPickerEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth = DimmingPickerView.curvedDesiredLocalWidth
                    let scale = desiredLocalWidth / unscaledWidth
                    dimPickerEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let hdrEnt = attachments.entity(for: "hdrPanel") {
            if hdrEnt.parent !== screen { screen.addChild(hdrEnt) }
            hdrEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            if showHDRPanel {
                let bounds = hdrEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(hdrEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.42
                    let scale = desiredLocalWidth / unscaledWidth
                    hdrEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let screenPresetEnt = attachments.entity(for: "screenPresetPanel") {
            if screenPresetEnt.parent !== screen { screen.addChild(screenPresetEnt) }
            screenPresetEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            if showScreenPresetPanel {
                let bounds = screenPresetEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(screenPresetEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.42
                    let scale = desiredLocalWidth / unscaledWidth
                    screenPresetEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let desktopEnt = attachments.entity(for: "desktopPicker") {
            if desktopEnt.parent !== screen { screen.addChild(desktopEnt) }
            desktopEnt.position = [0.0 as Float, 0.0 as Float, Float(0.12)]
            if showDesktopActionsPicker {
                let bounds = desktopEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(desktopEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let scale = DesktopActionsPickerView.curvedDesiredLocalWidth / unscaledWidth
                    desktopEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let statsEnt = attachments.entity(for: "stats") {
            if statsEnt.parent !== screen { screen.addChild(statsEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            statsEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(0.03), Float(0.05)]
            if viewModel.streamSettings.statsOverlay {
                if !headStorage.statsScaleInitialized {
                    let bounds = statsEnt.visualBounds(relativeTo: screen)
                    if bounds.extents.x > 0 {
                        let currentScaleX = max(statsEnt.scale.x, 0.0001)
                        let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                        let targetLocalWidth = statsCardWidthMeters
                        let scale = targetLocalWidth / unscaledWidth
                        statsEnt.scale = [scale, scale, scale]
                        headStorage.statsScaleInitialized = true
                    }
                }
            }
        }

        if let tutorialEnt = attachments.entity(for: "tutorial") {
            if tutorialEnt.parent !== screen { screen.addChild(tutorialEnt) }
            tutorialEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            if showCurvedTutorial {
                let bounds = tutorialEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(tutorialEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let targetLocalWidth = tutorialCardWidthMeters
                    let scale = targetLocalWidth / unscaledWidth
                    tutorialEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let swapEnt = attachments.entity(for: "swapConfirm") {
            if swapEnt.parent !== screen { screen.addChild(swapEnt) }
            swapEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]
            if showSwapConfirm {
                let bounds = swapEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(swapEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth = swapCardWidthMeters
                    let scale = desiredLocalWidth / unscaledWidth
                    swapEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let sbsEnt = attachments.entity(for: "sbsConfirm") {
            if sbsEnt.parent !== screen { screen.addChild(sbsEnt) }
            sbsEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]
            if show3DConfirm {
                let bounds = sbsEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(sbsEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth = sbsConfirmCardWidthMeters
                    let scale = desiredLocalWidth / unscaledWidth
                    sbsEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let disconnectEnt = attachments.entity(for: "disconnectConfirm") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            disconnectEnt.position = [0.0 as Float, 0.0 as Float, Float(0.06)]
            if showDisconnectConfirm {
                let bounds = disconnectEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth = swapCardWidthMeters
                    let scale = desiredLocalWidth / unscaledWidth
                    disconnectEnt.scale = [scale, scale, scale]
                }
            }
        }

        if let popupEnt = attachments.entity(for: "presetPopup") {
            if popupEnt.parent !== screen { screen.addChild(popupEnt) }
            popupEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            if showInlinePresetOverlay {
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
        
        // Co-op join notification (centered, same as presetPopup)
        if let joinEnt = attachments.entity(for: "coopJoinNotification") {
            if joinEnt.parent !== screen { screen.addChild(joinEnt) }
            joinEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            if coopCoordinator.friendJoinedNotification {
                let bounds = joinEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(joinEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.35
                    let scale = desiredLocalWidth / unscaledWidth
                    joinEnt.scale = [scale, scale, scale]
                }
            }
        }
        
        // Co-op disconnect notification (centered, same as presetPopup)
        if let disconnectEnt = attachments.entity(for: "coopDisconnectNotification") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            disconnectEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            if coopCoordinator.disconnectNotification {
                let bounds = disconnectEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.35
                    let scale = desiredLocalWidth / unscaledWidth
                    disconnectEnt.scale = [scale, scale, scale]
                }
            }
        }
        
        // Co-op connecting overlay (centered, same as presetPopup)
        if let connectingEnt = attachments.entity(for: "coopConnectingOverlay") {
            if connectingEnt.parent !== screen { screen.addChild(connectingEnt) }
            connectingEnt.position = [0.0 as Float, 0.0 as Float, Float(0.15)]
            if viewModel.isCoopSession && viewModel.assignedControllerSlot == 1 && viewModel.streamState == .starting {
                let bounds = connectingEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(connectingEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.35
                    let scale = desiredLocalWidth / unscaledWidth
                    connectingEnt.scale = [scale, scale, scale]
                }
            }
        }
        
        // Keyboard TextField - positioned below screen, centered
        if let keyboardEnt = attachments.entity(for: "keyboardTextField") {
            if keyboardEnt.parent !== screen { screen.addChild(keyboardEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below screen - if mic button is showing, keyboard goes above it
            let keyboardOffset: Float = viewModel.streamSettings.showMicButton ? 0.16 : 0.08
            keyboardEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(keyboardOffset), Float(0.05)]
            if showVirtualKeyboard {
                let bounds = keyboardEnt.visualBounds(relativeTo: screen)
                if bounds.extents.x > 0 {
                    let currentScaleX = max(keyboardEnt.scale.x, 0.0001)
                    let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                    let desiredLocalWidth: Float = 0.25
                    let scale = desiredLocalWidth / unscaledWidth
                    keyboardEnt.scale = [scale, scale, scale]
                }
            }
        }
        
        // Mic Button - positioned below keyboard (if keyboard is showing) or below screen
        if let micEnt = attachments.entity(for: "micButton") {
            if micEnt.parent !== screen { screen.addChild(micEnt) }
            let screenHeight = CURVED_MAX_WIDTH_METERS * screenAspect
            
            // Position below keyboard if keyboard is showing, otherwise below screen
            let micOffset: Float = showVirtualKeyboard
                ? CURVED_MIC_OFFSET_BELOW_SCREEN_WITH_KEYBOARD
                : CURVED_MIC_OFFSET_BELOW_SCREEN
            micEnt.position = [0.0 as Float, -(screenHeight / 2.0) - Float(micOffset), Float(0.05)]
            if viewModel.streamSettings.showMicButton {
                scaleMicBarAttachmentToMatchTopControls(micEnt, screen: screen)
            }
        }
        
        positionScreenAdjustHandles(attachments: attachments)
        positionScreenAdjustCurvaturePill(attachments: attachments)
        
        if let haloEnt = headStorage.chromosphereHaloEntity {
            applyChromosphereHaloLocalZOffset(curveMagnitude: currentCurve, entity: haloEnt)
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
            
            // CRITICAL: Sync HDR settings from panel to safeHDRSettings BEFORE decoder creation
            self.syncHDRSettingsForStreamStart()
            DispatchQueue.main.async {
                self.showHDRPresetToastOnStreamStart()
            }
            
            self.ensureHDRTextureMatchesSetting()
            
            // Set controller support reference for rumble forwarding
            self.connectionCallbacks.controllerSupport = self.controllerSupport
            
            // Capture texture locally for thread-safe background access
            let localTexture = self.texture
            
            self.streamMan = StreamManager(
                config: self.streamConfig,
                rendererProvider: {
                    let decoder = DrawableVideoDecoder(
                        texture: localTexture,
                        callbacks: self.connectionCallbacks,
                        aspectRatio: self.screenAspect,
                        useFramePacing: self.streamConfig.useFramePacing,
                        enableHDR: self.viewModel.streamSettings.enableHdr,
                        hdrSettingsProvider: { [safeHDRSettings] in safeHDRSettings.value },
                        enhancementsProvider: {
                            let p = self.viewModel.streamSettings.uikitPreset
                            switch p {
                            case 0: return (1.0, 1.0, 0.0)
                            case 1: return (1.15, 1.0, 0.0)
                            case 2: return (1.25, 1.0, 0.0)
                            case 3: return (0.90, 1.05, 0.0)
                            default: return (1.0, 1.0, 0.0)
                            }
                        },
                        callbackToRender: { textureQueue, haloQueue, correctedResolution in
                            guard self.renderGateOpen else { return }

                            // Push frame and UI metadata directly to Main Thread (Bypasses RealityKit traffic jam)
                            DispatchQueue.main.async {
                                // DIRECT PUSH: Instantly paint the new frame to the curved screen
                                self.texture.replace(withDrawables: textureQueue)

                                // Chromosphere: wire up the downsampled bloom texture on first frame
                                if let haloQueue {
                                    if self.chromosphereTexture == nil {
                                        let mipShift = ChromaHaloDownsample.mipShift
                                        let cw = max(1, Int(self.streamConfig.width) >> mipShift)
                                        let ch = max(1, Int(self.streamConfig.height) >> mipShift)
                                        let bpp = self.viewModel.streamSettings.enableHdr ? 8 : 4
                                        if let tex = try? TextureResource(
                                            dimensions: .dimensions(width: cw, height: ch),
                                            format: .raw(pixelFormat: self.viewModel.streamSettings.enableHdr ? .rgba16Float : .bgra8Unorm_srgb),
                                            contents: .init(mipmapLevels: [.mip(data: Data(count: bpp * cw * ch), bytesPerRow: bpp * cw)])
                                        ) {
                                            self.chromosphereTexture = tex
                                            tex.replace(withDrawables: haloQueue)
                                        }
                                    }
                                }

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
                                    self.syncCurvedGamepadSession()
                                    self.startHideTimer()
                                    self.micChromeFade.streamControlsShown()

                                    // Chromosphere opacity requires firstFrameReceived; persisted Reactive V1 restores dimLevel earlier.
                                    self.syncReactiveLightingVisualsAfterFramesReady()
                                } else if self.dimLevel == 2, self.chromosphereTexture != nil {
                                    self.updateChromosphereMesh()
                                }
                            }
                        }
                    )
                    
                    // Store the decoder reference for controlling reactive dimming
                    DispatchQueue.main.async {
                        self.videoDecoder = decoder
                        if self.firstFrameReceived {
                            self.syncReactiveLightingVisualsAfterFramesReady()
                        } else {
                            self.applyLightingPresetVisuals(previousLevel: 0)
                        }
                    }
                    
                    return decoder
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
            // Only open main window if menu isn't already showing it
            // (avoids duplicate window when disconnecting via in-stream menu)
            if !isMenuOpen {
                openWindow(id: "mainView")
                
                // Allow the OS time to build the window during the heavy teardown,
                // then force it to the correct height and size.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.positionMenuWindow()
                }
            }
            await dismissImmersiveSpace()
            viewModel.isImmersiveSpaceOpen = false
        }
    }
    
    private func refreshEDRHeadroomAndParams() { }
    
    private func performCompleteTeardown() {
        guard !hasPerformedTeardown else { return }
        hasPerformedTeardown = true

        AudioHelpers.pinStreamAudioToScene(nil)
        immersiveSpaceSceneID = nil

        cancelReactiveSphereEnvelopeIntro(resetDomeVisuals: true)
        
        print("[CurvedDisplay] 🔴 TEARDOWN START")

        headStorage.curvaturePillStableScale = nil
        stopPresetAnchorMonitoring()
        
        // CRITICAL: Close render gate BEFORE stopping stream
        renderGateOpen = false
        
        statsTimer?.invalidate()
        hideTimer?.invalidate()
        micChromeFade.invalidate()
        presetOverlayTimer?.invalidate()
        moonlightCycleTimer?.invalidate()
        
        idrWatchdogTimer1?.invalidate(); idrWatchdogTimer1 = nil
        idrWatchdogTimer2?.invalidate(); idrWatchdogTimer2 = nil
        postFirstFrameRebindTimer?.invalidate(); postFirstFrameRebindTimer = nil
        guestAggressiveIDRTimer?.invalidate(); guestAggressiveIDRTimer = nil
        firstFrameReceived = false
        
        streamGamepadSession.detach()
        BluetoothMouseRouting.releasePointerLock()
        controllerSupport?.cleanup()
        controllerSupport = nil
        
        if let sm = streamMan {
            print("[CurvedDisplay] Stopping StreamManager (waiting for LiStopConnection completion)...")
            streamMan = nil  // Clear reference now to prevent double-stop
            
            // Tell the serializer a stop is beginning — no new connection can start until
            // notifyStopComplete() is called inside the real completion block below.
            ConnectionSerializer.shared.notifyStopBegun()
            
            sm.stopStream(completion: {
                DispatchQueue.main.async {
                    print("[CurvedDisplay] 🔴 TEARDOWN COMPLETE — LiStopConnection finished")
                    // Ungate the serializer — new connections may now proceed.
                    ConnectionSerializer.shared.notifyStopComplete()
                    NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
                }
            })
        } else {
            print("[CurvedDisplay] 🔴 TEARDOWN COMPLETE (no stream to stop)")
            NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
        }
    }
    
    private func cleanupResources() {
        streamMan = nil
        BluetoothMouseRouting.releasePointerLock()
        controllerSupport?.cleanup()
        controllerSupport = nil
    }

    private func startEnvironmentFade(targetOpacity: Float, completion: (() -> Void)? = nil) {
        environmentFadeTimer?.invalidate()
        
        guard let dome = headStorage.environmentDome else {
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
        guard let dome = headStorage.environmentDome else { return }
        
        if environmentSphereLevel == 0 {
            startEnvironmentFade(targetOpacity: 0.0) {
                dome.isEnabled = false
                self.headStorage.lastEnvironmentSphereLevelApplied = 0
            }
            return
        }
        
        // If already enabled, fade out first then swap
        if dome.isEnabled {
            startEnvironmentFade(targetOpacity: 0.0) {
                if let tex = self.currentSkyboxTexture() {
                    self.applySkyboxTexture(tex)
                    self.headStorage.lastEnvironmentSphereLevelApplied = self.environmentSphereLevel
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
            headStorage.lastEnvironmentSphereLevelApplied = environmentSphereLevel
            startEnvironmentFade(targetOpacity: 1.0)
        }
    }
    
    private func updateNewsetState() {
        guard let dome = headStorage.environmentDome else { return }
        
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
        guard let dome = headStorage.environmentDome else { return }
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
    
    /// Pushes Chromosphere halo behind the panel with a tighter offset when curved vs flat (reduces coplanar z-fighting).
    private func applyChromosphereHaloLocalZOffset(curveMagnitude: Float, entity: Entity) {
        let zOffset: Float = abs(curveMagnitude) < 0.002 ? -0.048 : -0.028
        var pos = entity.position
        pos.z = zOffset
        entity.position = pos
    }

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

        if dimLevel == 10 {
            if var cached = tideMaterial {
                cached.color.tint = UIColor.white.withAlphaComponent(tideBrightnessAlpha())
                tideMaterial = cached
                return (cached, nil)
            }
            if let mat = buildTideMaterial(phase: tideCyclePhase) {
                tideMaterial = mat
                return (mat, nil)
            }
        }

        if dimLevel == 2 {
            var mat = UnlitMaterial(color: UIColor.clear)
            mat.blending = .transparent(opacity: 1.0)
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
                // All other gradients use user-adjustable brightness
                // Use user-adjustable brightness from presetBrightness, falling back to defaults
                let tintAlpha: CGFloat = {
                    if let userBrightness = presetBrightness[dimLevel] {
                        return CGFloat(userBrightness)
                    }
                    return defaultPresetBrightness[dimLevel] ?? 0.5
                }()
                
                // Always use transparent blending for smooth brightness cycling
                unlitMat.color.tint = UIColor.white.withAlphaComponent(tintAlpha)
                unlitMat.blending = .transparent(opacity: 1.0)
            }
            mat = unlitMat
        } else {
            var fallback = UnlitMaterial(color: .purple)
            let fallbackAlpha: CGFloat = {
                switch dimLevel {
                case 4, 5: return 0.95
                case 6, 7, 8, 9, 10, 14: return 0.90
                default: return 0.5
                }
            }()
            fallback.color.tint = UIColor(red: 0.60, green: 0.40, blue: 0.90, alpha: fallbackAlpha)
            fallback.blending = .transparent(opacity: 1.0)
            mat = fallback
        }
        return (mat, selectedTex)
    }

    /// Persisted Reactive 1 tier → updates Metal chroma halo + Chromosphere curved shell scale.
    private func applySavedReactive1ReachToChromospherePipeline() {
        let idx = Reactive1ChromosphereReach.clampedSavedIndex()
        let scale = Reactive1ChromosphereReach.haloScale(forIndex: idx)
        videoDecoder?.chromaHaloScale = scale
        guard chromosphereMeshEntity != nil || headStorage.chromosphereHaloEntity != nil else { return }
        replaceChromosphereMeshWithDisplayCurve(effectiveCurveMagnitude)
    }

    private func updateDimmerDomesState() {
        headStorage.dimmerDome?.isEnabled = (dimLevel == 1)
        headStorage.dimmerDomePurple?.isEnabled = (dimLevel >= 2 && dimLevel <= 14 && dimLevel != 2)

        chromosphereMeshEntity?.isEnabled = (dimLevel == 2) && firstFrameReceived
        updateChromosphereMesh()

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
        // Only update materials if dimLevel changed, in Reactive mode (needs continuous updates), 
        // or if the preset uses adjustable brightness (Night, Midnight, Twilight, Dawn, Sunrise, Woodland, Tide, Desert)
        let isReactiveMode = (dimLevel == 12)
        let isTideMode = (dimLevel == 10)
        let isAdjustablePreset = [1, 5, 6, 7, 8, 9, 10, 14].contains(dimLevel)
        
        if dimLevel != headStorage.lastAppliedDimLevel || isReactiveMode || isTideMode || isAdjustablePreset {
            headStorage.lastAppliedDimLevel = dimLevel
            
            if let dome = headStorage.dimmerDome {
                // Use user-adjustable brightness for Night mode, falling back to default
                let nightBrightness = presetBrightness[1] ?? defaultPresetBrightness[1] ?? 0.82
                let targetAlpha: Float = viewModel.streamSettings.dimPassthrough ? Float(nightBrightness) : Float(dimAlphas[0])
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

            if let purple = self.headStorage.dimmerDomePurple {
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
        self.headStorage.dimmerDome = dome

        let purpleDome = ModelEntity(mesh: .generateSphere(radius: 60.0))
        purpleDome.scale.x = -1.0
        purpleDome.position = .zero
        purpleDome.components.set(InputTargetComponent(allowedInputTypes: []))
        content.add(purpleDome)
        self.headStorage.dimmerDomePurple = purpleDome

        updateDimmerDomesState()
        if usesChromosphereHaloPipeline {
            DispatchQueue.main.async {
                self.updateChromosphereMesh()
            }
        }
        
        // Add particle system for Nebula preset
        content.add(particleManager.rootEntity)
        
        // Initialize particle manager with saved star distance preset
        particleManager.updateDistancePreset(starDistancePreset)

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
        headStorage.environmentDome = sphere

        if extraSkyboxTextures.isEmpty && extraSkyboxNames.isEmpty {
            loadExtraSkyboxesFromBundle()
        }
        if newsetLevel > 0, let tex = currentNewsetTexture() {
            sphere.isEnabled = true
            applySkyboxTexture(tex)
        } else if environmentSphereLevel != 0, let tex = currentSkyboxTexture() {
            sphere.isEnabled = true
            applySkyboxTexture(tex)
            headStorage.lastEnvironmentSphereLevelApplied = environmentSphereLevel
        }
    }

    private func reapplyPersistedEnvironmentAfterExtrasLoad() {
        let persisted = CurvedEnvironmentPersistence.load(extraSkyboxCount: extraSkyboxNames.count)
        guard persisted.newset > 0 || persisted.sphere > 0 else { return }

        if persisted.newset > 0 {
            if newsetLevel != persisted.newset {
                newsetLevel = persisted.newset
                environmentSphereLevel = 0
            }
            updateNewsetState()
        } else if persisted.sphere > 0 {
            if environmentSphereLevel != persisted.sphere {
                environmentSphereLevel = persisted.sphere
                newsetLevel = 0
            }
            updateEnvironmentState()
        }
    }

    func updateEnvironment360(content: RealityViewContent) {
        // We handle environment updates via updateEnvironmentState() triggered by Binding changes
        // to support fade animations. Automatic updates here would interfere with transitions.
    }

    private func disableEnvironmentImmediately() {
        environmentFadeTimer?.invalidate()
        environmentFadeTimer = nil

        headStorage.lastEnvironmentSphereLevelApplied = 0

        guard let dome = headStorage.environmentDome else { return }
        dome.components.set(OpacityComponent(opacity: 0.0))
        dome.isEnabled = false
    }
    
    internal init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool, swapAction: @escaping () -> Void) {
        self.swapAction = swapAction
        self._streamConfig = streamConfig
        self.needsHdr = needsHdr
        // Note: controllerSupport is created in setupScene (via onAppear), not here
        // Creating it in init causes excessive re-creation on every view update
        
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

    private func hasCurvedSavedTransform() -> Bool {
        guard let packed = UserDefaults.standard.array(forKey: kCurvedPosKey) as? [Float] else { return false }
        return packed.count == 3
    }

    private func hasCurvedSavedScale() -> Bool {
        UserDefaults.standard.float(forKey: kCurvedScaleKey) > 0
    }

    /// Sets comfortable first-launch transform in `@State` (what `updateRealityView` reads every frame).
    private func applyFirstLaunchDefaultsToState(scheduleHeadPlacement: Bool) {
        stopPresetAnchorMonitoring()
        screenPosition = CurvedFirstLaunch.placeholderPosition
        if !hasCurvedSavedScale() {
            screenScale = CurvedFirstLaunch.defaultScale
            targetScale = CurvedFirstLaunch.defaultScale
        }
        headStorage.pendingFirstLaunchHeadPlacement = scheduleHeadPlacement
    }

    /// Default scale and placement used when leaving the app in Head Follow (matches first install).
    private func applyDefaultLaunchPlacement() {
        screenScale = CurvedFirstLaunch.defaultScale
        targetScale = CurvedFirstLaunch.defaultScale
        applyFirstLaunchDefaultsToState(scheduleHeadPlacement: true)
    }

    private func flatHeadForward(_ head: AnchorEntity) -> SIMD3<Float> {
        let q = head.transform.rotation
        var flatForward = q.act(simd_float3(0, 0, -1))
        flatForward.y = 0
        let norm = simd_length(flatForward)
        if norm < 1e-4 {
            return simd_float3(0, 0, -1)
        }
        return flatForward / norm
    }

    // MARK: - Head Follow

    private let kHeadFollowSavedDimKey = "headFollow.savedDimLevel"
    private let kHeadFollowSavedSphereKey = "headFollow.savedEnvSphere"
    private let kHeadFollowSavedNewsetKey = "headFollow.savedNewset"
    private let headFollowIntroSeenKey = "hasSeenHeadFollowIntro_v1"

    private func resetHeadFollowToDefaultLayout() {
        guard isLocked else { return }
        let d = CurvedFirstLaunch.defaultHeadFollowOrbit
        let target = CurvedFirstLaunch.offset(yaw: d.yaw, pitch: d.pitch, radius: d.radius)
        startHeadFollowOrbit = nil
        headFollowLocalOffset = target
        if isLocked, let head = headStorage.headAnchor {
            screenScale = CurvedFirstLaunch.headFollowScale
            targetScale = CurvedFirstLaunch.headFollowScale
            snapHeadFollowSpringState()
            applyHeadFollowLayoutToScreen()
        }
        presetOverlayText = "Screen Reset"
        presetOverlayIcon = "crown.fill"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false }
            }
        }
    }

    private func handleHeadFollowWorldRecenter() {
        guard headStorage.streamTransformReady else { return }
        let now = CACurrentMediaTime()
        guard now - headStorage.lastCrownRecenterTime > 0.35 else { return }
        headStorage.lastCrownRecenterTime = now

        if isLocked {
            resetHeadFollowToDefaultLayout()
            headStorage.lastWorldAnchorTransform = nil
        } else if let head = headStorage.headAnchor {
            recenterNonFollowScreenToHead(head: head)
        }
    }

    /// Crown recenter in fixed (non-follow) mode — position/rotation only, never scale.
    private func recenterNonFollowScreenToHead(head: AnchorEntity) {
        let lockedScale = screenScale
        let lockedTarget = targetScale
        screenPosition = currentScreenWorldPosition()
        recenterScreenToHead(head: head)
        screenScale = lockedScale
        targetScale = lockedTarget
    }

    private func currentScreenWorldPosition() -> SIMD3<Float> {
        Transform(matrix: screen.transformMatrix(relativeTo: nil)).translation
    }

    private func translationFromTransform(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private func flatYawFromTransform(_ matrix: simd_float4x4) -> Float {
        var forward = SIMD3(-matrix.columns.2.x, 0, -matrix.columns.2.z)
        let len = simd_length(forward)
        guard len > 1e-4 else { return 0 }
        forward /= len
        return atan2(forward.x, forward.z)
    }

    private func shortestAngularDistance(_ a: Float, _ b: Float) -> Float {
        var delta = a - b
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }

    private func crownRecenterDetected(
        currentTransform: simd_float4x4,
        previousTransform: simd_float4x4?
    ) -> Bool {
        guard (CACurrentMediaTime() - headStorage.lastDragTime) > 0.4 else { return false }
        guard let previousTransform else { return false }

        let posDelta = simd_length(
            translationFromTransform(currentTransform) - translationFromTransform(previousTransform)
        )
        let yawDelta = abs(
            shortestAngularDistance(
                flatYawFromTransform(currentTransform),
                flatYawFromTransform(previousTransform)
            )
        )
        return posDelta > 0.12 || yawDelta > 0.22
    }

    private func startHeadFollowCrownMonitoring() {
        guard headStorage.crownMonitorTask == nil else { return }
        headStorage.crownMonitorTask = Task { @MainActor in
            let provider = WorldTrackingProvider()
            let session = ARKitSession()
            do {
                try await session.run([provider])
            } catch {
                print("[HeadFollow] Crown world-tracking monitor unavailable: \(error)")
                headStorage.crownMonitorTask = nil
                return
            }

            headStorage.crownWorldTrackingProvider = provider
            headStorage.crownARKitSession = session
            headStorage.lastWorldAnchorTransform = nil

            guard let deviceAnchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
                headStorage.crownMonitorTask = nil
                return
            }

            let referenceAnchor = WorldAnchor(originFromAnchorTransform: deviceAnchor.originFromAnchorTransform)
            do {
                try await provider.addAnchor(referenceAnchor)
            } catch {
                print("[HeadFollow] Failed to add crown reference world anchor: \(error)")
                headStorage.crownMonitorTask = nil
                return
            }

            headStorage.crownReferenceWorldAnchorID = referenceAnchor.id
            headStorage.lastWorldAnchorTransform = deviceAnchor.originFromAnchorTransform

            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                guard isLocked else { continue }
                guard update.event == .updated,
                      update.anchor.id == referenceAnchor.id else { continue }

                let transform = update.anchor.originFromAnchorTransform
                if crownRecenterDetected(
                    currentTransform: transform,
                    previousTransform: headStorage.lastWorldAnchorTransform
                ) {
                    resetHeadFollowToDefaultLayout()
                    headStorage.lastWorldAnchorTransform = transform
                } else {
                    headStorage.lastWorldAnchorTransform = transform
                }
            }

            headStorage.crownMonitorTask = nil
        }
    }

    private func stopHeadFollowCrownMonitoring() {
        headStorage.crownMonitorTask?.cancel()
        headStorage.crownMonitorTask = nil
        headStorage.crownWorldTrackingProvider = nil
        headStorage.crownARKitSession = nil
        headStorage.crownReferenceWorldAnchorID = nil
        headStorage.lastWorldAnchorTransform = nil
    }

    private func presentHeadFollowIntroIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: headFollowIntroSeenKey) else { return }
        UserDefaults.standard.set(true, forKey: headFollowIntroSeenKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.showHeadFollowIntro = true
            }
        }
    }

    private func presentHeadFollowOverlay(enabled: Bool) {
        presetOverlayText = enabled ? "Follow Mode" : "Follow Mode Off"
        presetOverlayIcon = enabled ? "figure.walk.circle.fill" : "figure.walk.circle"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false }
            }
        }
    }

    private func presentHeadFollowBlockedOverlay(feature: String) {
        presetOverlayText = "Turn off Follow Mode for \(feature)"
        presetOverlayIcon = "figure.walk.circle.fill"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false }
            }
        }
        startHideTimer()
    }

    private func saveHeadFollowVisualSnapshot() {
        UserDefaults.standard.set(dimLevel, forKey: kHeadFollowSavedDimKey)
        UserDefaults.standard.set(environmentSphereLevel, forKey: kHeadFollowSavedSphereKey)
        UserDefaults.standard.set(newsetLevel, forKey: kHeadFollowSavedNewsetKey)
    }

    private func clearHeadFollowVisualSnapshot() {
        UserDefaults.standard.removeObject(forKey: kHeadFollowSavedDimKey)
        UserDefaults.standard.removeObject(forKey: kHeadFollowSavedSphereKey)
        UserDefaults.standard.removeObject(forKey: kHeadFollowSavedNewsetKey)
    }

    private func applyHeadFollowClearedVisuals() {
        environmentSphereLevel = 0
        newsetLevel = 0
        environmentUSDZLevel = 0
        showEnvironmentPicker = false
        showDimmingPicker = false
        updateEnvironmentState()
        updateNewsetState()

        stopMoonlightCycle()
        stopTideCycle()
        stopReactiveLerp()
        dimLevel = 0
        viewModel.streamSettings.dimPassthrough = true
        applyLightingPresetVisuals(previousLevel: 0)
        updateDimmerDomesState()
    }

    private func restoreHeadFollowVisualSnapshot() {
        let savedDim = UserDefaults.standard.integer(forKey: kHeadFollowSavedDimKey)
        let savedSphere = UserDefaults.standard.integer(forKey: kHeadFollowSavedSphereKey)
        let savedNewset = UserDefaults.standard.integer(forKey: kHeadFollowSavedNewsetKey)
        clearHeadFollowVisualSnapshot()

        newsetLevel = savedNewset
        environmentSphereLevel = savedSphere

        if savedNewset > 0 {
            dimLevel = 0
            updateNewsetState()
            viewModel.streamSettings.dimPassthrough = true
        } else if savedSphere > 0 {
            dimLevel = 0
            updateEnvironmentState()
            viewModel.streamSettings.dimPassthrough = true
        } else {
            dimLevel = savedDim
            viewModel.streamSettings.dimPassthrough = (savedDim != 0)
            applyLightingPresetVisuals(previousLevel: 0)
        }

        AmbientDimmingPersistence.save(dimLevel)
        persistCurvedEnvironmentSelection()
        updateDimmerDomesState()
    }

    private func captureScaleForHeadFollowRestore() {
        scaleBeforeHeadFollow = screenScale
        targetScaleBeforeHeadFollow = targetScale
    }

    private func restoreScaleAfterHeadFollow() {
        screenScale = CurvedFirstLaunch.defaultScale
        targetScale = CurvedFirstLaunch.defaultScale
    }

    private func headFollowLookAtRotation(for offset: SIMD3<Float>) -> simd_quatf {
        let distance = simd_length(offset)
        guard distance > 1e-3 else { return simd_quatf() }
        let towardHead = -offset / distance
        let defaultFacing = SIMD3<Float>(0, 0, 1)
        let alignment = simd_dot(defaultFacing, towardHead)
        if alignment > 0.9999 { return simd_quatf() }
        if alignment < -0.9999 {
            return simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        }
        return simd_quatf(from: defaultFacing, to: towardHead)
    }

    private func applyOrbitDragDelta(startOrbit: SIMD3<Float>, localDelta: SIMD3<Float>) -> SIMD3<Float> {
        let orbitScale = CurvedFirstLaunch.headFollowOrbitRadiansPerMeter / max(startOrbit.z, 0.45)
        let deltaYaw = localDelta.x * orbitScale
        let deltaPitch = localDelta.y * orbitScale
        let clamped = CurvedFirstLaunch.clampedOrbit(
            yaw: startOrbit.x + deltaYaw,
            pitch: startOrbit.y + deltaPitch,
            radius: startOrbit.z
        )
        return CurvedFirstLaunch.offset(
            yaw: clamped.yaw,
            pitch: clamped.pitch,
            radius: clamped.radius
        )
    }

    private func headFollowPanelLocalRotation() -> simd_quatf {
        let tiltRadians = CurvedFirstLaunch.clampTilt(tiltAngle) * .pi / 180.0
        let lookRotation = headFollowLookAtRotation(for: headFollowLocalOffset)
        let tiltRotation = simd_quatf(angle: tiltRadians, axis: SIMD3<Float>(1, 0, 0))
        return lookRotation * tiltRotation
    }

    /// Target rotation based on current smoothed offset (for spring system).
    private func headFollowTargetRotation(for offset: SIMD3<Float>) -> simd_quatf {
        let tiltRadians = CurvedFirstLaunch.clampTilt(tiltAngle) * .pi / 180.0
        let lookRotation = headFollowLookAtRotation(for: offset)
        let tiltRotation = simd_quatf(angle: tiltRadians, axis: SIMD3<Float>(1, 0, 0))
        return lookRotation * tiltRotation
    }

    /// Snap spring state to current target (no smoothing) — used when entering Follow Mode or resetting.
    private func snapHeadFollowSpringState() {
        headStorage.headFollowSmoothedOffset = headFollowLocalOffset
        headStorage.headFollowOffsetVelocity = .zero
        headStorage.headFollowSmoothedRotation = headFollowPanelLocalRotation()
        headStorage.headFollowRotationVelocity = .zero
        headStorage.headFollowLastUpdateTime = CACurrentMediaTime()
    }

    /// Clear spring state when leaving Follow Mode.
    private func clearHeadFollowSpringState() {
        headStorage.headFollowSmoothedOffset = nil
        headStorage.headFollowSmoothedRotation = nil
        headStorage.headFollowOffsetVelocity = .zero
        headStorage.headFollowRotationVelocity = .zero
    }

    /// Critically damped spring step for a 3D vector.
    private func springStep(
        current: SIMD3<Float>,
        target: SIMD3<Float>,
        velocity: inout SIMD3<Float>,
        stiffness: Float,
        damping: Float,
        dt: Float
    ) -> SIMD3<Float> {
        let displacement = current - target
        let springForce = -stiffness * displacement
        let dampingForce = -damping * velocity
        let acceleration = springForce + dampingForce
        velocity += acceleration * dt
        return current + velocity * dt
    }

    /// Critically damped spring step for rotation (quaternion via axis-angle velocity).
    private func rotationSpringStep(
        current: simd_quatf,
        target: simd_quatf,
        velocity: inout SIMD3<Float>,
        stiffness: Float,
        damping: Float,
        dt: Float
    ) -> simd_quatf {
        // Compute rotation difference as axis-angle
        let diff = target * current.inverse
        let angle = diff.angle
        guard angle > 1e-6 else {
            velocity *= max(0, 1 - damping * dt * 0.1)
            return target
        }
        let axis = diff.axis
        let displacement = axis * angle

        let springForce = stiffness * displacement
        let dampingForce = -damping * velocity
        let acceleration = springForce + dampingForce
        velocity += acceleration * dt

        let stepAngle = simd_length(velocity) * dt
        guard stepAngle > 1e-8 else { return current }
        let stepAxis = simd_normalize(velocity)
        let stepRotation = simd_quatf(angle: stepAngle, axis: stepAxis)
        return simd_normalize(stepRotation * current)
    }

    private func applyHeadFollowLayoutToScreen() {
        let now = CACurrentMediaTime()
        var dt = Float(now - headStorage.headFollowLastUpdateTime)
        headStorage.headFollowLastUpdateTime = now

        // Clamp dt to prevent explosion after app pause/resume
        if dt <= 0 || dt > CurvedFirstLaunch.headFollowMaxDeltaTime {
            dt = 1.0 / 90.0
        }

        // Initialize spring state if needed
        if headStorage.headFollowSmoothedOffset == nil {
            snapHeadFollowSpringState()
        }

        let targetOffset = headFollowLocalOffset
        let targetRotation = headFollowTargetRotation(for: targetOffset)

        // Spring step for position
        var offsetVel = headStorage.headFollowOffsetVelocity
        let newOffset = springStep(
            current: headStorage.headFollowSmoothedOffset!,
            target: targetOffset,
            velocity: &offsetVel,
            stiffness: CurvedFirstLaunch.headFollowSpringStiffness,
            damping: CurvedFirstLaunch.headFollowSpringDamping,
            dt: dt
        )
        headStorage.headFollowOffsetVelocity = offsetVel
        headStorage.headFollowSmoothedOffset = newOffset

        // Spring step for rotation
        var rotVel = headStorage.headFollowRotationVelocity
        let newRotation = rotationSpringStep(
            current: headStorage.headFollowSmoothedRotation!,
            target: targetRotation,
            velocity: &rotVel,
            stiffness: CurvedFirstLaunch.headFollowRotationStiffness,
            damping: CurvedFirstLaunch.headFollowRotationDamping,
            dt: dt
        )
        headStorage.headFollowRotationVelocity = rotVel
        headStorage.headFollowSmoothedRotation = newRotation

        screen.transform = Transform(
            scale: SIMD3(repeating: screenScale),
            rotation: newRotation,
            translation: newOffset
        )
    }

    private func attachScreenToHeadForFollow(_ head: AnchorEntity) {
        guard screen.parent !== head else { return }
        screen.removeFromParent()
        head.addChild(screen)
        applyHeadFollowLayoutToScreen()
    }

    private func detachScreenFromHeadFollow() {
        guard let head = headStorage.headAnchor, screen.parent === head else { return }
        let worldTransform = Transform(matrix: screen.transformMatrix(relativeTo: nil))
        screen.removeFromParent()
        if let sceneRoot = head.parent {
            sceneRoot.addChild(screen)
        }
        screen.setTransformMatrix(worldTransform.matrix, relativeTo: nil)
        screenPosition = worldTransform.translation
    }

    private func toggleHeadFollow() {
        setHeadFollowActive(!isLocked)
        startHideTimer()
    }

    private func setHeadFollowActive(_ active: Bool) {
        if active {
            captureScaleForHeadFollowRestore()
            headFollowLocalOffset = CurvedFirstLaunch.defaultHeadFollowLocalOffset
            startHeadFollowOrbit = nil
            screenScale = CurvedFirstLaunch.headFollowScale
            targetScale = CurvedFirstLaunch.headFollowScale
            inputModeBeforeHeadFollow = inputMode
            if inputMode != .screenMove {
                gazeController.cleanup()
                inputMode = .screenMove
                updateScreenInteractivity()
            }
            saveHeadFollowVisualSnapshot()
            applyHeadFollowClearedVisuals()
            if let head = headStorage.headAnchor {
                startHeadFollowCrownMonitoring()
                attachScreenToHeadForFollow(head)
            }
            snapHeadFollowSpringState()
            isLocked = true
            presentHeadFollowOverlay(enabled: true)
            presentHeadFollowIntroIfNeeded()
        } else {
            isLocked = false
            showHeadFollowIntro = false
            clearHeadFollowSpringState()
            detachScreenFromHeadFollow()
            screenScale = CurvedFirstLaunch.defaultScale
            targetScale = CurvedFirstLaunch.defaultScale
            if let head = headStorage.headAnchor {
                resetScreenToDefaultPosition(head: head)
            }
            restoreHeadFollowVisualSnapshot()
            if let savedMode = inputModeBeforeHeadFollow {
                inputModeBeforeHeadFollow = nil
                inputMode = savedMode
                if inputMode == .gazeControl {
                    gazeController.streamConfig = streamConfig
                }
                updateScreenInteractivity()
            }
            headFollowLocalOffset = CurvedFirstLaunch.defaultHeadFollowLocalOffset
            startHeadFollowOrbit = nil
            stopHeadFollowCrownMonitoring()
            presentHeadFollowOverlay(enabled: false)
        }
    }

    /// Reset screen to the same world pose as first install (2.75 m in front of head, saved/default Y).
    private func placeScreenAtFirstInstallPosition(head: AnchorEntity) {
        if screen.parent === head {
            detachScreenFromHeadFollow()
        }
        placeScreenInFrontOfHead(
            head: head,
            distance: CurvedFirstLaunch.defaultDistance,
            verticalOffset: CurvedFirstLaunch.verticalOffsetFromHead
        )
    }

    /// Reset screen to the same position used on initial app install.
    private func resetScreenToDefaultPosition(head: AnchorEntity) {
        placeScreenAtFirstInstallPosition(head: head)
    }

    /// Compute the fixed default Y for the screen (consistent regardless of head height at call time).
    private func defaultScreenY(headPos: SIMD3<Float>, verticalOffset: Float) -> Float {
        let panelHalfHeight = CURVED_MAX_WIDTH_METERS * screenAspect * CurvedFirstLaunch.eyeLevelLiftReferenceScale * 0.5
        let computedY = headPos.y + verticalOffset + panelHalfHeight * 2

        let savedY = UserDefaults.standard.float(forKey: kCurvedDefaultYKey)
        if savedY > 0 {
            return savedY
        }
        UserDefaults.standard.set(computedY, forKey: kCurvedDefaultYKey)
        return computedY
    }

    /// First launch: place the panel in front of the user's head at a fixed distance (immersive world space).
    private func placeScreenInFrontOfHead(head: AnchorEntity, distance: Float, verticalOffset: Float) {
        let headPos = head.position(relativeTo: nil)
        let flatForward = flatHeadForward(head)
        var newPos = headPos + flatForward * distance
        newPos.y = defaultScreenY(headPos: headPos, verticalOffset: verticalOffset)
        newPos.x = min(max(newPos.x, -allowedLateralMax), allowedLateralMax)
        screenPosition = newPos
    }

    private func recenterScreenToHead(head: AnchorEntity) {
        recenterScreenToHeadFlat(head: head)
    }

    private func recenterScreenToHeadFlat(head: AnchorEntity) {
        let preservedScale = screenScale
        let preservedTargetScale = targetScale

        let headPos = head.position(relativeTo: nil)
        let current = currentScreenWorldPosition()
        let yOffset = current.y - headPos.y
        let actualDistance = simd_length(current - headPos)
        let flatForward = flatHeadForward(head)

        var newPos = simd_float3(
            headPos.x + flatForward.x * actualDistance,
            headPos.y + yOffset,
            headPos.z + flatForward.z * actualDistance
        )
        newPos.x = min(max(newPos.x, -allowedLateralMax), allowedLateralMax)

        screenPosition = newPos
        screenScale = preservedScale
        targetScale = preservedTargetScale
    }

    private func saveCurrentTransform() {
        let pos: SIMD3<Float>
        if isLocked, screen.parent != nil {
            pos = Transform(matrix: screen.transformMatrix(relativeTo: nil)).translation
        } else {
            pos = screenPosition
        }
        let scale = isLocked ? scaleBeforeHeadFollow : screenScale
        let packed = [pos.x, pos.y, pos.z]
        UserDefaults.standard.set(packed, forKey: kCurvedPosKey)
        UserDefaults.standard.set(scale, forKey: kCurvedScaleKey)
        tiltAngle = CurvedFirstLaunch.clampTilt(tiltAngle)
        yawAngle = CurvedFirstLaunch.clampYaw(yawAngle)
        savedTiltAngle = Double(tiltAngle)
        savedYawAngle = Double(yawAngle)
    }

    private func applyScreenPresetValues(_ values: ScreenPresetValues) {
        screenPosition = values.position
        screenScale = values.scale
        targetScale = values.scale
        tiltAngle = CurvedFirstLaunch.clampTilt(values.tiltAngle)
        yawAngle = CurvedFirstLaunch.clampYaw(values.yawAngle)
        savedTiltAngle = Double(tiltAngle)
        savedYawAngle = Double(yawAngle)
        setCurveMagnitude(values.curveMagnitude)
        headStorage.forceCollisionRegen = true
        screenAdjustBaselineTilt = tiltAngle
        screenAdjustBaselineYaw = yawAngle
    }

    private func applyScreenPreset(slot: Int, showToast: Bool = true, atLaunch: Bool = false) {
        if !atLaunch {
            guard !isLocked else {
                presentHeadFollowBlockedOverlay(feature: "Screen Preset")
                return
            }
        }

        let clamped = ScreenPresetSettings.clampSlot(slot)
        screenPresetSettings.selectActiveSlot(clamped)

        guard ScreenPresetSettings.hasSavedData(for: clamped),
              let values = ScreenPresetSettings.loadValues(for: clamped) else {
            if atLaunch {
                applyFirstLaunchDefaultsToState(scheduleHeadPlacement: true)
            } else {
                applyDefaultLaunchPlacement()
                presentScreenPresetCenterToast(
                    name: screenPresetSettings.displayName(for: clamped),
                    isEmpty: true
                )
            }
            return
        }

        headStorage.presetApplyRefineTask?.cancel()
        headStorage.presetApplyRefineTask = nil

        // Apply persisted coordinates immediately — never block UI on ARKit relocalization.
        applyScreenPresetValues(values)
        suppressPresetAnchorUpdates(for: ScreenPresetAnchorTolerance.suppressAfterManualApplySeconds)

        if !atLaunch {
            saveCurrentTransform()
        }
        if showToast {
            presentScreenPresetCenterToast(
                name: screenPresetSettings.displayName(for: clamped),
                isEmpty: false
            )
        }

        guard let anchorID = values.worldAnchorID else {
            stopPresetAnchorMonitoring()
            return
        }

        let anchorWait = atLaunch
            ? ScreenPresetAnchorTolerance.launchAnchorWaitSeconds
            : ScreenPresetAnchorTolerance.interactiveAnchorWaitSeconds

        headStorage.presetApplyRefineTask = Task { @MainActor in
            let resolvedValues = await resolveWorldAnchorPosition(for: values, timeoutSeconds: anchorWait)
            guard !Task.isCancelled else { return }

            if screenPresetPoseDiffersSignificantly(
                position: resolvedValues.position,
                tilt: resolvedValues.tiltAngle,
                yaw: resolvedValues.yawAngle,
                from: values.position,
                referenceTilt: values.tiltAngle,
                referenceYaw: values.yawAngle
            ) {
                applyScreenPresetValues(resolvedValues)
                suppressPresetAnchorUpdates(for: 1.0)
                if !atLaunch {
                    saveCurrentTransform()
                }
            }

            guard !Task.isCancelled else { return }
            startPresetAnchorMonitoring(anchorID: anchorID)
        }
    }

    private func captureCurrentScreenToPreset(slot: Int) {
        guard !isLocked else {
            presentHeadFollowBlockedOverlay(feature: "Screen Preset")
            return
        }

        let clamped = ScreenPresetSettings.clampSlot(slot)
        let worldMatrix = currentScreenWorldPoseMatrix()

        var values = presetValuesFromWorldMatrix(
            worldMatrix,
            scale: screenScale,
            curveMagnitude: curveMagnitude
        )

        Task { @MainActor in
            let anchorID = await saveWorldAnchorForPreset(slot: clamped)
            values.worldAnchorID = anchorID
            ScreenPresetSettings.saveValues(values, for: clamped)
            screenPresetSettings.selectActiveSlot(clamped)
            suppressPresetAnchorUpdates(for: ScreenPresetAnchorTolerance.suppressAfterManualApplySeconds)
            if let anchorID = anchorID {
                startPresetAnchorMonitoring(anchorID: anchorID)
            } else {
                stopPresetAnchorMonitoring()
            }
            presentScreenPresetCenterToast(
                name: screenPresetSettings.displayName(for: clamped),
                isEmpty: false,
                saved: true
            )
        }
    }

    private func presentScreenPresetCenterToast(name: String, isEmpty: Bool, saved: Bool = false) {
        if saved {
            presetOverlayText = "Saved: \(name)"
            presetOverlayIcon = "square.and.arrow.down"
        } else if isEmpty {
            presetOverlayText = "\(name) not saved yet"
            presetOverlayIcon = "rectangle.on.rectangle.angled"
        } else {
            presetOverlayText = "Screen Preset: \(name)"
            presetOverlayIcon = "rectangle.on.rectangle.angled"
        }
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
        }
    }

    // MARK: - World Anchor Preset Support

    private func currentScreenWorldPoseMatrix() -> simd_float4x4 {
        screen.transformMatrix(relativeTo: nil)
    }

    /// Strip scale from a world matrix so ARKit stores a pure pose for the screen origin.
    private func normalizedWorldPoseMatrix(_ matrix: simd_float4x4) -> simd_float4x4 {
        var pose = matrix
        pose.columns.0 = simd_normalize(pose.columns.0)
        pose.columns.1 = simd_normalize(pose.columns.1)
        pose.columns.2 = simd_normalize(pose.columns.2)
        pose.columns.3 = simd_float4(translationFromTransform(matrix), 1)
        return pose
    }

    /// Inverse of `screen.transform` rotation order: yaw (Y) × pitch (X).
    private func screenPresetAnglesFromWorldPoseMatrix(_ matrix: simd_float4x4) -> (tilt: Float, yaw: Float) {
        let pitchRadians = asin(min(max(-matrix.columns.1.z, -1), 1))
        let cosPitch = cos(pitchRadians)
        let yawRadians: Float
        if abs(cosPitch) > 0.001 {
            yawRadians = atan2(matrix.columns.2.x, matrix.columns.2.z)
        } else {
            yawRadians = flatYawFromTransform(matrix)
        }
        return (
            CurvedFirstLaunch.clampTilt(pitchRadians * 180 / .pi),
            CurvedFirstLaunch.clampYaw(yawRadians * 180 / .pi)
        )
    }

    private func presetValuesFromWorldMatrix(
        _ matrix: simd_float4x4,
        scale: Float,
        curveMagnitude: Float
    ) -> ScreenPresetValues {
        let pose = normalizedWorldPoseMatrix(matrix)
        let angles = screenPresetAnglesFromWorldPoseMatrix(pose)
        return ScreenPresetValues(
            position: translationFromTransform(pose),
            scale: scale,
            curveMagnitude: curveMagnitude,
            tiltAngle: angles.tilt,
            yawAngle: angles.yaw,
            worldAnchorID: nil
        )
    }

    private func applyScreenPoseFromWorldMatrix(_ matrix: simd_float4x4, updateSavedState: Bool) {
        let pose = normalizedWorldPoseMatrix(matrix)
        let angles = screenPresetAnglesFromWorldPoseMatrix(pose)
        screenPosition = translationFromTransform(pose)
        tiltAngle = angles.tilt
        yawAngle = angles.yaw
        if updateSavedState {
            savedTiltAngle = Double(tiltAngle)
            savedYawAngle = Double(yawAngle)
        }
        screenAdjustBaselineTilt = tiltAngle
        screenAdjustBaselineYaw = yawAngle
    }

    private func findTrackedWorldAnchor(id: UUID, in provider: WorldTrackingProvider) async -> WorldAnchor? {
        // Guard: Only access allAnchors when the provider is running to avoid log spam
        guard provider.state == .running else { return nil }
        let anchors = await provider.allAnchors ?? []
        return anchors.first { $0.id == id && $0.isTracked }
    }

    /// Waits for ARKit to relocalize a persisted world anchor (poll + anchorUpdates).
    private func waitForTrackedWorldAnchor(
        id: UUID,
        provider: WorldTrackingProvider,
        timeoutSeconds: TimeInterval = 6.0
    ) async -> WorldAnchor? {
        if let initial = await findTrackedWorldAnchor(id: id, in: provider) {
            return initial
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)

        return await withCheckedContinuation { continuation in
            var finished = false
            let finish: (WorldAnchor?) -> Void = { anchor in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: anchor)
            }

            let listenTask = Task { @MainActor in
                for await update in provider.anchorUpdates {
                    guard update.anchor.id == id else { continue }
                    if update.event == .removed {
                        finish(nil)
                        return
                    }
                    if update.anchor.isTracked {
                        finish(update.anchor)
                        return
                    }
                }
            }

            Task { @MainActor in
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if let anchor = await findTrackedWorldAnchor(id: id, in: provider) {
                        listenTask.cancel()
                        finish(anchor)
                        return
                    }
                }
                listenTask.cancel()
                finish(await findTrackedWorldAnchor(id: id, in: provider))
            }
        }
    }

    private func shouldApplyPresetAnchorUpdates() -> Bool {
        CACurrentMediaTime() >= headStorage.presetAnchorApplySuppressUntil
            && !isLocked
            && activeScreenAdjustHandle == nil
            && !curvatureSliderDragging
            && startDragPosition == nil
    }

    private func suppressPresetAnchorUpdates(for seconds: TimeInterval) {
        headStorage.presetAnchorApplySuppressUntil = CACurrentMediaTime() + seconds
    }

    private func screenPresetPoseDiffersSignificantly(
        position: SIMD3<Float>,
        tilt: Float,
        yaw: Float,
        from referencePosition: SIMD3<Float>,
        referenceTilt: Float,
        referenceYaw: Float
    ) -> Bool {
        simd_length(position - referencePosition) > ScreenPresetAnchorTolerance.positionMeters
            || abs(tilt - referenceTilt) > ScreenPresetAnchorTolerance.angleDegrees
            || abs(yaw - referenceYaw) > ScreenPresetAnchorTolerance.angleDegrees
    }

    private func shouldApplyPresetAnchorPose(_ matrix: simd_float4x4) -> Bool {
        guard shouldApplyPresetAnchorUpdates() else { return false }
        let pose = normalizedWorldPoseMatrix(matrix)
        let angles = screenPresetAnglesFromWorldPoseMatrix(pose)
        return screenPresetPoseDiffersSignificantly(
            position: translationFromTransform(pose),
            tilt: angles.tilt,
            yaw: angles.yaw,
            from: screenPosition,
            referenceTilt: tiltAngle,
            referenceYaw: yawAngle
        )
    }

    private func startPresetAnchorMonitoring(anchorID: UUID) {
        stopPresetAnchorMonitoring()
        headStorage.activePresetWorldAnchorID = anchorID

        headStorage.presetAnchorMonitorTask = Task { @MainActor in
            guard let provider = await ensurePresetWorldTrackingSession() else { return }

            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                guard headStorage.activePresetWorldAnchorID == anchorID else { break }
                guard update.anchor.id == anchorID, update.anchor.isTracked else { continue }
                guard update.event == .added || update.event == .updated else { continue }
                guard shouldApplyPresetAnchorPose(update.anchor.originFromAnchorTransform) else { continue }

                applyScreenPoseFromWorldMatrix(update.anchor.originFromAnchorTransform, updateSavedState: false)
            }
        }
    }

    private func stopPresetAnchorMonitoring() {
        headStorage.presetApplyRefineTask?.cancel()
        headStorage.presetApplyRefineTask = nil
        headStorage.presetAnchorMonitorTask?.cancel()
        headStorage.presetAnchorMonitorTask = nil
        headStorage.activePresetWorldAnchorID = nil
    }

    private func ensurePresetWorldTrackingSession() async -> WorldTrackingProvider? {
        if let existing = headStorage.presetWorldTrackingProvider {
            return existing
        }
        let provider = WorldTrackingProvider()
        let session = ARKitSession()
        do {
            try await session.run([provider])
        } catch {
            print("[ScreenPreset] World tracking unavailable: \(error)")
            return nil
        }
        headStorage.presetWorldTrackingProvider = provider
        headStorage.presetARKitSession = session
        return provider
    }

    private func saveWorldAnchorForPreset(slot: Int) async -> UUID? {
        guard let provider = await ensurePresetWorldTrackingSession() else { return nil }

        // Remove old anchor for this slot if present
        if let oldValues = ScreenPresetSettings.loadValues(for: slot),
           let oldAnchorID = oldValues.worldAnchorID {
            do {
                try await provider.removeAnchor(forID: oldAnchorID)
            } catch {
                print("[ScreenPreset] Failed to remove old anchor for slot \(slot): \(error)")
            }
        }

        let anchorMatrix = normalizedWorldPoseMatrix(currentScreenWorldPoseMatrix())
        let anchor = WorldAnchor(originFromAnchorTransform: anchorMatrix)
        do {
            try await provider.addAnchor(anchor)
            print("[ScreenPreset] Saved world anchor \(anchor.id) for slot \(slot) at \(translationFromTransform(anchorMatrix))")
            return anchor.id
        } catch {
            print("[ScreenPreset] Failed to save world anchor for slot \(slot): \(error)")
            return nil
        }
    }

    private func resolveWorldAnchorPosition(
        for values: ScreenPresetValues,
        timeoutSeconds: TimeInterval = ScreenPresetAnchorTolerance.interactiveAnchorWaitSeconds
    ) async -> ScreenPresetValues {
        guard let anchorID = values.worldAnchorID else { return values }
        guard let provider = await ensurePresetWorldTrackingSession() else { return values }

        if let anchor = await waitForTrackedWorldAnchor(id: anchorID, provider: provider, timeoutSeconds: timeoutSeconds) {
            var resolved = values
            let poseMatrix = normalizedWorldPoseMatrix(anchor.originFromAnchorTransform)
            let angles = screenPresetAnglesFromWorldPoseMatrix(poseMatrix)
            resolved.position = translationFromTransform(poseMatrix)
            resolved.tiltAngle = angles.tilt
            resolved.yawAngle = angles.yaw
            print("[ScreenPreset] Resolved world anchor \(anchorID) → position \(resolved.position), tilt \(angles.tilt)°, yaw \(angles.yaw)°")
            return resolved
        }

        print("[ScreenPreset] World anchor \(anchorID) not tracked after wait; using saved fallback pose")
        return values
    }

    private func restoreSavedTransform() {
        if let packed = UserDefaults.standard.array(forKey: kCurvedPosKey) as? [Float], packed.count == 3 {
            screenPosition = SIMD3<Float>(packed[0], packed[1], packed[2])
        }
        let scale = UserDefaults.standard.float(forKey: kCurvedScaleKey)
        if scale > 0 {
            screenScale = scale
            targetScale = scale
        }
        tiltAngle = CurvedFirstLaunch.clampTilt(Float(savedTiltAngle))
        yawAngle = CurvedFirstLaunch.clampYaw(Float(savedYawAngle))
        savedTiltAngle = Double(tiltAngle)
        savedYawAngle = Double(yawAngle)
    }
    
    private let kCurvedLockedKey = "curved.locked"
    private let kCurvedPosKey = "curved.pos"
    private let kCurvedScaleKey = "curved.scale"
    private let kCurvedDefaultYKey = "curved.defaultY"
    private let kCurvedSpecialModeExitKey = "curved.specialModeExit"
    private let tutorialSeenKey = "hasSeenCurvedDisplayTutorial_v3"

    private func refreshImmersiveStreamScenePin() {
        if let sceneID = AudioHelpers.immersiveSpaceSceneIdentifier() {
            immersiveSpaceSceneID = sceneID
            AudioHelpers.pinStreamAudioToScene(sceneID)
        }
    }

    private func restoreStreamAudioAfterMenuDismiss() {
        isMenuOpen = false
        refreshImmersiveStreamScenePin()
        fixAudioForCurrentMode()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.refreshImmersiveStreamScenePin()
            self.fixAudioForCurrentMode()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.fixAudioForCurrentMode()
        }
    }

    private func handleResumeFromMenu() {
        isMenuOpen = false
        withAnimation(.easeInOut) {
            self.showMenuPanel = false
        }
        dismissWindow(id: "mainView")
        restoreStreamAudioAfterMenuDismiss()
        self.refreshAfterResume()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) { self.refreshAfterResume() }
        self.controlsHighlighted = false
        self.startHideTimer()
    }

    private func startMoonlightCycle() {
        moonlightCyclePhase = 0.0
        moonlightCycleTimer?.invalidate()
        lastMoonlightUpdateTime = CACurrentMediaTime()

        if let purple = self.headStorage.dimmerDomePurple {
            let initial = getMoonlightCycleColor(phase: moonlightCyclePhase).withAlphaComponent(moonlightAlphaLowPower)
            var mat = moonlightMaterial ?? UnlitMaterial(color: initial)
            mat.blending = .transparent(opacity: 1.0)
            self.moonlightMaterial = mat
            purple.model?.materials = [mat]
            self.lastMoonlightAppliedRGB = rgb(initial)
        }

        moonlightCycleTimer = Timer.scheduledTimer(withTimeInterval: moonlightUpdateIntervalLowPower, repeats: true) { _ in
            guard self.dimLevel == 11, let purple = self.headStorage.dimmerDomePurple else { return }

            let now = CACurrentMediaTime()
            let dt = now - self.lastMoonlightUpdateTime
            
            DispatchQueue.main.async {
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
    }

    private func stopMoonlightCycle() {
        moonlightCycleTimer?.invalidate()
        moonlightCycleTimer = nil
        moonlightMaterial = nil
    }

    // MARK: - Tide morphing gradient cycle

    private func tideBrightnessAlpha() -> CGFloat {
        if let userBrightness = presetBrightness[10] {
            return CGFloat(userBrightness)
        }
        return defaultPresetBrightness[10] ?? 0.90
    }

    private func buildTideMaterial(phase: CGFloat) -> UnlitMaterial? {
        guard let cgImage = TideGradientPalette.makeCGImage(size: 256, phase: phase),
              let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) else {
            return nil
        }
        var mat = UnlitMaterial(texture: texture)
        mat.color.tint = UIColor.white.withAlphaComponent(tideBrightnessAlpha())
        mat.blending = .transparent(opacity: 1.0)
        return mat
    }

    private func currentTidePhase() -> CGFloat {
        let elapsed = CACurrentMediaTime() - tideCycleStartTime
        let wrapped = elapsed.truncatingRemainder(dividingBy: Double(tideCycleDuration))
        return CGFloat(wrapped / Double(tideCycleDuration))
    }

    private func applyTideMaterialToDome(phase: CGFloat) {
        guard let mat = buildTideMaterial(phase: phase), let purple = headStorage.dimmerDomePurple else { return }
        tideMaterial = mat
        purple.model?.materials = [mat]
    }

    private func startTideCycle() {
        tideCycleTimer?.invalidate()
        tideCycleStartTime = CACurrentMediaTime()
        applyTideMaterialToDome(phase: currentTidePhase())

        let timer = Timer(timeInterval: tideUpdateInterval, repeats: true) { _ in
            guard self.dimLevel == 10, self.headStorage.dimmerDomePurple != nil else { return }
            self.tideCyclePhase = self.currentTidePhase()
            self.applyTideMaterialToDome(phase: self.tideCyclePhase)
        }
        RunLoop.main.add(timer, forMode: .common)
        tideCycleTimer = timer
    }

    private func stopTideCycle() {
        tideCycleTimer?.invalidate()
        tideCycleTimer = nil
        tideMaterial = nil
    }
    
    /// Resets purple reactive dome transform if a prior build left non-identity envelope state.
    private func cancelReactiveSphereEnvelopeIntro(resetDomeVisuals: Bool = true) {
        guard resetDomeVisuals, let purple = headStorage.dimmerDomePurple else { return }
        purple.scale = SIMD3<Float>(-1, 1, 1)
        purple.components.remove(OpacityComponent.self)
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
            guard let purple = self.headStorage.dimmerDomePurple else { return }
            let isReactive = self.dimLevel == 12
            guard isReactive else { return }

            // Lerp factor: 0.15 = smooth but responsive (reaches 95% in ~0.2s)
            let lerpFactor: CGFloat = 0.15

            var currentR: CGFloat = 0, currentG: CGFloat = 0, currentB: CGFloat = 0, currentA: CGFloat = 0
            self.currentAmbientColor.getRed(&currentR, green: &currentG, blue: &currentB, alpha: &currentA)

            var targetR: CGFloat = 0, targetG: CGFloat = 0, targetB: CGFloat = 0, targetA: CGFloat = 0
            self.targetReactiveColor.getRed(&targetR, green: &targetG, blue: &targetB, alpha: &targetA)

            // Linear interpolation toward center zone color
            let newR = currentR + (targetR - currentR) * lerpFactor
            let newG = currentG + (targetG - currentG) * lerpFactor
            let newB = currentB + (targetB - currentB) * lerpFactor

            DispatchQueue.main.async {
                self.currentAmbientColor = UIColor(red: newR, green: newG, blue: newB, alpha: 1.0)
            }

            // Update material
            let (mat, _) = self.getDimmerMaterial()
            purple.model?.materials = [mat]
        }
    }
    
    private func stopReactiveLerp() {
        reactiveLerpTimer?.invalidate()
        reactiveLerpTimer = nil
    }

    // MARK: - ChromaHalo

    private func makeChromosphereMesh(curveMagnitude: Float) throws -> MeshResource {
        let haloScale = videoDecoder?.chromaHaloScale ?? 1.55
        // Match main curved panel tessellation (see `setupRealityView` screen mesh). Symmetric grid avoids
        // uneven UV density vs the halo texture that made the shell read as a rectangular “LED matrix”.
        let res: (UInt32, UInt32) = (256, 256)
        return try generateCurvedRoundedPlane(
            width: CURVED_MAX_WIDTH_METERS * haloScale,
            aspectRatio: screenAspect,
            resolution: res,
            curveMagnitude: curveMagnitude,
            cornerRadiusFraction: cornerRadiusFraction / haloScale
        )
    }

    private func fallbackChromospherePlaneMesh() -> MeshResource {
        let haloScale = videoDecoder?.chromaHaloScale ?? 1.55
        return MeshResource.generatePlane(
            width: CURVED_MAX_WIDTH_METERS * haloScale,
            height: CURVED_MAX_WIDTH_METERS * screenAspect * haloScale
        )
    }

    /// Rebuild chromosphere geometry to match the display (`generateCurvedRoundedPlane` halo shell).
    private func replaceChromosphereMeshWithDisplayCurve(_ curveMagnitude: Float) {
        guard let haloEnt = chromosphereMeshEntity ?? headStorage.chromosphereHaloEntity, let model = haloEnt.model else { return }
        let haloResource = (try? makeChromosphereMesh(curveMagnitude: curveMagnitude)) ?? fallbackChromospherePlaneMesh()
        do {
            try model.mesh.replace(with: haloResource.contents)
        } catch {
            print("⚠️ Chromosphere mesh.replace failed: \(error)")
        }
        applyChromosphereHaloLocalZOffset(curveMagnitude: curveMagnitude, entity: haloEnt)
    }

    /// Chromosphere mesh + halo intensity — Reactive 1 (curved bezel).
    private func updateChromosphereMesh() {
        guard let decoder = videoDecoder else { return }

        let pipelineActive = usesChromosphereHaloPipeline
        decoder.chromaHaloIntensity = pipelineActive ? 1.0 : 0.0

        if dimLevel == 2 {
            let idx = Reactive1ChromosphereReach.clampedSavedIndex()
            decoder.chromaHaloScale = Reactive1ChromosphereReach.haloScale(forIndex: idx)
        }

        guard let tex = chromosphereTexture else { return }

        if let shell = chromosphereMeshEntity ?? headStorage.chromosphereHaloEntity {
            applyChromosphereMaterial(
                to: shell,
                texture: tex,
                visible: dimLevel == 2 && firstFrameReceived
            )
        }
    }

    private func applyChromosphereMaterial(to entity: ModelEntity, texture: TextureResource, visible: Bool) {
        var mat = UnlitMaterial(texture: texture)
        mat.blending = .transparent(opacity: 1.0)
        mat.color.tint = UIColor.white.withAlphaComponent(visible ? 1.0 : 0.0)
        if entity.model != nil {
            entity.model?.materials = [mat]
        }
        entity.components.set(OpacityComponent(opacity: visible ? 1.0 : 0.0))
    }

    // MARK: - Timers & State Changes

    private func startHideTimer() {
        hideTimer?.invalidate()
        hideControls = false
        controlsHighlighted = true

        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.viewModel.streamSettings.useCollapsedControlsMenu && self.controlsExpanded {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        self.controlsExpanded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.collapsedMenuHideDelay) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            self.controlsExpanded = false
                            self.hideControls = true
                            self.controlsHighlighted = false
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.hideControls = true
                        self.controlsHighlighted = false
                    }
                }
            }
        }
    }
    
    private func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.viewModel.streamSettings.useCollapsedControlsMenu && self.controlsExpanded {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        self.controlsExpanded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.collapsedMenuHideDelay) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            self.controlsExpanded = false
                            self.hideControls = true
                            self.controlsHighlighted = false
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.hideControls = true
                        self.controlsHighlighted = false
                    }
                }
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
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.showModeLabel = false
                }
            }
        }
    }

    /// Center toast for FILTER selection; if Reference HDR blocks preset grading, follows with a short hint.
    private func presentFilterPresetCenterPopup(selectedPreset: Int32) {
        presetOverlayText = presetName(for: selectedPreset)
        presetOverlayIcon = "camera.filters"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        
        let needsReferenceHdrOffHint = selectedPreset != 0
            && viewModel.streamSettings.enableHdr
            && hdrPanelSettings.referenceHDR
        
        if needsReferenceHdrOffHint {
            presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.presetOverlayText = "DISABLE REFERENCE HDR TO USE FILTER PRESETS"
                    self.presetOverlayIcon = "wand.and.stars"
                    self.presetOverlayTimer?.invalidate()
                    self.presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 2.1, repeats: false) { _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.15)) {
                                self.showInlinePresetOverlay = false
                            }
                        }
                    }
                }
            }
        } else {
            presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.showInlinePresetOverlay = false
                    }
                }
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
    
    private func canChangePreset() -> Bool {
        guard let cooldownUntil = presetCooldownUntil else { return true }
        return Date() >= cooldownUntil
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let streamMan = self.streamMan, let stats = streamMan.getStatsOverlayText() {
                DispatchQueue.main.async {
                    self.statsOverlayText = stats
                }
            }
        }
    }
    
    private func fixAudioForCurrentMode() {
        if self.spatialAudioMode {
            AudioHelpers.fixAudioForSurroundForStream(
                soundStageSize: soundStageSize,
                sceneIdentifier: immersiveSpaceSceneID
            )
        } else {
            AudioHelpers.fixAudioForDirectStereo()
        }
    }

    private func toggleStreamPeekThrough() {
        setStreamPeekThroughActive(!streamPeekThroughActive)
        guard streamPeekThroughActive else { return }
        presetOverlayText = "Pass Through Mode"
        presetOverlayIcon = "vision.pro"
        showInlinePresetOverlay = true
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) { self.showInlinePresetOverlay = false }
            }
        }
        startHideTimer()
    }

    /// Top bar is parented to the screen; OpacityComponent on the screen fades children too — reparent controls to the scene root while peeking.
    private func reparentControlsForPeekThrough(active: Bool) {
        guard let controls = headStorage.controlsEntity, screen.parent != nil else { return }

        if active {
            guard controls.parent === screen, let sceneRoot = screen.parent else { return }
            headStorage.controlsTransformBeforePeek = controls.transform
            let worldTransform = controls.transformMatrix(relativeTo: nil)
            controls.removeFromParent()
            sceneRoot.addChild(controls)
            controls.setTransformMatrix(worldTransform, relativeTo: nil)
            controls.components.set(OpacityComponent(opacity: 1.0))
        } else if headStorage.controlsTransformBeforePeek != nil {
            let worldTransform = controls.transformMatrix(relativeTo: nil)
            controls.removeFromParent()
            screen.addChild(controls)
            controls.setTransformMatrix(worldTransform, relativeTo: nil)
            controls.components.remove(OpacityComponent.self)
            headStorage.controlsTransformBeforePeek = nil
        }
    }

    private func cancelPassThroughFade() {
        passThroughFadeTimer?.invalidate()
        passThroughFadeTimer = nil
    }

    private func passThroughSmoothstep(_ t: Float) -> Float {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func currentPassThroughStreamOpacity() -> Float {
        screen.components[OpacityComponent.self]?.opacity ?? 1.0
    }

    private func applyPassThroughStreamOpacity(_ opacity: Float) {
        screen.components.set(OpacityComponent(opacity: opacity))
        if let halo = headStorage.chromosphereHaloEntity {
            halo.components.set(OpacityComponent(opacity: opacity))
        }
    }

    private func restorePassThroughStreamOpacityFully() {
        screen.components.remove(OpacityComponent.self)
        headStorage.chromosphereHaloEntity?.components.remove(OpacityComponent.self)
        updateChromosphereMesh()
    }

    private func animatePassThroughTransition(
        targetOpacity: Float,
        restoreFullOpacity: Bool,
        targetVolume: Float?,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        cancelPassThroughFade()
        guard screen.parent != nil else {
            completion?()
            return
        }

        let startOpacity = currentPassThroughStreamOpacity()
        let startVolume = viewModel.vol
        let steps = max(Int(duration * 60), 1)
        let interval = duration / Double(steps)
        var currentStep = 0

        passThroughFadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            currentStep += 1
            let progress = passThroughSmoothstep(Float(currentStep) / Float(steps))
            let newOpacity = startOpacity + (targetOpacity - startOpacity) * progress
            applyPassThroughStreamOpacity(newOpacity)

            if let targetVolume {
                let newVolume = startVolume + (targetVolume - startVolume) * progress
                viewModel.vol = newVolume
                StreamVolume.apply(Int32(newVolume))
            }

            guard currentStep >= steps else { return }

            timer.invalidate()
            passThroughFadeTimer = nil

            if restoreFullOpacity {
                restorePassThroughStreamOpacityFully()
            } else {
                applyPassThroughStreamOpacity(targetOpacity)
            }

            if let targetVolume {
                viewModel.vol = targetVolume
                StreamVolume.apply(Int32(targetVolume))
            }

            completion?()
        }
    }

    private func setStreamPeekThroughActive(_ active: Bool) {
        guard streamPeekThroughActive != active else { return }
        streamPeekThroughActive = active
        updateScreenInteractivity()
        syncCurvedGamepadSession()

        guard screen.parent != nil else { return }

        if active {
            reparentControlsForPeekThrough(active: true)
            if viewModel.vol > 0 {
                streamVolumeBeforePeek = viewModel.vol
            }
            gazeController.cleanup()

            let targetVolume: Float? = viewModel.vol > 0 ? streamPeekVolumeLevel : nil
            animatePassThroughTransition(
                targetOpacity: streamPeekScreenOpacity,
                restoreFullOpacity: false,
                targetVolume: targetVolume,
                duration: streamPeekFadeInDuration
            )
        } else {
            let targetVolume: Float? = (viewModel.vol > 0 && streamVolumeBeforePeek > 0) ? streamVolumeBeforePeek : nil
            animatePassThroughTransition(
                targetOpacity: 1.0,
                restoreFullOpacity: false,
                targetVolume: targetVolume,
                duration: streamPeekFadeOutDuration
            ) {
                reparentControlsForPeekThrough(active: false)
                restorePassThroughStreamOpacityFully()
            }
        }
    }

    /// Clears peek-through when leaving the stream (restores volume and screen opacity).
    private func clearStreamPeekThroughIfNeeded() {
        guard streamPeekThroughActive else { return }
        cancelPassThroughFade()
        streamPeekThroughActive = false
        if screen.parent != nil {
            reparentControlsForPeekThrough(active: false)
            restorePassThroughStreamOpacityFully()
        }
        if viewModel.vol > 0, streamVolumeBeforePeek > 0 {
            viewModel.vol = streamVolumeBeforePeek
            StreamVolume.apply(Int32(streamVolumeBeforePeek))
        }
        updateScreenInteractivity()
        syncCurvedGamepadSession()
    }

    private func updateScreenInteractivity() {
        guard screen.parent != nil else { return }
        // Disable screen collision when menus/pickers are showing OR when in Controller mode.
        // Otherwise the curved screen mesh intercepts pinches meant for attachment panels.
        let shouldDisableInteractions = showMenuPanel || showSwapConfirm || show3DConfirm || showDisconnectConfirm
            || showHDRPanel || showScreenPresetPanel || showEnvironmentPicker || showDimmingPicker || showDesktopActionsPicker
            || showCurvedTutorial || hdrPresetRenamingActive || screenPresetRenamingActive
            || streamPeekThroughActive
            || inputMode == .controller
        if shouldDisableInteractions {
            screen.components.remove(CollisionComponent.self)
            screen.components.remove(InputTargetComponent.self)
        } else {
            // Generate curved collision mesh for accurate gaze hit detection
            if let collisionMesh = try? generateCurvedRoundedPlane(
                width: CURVED_MAX_WIDTH_METERS,
                aspectRatio: screenAspect,
                resolution: (64, 64),
                curveMagnitude: effectiveCurveMagnitude,
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
                self.reapplyPersistedEnvironmentAfterExtrasLoad()
            }
        }
    }
}

// MARK: - Digital Crown world recenter (visionOS 26+)

private extension View {
    @ViewBuilder
    func curvedOnWorldRecenter(_ action: @escaping @MainActor (WorldRecenterPhase) -> Void) -> some View {
        if #available(visionOS 26.0, *) {
            self.onWorldRecenter(action: action)
        } else {
            self
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
