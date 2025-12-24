//
//  RealityKitInputSupport.swift
//  NeoMoonlight - Input handling for RealityKit views
//
//  Extracted from RikuKun's moonlight-ios-vision
//

import UIKit
import SwiftUI
import GameController

// MARK: - C-Function Bridges (Manual Linking)

@_silgen_name("LiSendMouseButtonEvent")
func LiSendMouseButtonEvent(_ action: Int8, _ button: Int32) -> Int32

@_silgen_name("LiSendMousePositionEvent")
func LiSendMousePositionEvent(_ x: Int16, _ y: Int16, _ width: Int16, _ height: Int16) -> Int32

@_silgen_name("LiSendHighResScrollEvent")
func LiSendHighResScrollEvent(_ scrollAmount: Int16) -> Int32

@_silgen_name("LiSendHighResHScrollEvent")
func LiSendHighResHScrollEvent(_ scrollAmount: Int16) -> Int32

@_silgen_name("LiSendKeyboardEvent")
func LiSendKeyboardEvent(_ keyCode: Int16, _ keyAction: Int8, _ modifiers: Int8) -> Int32

@_silgen_name("LiSendUtf8TextEvent")
func LiSendUtf8TextEvent(_ text: UnsafePointer<CChar>, _ length: UInt32) -> Int32

// MARK: - Constants

private let BUTTON_ACTION_PRESS: Int8 = 0
private let BUTTON_ACTION_RELEASE: Int8 = 1
private let BUTTON_LEFT: Int32 = 1
private let BUTTON_RIGHT: Int32 = 2
private let KEY_ACTION_DOWN: Int8 = 0x03
private let KEY_ACTION_UP: Int8 = 0x04

// MARK: - SwiftUI Wrapper

struct RealityKitInputView: UIViewControllerRepresentable {
    var streamConfig: StreamConfiguration
    let controllerSupport: ControllerSupport
    @Binding var showKeyboard: Bool

    var curvatureMagnitude: Float = 0.0

    func makeUIViewController(context: Context) -> RealityKitInputViewController {
        let vc = RealityKitInputViewController()
        vc.streamConfig = streamConfig
        vc.controllerSupport = controllerSupport
        vc.keyboardDismissHandler = { DispatchQueue.main.async {} }
        vc.curvatureMagnitude = curvatureMagnitude
        return vc
    }
    
    func updateUIViewController(_ vc: RealityKitInputViewController, context: Context) {
        vc.streamConfig = streamConfig
        vc.curvatureMagnitude = curvatureMagnitude
        if let overlay = vc.view as? RealityKitInputOverlay {
            overlay.streamConfig = streamConfig
            overlay.curvatureMagnitude = curvatureMagnitude
            if overlay.showSoftwareKeyboard != showKeyboard {
                overlay.showSoftwareKeyboard = showKeyboard
                if showKeyboard {
                    DispatchQueue.main.async { overlay.becomeFirstResponder() }
                }
            }
        }
    }
}

// MARK: - View Controller

class RealityKitInputViewController: UIViewController {
    var streamConfig: StreamConfiguration? {
        didSet {
            if let overlay = view as? RealityKitInputOverlay { overlay.streamConfig = streamConfig }
        }
    }
    var controllerSupport: ControllerSupport?
    var keyboardDismissHandler: (() -> Void)?
    var curvatureMagnitude: Float = 0.0 {
        didSet {
            if let overlay = view as? RealityKitInputOverlay {
                overlay.curvatureMagnitude = curvatureMagnitude
            }
        }
    }
    
    private lazy var inputOverlayView: RealityKitInputOverlay = {
        let v = RealityKitInputOverlay()
        v.parentController = self
        v.curvatureMagnitude = curvatureMagnitude
        return v
    }()
    
    override func loadView() { self.view = inputOverlayView }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let support = controllerSupport {
            support.attachGCEventInteraction(to: self.view)
            support.realityKitMode = true
            support.realityKitMouseMovedHandler = { [weak self] (dx: Float, dy: Float) in
                self?.inputOverlayView.handleRawMouseDelta(dx: dx, dy: dy)
            }
            support.realityKitKeyboardHandler = nil
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let support = controllerSupport {
            for mouse in GCMouse.mice() { support.registerMouseCallbacks(mouse) }
        }
        if !self.inputOverlayView.becomeFirstResponder() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                _ = self?.inputOverlayView.becomeFirstResponder()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let support = controllerSupport {
            support.realityKitMode = false
            support.realityKitMouseMovedHandler = nil
            support.realityKitKeyboardHandler = nil
        }
    }
    
    override var canBecomeFirstResponder: Bool { false }
}

// MARK: - Overlay View

class RealityKitInputOverlay: UIView, UIKeyInput, UIPointerInteractionDelegate, UIGestureRecognizerDelegate {
    weak var parentController: RealityKitInputViewController?
    var streamConfig: StreamConfiguration?
    var showSoftwareKeyboard: Bool = false {
        didSet {
            DispatchQueue.main.async {
                if self.showSoftwareKeyboard && !self.isFirstResponder { self.becomeFirstResponder() }
                self.reloadInputViews()
            }
        }
    }

    var curvatureMagnitude: Float = 0.0

    // Mirror CURVED_MAX_ANGLE from CurvedDisplayStreamView
    private let CURVED_MAX_ANGLE: Float = 1.3
    
    override var inputView: UIView? { showSoftwareKeyboard ? nil : UIView() }
    private var currentMousePosition: CGPoint = .zero
    private var lastMouseButtonMask: UIEvent.ButtonMask = []
    private var lastScrollTranslation: CGPoint = .zero
    private let wheelDelta: CGFloat = 120.0

    // Multi-click/drag gesture state (retuned for responsiveness)
    private var selectPressStart: TimeInterval?
    private var leftDownSent = false
    private var dragTimer: Timer?
    private var pendingLeftClickTimer: Timer?
    private var clickQueue: [TimeInterval] = []

    // Tighter timings for snappier feel
    private let clickMaxDuration: TimeInterval = 0.18
    private let dragHoldThreshold: TimeInterval = 0.12
    private let multiClickWindow: TimeInterval = 0.20

    // Movement-based early drag trigger
    private var lastOverlayPoint: CGPoint = .zero
    private var pressStartOverlayPoint: CGPoint?
    private let movementToDragThreshold: CGFloat = 6.0

    override init(frame: CGRect) { super.init(frame: frame); setupInteraction() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupInteraction() }
    
    private func setupInteraction() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        self.isMultipleTouchEnabled = true
        self.isUserInteractionEnabled = true
        self.addInteraction(UIPointerInteraction(delegate: self))
        let panScroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        panScroll.allowedScrollTypesMask = .all
        panScroll.delegate = self
        self.addGestureRecognizer(panScroll)
        self.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:))))
    }
    
    override var canBecomeFocused: Bool { true }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { parentController?.keyboardDismissHandler?() }
        return result
    }
    
    // Map visionOS pinch (.select press) to mouse down/up for click/drag + multi-click promotion
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        if presses.contains(where: { $0.type == .select }) {
            handled = true
            selectPressStart = CACurrentMediaTime()
            leftDownSent = false

            // Record where the press began (overlay coords) for movement-based drag
            pressStartOverlayPoint = lastOverlayPoint

            // Schedule time-based drag fallback
            dragTimer?.invalidate()
            dragTimer = Timer.scheduledTimer(withTimeInterval: dragHoldThreshold, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.selectPressStart != nil && !self.leftDownSent {
                    self.sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_LEFT)
                    self.leftDownSent = true
                }
            }
        }

        // Existing keyboard mapping
        for press in presses {
            if KeyboardSupport.sendKeyEvent(for: press, down: true) {
                handled = true
            }
        }

        if !handled { super.pressesBegan(presses, with: event) }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        if presses.contains(where: { $0.type == .select }) {
            handled = true
            let now = CACurrentMediaTime()
            dragTimer?.invalidate()
            dragTimer = nil

            if leftDownSent {
                // End of drag
                sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_LEFT)
                leftDownSent = false
                selectPressStart = nil
                pressStartOverlayPoint = nil
            } else {
                // Quick pinch -> candidate click
                let started = selectPressStart ?? now
                let duration = now - started
                selectPressStart = nil
                pressStartOverlayPoint = nil

                if duration <= clickMaxDuration {
                    enqueueClickAndMaybePromote(now: now)
                } else {
                    scheduleOrSendSingleLeftClick(now: now)
                }
            }
        }

        // Existing keyboard mapping
        for press in presses {
            if KeyboardSupport.sendKeyEvent(for: press, down: false) {
                handled = true
            }
        }

        if !handled { super.pressesEnded(presses, with: event) }
    }

    // Click promotion logic (double = right, triple = middle)
    private func enqueueClickAndMaybePromote(now: TimeInterval) {
        pendingLeftClickTimer?.invalidate()
        pendingLeftClickTimer = nil

        clickQueue.append(now)
        clickQueue = clickQueue.filter { now - $0 <= multiClickWindow }

        if clickQueue.count >= 3 {
            sendMiddleClick()
            clickQueue.removeAll()
        } else if clickQueue.count == 2 {
            sendRightClick()
            clickQueue.removeAll()
        } else {
            scheduleOrSendSingleLeftClick(now: now)
        }
    }

    private func scheduleOrSendSingleLeftClick(now: TimeInterval) {
        pendingLeftClickTimer?.invalidate()
        pendingLeftClickTimer = Timer.scheduledTimer(withTimeInterval: multiClickWindow, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.clickQueue.count == 1 {
                self.sendLeftClick()
            }
            self.clickQueue.removeAll()
        }
    }

    private func sendLeftClick() {
        DispatchQueue.global(qos: .userInteractive).async {
            self.sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_LEFT)
            usleep(25_000)
            self.sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_LEFT)
        }
    }

    private func sendRightClick() {
        DispatchQueue.global(qos: .userInteractive).async {
            self.sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_RIGHT)
            usleep(25_000)
            self.sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_RIGHT)
        }
    }

    private func sendMiddleClick() {
        let BUTTON_MIDDLE: Int32 = 3
        DispatchQueue.global(qos: .userInteractive).async {
            self.sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_MIDDLE)
            usleep(25_000)
            self.sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_MIDDLE)
        }
    }

    // Optional: Clean up timers
    override func removeFromSuperview() {
        super.removeFromSuperview()
        dragTimer?.invalidate()
        dragTimer = nil
        pendingLeftClickTimer?.invalidate()
        pendingLeftClickTimer = nil
        clickQueue.removeAll()
        selectPressStart = nil
        pressStartOverlayPoint = nil
    }
    
    var hasText: Bool { true }
    func insertText(_ text: String) {
        if text.count == 1, let char = text.first {
            let utf16 = String(char).utf16.first!
            let keyEvent = KeyboardSupport.translateKeyEvent(utf16, with: [])
            if keyEvent.keycode != 0 { sendLowLevelEvent(event: keyEvent); return }
        }
        let cString = text.cString(using: .utf8)
        cString?.withUnsafeBufferPointer { ptr in if let base = ptr.baseAddress { LiSendUtf8TextEvent(base, UInt32(text.utf8.count)) } }
    }
    
    func deleteBackward() {
        LiSendKeyboardEvent(0x08, 0x03, 0)
        usleep(50 * 1000)
        LiSendKeyboardEvent(0x08, 0x04, 0)
    }
    
    private func sendLowLevelEvent(event: KeyEvent) {
        DispatchQueue.global(qos: .userInteractive).async {
            if event.modifier != 0 { LiSendKeyboardEvent(Int16(event.modifierKeycode), 0x03, Int8(event.modifier)) }
            LiSendKeyboardEvent(Int16(event.keycode), 0x03, Int8(event.modifier))
            usleep(50 * 1000)
            LiSendKeyboardEvent(Int16(event.keycode), 0x04, Int8(event.modifier))
            if event.modifier != 0 { LiSendKeyboardEvent(Int16(event.modifierKeycode), 0x04, Int8(event.modifier)) }
        }
    }
    
    func handleRawMouseDelta(dx: Float, dy: Float) {
        guard let config = streamConfig else { return }
        let sensitivity: CGFloat = 1.0
        var newX = currentMousePosition.x + (CGFloat(dx) * sensitivity)
        var newY = currentMousePosition.y - (CGFloat(dy) * sensitivity)
        let width = CGFloat(config.width); let height = CGFloat(config.height)
        newX = min(max(newX, 0), width); newY = min(max(newY, 0), height)
        currentMousePosition = CGPoint(x: newX, y: newY)
        LiSendMousePositionEvent(Int16(newX), Int16(newY), Int16(width), Int16(height))
    }
    
    func sendMouseButton(action: Int8, button: Int32) { LiSendMouseButtonEvent(action, button) }
    
    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        if lastMouseButtonMask.isEmpty { updateCursorFromSystemPointer(location: request.location) }
        return UIPointerRegion(rect: self.bounds)
    }
    
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? { return nil }
    
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        if lastMouseButtonMask.isEmpty { updateCursorFromSystemPointer(location: gesture.location(in: self)) }
    }
    
    // Curvature-aware pointer mapping
    private func sendMouseAtOverlayPoint(_ pt: CGPoint) {
        guard let config = streamConfig else { return }

        // Track latest overlay point (for movement-based drag detection)
        lastOverlayPoint = pt

        // Early-drag trigger on movement (if user is holding pinch)
        if let startPt = pressStartOverlayPoint,
           selectPressStart != nil,
           !leftDownSent {
            let dx = pt.x - startPt.x
            let dy = pt.y - startPt.y
            if (dx*dx + dy*dy).squareRoot() >= movementToDragThreshold {
                sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_LEFT)
                leftDownSent = true
            }
        }

        let width = self.bounds.width
        let height = self.bounds.height

        var finalX = pt.x
        let y = pt.y

        if curvatureMagnitude > 0.001 && width > 1 {
            let normalizedX = Float(pt.x / width)
            let relativeX = normalizedX - 0.5

            let angle = CURVED_MAX_ANGLE * curvatureMagnitude
            let sinHalf = sin(angle / 2.0)
            let sinTheta = relativeX * 2.0 * sinHalf
            let clampedSin = max(-1.0, min(1.0, sinTheta))
            let theta = asinf(clampedSin)
            let u = (theta / angle) + 0.5
            finalX = CGFloat(u) * width
        }

        let streamWidth = CGFloat(config.width)
        let streamHeight = CGFloat(config.height)

        let hostX = (finalX / width) * streamWidth
        let hostY = (y / height) * streamHeight

        let clampedX = min(max(hostX, 0), streamWidth)
        let clampedY = min(max(hostY, 0), streamHeight)

        currentMousePosition = CGPoint(x: clampedX, y: clampedY)
        LiSendMousePositionEvent(Int16(clampedX), Int16(clampedY), Int16(streamWidth), Int16(streamHeight))
    }

    private func updateCursorFromSystemPointer(location: CGPoint) {
        // Wrap the existing mapping with curvature correction
        sendMouseAtOverlayPoint(location)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        sendMouseButton(action: BUTTON_ACTION_PRESS, button: BUTTON_LEFT)
        if let touch = touches.first { sendMouseAtOverlayPoint(touch.location(in: self)) }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { sendMouseAtOverlayPoint(touch.location(in: self)) }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_LEFT)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        sendMouseButton(action: BUTTON_ACTION_RELEASE, button: BUTTON_LEFT)
    }
    
    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .began else { lastScrollTranslation = .zero; return }
        let currentTranslation = gesture.translation(in: self)
        let deltaY = (currentTranslation.y - lastScrollTranslation.y)
        let deltaX = (currentTranslation.x - lastScrollTranslation.x)
        if deltaY != 0 { LiSendHighResScrollEvent(Int16((deltaY / self.bounds.height) * wheelDelta * 20.0)) }
        if deltaX != 0 { LiSendHighResHScrollEvent(Int16(-(deltaX / self.bounds.width) * wheelDelta * 20.0)) }
        lastScrollTranslation = currentTranslation
    }
}