//
//  SettingsView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @Binding public var settings: TemporarySettings
    @State private var selectedAspectRatio: AspectRatio?
    @State private var isCustomAspectRatio: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Video Settings Section
                SettingsSection(title: "Video Settings") {
                    HStack {
                        Text("Resolution")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.resolution) {
                            ForEach(Self.resolutionsGroupedByType, id: \.0) { aspectRatio, resolutions in
                                ForEach(resolutions, id: \.self) { resolution in
                                    Text(resolution.description).tag(resolution)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Aspect Ratio")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $selectedAspectRatio) {
                            ForEach(Self.resolutionsGroupedByType.map { $0.0 }, id: \.self) { aspectRatio in
                                Text(aspectRatio.displayString).tag(aspectRatio as AspectRatio?)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedAspectRatio) { newValue in
                            if let newAspectRatio = newValue {
                                Task { @MainActor in
                                    updateResolutionForAspectRatio(newAspectRatio)
                                }
                                isCustomAspectRatio = false
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Framerate")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.framerate) {
                            ForEach(Self.framerateTable, id: \.self) { framerate in
                                Text("\(framerate) FPS").tag(framerate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Bitrate")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.bitrate) {
                            ForEach(Self.bitrateTable, id: \.self) { bitrate in
                                Text("\(bitrate / 1000) Mbps").tag(bitrate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    if settings.bitrate > 300000 {
                        Label("Bitrates exceeding 300 Mbps require an extreme high-performance network.", systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }
                    
                    HStack {
                        Text("Renderer")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("Renderer", selection: $settings.renderer) {
                            Text(Renderer.classic.description).tag(Renderer.classic)
                            Text(Renderer.curvedDisplay.description).tag(Renderer.curvedDisplay)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                }
                
                // Display Settings
                SettingsSection(title: "Display Settings") {
                    HStack {
                        Text("Touch Mode")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.absoluteTouchMode) {
                            Text("Touchpad").tag(false)
                            Text("Touchscreen").tag(true)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("On-Screen Controls")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.onscreenControls) {
                            Text("Off").tag(OnScreenControlsLevel.off)
                            Text("Auto").tag(OnScreenControlsLevel.auto)
                            Text("Simple").tag(OnScreenControlsLevel.simple)
                            Text("Full").tag(OnScreenControlsLevel.full)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Statistics Overlay", isOn: $settings.statsOverlay)
                        .padding(.vertical, 4)
                    
                    Toggle("Hide VisionOS Cursor", isOn: $settings.hideSystemCursor)
                        .padding(.vertical, 4)
                }
                
                // Controller & Audio Settings
                SettingsSection(title: "Controller & Audio") {
                    HStack {
                        Text("Multi-Controller Mode")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.multiController) {
                            Text("Single").tag(false)
                            Text("Auto").tag(true)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Swap A/B and X/Y Buttons", isOn: $settings.swapABXYButtons)
                        .padding(.vertical, 4)
                    
                    Toggle("Play Audio on PC", isOn: $settings.playAudioOnPC)
                        .padding(.vertical, 4)
                }
                
                // Advanced Settings
                SettingsSection(title: "Advanced") {
                    HStack {
                        Text("Preferred Codec")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.preferredCodec) {
                            Text("H.264").tag(PreferredCodec.h264)
                            Text("HEVC").tag(PreferredCodec.hevc)
                            Text("AV1 (M5 only)").tag(PreferredCodec.av1)
                            Text("Auto").tag(PreferredCodec.auto)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Enable HDR", isOn: $settings.enableHdr)
                        .padding(.vertical, 4)
                    
                    if settings.enableHdr {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundColor(.yellow)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("HDR Setup Required")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("To use HDR, enable it on your host PC: Settings → Display → Use HDR. Your monitor must support HDR. For virtual displays (Apollo), HDR is supported automatically.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.yellow.opacity(0.15))
                            )
                        }
                        .padding(.top, 4)
                    }
                    
                    HStack {
                        Text("Frame Pacing")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.useFramePacing) {
                            Text("Lowest Latency").tag(false)
                            Text("Smoothest Video").tag(true)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 24)
        }
        .onDisappear {
            settings.save()
        }
        .onAppear {
            selectedAspectRatio = settings.resolution.aspectRatio
            isCustomAspectRatio = !Self.resolutionTable.contains(settings.resolution)
        }
        .onChange(of: settings.resolution) { _, newValue in
            selectedAspectRatio = newValue.aspectRatio
        }
    }

    @MainActor
    private func updateResolutionForAspectRatio(_ newAspectRatio: AspectRatio) {
        let currentWidth = settings.resolution.width
        let currentHeight = settings.resolution.height

        if currentWidth >= currentHeight {
            settings.resolution = Resolution(width: currentWidth, height: (currentWidth * newAspectRatio.height) / newAspectRatio.width)
        } else {
            settings.resolution = Resolution(width: (currentHeight * newAspectRatio.width) / newAspectRatio.height, height: currentHeight)
        }
        isCustomAspectRatio = false
    }
}

// MARK: - Settings Section Component
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            VStack(spacing: 12) {
                content
            }
            .padding(24)
            .background(
                ZStack {
                    // Depth shadow
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                        .offset(y: 6)
                        .blur(radius: 12)
                    
                    // Main card
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Setting Row Component
struct SettingRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.white.opacity(0.7))
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

private extension TemporarySettings {
    var resolution: SettingsView.Resolution {
        get {
            SettingsView.Resolution(width: Int(width), height: Int(height))
        }
        set {
            width = Int32(newValue.width)
            height = Int32(newValue.height)
        }
    }
}

extension SettingsView {
    struct AspectRatio: Equatable, Hashable, Comparable {
        private(set) var width: Int
        private(set) var height: Int

        init(width: Int, height: Int) {
            let reduced = simplifyFraction(numerator: width, denominator: height)
            self.width = reduced.numerator
            self.height = reduced.denominator
        }

        var casualDescription: LocalizedStringKey {
            switch self {
            case AspectRatio(width: 16, height: 9):
                "16:9"
            case AspectRatio(width: 16, height: 10):
                "16:10"
            case AspectRatio(width: 4, height: 3):
                "4:3"
            case AspectRatio(width: 64, height: 27):
                "'21:9' 2560x1080 or 5120x2160"
            case AspectRatio(width: 43, height: 18):
                "'21:9' 3440x1440"
            case AspectRatio(width: 24, height: 10):
                "24:10 3840x1600"
            case AspectRatio(width: 64, height: 18):
                "32:9"
            default:
                "\(width)-by-\(height)"
            }
        }
        
        var displayString: String {
            switch self {
            case AspectRatio(width: 16, height: 9):
                return "16:9"
            case AspectRatio(width: 16, height: 10):
                return "16:10"
            case AspectRatio(width: 4, height: 3):
                return "4:3"
            case AspectRatio(width: 64, height: 27):
                return "'21:9' 2560x1080 or 5120x2160"
            case AspectRatio(width: 43, height: 18):
                return "'21:9' 3440x1440"
            case AspectRatio(width: 24, height: 10):
                return "24:10 3840x1600"
            case AspectRatio(width: 64, height: 18):
                return "32:9"
            default:
                return "\(width)-by-\(height)"
            }
        }

        static func < (lhs: SettingsView.AspectRatio, rhs: SettingsView.AspectRatio) -> Bool {
            (Double(lhs.width) / Double(lhs.height)) < (Double(rhs.width) / Double(rhs.height))
        }
    }

    struct Resolution: Equatable, Hashable, CustomStringConvertible {
        var width: Int
        var height: Int

        var aspectRatio: AspectRatio {
            AspectRatio(width: width, height: height)
        }

        var description: String {
            switch self {
            case Resolution(width: 3840, height: 2160):
                "4K"
            case Resolution(width: 5120, height: 2880):
                "5K"
            case _ where simplifyFraction(numerator: width, denominator: height) == simplifyFraction(numerator: 16, denominator: 9):
                "\(height)p"
            default:
                "\(width)x\(height)"
            }
        }
    }

    static let resolutionTable = [
        Resolution(width: 1280, height: 720),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 2560, height: 1440),
        Resolution(width: 3840, height: 2160),
        Resolution(width: 5120, height: 2880),
        Resolution(width: 1920, height: 1200),
        Resolution(width: 2560, height: 1600),
        Resolution(width: 2560, height: 1080),
        Resolution(width: 5120, height: 2160),
        Resolution(width: 3440, height: 1440),
        Resolution(width: 3840, height: 1600),
        Resolution(width: 5120, height: 1440),
    ]

    static var resolutionsGroupedByType: [(AspectRatio, [Resolution])] {
        Dictionary(grouping: resolutionTable, by: \.aspectRatio).sorted { $0.key < $1.key }
    }

    static let framerateTable: [Int32] = [30, 60, 90, 100, 120]

    static let bitrateTable: [Int32] = [5000, 10000, 30000, 50000, 75000, 100000, 120000, 150000, 175000, 200000, 225000, 250000, 300000, 325000, 350000, 400000, 450000, 500000]
}

private func gcd<I: BinaryInteger>(_ a: I, _ b: I) -> I {
    var a = a
    var b = b
    while b != 0 {
        let temp = b
        b = a % b
        a = temp
    }
    return a
}

private func simplifyFraction<I: BinaryInteger>(numerator: I, denominator: I) -> (numerator: I, denominator: I) {
    let divisor = gcd(numerator, denominator)
    return (numerator / divisor, denominator / divisor)
}

#Preview {
    @State var settings = TemporarySettings()
    return SettingsView(settings: $settings)
}