//
//  UserGuideView.swift
//  Neo Moonlight
//

import SwiftUI

// MARK: - Guide Tabs

private enum StreamingGuideTab: String, CaseIterable, Identifiable {
    case getStarted
    case settings
    case coop
    case controls
    case tips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .getStarted: return "Get Started"
        case .settings: return "Settings"
        case .coop: return "Co-op"
        case .controls: return "Controls"
        case .tips: return "Tips"
        }
    }

    var icon: String {
        switch self {
        case .getStarted: return "play.circle.fill"
        case .settings: return "slider.horizontal.3"
        case .coop: return "person.2.fill"
        case .controls: return "gamecontroller.fill"
        case .tips: return "bolt.circle.fill"
        }
    }
}

// MARK: - Guide Typography (matches Settings / About)

private enum GuideTypography {
    static let pageTitle = Font.system(size: 34, weight: .bold)
    static let tabIntro = Font.system(size: 16)
    static let sectionTitle = Font.system(size: 19, weight: .semibold)
    static let subsection = Font.system(size: 18, weight: .semibold)
    static let cardTitle = Font.system(size: 18, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 16)
    static let caption = Font.system(size: 14)
    static let finePrint = Font.system(size: 13)
}

// MARK: - User Guide

struct UserGuideView: View {
    var scrollResetID: Int = 0

    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    private let guidePadding: CGFloat = 24
    private let guideScrollTopID = "guideScrollTop"

    @State private var selectedTab: StreamingGuideTab = .getStarted

    var body: some View {
        VStack(spacing: 0) {
            Text("Streaming Guide")
                .font(GuideTypography.pageTitle)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, guidePadding)
                .padding(.top, 12)
                .padding(.bottom, 8)

            guideTabBar
                .padding(.horizontal, guidePadding)
                .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        Color.clear
                            .frame(height: 1)
                            .id(guideScrollTopID)
                        tabContent
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    scrollGuideToTop(proxy: proxy, animated: false)
                }
                .onChange(of: scrollResetID) { _, _ in
                    scrollGuideToTop(proxy: proxy)
                }
                .onChange(of: selectedTab) { _, _ in
                    scrollGuideToTop(proxy: proxy)
                }
            }
        }
    }

    private func scrollGuideToTop(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(guideScrollTopID, anchor: .top)
            }
        } else {
            proxy.scrollTo(guideScrollTopID, anchor: .top)
        }
    }

    private var guideTabBar: some View {
        HStack(spacing: 6) {
            ForEach(StreamingGuideTab.allCases) { tab in
                GuideTabChip(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: selectedTab == tab,
                    brandBlue: brandBlue
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .getStarted: getStartedTab
        case .settings: settingsTab
        case .coop: coopTab
        case .controls: controlsTab
        case .tips: tipsTab
        }
    }
}

// MARK: - Get Started

private extension UserGuideView {
    var getStartedTab: some View {
        VStack(spacing: 20) {
            GuideTabIntro(
                "New to Neo Moonlight? Follow these steps in order on your gaming PC and Vision Pro. You can fine-tune Sunshine later—the goal here is to get paired and streaming."
            )

            GuideSection(title: "First-time setup walkthrough", icon: "list.number", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 20) {
                    GuideWalkthroughStep(
                        number: 1,
                        title: "Choose the host software for your PC",
                        intro: "Sunshine is recommended for most users. Apollo is an advanced option if you need virtual monitor features.",
                        color: brandBlue
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HostOptionCard(
                            name: "Sunshine",
                            badge: "Recommended",
                            badgeColor: .green,
                            description: "The most common, open-source streaming host.",
                            benefit: "Simple setup, runs reliably."
                        )
                        sunshineDownloadLink
                        HostOptionCard(
                            name: "Apollo",
                            badge: "Advanced",
                            badgeColor: brandBlue,
                            description: "A fork of Sunshine specifically optimized for virtual monitors.",
                            benefit: "Advanced options. Apollo can automatically create a virtual display that matches your stream settings."
                        )
                        apolloDownloadLink
                    }
                    .padding(.leading, 40)

                    GuideWalkthroughStep(
                        number: 2,
                        title: "Install and allow through firewall",
                        details: [
                            "Run the installer on your gaming PC and finish setup.",
                            "If Windows Firewall asks, allow Sunshine or Apollo so your Vision Pro can reach the PC."
                        ],
                        color: brandBlue
                    )

                    GuideWalkthroughStep(
                        number: 3,
                        title: "Confirm the host is running",
                        details: [
                            "You should see Sunshine or Apollo running on the PC (tray icon or service).",
                            "On the gaming PC, open https://localhost:47990 in a browser to open the host web UI."
                        ],
                        color: brandBlue
                    )

                    GuideWalkthroughStep(
                        number: 4,
                        title: "Pair your Vision Pro",
                        details: [
                            "On Vision Pro, open Neo Moonlight.",
                            "Your PC should appear on the same network. Select it and note the PIN shown on your headset.",
                            "In Sunshine, enter that PIN to authorize this device.",
                            "If using Apollo, enable all permissions on the PIN page when pairing."
                        ],
                        color: brandBlue
                    )

                    GuideWalkthroughStep(
                        number: 5,
                        title: "Set stream options on Vision Pro",
                        details: [
                            "In Neo Moonlight, open the Settings tab.",
                            "Use the recommended resolution, frame rate, bitrate, and codec from the Settings section of this guide.",
                            "You can change these anytime; start with the defaults and adjust if you see lag or quality issues."
                        ],
                        color: brandBlue
                    )

                    GuideWalkthroughStep(
                        number: 6,
                        title: "Match codecs on the PC (quick check)",
                        details: [
                            "In Sunshine Configuration → Audio/Video, enable HEVC (and AV1 if you plan to use it on M5).",
                            "Set the same codec in Neo Moonlight Settings → Preferred Codec.",
                            
                        ],
                        color: brandBlue
                    )

                    GuideWalkthroughStep(
                        number: 7,
                        title: "Start your first stream",
                        details: [
                            "In Neo Moonlight select your paired PC.",
                            "Choose Desktop, then connect. The stream should start.",
                        ],
                        color: brandBlue
                    )
                }
            }

            sunshineEncoderOptionalSection
        }
    }

    var sunshineEncoderOptionalSection: some View {
        GuideSection(title: "Sunshine encoder settings", icon: "cpu", iconColor: brandBlue) {
            VStack(alignment: .leading, spacing: 20) {
                Text("After your first successful stream, you can tune these on the gaming PC for better quality or lower latency. Not required for setup.")
                    .font(GuideTypography.body)
                    .foregroundColor(.white.opacity(0.75))
                    .lineSpacing(3)

                Divider().background(Color.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 10) {
                    GuideSubsectionTitle("Codecs", color: brandBlue)
                    Text("In Sunshine Configuration → Audio/Video, enable the codecs you plan to use. Set the same choice in Neo Moonlight Settings → Preferred Codec.")
                        .font(GuideTypography.caption)
                        .foregroundColor(.white.opacity(0.72))
                        .lineSpacing(2)

                    GuideSunshinePickRow(
                        label: "H.264",
                        detail: "Widest compatibility; needs more bitrate than HEVC or AV1 for the same look.",
                        brandBlue: brandBlue
                    )
                    GuideSunshinePickRow(
                        label: "HEVC",
                        detail: "Efficient default for all Vision Pro models.",
                        badge: .recommended,
                        brandBlue: brandBlue
                    )
                    GuideSunshinePickRow(
                        label: "AV1",
                        detail: "Enable if you own a M5 Vision Pro. Offers better compression and slightly better image quality.",
                        
                        brandBlue: brandBlue
                    )
                }

                Divider().background(Color.white.opacity(0.15))

                GuideSubsectionTitle("Encoder settings", color: .white)

                GuideSunshineSettingExplainer(
                        title: "NVENC PQ mode",
                        platform: "NVIDIA",
                        whatItIs: "Encoder preset on a P1–P7 scale. Lower numbers favor speed and lower latency; higher numbers favor image quality with more GPU work and delay.",
                        recommendedPick: "P4",
                        gamingNotes: "Use P1–P3 if latency or GPU load is high. Try P6–P7 only when quality matters more than snappiness.",
                        brandBlue: brandBlue
                    )

                    GuideSunshineSettingExplainer(
                        title: "Two-pass",
                        platform: "NVIDIA",
                        whatItIs: "Two-pass mode makes the encoder analyze frames before fully compressing them so it can allocate bitrate more efficiently and improve image quality.",
                        recommendedPick: "Quarter resolution",
                        gamingNotes: "Quarter resolution fits most Wi‑Fi setups. Disabled is lowest latency but can artifact more. Full res is slower and rarely worth it on a strong local network.",
                        brandBlue: brandBlue
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("AMF usage")
                                .font(GuideTypography.subsection)
                                .foregroundColor(.white)
                            Text("AMD")
                                .font(GuideTypography.finePrint)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(brandBlue.opacity(0.25))
                                .foregroundColor(brandBlue)
                                .cornerRadius(4)
                        }
                        Text("Chooses the encoder profile on AMD GPUs")
                            .font(GuideTypography.caption)
                            .foregroundColor(.white.opacity(0.65))

                        GuideSunshinePickRow(label: "Ultralowlatency", detail: "Minimum delay for live play and game streaming.", gaming: "Default for Neo Moonlight gaming.", badge: .recommended, brandBlue: brandBlue)
                        GuideSunshinePickRow(label: "Lowlatency", detail: "Still real-time, slightly less aggressive than ultralowlatency.", gaming: "Try if ultralowlatency stutters or spikes GPU usage.", brandBlue: brandBlue)
                        GuideSunshinePickRow(label: "Transcoding", detail: "Optimized for converting or processing video, not twitch gameplay.", gaming: "Avoid for games — can feel laggy or mushy.", brandBlue: brandBlue)
                        GuideSunshinePickRow(label: "Webcam", detail: "Tuned for camera-style live capture.", gaming: "Rare fallback only.", brandBlue: brandBlue)
                        GuideSunshinePickRow(label: "High quality", detail: "Favors picture over response time.", gaming: "Desktop or slow content only, not action games.", brandBlue: brandBlue)
                        GuideSunshinePickRow(label: "Low latency high quality", detail: "Middle ground between quality and delay.", gaming: "Experiment only if other modes misbehave.", brandBlue: brandBlue)
                    }

                    GuideSunshineSettingExplainer(
                        title: "AMF quality",
                        platform: "AMD",
                        whatItIs: "How hard the encoder works within the usage mode you picked (Speed, Balanced, Quality).",
                        recommendedPick: "Balanced",
                        gamingNotes: "Use Quality if the GPU has headroom. Use Speed if the GPU is maxed.",
                        brandBlue: brandBlue
                    )

                Text("If the PC struggles, step NVENC toward P1–P3 or AMF Quality toward Speed before lowering app bitrate.")
                    .font(GuideTypography.finePrint)
                    .foregroundColor(.white.opacity(0.6))
                    .italic()
            }
        }
    }

    var sunshineDownloadLink: some View {
        Link(destination: URL(string: "https://github.com/LizardByte/Sunshine/releases/latest")!) {
            Label("Download Sunshine", systemImage: "arrow.down.circle.fill")
                .font(GuideTypography.rowTitle)
                .foregroundColor(brandBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(brandBlue.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(brandBlue.opacity(0.35), lineWidth: 1))
        }
    }

    var apolloDownloadLink: some View {
        Link(destination: URL(string: "https://github.com/ClassicOldSong/Apollo/releases/latest")!) {
            Label("Download Apollo", systemImage: "arrow.down.circle.fill")
                .font(GuideTypography.rowTitle)
                .foregroundColor(brandBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(brandBlue.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(brandBlue.opacity(0.35), lineWidth: 1))
        }
    }

}

// MARK: - Settings Tab

private extension UserGuideView {
    var settingsTab: some View {
        VStack(spacing: 20) {
            GuideTabIntro(
                "Stream quality is controlled on your Vision Pro in the app Settings tab. The values below are a solid starting point for image quality and smooth playback—adjust them if your network or games need something different."
            )

            GuideSection(title: "Recommended Neo Moonlight Settings", icon: "slider.horizontal.3", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 16) {
                    GuideSettingRow(setting: "Video Resolution", value: "4K or Custom Ultrawide", explanation: "Highest pixel density for the virtual screen.", valueColor: brandBlue)
                    GuideSettingRow(setting: "Frame Rate", value: "90 FPS", explanation: "Standard smooth experience. M5 supports 120 FPS for solo streaming.", valueColor: brandBlue)
                    GuideSettingRow(setting: "Video Bitrate", value: "80–120 Mbps", explanation: "Start at 120 and reduce if lag or stuttering occurs.", valueColor: brandBlue)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bitrate Warning")
                                .font(GuideTypography.rowTitle)
                                .foregroundColor(.white)
                            Text("Bitrates over 300 Mbps need an extremely fast, stable network or you may see stutter and frame drops.")
                                .font(GuideTypography.caption)
                                .foregroundColor(.white.opacity(0.72))
                                .lineSpacing(2)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)

                    GuideSettingRow(setting: "Preferred Codec", value: "HEVC", explanation: "Efficient default for all Vision Pro models.", valueColor: brandBlue)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "m.circle.fill")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("M5: AV1")
                                .font(GuideTypography.rowTitle)
                                .foregroundColor(.white)
                            Text("Slightly better image quality and compression. Enable AV1 in Sunshine and set Preferred Codec to AV1 (M5 only).")
                                .font(GuideTypography.caption)
                                .foregroundColor(.white.opacity(0.72))
                                .lineSpacing(2)
                        }
                    }
                    .padding()
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(10)

                    GuideSettingRow(setting: "Enable HDR", value: "On", explanation: "Turn on HDR on the host display and in app Settings. Mismatched HDR can look washed or too dark.", valueColor: brandBlue)
                }
            }

            GuideSection(title: "Understanding Key Settings", icon: "info.circle", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 16) {
                    SpecialSettingCard(
                        icon: "chart.xyaxis.line",
                        iconColor: brandBlue,
                        title: "Statistics Overlay",
                        description: "Diagnostic tool for troubleshooting streaming issues.",
                        details: ["Shows end-to-end latency (ms), network bandwidth, and FPS received by Vision Pro."]
                    )
                    SpecialSettingCard(
                        icon: "timer",
                        iconColor: brandBlue,
                        title: "Frame Pacing Modes",
                        description: "Responsiveness vs visual smoothness.",
                        details: [
                            "Lowest Latency: Frames display immediately. Best for competitive play.",
                            "Smoothest Video: Consistent timing. Best when stutter-free video is the priority."
                        ]
                    )
                    SpecialSettingCard(
                        icon: "mic.fill",
                        iconColor: brandBlue,
                        title: "Mic Streamer Compatibility Mode",
                        description: "Mute control in Curved Display immersive mode with Mic Streamer.",
                        details: ["Run Mic Streamer, start the mic stream, then enable this toggle in Settings."]
                    )
                }
            }
        }
    }
}

// MARK: - Co-op Tab

private extension UserGuideView {
    var coopTab: some View {
        VStack(spacing: 20) {
            GuideTabIntro(
                "Play couch co-op games with another person who owns a Vision Pro - online or locally. Only the host needs to own the game on their PC. Controllers must be connected to Vision Pro Bluetooth and set to Single/Co-op in settings. In Flat Display mode, you can see your buddy's Persona sitting next to you. Requires a strong connection."
            )

            GuideSection(title: "Co-op Gameplay", icon: "person.2.fill", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 16) {
                    hostCoopBlock
                guestCoopBlock
                    coopImportantNotes
                }
            }
        }
    }

    var hostCoopBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            coopRoleHeader(icon: "person.crop.circle.badge.checkmark", color: .orange, title: "Host Setup", subtitle: "The person who owns the gaming PC starts and manages the session.")
            coopNetworkBlock
            VStack(alignment: .leading, spacing: 10) {
                CoopStep(text: "Start a FaceTime call with your friend")
                CoopStep(text: "In Neo Moonlight Settings, set Controller Mode to Single/Co-op")
                CoopStep(text: "Click the Co-op button on the main menu, then Host Co-op Session")
                CoopStep(text: "Select your PC or app. Use Desktop or a physical monitor app — Apollo virtual displays are not supported for co-op.")
                CoopStep(text: "Choose Local or Online mode, then Start Co-op Session. Select SharePlay (not SharePlay for Me).")
                CoopStep(text: "Authorize the guest PIN in Sunshine/Apollo when prompted. Enable all permissions including controller for the guest in Apollo.")
                
            }
            .padding()
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }

    var guestCoopBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            coopRoleHeader(icon: "person.crop.circle.badge.plus", color: .pink, title: "Guest Setup", subtitle: "Join your friend's session and play together.")
            VStack(alignment: .leading, spacing: 10) {
                CoopStep(text: "Join the host's FaceTime call")
                CoopStep(text: "In Settings, set Controller Mode to Single/Co-op")
                CoopStep(text: "When the host starts, open the SharePlay notification")
                CoopStep(text: "In Neo Moonlight, Co-op → Join Co-op Session → select the session")
                CoopStep(text: "First-time guests: share your PIN with the host for authorization in Sunshine/Apollo")
            }
            .padding()
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }

    func coopRoleHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GuideTypography.cardTitle)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding()
        .background(color.opacity(0.15))
        .cornerRadius(10)
    }

    var coopNetworkBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Connection Mode", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                coopConnectionRow(icon: "house.fill", color: .green, title: "Local Mode", detail: "Both players on the same Wi-Fi. No extra setup.")
                coopConnectionRow(icon: "globe", color: .orange, title: "Online Mode", detail: "Remote play over the internet. Requires port forwarding.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Port Forwarding (Online Only)", systemImage: "exclamationmark.triangle.fill")
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Text("Forward these ports to your gaming PC's local IP:")
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.78))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TCP").font(.caption).fontWeight(.bold).foregroundColor(.orange).frame(width: 40, alignment: .leading)
                        Text("47984-47990, 48000-48010").font(.caption).foregroundColor(.white)
                    }
                    HStack {
                        Text("UDP").font(.caption).fontWeight(.bold).foregroundColor(.orange).frame(width: 40, alignment: .leading)
                        Text("47998-48010").font(.caption).foregroundColor(.white)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                Text("Opening ports exposes your PC online. Only share with people you trust. VPN options like Tailscale or ZeroTier are more secure alternatives.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    func coopConnectionRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.caption).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(GuideTypography.rowTitle).foregroundColor(.white)
                Text(detail).font(GuideTypography.finePrint).foregroundColor(.white.opacity(0.72))
            }
        }
    }

    var coopImportantNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSubsectionTitle("Important Notes", color: brandBlue)
            QuickTip(icon: "exclamationmark.triangle.fill", iconColor: .yellow, tip: "Experimental", detail: "Co-op is highly experimental. You may encounter bugs or connection issues.")
            QuickTip(icon: "person.2.fill", iconColor: .blue, tip: "Maximum Players", detail: "Two players max (1 host + 1 guest).")
            QuickTip(icon: "video.fill", iconColor: .orange, tip: "FaceTime Required", detail: "Both players need an active FaceTime call.")
            QuickTip(icon: "gamecontroller.fill", iconColor: .purple, tip: "Controllers", detail: "Pair controllers before joining. Use Single/Co-op in Settings.")
            QuickTip(icon: "wifi", iconColor: .green, tip: "Network", detail: "Same LAN works best. For online play, lower resolution (1080p/1440p) and bitrate if quality suffers. See Tips tab for general lag fixes.")
            QuickTip(icon: "slider.horizontal.3", iconColor: brandBlue, tip: "Frame Rate", detail: "Co-op runs at 90 FPS. Solo M5 streaming supports up to 120 FPS.")
            QuickTip(icon: "envelope.badge.fill", iconColor: .orange, tip: "Re-invite Guest", detail: "Use the Invite button in the stream bar if your guest disconnects.")
            QuickTip(icon: "key.fill", iconColor: .cyan, tip: "PIN Authorization", detail: "First-time guests need host authorization in Sunshine/Apollo. Apollo: enable all guest permissions including controller.")
            QuickTip(icon: "shield.fill", iconColor: .red, tip: "Firewall", detail: "Online mode: allow Sunshine/Apollo through Windows Firewall and antivirus.")
            coopPortCheckerBlock
            QuickTip(icon: "person.crop.circle", iconColor: .purple, tip: "FaceTime Personas", detail: "Curved immersive mode hides personas. Flat Display shows them during co-op.")
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    var coopPortCheckerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Testing Port Forwarding", systemImage: "network")
                .font(GuideTypography.rowTitle)
                .foregroundColor(.white)
            Text("With Sunshine running, verify ports with a port checker:")
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.72))
            HStack(spacing: 12) {
                Link("CanYouSeeMe.org", destination: URL(string: "https://canyouseeme.org")!)
                    .font(.caption)
                    .foregroundColor(brandBlue)
                Link("Portchecker.io", destination: URL(string: "https://portchecker.io")!)
                    .font(.caption)
                    .foregroundColor(brandBlue)
            }
            Text("Test 47984, 47990, 48010. Open/Success means forwarding works.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

// MARK: - Controls Tab

private extension UserGuideView {
    var controlsTab: some View {
        VStack(spacing: 20) {
            GuideTabIntro(
                "On Curved Display, the input mode button in the top stream bar switches how you interact with the stream. Select Accessory Mode when using a Bluetooth gamepad or mouse."
            )

            GuideSection(title: "Input Modes", icon: "gamecontroller.fill", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap the input mode button in the stream bar to cycle between three modes:")
                        .font(GuideTypography.body)
                        .foregroundColor(.white.opacity(0.85))

                    GuideControlModeRow(
                        icon: "eye.fill",
                        title: "Gaze Control Mode",
                        detail: "Control the cursor with your eyes or hands (double pinch to click).",
                        brandBlue: brandBlue
                    )
                    GuideControlModeRow(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: "Screen Adjust Mode",
                        detail: "Move, resize, tilt, and rotate the screen. Use Gaze or Accessory Mode to enable keyboard.",
                        brandBlue: brandBlue
                    )
                    GuideControlModeRow(
                        icon: "gamecontroller.fill",
                        title: "Accessory Mode",
                        detail: "Required for Bluetooth gamepads and mice paired to Vision Pro.",
                        brandBlue: brandBlue
                    )

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 22)
                        Text("In Gaze Control Mode, long-press the input mode button to temporarily lock input (for example while eating). Long-press in Screen Adjust resets the screen.")
                            .font(GuideTypography.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .lineSpacing(2)
                    }
                    .padding(.top, 4)

                    controllerTroubleshootingBlock
                }
            }
        }
    }

    var controllerTroubleshootingBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controller or mouse not working?")
                .font(GuideTypography.subsection)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 8) {
                troubleshootingRow("1", "Select Accessory Mode on Curved Display.")
                troubleshootingRow("2", "Turn off the on-screen keyboard in the stream bar.")
                troubleshootingRow("3", "For co-op: set Controller Mode to Single/Co-op in Settings, and ensure the host has authorized your gamepad in the Sunshine PIN settings.")
            }
        }
        .padding()
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    func troubleshootingRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .frame(width: 16)
            Text(text)
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.88))
                .lineSpacing(2)
        }
    }
}

// MARK: - Tips Tab

private extension UserGuideView {
    var tipsTab: some View {
        VStack(spacing: 20) {
            GuideTabIntro(
                "Once you are streaming, these network and performance tips can help reduce stutter and input lag beyond what you set in the Settings tab."
            )

            GuideSection(title: "Performance & Network Tips", icon: "bolt.circle", iconColor: brandBlue) {
                VStack(alignment: .leading, spacing: 12) {
                    PerformanceTip(icon: "cable.connector", iconColor: .green, tip: "Wire your PC", detail: "Connect the gaming PC to your router via Ethernet.")
                    PerformanceTip(icon: "wifi", iconColor: brandBlue, tip: "Wi-Fi Channel", detail: "Try router channel 149 or 44 to reduce stuttering from AWDL (AirDrop/Handoff).")
                PerformanceTip(icon: "gamecontroller", iconColor: brandBlue, tip: "Accessories", detail: "On Curved Display, switch to Accessory Mode in the stream bar for gamepads and mice.")
                PerformanceTip(icon: "wrench.and.screwdriver", iconColor: brandBlue, tip: "Troubleshooting Lag", detail: "Drop bitrate by about 20 Mbps and re-test. Check Statistics Overlay in Settings.")
                }
            }
        }
    }
}

// MARK: - Sunshine / Tab Components

struct GuideTabIntro: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(GuideTypography.tabIntro)
            .foregroundColor(.white.opacity(0.75))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
    }
}

struct GuideSubsectionTitle: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(GuideTypography.subsection)
            .foregroundColor(color)
            .tracking(0.2)
    }
}

struct GuideControlModeRow: View {
    let icon: String
    let title: String
    let detail: String
    let brandBlue: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(brandBlue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Text(detail)
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .lineSpacing(2)
            }
        }
    }
}

struct GuideTabChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let brandBlue: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(GuideTypography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? brandBlue.opacity(0.45) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? brandBlue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

enum GuideSunshinePickBadge {
    case recommended
    case m5
}

struct GuideSunshinePickRow: View {
    let label: String
    let detail: String
    var gaming: String? = nil
    var badge: GuideSunshinePickBadge? = nil
    let brandBlue: Color

    private var labelColor: Color {
        switch badge {
        case .recommended, .m5: brandBlue
        case nil: .white
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(labelColor)
                switch badge {
                case .recommended:
                    Text("Recommended")
                        .font(.caption2)
                        .foregroundColor(.green)
                case .m5:
                    Text("M5")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                case nil:
                    EmptyView()
                }
            }
            Text(detail)
                .font(GuideTypography.finePrint)
                .foregroundColor(.white.opacity(0.65))
            if let gaming {
                Text(gaming)
                    .font(GuideTypography.finePrint)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.leading, 4)
    }
}

struct GuideSunshineSettingExplainer: View {
    let title: String
    let platform: String
    let whatItIs: String
    var recommendedPick: String? = nil
    var gamingNotes: String = ""
    let brandBlue: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Text(platform)
                    .font(GuideTypography.finePrint)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(brandBlue.opacity(0.25))
                    .foregroundColor(brandBlue)
                    .cornerRadius(4)
            }
            Text("What it is: \(whatItIs)")
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.72))
                .lineSpacing(2)
            if let recommendedPick {
                HStack(spacing: 6) {
                    Text(recommendedPick)
                        .font(GuideTypography.rowTitle)
                        .foregroundColor(brandBlue)
                    Text("Recommended")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            if !gamingNotes.isEmpty {
                Text(gamingNotes)
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.92))
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
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
                .font(GuideTypography.sectionTitle)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                        .offset(y: 6)
                        .blur(radius: 12)

                    RoundedRectangle(cornerRadius: 20)
                        .fill(MenuCardStyle.fill)
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
                    .font(GuideTypography.cardTitle)
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
                .font(GuideTypography.body)
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(2)
            Text(benefit)
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.62))
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
                .font(GuideTypography.body)
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(2)
        }
    }
}

struct GuideWalkthroughStep: View {
    let number: Int
    let title: String
    var intro: String? = nil
    var details: [String] = []
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(GuideTypography.cardTitle)
                    .foregroundColor(.white)

                if let intro {
                    Text(intro)
                        .font(GuideTypography.body)
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(2)
                }

                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(details, id: \.self) { detail in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(GuideTypography.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                Text(detail)
                                    .font(GuideTypography.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }
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
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(valueColor)
            }
            Text(explanation)
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.65))
                .lineSpacing(2)
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
                    .font(GuideTypography.cardTitle)
                    .foregroundColor(.white)
            }
            Text(description)
                .font(GuideTypography.body)
                .foregroundColor(.white.opacity(0.88))
                .lineSpacing(2)
            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            Text(detail)
                                .font(GuideTypography.caption)
                                .foregroundColor(.white.opacity(0.72))
                                .lineSpacing(2)
                        }
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
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Text(detail)
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .lineSpacing(2)
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
                    .font(GuideTypography.rowTitle)
                    .foregroundColor(.white)
                Text(detail)
                    .font(GuideTypography.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .lineSpacing(2)
            }
        }
    }
}

struct CoopStep: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.7))
                .frame(width: 16)
            Text(text)
                .font(GuideTypography.caption)
                .foregroundColor(.white.opacity(0.88))
                .lineSpacing(2)
        }
    }
}

#Preview {
    UserGuideView()
}
