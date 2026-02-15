//
//  UserGuideView.swift
//  Moonlight Vision
//
//  Created by NeoVectorX on 2/2/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct UserGuideView: View {
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let horizontalPadding = screenWidth * 0.30
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        Image("neomoonlight-banner")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 500)
                        
                        Text("Ultimate Streaming Guide")
                            .font(.title)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                    
                    // Step 1: Host Software
                    GuideSection(
                        title: "Step 1: Choosing Your Host Software",
                        icon: "server.rack"
                    ) {
                        VStack(alignment: .leading, spacing: 20) {
                            HostOptionCard(
                                name: "Sunshine",
                                badge: "Recommended",
                                badgeColor: .green,
                                description: "The most common, open-source streaming host.",
                                benefit: "Simple setup, runs reliably."
                            )
                            
                            Link(destination: URL(string: "https://github.com/LizardByte/Sunshine/releases/latest")!) {
                                Label("Download Sunshine", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.orange.opacity(0.12))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            
                            HostOptionCard(
                                name: "Apollo",
                                badge: "Advanced",
                                badgeColor: .orange,
                                description: "A fork of Sunshine specifically optimized for virtual monitors.",
                                benefit: "Advanced options. Apollo can automatically create a virtual display that matches your stream settings."
                            )
                            
                            Link(destination: URL(string: "https://github.com/ClassicOldSong/Apollo/releases/latest")!) {
                                Label("Download Apollo", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.blue.opacity(0.12))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Basic Server Setup:")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                SetupStep(number: 1, text: "Download & Install Sunshine or Apollo on your gaming PC")
                                SetupStep(number: 2, text: "Access Web UI at https://localhost:47990")
                                SetupStep(number: 3, text: "Find your PC in Moonlight on AVP and enter the PIN shown to authorize")
                            }
                            .padding()
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                                        .overlay(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                                    Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                                    Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            )
                            .cornerRadius(12)
                        }
                    }
                    
                    // Step 2: Optimal Settings
                    GuideSection(
                        title: "Step 2: Optimal Moonlight Settings",
                        icon: "slider.horizontal.3"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Configure these settings in Moonlight before launching your stream:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            SettingRow(
                                setting: "Video Resolution",
                                value: "4K (or Custom Ultrawide)",
                                explanation: "Provides the highest pixel density for the massive virtual screen."
                            )
                            
                            SettingRow(
                                setting: "Frame Rate",
                                value: "90 FPS",
                                explanation: "The standard smooth experience. M5 AVP owners can use 120 FPS."
                            )
                            
                            SettingRow(
                                setting: "Video Bitrate",
                                value: "80-120 Mbps",
                                explanation: "Start high and reduce only if lag occurs. Higher bitrate = Better image quality."
                            )
                            
                            SettingRow(
                                setting: "Video Codec",
                                value: "H.265 (HEVC)",
                                explanation: "The standard, efficient codec supported by all models."
                            )
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Image(systemName: "m.circle.fill")
                                        .foregroundColor(.purple)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("M5 Vision Pro Only: AV1 Codec")
                                            .font(.headline)
                                        Text("AV1 offers superior image quality and compression efficiency. Requires host PC with dedicated hardware support.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                                            .overlay(
                                                LinearGradient(
                                                    colors: [
                                                        Color.purple.opacity(0.20),
                                                        Color.purple.opacity(0.10),
                                                        Color.purple.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                )
                                .cornerRadius(10)
                            }
                        }
                    }
                    
                    // Special Settings Guide
                    GuideSection(
                        title: "Understanding Key Settings",
                        icon: "info.circle"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            SpecialSettingCard(
                                icon: "chart.xyaxis.line",
                                title: "Statistics Overlay",
                                description: "A key diagnostic tool for troubleshooting streaming issues.",
                                details: [
                                    "Shows: Real-time metrics including end-to-end latency (ms), network bandwidth, and actual FPS received by AVP",
                                    "Action: Turn ON only when troubleshooting. Use it to confirm FPS matches your desired 90 FPS setting"
                                ]
                            )
                            
                            SpecialSettingCard(
                                icon: "timer",
                                title: "Frame Pacing Modes",
                                description: "Choose between responsiveness and visual smoothness.",
                                details: [
                                    "Lowest Latency: Displays frames immediately. Best for competitive games where minimum input lag is critical, accepting minor micro-stutters",
                                    "Smoothest Video: Consistent frame display timing. Best for visually demanding games where stutter-free streaming is the priority"
                                ]
                            )

                            SpecialSettingCard(
                                icon: "mic.fill",
                                title: "Mic Streamer Compatibility Mode",
                                description: "Adds a mute button control in Curved Display immersive mode by integrating with Mic Streamer.",
                                details: [
                                    "Run Mic Streamer, start streaming the mic. Toggle Mic Streamer Compatibility Mode On and enjoy mic control while in Curved Display immersive mode."
                                ]
                            )
                        }
                    }
                    
                    // In-Stream Controls & Features Guide
                    GuideSection(
                        title: "In-Stream Controls & Features",
                        icon: "gamecontroller"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Once you're actively streaming, both Standard and Curved Display modes offer powerful controls and features:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            // Control Bar Overview
                            SpecialSettingCard(
                                icon: "rectangle.3.offgrid.bubble.left",
                                title: "Control Bar",
                                description: "Access all streaming controls via the floating control bar at the top of your screen.",
                                details: [
                                    "Auto-hide: Controls fade to a faint state after 5 seconds of inactivity to minimize distractions",
                                    "Reveal: Tap any control button to fully reveal the entire control bar",
                                    "Navigate: When highlighted, tap again to activate the specific control"
                                ]
                            )
                            
                            // Display Mode Switching
                            SpecialSettingCard(
                                icon: "rectangle.2.swap",
                                title: "Seamless Display Mode Switching",
                                description: "Switch between Standard and Curved Display without interrupting your stream.",
                                details: [
                                    "Home Button: Tap the house icon to access the main menu overlay",
                                    "Mode Swap: Use the 'Display Mode' option in settings to switch instantly",
                                    "No Reconnection: Your stream continues uninterrupted during the transition"
                                ]
                            )
                            
                            // Controller Mode
                            SpecialSettingCard(
                                icon: "gamecontroller.fill",
                                title: "Controller Mode (Curved Display Only)",
                                description: "Switch input handling to use physical game controllers in Curved Display mode.",
                                details: [
                                    "Three Input Modes: Toggle between Gaze Control, Screen Adjust, and Controller Mode",
                                    "Controller Mode: When enabled, Bluetooth controllers connected to Vision Pro will function",
                                    "Keyboard: Ensure the keyboard is disabled for controllers to properly function and avoid input conflicts",
                                    "Not Needed in Standard Display: Physical controllers work automatically in Standard Display mode without toggling"
                                ]
                            )
                            
                            // Standard Display Features
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    Image(systemName: "rectangle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Standard Display Features")
                                            .font(.headline)
                                        Text("Traditional windowed gaming with full system integration.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                                            .overlay(
                                                LinearGradient(
                                                    colors: [
                                                        Color.blue.opacity(0.20),
                                                        Color.blue.opacity(0.10),
                                                        Color.blue.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                )
                                .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    InStreamFeature(
                                        icon: "paintpalette",
                                        title: "Preset Color Filters",
                                        description: "Cycle through Cinematic, Vivid, and Realistic visual filters"
                                    )
                                    InStreamFeature(
                                        icon: "moon.fill",
                                        title: "Passthrough Dimming",
                                        description: "Reduce outside distractions with environment dimming"
                                    )
                                    InStreamFeature(
                                        icon: "person.spatialaudio.fill",
                                        title: "Audio Mode Toggle",
                                        description: "Switch between Spatial Audio and Direct Stereo"
                                    )
                                }
                            }
                            
                            // Curved Display Features
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    Image(systemName: "pano.fill")
                                        .foregroundColor(.purple)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Curved Display Features")
                                            .font(.headline)
                                        Text("Immersive curved screen with advanced positioning controls.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                                            .overlay(
                                                LinearGradient(
                                                    colors: [
                                                        Color.purple.opacity(0.20),
                                                        Color.purple.opacity(0.10),
                                                        Color.purple.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                )
                                .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    InStreamFeature(
                                        icon: "crown.fill",
                                        title: "Auto-Recenter",
                                        description: "Hold the Digital Crown to instantly recenter the screen"
                                    )
                                    InStreamFeature(
                                        icon: "arrow.up.left.and.arrow.down.right",
                                        title: "Pinch to Scale",
                                        description: "Pinch with two fingers to resize the screen from 0.5x to 6x"
                                    )
                                    InStreamFeature(
                                        icon: "hand.point.up.left.fill",
                                        title: "Drag Repositioning",
                                        description: "When controls are highlighted, drag the screen to reposition"
                                    )
                                    InStreamFeature(
                                        icon: "pano.fill",
                                        title: "Curvature Presets",
                                        description: "Cycle between Flat, Curved, Immersive, and Extreme curvature"
                                    )
                                    InStreamFeature(
                                        icon: "bed.double.fill",
                                        title: "Screen Tilt",
                                        description: "Adjust screen angle for comfortable viewing positions"
                                    )
                                    InStreamFeature(
                                        icon: "globe.americas.fill",
                                        title: "Environment Spheres",
                                        description: "Immerse yourself with 360° environment backgrounds"
                                    )
                                    InStreamFeature(
                                        icon: "moon.fill",
                                        title: "Advanced Lighting",
                                        description: "Multiple lighting modes including reactive ambient lighting"
                                    )
                                    InStreamFeature(
                                        icon: "paintpalette",
                                        title: "Preset Color Filters",
                                        description: "Cycle through Cinematic, Vivid, and Realistic visual filters"
                                    )
                                }
                            }
                            
                            // Quick Tips
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pro Tips:")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                QuickTip(
                                    icon: "eye.slash.fill",
                                    iconColor: .orange,
                                    tip: "Curved Display Isolation",
                                    detail: "In Curved Display mode, other apps and system windows aren't visible. Switch to Standard Display if you need to multitask."
                                )
                                
                                QuickTip(
                                    icon: "mountain.2.fill",
                                    iconColor: .green,
                                    tip: "Apple Environments",
                                    detail: "Choose an Apple environment first, then use the Sphere controls to reveal and enjoy the scenic backdrop."
                                )
                                
                                QuickTip(
                                    icon: "hand.tap.fill",
                                    iconColor: .blue,
                                    tip: "Wake from Auto-Hide",
                                    detail: "When controls are hidden, simply tap anywhere on the screen to reveal them instantly."
                                )
                            }
                            .padding()
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                                        .overlay(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                                    Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                                    Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            )
                            .cornerRadius(12)
                        }
                    }
                    
                    // Performance Tips
                    GuideSection(
                        title: "Performance Tips",
                        icon: "bolt.circle"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            PerformanceTip(
                                icon: "cable.connector",
                                iconColor: .green,
                                tip: "Wire your PC",
                                detail: "Your gaming PC must be connected to your router via Ethernet."
                            )
                            
                            PerformanceTip(
                                icon: "wifi",
                                iconColor: .orange,
                                tip: "Wi-Fi Optimization",
                                detail: "Manually set your 5 GHz router channel to 149 (or 44). This eliminates rhythmic stuttering caused by Apple's AWDL protocol (AirDrop/Handoff)."
                            )
                            
                            PerformanceTip(
                                icon: "gamecontroller",
                                iconColor: .purple,
                                tip: "Controller Connection",
                                detail: "Connect your controller via Bluetooth directly to the Apple Vision Pro for the lowest latency input."
                            )
                            
                            PerformanceTip(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .red,
                                tip: "Controller Not Working in Curved Display?",
                                detail: "Enable Controller Mode in the control bar and ensure the keyboard is disabled. Standard Display mode doesn't require this toggle."
                            )
                            
                            PerformanceTip(
                                icon: "wrench.and.screwdriver",
                                iconColor: .orange,
                                tip: "Troubleshooting Lag",
                                detail: "If you experience noticeable lag, drop your Bitrate by 20 Mbps and re-test immediately."
                            )
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
}

// MARK: - Supporting Views

struct GuideSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 20)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }
}

struct HostOptionCard: View {
    let name: String
    let badge: String
    let badgeColor: Color
    let description: String
    let benefit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.2))
                    .foregroundColor(badgeColor)
                    .cornerRadius(8)
            }
            
            Text(description)
                .font(.body)
                .foregroundColor(.primary)
            
            Text(benefit)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(
            ZStack {
                // Depth shadow
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)
                
                // Main card
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
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
        .cornerRadius(12)
    }
}

struct SetupStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.orange)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

struct SettingRow: View {
    let setting: String
    let value: String
    let explanation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(setting)
                    .font(.headline)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                    .fontWeight(.medium)
            }
            Text(explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            ZStack {
                // Depth shadow
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)
                
                // Main card
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
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
        .cornerRadius(10)
    }
}

struct SpecialSettingCard: View {
    let icon: String
    let title: String
    let description: String
    let details: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.headline)
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            ZStack {
                // Depth shadow
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)
                
                // Main card
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
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
        .cornerRadius(12)
    }
}

struct PerformanceTip: View {
    let icon: String
    let iconColor: Color
    let tip: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tip)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            ZStack {
                // Depth shadow
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)
                
                // Main card
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                                Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                                Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
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
        .cornerRadius(10)
    }
}

struct InStreamFeature: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct QuickTip: View {
    let icon: String
    let iconColor: Color
    let tip: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tip)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    UserGuideView()
}