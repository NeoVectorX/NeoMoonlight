//
//  BitrateAssistantViews.swift
//  Neo Moonlight
//

import SwiftUI

// MARK: - Link Quality Meter

struct LinkQualityMeter: View {
    let qualityScore: Int
    let qualityLabel: String
    let progress: Double
    let scale: CGFloat
    var compact: Bool = false

    private var scoreColor: Color {
        if qualityScore >= 80 { return Color(red: 0.35, green: 0.88, blue: 0.62) }
        if qualityScore >= 55 { return NeoBrandColors.orange }
        return Color(red: 1.0, green: 0.45, blue: 0.25)
    }

    var body: some View {
        let size: CGFloat = (compact ? 88 : 140) * scale
        let lineWidth: CGFloat = (compact ? 7 : 10) * scale
        let outerLine: CGFloat = (compact ? 4 : 5) * scale

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: outerLine)
                .frame(width: size + 14 * scale, height: size + 14 * scale)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    NeoBrandColors.orange.opacity(0.85),
                    style: StrokeStyle(lineWidth: outerLine, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size + 14 * scale, height: size + 14 * scale)

            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, Double(qualityScore) / 100.0)))
                .stroke(
                    AngularGradient(
                        colors: [scoreColor.opacity(0.5), scoreColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.easeOut(duration: 0.35), value: qualityScore)

            VStack(spacing: 2 * scale) {
                if compact {
                    Text("\(qualityScore)")
                        .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Text("\(qualityScore)")
                        .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/ 100")
                        .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(qualityLabel.uppercased())
                    .font(.system(size: (compact ? 8 : 10) * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .tracking(0.6 * scale)
            }
        }
        .frame(width: size + 20 * scale, height: size + 20 * scale)
    }
}

// MARK: - Range Gauge

struct BitrateRangeGauge: View {
    let currentMbps: Int
    let minMbps: Int
    let maxMbps: Int
    let sessionMinMbps: Int?
    let sessionMaxMbps: Int?
    let recommendedMbps: Int?
    let accent: Color
    let scale: CGFloat

    private var displayMin: Double { Double(max(5, min(minMbps, sessionMinMbps ?? minMbps) - 20)) }
    private var displayMax: Double { Double(max(maxMbps, sessionMaxMbps ?? maxMbps) + 40) }

    private func position(for mbps: Int) -> CGFloat {
        let clamped = min(max(Double(mbps), displayMin), displayMax)
        return CGFloat((clamped - displayMin) / (displayMax - displayMin))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                Text("Bitrate Range")
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let sMin = sessionMinMbps, let sMax = sessionMaxMbps {
                    Text("Suggested: \(sMin)–\(sMax) Mbps")
                        .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeoBrandColors.orange.opacity(0.85))
                } else {
                    Text("\(minMbps)–\(maxMbps) Mbps typical")
                        .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeoBrandColors.orange.opacity(0.85))
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))

                    if let sMin = sessionMinMbps, let sMax = sessionMaxMbps {
                        let start = position(for: sMin)
                        let end = position(for: sMax)
                        Capsule()
                            .fill(LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.38)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, width * max(0.04, end - start)))
                            .offset(x: width * start)
                    }

                    if let rec = recommendedMbps {
                        let x = width * position(for: rec)
                        Diamond()
                            .fill(NeoBrandColors.orange)
                            .frame(width: 10 * scale, height: 10 * scale)
                            .offset(x: max(0, min(width - 10 * scale, x - 5 * scale)), y: -10 * scale)
                    }

                    Circle()
                        .fill(RadialGradient(colors: [.white, accent], center: .center, startRadius: 0, endRadius: 8 * scale))
                        .frame(width: 14 * scale, height: 14 * scale)
                        .shadow(color: accent.opacity(0.65), radius: 8 * scale)
                        .offset(x: max(0, min(width - 14 * scale, width * position(for: currentMbps) - 7 * scale)))
                }
            }
            .frame(height: 14 * scale)
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Metric Tile

private struct BitrateMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let accent: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(title.uppercased())
                .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.system(size: 9 * scale, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 10 * scale)
        .frame(maxWidth: .infinity, minHeight: 74 * scale, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Measuring Panel

struct BitrateMeasuringPopoverView: View {
    @Bindable var session: BitrateCheckSession
    let streamLabel: String
    var displayScale: CGFloat = 1.4
    var showFirstRunHint: Bool = false
    var onCancel: () -> Void

    var body: some View {
        let scale = max(displayScale, 0.01)
        let radius: CGFloat = 24 * scale
        let panelWidth: CGFloat = 560 * scale

        VStack(alignment: .leading, spacing: 16 * scale) {
            HStack {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text("Analyzing Stream…")
                        .font(.custom("Fredoka-SemiBold", size: 28 * scale))
                        .foregroundStyle(.white)
                    Text(streamLabel)
                        .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NeoBrandColors.orange.opacity(0.92))
                }
                Spacer()
            }

            LinkQualityMeter(
                qualityScore: session.liveQualityScore,
                qualityLabel: session.liveQualityLabel,
                progress: Double(session.elapsedSeconds) / Double(max(1, session.totalSeconds)),
                scale: scale
            )
            .frame(maxWidth: .infinity)

            Text("\(session.remainingSeconds)s remaining")
                .font(.system(size: 13 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeoBrandColors.orange)
                .frame(maxWidth: .infinity, alignment: .center)

            if showFirstRunHint {
                Text("Run while in a game, not on the desktop. You may need a few runs to find your sweet spot.")
                    .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 8 * scale) {
                compactMetric(title: "Drops/s", value: String(format: "%.1f", session.liveDrops), scale: scale)
                compactMetric(title: "FPS", value: String(format: "%.0f", session.liveFps), scale: scale)
                compactMetric(title: "Latency", value: session.liveRtt >= 0 ? "\(session.liveRtt)" : "—", scale: scale)
                compactMetric(title: "Network", value: session.liveNetworkGood ? "Good" : "Poor", scale: scale)
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12 * scale)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 20 * scale)
        .frame(width: panelWidth)
        .neoClearBluePanelChrome(cornerRadius: radius, layoutScale: scale)
    }

    private func compactMetric(title: String, value: String, scale: CGFloat) -> some View {
        VStack(spacing: 2 * scale) {
            Text(title.uppercased())
                .font(.system(size: 8 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8 * scale)
        .background(RoundedRectangle(cornerRadius: 10 * scale).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Reconnecting Panel

struct BitrateReconnectingPopoverView: View {
    @Bindable var session: BitrateCheckSession
    var displayScale: CGFloat = 1.4

    var body: some View {
        let scale = max(displayScale, 0.01)
        let radius: CGFloat = 24 * scale
        let panelWidth: CGFloat = 560 * scale

        VStack(spacing: 18 * scale) {
            ProgressView()
                .scaleEffect(1.2 * scale)
                .tint(NeoBrandColors.orange)

            Text("Reconnecting…")
                .font(.custom("Fredoka-SemiBold", size: 28 * scale))
                .foregroundStyle(.white)

            if session.reconnectCountdown > 0 {
                Text("Ready in \(session.reconnectCountdown)…")
                    .font(.system(size: 16 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeoBrandColors.orange)
            }

            Text(session.reconnectStatus)
                .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 28 * scale)
        .frame(width: panelWidth)
        .neoClearBluePanelChrome(cornerRadius: radius, layoutScale: scale)
        .allowsHitTesting(false)
    }
}

// MARK: - Report Panel

struct BitrateCheckPopoverView: View {
    let result: BitrateCheckResult
    @Bindable var session: BitrateCheckSession
    var displayScale: CGFloat = 1.4
    var canReconnect: Bool = true
    var onApply: (Int32) -> Void
    var onApplyAndReconnect: (Int32) -> Void
    var onClose: () -> Void

    var body: some View {
        let scale = max(displayScale, 0.01)
        let radius: CGFloat = 24 * scale
        let panelWidth: CGFloat = 560 * scale

        VStack(alignment: .leading, spacing: 16 * scale) {
            header(scale: scale)

            HStack {
                LinkQualityMeter(
                    qualityScore: result.sessionScore,
                    qualityLabel: result.sessionQuality.rawValue,
                    progress: 1.0,
                    scale: scale,
                    compact: true
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 4 * scale) {
                    Text("Tested at \(result.testedAtMbps) Mbps")
                        .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(result.sampleCount) samples")
                        .font(.system(size: 10 * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            metricGrid(scale: scale)

            BitrateRangeGauge(
                currentMbps: result.currentMbps,
                minMbps: result.recommendedMinMbps,
                maxMbps: result.recommendedMaxMbps,
                sessionMinMbps: result.sessionMinMbps,
                sessionMaxMbps: result.sessionMaxMbps,
                recommendedMbps: result.suggestedMbps,
                accent: result.accentColor,
                scale: scale
            )

            verdictCard(scale: scale)

            if case .wait = result.verdict {
                Button(action: onClose) {
                    actionLabel("Close", scale: scale, filled: false)
                }
                .buttonStyle(.plain)
            } else {
                bitratePicker(scale: scale)

                HStack(spacing: 10 * scale) {
                    Button(action: onClose) {
                        actionLabel("Close", scale: scale, filled: false)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onApply(session.selectedBitrateKbps) }) {
                        actionLabel("Apply", scale: scale, filled: false)
                    }
                    .buttonStyle(.plain)

                    if canReconnect {
                        Button(action: { onApplyAndReconnect(session.selectedBitrateKbps) }) {
                            actionLabel("Apply & Reconnect", scale: scale, filled: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(result.footnote)
                .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 20 * scale)
        .frame(width: panelWidth)
        .neoClearBluePanelChrome(cornerRadius: radius, layoutScale: scale)
    }

    @ViewBuilder
    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 14 * scale) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [result.accentColor, result.accentColor.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64 * scale, height: 64 * scale)
                    .shadow(color: result.accentColor.opacity(0.45), radius: 14 * scale, x: 0, y: 8 * scale)
                Image(systemName: result.iconName)
                    .font(.system(size: 28 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4 * scale) {
                Text("Bitrate Analysis")
                    .font(.custom("Fredoka-SemiBold", size: 28 * scale))
                    .foregroundStyle(.white)
                Text(result.streamLabel)
                    .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeoBrandColors.orange.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func metricGrid(scale: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * scale), count: 4), spacing: 10 * scale) {
            BitrateMetricTile(title: "Bitrate", value: "\(result.currentMbps)", unit: "Mbps", accent: result.accentColor, scale: scale)
            BitrateMetricTile(title: "Network", value: result.networkStatus, unit: result.networkIsGood ? "Stable" : "Strained", accent: result.networkIsGood ? Color(red: 0.35, green: 0.88, blue: 0.62) : Color(red: 1.0, green: 0.45, blue: 0.25), scale: scale)
            BitrateMetricTile(title: "Latency", value: result.rttMs >= 0 ? "\(result.rttMs)" : "—", unit: result.rttMs >= 0 ? "ms RTT" : "N/A", accent: .white.opacity(0.9), scale: scale)
            BitrateMetricTile(title: "Stream", value: String(format: "%.0f", result.actualFps), unit: "/ \(result.targetFps) FPS", accent: .white.opacity(0.9), scale: scale)
        }
    }

    @ViewBuilder
    private func verdictCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(spacing: 8 * scale) {
                Capsule().fill(result.accentColor).frame(width: 4 * scale, height: 18 * scale)
                Text(result.verdictTitle.uppercased())
                    .font(.custom("Fredoka-SemiBold", size: 16 * scale))
                    .foregroundStyle(result.accentColor)
            }
            Text(result.verdictSubtitle)
                .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).strokeBorder(result.accentColor.opacity(0.22), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func bitratePicker(scale: CGFloat) -> some View {
        HStack {
            Text("Target bitrate")
                .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Menu {
                ForEach(BitrateCheckResult.bitrateTable, id: \.self) { kbps in
                    Button("\(kbps / 1000) Mbps") {
                        session.selectedBitrateKbps = kbps
                    }
                }
            } label: {
                HStack(spacing: 6 * scale) {
                    Text("\(session.selectedBitrateKbps / 1000) Mbps")
                        .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10 * scale, weight: .bold))
                }
                .foregroundStyle(NeoBrandColors.orange)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 8 * scale)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ title: String, scale: CGFloat, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11 * scale)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? NeoBrandColors.orange.opacity(0.9) : Color.white.opacity(0.1))
            )
    }
}

// MARK: - Unified Panel

struct BitrateAssistantPanel: View {
    @Bindable var session: BitrateCheckSession
    let streamLabel: String
    var displayScale: CGFloat = 1.4
    var canReconnect: Bool = true
    var showFirstRunHint: Bool = false
    var onCancel: () -> Void
    var onClose: () -> Void
    var onApply: (Int32) -> Void
    var onApplyAndReconnect: (Int32) -> Void

    var body: some View {
        switch session.phase {
        case .idle:
            Color.clear.frame(width: 1, height: 1)
        case .measuring:
            BitrateMeasuringPopoverView(
                session: session,
                streamLabel: streamLabel,
                displayScale: displayScale,
                showFirstRunHint: showFirstRunHint,
                onCancel: onCancel
            )
        case .report:
            if let result = session.result {
                BitrateCheckPopoverView(
                    result: result,
                    session: session,
                    displayScale: displayScale,
                    canReconnect: canReconnect,
                    onApply: onApply,
                    onApplyAndReconnect: onApplyAndReconnect,
                    onClose: onClose
                )
            }
        case .reconnecting:
            BitrateReconnectingPopoverView(session: session, displayScale: displayScale)
        }
    }
}

// MARK: - Reconnect Helper

enum BitrateStreamReconnect {
    static let settleSeconds: TimeInterval = BitrateCheckResult.bitrateReconnectSettleSeconds

    @MainActor
    static func runSettleCountdown(session: BitrateCheckSession) async {
        let total = Int(settleSeconds)
        for remaining in stride(from: total, through: 1, by: -1) {
            session.updateReconnect(status: "Waiting for connection to settle…", countdown: remaining)
            try? await Task.sleep(for: .seconds(1))
        }
        session.updateReconnect(status: "Starting stream…", countdown: 0)
        try? await Task.sleep(for: .milliseconds(200))
    }
}
