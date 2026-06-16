//
//  FloatingMicButton.swift
//  Neo Moonlight
//
//  Glass pill with custom mute PNG (MicMute-UnMuted / MicMute-Muted).
//  Tap = mic mute only. Long-press = mic mute + game audio dim.
//

import SwiftUI

/// Sizing aligned to curved/flat top stream controls.
enum StreamMicBarMetrics {
    static let tapSize: CGFloat = 50
    /// MicMute PNGs are capsule art (417×112); height matches top-bar tap targets.
    static let muteAssetAspect: CGFloat = 417.0 / 112.0
    static var muteAssetWidth: CGFloat { tapSize * muteAssetAspect }
    static let barHorizontalPadding: CGFloat = 24
    static let barVerticalPadding: CGFloat = 12
}

enum MicButtonColorStyle: String, CaseIterable, Identifiable {
    case white = "white"
    case greenRed = "greenRed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .greenRed: return "Green / Red"
        }
    }

    static func from(raw: String) -> MicButtonColorStyle {
        MicButtonColorStyle(rawValue: raw) ?? .white
    }

    func assetName(isMuted: Bool, isDimmed: Bool) -> String {
        if isDimmed { return "MicMute-Reduced3" }
        switch self {
        case .white:
            return isMuted ? "MicMute-Muted" : "MicMute-UnMuted"
        case .greenRed:
            return isMuted ? "MicMute-Muted-Red" : "MicMute-UnMuted-Green"
        }
    }
}

// MARK: - Mic chrome fade (independent timer, matches top-bar opacity levels)

enum MicChromeFadeStyle {
    case flat
    case classic
    case curved
}

@MainActor
final class MicChromeFadeController: ObservableObject {
    @Published var hideControls: Bool
    @Published var controlsHighlighted: Bool = false

    private let style: MicChromeFadeStyle
    private var fadeTimer: Timer?

    init(style: MicChromeFadeStyle) {
        self.style = style
        switch style {
        case .flat:
            hideControls = true
        case .classic, .curved:
            hideControls = false
        }
    }

    func invalidate() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    /// Curved first-frame behavior — mirrors `startHideTimer()` on the top bar.
    func streamControlsShown() {
        guard style == .curved else { return }
        hideControls = false
        controlsHighlighted = true
        scheduleHideFade()
    }

    /// Classic stream setup — mirrors delayed `startHideTimer()` after 3s.
    func scheduleClassicInitialFade() {
        guard style == .classic else { return }
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleHideFade()
            }
        }
    }

    /// After a mute/dim action — highlight, then fade.
    func actionPerformed() {
        withAnimation(.easeInOut(duration: fadeAnimationDuration)) {
            hideControls = false
            controlsHighlighted = true
        }
        scheduleHideFade()
    }

    // MARK: - Timers (match top-bar intervals)

    private var fadeAnimationDuration: TimeInterval {
        style == .curved ? 0.35 : 0.3
    }

    private func scheduleHideFade() {
        fadeTimer?.invalidate()
        let interval: TimeInterval = 5.0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                withAnimation(.easeInOut(duration: self.fadeAnimationDuration)) {
                    self.hideControls = true
                    self.controlsHighlighted = false
                }
            }
        }
    }
}

enum StreamMicChromeOpacity {
    static func flat(
        hideControls: Bool,
        controlsHighlighted: Bool,
        peekThroughActive: Bool,
        darkControlsMode: Bool,
        lightControlsMode: Bool
    ) -> CGFloat {
        if peekThroughActive { return 1.0 }
        if controlsHighlighted { return 1.0 }
        if hideControls {
            if darkControlsMode { return 0.01 }
            if lightControlsMode { return 0.5 }
            return 0.05
        }
        if darkControlsMode { return 0.12 }
        if lightControlsMode { return 1.0 }
        return 0.5
    }

    static func classic(hideControls: Bool, controlsHighlighted: Bool) -> CGFloat {
        if controlsHighlighted { return 1.0 }
        if hideControls { return 0.05 }
        return 0.5
    }
}

// MARK: - Mic button

struct FloatingMicButton: View {
    @StateObject private var micManager = RemoteMicManager()

    var chromeOpacity: CGFloat = 1.0
    var colorStyle: MicButtonColorStyle = .white
    var onActionPerformed: (() -> Void)?

    @State private var tapFeedbackTrigger = 0
    @State private var skipNextTap = false

    var body: some View {
        Button(action: handleTap) {
            Image(micAssetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: StreamMicBarMetrics.muteAssetWidth, height: StreamMicBarMetrics.tapSize)
                .padding(.horizontal, StreamMicBarMetrics.barHorizontalPadding)
                .padding(.vertical, StreamMicBarMetrics.barVerticalPadding)
                .glassBackgroundEffect()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .opacity(chromeOpacity)
        .allowsHitTesting(true)
        .onLongPressGesture(
            minimumDuration: RemoteMicManager.longPressDuration,
            pressing: { isPressing in
                if !isPressing, micManager.isDimmed {
                    skipNextTap = true
                    bumpFeedback()
                    micManager.longPressRelease()
                    onActionPerformed?()
                }
            },
            perform: {
                skipNextTap = true
                bumpFeedback()
                micManager.longPressMute()
                onActionPerformed?()
            }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: tapFeedbackTrigger)
    }

    private func handleTap() {
        if skipNextTap {
            skipNextTap = false
            return
        }
        bumpFeedback()
        micManager.toggleMute()
        onActionPerformed?()
    }

    private var micAssetName: String {
        colorStyle.assetName(isMuted: micManager.isMuted, isDimmed: micManager.isDimmed)
    }

    private func bumpFeedback() {
        tapFeedbackTrigger += 1
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.6)
        FloatingMicButton()
    }
    .frame(width: 400, height: 200)
}
