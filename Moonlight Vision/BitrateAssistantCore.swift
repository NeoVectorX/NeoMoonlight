//
//  BitrateAssistantCore.swift
//  Neo Moonlight
//

import SwiftUI

// MARK: - Types

enum BitrateCheckVerdict {
    case wait(remainingSeconds: Int)
    case good
    case raiseBitrate(suggestedKbps: Int32, stepKbps: Int32)
    case lowerBitrate(suggestedKbps: Int32, stepKbps: Int32)
    case noData
    case inconclusive
}

enum BitrateSessionQuality: String {
    case stable = "Stable"
    case marginal = "Marginal"
    case unstable = "Unstable"
    case inconclusive = "Inconclusive"
}

enum BitrateSessionPhase: Equatable {
    case idle
    case measuring
    case report
    case reconnecting
}

struct BitrateSample {
    let dropsPerSecond: Double
    let fps: Double
    let rttMs: Int32
    let connectionStatus: Int32
}

struct BitrateCheckResult {
    let verdict: BitrateCheckVerdict
    let iconName: String
    let accentColor: Color

    let verdictTitle: String
    let verdictSubtitle: String
    let footnote: String
    let suggestedMbps: Int?

    let currentMbps: Int
    let recommendedMinMbps: Int
    let recommendedMaxMbps: Int
    let streamLabel: String
    let networkStatus: String
    let networkIsGood: Bool
    let dropsPerSecond: Double
    let actualFps: Double
    let targetFps: Int32
    let rttMs: Int32

    let sessionMinMbps: Int
    let sessionMaxMbps: Int
    let sessionQuality: BitrateSessionQuality
    let sessionScore: Int
    let testedAtMbps: Int
    let defaultSelectedKbps: Int32
    let sampleCount: Int

    static let warmupSeconds: TimeInterval = 5
    static let bitrateReconnectSettleSeconds: TimeInterval = 5.0

    static let bitrateTable: [Int32] = [
        5000, 10000, 30000, 50000, 75000, 100000, 120000, 150000,
        175000, 200000, 225000, 250000, 300000, 325000, 350000,
        400000, 450000, 500000,
    ]

    static let iterativeFootnote = "Run the scan while in a game (not on the desktop) for accurate results. Dial in by going up on headroom and down when strained — your sweet spot is usually the highest bitrate that still scans clean."
}

// MARK: - Advisor

@MainActor
enum BitrateAdvisor {
    static func recommendedRangeKbps(width: Int, height: Int, fps: Int, hdrEnabled: Bool) -> (min: Int32, max: Int32) {
        let frameRateFactor = fps <= 60
            ? Double(fps) / 30.0
            : (sqrt(Double(fps) / 60.0) * 60.0) / 30.0

        let resTable: [(pixels: Int, factor: Int)] = [
            (640 * 360, 1),
            (854 * 480, 2),
            (1280 * 720, 5),
            (1920 * 1080, 10),
            (2560 * 1440, 20),
            (3840 * 2160, 40),
        ]

        let pixels = width * height
        var resolutionFactor = 1.0

        for i in 0..<resTable.count {
            if pixels == resTable[i].pixels {
                resolutionFactor = Double(resTable[i].factor)
                break
            } else if pixels < resTable[i].pixels {
                if i == 0 {
                    resolutionFactor = Double(resTable[i].factor)
                } else {
                    let prev = resTable[i - 1]
                    let next = resTable[i]
                    let t = Double(pixels - prev.pixels) / Double(next.pixels - prev.pixels)
                    resolutionFactor = t * Double(next.factor - prev.factor) + Double(prev.factor)
                }
                break
            } else if i == resTable.count - 1 {
                resolutionFactor = Double(resTable[i].factor)
            }
        }

        let baseKbps = Int32(round(resolutionFactor * frameRateFactor)) * 1000
        var minKbps = Int32(Double(baseKbps) * 0.85)
        var maxKbps = Int32(Double(baseKbps) * 1.35)

        if hdrEnabled {
            minKbps = Int32(Double(minKbps) * 1.15)
            maxKbps = Int32(Double(maxKbps) * 1.2)
        }

        return (max(5000, minKbps), max(minKbps + 5000, maxKbps))
    }

    static func nextPresetKbps(from currentKbps: Int32, direction: Int) -> Int32 {
        if direction > 0 {
            if let next = BitrateCheckResult.bitrateTable.first(where: { $0 > currentKbps }) {
                return next
            }
            return min(currentKbps + 20_000, 500_000)
        }

        if let prev = BitrateCheckResult.bitrateTable.last(where: { $0 < currentKbps }) {
            return prev
        }
        return max(currentKbps - 20_000, 5_000)
    }

    static func nearestPresetKbps(to kbps: Int32) -> Int32 {
        BitrateCheckResult.bitrateTable.min(by: { abs($0 - kbps) < abs($1 - kbps) }) ?? kbps
    }

    static func liveQualityScore(
        dropsPerSecond: Double,
        actualFps: Double,
        targetFps: Int32,
        rttMs: Int32,
        connectionStatus: Int32
    ) -> Int {
        if connectionStatus == 1 { return max(0, 35) }

        var score = 100.0
        if dropsPerSecond >= 3 { score -= 45 }
        else if dropsPerSecond >= 1 { score -= 20 }
        else if dropsPerSecond >= 0.5 { score -= 8 }

        let target = Double(targetFps)
        if target > 0 {
            let ratio = actualFps / target
            if ratio < 0.8 { score -= 35 }
            else if ratio < 0.9 { score -= 18 }
            else if ratio < 0.95 { score -= 6 }
        }

        if rttMs >= 0 {
            if rttMs > 60 { score -= 18 }
            else if rttMs > 30 { score -= 8 }
        }

        return max(0, min(100, Int(score.rounded())))
    }

    static func qualityLabel(for score: Int, measuring: Bool) -> String {
        if measuring && score < 10 { return "Checking…" }
        if score >= 80 { return "Stable" }
        if score >= 55 { return "Marginal" }
        return "Strained"
    }

    static func classifySession(
        samples: [BitrateSample],
        targetFps: Int32
    ) -> BitrateSessionQuality {
        guard !samples.isEmpty else { return .inconclusive }

        let avgDrops = samples.map(\.dropsPerSecond).reduce(0, +) / Double(samples.count)
        let avgFps = samples.map(\.fps).reduce(0, +) / Double(samples.count)
        let poorCount = samples.filter { $0.connectionStatus == 1 }.count
        let poorRatio = Double(poorCount) / Double(samples.count)
        let target = Double(targetFps)
        let fpsShortfall = target > 0 && avgFps < target * 0.9

        if avgDrops > 3 || poorRatio > 0.25 || (fpsShortfall && avgDrops > 1) {
            return .unstable
        }
        if avgDrops > 1 || poorRatio > 0.1 || fpsShortfall {
            return .marginal
        }
        return .stable
    }

    static func evaluateSession(
        samples: [BitrateSample],
        targetFps: Int32,
        currentBitrateKbps: Int32,
        width: Int32,
        height: Int32,
        hdrEnabled: Bool
    ) -> BitrateCheckResult {
        let tableRange = recommendedRangeKbps(
            width: Int(width),
            height: Int(height),
            fps: Int(targetFps),
            hdrEnabled: hdrEnabled
        )

        let resLabel = "\(width)×\(height) @ \(targetFps)"
        let currentMbps = max(1, Int(currentBitrateKbps / 1000))
        let recMinMbps = max(1, Int(tableRange.min / 1000))
        let recMaxMbps = max(recMinMbps, Int(tableRange.max / 1000))

        guard samples.count >= 5 else {
            return inconclusiveResult(
                currentMbps: currentMbps,
                currentBitrateKbps: currentBitrateKbps,
                recMinMbps: recMinMbps,
                recMaxMbps: recMaxMbps,
                streamLabel: resLabel,
                targetFps: targetFps,
                sampleCount: samples.count
            )
        }

        let avgDrops = samples.map(\.dropsPerSecond).reduce(0, +) / Double(samples.count)
        let avgFps = samples.map(\.fps).reduce(0, +) / Double(samples.count)
        let rttValues = samples.map(\.rttMs).filter { $0 >= 0 }
        let avgRtt: Int32 = rttValues.isEmpty ? -1 : Int32(rttValues.map(Int.init).reduce(0, +) / rttValues.count)
        let poorCount = samples.filter { $0.connectionStatus == 1 }.count
        let networkIsGood = poorCount < samples.count / 10
        let networkLabel = networkIsGood ? "Good" : "Poor"

        let sessionQuality = classifySession(samples: samples, targetFps: targetFps)
        let sessionScore = liveQualityScore(
            dropsPerSecond: avgDrops,
            actualFps: avgFps,
            targetFps: targetFps,
            rttMs: avgRtt,
            connectionStatus: poorCount > samples.count / 5 ? 1 : 0
        )

        let (sessionMinKbps, sessionMaxKbps, verdict, icon, accent, title, subtitle, suggestedMbps) = sessionRangeAndVerdict(
            quality: sessionQuality,
            score: sessionScore,
            currentBitrateKbps: currentBitrateKbps,
            tableRange: tableRange,
            avgDrops: avgDrops,
            avgFps: avgFps,
            targetFps: targetFps,
            currentMbps: currentMbps
        )

        let defaultKbps = defaultSelectionKbps(minKbps: sessionMinKbps, maxKbps: sessionMaxKbps, currentKbps: currentBitrateKbps, verdict: verdict)

        return BitrateCheckResult(
            verdict: verdict,
            iconName: icon,
            accentColor: accent,
            verdictTitle: title,
            verdictSubtitle: subtitle,
            footnote: BitrateCheckResult.iterativeFootnote,
            suggestedMbps: suggestedMbps,
            currentMbps: currentMbps,
            recommendedMinMbps: recMinMbps,
            recommendedMaxMbps: recMaxMbps,
            streamLabel: resLabel,
            networkStatus: networkLabel,
            networkIsGood: networkIsGood,
            dropsPerSecond: avgDrops,
            actualFps: avgFps,
            targetFps: targetFps,
            rttMs: avgRtt,
            sessionMinMbps: max(1, Int(sessionMinKbps / 1000)),
            sessionMaxMbps: max(1, Int(sessionMaxKbps / 1000)),
            sessionQuality: sessionQuality,
            sessionScore: sessionScore,
            testedAtMbps: currentMbps,
            defaultSelectedKbps: defaultKbps,
            sampleCount: samples.count
        )
    }

    private static func sessionRangeAndVerdict(
        quality: BitrateSessionQuality,
        score: Int,
        currentBitrateKbps: Int32,
        tableRange: (min: Int32, max: Int32),
        avgDrops: Double,
        avgFps: Double,
        targetFps: Int32,
        currentMbps: Int
    ) -> (Int32, Int32, BitrateCheckVerdict, String, Color, String, String, Int?) {
        let green = Color(red: 0.35, green: 0.88, blue: 0.62)
        let orange = NeoBrandColors.orange
        let red = Color(red: 1.0, green: 0.45, blue: 0.25)

        switch quality {
        case .unstable:
            let suggested = nextPresetKbps(from: currentBitrateKbps, direction: -1)
            let minK = nextPresetKbps(from: suggested, direction: -1)
            return (
                minK, currentBitrateKbps, .lowerBitrate(suggestedKbps: suggested, stepKbps: 0),
                "waveform.path.ecg", red, "Lower Bitrate",
                "Your link struggled at \(currentMbps) Mbps. Try \(suggested / 1000) Mbps, reconnect, then scan again.",
                Int(suggested / 1000)
            )

        case .marginal:
            let suggested = nextPresetKbps(from: currentBitrateKbps, direction: -1)
            return (
                suggested, currentBitrateKbps, .lowerBitrate(suggestedKbps: suggested, stepKbps: 0),
                "exclamationmark.triangle.fill", orange, "Marginal Link",
                "Some strain detected at \(currentMbps) Mbps. Consider \(suggested / 1000) Mbps if issues continue.",
                Int(suggested / 1000)
            )

        case .stable, .inconclusive:
            let target = Double(targetFps)
            let fpsShortfall = target > 0 && avgFps < target * 0.9
            let hasHeadroom = avgDrops < 1.0 && !fpsShortfall && score >= 70

            if hasHeadroom {
                let stepCount = (score >= 95 && avgDrops < 0.1) ? 3 : 2
                var maxK = currentBitrateKbps
                for _ in 0..<stepCount { maxK = nextPresetKbps(from: maxK, direction: 1) }
                let suggested = nextPresetKbps(from: currentBitrateKbps, direction: 1)
                return (
                    currentBitrateKbps, maxK, .raiseBitrate(suggestedKbps: suggested, stepKbps: 0),
                    "waveform.path.ecg", orange, "Headroom Detected",
                    "Your link looks healthy at \(currentMbps) Mbps. Try \(suggested / 1000) Mbps, reconnect, then run another scan.",
                    Int(suggested / 1000)
                )
            }

            let padMin = max(currentBitrateKbps, tableRange.min)
            let padMax = min(nextPresetKbps(from: currentBitrateKbps, direction: 1), tableRange.max)
            return (
                padMin, max(padMax, currentBitrateKbps), .good,
                "checkmark.seal.fill", green, "Looking Good",
                "Bitrate and network health look well matched for this stream.",
                nil
            )
        }
    }

    private static func defaultSelectionKbps(
        minKbps: Int32,
        maxKbps: Int32,
        currentKbps: Int32,
        verdict: BitrateCheckVerdict
    ) -> Int32 {
        switch verdict {
        case .raiseBitrate(let suggested, _), .lowerBitrate(let suggested, _):
            return suggested
        default:
            let mid = (minKbps + maxKbps) / 2
            let inRange = BitrateCheckResult.bitrateTable.filter { $0 >= minKbps && $0 <= maxKbps }
            if let pick = inRange.min(by: { abs($0 - mid) < abs($1 - mid) }) {
                return pick
            }
            return nearestPresetKbps(to: currentKbps)
        }
    }

    private static func inconclusiveResult(
        currentMbps: Int,
        currentBitrateKbps: Int32,
        recMinMbps: Int,
        recMaxMbps: Int,
        streamLabel: String,
        targetFps: Int32,
        sampleCount: Int
    ) -> BitrateCheckResult {
        BitrateCheckResult(
            verdict: .inconclusive,
            iconName: "questionmark.circle",
            accentColor: NeoBrandColors.orange.opacity(0.85),
            verdictTitle: "Inconclusive",
            verdictSubtitle: "Not enough stable samples. Try running the scan again.",
            footnote: BitrateCheckResult.iterativeFootnote,
            suggestedMbps: nil,
            currentMbps: currentMbps,
            recommendedMinMbps: recMinMbps,
            recommendedMaxMbps: recMaxMbps,
            streamLabel: streamLabel,
            networkStatus: "—",
            networkIsGood: true,
            dropsPerSecond: 0,
            actualFps: 0,
            targetFps: targetFps,
            rttMs: -1,
            sessionMinMbps: currentMbps,
            sessionMaxMbps: currentMbps,
            sessionQuality: .inconclusive,
            sessionScore: 0,
            testedAtMbps: currentMbps,
            defaultSelectedKbps: currentBitrateKbps,
            sampleCount: sampleCount
        )
    }

    static func warmupBlockResult(
        remainingSeconds: Int,
        streamConfig: StreamConfiguration,
        settings: TemporarySettings,
        metrics: [String: Any]?
    ) -> BitrateCheckResult {
        let width = streamConfig.width
        let height = streamConfig.height
        let range = recommendedRangeKbps(width: Int(width), height: Int(height), fps: Int(streamConfig.frameRate), hdrEnabled: settings.enableHdr)
        let currentMbps = max(1, Int(settings.bitrate / 1000))
        let actualFps = metrics?["fps"] as? Double ?? 0
        let drops = metrics?["dropsPerSecond"] as? Double ?? 0
        let rtt = metrics?["rttMs"] as? Int32 ?? -1

        return BitrateCheckResult(
            verdict: .wait(remainingSeconds: remainingSeconds),
            iconName: "waveform.path.ecg",
            accentColor: NeoBrandColors.orange.opacity(0.75),
            verdictTitle: "Stream Warming Up",
            verdictSubtitle: "Stream metrics are still stabilizing. Try again in ~\(remainingSeconds)s.",
            footnote: BitrateCheckResult.iterativeFootnote,
            suggestedMbps: nil,
            currentMbps: currentMbps,
            recommendedMinMbps: max(1, Int(range.min / 1000)),
            recommendedMaxMbps: max(1, Int(range.max / 1000)),
            streamLabel: "\(width)×\(height) @ \(streamConfig.frameRate)",
            networkStatus: "—",
            networkIsGood: true,
            dropsPerSecond: drops,
            actualFps: actualFps,
            targetFps: streamConfig.frameRate,
            rttMs: rtt,
            sessionMinMbps: currentMbps,
            sessionMaxMbps: currentMbps,
            sessionQuality: .inconclusive,
            sessionScore: 0,
            testedAtMbps: currentMbps,
            defaultSelectedKbps: settings.bitrate,
            sampleCount: 0
        )
    }
}

// MARK: - Session

@MainActor
@Observable
final class BitrateCheckSession {
    var phase: BitrateSessionPhase = .idle
    var result: BitrateCheckResult?
    var remainingSeconds: Int = 0
    var totalSeconds: Int = 30
    var elapsedSeconds: Int = 0
    var liveQualityScore: Int = 0
    var liveQualityLabel: String = "Checking…"
    var liveDrops: Double = 0
    var liveFps: Double = 0
    var liveRtt: Int32 = -1
    var liveNetworkGood: Bool = true
    var selectedBitrateKbps: Int32 = 0
    var reconnectStatus: String = "Stopping stream…"
    var reconnectCountdown: Int = 0

    private var timer: Timer?
    private var samples: [BitrateSample] = []
    private var warmupDiscardCount: Int = 3
    private var metricsProvider: (() -> ([String: Any]?, Int32))?
    private var streamConfig: StreamConfiguration?
    private var settings: TemporarySettings?

    var isActive: Bool { phase != .idle }

    func cancel() {
        timer?.invalidate()
        timer = nil
        samples.removeAll()
        phase = .idle
        result = nil
    }

    func closeReport() {
        guard phase == .report else { return }
        phase = .idle
        result = nil
    }

    func start(
        extendedScan: Bool,
        metricsProvider: @escaping () -> ([String: Any]?, Int32),
        streamConfig: StreamConfiguration,
        settings: TemporarySettings
    ) {
        cancel()

        self.metricsProvider = metricsProvider
        self.streamConfig = streamConfig
        self.settings = settings
        totalSeconds = extendedScan ? 60 : 30
        warmupDiscardCount = extendedScan ? 5 : 3
        remainingSeconds = totalSeconds
        elapsedSeconds = 0
        selectedBitrateKbps = settings.bitrate

        if let metrics = metricsProvider().0 {
            let uptime = metrics["streamUptimeSeconds"] as? Double ?? 0
            if uptime < BitrateCheckResult.warmupSeconds {
                let remaining = max(1, Int(ceil(BitrateCheckResult.warmupSeconds - uptime)))
                result = BitrateAdvisor.warmupBlockResult(
                    remainingSeconds: remaining,
                    streamConfig: streamConfig,
                    settings: settings,
                    metrics: metrics
                )
                phase = .report
                selectedBitrateKbps = settings.bitrate
                return
            }
        }

        phase = .measuring
        tickMeasurement()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickMeasurement() }
        }
    }

    private func tickMeasurement() {
        guard phase == .measuring,
              let metricsProvider,
              let streamConfig,
              let settings else { return }

        let (metrics, connectionStatus) = metricsProvider()

        if let metrics {
            let sample = BitrateSample(
                dropsPerSecond: metrics["dropsPerSecond"] as? Double ?? 0,
                fps: metrics["fps"] as? Double ?? 0,
                rttMs: metrics["rttMs"] as? Int32 ?? -1,
                connectionStatus: connectionStatus
            )
            samples.append(sample)

            let window = samples.suffix(min(8, samples.count))
            liveDrops = window.map(\.dropsPerSecond).reduce(0, +) / Double(window.count)
            liveFps = window.map(\.fps).reduce(0, +) / Double(window.count)
            let rtts = window.map(\.rttMs).filter { $0 >= 0 }
            liveRtt = rtts.isEmpty ? -1 : Int32(rtts.map(Int.init).reduce(0, +) / rtts.count)
            liveNetworkGood = window.filter { $0.connectionStatus == 1 }.count < window.count / 3
            liveQualityScore = BitrateAdvisor.liveQualityScore(
                dropsPerSecond: liveDrops,
                actualFps: liveFps,
                targetFps: streamConfig.frameRate,
                rttMs: liveRtt,
                connectionStatus: liveNetworkGood ? 0 : 1
            )
            liveQualityLabel = BitrateAdvisor.qualityLabel(for: liveQualityScore, measuring: elapsedSeconds < 3)
        }

        elapsedSeconds += 1
        remainingSeconds = max(0, totalSeconds - elapsedSeconds)

        if remainingSeconds <= 0 {
            finishMeasurement()
        }
    }

    private func finishMeasurement() {
        timer?.invalidate()
        timer = nil

        guard let streamConfig, let settings else {
            phase = .idle
            return
        }

        let analysisSamples = Array(samples.dropFirst(min(warmupDiscardCount, samples.count)))
        let evaluation = BitrateAdvisor.evaluateSession(
            samples: analysisSamples,
            targetFps: streamConfig.frameRate,
            currentBitrateKbps: settings.bitrate,
            width: streamConfig.width,
            height: streamConfig.height,
            hdrEnabled: settings.enableHdr
        )

        result = evaluation
        selectedBitrateKbps = evaluation.defaultSelectedKbps
        phase = .report
        samples.removeAll()
    }

    func beginReconnectUI() {
        phase = .reconnecting
        reconnectStatus = "Stopping stream…"
        reconnectCountdown = Int(BitrateCheckResult.bitrateReconnectSettleSeconds)
    }

    func updateReconnect(status: String, countdown: Int? = nil) {
        reconnectStatus = status
        if let countdown { reconnectCountdown = countdown }
    }

    func finishReconnect(success: Bool) {
        if success {
            phase = .idle
            result = nil
        } else {
            phase = .report
            reconnectStatus = "Reconnect failed. Try again or disconnect manually."
        }
    }
}

// MARK: - In-place reconnect

@MainActor
enum BitrateInPlaceReconnect {
    static func stopStreamManager(
        _ streamMan: StreamManager?,
        clearReference: () -> Void,
        completion: @escaping () -> Void
    ) {
        guard let sm = streamMan else {
            completion()
            return
        }
        clearReference()
        ConnectionSerializer.shared.notifyStopBegun()
        sm.stopStream(completion: {
            Task { @MainActor in
                ConnectionSerializer.shared.notifyStopComplete()
                completion()
            }
        })
    }
}
