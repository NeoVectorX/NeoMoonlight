//
//  UIKitStreamView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/27/24.
//  Copyright © 2024 Moonlight Game Streaming Project.
//

import SwiftUI
import AVFoundation

struct UIKitStreamView: View {
    @Binding var streamConfig: StreamConfiguration?

    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasPerformedTeardown = false
    @State private var hideOrnament = false
    @State private var hideTimer: Timer?
    @State private var spatialAudioMode: Bool = true
    @State private var controlsHighlighted = false
    @State private var showSwapOverlay = false
    @State private var swapInProgress = false
    @State private var showSwapConfirm = false
    @State private var dimLevel: Int = UserDefaults.standard.integer(forKey: "ambient.dimming.level")

    // Preset overlay state
    @State private var presetOverlayText: String = ""
    @State private var showPresetOverlay: Bool = false
    @State private var showInlinePresetOverlay: Bool = false
    @State private var presetOverlayTimer: Timer?
    @State private var presetCooldownUntil: Date? = nil

    @State private var isGazingAtControls = false

    @State private var currentAmbientColor: Color = .clear

    @State private var firstFrameSeen = false
    @State private var idrWatchdogScheduled = false

    // Profiles: Default, Cinematic, Vivid, Realistic
    private func presetName(_ v: Int32) -> String {
        switch v {
        case 0: return "Default"
        case 1: return "Cinematic"
        case 2: return "Vivid"
        case 3: return "Realistic"
        default: return "Default"
        }
    }

    private func applyUIKitPreset(_ value: Int32) {
        guard canChangePreset() else {
            print("[UIKitStream] Preset change on cooldown, ignoring")
            return
        }
        
        viewModel.streamSettings.uikitPreset = value
        if let controller = _UIKitStreamView.controllerReference.object {
            controller.applyUIKitPreset(value)
        }
        
        presetCooldownUntil = Date().addingTimeInterval(0.5)
        showPresetOverlay(preset: value)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            LiRequestIdrFrame()
        }
        
        startHideTimer()
    }

    private func nextUIKitPreset(_ current: Int32) -> Int32 {
        let all: [Int32] = [0, 1, 2, 3]
        if let idx = all.firstIndex(of: current) {
            return all[(idx + 1) % all.count]
        }
        return 0
    }

    private func canChangePreset() -> Bool {
        guard let cooldownUntil = presetCooldownUntil else { return true }
        return Date() >= cooldownUntil
    }

    private func showPresetOverlay(preset: Int32) {
        presetOverlayText = presetName(preset)
        showInlinePresetOverlay = true
        
        presetOverlayTimer?.invalidate()
        presetOverlayTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showInlinePresetOverlay = false
            }
        }
    }

    var body: some View {
        Group {
            if let configBinding = Binding($streamConfig) {
                ZStack {
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

                    _UIKitStreamView(streamConfig: configBinding)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .preferredSurroundingsEffect(dimLevel == 0 ? nil : .systemDark)
                        .persistentSystemOverlays(hideOrnament ? .hidden : .visible)
                        .ornament(attachmentAnchor: .scene(.top), contentAlignment: .bottom) {
                            HStack {
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
                                    // KEEP: Show main menu in front of the live stream
                                    pushWindow(id: "mainView")
                                    controlsHighlighted = true
                                    hideTimer?.invalidate()
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
                                    let next = (dimLevel == 0) ? 1 : 0
                                    dimLevel = next
                                    UserDefaults.standard.set(dimLevel, forKey: "ambient.dimming.level")
                                    viewModel.streamSettings.dimPassthrough = (dimLevel != 0)
                                    startHideTimer()
                                } label: {
                                    let title: String = {
                                        switch dimLevel {
                                        case 0: return "Dim: Off"
                                        case 1: return "Dim: Night"
                                        default: return "Dim: Off"
                                        }
                                    }()
                                    let icon: String = (dimLevel == 0) ? "moon" : "moon.fill"
                                    Label(title, systemImage: icon)
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
                                    
                                    let next = nextUIKitPreset(viewModel.streamSettings.uikitPreset)
                                    applyUIKitPreset(next)
                                } label: {
                                    Label("Preset", systemImage: "camera.filters")
                                }
                                .labelStyle(.iconOnly)

//                                Button {
//                                    if hideOrnament && !controlsHighlighted {
//                                        withAnimation(.easeInOut(duration: 0.3)) {
//                                            hideOrnament = false
//                                            controlsHighlighted = true
//                                            hideTimer?.invalidate()
//                                            startHighlightTimer()
//                                        }
//                                        return
//                                    }
//                                    hideTimer?.invalidate()
//                                    controlsHighlighted = true
//                                    showSwapConfirm = true
//                                } label: {
//                                    Label("Swap", systemImage: "rectangle.2.swap")
//                                }
//                                .labelStyle(.iconOnly)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.001))
                            .opacity((isGazingAtControls || !hideOrnament) ? 1.0 : 0.05)
                            .conditionalGlass(isGazingAtControls || !hideOrnament)
                            .animation(.easeInOut(duration: 0.25), value: isGazingAtControls)
                            .animation(.easeInOut(duration: 0.25), value: hideOrnament)
                            .onHover { hovering in
                                isGazingAtControls = hovering
                                if hovering { startHideTimer() }
                            }
                            // Keep interactive even when ghosted
                            .allowsHitTesting(true)
                        }
                        .onAppear {
                            NotificationCenter.default.addObserver(
                                forName: Notification.Name("ResumeStreamFromMenu"),
                                object: nil,
                                queue: .main
                            ) { _ in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    controlsHighlighted = true
                                    hideOrnament = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    if self.spatialAudioMode {
                                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                                    } else {
                                        AudioHelpers.fixAudioForDirectStereo()
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { LiRequestIdrFrame() }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    dismissWindow(id: "mainView")
                                    controlsHighlighted = false
                                    startHideTimer()
                                }
                            }

                            NotificationCenter.default.addObserver(
                                forName: Notification.Name("MainViewWindowClosed"),
                                object: nil,
                                queue: .main
                            ) { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    if self.spatialAudioMode {
                                        AudioHelpers.fixAudioForSurroundForCurrentWindow()
                                    } else {
                                        AudioHelpers.fixAudioForDirectStereo()
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { LiRequestIdrFrame() }
                            }

                            hasPerformedTeardown = false
                            hideOrnament = false
                            spatialAudioMode = true
                            dismissWindow(id: "mainView")
                            
                            var stored = UserDefaults.standard.integer(forKey: "ambient.dimming.level")
                            if stored > 2 { stored = 2; UserDefaults.standard.set(stored, forKey: "ambient.dimming.level") }
                            dimLevel = stored
                            viewModel.streamSettings.dimPassthrough = (dimLevel != 0)

                            firstFrameSeen = false
                            idrWatchdogScheduled = false
                            kickFirstFrameWatchdog()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                startHideTimer()
                            }
                        }
                        .onChange(of: scenePhase) { _, phase in
                            switch phase {
                            case .active:
                                if streamConfig != nil {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        if self.spatialAudioMode {
                                            AudioHelpers.fixAudioForSurroundForCurrentWindow()
                                        } else {
                                            AudioHelpers.fixAudioForDirectStereo()
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { LiRequestIdrFrame() }
                                }
                            default:
                                break
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .ambientAverageColorUpdated)) { notif in
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
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StreamDidTeardownNotification"))) { _ in
                            dismissWindow(id: "classicStreamingWindow")
                            _UIKitStreamView.controllerReference.object = nil

                            firstFrameSeen = false
                            idrWatchdogScheduled = false
                        }
                        .onChange(of: viewModel.shouldCloseStream) { _, shouldClose in
                            if shouldClose && !hasPerformedTeardown {
                                print("[UIKitStreamView] ViewModel requested teardown.")
                                tearDownStream()
                            }
                        }
                        .onDisappear {
                            hideOrnament = false
                            hideTimer?.invalidate()
                            NotificationCenter.default.removeObserver(self)
                            
                            if !hasPerformedTeardown && streamConfig != nil {
                                print("[UIKitStreamView] onDisappear teardown (safety net).")
                                tearDownStream()
                            }
                        }
                    
                    // The 'isSwappingRenderers' flag provides a visual indicator during the swap
                    if viewModel.isSwappingRenderers {
                        let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
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
                    }
                    
                    if showSwapConfirm {
                        let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
                        let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
                        
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            
                            VStack(spacing: 24) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [brandViolet, brandPurple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                                    Text("This will stop the current stream and reconnect in Curved Display.")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 8)
                                }
                                
                                VStack(spacing: 12) {
                                    Button {
                                        showSwapConfirm = false
                                        Task {
                                            await viewModel.performRendererSwap(
                                                openWindow: openWindow,
                                                openImmersiveSpace: openImmersiveSpace,
                                                dismissWindow: dismissWindow
                                            )
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "rectangle.2.swap")
                                                .font(.system(size: 18, weight: .semibold))
                                            Text("Swap to Curved Display")
                                                .font(.system(size: 17, weight: .semibold))
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [brandViolet, brandPurple.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
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
                                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(28)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                            )
                            .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 16)
                            .frame(width: 400)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }

                    // CENTER-STAGE PRESET POPUP (matches brand blue/glow)
                    if showInlinePresetOverlay {
                        PresetPopupView(text: presetOverlayText)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                    }
                }
            } else {
                Color.clear
                    .onAppear {
                        if viewModel.streamState == .idle {
                            dismissWindow(id: "classicStreamingWindow")
                            _UIKitStreamView.controllerReference.object = nil
                        }
                    }
            }
        }
    }
    
    private func tearDownStream() {
        guard !hasPerformedTeardown else { return }
        hasPerformedTeardown = true
        
        print("[UIKitStreamView] Tearing down stream by calling native stopStream...")
        
        if let streamVC = _UIKitStreamView.controllerReference.object {
            streamVC.stopStream()
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

    private func kickFirstFrameWatchdog() {
        guard !idrWatchdogScheduled else { return }
        idrWatchdogScheduled = true

        // Gentle nudges shortly after connect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !firstFrameSeen {
                LiRequestIdrFrame()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if !firstFrameSeen {
                LiRequestIdrFrame()
            }
        }
        // One last retry; if this still doesn’t resolve, the core stack will terminate/alert on its own
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if !firstFrameSeen {
                LiRequestIdrFrame()
            }
        }
    }
}

struct _UIKitStreamView: UIViewControllerRepresentable {
    typealias UIViewControllerType = StreamFrameViewController

    @Binding var streamConfig: StreamConfiguration
    static let controllerReference = Reference<UIViewControllerType>()

    static var reference: Reference<UIViewControllerType> {
        return controllerReference
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let streamView = StreamFrameViewController()
        streamView.streamConfig = streamConfig
        streamView.connectedCallback = { [weak streamView] in
            print("Connected in Swift!")
            AudioHelpers.fixAudioForSurroundForCurrentWindow()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = streamView?.view.window ?? streamView?.view?.superview?.window else { return }
                applyAspectRatioLock(streamConfiguration: streamConfig, targetWindow: window)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { LiRequestIdrFrame() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { LiRequestIdrFrame() }
        };
        streamView.disconnectedCallback = {
            print("Disconnected in Swift!")
        };
        _UIKitStreamView.controllerReference.object = streamView
        return streamView
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) {
        viewController.streamConfig = streamConfig
        _UIKitStreamView.controllerReference.object = viewController
    }

    static func dismantleUIViewController(_ uiViewController: StreamFrameViewController, coordinator: ()) {
        uiViewController.stopStream()
        _UIKitStreamView.controllerReference.object = nil
        NotificationCenter.default.post(name: Notification.Name("StreamControllerDismantled"), object: nil)
    }
}

class Reference<T: AnyObject> {
    weak var object: T?
}

func applyAspectRatioLock(streamConfiguration: StreamConfiguration, targetWindow: UIWindow?) {
    guard let window = targetWindow else {
        print("Error: No target window provided to apply aspect ratio lock.")
        return
    }

    let streamWidth = CGFloat(streamConfiguration.width)
    let streamHeight = CGFloat(streamConfiguration.height)
    let streamAspectRatio = streamWidth / streamHeight

    print("Applying Aspect Ratio Lock - Stream Width: \(streamWidth), Stream Height: \(streamHeight), Stream AR: \(streamAspectRatio)")

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

private struct PresetPopupView: View {
    var text: String
    
    var body: some View {
        let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
        let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
        let radius: CGFloat = 18
        let pillWidth: CGFloat = 240
        let pillHeight: CGFloat = 56
        
        HStack(spacing: 10) {
            Image(systemName: "camera.filters")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [brandOrange, brandOrange.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(text)
                .font(.custom("Fredoka-SemiBold", size: 20))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(width: pillWidth, height: pillHeight, alignment: .center)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(brandNavy.opacity(0.85))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.3))
            }
        )
        .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [brandOrange.opacity(0.5), brandOrange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .compositingGroup()
        .shadow(color: brandOrange.opacity(0.4), radius: 20, x: 0, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private func positionMainMenuWindowInFrontOfStream() {
    guard let streamingWindow = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }) else {
        print("Could not find streaming window!")
        return
    }

    let windowScene = streamingWindow.windowScene

    windowScene?.requestGeometryUpdate(
        UIWindowScene.GeometryPreferences.Vision(
            size: CGSize(width: 700, height: 920),
            resizingRestrictions: .uniform
        )
    )
}