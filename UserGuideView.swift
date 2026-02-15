//
//  UserGuideView.swift
//  Neo Moonlight
//
//  
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
                    title: "Step 2: Recommended Moonlight Settings",
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
                                    Text("AV1 offers slightly improved image quality and higher compression efficiency.")
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

                        SpecialSettingCard(
                            icon: "gamecontroller.fill",
                            iconColor: brandBlue,
                            title: "Input Mode Toggle (Curved Display)",
                            description: "Cycle through three input modes in Curved Display mode for different use cases.",
                            details: [
                                "Three Input Modes: Toggle between Gaze Control, Screen Adjust, and Controller Mode",
                                "Controller Mode: When enabled, Bluetooth controllers connected to Vision Pro will function. Ensure keyboard is disabled to avoid conflict with controller input"
                            ]
                        )

                        SpecialSettingCard(
                            icon: "mic.fill",
                            iconColor: brandBlue,
                            title: "Mic Streamer Compatibility Mode",
                            description: "Adds a mute button in Curved Display immersive mode that connects to Mic Streamer.",
                            details: [
                                "Run Mic Streamer and start streaming the mic. Toggle Mic Streamer Compatibility Mode On for mic control while in the Curved Display immersive mode"
                            ]
                        )
                    }
                }
                
                // Co-op Gameplay Section
                GuideSection(
                    title: "Co-op Gameplay",
                    icon: "person.2.fill",
                    iconColor: brandBlue
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Play together with a friend using SharePlay. One person hosts the session while the other joins as a guest.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                        
                        // Host Instructions
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Host Setup")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("The person who owns the gaming PC starts and manages the session.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(10)
                            
                            // Network Configuration for Hosts
                            VStack(alignment: .leading, spacing: 16) {
                                // Connection Mode Selection
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                                            .foregroundColor(brandBlue)
                                        Text("Connection Mode")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Choose your connection mode when hosting:")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.leading, 28)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "house.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Local Mode")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                                Text("Both players on the same Wi-Fi network. No setup required.")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                        
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "globe")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Online Mode")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                                Text("Playing remotely over the internet. Requires port forwarding.")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                    }
                                    .padding(.leading, 28)
                                }
                                
                                // Port Forwarding Requirements
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Port Forwarding (Online Mode Only)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("If using Online Mode, you MUST forward these ports on your router or the connection will fail:")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.leading, 28)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 12) {
                                            Text("TCP")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.orange)
                                                .frame(width: 40, alignment: .leading)
                                            
                                            Text("47984-47990, 48000-48010")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                        }
                                        
                                        HStack(spacing: 12) {
                                            Text("UDP")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.orange)
                                                .frame(width: 40, alignment: .leading)
                                            
                                            Text("47998-48010")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                    .padding(.leading, 28)
                                    
                                    Text("Forward these ports to your gaming PC's local IP address in your router settings.")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                        .italic()
                                        .padding(.leading, 28)
                                }
                                
                                // Security Note
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.cyan)
                                        Text("Note on Port Forwarding")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Opening ports allows external connections but makes your PC visible online. Only share your connection with people you trust. If you want a more secure alternative to opening ports, look at options for private VPN like Tailscale or ZeroTier.")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.leading, 28)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                CoopStep(text: "Start a FaceTime call with your friend")
                                CoopStep(text: "In Neo Moonight settings, set Controller Mode to 'Single/Co-op'")
                                CoopStep(text: "Click the Co-op button on the main menu")
                                CoopStep(text: "Click 'Host Co-op Session'")
                                CoopStep(text: "Select your gaming PC/App to stream")
                                CoopStep(text: "Toggle between 'Local' or 'Online' mode (see Connection Mode above)")
                                CoopStep(text: "Click 'Start Co-op Session' - the session will launch for you and a SharePlay audio cue will play")
                                CoopStep(text: "Wait for your friend to join. If they're a new guest, you'll need to authorize the PIN that will appear for them. They will need to share the PIN with you to add them in Apollo. Important: Enable controller permissions for the guest client in Sunshine/Apollo settings, otherwise their gamepad won't work")
                                CoopStep(text: "If using Curved Display mode, select Controller Mode to activate your gamepad")
                            }
                            .padding()
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(12)
                        }
                        
                        // Guest Instructions
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(.pink)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Guest Setup")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Join your friend's gaming session and play together.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding()
                            .background(Color.pink.opacity(0.15))
                            .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                CoopStep(text: "Join the FaceTime call with the host")
                                CoopStep(text: "In Settings, set Controller Mode to 'Single/Co-op'")
                                CoopStep(text: "Wait for the host to launch their session - you'll hear a SharePlay audio cue")
                                CoopStep(text: "A SharePlay window will appear - click 'Open' to reveal the session")
                                CoopStep(text: "In Neo Moonlight, click the Co-op button on the main menu")
                                CoopStep(text: "Click 'Join Co-op Session' and select the available session")
                                CoopStep(text: "Click 'Join Session' - if you've connected before, the stream launches automatically")
                                CoopStep(text: "For first-time connections, you'll see a PIN - share it with the host")
                                CoopStep(text: "The host must enter your PIN in Sunshine/Apollo to authorize you")
                                CoopStep(text: "Once authorized, your stream will launch")
                                CoopStep(text: "If using Curved Display mode, select Controller Mode to activate your gamepad")
                            }
                            .padding()
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(12)
                        }
                        
                        // Important Notes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Important Co-op Notes:")
                                .font(.headline)
                                .foregroundColor(brandBlue)
                                .padding(.top, 8)
                            
                            QuickTip(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .yellow,
                                tip: "Experimental Feature",
                                detail: "Co-op mode is highly experimental. You may encounter bugs, connection issues, or unexpected behavior."
                            )
                            
                            QuickTip(
                                icon: "person.2.fill",
                                iconColor: .blue,
                                tip: "Maximum Players",
                                detail: "Co-op sessions support a maximum of 2 players (1 host + 1 guest)."
                            )
                            
                            QuickTip(
                                icon: "video.fill",
                                iconColor: .orange,
                                tip: "FaceTime Required",
                                detail: "Both players must be in an active FaceTime call for co-op to work. "
                            )
                            
                            QuickTip(
                                icon: "gamecontroller.fill",
                                iconColor: .purple,
                                tip: "Controller Setup",
                                detail: "IMPORTANT: Connect your controller via Bluetooth BEFORE joining the co-op session to ensure correct player assignment (Player 1 for host, Player 2 for guest). Set Controller Mode to 'Single/Co-op' in Settings before starting. Once streaming in Curved Display mode, use the input mode toggle to select Controller Mode. Ensure keyboard is disabled to avoid conflicts."
                            )
                            
                            QuickTip(
                                icon: "wifi",
                                iconColor: .green,
                                tip: "Network Performance",
                                detail: "For best results, both players should be on the same local network. Remote play over the internet is supported but may have higher latency. If experiencing connection issues or poor quality, try reducing the resolution (1080p or 1440p recommended for remote play) and lowering the bitrate."
                            )
                            
                            QuickTip(
                                icon: "slider.horizontal.3",
                                iconColor: brandBlue,
                                tip: "Frame Rate",
                                detail: "Co-op sessions run at 90 FPS for compatibility with all Vision Pro models (M2 and M5). Solo streaming supports up to 120 FPS on M5 units."
                            )
                            
                            QuickTip(
                                icon: "envelope.badge.fill",
                                iconColor: .orange,
                                tip: "Invite Button",
                                detail: "If your guest disconnects during the session, use the Invite button in the top control bar to re-invite them. The guest will receive a new SharePlay notification and can rejoin the same session without the host needing to restart."
                            )
                            
                            QuickTip(
                                icon: "key.fill",
                                iconColor: .cyan,
                                tip: "PIN Authorization",
                                detail: "First-time guests need PIN authorization. The guest receives a PIN that must be entered by the host in Sunshine/Apollo. Important: The host must also enable all permissions in Apollo for the guest client, otherwise their gamepad won't work."
                            )
                            
                            QuickTip(
                                icon: "clock.fill",
                                iconColor: .yellow,
                                tip: "Connection Time",
                                detail: "The initial connection between host and guest can sometimes take a moment to establish, please be patient."
                            )
                            
                            QuickTip(
                                icon: "shield.fill",
                                iconColor: .red,
                                tip: "Firewall Settings",
                                detail: "If the guest cannot connect in Online mode, ensure your PC's firewall (Windows Defender, antivirus software, etc.) allows Sunshine/Apollo through. Firewall blocking is a common connection issue."
                            )
                            
                            QuickTip(
                                icon: "person.crop.circle",
                                iconColor: .purple,
                                tip: "FaceTime Personas",
                                detail: "In Curved Display mode (immersive space) you won't see your friend's FaceTime persona . Only Flat Display mode shows personas during co-op sessions."
                            )
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
                
                // In-Stream Controls & Features Guide
                GuideSection(
                    title: "In-Stream Controls & Features",
                    icon: "gamecontroller",
                    iconColor: brandBlue
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Once you're actively streaming, both Flat and Curved Display modes offer powerful controls and features:")
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
                                    Text("Flat Display Features")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Traditional windowed gaming with full system integration and external app visibility.")
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
                                InStreamFeature(
                                    icon: "hand.point.up.left.fill",
                                    title: "Touch Control",
                                    description: "Trackpad-style hand dragging or physical mouse/trackpad support",
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
                                    title: "Screen Adjustment",
                                    description: "Enable Screen Adjust Mode using the input mode toggle. Once enabled, pinch and drag to reposition the screen, or pinch with both fingers to change the scale.",
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
                                    title: "Advanced Lighting",
                                    description: "Choose from various gradient presets, two reactive modes that dynamically respond to screen content, or the immersive Starfield effect.",
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
                                detail: "In Curved Display mode, other apps and system windows will not be visible. Switch to Flat Display if you need to multitask. "
                            )
                            
                            QuickTip(
                                icon: "mountain.2.fill",
                                iconColor: .green,
                                tip: "Apple Environments",
                                detail: "Choose an Apple environment first, launch Curved Display mode, then rotate the digital crown to reveal the environment."
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
                            detail: "Manually set your router channel to 149 (or 44). This eliminates rhythmic stuttering caused by Apple's AWDL protocol (AirDrop/Handoff)."
                        )
                        
                        PerformanceTip(
                            icon: "gamecontroller",
                            iconColor: brandBlue,
                            tip: "Controller Connection",
                            detail: "Connect your controller via Bluetooth directly to your PC for the lowest latency input."
                        )
                        
                        PerformanceTip(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .red,
                            tip: "Controller Not Working in Curved Display?",
                            detail: "Enable Controller Mode in the control bar and ensure the keyboard is disabled."
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

struct CoopStep: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.7))
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

#Preview {
    UserGuideView()
}
