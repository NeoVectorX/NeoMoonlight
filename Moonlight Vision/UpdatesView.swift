//
//  UpdatesView.swift
//  Moonlight
//
//  Created by camy on 2/2/25.
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
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Neo Moonlight Version 11.1 December 2025")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        ChangelogItem(text: "Complete UI/UX overhaul")
                        ChangelogItem(text: "Added a Moonlight user guide")
                        ChangelogItem(text: "Added multiple dimming options")
                        ChangelogItem(text: "Added 360° environments")
                        ChangelogItem(text: "Added curvature presets to match popular gaming monitor industry standards")
                        ChangelogItem(text: "Icons automatically hide for better immersion")
                        ChangelogItem(text: "Added statistics overlay to Immersive mode")
                        ChangelogItem(text: "Added preset color grading options")
                        ChangelogItem(text: "Added a tilt feature to Curved Display mode")
                        ChangelogItem(text: "Increased options for framerate and bitrate")
                        ChangelogItem(text: "Added a disconnect button in the main menu while streaming")
                        ChangelogItem(text: "Updated Renderers to a more user-friendly naming structure")
                        ChangelogItem(text: "Implemented Apple's new low-latency streaming entitlement for enhanced streaming performance")
                        ChangelogItem(text: "Added new toggle for switching between spatial audio and stereo modes for optimized gaming audio")
                        ChangelogItem(text: "Added AV1 Codec support for M5 Owners")
                        ChangelogItem(text: "Rounded UI corners slightly to better match visionOS aesthetic design")
                        ChangelogItem(text: "Set aspect ratio to automatically configure when streaming")
                        ChangelogItem(text: "Added toggle to hide system cursor to remove duplicate mouse cursors")
                    }
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
                            
                            Text("This is a modified fork with enhanced visionOS gaming features and UI changes.")
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
                            Text("Testers")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("• skynet01 - Beta testing and feedback")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("• Delt31 - Beta testing and feedback")
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
                
                // Support the Developer Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Support the Developer")
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
                                    Text("Support Neo Moonlight")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text("I'm a one-person team trying to enhance the Moonlight gaming experience as much as possible. If you enjoy the app and would like to support me, any contribution is greatly appreciated!")
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
