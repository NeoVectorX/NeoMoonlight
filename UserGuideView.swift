//
//  UserGuideView.swift
//  Moonlight Vision
//
//  Created by NeoVectorX on 2/2/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct UserGuideView: View {
    // Define brand color
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Streaming Guide")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Step 1: Host Software
                GuideSection(
                    title: "Step 1: Choosing Your Host Software",
                    icon: "server.rack",
                    iconColor: brandBlue
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
                                .foregroundColor(brandBlue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(brandBlue.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(brandBlue.opacity(0.35), lineWidth: 1)
                                )
                        }
                        
                        HostOptionCard(
                            name: "Apollo",
                            badge: "Advanced",
                            badgeColor: brandBlue,
                            description: "A fork of Sunshine specifically optimized for virtual monitors.",
                            benefit: "Advanced options. Apollo can automatically create a virtual display that matches your stream settings."
                        )
                        
                        Link(destination: URL(string: "https://github.com/ClassicOldSong/Apollo/releases/latest")!) {
                            Label("Download Apollo", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .foregroundColor(brandBlue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(brandBlue.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(brandBlue.opacity(0.35), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Basic Server Setup:")
                                .font(.headline)
                                .foregroundColor(brandBlue)
                                .padding(.top, 8)
                            
                            SetupStep(number: 1, text: "Download & Install Sunshine or Apollo on your gaming PC", color: brandBlue)
                            SetupStep(number: 2, text: "Access Web UI at https://localhost:47990", color: brandBlue)
                            SetupStep(number: 3, text: "Find your PC in Moonlight on AVP and enter the PIN shown to authorize", color: brandBlue)
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
                
                // Step 2: Optimal Settings
                GuideSection(
                    title: "Step 2: Optimal Moonlight Settings",
                    icon: "slider.horizontal.3",
                    iconColor: brandBlue
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configure these settings in Moonlight before launching your stream:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                        
                        GuideSettingRow(
                            setting: "Video Resolution",
                            value: "4K (or Custom Ultrawide)",
                            explanation: "Provides the highest pixel density for the massive virtual screen.",
                            valueColor: brandBlue
                        )
                        
                        GuideSettingRow(
                            setting: "Frame Rate",
                            value: "90 FPS",
                            explanation: "The standard smooth experience. M5 AVP owners can use 120 FPS.",
                            valueColor: brandBlue
                        )
                        
                        GuideSettingRow(
                            setting: "Video Bitrate",
                            value: "80-120 Mbps",
                            explanation: "Start at 120 and reduce if lag or stuttering occurs.",
                            valueColor: brandBlue
                        )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bitrate Warning")
                                        .font(.headline)
                                    Text("Bitrates over 300 Mbps require extreme optimal network conditions. Only use higher bitrates if you have a stable, extremely high-speed connection, otherwise stuttering and framerate issues will occur.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(10)
                        }
                        
                        GuideSettingRow(
                            setting: "Video Codec",
                            value: "H.265 (HEVC)",
                            explanation: "The standard, efficient codec supported by all models.",
                            valueColor: brandBlue
                        )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Image(systemName: "m.circle.fill")
                                    .foregroundColor(.purple)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("M5 Vision Pro Only: AV1 Codec")
                                        .font(.headline)
                                    Text("AV1 offers slightly improved image quality and compression efficiency.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(10)
                        }
                    }
                }
                
                // Special Settings Guide
                GuideSection(
                    title: "Understanding Key Settings",
                    icon: "info.circle",
                    iconColor: brandBlue
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        SpecialSettingCard(
                            icon: "chart.xyaxis.line",
                            iconColor: brandBlue,
                            title: "Statistics Overlay",
                            description: "A key diagnostic tool for troubleshooting streaming issues.",
                            details: [
                                "Shows: Real-time metrics including end-to-end latency (ms), network bandwidth, and actual FPS received by AVP"
                            ]
                        )
                        
                        SpecialSettingCard(
                            icon: "timer",
                            iconColor: brandBlue,
                            title: "Frame Pacing Modes",
                            description: "Choose between responsiveness and visual smoothness.",
                            details: [
                                "Lowest Latency: Displays frames immediately. Best for competitive games where minimum input lag is critical, accepting minor micro-stutters",
                                "Smoothest Video: Consistent frame display timing. Best for visually demanding games where stutter-free streaming is the priority"
                            ]
                        )
                    }
                }
                
                // In-Stream Controls & Features Guide
                GuideSection(
                    title: "In-Stream Controls & Features",
                    icon: "gamecontroller",
                    iconColor: brandBlue
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Once you're actively streaming, both Standard and Curved Display modes offer powerful controls and features:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 4)
                        
                        // Standard Display Features
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Image(systemName: "rectangle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Standard Display Features")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Traditional windowed gaming with full system integration.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding()
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InStreamFeature(
                                    icon: "paintpalette",
                                    title: "Preset Color Grading",
                                    description: "Cycle through Cinematic, Vivid, and Realistic visual presets",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "moon.fill",
                                    title: "Passthrough Dimming",
                                    description: "Reduce outside distractions with environment dimming",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "person.spatialaudio.fill",
                                    title: "Audio Mode Toggle",
                                    description: "Switch between Spatial Audio and Direct Stereo",
                                    brandBlue: brandBlue
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
                                        .foregroundColor(.white)
                                    Text("Immersive curved screen with advanced positioning controls.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding()
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InStreamFeature(
                                    icon: "crown.fill",
                                    title: "Auto-Recenter",
                                    description: "Hold the Digital Crown to instantly recenter the screen",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "arrow.up.left.and.arrow.down.right",
                                    title: "Pinch to Scale",
                                    description: "Pinch with two fingers to resize the screen",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "hand.point.up.left.fill",
                                    title: "Screen AutoLock",
                                    description: "The screen auto locks when the icons fade out. Click the icons to highlight them, then pinch-hold the screen to drag the screen to preferred position ",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "pano.fill",
                                    title: "Curvature Presets",
                                    description: "Cycle between 1800R, 1000R, and 800R",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "bed.double.fill",
                                    title: "Screen Tilt",
                                    description: "Adjust screen angle for comfortable viewing positions",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "globe.americas.fill",
                                    title: "360° Environments",
                                    description: "Immerse yourself within 360° environment backgrounds",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "moon.fill",
                                    title: "Advanced Dimming",
                                    description: "Multiple dimming modes",
                                    brandBlue: brandBlue
                                )
                                InStreamFeature(
                                    icon: "paintpalette",
                                    title: "Preset Color Grading",
                                    description: "Cycle through Cinematic, Vivid, and Realistic visual presets",
                                    brandBlue: brandBlue
                                )
                            }
                        }
                        
                        // Quick Tips
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pro Tips:")
                                .font(.headline)
                                .foregroundColor(brandBlue)
                                .padding(.top, 8)
                            
                            QuickTip(
                                icon: "eye.slash.fill",
                                iconColor: .orange,
                                tip: "Curved Display Immersive Mode",
                                detail: "In Curved Display mode, other apps and system windows will not be visible. Switch to Standard Display if you need to multitask. "
                            )
                            
                            QuickTip(
                                icon: "mountain.2.fill",
                                iconColor: .green,
                                tip: "Apple Environments",
                                detail: "Choose an Apple environment first, launch Curved Display mode, then rotate the digital crown wheel to reveal the scenic backdrop."
                            )
                            
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
                
                // Performance Tips
                GuideSection(
                    title: "Performance Tips",
                    icon: "bolt.circle",
                    iconColor: brandBlue
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
                            iconColor: brandBlue,
                            tip: "Wi-Fi Optimization",
                            detail: "Manually set your 5 GHz router channel to 149 (or 44). This eliminates rhythmic stuttering caused by Apple's AWDL protocol (AirDrop/Handoff)."
                        )
                        
                        PerformanceTip(
                            icon: "gamecontroller",
                            iconColor: brandBlue,
                            tip: "Controller Connection",
                            detail: "Connect your controller via Bluetooth directly to your PC for the lowest latency input."
                        )
                        
                        PerformanceTip(
                            icon: "wrench.and.screwdriver",
                            iconColor: brandBlue,
                            tip: "Troubleshooting Lag",
                            detail: "If you experience noticeable lag, drop your Bitrate by 20 Mbps and re-test immediately."
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Supporting Views

struct GuideSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                ZStack {
                    // Depth shadow
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                        .offset(y: 6)
                        .blur(radius: 12)
                    
                    // Main card - matching ComputerView blue background
                    RoundedRectangle(cornerRadius: 20)
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
                    .foregroundColor(.white)
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
                .foregroundColor(.white.opacity(0.9))
            
            Text(benefit)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .italic()
        }
    }
}

struct SetupStep: View {
    let number: Int
    let text: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct GuideSettingRow: View {
    let setting: String
    let value: String
    let explanation: String
    let valueColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(setting)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(valueColor)
                    .fontWeight(.medium)
            }
            Text(explanation)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct SpecialSettingCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let details: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.white.opacity(0.6))
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
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
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct InStreamFeature: View {
    let icon: String
    let title: String
    let description: String
    let brandBlue: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(brandBlue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
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
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    UserGuideView()
}
