//
//  StreamGamepadSession.swift
//  Moonlight Vision
//
//  Created by NeoVectorX 2026
//

import UIKit

/// Shared coordinator for Flat (always-on gamepad) and Curved (Controller input mode only).
@MainActor
final class StreamGamepadSession {
    enum DisplayStyle {
        case flat
        case curved
    }

    var displayStyle: DisplayStyle = .flat
    private(set) var modalBlocking: Bool = false
    private(set) var controllerModeActive: Bool = false
    private(set) var streamActive: Bool = false

    private weak var captureView: UIView?
    private weak var controllerSupport: ControllerSupport?
    private var focusWatchdog: Timer?
    private weak var attachedView: UIView?
    private var gcEventInteractionAttached = false
    /// Brief pause after desktop keyboard shortcuts so host UI (e.g. Alt+Tab) is not confirmed by gamepad A.
    private var desktopActionSuppressUntil: Date?

    /// When true, the input-capture overlay must not steal hits (HDR, pickers, etc.).
    var modalBlocksOverlay: Bool {
        modalBlocking
    }

    func attach(captureView: UIView, controllerSupport: ControllerSupport) {
        let viewChanged = attachedView !== captureView
        let supportChanged = self.controllerSupport !== controllerSupport

        if viewChanged || supportChanged {
            if let previous = attachedView, let support = self.controllerSupport {
                detachGCEventInteraction(from: previous, support: support)
            } else if gcEventInteractionAttached {
                // Old view or support was deallocated; reset the stale flag so
                // the new GCEventInteraction can be attached.
                gcEventInteractionAttached = false
            }
            attachedView = captureView
        }
        self.captureView = captureView
        self.controllerSupport = controllerSupport
        if viewChanged || supportChanged {
            updateCapturePolicy()
        }
    }

    func detach() {
        stopFocusWatchdog()
        controllerSupport?.setInputSyncEnabled(false)
        if let view = attachedView, let support = controllerSupport {
            detachGCEventInteraction(from: view, support: support)
        }
        captureView?.resignFirstResponder()
        attachedView = nil
        captureView = nil
        controllerSupport = nil
    }

    func setModalBlocking(_ blocking: Bool) {
        guard modalBlocking != blocking else { return }
        let wasBlocking = modalBlocking
        modalBlocking = blocking
        if blocking && !wasBlocking {
            controllerSupport?.releaseHeldInputsToHost()
        }
        updateCapturePolicy()
    }

    /// Clears stuck buttons/sticks on the host without pausing capture (e.g. after Alt+Tab).
    func clearHeldGamepadButtonsOnHost() {
        controllerSupport?.releaseHeldInputsToHost()
    }

    /// Suppress gamepad capture briefly after a desktop keyboard chord (picker closes immediately).
    func suppressAfterDesktopAction(for seconds: TimeInterval = 1.35) {
        desktopActionSuppressUntil = Date().addingTimeInterval(seconds)
        controllerSupport?.releaseHeldInputsToHost()
        updateCapturePolicy()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            if let until = self.desktopActionSuppressUntil, Date() >= until {
                self.desktopActionSuppressUntil = nil
            }
            self.updateCapturePolicy()
        }
    }

    func setControllerModeActive(_ active: Bool) {
        guard controllerModeActive != active else { return }
        controllerModeActive = active
        updateCapturePolicy()
    }

    func setStreamActive(_ active: Bool) {
        guard streamActive != active else { return }
        streamActive = active
        if !active {
            deactivateGamepadCapture()
        } else {
            updateCapturePolicy()
        }
    }

    func activateGamepadCapture() {
        guard shouldRunGamepadCapture else { return }

        if let view = captureView, let support = controllerSupport {
            attachGCEventInteraction(to: view, support: support)
        }
        if let view = captureView, !view.isFirstResponder {
            _ = view.becomeFirstResponder()
        }
        // setInputSyncEnabled already reregisters handlers — no separate restore needed
        controllerSupport?.setInputSyncEnabled(true)
        startFocusWatchdogIfNeeded()
    }

    func deactivateGamepadCapture() {
        stopFocusWatchdog()
        controllerSupport?.setInputSyncEnabled(false)
        if let view = attachedView, let support = controllerSupport {
            detachGCEventInteraction(from: view, support: support)
        }
        captureView?.resignFirstResponder()
    }

    func onSceneBecameActive() {
        updateCapturePolicy()
        guard shouldRunGamepadCapture else { return }

        reclaimFirstResponderAggressively()
        // Single intentional handler restore after foreground; reclaim only reclaims focus.
        controllerSupport?.restoreGamepadHandlersAfterForeground()
    }

    private func reclaimFirstResponderAggressively() {
        guard captureView != nil else { return }

        let reclaimFocus = { [weak self] in
            guard let self, self.shouldRunGamepadCapture else { return }
            if let v = self.captureView, !v.isFirstResponder {
                _ = v.becomeFirstResponder()
            }
        }

        reclaimFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { reclaimFocus() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { reclaimFocus() }
    }

    func captureViewDidMoveToWindow() {
        guard shouldRunGamepadCapture else { return }
        // activateGamepadCapture already restores handlers once.
        activateGamepadCapture()
    }

    func captureViewTouchesBegan() {
        guard shouldRunGamepadCapture else { return }
        if let view = captureView, !view.isFirstResponder {
            _ = view.becomeFirstResponder()
        }
    }

    private var isDesktopActionSuppressed: Bool {
        guard let until = desktopActionSuppressUntil else { return false }
        if Date() >= until {
            desktopActionSuppressUntil = nil
            return false
        }
        return true
    }

    private var shouldRunGamepadCapture: Bool {
        guard streamActive, !modalBlocking, !isDesktopActionSuppressed else { return false }
        switch displayStyle {
        case .flat:
            return true
        case .curved:
            return controllerModeActive
        }
    }

    private func updateCapturePolicy() {
        if shouldRunGamepadCapture {
            activateGamepadCapture()
        } else {
            deactivateGamepadCapture()
        }
    }

    private func attachGCEventInteraction(to view: UIView, support: ControllerSupport) {
        guard !gcEventInteractionAttached else { return }
        support.attachGCEventInteraction(to: view)
        gcEventInteractionAttached = true
    }

    private func detachGCEventInteraction(from view: UIView, support: ControllerSupport) {
        guard gcEventInteractionAttached else { return }
        support.detachGCEventInteraction(from: view)
        gcEventInteractionAttached = false
    }

    private func startFocusWatchdogIfNeeded() {
        guard shouldRunGamepadCapture else {
            stopFocusWatchdog()
            return
        }
        guard focusWatchdog == nil else { return }

        focusWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.shouldRunGamepadCapture else { return }
            if let view = self.captureView, !view.isFirstResponder {
                _ = view.becomeFirstResponder()
            }
        }
    }

    private func stopFocusWatchdog() {
        focusWatchdog?.invalidate()
        focusWatchdog = nil
    }
}
