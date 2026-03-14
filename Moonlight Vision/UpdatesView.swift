//
//  UpdatesView.swift
//  Moonlight
//
//  
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct UpdatesView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("About Neo Moonlight")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Changelog Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Changelog")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                    
                    // Version 12.0
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Neo Moonlight Version 12.0 - PLATO EDITION (February 2026)")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        ChangelogItem(text: "Experimental: Couch Co-op via SharePlay - Play couch co-op games with your friend. This is an extremely experimental feature, so please bear with any bugs or issues you may encounter. IMPORTANT: read co-op instructions in the user guide first")
                        ChangelogItem(text: "Added Gaze / Touch control to curved display mode, this was uber challenging to make work across all curvatures, resolutions, sizes, etc.")
                        ChangelogItem(text: "Added Gaze Control cursor adjustment in settings. If the gaze control cursor is slightly off for you, use this to make minor adjustments")
                        ChangelogItem(text: "Added Gaze / Touch Control to Flat Display Mode.")
                        ChangelogItem(text: "Added Classic Display Mode for improved compatibility with keyboard and mouse input")
                        ChangelogItem(text: "Added keyboard support to Flat Display mode")
                        ChangelogItem(text: "Added 'Reactive V1, V2 and Starfield' lighting presets that dynamically adjust based on screen content")
                        ChangelogItem(text: "Added 5 new 360° environments")
                        ChangelogItem(text: "Added star distance toggle that appears when Starfield is enabled with 3 presets (Close, Medium, Far) to customize star proximity")
                        ChangelogItem(text: "Curvature and tilt angle settings now persist")
                        ChangelogItem(text: "Added option in settings to add command button to open Windows Task Manager")
                        ChangelogItem(text: "Added 3D SBS mode to Flat Display mode")
                        ChangelogItem(text: "Added long press to control mode button to lock screen input. Useful for eating or resting hands without cursor interference. Long press again to unlock")
                        ChangelogItem(text: "Added sound stage adjustment via long press on audio button. Cycle through Small, Medium, and Large sound stages when spatial audio is enabled")
                        ChangelogItem(text: "Added co-op mode button and reorganized main menu layout for improved accessibility and workflow")
                        ChangelogItem(text: "Added Gaze Control / Screen Adjust / Controller Mode toggle for curved display to easily switch between gaze/touch control, screen adjustment, and controller input. This was added to avoid conflict with screen interaction and the new gaze control. Controller mode must be enabled for gamepads connected directly to the Vision Pro Bluetooth to function")
                        ChangelogItem(text: "Added option to choose default control mode in settings")
                        ChangelogItem(text: "Added option to choose preferred cursor control method in settings (Gaze/Touch)")
                        ChangelogItem(text: "Changed Renderer name to Display Mode in settings")
                        ChangelogItem(text: "Added co-op mode external IP address help guide")
                        ChangelogItem(text: "Fixed PS5 controller rumble")
                        ChangelogItem(text: "Added custom resolution selection in dropdown")
                        ChangelogItem(text: "Added more screen resolutions and categorized them by aspect ratio")
                        ChangelogItem(text: "Added keyboard support to curved display mode. This requires the user to click an input bar below the screen to appear. Curved display keyboard solution had to be different due to the limitation of immersive mode and the lack of visibility of external elements")
                        ChangelogItem(text: "Updated user guide with co-op connection info")
                        ChangelogItem(text: "Minor UI panel fixes and adjustments")
                        ChangelogItem(text: "Fixed cursor jitter in curved display mode")
                        ChangelogItem(text: "Fixed memory leak and various bugs")
                        ChangelogItem(text: "Fixed keyboard focus stealing from other visionOS apps in flat display mode")
                        ChangelogItem(text: "Added optional battery meter for primary connected controller. Shows battery level and charging status in the top control bar")
                        ChangelogItem(text: "Added adjustable brightness for select lighting presets (marked with lightbulb icon). Long press to cycle brightness from dark to light")
                        ChangelogItem(text: "Added toggle in settings to remove rounded corners from stream display")
                        ChangelogItem(text: "Added Dark Mode in settings - dims control overlays for a more immersive viewing experience (Flat and Curved modes only)")
                        ChangelogItem(text: "Added Dynamic Controls Menu — optional collapsible top bar (toggle in Settings). Single center launcher expands to the full icon row")
                        ChangelogItem(text: "Performance optimizations across streaming and rendering for a smoother experience with improved FPS stability")
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
                                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.92))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
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
                
                // Support the Developer Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Support Me on Ko-fi")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image("kofi")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enjoying the app?")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text("Neo Moonlight is simply my vision of Moonlight on the Vision Pro. If this app has improved your experience and you'd like to leave a tip, it would be greatly appreciated.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Link(destination: URL(string: "https://ko-fi.com/neovectorx")!) {
                                HStack(spacing: 10) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 16))
                                    Text("Support on Ko-fi")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.7, green: 0.3, blue: 0.9),
                                                    Color(red: 0.85, green: 0.6, blue: 0.95)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: Color(red: 0.7, green: 0.3, blue: 0.9).opacity(0.4), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(24)
                    .background(
                        ZStack {
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
                
                // Contributors Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Contributors & Credits")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Based on:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Link("Original Moonlight Project", destination: URL(string: "https://moonlight-stream.org/")!)
                                .font(.body)
                            Link("Moonlight iOS GitHub", destination: URL(string: "https://github.com/moonlight-stream/moonlight-ios")!)
                                .font(.body)
                            Link("Moonlight visionOS Port", destination: URL(string: "https://github.com/RikuKunMS2/moonlight-ios-vision/tree/vision-testflight")!)
                                .font(.body)
                            
                            Text("This is a modified fork of the original XrOS port by RikuKunMS2.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 4)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Original Moonlight Team")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• cgutman - Lead developer of Moonlight iOS")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• dwaxemberg, ascagnel, and many others")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VisionOS Port & Enhancements")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• RikuKunMS2 - Initial visionOS port and foundation work")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• tht7 - Curved screen feature implementation")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• shinyquagsire23 - Performance optimizations")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• JFuellem - Controller crash fixes")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• linggan-ua - Black screen recovery fixes")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• Max T (ALVR Project) - AV1 Parser")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Neo Moonlight")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• NeoVectorX")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Special Thanks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• Samantha - Thank you for the countless hours of testing and dealing with me devoting nearly all of my time coding this app the past few months. 💜")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Testers")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• skynet01 - Beta testing, suggestions, and feedback")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• Delt31 - Beta testing, suggestions, and feedback")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Text("And many others who contributed through issues, testing, and feedback.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .italic()
                        
                        Link("View all contributors on GitHub", destination: URL(string: "https://github.com/moonlight-stream/moonlight-ios/graphs/contributors")!)
                            .font(.body)
                            .padding(.top, 4)
                    }
                    .padding(24)
                    .background(
                        ZStack {
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
                
                // License Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("License")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GPL-3.0 License")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("This project is licensed under GPL-3.0, the same license as the original Moonlight project. This means the source code is freely available and can be modified and redistributed under the same terms.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Link("View License", destination: URL(string: "https://github.com/NeoVectorX/NeoMoonlight/blob/vision-testflight/LICENSE.txt")!)
                            .font(.body)
                            .padding(.top, 4)
                    }
                    .padding(24)
                    .background(
                        ZStack {
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
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Helper Components
struct ChangelogItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.white.opacity(0.7))
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

struct TechnicalDetail: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(description)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

#Preview {
    UpdatesView()
}
