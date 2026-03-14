//
//  UIKitStreamView.swift
//  Moonlight Vision
//
//  Classic Display Mode - UIKit-based streaming with full controls
//  Matches FlatDisplayStreamView features but uses UIKit rendering
//

import SwiftUI
import AVFoundation

// MARK: - Main View

struct UIKitStreamView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.pushWindow) private var pushWindow
    
    @Binding var streamConfig: StreamConfiguration?
    
    var body: some View {
        if let config = streamConfig {
            if config.sessionUUID == viewModel.activeSessionToken {
                _UIKitStreamViewInner(
                    streamConfig: Binding<StreamConfiguration>(
                        get: { config },
                        set: { streamConfig = $0 }
                    )
                )
                .id(config.sessionUUID)
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onAppear {
                        debugLog("👻 Ghost view detected (UUID \(config.sessionUUID) != active \(viewModel.activeSessionToken)). Suppressing.")
                        recoverFromStaleWindow()
                    }
            }
        } else {
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
                print("[ClassicDisplay] Stale window detected - dismissing and opening mainView")
                openWindow(id: "mainView")
                dismissWindow(id: "classicStreamingWindow")
            }
        }
    }
}

// MARK: - Inner Stream View

struct _UIKitStreamViewInner: View {
    @Binding var streamConfig: StreamConfiguration
    
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pushWindow) private var pushWindow
    
    // Co-op coordinator
    @ObservedObject private var coopCoordinator = CoopSessionCoordinator.shared
    
    // Core state
    @State private var hasPerformedTeardown = false
    @State private var hideControls: Bool = true
    @State private var controlsExpanded: Bool = false
    @State private var hideTimer: Timer?
    @State private var controlsHighlighted = false
    @State private var isMenuOpen = false
    @State private var isGazingAtControls = false
    
    // Audio state
    @State private var spatialAudioMode: Bool = true
    @State private var soundStageSize: SoundStageSize = .medium
    
    // Display state
    @State private var dimLevel: Int = UserDefaults.standard.integer(forKey: "ambient.dimming.level")
    @State private var currentAmbientColor: Color = .clear
    @AppStorage("removeRoundedCorners") private var removeRoundedCorners: Bool = false
    
    // Virtual keyboard
    @State private var showVirtualKeyboard = false
    
    // Preset overlay state
    @State private var presetOverlayText: String = ""
    @State private var presetOverlayIcon: String = "camera.filters"
    @State private var showInlinePresetOverlay: Bool = false
    @State private var presetOverlayTimer: Timer?
    @State private var presetCooldownUntil: Date? = nil
    
    // Stats overlay
    @State private var statsOverlayText: String = ""
    @State private var statsTimer: Timer?
    
    // Co-op state
    @State private var inviteButtonSent: Bool = false
    @State private var showDisconnectConfirm: Bool = false
    
    // Stream lifecycle
    @State private var streamEpoch: Int = 0
    @State private var firstFrameSeen = false
    @State private var firstFrameSeenEpoch: Int = -1
    @State private var idrWatchdogScheduled = false
    @State private var guestAggressiveIDRTimer: Timer?
    @State private var needsResume = false
    @State private var streamVC: StreamFrameViewController?
    @State private var startingStream = false
    
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    
    var body: some View {
        let mainContent = ZStack {
            // Ambient glow effect
            if dimLevel == 2 {
                let glow = currentAmbientColor
                LinearGradient(
                    colors: [glow.opacity(0.28), glow.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blur(radius: 30)
                .ignoresSafeArea()
            }
            
            // UIKit stream view - now persistent, stream lifecycle managed externally
            _UIKitStreamView(
                streamConfig: $streamConfig,
                streamVC: $streamVC
            )
            .clipShape(RoundedRectangle(cornerRadius: removeRoundedCorners ? 0 : CGFloat(streamConfig.width) * 0.006, style: .continuous))
            
            // Preset popup overlay
            if showInlinePresetOverlay {
                CenterPresetPopup(text: presetOverlayText, icon: presetOverlayIcon)
                    .scaleEffect(0.65)
                    .offset(z: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                    .allowsHitTesting(false)
            }
            
            // Co-op join notification
            if coopCoordinator.friendJoinedNotification {
                CenterPresetPopup(text: "Guest Joined!", icon: "person.badge.plus.fill")
                    .scaleEffect(0.65)
                    .offset(z: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                    .allowsHitTesting(false)
            }
            
            // Co-op disconnect notification
            if coopCoordinator.disconnectNotification {
                CenterPresetPopup(text: coopCoordinator.disconnectMessage, icon: "person.badge.minus.fill")
                    .scaleEffect(0.65)
                    .offset(z: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                    .allowsHitTesting(false)
            }
            
            // Co-op connecting overlay (for guests)
            if viewModel.isCoopSession && viewModel.assignedControllerSlot == 1 && viewModel.streamState == .starting {
                CoopConnectingPopup()
                    .scaleEffect(0.65)
                    .offset(z: 150)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            
            // Disconnect confirmation dialog
            if showDisconnectConfirm {
                disconnectConfirmationOverlay
            }
        }
        .preferredSurroundingsEffect(dimLevel == 0 ? nil : .systemDark)
        .persistentSystemOverlays(hideControls ? .hidden : .visible)
        
        // Ornaments applied AFTER persistentSystemOverlays so they aren't affected by it
        return mainContent
            .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
                topControlsBar
                    .padding(.bottom, 8)
            }
            .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
                bottomOrnaments
            }
        .onAppear {
            setupScene()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ambientAverageColorUpdated)) { notif in
            handleAmbientColorUpdate(notif)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StreamFirstFrameShownNotification"))) { _ in
            if firstFrameSeenEpoch != streamEpoch {
                print("[ClassicDisplay] First frame observed; epoch=\(streamEpoch)")
                firstFrameSeen = true
                firstFrameSeenEpoch = streamEpoch
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StreamDidTeardownNotification"))) { _ in
            // Ungate the serializer — LiStopConnection() has truly finished.
            ConnectionSerializer.shared.notifyStopComplete()

            // Ignore teardown notification during background suspend
            guard !viewModel.isSuspendingForBackground else {
                print("[ClassicDisplay] Ignoring StreamDidTeardownNotification — suspending for background")
                return
            }

            // Prevent "presentation deallocated" crash by dismissing active Moonlight error alerts
            if let vc = _UIKitStreamView.controllerReference.object, let presented = vc.presentedViewController {
                presented.dismiss(animated: false)
            }

            dismissWindow(id: "classicStreamingWindow")
            _UIKitStreamView.controllerReference.object = nil
            firstFrameSeen = false
            idrWatchdogScheduled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeStreamFromMenu)) { _ in
            handleResume()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mainViewWindowClosed)) { _ in
            isMenuOpen = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fixAudioForCurrentMode()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { LiRequestIdrFrame() }
        }
        .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
            if shouldClose && !hasPerformedTeardown {
                DispatchQueue.main.async {
                    print("[ClassicDisplay] ViewModel requested teardown.")
                    tearDownStream()
                }
            }
        }
        .onChange(of: viewModel.streamSettings.statsOverlay) { _, newValue in
            if newValue {
                startStatsTimer()
            } else {
                statsTimer?.invalidate()
                statsTimer = nil
                statsOverlayText = ""
            }
        }
        .onChange(of: viewModel.activelyStreaming) { _, newValue in
            if !newValue && !hasPerformedTeardown {
                print("[ClassicDisplay] activelyStreaming became false - tearing down")
                tearDownStream()
            }
        }
        .onDisappear {
            hideControls = true
            hideTimer?.invalidate()
            statsTimer?.invalidate()
            guestAggressiveIDRTimer?.invalidate()
            
            // Don't tear down if we're just pausing for resume
            guard !needsResume else { return }
            
            if !hasPerformedTeardown && viewModel.activelyStreaming {
                print("[ClassicDisplay] onDisappear teardown (safety net).")
                tearDownStream()
            }
        }
    }
    
    // MARK: - Top Controls Bar
    
    /// Center button: tap to expand the dynamic menu.
    private var uikitCollapsedControlsView: some View {
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
                uikitDynamicControlsBar
                    .opacity(!hideControls ? (controlsHighlighted ? 1.0 : 0.5) : 0.05)
                    .animation(Animation.easeInOut(duration: 0.25), value: controlsHighlighted)
                    .animation(Animation.easeInOut(duration: 0.25), value: hideControls)
                    .allowsHitTesting(true)
                    .onHover { hovering in
                        isGazingAtControls = hovering
                        if hovering { startHideTimer() }
                    }
            } else {
                uikitOriginalControlsBar
            }
        }
    }
    
    /// Dynamic bar: collapsed = center only (no pill); expanded = full bar with pill. Both branches animate opacity/scale for smooth expand and collapse.
    private var uikitDynamicControlsBar: some View {
        ZStack {
            uikitCollapsedControlsView
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .opacity(controlsExpanded ? 0 : 1)
                .scaleEffect(controlsExpanded ? 0.88 : 1)
                .allowsHitTesting(!controlsExpanded)
            uikitControlsBarContent
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .opacity(controlsExpanded ? 1 : 0)
                .scaleEffect(controlsExpanded ? 1 : 0.88)
                .allowsHitTesting(controlsExpanded)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: controlsExpanded)
    }
    
    private var uikitOriginalControlsBar: some View {
        uikitControlsBarContent
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
        .opacity(!hideControls ? (controlsHighlighted ? 1.0 : 0.5) : 0.05)
        .animation(Animation.easeInOut(duration: 0.25), value: controlsHighlighted)
        .animation(Animation.easeInOut(duration: 0.25), value: hideControls)
        .allowsHitTesting(true)
        .onHover { hovering in
            isGazingAtControls = hovering
            if hovering { startHideTimer() }
        }
    }
    
    private var uikitControlsBarContent: some View {
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
                showPresetOverlay()
                startHideTimer()
            } label: {
                Label(spatialAudioMode ? "Spatial Audio" : "Direct Audio", systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones")
                    .font(.system(size: 24.07))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(width: 50, height: 50)
            }
            .labelStyle(.iconOnly)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        guard spatialAudioMode else { return }
                        soundStageSize = soundStageSize.next()
                        fixAudioForCurrentMode()
                        presetOverlayText = "Sound Stage: \(soundStageSize.rawValue)"
                        presetOverlayIcon = "person.spatialaudio.fill"
                        showPresetOverlay()
                    }
            )
            makeControlButton(label: "Dim", systemImage: dimLevel == 0 ? "lightbulb.fill" : "lightbulb") {
                dimLevel = dimLevel == 0 ? 1 : 0
                UserDefaults.standard.set(dimLevel, forKey: "ambient.dimming.level")
                viewModel.streamSettings.dimPassthrough = (dimLevel != 0)
                presetOverlayText = dimLevel == 0 ? "Dimming: Off" : "Dimming: On"
                presetOverlayIcon = dimLevel == 0 ? "lightbulb.fill" : "lightbulb"
                showPresetOverlay()
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
                if let streamVC = _UIKitStreamView.controllerReference.object {
                    let isNowVisible = streamVC.toggleKeyboard()
                    showVirtualKeyboard = isNowVisible
                }
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
            if viewModel.isCoopSession {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("2P")
                        .font(.system(size: 14, weight: .bold))
                    Text("(\(coopCoordinator.participants.count)/2)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .fixedSize()
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.3))
                )
            }
            if viewModel.isCoopSession, coopCoordinator.isHosting, coopCoordinator.participants.count < 2 {
                coopInviteButton
            }
            if viewModel.isCoopSession {
                coopDisconnectButton
            }
        }
    }

    // MARK: - Bottom Ornaments
    
    @ViewBuilder
    private var bottomOrnaments: some View {
        VStack(spacing: 12) {
            // Stats overlay
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
                        .fill(brandNavy.opacity(0.92))
                )
                .allowsHitTesting(false)
            }
            
            // Floating mic button
            if viewModel.streamSettings.showMicButton {
                FloatingMicButton()
            }
        }
    }
    
    // MARK: - Control Button Helper
    
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
    
    // MARK: - Co-op Buttons
    
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
            
            Task {
                await coopCoordinator.reInviteGuest()
            }
            
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
    
    // MARK: - Disconnect Confirmation Overlay
    
    private var disconnectConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
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
                            viewModel.userDidRequestDisconnect()
                            openWindow(id: "mainView")
                            dismissWindow(id: "classicStreamingWindow")
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
    
    // MARK: - Lifecycle
    
    private func setupScene() {
        hasPerformedTeardown = false
        hideControls = false
        spatialAudioMode = true
        dismissWindow(id: "mainView")
        
        var stored = UserDefaults.standard.integer(forKey: "ambient.dimming.level")
        if stored > 2 { stored = 2; UserDefaults.standard.set(stored, forKey: "ambient.dimming.level") }
        dimLevel = stored
        viewModel.streamSettings.dimPassthrough = (dimLevel != 0)
        
        viewModel.isStreamViewAlive = true
        
        // Load saved control mode preference for Classic (separate from Flat)
        viewModel.streamSettings.absoluteTouchMode = UserDefaults.standard.bool(forKey: "classic.absoluteTouchMode")
        
        firstFrameSeen = false
        idrWatchdogScheduled = false
        streamEpoch += 1
        kickFirstFrameWatchdog()
        
        // Start the stream after a short delay to let the view controller set up
        startStreamIfNeeded()
        
        // Start aggressive IDR for co-op guests
        if viewModel.isCoopSession && viewModel.assignedControllerSlot == 1 {
            startGuestAggressiveIDR()
        }
        
        if viewModel.streamSettings.statsOverlay {
            startStatsTimer()
        }
        
        // Apply aspect ratio lock early (before stream connects) to prevent visible resize
        // This matches Flat Display's behavior
        applyAspectRatioLockIfReady()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            startHideTimer()
        }
    }
    
    // MARK: - Stream Management (mirrors FlatDisplayStreamView pattern)
    
    private func startStreamIfNeeded() {
        guard !startingStream else {
            print("[ClassicDisplay] Stream start skipped (already starting)")
            return
        }
        
        startingStream = true
        
        // Wait for the view controller to be ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !self.hasPerformedTeardown, self.viewModel.activelyStreaming else {
                print("[ClassicDisplay] Aborting stream start - Teardown: \(self.hasPerformedTeardown), Streaming: \(self.viewModel.activelyStreaming)")
                self.startingStream = false
                return
            }
            
            guard let vc = self.streamVC else {
                print("[ClassicDisplay] ⚠️ Stream VC not ready, retrying...")
                self.startingStream = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.startStreamIfNeeded()
                }
                return
            }
            
            // Check if stream is already active
            if vc.isStreamActive() {
                print("[ClassicDisplay] Stream already active, skipping start")
                self.startingStream = false
                return
            }
            
            print("[ClassicDisplay] 🚀 Starting stream (epoch \(self.streamEpoch))")
            vc.startStreamExternal()
            self.startingStream = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { LiRequestIdrFrame() }
        }
    }
    
    private func stopStreamExternal() {
        guard let vc = streamVC, vc.isStreamActive() else {
            print("[ClassicDisplay] stopStreamExternal: no active stream")
            return
        }

        print("[ClassicDisplay] 🛑 Stopping stream externally")
        // Tell the serializer a stop is beginning — no new connection can start until
        // the completion fires in StreamFrameViewController.stopStreamExternal.
        ConnectionSerializer.shared.notifyStopBegun()
        vc.stopStreamExternal()
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            prepareForBackground()
        case .active:
            resumeIfNeeded()
        default:
            break
        }
    }
    
    private func prepareForBackground() {
        guard !hasPerformedTeardown else { return }
        guard viewModel.activelyStreaming else { return }
        
        print("[ClassicDisplay] Preparing for background - stopping stream externally")
        needsResume = true
        viewModel.isSuspendingForBackground = true
        
        // Ensure we don't accidentally tear down if the view disappears while backgrounded
        hasPerformedTeardown = false
        
        // Stop stream using the new external control method (view persists)
        stopStreamExternal()
    }
    
    private func resumeIfNeeded() {
        guard needsResume else {
            // Standard active handling when not resuming
            if viewModel.activelyStreaming {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    fixAudioForCurrentMode()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { LiRequestIdrFrame() }
            }
            return
        }

        print("[ClassicDisplay] Resuming from background - restarting stream externally")
        viewModel.isSuspendingForBackground = false
        needsResume = false
        hasPerformedTeardown = false
        
        // Re-arm the view model state so the stream knows it should be active
        viewModel.activelyStreaming = true
        viewModel.streamState = .starting
        
        // Reset stream epoch for first-frame detection
        firstFrameSeen = false
        streamEpoch += 1
        
        // Restart stream using the existing view controller (view persists, only stream restarts)
        startStreamIfNeeded()

        // Wait slightly longer for the new view controller to be fully mounted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            fixAudioForCurrentMode()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { LiRequestIdrFrame() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { LiRequestIdrFrame() }
    }
    
    private func handleAmbientColorUpdate(_ notif: Notification) {
        if dimLevel == 2 {
            if let r = notif.userInfo?["r"] as? Float,
               let g = notif.userInfo?["g"] as? Float,
               let b = notif.userInfo?["b"] as? Float {
                let boostedR = min(1.0, max(0.0, r * 1.5))
                let boostedG = min(1.0, max(0.0, g * 1.5))
                let boostedB = min(1.0, max(0.0, b * 1.5))
                currentAmbientColor = Color(red: Double(boostedR), green: Double(boostedG), blue: Double(boostedB))
            }
        }
    }
    
    private func handleResume() {
        print("[ClassicDisplay] handleResume: Called (activelyStreaming: \(viewModel.activelyStreaming), needsResume: \(needsResume))")
        
        // CRITICAL FIX: Match Curved Display's safety check
        // If stream isn't active, we need a full relaunch instead of just resuming
        guard viewModel.activelyStreaming else {
            print("[ClassicDisplay] handleResume: Stream not active - triggering relaunch via shouldRelaunchStream")
            dismissWindow(id: "mainView")
            viewModel.shouldRelaunchStream = true
            return
        }
        
        dismissWindow(id: "mainView")
        isMenuOpen = false
        withAnimation(.easeInOut(duration: 0.3)) {
            hideControls = false
            controlsHighlighted = true
        }
        startHighlightTimer()
        
        // If the stream was stopped due to backgrounding, restart it using the existing view controller
        if needsResume {
            print("[ClassicDisplay] handleResume: Stream was backgrounded, restarting stream externally")
            viewModel.isSuspendingForBackground = false
            needsResume = false
            hasPerformedTeardown = false
            
            // Re-arm the view model state so the stream knows it should be active
            viewModel.activelyStreaming = true
            viewModel.streamState = .starting
            
            // Reset stream epoch for first-frame detection
            firstFrameSeen = false
            streamEpoch += 1
            
            // Restart stream using the existing view controller (view persists, only stream restarts)
            startStreamIfNeeded()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fixAudioForCurrentMode()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { LiRequestIdrFrame() }
        } else {
            // Stream is already running, just fix audio and request IDR
            fixAudioForCurrentMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { LiRequestIdrFrame() }
        }
    }
    
    private func tearDownStream() {
        guard !hasPerformedTeardown else { return }
        hasPerformedTeardown = true
        
        print("[ClassicDisplay] Tearing down stream using external control...")
        
        statsTimer?.invalidate()
        guestAggressiveIDRTimer?.invalidate()
        viewModel.isStreamViewAlive = false
        
        // Use the new external stream control method
        stopStreamExternal()
    }
    
    // MARK: - Helper Functions
    
    private func fixAudioForCurrentMode() {
        if spatialAudioMode {
            AudioHelpers.fixAudioForSurroundForCurrentWindow(soundStageSize: soundStageSize)
        } else {
            AudioHelpers.fixAudioForDirectStereo()
        }
    }
    
    private func showPresetOverlay() {
        showInlinePresetOverlay = true
        
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
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
            if let controller = _UIKitStreamView.controllerReference.object {
                statsOverlayText = controller.getStatsOverlayText() ?? "No stats available"
            }
        }
    }
    
    private func kickFirstFrameWatchdog() {
        guard !idrWatchdogScheduled else { return }
        idrWatchdogScheduled = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !firstFrameSeen { LiRequestIdrFrame() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if !firstFrameSeen { LiRequestIdrFrame() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if !firstFrameSeen { LiRequestIdrFrame() }
        }
    }
    
    private func startGuestAggressiveIDR() {
        print("[ClassicDisplay] CO-OP GUEST: Starting aggressive IDR requesting")
        var requestCount = 0
        let maxRequests = 120
        
        guestAggressiveIDRTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            requestCount += 1
            if firstFrameSeen {
                print("[ClassicDisplay] CO-OP GUEST: First frame received! Stopping IDR requests after \(requestCount) requests")
                timer.invalidate()
                guestAggressiveIDRTimer = nil
                return
            }
            if requestCount > maxRequests {
                print("[ClassicDisplay] CO-OP GUEST: Max IDR requests reached (\(maxRequests)), stopping")
                timer.invalidate()
                guestAggressiveIDRTimer = nil
                return
            }
            print("[ClassicDisplay] CO-OP GUEST: Requesting IDR frame #\(requestCount)")
            LiRequestIdrFrame()
        }
    }
    
    private func sendTaskManager() {
        DispatchQueue.global(qos: .userInteractive).async {
            let MODIFIER_CTRL: Int8 = 0x02
            let MODIFIER_SHIFT: Int8 = 0x01
            let modifiers = MODIFIER_CTRL | MODIFIER_SHIFT
            let ESC_KEY: Int16 = 0x1B
            
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | ESC_KEY, 0x03, modifiers)
            usleep(50 * 1000)
            LiSendKeyboardEvent(Int16(bitPattern: 0x8000) | ESC_KEY, 0x04, modifiers)
        }
    }
    
    private func applyAspectRatioLockIfReady() {
        // Try to get the window from the controller reference
        guard let streamVC = _UIKitStreamView.controllerReference.object else {
            // Controller not ready yet, retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.applyAspectRatioLockIfReady()
            }
            return
        }
        
        guard let window = streamVC.view.window ?? streamVC.view?.superview?.window else {
            // Window not ready yet, retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.applyAspectRatioLockIfReady()
            }
            return
        }
        
        // Window is ready, apply the aspect ratio lock
        applyAspectRatioLock(streamConfiguration: streamConfig, targetWindow: window)
    }
}

// MARK: - UIKit Stream View Wrapper

struct _UIKitStreamView: UIViewControllerRepresentable {
    typealias UIViewControllerType = StreamFrameViewController
    
    @Binding var streamConfig: StreamConfiguration
    @Binding var streamVC: StreamFrameViewController?
    static let controllerReference = Reference<UIViewControllerType>()
    
    static var reference: Reference<UIViewControllerType> {
        return controllerReference
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        let vc = StreamFrameViewController()
        vc.streamConfig = streamConfig
        
        // Enable view-only mode - stream lifecycle managed by Swift
        vc.setViewOnlyMode(true)
        
        vc.connectedCallback = {
            print("[ClassicDisplay] Connected!")
            AudioHelpers.fixAudioForSurroundForCurrentWindow()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { LiRequestIdrFrame() }
        }
        vc.disconnectedCallback = {
            print("[ClassicDisplay] Disconnected!")
        }
        
        _UIKitStreamView.controllerReference.object = vc
        
        // Pass the controller reference back to Swift for stream control
        DispatchQueue.main.async {
            self.streamVC = vc
        }
        
        return vc
    }
    
    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) {
        viewController.streamConfig = streamConfig
        _UIKitStreamView.controllerReference.object = viewController
    }
    
    static func dismantleUIViewController(_ uiViewController: StreamFrameViewController, coordinator: ()) {
        // Stream lifecycle is managed by Swift - just clean up the reference
        print("[ClassicDisplay] dismantleUIViewController - cleaning up reference")
        _UIKitStreamView.controllerReference.object = nil
    }
}

// MARK: - Reference Helper

class Reference<T: AnyObject> {
    weak var object: T?
}

// MARK: - Aspect Ratio Lock

func applyAspectRatioLock(streamConfiguration: StreamConfiguration, targetWindow: UIWindow?) {
    guard let window = targetWindow else {
        print("Error: No target window provided to apply aspect ratio lock.")
        return
    }
    
    let streamWidth = CGFloat(streamConfiguration.width)
    let streamHeight = CGFloat(streamConfiguration.height)
    let streamAspectRatio = streamWidth / streamHeight
    
    print("[ClassicDisplay] Applying Aspect Ratio Lock - Stream: \(Int(streamWidth))x\(Int(streamHeight)), AR: \(String(format: "%.3f", streamAspectRatio))")
    
    let maxWidth: CGFloat = 2000
    var desiredSize = CGSize.zero
    
    for desiredWidthInt in (1...Int(maxWidth)).reversed() {
        let desiredWidth = CGFloat(desiredWidthInt)
        let desiredHeightFloat = desiredWidth / streamAspectRatio
        let desiredHeightInt = Int(round(desiredHeightFloat))
        
        if desiredHeightInt > 0 {
            desiredSize = CGSize(width: desiredWidth, height: CGFloat(desiredHeightInt))
            break
        }
    }
    
    guard let windowScene = window.windowScene else {
        print("Error: Could not get window scene from target window.")
        return
    }
    
    #if os(visionOS)
    if windowScene.activationState != .foregroundActive {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            applyAspectRatioLock(streamConfiguration: streamConfiguration, targetWindow: targetWindow)
        }
        return
    }
    #endif
    
    let geometryRequest = UIWindowScene.GeometryPreferences.Vision(
        size: desiredSize,
        resizingRestrictions: .uniform
    )
    
    windowScene.requestGeometryUpdate(geometryRequest)
}
