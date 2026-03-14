//
//  FloatingMicButton.swift
//  Neo Moonlight
//
//  Created by NeoVectorX


import SwiftUI
import RealityKit
import simd
import GameController
import ARKit
import UIKit
import AVFoundation
import QuartzCore
import os

// MARK: - Gaze Control Calibration

// Small upward offset to compensate for eye-to-cursor alignment in Flat Display
// Positive value moves cursor UP (compensates for cursor appearing too low)
let FLAT_GAZE_VERTICAL_OFFSET: CGFloat = 0.02  // 2% upward adjustment

// MARK: - Thread-Safe HDR Settings

final class FlatThreadSafeHDRSettings: @unchecked Sendable {
    private var params: HDRParams
    private let lock = NSLock()
    init(params: HDRParams) { self.params = params }
    var value: HDRParams {
        get { lock.lock(); defer { lock.unlock() }; return params }
        set { lock.lock(); defer { lock.unlock() }; params = newValue }
    }
}

// MARK: - Frame Mailbox (Thread-Safe Handoff) - Flat Display Version
// Uses OSAllocatedUnfairLock for nanosecond-level access - critical for 120Hz M5 support.
final class FlatFrameMailbox: @unchecked Sendable {
    // OSAllocatedUnfairLock spins briefly instead of sleeping the thread.
    // This prevents missed V-Sync deadlines at 120Hz (8.3ms budget).
    // The lock protects the optional DrawableQueue state directly.
    private let lock = OSAllocatedUnfairLock<TextureResource.DrawableQueue?>(initialState: nil)
    
    func deposit(_ drawable: TextureResource.DrawableQueue) {
        lock.withLock { $0 = drawable }
    }
    
    func collect() -> TextureResource.DrawableQueue? {
        lock.withLock {
            let d = $0
            $0 = nil
            return d
        }
    }
}

// MARK: - Input Capture View

struct FlatInputCaptureView: UIViewRepresentable {
    let controllerSupport: ControllerSupport
    @Binding var showKeyboard: Bool
    var streamConfig: StreamConfiguration
    var absoluteTouchMode: Bool
    var hideSystemCursor: Bool
    var reclaimFocusTrigger: Int
    var isHandGazeInputDisabled: Bool
    var onReturnPressed: (() -> Void)?
    
    func makeUIView(context: Context) -> FlatInputCaptureUIView {
        let view = FlatInputCaptureUIView()
        view.controllerSupport = controllerSupport
        view.streamConfig = streamConfig
        view.absoluteTouchMode = absoluteTouchMode
        view.showVirtualKeyboard = showKeyboard
        view.hideSystemCursor = hideSystemCursor
        view.isHandGazeInputDisabled = isHandGazeInputDisabled
        view.onReturnPressed = onReturnPressed
        view.isMultipleTouchEnabled = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        
        // Become first responder immediately to capture keyboard input
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: FlatInputCaptureUIView, context: Context) {
        uiView.streamConfig = streamConfig
        uiView.absoluteTouchMode = absoluteTouchMode
        uiView.hideSystemCursor = hideSystemCursor
        uiView.isHandGazeInputDisabled = isHandGazeInputDisabled
        uiView.onReturnPressed = onReturnPressed

        if uiView.showVirtualKeyboard != showKeyboard {
            uiView.showVirtualKeyboard = showKeyboard
        }

        // Only reclaim first responder when explicitly triggered (e.g., scenePhase became .active)
        // This prevents stealing keyboard focus from other visionOS apps
        if uiView.lastReclaimTrigger != reclaimFocusTrigger {
            uiView.lastReclaimTrigger = reclaimFocusTrigger
            if !uiView.isFirstResponder {
                _ = uiView.becomeFirstResponder()
            }
        }
    }
}

class FlatInputCaptureUIView: UIView, UIKeyInput, UIPointerInteractionDelegate {
    var controllerSupport: ControllerSupport?
    var streamConfig: StreamConfiguration?
    var absoluteTouchMode: Bool = true
    var isHandGazeInputDisabled: Bool = false
    var lastReclaimTrigger: Int = 0
    var onReturnPressed: (() -> Void)?
    var showVirtualKeyboard: Bool = false {
        didSet {
            if oldValue != showVirtualKeyboard {
                reloadInputViews()
            }
        }
    }
    
    var hideSystemCursor: Bool = false {
        didSet {
            if oldValue != hideSystemCursor {
                // Remove and re-add interaction to force immediate style update
                if let interaction = self.interactions.first(where: { $0 is UIPointerInteraction }) {
                    self.removeInteraction(interaction)
                    self.addInteraction(interaction)
                }
            }
        }
    }
    
    // Suppress software keyboard if showVirtualKeyboard is false, but still allow hardware input
    override var inputView: UIView? {
        return showVirtualKeyboard ? nil : UIView()
    }
    
    // Touch state for Absolute Touch (Touchscreen) Mode
    private var longPressTimer: Timer?
    private var lastTouchDownLocation: CGPoint = .zero
    private var lastTouchUpLocation: CGPoint = .zero
    private var lastTouchUpTimestamp: TimeInterval = 0
    
    // Touch state for Relative Touch (Trackpad) Mode
    private var lastTouchPosition: CGPoint? = nil
    private var touchStartPosition: CGPoint? = nil
    private var touchStartTime: TimeInterval = 0
    private var hasMovedInTouch = false
    private var touchClickTimer: Timer? = nil
    private var touchModeInitialized = false
    private let touchTapThreshold: CGFloat = 0.01  // 1% movement = drag, not tap
    private let touchTapTimeThreshold: TimeInterval = 0.2  // 200ms = quick tap
    
    // Internal cursor tracking for relative movement
    private var currentMouseX: Int16 = 0
    private var currentMouseY: Int16 = 0
    
    // Button action constants - MUST match Limelight.h exactly!
    private let BUTTON_ACTION_PRESS: Int8 = 0x07
    private let BUTTON_ACTION_RELEASE: Int8 = 0x08
    private let BUTTON_LEFT: Int32 = 0x01
    private let BUTTON_RIGHT: Int32 = 0x03
    
    // Constants from AbsoluteTouchHandler - matching UIKit exactly
    private let longPressActivationDelay: TimeInterval = 0.650
    private let longPressActivationDelta: CGFloat = 0.01  // 1% of screen (normalized)
    private let doubleTapDeadZoneDelay: TimeInterval = 0.250  // 250ms
    private let doubleTapDeadZoneDelta: CGFloat = 0.025  // 2.5% of screen (normalized)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
        setupPointerInteraction()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
        setupPointerInteraction()
    }
    
    private func setupGestures() {
        // We rely on standard touchesBegan/Moved/Ended for "Look and Pinch".
        DispatchQueue.main.async {
            self.controllerSupport?.attachGCEventInteraction(to: self)
        }
    }
    
    private func setupPointerInteraction() {
        let interaction = UIPointerInteraction(delegate: self)
        self.addInteraction(interaction)
    }
    
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        if hideSystemCursor {
            return UIPointerStyle.hidden()
        }
        return nil
    }
    
    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        // This is called when the pointer moves - send the mouse position
        let location = request.location
        print("[MOUSE DEBUG] Pointer moved to: (\(location.x), \(location.y))")
        sendMousePosition(x: location.x, y: location.y)
        return defaultRegion
    }
    
    // CRITICAL: Override hitTest to allow touches to pass through to ornaments
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled else { return nil }
        
        // No exclusion needed - ornaments are in a separate layer above
        if bounds.contains(point) {
            return self
        }
        
        return nil
    }
    
    @objc private func onLongPressStart() {
        // Convert Left Click/Hold into Right Click
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT)
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Reclaim first responder on touch if lost (e.g., after switching to another app)
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }
        
        // Ignore when hand/gaze input is disabled
        guard !isHandGazeInputDisabled else { return }
        
        // Ignore touch down events with more than one finger
        guard let allTouches = event?.allTouches, allTouches.count == 1 else {
            return
        }
        
        guard let touch = touches.first else { return }
        let touchLocation = touch.location(in: self)
        
        if absoluteTouchMode {
            // GAZE CONTROL MODE: Absolute positioning (eye tracking + pinch)
            // Calculate normalized coordinates for deadzone comparison
            let normalizedX = touchLocation.x / bounds.width
            let normalizedY = touchLocation.y / bounds.height
            let lastNormalizedX = lastTouchUpLocation.x / bounds.width
            let lastNormalizedY = lastTouchUpLocation.y / bounds.height
            
            let dx = normalizedX - lastNormalizedX
            let dy = normalizedY - lastNormalizedY
            let distance = sqrt(dx * dx + dy * dy)
            
            let timeDelta = touch.timestamp - lastTouchUpTimestamp
            
            // Don't reposition for finger down events within the deadzone
            if timeDelta > doubleTapDeadZoneDelay || distance > doubleTapDeadZoneDelta {
                sendMousePosition(x: touchLocation.x, y: touchLocation.y)
            }
            
            // Press the left button down
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT)
            
            // Start the long press timer
            longPressTimer?.invalidate()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressActivationDelay, repeats: false) { [weak self] _ in
                self?.onLongPressStart()
            }
            
            lastTouchDownLocation = touchLocation
        } else {
            // TOUCH CONTROL MODE: Relative movement (trackpad style)
            lastTouchPosition = touchLocation
            touchStartPosition = touchLocation
            touchStartTime = touch.timestamp
            hasMovedInTouch = false
            
            // On first touch in Touch mode, center the cursor
            if !touchModeInitialized {
                centerCursor()
                touchModeInitialized = true
            }
            
            // DON'T press any button yet - wait to see if it's a tap or drag
            touchClickTimer?.invalidate()
            touchClickTimer = Timer.scheduledTimer(withTimeInterval: touchTapTimeThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                // If still holding after 200ms and haven't moved much, it's a click-drag
                if !self.hasMovedInTouch {
                    LiSendMouseButtonEvent(self.BUTTON_ACTION_PRESS, self.BUTTON_LEFT)
                }
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Ignore when hand/gaze input is disabled
        guard !isHandGazeInputDisabled else { return }
        
        // Ignore touch move events with more than one finger
        guard let allTouches = event?.allTouches, allTouches.count == 1 else {
            return
        }
        
        guard let touch = touches.first else { return }
        let touchLocation = touch.location(in: self)
        
        if absoluteTouchMode {
            // GAZE CONTROL MODE: Absolute positioning
            // Check if moved far enough to cancel long press
            let normalizedX = touchLocation.x / bounds.width
            let normalizedY = touchLocation.y / bounds.height
            let lastNormalizedX = lastTouchDownLocation.x / bounds.width
            let lastNormalizedY = lastTouchDownLocation.y / bounds.height
            
            let dx = normalizedX - lastNormalizedX
            let dy = normalizedY - lastNormalizedY
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance > longPressActivationDelta {
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
            
            // CRITICAL: Always update cursor position in touchesMoved for Absolute Mode
            sendMousePosition(x: touchLocation.x, y: touchLocation.y)
        } else {
            // TOUCH CONTROL MODE: Relative movement (trackpad style)
            guard let lastPos = lastTouchPosition,
                  let startPos = touchStartPosition else { return }
            
            // Calculate delta
            let deltaX = touchLocation.x - lastPos.x
            let deltaY = touchLocation.y - lastPos.y
            
            // Check if we've moved significantly from start
            let totalDX = touchLocation.x - startPos.x
            let totalDY = touchLocation.y - startPos.y
            let totalDist = sqrt(totalDX * totalDX + totalDY * totalDY)
            let normalizedDist = totalDist / bounds.width
            
            if normalizedDist > touchTapThreshold {
                hasMovedInTouch = true
                // Cancel the click timer - this is a drag, not a tap
                touchClickTimer?.invalidate()
                touchClickTimer = nil
            }
            
            // Send relative mouse movement
            sendRelativeMouseMovement(dx: deltaX, dy: deltaY)
            
            lastTouchPosition = touchLocation
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Ignore when hand/gaze input is disabled
        guard !isHandGazeInputDisabled else { return }
        
        guard let allTouches = event?.allTouches, allTouches.count == touches.count else {
            return
        }
        
        if absoluteTouchMode {
            // GAZE CONTROL MODE: Release buttons
            longPressTimer?.invalidate()
            longPressTimer = nil
            
            // Left button up
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT)
            
            // Raise right button too in case we triggered a long press gesture
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT)
            
            if let touch = touches.first {
                lastTouchUpLocation = touch.location(in: self)
                lastTouchUpTimestamp = touch.timestamp
            }
        } else {
            // TOUCH CONTROL MODE: Handle tap vs drag
            guard let touch = touches.first else { return }
            let holdDuration = touch.timestamp - touchStartTime
            
            // Cancel timers
            touchClickTimer?.invalidate()
            touchClickTimer = nil
            longPressTimer?.invalidate()
            longPressTimer = nil
            
            // Determine what kind of gesture this was
            if !hasMovedInTouch && holdDuration < touchTapTimeThreshold {
                // Quick tap without movement = CLICK
                LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT)
                // Release after a tiny delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self else { return }
                    LiSendMouseButtonEvent(self.BUTTON_ACTION_RELEASE, self.BUTTON_LEFT)
                }
            } else if !hasMovedInTouch && holdDuration >= touchTapTimeThreshold {
                // Held still for a while = click was already sent by timer, now release
                LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT)
            } else {
                // Movement happened = just cursor movement, no click needed
                // (unless click timer fired for click-drag, in which case release it)
                if holdDuration >= touchTapTimeThreshold {
                    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT)
                }
            }
            
            lastTouchPosition = nil
            touchStartPosition = nil
            hasMovedInTouch = false
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    // Get the actual video area size (aspect-fitted within the view)
    private func getVideoAreaSize() -> CGSize {
        guard let config = streamConfig else { return bounds.size }
        
        let streamAspectRatio = CGFloat(config.width) / CGFloat(config.height)
        
        if bounds.size.width > bounds.size.height * streamAspectRatio {
            // View is wider than needed (pillarboxing)
            return CGSize(width: bounds.size.height * streamAspectRatio, height: bounds.size.height)
        } else {
            // View is taller than needed (letterboxing)
            return CGSize(width: bounds.size.width, height: bounds.size.width / streamAspectRatio)
        }
    }
    
    // Adjust coordinates to be relative to the centered video area
    private func adjustCoordinatesForVideoArea(_ point: CGPoint) -> CGPoint {
        let x = point.x - bounds.origin.x
        let y = point.y - bounds.origin.y
        
        // Calculate centered video area
        let videoSize = getVideoAreaSize()
        let videoOrigin = CGPoint(
            x: bounds.size.width / 2 - videoSize.width / 2,
            y: bounds.size.height / 2 - videoSize.height / 2
        )
        
        // Clamp to video region and return relative to video origin
        let clampedX = min(max(x, videoOrigin.x), videoOrigin.x + videoSize.width) - videoOrigin.x
        let clampedY = min(max(y, videoOrigin.y), videoOrigin.y + videoSize.height) - videoOrigin.y
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    private func sendRelativeMouseMovement(dx: CGFloat, dy: CGFloat) {
        guard let config = streamConfig else { return }
        
        // Scale factor for sensitivity (adjust as needed)
        let sensitivity: CGFloat = 2.5
        let scaledDX = dx * sensitivity
        let scaledDY = dy * sensitivity
        
        // Update internal cursor position
        currentMouseX = Int16(max(0, min(CGFloat(config.width), CGFloat(currentMouseX) + scaledDX)))
        currentMouseY = Int16(max(0, min(CGFloat(config.height), CGFloat(currentMouseY) + scaledDY)))
        
        LiSendMousePositionEvent(currentMouseX, currentMouseY, Int16(config.width), Int16(config.height))
    }
    
    private func centerCursor() {
        guard let config = streamConfig else { return }
        
        // Calculate exact center pixels
        let centerX = Int16(config.width / 2)
        let centerY = Int16(config.height / 2)
        
        // Update internal tracking
        currentMouseX = centerX
        currentMouseY = centerY
        
        print("[Touch Mode] Centering cursor: \(centerX), \(centerY)")
        LiSendMousePositionEvent(centerX, centerY, Int16(config.width), Int16(config.height))
    }
    
    private func sendMousePosition(x: CGFloat, y: CGFloat) {
        guard let config = streamConfig else { return }
        
        // DEBUG: Print actual bounds and stream config
        print("[MOUSE DEBUG] Input: (\(x), \(y)) | Bounds: \(bounds.size) | Stream: \(config.width)x\(config.height)")
        
        // Adjust coordinates to video area (handles letterboxing/pillarboxing)
        let adjustedPoint = adjustCoordinatesForVideoArea(CGPoint(x: x, y: y))
        
        // Now map from video area coordinates to stream pixel coordinates
        let videoSize = getVideoAreaSize()
        print("[MOUSE DEBUG] VideoSize: \(videoSize) | Adjusted: (\(adjustedPoint.x), \(adjustedPoint.y))")
        
        let normX = adjustedPoint.x / videoSize.width
        // Apply vertical offset to compensate for eye-to-cursor alignment
        // Subtracting moves cursor UP (since Y increases downward)
        let normY = (adjustedPoint.y / videoSize.height) - FLAT_GAZE_VERTICAL_OFFSET
        
        let streamX = normX * CGFloat(config.width)
        let streamY = normY * CGFloat(config.height)
        
        let clampedX = Int16(min(max(streamX, 0), CGFloat(config.width - 1)))
        let clampedY = Int16(min(max(streamY, 0), CGFloat(config.height - 1)))
        
        print("[MOUSE DEBUG] Stream coords: (\(clampedX), \(clampedY))")
        
        LiSendMousePositionEvent(clampedX, clampedY, Int16(config.width), Int16(config.height))
    }
    
    override var canBecomeFocused: Bool { true }
    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }
    
    func insertText(_ text: String) {
        // Handle Return/Enter key specially - it comes as "\n" or "\r"
        if text == "\n" || text == "\r" {
            print("[Keyboard] Return key pressed")
            // Send Enter key: keycode 0x0D (13), scancode for Enter
            LiSendKeyboardEvent(0x0D, 0x03, 0)  // Key Down
            usleep(50 * 1000)
            LiSendKeyboardEvent(0x0D, 0x04, 0)  // Key Up
            
            // Notify parent view to close keyboard
            DispatchQueue.main.async { [weak self] in
                self?.onReturnPressed?()
            }
            return
        }
        
        // For all other characters, send as UTF-8 text
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

// MARK: - Main View

struct FlatDisplayStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow
    
    @Binding var streamConfig: StreamConfiguration?
    var needsHdr: Bool
    
    var body: some View {
        if let config = streamConfig {
            // SESSION TOKEN GUARD: If this view's sessionUUID doesn't match the
            // ViewModel's activeSessionToken, this is a "ghost" view from a dying
            // window. Render black and skip all logic to prevent resource collision.
            if config.sessionUUID == viewModel.activeSessionToken {
                _FlatDisplayStreamView(
                    streamConfig: Binding<StreamConfiguration>(
                        get: { config },
                        set: { streamConfig = $0 }
                    ),
                    needsHdr: needsHdr
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
                print("[FlatDisplay] Stale window detected - dismissing and opening mainView")
                openWindow(id: "mainView")
                dismissWindow(id: "flatDisplayWindow")
            }
        }
    }
}

struct _FlatDisplayStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow
    
    @Binding var streamConfig: StreamConfiguration
    var needsHdr: Bool
    
    @State private var streamMan: StreamManager?
    @State private var controllerSupport: ControllerSupport?
    @State private var isHandGazeInputDisabled = false // Long press on control mode button to disable hand/gaze input
    @ObservedObject var connectionCallbacks: ObservableConnectionManager = .init()
    @ObservedObject private var coopCoordinator = CoopSessionCoordinator.shared
    
    @State private var texture: TextureResource
    @State private var screen: ModelEntity = ModelEntity()
    @State private var surfaceMaterial: ShaderGraphMaterial?
    
    // Frame Mailbox for stutter-free, dizziness-free video display
    private let frameMailbox = FlatFrameMailbox()
    
    @State private var lastUpdateSize: CGSize = .zero
    @State private var lastPhysicalWidth: Float = 0
    @AppStorage("removeRoundedCorners") private var removeRoundedCorners: Bool = false
    @AppStorage("darkControlsMode") private var darkControlsMode: Bool = false
    
    @State private var safeHDRSettings = FlatThreadSafeHDRSettings(
        params: HDRParams(boost: 1.0, contrast: 1.0, saturation: 1.0, brightness: 0.0, mode: 0)
    )
    @StateObject private var hdrParams = HDRTestParams()
    
    @State private var showVirtualKeyboard = false
    @State private var keyboardInput: String = " "
    @FocusState private var isKeyboardFocused: Bool
    @State private var hideControls: Bool = true
    @State private var controlsExpanded: Bool = false
    @State private var hideTimer: Timer?
    @State private var hasPerformedTeardown = false
    @State private var windowDecommissioned = false
    @State private var spatialAudioMode: Bool = true
    @State private var soundStageSize: SoundStageSize = .medium
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?
    @State private var controlsHighlighted: Bool = false
    @State private var isMenuOpen = false
    @State private var renderGateOpen: Bool = true
    @State private var dimLevel: Int = 0
    @State private var correctedResolution: (Int, Int)? = nil
    @State private var correctedResolutionVersion: Int = 0
    @State private var needsResume = false
    @State private var videoMode: VideoMode = .standard2D
    @State private var show3DConfirm = false
    
    @State private var showInlinePresetOverlay: Bool = false
    @State private var presetOverlayText: String = ""
    @State private var presetOverlayIcon: String = "camera.filters"
    @State private var presetOverlayTimer: Timer?
    @State private var presetCooldownUntil: Date? = nil
    
    // Co-op invite button state
    @State private var inviteButtonSent: Bool = false
    @State private var showDisconnectConfirm: Bool = false
    
    @State private var hostingWindow: UIWindow?
    
    @State private var isHDRTexture: Bool = false
    
    @State private var streamEpoch: Int = 0
    @State private var startingStream: Bool = false
    @State private var firstFrameSeenEpoch: Int = -1
    @State private var watchdogIDR1: DispatchWorkItem?
    @State private var watchdogIDR2: DispatchWorkItem?
    @State private var guestAggressiveIDRTimer: Timer?
    @State private var reclaimKeyboardFocus: Int = 0
    
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    
    /// Detects if the stream is a typical SBS 3D format (32:9 aspect ratio)
    var isSBSVideo: Bool {
        let ratio = Float(streamConfig.width) / Float(streamConfig.height)
        return abs(ratio - (32.0 / 9.0)) < 0.01
    }
    
    var screenAspect: Float {
        if let (w, h) = correctedResolution {
            // When SBS 3D mode is enabled and video is 32:9, use half-width for correct aspect
            if videoMode == .sideBySide3D, abs(Float(w) / Float(h) - (32.0 / 9.0)) < 0.01 {
                return Float(h) / Float(w / 2)
            } else {
                return Float(h) / Float(w)
            }
        } else {
            // When SBS 3D mode is enabled and video is 32:9, use half-width for correct aspect
            if videoMode == .sideBySide3D && isSBSVideo {
                return Float(streamConfig.height) / Float(streamConfig.width / 2)
            } else {
                return Float(streamConfig.height) / Float(streamConfig.width)
            }
        }
    }
    
    var cornerRadiusFraction: Float { removeRoundedCorners ? 0.0 : 0.012 }
    
    init(streamConfig: Binding<StreamConfiguration>, needsHdr: Bool) {
        self._streamConfig = streamConfig
        self.needsHdr = needsHdr
        
        // DEBUG: Log view creation with sessionUUID to verify fresh instance
        debugLog("🟢 INIT - sessionUUID: \(streamConfig.wrappedValue.sessionUUID)")
        
        let width = Int(streamConfig.wrappedValue.width)
        let height = Int(streamConfig.wrappedValue.height)
        let bytesPerPixel = needsHdr ? 8 : 4
        let data = Data(count: bytesPerPixel * width * height)
        
        // Safe texture creation with fallback
        let initialTexture: TextureResource
        do {
            initialTexture = try TextureResource(
                dimensions: .dimensions(width: width, height: height),
                format: .raw(pixelFormat: needsHdr ? .rgba16Float : .bgra8Unorm_srgb),
                contents: .init(mipmapLevels: [.mip(data: data, bytesPerRow: bytesPerPixel * width)])
            )
        } catch {
            print("⚠️ Failed to create initial texture: \(error). Using fallback.")
            let fallbackData = Data(count: 4)
            initialTexture = try! TextureResource(
                dimensions: .dimensions(width: 1, height: 1),
                format: .raw(pixelFormat: .bgra8Unorm_srgb),
                contents: .init(mipmapLevels: [.mip(data: fallbackData, bytesPerRow: 4)])
            )
        }
        _texture = State(initialValue: initialTexture)
        
        _isHDRTexture = State(initialValue: needsHdr)
    }
    
    // Calculate aspect-fit size for the video within a container
    private func calculateVideoSize(containerSize: CGSize) -> CGSize {
        let streamAspect = CGFloat(streamConfig.width) / CGFloat(streamConfig.height)
        let containerAspect = containerSize.width / containerSize.height
        
        if containerAspect > streamAspect {
            // Container wider - pillarbox
            let height = containerSize.height
            let width = height * streamAspect
            return CGSize(width: width, height: height)
        } else {
            // Container taller - letterbox
            let width = containerSize.width
            let height = width / streamAspect
            return CGSize(width: width, height: height)
        }
    }
    
    var body: some View {
        let mainContent = ZStack {
            GeometryReader { proxy in
                let fitSize = calculateVideoSize(containerSize: proxy.size)
                
                ZStack {
                    RealityView { content, attachments in
                        setupRealityView(content: content, attachments: attachments)
                        
                        // --- THE HEARTBEAT FIX ---
                        // This forces RealityKit to check the mailbox at display refresh rate.
                        _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                            if let newFrame = frameMailbox.collect() {
                                texture.replace(withDrawables: newFrame)
                            }
                        }
                        
                    } update: { content, attachments in
                        updateRealityView(content: content, attachments: attachments, size: fitSize)
                    } attachments: {
                        // THE INVISIBLE RULER - 100 points wide for calibration
                        Attachment(id: "calibrationRuler") {
                            Color.clear.frame(width: 100, height: 100)
                        }
                        
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
                        
                        Attachment(id: "sbsConfirm") {
                            if show3DConfirm || showDisconnectConfirm {
                                confirmationsOverlay
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                            } else {
                                Color.clear.frame(width: 1, height: 1)
                            }
                        }
                    }
                    .frame(width: fitSize.width, height: fitSize.height)
                    
                    if let support = controllerSupport {
                        FlatInputCaptureView(
                            controllerSupport: support,
                            showKeyboard: $showVirtualKeyboard,
                            streamConfig: streamConfig,
                            absoluteTouchMode: viewModel.streamSettings.absoluteTouchMode,
                            hideSystemCursor: true,  // Always hide - PC renders its own cursor
                            reclaimFocusTrigger: reclaimKeyboardFocus,
                            isHandGazeInputDisabled: isHandGazeInputDisabled
                        )
                        .frame(width: fitSize.width, height: fitSize.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(viewModel.activelyStreaming)
                    }
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            
            WindowResolver { win in
                if hostingWindow !== win {
                    hostingWindow = win
                }
            }
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
            
            // Hidden TextField to trigger keyboard via @FocusState
            TextField("", text: $keyboardInput)
                .focused($isKeyboardFocused)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .onSubmit {
                    // When user hits return, send the Return key to the stream
                    print("[Keyboard] Submit detected, sending Return key")
                    let returnKey = "\n"
                    let cString = returnKey.cString(using: .utf8)
                    cString?.withUnsafeBufferPointer { ptr in
                        if let base = ptr.baseAddress {
                            LiSendUtf8TextEvent(base, UInt32(returnKey.utf8.count))
                        }
                    }
                    
                    // Then close the keyboard and clear text
                    showVirtualKeyboard = false
                    isKeyboardFocused = false
                    keyboardInput = ""
                }
        }
        .onTapGesture {
            // Only handle tap if NOT in touchscreen mode
            guard !viewModel.streamSettings.absoluteTouchMode else { return }
            guard viewModel.activelyStreaming else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                hideControls = false
                controlsHighlighted = true
            }
            startHighlightTimer()
            fixAudioForCurrentMode()
        }
        .preferredSurroundingsEffect(dimLevel == 1 ? .systemDark : nil)
        .persistentSystemOverlays(hideControls ? .hidden : .visible)
        
        let withOrnaments: AnyView = AnyView(
            mainContent
                .ornament(attachmentAnchor: OrnamentAttachmentAnchor.scene(.top), contentAlignment: Alignment.bottom) {
                    topControlsBar
                        .padding(.bottom, 8)
                }
                .ornament(attachmentAnchor: OrnamentAttachmentAnchor.scene(.bottom), contentAlignment: Alignment.top) {
                    VStack(spacing: 12) {
                        if viewModel.streamSettings.showMicButton {
                            FloatingMicButton()
                                .padding(.top, -12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        if viewModel.streamSettings.statsOverlay {
                            statsOverlayView
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
        )
        
        let withLifecycle: AnyView = AnyView(
            withOrnaments
                .task { await setupMaterial() }
                .onAppear(perform: setupScene)
                .onDisappear(perform: teardownScene)
                .onTapGesture {
                    // Only handle tap if NOT in touchscreen mode
                    guard !viewModel.streamSettings.absoluteTouchMode else { return }
                    guard viewModel.activelyStreaming else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideControls = false
                        controlsHighlighted = true
                    }
                    startHighlightTimer()
                    fixAudioForCurrentMode()
                }
        )
        
        return withLifecycle
            .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
                if shouldClose && !hasPerformedTeardown {
                    DispatchQueue.main.async { triggerCloseSequence() }
                }
            }
            .onChange(of: scenePhase) { oldValue, newValue in
                if newValue == .background {
                    if !isMenuOpen && viewModel.activelyStreaming, streamMan != nil {
                        print("Suspending stream due to background (Menu is not open)")
                        needsResume = true
                        startingStream = false
                        viewModel.isSuspendingForBackground = true
                        streamMan?.stopStream()
                        streamMan = nil
                        controllerSupport?.cleanup()
                        controllerSupport = nil
                    }
                } else if newValue == .active {
                    // Trigger keyboard focus reclaim whenever window becomes active
                    reclaimKeyboardFocus += 1
                    
                    if needsResume {
                        print("Resuming stream from background")
                        viewModel.isSuspendingForBackground = false
                        needsResume = false
                        self.renderGateOpen = true
                        self.hasPerformedTeardown = false
                        self.startingStream = false
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
                            print("[FlatDisplay] Stream died while inactive - restarting")
                            self.renderGateOpen = true
                            self.hasPerformedTeardown = false
                            self.startingStream = false
                            controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
                            connectionCallbacks.controllerSupport = controllerSupport
                            startStreamIfNeeded()
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                           fixAudioForCurrentMode()
                       }
                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                           self.refreshAfterResume()
                       }
                    }
                }
            }
            .onChange(of: viewModel.streamSettings.statsOverlay) { _, newValue in
                if newValue { startStatsTimer() } else { statsTimer?.invalidate(); statsTimer = nil; statsOverlayText = "" }
            }
            .onChange(of: viewModel.activelyStreaming) { _, newValue in
                guard !windowDecommissioned else { return }  // Zombie window — ignore
                if newValue {
                    // FIX: Defer state modification to prevent "Modifying state during view update" warnings
                    DispatchQueue.main.async {
                        self.renderGateOpen = true
                    }
                    ensureStreamStartedIfNeeded()
                    dismissWindow(id: "mainView")
                }
            }
            .onChange(of: hostingWindow) { _, _ in
                applyWindowAspectRatioLock()
            }
            .onChange(of: correctedResolutionVersion) { _, _ in
                applyWindowAspectRatioLock()
            }
            .onChange(of: videoMode) { _, _ in
                applyWindowAspectRatioLock()
                updateScreenMaterial()
            }
            .onChange(of: viewModel.streamSettings.swapABXYButtons) { _, newValue in
                controllerSupport?.setSwapABXYButtons(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .resumeStreamFromMenu)) { _ in
                handleResume()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mainViewWindowClosed)) { _ in
                isMenuOpen = false
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RKStreamFirstFrameShown"))) { _ in
                if firstFrameSeenEpoch != streamEpoch {
                    print("[FlatDisplay] First frame (RK) observed; epoch=\(streamEpoch)")
                    firstFrameSeenEpoch = streamEpoch
                    self.renderGateOpen = true
                    rebindScreenMaterial()
                    cancelFirstFrameWatchdogs()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StreamFirstFrameShownNotification"))) { _ in
                if firstFrameSeenEpoch != streamEpoch {
                    print("[FlatDisplay] First frame (UIKit) observed; epoch=\(streamEpoch)")
                    firstFrameSeenEpoch = streamEpoch
                    self.renderGateOpen = true
                    rebindScreenMaterial()
                    cancelFirstFrameWatchdogs()
                }
            }
    }
    
    // MARK: - Controls
    
    /// Center button: tap to expand the dynamic menu.
    private var flatCollapsedControlsView: some View {
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
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 24.07))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var topControlsBar: some View {
        Group {
            if viewModel.streamSettings.useCollapsedControlsMenu {
                flatDynamicControlsBar
                    .opacity(!hideControls ? (controlsHighlighted ? 1.0 : (darkControlsMode ? 0.12 : 0.5)) : (darkControlsMode ? 0.01 : 0.05))
                    .animation(Animation.easeInOut(duration: 0.25), value: controlsHighlighted)
                    .animation(Animation.easeInOut(duration: 0.25), value: hideControls)
                    .allowsHitTesting(true)
            } else {
                flatOriginalControlsBar
            }
        }
    }
    
    private var flatOriginalControlsBar: some View {
        flatControlsBarContent
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
        .opacity(!hideControls ? (controlsHighlighted ? 1.0 : (darkControlsMode ? 0.12 : 0.5)) : (darkControlsMode ? 0.01 : 0.05))
        .animation(Animation.easeInOut(duration: 0.25), value: controlsHighlighted)
        .animation(Animation.easeInOut(duration: 0.25), value: hideControls)
        .allowsHitTesting(true)
    }
    
    /// Original bar content (no accordion); used when dynamic menu is off.
    private var flatControlsBarContent: some View {
        HStack(spacing: 20) {
            makeControlButton(label: "Home", systemImage: "house.fill") {
                if isMenuOpen {
                    dismissWindow(id: "mainView")
                    isMenuOpen = false
                } else {
                    pushWindow(id: "mainView")
                    isMenuOpen = true
                }
                fixAudioForCurrentMode()
            }
            Button {
                if !controlsHighlighted && hideControls {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideControls = false
                        controlsHighlighted = true
                    }
                    startHighlightTimer()
                    return
                }
                controlsHighlighted = false
                hideControls = false
                spatialAudioMode.toggle()
                fixAudioForCurrentMode()
                presetOverlayText = spatialAudioMode ? "Audio: Spatial" : "Audio: Stereo"
                presetOverlayIcon = spatialAudioMode ? "person.spatialaudio.fill" : "headphones"
                showInlinePresetOverlay = true
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                }
                startHideTimer()
            } label: {
                Label(spatialAudioMode ? "Spatial Audio" : "Direct Audio", systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                    .font(.system(size: 24.07))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(width: 50, height: 50)
            }
            .labelStyle(.iconOnly)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
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
            })
            makeControlButton(label: "Dim", systemImage: dimLevel == 0 ? "lightbulb.fill" : "lightbulb") {
                dimLevel = dimLevel == 0 ? 1 : 0
                UserDefaults.standard.set(dimLevel, forKey: "ambient.dimming.level")
                viewModel.streamSettings.dimPassthrough = (dimLevel != 0)
                presetOverlayText = dimLevel == 0 ? "Dimming: Off" : "Dimming: On"
                presetOverlayIcon = dimLevel == 0 ? "lightbulb.fill" : "lightbulb"
                showInlinePresetOverlay = true
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                }
            }
            makeControlButton(label: "Preset", systemImage: "camera.filters") {
                guard canChangePreset() else { return }
                let next = (viewModel.streamSettings.uikitPreset + 1) % 4
                viewModel.streamSettings.uikitPreset = next
                applyCurvedUIKitPreset(next)
                presetCooldownUntil = Date().addingTimeInterval(0.3)
                presetOverlayText = presetName(for: next)
                presetOverlayIcon = "camera.filters"
                showInlinePresetOverlay = true
                presetOverlayTimer?.invalidate()
                presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                }
                startHideTimer()
            }
            makeControlButton(label: videoMode == .standard2D ? "Standard" : "3D", systemImage: "view.3d") {
                if videoMode == .standard2D { show3DConfirm = true }
                else {
                    videoMode = .standard2D
                    applyWindowAspectRatioLock()
                    presetOverlayText = "Standard Display"
                    presetOverlayIcon = "view.3d"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                    }
                }
                startHideTimer()
            }
            makeControlButton(label: viewModel.streamSettings.statsOverlay ? "Hide Stats" : "Show Stats", systemImage: "wifi") {
                viewModel.streamSettings.statsOverlay.toggle()
                if viewModel.streamSettings.statsOverlay {
                    startStatsTimer()
                } else {
                    statsTimer?.invalidate()
                }
                startHideTimer()
            }
            if viewModel.streamSettings.showTaskManagerButton {
                makeControlButton(label: "Task Manager", systemImage: "list.bullet.circle") {
                    sendTaskManager()
                    startHideTimer()
                }
            }
            makeControlButton(label: showVirtualKeyboard ? "Hide Keyboard" : "Show Keyboard", systemImage: showVirtualKeyboard ? "keyboard.fill" : "keyboard") {
                showVirtualKeyboard.toggle()
                isKeyboardFocused = showVirtualKeyboard
                startHideTimer()
            }
            if viewModel.streamSettings.showControllerBattery {
                BatteryIndicatorView(
                    controlsHighlighted: $controlsHighlighted,
                    hideControls: $hideControls,
                    startHighlightTimer: startHighlightTimer,
                    startHideTimer: startHideTimer
                )
            }
            LongPressControlBtn(
                label: viewModel.streamSettings.absoluteTouchMode ? "Gaze Control" : "Touch Control",
                systemImage: isHandGazeInputDisabled ? "lock.fill" : (viewModel.streamSettings.absoluteTouchMode ? "eye.fill" : "hand.point.up.left.fill"),
                controlsHighlighted: $controlsHighlighted,
                hideControls: $hideControls,
                startHighlightTimer: startHighlightTimer,
                startHideTimer: startHideTimer,
                primaryAction: {
                    viewModel.streamSettings.absoluteTouchMode.toggle()
                    UserDefaults.standard.set(viewModel.streamSettings.absoluteTouchMode, forKey: "flat.absoluteTouchMode")
                    presetOverlayText = viewModel.streamSettings.absoluteTouchMode ? "Gaze Control" : "Touch Control"
                    presetOverlayIcon = viewModel.streamSettings.absoluteTouchMode ? "eye.fill" : "hand.point.up.left.fill"
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                    }
                },
                longPressAction: {
                    isHandGazeInputDisabled.toggle()
                    presetOverlayText = isHandGazeInputDisabled ? "Screen Input Disabled" : "Screen Input Enabled"
                    presetOverlayIcon = isHandGazeInputDisabled ? "lock.fill" : (viewModel.streamSettings.absoluteTouchMode ? "eye.fill" : "hand.point.up.left.fill")
                    showInlinePresetOverlay = true
                    presetOverlayTimer?.invalidate()
                    presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.15)) { showInlinePresetOverlay = false }
                    }
                }
            )
            if viewModel.isCoopSession {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill").font(.system(size: 16, weight: .semibold))
                    Text("2P").font(.system(size: 14, weight: .bold))
                    Text("(\(CoopSessionCoordinator.shared.participants.count)/2)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .fixedSize()
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.3)))
            }
            if viewModel.isCoopSession {
                let coordinator = CoopSessionCoordinator.shared
                if coordinator.isHosting && coordinator.participants.count < 2 {
                    coopInviteButton
                }
            }
            if viewModel.isCoopSession {
                coopDisconnectButton
            }
        }
    }
    
    /// Dynamic bar: collapsed = center only (no pill); expanded = full bar with pill. Both branches animate opacity/scale for smooth expand and collapse.
    private var flatDynamicControlsBar: some View {
        ZStack {
            flatCollapsedControlsView
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .opacity(controlsExpanded ? 0 : 1)
                .scaleEffect(controlsExpanded ? 0.88 : 1)
                .allowsHitTesting(!controlsExpanded)
            flatControlsBarContent
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .opacity(controlsExpanded ? 1 : 0)
                .scaleEffect(controlsExpanded ? 1 : 0.88)
                .allowsHitTesting(controlsExpanded)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: controlsExpanded)
    }

    private func makeControlButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            if !controlsHighlighted && hideControls {
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
    
    private var coopInviteButton: some View {
        Button {
            if !controlsHighlighted && hideControls {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hideControls = false
                    controlsHighlighted = true
                }
                startHighlightTimer()
                return
            }
            
            
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
            if !controlsHighlighted && hideControls {
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
    
    private func sendTaskManager() {
        DispatchQueue.global(qos: .userInteractive).async {
            let MODIFIER_CTRL: Int8 = 0x02
            let MODIFIER_SHIFT: Int8 = 0x01
            let modifiers = MODIFIER_CTRL | MODIFIER_SHIFT
            let ESC_KEY: Int16 = 0x1B
            
           
            
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | ESC_KEY, 0x03, modifiers)  // Key Down
            usleep(50 * 1000)
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | ESC_KEY, 0x04, modifiers)  // Key Up
        }
    }
    
    @ViewBuilder
    private var statsOverlayView: some View {
        if viewModel.streamSettings.statsOverlay {
            VStack(spacing: 6) {
                Text(statsOverlayText.isEmpty ? "Collecting stats..." : statsOverlayText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.92))
            )
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - RealityView Setup
    
    func setupRealityView(content: RealityViewContent, attachments: RealityViewAttachments) {
        let baseWidth: Float = 1.0
        let baseHeight = baseWidth * screenAspect
        
        // Safe mesh generation with fallback
        let mesh: MeshResource
        do {
            mesh = try generateCurvedRoundedPlane(
                width: baseWidth,
                aspectRatio: screenAspect,
                resolution: (256, 256),
                curveMagnitude: 0,
                cornerRadiusFraction: cornerRadiusFraction
            )
        } catch {
            print("⚠️ Failed to generate flat mesh: \(error). Using simple plane fallback.")
            mesh = .generatePlane(width: baseWidth, height: baseHeight)
        }
        
        let material = UnlitMaterial(texture: texture)
        screen = ModelEntity(mesh: mesh, materials: [material])
        screen.position = SIMD3<Float>(0, 0, 0)
        
        content.add(screen)
        
        // Add the invisible ruler for calibration
        if let ruler = attachments.entity(for: "calibrationRuler") {
            ruler.components.set(OpacityComponent(opacity: 0.0))
            content.add(ruler)
        }
        
        attachAttachments(attachments: attachments, width: baseWidth, height: baseHeight)
    }
    
    func updateRealityView(content: RealityViewContent, attachments: RealityViewAttachments, size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        if abs(size.width - lastUpdateSize.width) < 1.0 && abs(size.height - lastUpdateSize.height) < 1.0 {
            return
        }
        lastUpdateSize = size
        
        // DYNAMIC CALIBRATION - Measure the ruler to get exact points-to-meters conversion
        if let ruler = attachments.entity(for: "calibrationRuler") {
            let rulerBounds = ruler.visualBounds(relativeTo: nil)
            let physicalRulerWidth = rulerBounds.extents.x
            
            if physicalRulerWidth > 0 {
                // Ruler is 100 points wide, so metersPerPoint = physicalWidth / 100
                let metersPerPoint = physicalRulerWidth / 100.0
                
                // Calculate target physical width for video mesh
                let targetPhysicalWidth = Float(size.width) * metersPerPoint
                
                // Scale the mesh (base is 1.0 meter)
                let scale = targetPhysicalWidth
                
                // Only update if changed significantly
                if abs(scale - screen.scale.x) > 0.0001 {
                    screen.scale = SIMD3<Float>(scale, scale, 1.0)
                    lastPhysicalWidth = scale
                }
            }
        }
        
        let physicalHeight = screen.scale.x * screenAspect
        updateAttachments(attachments: attachments, width: screen.scale.x, height: physicalHeight)
    }
    
    private func attachAttachments(attachments: RealityViewAttachments, width: Float, height: Float) {
        if let popupEnt = attachments.entity(for: "presetPopup") {
            screen.addChild(popupEnt)
            popupEnt.position = [0, 0, 0.15]
            
            let bounds = popupEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(popupEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                popupEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op join notification (centered, same as presetPopup)
        if let joinEnt = attachments.entity(for: "coopJoinNotification") {
            screen.addChild(joinEnt)
            joinEnt.position = [0, 0, 0.15]
            
            let bounds = joinEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(joinEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                joinEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op disconnect notification (centered, same as presetPopup)
        if let disconnectEnt = attachments.entity(for: "coopDisconnectNotification") {
            screen.addChild(disconnectEnt)
            disconnectEnt.position = [0, 0, 0.15]
            
            let bounds = disconnectEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                disconnectEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op connecting overlay (centered, same as presetPopup)
        if let connectingEnt = attachments.entity(for: "coopConnectingOverlay") {
            screen.addChild(connectingEnt)
            connectingEnt.position = [0, 0, 0.15]
            
            let bounds = connectingEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(connectingEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                connectingEnt.scale = [scale, scale, scale]
            }
        }
        
        // SBS 3D confirmation dialog (centered, floating in front)
        if let sbsEnt = attachments.entity(for: "sbsConfirm") {
            screen.addChild(sbsEnt)
            sbsEnt.position = [0, 0, 0.15]
            
            let bounds = sbsEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(sbsEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.3  // Slightly larger for the dialog
                let scale = desiredLocalWidth / unscaledWidth
                sbsEnt.scale = [scale, scale, scale]
            }
        }
    }
    
    private func updateAttachments(attachments: RealityViewAttachments, width: Float, height: Float) {
        if let popupEnt = attachments.entity(for: "presetPopup") {
            if popupEnt.parent !== screen { screen.addChild(popupEnt) }
            let bounds = popupEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(popupEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                popupEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op join notification
        if let joinEnt = attachments.entity(for: "coopJoinNotification") {
            if joinEnt.parent !== screen { screen.addChild(joinEnt) }
            let bounds = joinEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(joinEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                joinEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op disconnect notification
        if let disconnectEnt = attachments.entity(for: "coopDisconnectNotification") {
            if disconnectEnt.parent !== screen { screen.addChild(disconnectEnt) }
            let bounds = disconnectEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(disconnectEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                disconnectEnt.scale = [scale, scale, scale]
            }
        }
        
        // Co-op connecting overlay
        if let connectingEnt = attachments.entity(for: "coopConnectingOverlay") {
            if connectingEnt.parent !== screen { screen.addChild(connectingEnt) }
            let bounds = connectingEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(connectingEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.25
                let scale = desiredLocalWidth / unscaledWidth
                connectingEnt.scale = [scale, scale, scale]
            }
        }
        
        // SBS 3D confirmation dialog
        if let sbsEnt = attachments.entity(for: "sbsConfirm") {
            if sbsEnt.parent !== screen { screen.addChild(sbsEnt) }
            let bounds = sbsEnt.visualBounds(relativeTo: screen)
            if bounds.extents.x > 0 {
                let currentScaleX = max(sbsEnt.scale.x, 0.0001)
                let unscaledWidth = Float(bounds.extents.x) / currentScaleX
                let desiredLocalWidth: Float = 0.3  // Slightly larger for the dialog
                let scale = desiredLocalWidth / unscaledWidth
                sbsEnt.scale = [scale, scale, scale]
            }
        }
    }
    
    private func rebindScreenMaterial() {
        // Rebind material based on current video mode
        updateScreenMaterial()
    }
    
    private func refreshAfterResume() {
        LiRequestIdrFrame()
        rebindScreenMaterial()
    }
    
    private func cancelFirstFrameWatchdogs() {
        watchdogIDR1?.cancel()
        watchdogIDR2?.cancel()
        watchdogIDR1 = nil
        watchdogIDR2 = nil
        guestAggressiveIDRTimer?.invalidate()
        guestAggressiveIDRTimer = nil
    }
    
    // MARK: - HDR & Presets
    
    private func applyCurvedUIKitPreset(_ preset: Int32) {
        var params = safeHDRSettings.value
        let isHdr = viewModel.streamSettings.enableHdr
        
        if isHdr {
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
            
            let hrBoost: Float = 1.40
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
    
    private func presetName(for preset: Int32) -> String {
        switch preset {
        case 0: return "FILTER: Default"
        case 1: return "FILTER: Cinematic"
        case 2: return "FILTER: Vi\u{200A}vid"  // Hair space between I and V
        case 3: return "FILTER: Realistic"
        default: return "FILTER: Default"
        }
    }
    
    private func canChangePreset() -> Bool {
        guard let cooldownUntil = presetCooldownUntil else { return true }
        return Date() >= cooldownUntil
    }

    // MARK: - Scene Lifecycle & Helpers
    
    private func setupScene() {
        debugLog("📍 setupScene called - activelyStreaming: \(viewModel.activelyStreaming), hasPerformedTeardown: \(hasPerformedTeardown), windowDecommissioned: \(windowDecommissioned)")
        
        if !viewModel.activelyStreaming { return }
        
        // Force recreation of ControllerSupport with the LATEST streamConfig.
        // This fixes the issue where 'init' captured a stale config (wrong player slot)
        // and @State persisted it.
        debugLog("[FlatDisplay] Re-initializing ControllerSupport with slotOffset: \(streamConfig.controllerSlotOffset)")
        self.controllerSupport = ControllerSupport(config: streamConfig, delegate: DummyControllerDelegate())
        
        // Set controller support reference for rumble forwarding
        self.connectionCallbacks.controllerSupport = self.controllerSupport
        
        // CRITICAL: Reset teardown flag to allow proper cleanup on next disconnect
        self.hasPerformedTeardown = false
        self.windowDecommissioned = false  // Window is alive again — allow it to react to state
        self.renderGateOpen = true
        viewModel.isStreamViewAlive = true
        dismissWindow(id: "mainView")
        isMenuOpen = false
        
        viewModel.streamSettings.statsOverlay = false
        statsTimer?.invalidate()
        statsTimer = nil
        statsOverlayText = ""
        
        var stored = UserDefaults.standard.integer(forKey: "ambient.dimming.level")
        if stored > 1 { stored = 0 }
        dimLevel = stored
        
        // Load saved touch control preference
        viewModel.streamSettings.absoluteTouchMode = UserDefaults.standard.bool(forKey: "flat.absoluteTouchMode")
        
        startStreamIfNeeded()
        spatialAudioMode = true
        
        hideTimer?.invalidate()
        hideTimer = nil
        hideControls = false
        
        if viewModel.streamSettings.uikitPreset != 0 {
            viewModel.streamSettings.uikitPreset = 0
        }
        applyCurvedUIKitPreset(0)
        
        applyWindowAspectRatioLock()
    }
    
    private func teardownScene() {
        debugLog("📍 teardownScene called - hasPerformedTeardown: \(hasPerformedTeardown)")
        statsTimer?.invalidate()
        statsTimer = nil
        viewModel.isStreamViewAlive = false
        if !hasPerformedTeardown { performCompleteTeardown() }
    }
    
    private func ensureStreamStartedIfNeeded() { startStreamIfNeeded() }
    
    private func performCompleteTeardown() {
        guard !hasPerformedTeardown else {
            debugLog("⚠️ performCompleteTeardown SKIPPED - already performed")
            return
        }
        hasPerformedTeardown = true
        
        debugLog("🔴 TEARDOWN START - streamMan exists: \(streamMan != nil)")
        
        // CRITICAL: Close render gate BEFORE stopping stream to prevent race conditions
        renderGateOpen = false
        
        cancelFirstFrameWatchdogs()
        startingStream = false
        
        statsTimer?.invalidate()
        hideTimer?.invalidate()
        presetOverlayTimer?.invalidate()
        
        controllerSupport?.cleanup()
        controllerSupport = nil
        
        if let sm = streamMan {
            print("[FlatDisplay] Stopping StreamManager (waiting for LiStopConnection completion)...")
            streamMan = nil  // Clear reference now to prevent double-stop
            
            // Tell the serializer a stop is beginning — no new connection can start until
            // notifyStopComplete() is called inside the real completion block below.
            ConnectionSerializer.shared.notifyStopBegun()
            
            sm.stopStream(completion: {
                DispatchQueue.main.async {
                    print("[FlatDisplay] 🔴 TEARDOWN COMPLETE — LiStopConnection finished")
                    // Ungate the serializer — new connections may now proceed.
                    ConnectionSerializer.shared.notifyStopComplete()
                    NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
                }
            })
        } else {
            print("[FlatDisplay] 🔴 TEARDOWN COMPLETE (no stream to stop)")
            NotificationCenter.default.post(name: Notification.Name("RKStreamDidTeardown"), object: nil)
        }
    }
    
    private func triggerCloseSequence() {
        windowDecommissioned = true  // Silence this window so it can't interfere as a zombie
        performCompleteTeardown()
        viewModel.activelyStreaming = false  // CRITICAL FIX: Match CurvedDisplay behavior
        viewModel.shouldCloseStream = false
        dismissWindow(id: "flatDisplayWindow")
    }
    
    private func fixAudioForCurrentMode() {
        if spatialAudioMode {
            AudioHelpers.fixAudioForSurroundForCurrentWindow(soundStageSize: soundStageSize)
        } else {
            AudioHelpers.fixAudioForDirectStereo()
        }
    }
    
    @ViewBuilder
    private var confirmationsOverlay: some View {
        if show3DConfirm {
            let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
            let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

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
                        applyWindowAspectRatioLock()
                        
                        presetOverlayText = "SBS 3D Enabled"
                        presetOverlayIcon = "view.3d"
                        showInlinePresetOverlay = true
                        
                        presetOverlayTimer?.invalidate()
                        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                showInlinePresetOverlay = false
                            }
                        }
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
        } else if showDisconnectConfirm {
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
                        Task { @MainActor in
                            // userDidRequestDisconnect handles quit request + co-op cleanup + endSession
                            viewModel.userDidRequestDisconnect()
                            openWindow(id: "mainView")
                            dismissWindow(id: "flatDisplayWindow")
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
    
    private func handleResume() {
        dismissWindow(id: "mainView")
        isMenuOpen = false
        withAnimation(.easeInOut(duration: 0.3)) {
            hideControls = false
            controlsHighlighted = true
        }
        startHighlightTimer()
        fixAudioForCurrentMode()
    }
    
    // MARK: - SBS 3D Material Management
    
    private func setupMaterial() async {
        if surfaceMaterial == nil {
            do {
                var material = try await ShaderGraphMaterial(named: "/Root/SBSMaterial", from: "SBSMaterial.usda")
                try material.setParameter(name: "texture", value: .textureResource(self.texture))
                self.surfaceMaterial = material
                print("[FlatDisplay] SBS material loaded successfully")
            } catch {
                print("[FlatDisplay] ⚠️ Failed to load SBS material: \(error)")
            }
        }
    }
    
    private func updateScreenMaterial() {
        if videoMode == .sideBySide3D {
            if var mat = surfaceMaterial {
                do {
                    try mat.setParameter(name: "texture", value: .textureResource(self.texture))
                    surfaceMaterial = mat
                    screen.model?.materials = [mat]
                    print("[FlatDisplay] Switched to SBS 3D material")
                } catch {
                    print("[FlatDisplay] ⚠️ Failed to set SBS material parameter: \(error)")
                    screen.model?.materials = [UnlitMaterial(texture: texture)]
                }
            } else {
                print("[FlatDisplay] ⚠️ SBS material not loaded, using standard material")
                screen.model?.materials = [UnlitMaterial(texture: texture)]
            }
        } else {
            screen.model?.materials = [UnlitMaterial(texture: self.texture)]
            print("[FlatDisplay] Switched to standard 2D material")
        }
    }
    
    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if viewModel.activelyStreaming {
                    if self.viewModel.streamSettings.useCollapsedControlsMenu && self.controlsExpanded {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            self.controlsExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                self.hideControls = true
                                self.controlsHighlighted = false
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            self.hideControls = true
                            self.controlsHighlighted = false
                        }
                    }
                }
            }
        }
    }
    
    private func startHighlightTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.viewModel.streamSettings.useCollapsedControlsMenu && self.controlsExpanded {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        self.controlsExpanded = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            self.controlsHighlighted = false
                            self.hideControls = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.controlsHighlighted = false
                        self.hideControls = true
                    }
                }
            }
        }
    }
    
    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard self.viewModel.activelyStreaming else { return }
            if let streamMan = self.streamMan, let stats = streamMan.getStatsOverlayText() {
                self.statsOverlayText = stats
            }
        }
    }
    
    private func applyWindowAspectRatioLock() {
        guard viewModel.activelyStreaming else { return }
        
        // Create effective config - for SBS 3D mode, use half width for correct aspect ratio
        let effectiveConfig: StreamConfiguration
        if videoMode == .sideBySide3D && isSBSVideo {
            effectiveConfig = StreamConfiguration()
            effectiveConfig.width = streamConfig.width / 2  // Half width for one eye
            effectiveConfig.height = streamConfig.height
        } else {
            effectiveConfig = streamConfig
        }
        
        guard let win = hostingWindow else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let w = self.hostingWindow {
                    applyAspectRatioLock(streamConfiguration: effectiveConfig, targetWindow: w)
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            applyAspectRatioLock(streamConfiguration: effectiveConfig, targetWindow: win)
        }
    }
    
    // MARK: - Stream Management
    
    private func startStreamIfNeeded() {
        guard streamMan == nil, !startingStream else {
            print("[FlatDisplay] Stream start skipped (streamMan exists: \(streamMan != nil), startingStream: \(startingStream))")
            return
        }
        
        startingStream = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.hasPerformedTeardown, self.viewModel.activelyStreaming, self.streamMan == nil else {
                print("[FlatDisplay] Aborting stream start - Teardown: \(self.hasPerformedTeardown), Streaming: \(self.viewModel.activelyStreaming), Exists: \(self.streamMan != nil)")
                self.startingStream = false
                return
            }
            
            self.streamEpoch &+= 1
            self.firstFrameSeenEpoch = -1
            let myEpoch = self.streamEpoch
            print("[FlatDisplay] 🚀 Starting stream (epoch \(myEpoch))")
            
            self.renderGateOpen = true
            self.ensureHDRTextureMatchesSetting()
        
            self.controllerSupport = ControllerSupport(config: self.streamConfig, delegate: DummyControllerDelegate())
            
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
                                guard self.renderGateOpen else { return }
                                if let correctedResolution {
                                    self.correctedResolution = correctedResolution
                                    self.correctedResolutionVersion += 1
                                }
                                
                                // First Frame Logic (matches CurvedDisplay behavior)
                                if self.firstFrameSeenEpoch != self.streamEpoch {
                                    self.firstFrameSeenEpoch = self.streamEpoch
                                    print("[FlatDisplay] First frame received; epoch=\(self.streamEpoch)")
                                    self.cancelFirstFrameWatchdogs()
                                    
                                    // Rebind material after short delay to ensure texture is ready
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                        self.rebindScreenMaterial()
                                    }
                                    
                                    // Force first frame to display immediately
                                    if let firstFrame = self.frameMailbox.collect() {
                                        self.texture.replace(withDrawables: firstFrame)
                                    }
                                }
                                
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
        
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { LiRequestIdrFrame() }
            
            let w1 = DispatchWorkItem {
                if self.streamEpoch == myEpoch && self.firstFrameSeenEpoch != myEpoch && !self.hasPerformedTeardown {
                    print("[FlatDisplay] Watchdog @0.9s → Requesting IDR (epoch \(myEpoch))")
                    LiRequestIdrFrame()
                }
            }
            let w2 = DispatchWorkItem {
                if self.streamEpoch == myEpoch && self.firstFrameSeenEpoch != myEpoch && !self.hasPerformedTeardown {
                    print("[FlatDisplay] Watchdog @1.8s → Requesting IDR (epoch \(myEpoch))")
                    LiRequestIdrFrame()
                }
            }
            self.watchdogIDR1 = w1
            self.watchdogIDR2 = w2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: w1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: w2)
            
            // AGGRESSIVE GUEST-SIDE IDR REQUESTING
            // Co-op guests have independent streams - they must request their own IDR frames
            if self.viewModel.isCoopSession && self.viewModel.assignedControllerSlot == 1 {
                print("[FlatDisplay] 🎮 CO-OP GUEST: Starting aggressive IDR requesting")
                var requestCount = 0
                let maxRequests = 120 // 60 seconds at 500ms intervals
                self.guestAggressiveIDRTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    requestCount += 1
                    if self.firstFrameSeenEpoch == myEpoch {
                        print("[FlatDisplay] 🎮 CO-OP GUEST: First frame received! Stopping IDR requests after \(requestCount) requests")
                        timer.invalidate()
                        self.guestAggressiveIDRTimer = nil
                        return
                    }
                    if requestCount > maxRequests {
                        print("[FlatDisplay] 🎮 CO-OP GUEST: Max IDR requests reached (\(maxRequests)), stopping")
                        timer.invalidate()
                        self.guestAggressiveIDRTimer = nil
                        return
                    }
                    print("[FlatDisplay] 🎮 CO-OP GUEST: Requesting IDR frame #\(requestCount)")
                    LiRequestIdrFrame()
                }
            }
            
            self.startingStream = false
        }
    }
    
    private func ensureHDRTextureMatchesSetting() {
        let desiredHDR = viewModel.streamSettings.enableHdr
        if desiredHDR == isHDRTexture { return }
        
        let width = Int(streamConfig.width)
        let height = Int(streamConfig.height)
        let bytesPerPixel = desiredHDR ? 8 : 4
        let data = Data(count: bytesPerPixel * width * height)
        
        // Safe texture recreation with fallback
        do {
            texture = try TextureResource(
                dimensions: .dimensions(width: width, height: height),
                format: .raw(pixelFormat: desiredHDR ? .rgba16Float : .bgra8Unorm_srgb),
                contents: .init(mipmapLevels: [.mip(data: data, bytesPerRow: bytesPerPixel * width)])
            )
            isHDRTexture = desiredHDR
            screen.model?.materials = [UnlitMaterial(texture: texture)]
        } catch {
            print("⚠️ Failed to recreate texture for HDR toggle: \(error). Keeping existing texture.")
            // Keep existing texture rather than crash
        }
    }
}

private struct WindowResolver: UIViewRepresentable {
    let onResolve: (UIWindow) -> Void
    func makeUIView(context: Context) -> _WindowResolverView {
        let v = _WindowResolverView()
        v.onResolve = onResolve
        return v
    }
    func updateUIView(_ uiView: _WindowResolverView, context: Context) {}
}
private final class _WindowResolverView: UIView {
    var onResolve: ((UIWindow) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let w = window {
            onResolve?(w)
        }
    }
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
    let cornerRadius = max(0.0, min(1.0, cornerRadiusFraction)) * width

    let resX = max(2, Int(resolution.0))
    let resY = max(2, Int(resolution.1))
    let vertexCount = resX * resY

    let numQuadsX = resX - 1
    let numQuadsY = resY - 1
    let triangleCount = numQuadsX * numQuadsY * 2
    let indexCount = triangleCount * 3

    var positions: [SIMD3<Float>] = .init(repeating: .zero, count: vertexCount)
    var uvs: [SIMD2<Float>] = .init(repeating: .zero, count: vertexCount)
    var indices: [UInt32] = .init(repeating: 0, count: indexCount)

    let maxCurveAngle: Float = (5.5 * .pi / 6.0)
    let currentAngle = maxCurveAngle * max(0.0, min(curveMagnitude, 1.0))
    let halfAngle = currentAngle / 2.0
    let radius: Float = (abs(halfAngle) < 0.0001) ? .infinity : (width / (2.0 * sin(halfAngle)))

    let uvInset: Float = 0.0005

    var vIndex = 0
    var iIndex = 0
    for y in 0..<resY {
        let vGeo = Float(y) / Float(resY - 1)
        let yPos = (0.5 - vGeo) * height
        let vTex = (1.0 - vGeo) * (1.0 - 2.0 * uvInset) + uvInset

        for x in 0..<resX {
            let u = Float(x) / Float(resX - 1)

            var xPlane = (u - 0.5) * width
            var yPlane = yPos
            if cornerRadius > 0.0 {
                let halfW = width * 0.5
                let halfH = height * 0.5
                let rx = halfW - cornerRadius
                let ry = halfH - cornerRadius

                var px = xPlane
                var py = yPlane

                let sx = (abs(px) - rx)
                let sy = (abs(py) - ry)

                if sx > 0.0 || sy > 0.0 {
                    let dx = max(sx, 0.0)
                    let dy = max(sy, 0.0)
                    let len = simd_length(SIMD2<Float>(dx, dy))
                    if len > cornerRadius {
                        let norm = simd_normalize(SIMD2<Float>(dx, dy))
                        let clamped = norm * cornerRadius
                        let signX: Float = (px >= 0) ? 1.0 : -1.0
                        let signY: Float = (py >= 0) ? 1.0 : -1.0
                        px = signX * (rx + clamped.x)
                        py = signY * (ry + clamped.y)
                    }
                }

                xPlane = px
                yPlane = py
            }

            let xPos: Float
            let zPos: Float
            if radius.isFinite && radius > 0 && currentAngle > 0.0001 {
                let theta = (u - 0.5) * currentAngle
                xPos = radius * sin(theta)
                zPos = radius * (cos(halfAngle) - cos(theta))
            } else {
                xPos = xPlane
                zPos = 0.0
            }

            positions[vIndex] = [xPos, yPlane, zPos]
            let uTex = u * (1.0 - 2.0 * uvInset) + uvInset
            uvs[vIndex] = [uTex, vTex]

            if x < numQuadsX && y < numQuadsY {
                let current = UInt32(vIndex)
                let nextRow = current + UInt32(resX)

                let topLeft = current
                let topRight = topLeft + 1
                let bottomLeft = nextRow
                let bottomRight = bottomLeft + 1

                indices[iIndex + 0] = topLeft
                indices[iIndex + 1] = bottomLeft
                indices[iIndex + 2] = bottomRight

                indices[iIndex + 3] = topLeft
                indices[iIndex + 4] = bottomRight
                indices[iIndex + 5] = topRight

                iIndex += 6
            }

            vIndex += 1
        }
    }

    descr.positions = MeshBuffers.Positions(positions)
    descr.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    descr.primitives = .triangles(indices)

    return try MeshResource.generate(from: [descr])
}
