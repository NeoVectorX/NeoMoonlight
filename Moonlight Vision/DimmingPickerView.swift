//
//  DimmingPickerView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//

import SwiftUI

struct DimmingPickerView: View {
    @Binding var dimLevel: Int
    @Binding var isPresented: Bool
    @Binding var environmentSphereLevel: Int
    @Binding var newsetLevel: Int
    
    // Dimming preset items
    private struct DimItem: Identifiable {
        let id: String
        let displayName: String
        let dimLevel: Int
    }
    
    private var allItems: [DimItem] {
        [
            DimItem(id: "0", displayName: "Off", dimLevel: 0),
            DimItem(id: "1", displayName: "Night", dimLevel: 1),
            DimItem(id: "2", displayName: "Reactive V1", dimLevel: 2),
            DimItem(id: "10", displayName: "Reactive V2", dimLevel: 10),
            DimItem(id: "12", displayName: "Starfield", dimLevel: 12),
            DimItem(id: "4", displayName: "Eclipse", dimLevel: 4),
            DimItem(id: "5", displayName: "Midnight", dimLevel: 5),
            DimItem(id: "6", displayName: "Twilight", dimLevel: 6),
            DimItem(id: "7", displayName: "Dawn", dimLevel: 7),
            DimItem(id: "8", displayName: "Sunrise", dimLevel: 8),
            DimItem(id: "9", displayName: "Woodland", dimLevel: 9),
            DimItem(id: "14", displayName: "Desert", dimLevel: 14)
        ]
    }
    
    // Theme Colors
    private let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Select Lighting Preset")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            // Grid (6 columns × 2 rows)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 20) {
                ForEach(allItems) { item in
                    Button {
                        selectItem(item)
                    } label: {
                        VStack(spacing: 8) {
                            DimmingThumbnailView(displayName: item.displayName, dimLevel: item.dimLevel, isPickerOpen: isPresented)
                                .frame(height: 80)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isSelected(item) ? brandOrange : Color.white.opacity(0.2), lineWidth: isSelected(item) ? 3 : 1)
                                )
                            
                            Text(item.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isSelected(item) ? brandOrange : .white)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 220)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(brandNavy.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .frame(width: 700)
    }
    
    private func isSelected(_ item: DimItem) -> Bool {
        return dimLevel == item.dimLevel
    }
    
    private func selectItem(_ item: DimItem) {
        dimLevel = item.dimLevel
        
        // Reset environment when selecting a dimming preset (they're mutually exclusive)
        if item.dimLevel != 0 {
            environmentSphereLevel = 0
            newsetLevel = 0
        }
        
        // Keep picker open to allow cycling through presets
    }
}

private struct DimmingThumbnailView: View {
    let displayName: String
    let dimLevel: Int
    let isPickerOpen: Bool
    @State private var animationPhase: Double = 0
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if dimLevel == 12, let _ = UIImage(named: "starfield") {
                // Use custom image for Starfield preset
                Image("starfield")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                // Use gradient for all other presets
                Circle()
                    .fill(gradientForPreset())
                    .frame(width: 80, height: 80)
                    .opacity(dimLevel == 2 ? 0.8 : 1.0)
                    .overlay(
                        Group {
                            if dimLevel == 0 {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    )
            }
        }
            .onChange(of: isPickerOpen) { _, isOpen in
                // Cancel existing animation when picker closes
                if !isOpen {
                    animationTask?.cancel()
                    animationTask = nil
                    animationPhase = 0
                } else if dimLevel == 2 || dimLevel == 10 || dimLevel == 12 {
                    // Start animation when picker opens (Reactive V1, V2, and Starfield)
                    startAnimation()
                }
            }
            .onAppear {
                if isPickerOpen && (dimLevel == 2 || dimLevel == 10 || dimLevel == 12) {
                    startAnimation()
                }
            }
            .onDisappear {
                animationTask?.cancel()
                animationTask = nil
            }
    }
    
    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms updates (much slower, less CPU)
                if !Task.isCancelled {
                    animationPhase += 0.015 // Slightly larger steps to compensate
                    if animationPhase >= 1.0 {
                        animationPhase = 0
                    }
                }
            }
        }
    }
    
    private func gradientForPreset() -> LinearGradient {
        switch dimLevel {
        case 0: // Off
            return LinearGradient(
                colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 1: // Night
            return LinearGradient(
                colors: [Color.black, Color(white: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2: // Reactive - Animated color cycling
            // Cycle through distinct colors based on animation phase
            let progress = animationPhase
            let color1: Color
            let color2: Color
            let color3: Color
            
            // Smooth color transitions through spectrum
            if progress < 0.2 {
                // Purple to Blue
                let t = progress / 0.2
                color1 = Color(red: 0.5 - 0.2 * t, green: 0.0 + 0.3 * t, blue: 0.8 + 0.2 * t)
                color2 = Color(red: 0.3 - 0.1 * t, green: 0.0 + 0.5 * t, blue: 0.9 + 0.1 * t)
                color3 = Color(red: 0.6 - 0.3 * t, green: 0.1 + 0.4 * t, blue: 0.7 + 0.2 * t)
            } else if progress < 0.4 {
                // Blue to Cyan
                let t = (progress - 0.2) / 0.2
                color1 = Color(red: 0.3 - 0.3 * t, green: 0.3 + 0.4 * t, blue: 1.0)
                color2 = Color(red: 0.2 - 0.2 * t, green: 0.5 + 0.3 * t, blue: 1.0)
                color3 = Color(red: 0.3 - 0.3 * t, green: 0.5 + 0.3 * t, blue: 0.9 + 0.1 * t)
            } else if progress < 0.6 {
                // Cyan to Green
                let t = (progress - 0.4) / 0.2
                color1 = Color(red: 0.0, green: 0.7 + 0.2 * t, blue: 1.0 - 0.3 * t)
                color2 = Color(red: 0.0, green: 0.8 + 0.1 * t, blue: 0.8 - 0.4 * t)
                color3 = Color(red: 0.0 + 0.2 * t, green: 0.8 + 0.1 * t, blue: 1.0 - 0.5 * t)
            } else if progress < 0.8 {
                // Green to Yellow/Orange
                let t = (progress - 0.6) / 0.2
                color1 = Color(red: 0.0 + 0.9 * t, green: 0.9, blue: 0.7 - 0.5 * t)
                color2 = Color(red: 0.0 + 1.0 * t, green: 0.9 - 0.2 * t, blue: 0.4 - 0.4 * t)
                color3 = Color(red: 0.2 + 0.6 * t, green: 0.9 - 0.1 * t, blue: 0.5 - 0.3 * t)
            } else {
                // Orange to Purple (completing cycle)
                let t = (progress - 0.8) / 0.2
                color1 = Color(red: 0.9 - 0.4 * t, green: 0.7 - 0.7 * t, blue: 0.2 + 0.6 * t)
                color2 = Color(red: 1.0 - 0.7 * t, green: 0.7 - 0.7 * t, blue: 0.0 + 0.9 * t)
                color3 = Color(red: 0.8 - 0.2 * t, green: 0.8 - 0.7 * t, blue: 0.2 + 0.5 * t)
            }
            
            return LinearGradient(
                colors: [color1, color2, color3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 4: // Eclipse
            return LinearGradient(
                colors: [
                    Color.black,
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 5: // Midnight
            return LinearGradient(
                colors: [
                    Color(red: 0.4, green: 0.2, blue: 0.6),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 6: // Twilight
            return LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.20, blue: 0.40),
                    Color(red: 0.40, green: 0.25, blue: 0.50),
                    Color(red: 0.20, green: 0.15, blue: 0.30),
                    Color(red: 0.05, green: 0.03, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 7: // Dawn
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.75, blue: 0.55),
                    Color(red: 0.90, green: 0.60, blue: 0.70),
                    Color(red: 0.60, green: 0.45, blue: 0.75),
                    Color(red: 0.30, green: 0.25, blue: 0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 8: // Sunrise
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.85, blue: 0.40),
                    Color(red: 0.98, green: 0.70, blue: 0.50),
                    Color(red: 0.90, green: 0.50, blue: 0.60),
                    Color(red: 0.70, green: 0.40, blue: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 9: // Woodland
            return LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.45, blue: 0.22),
                    Color(red: 0.18, green: 0.32, blue: 0.15),
                    Color(red: 0.08, green: 0.18, blue: 0.06),
                    Color(red: 0.04, green: 0.10, blue: 0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 11: // Desert - Original tan to brown gradient
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.80, blue: 0.50),
                    Color(red: 0.90, green: 0.65, blue: 0.45),
                    Color(red: 0.75, green: 0.50, blue: 0.40),
                    Color(red: 0.50, green: 0.35, blue: 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 14: // Desert - Original tan to brown gradient
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.80, blue: 0.50),
                    Color(red: 0.90, green: 0.65, blue: 0.45),
                    Color(red: 0.75, green: 0.50, blue: 0.40),
                    Color(red: 0.50, green: 0.35, blue: 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 10: // Reactive V2 - Offset color cycle (starts at Cyan instead of Purple)
            // Cycle through distinct colors based on animation phase
            // Offset by 0.4 (40%) to start at Cyan instead of Purple
            let progress = fmod(animationPhase + 0.4, 1.0)
            let color1: Color
            let color2: Color
            let color3: Color
            
            // Smooth color transitions through spectrum (offset from V1)
            if progress < 0.2 {
                // Purple to Blue
                let t = progress / 0.2
                color1 = Color(red: 0.5 - 0.2 * t, green: 0.0 + 0.3 * t, blue: 0.8 + 0.2 * t)
                color2 = Color(red: 0.3 - 0.1 * t, green: 0.0 + 0.5 * t, blue: 0.9 + 0.1 * t)
                color3 = Color(red: 0.6 - 0.3 * t, green: 0.1 + 0.4 * t, blue: 0.7 + 0.2 * t)
            } else if progress < 0.4 {
                // Blue to Cyan
                let t = (progress - 0.2) / 0.2
                color1 = Color(red: 0.3 - 0.3 * t, green: 0.3 + 0.4 * t, blue: 1.0)
                color2 = Color(red: 0.2 - 0.2 * t, green: 0.5 + 0.3 * t, blue: 1.0)
                color3 = Color(red: 0.3 - 0.3 * t, green: 0.5 + 0.3 * t, blue: 0.9 + 0.1 * t)
            } else if progress < 0.6 {
                // Cyan to Green
                let t = (progress - 0.4) / 0.2
                color1 = Color(red: 0.0, green: 0.7 + 0.2 * t, blue: 1.0 - 0.3 * t)
                color2 = Color(red: 0.0, green: 0.8 + 0.1 * t, blue: 0.8 - 0.4 * t)
                color3 = Color(red: 0.0 + 0.2 * t, green: 0.8 + 0.1 * t, blue: 1.0 - 0.5 * t)
            } else if progress < 0.8 {
                // Green to Yellow/Orange
                let t = (progress - 0.6) / 0.2
                color1 = Color(red: 0.0 + 0.9 * t, green: 0.9, blue: 0.7 - 0.5 * t)
                color2 = Color(red: 0.0 + 1.0 * t, green: 0.9 - 0.2 * t, blue: 0.4 - 0.4 * t)
                color3 = Color(red: 0.2 + 0.6 * t, green: 0.9 - 0.1 * t, blue: 0.5 - 0.3 * t)
            } else {
                // Orange to Purple (completing cycle)
                let t = (progress - 0.8) / 0.2
                color1 = Color(red: 0.9 - 0.4 * t, green: 0.7 - 0.7 * t, blue: 0.2 + 0.6 * t)
                color2 = Color(red: 1.0 - 0.7 * t, green: 0.7 - 0.7 * t, blue: 0.0 + 0.9 * t)
                color3 = Color(red: 0.8 - 0.2 * t, green: 0.8 - 0.7 * t, blue: 0.2 + 0.5 * t)
            }
            
            return LinearGradient(
                colors: [color1, color2, color3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 12: // Starfield - Deep black space with subtle deep blue tint
            return LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.08),  // Very dark blue-black
                    Color(red: 0.0, green: 0.0, blue: 0.05),     // Deep space black
                    Color(red: 0.0, green: 0.0, blue: 0.0)       // Pure black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            let progress = animationPhase
            let color1: Color
            let color2: Color
            let color3: Color
            
            // Smooth color transitions through spectrum (offset from V1/V2)
            if progress < 0.2 {
                // Purple to Blue
                let t = progress / 0.2
                color1 = Color(red: 0.5 - 0.2 * t, green: 0.0 + 0.3 * t, blue: 0.8 + 0.2 * t)
                color2 = Color(red: 0.3 - 0.1 * t, green: 0.0 + 0.5 * t, blue: 0.9 + 0.1 * t)
                color3 = Color(red: 0.6 - 0.3 * t, green: 0.1 + 0.4 * t, blue: 0.7 + 0.2 * t)
            } else if progress < 0.4 {
                // Blue to Cyan
                let t = (progress - 0.2) / 0.2
                color1 = Color(red: 0.3 - 0.3 * t, green: 0.3 + 0.4 * t, blue: 1.0)
                color2 = Color(red: 0.2 - 0.2 * t, green: 0.5 + 0.3 * t, blue: 1.0)
                color3 = Color(red: 0.3 - 0.3 * t, green: 0.5 + 0.3 * t, blue: 0.9 + 0.1 * t)
            } else if progress < 0.6 {
                // Cyan to Green
                let t = (progress - 0.4) / 0.2
                color1 = Color(red: 0.0, green: 0.7 + 0.2 * t, blue: 1.0 - 0.3 * t)
                color2 = Color(red: 0.0, green: 0.8 + 0.1 * t, blue: 0.8 - 0.4 * t)
                color3 = Color(red: 0.0 + 0.2 * t, green: 0.8 + 0.1 * t, blue: 1.0 - 0.5 * t)
            } else if progress < 0.8 {
                // Green to Yellow/Orange
                let t = (progress - 0.6) / 0.2
                color1 = Color(red: 0.0 + 0.9 * t, green: 0.9, blue: 0.7 - 0.5 * t)
                color2 = Color(red: 0.0 + 1.0 * t, green: 0.9 - 0.2 * t, blue: 0.4 - 0.4 * t)
                color3 = Color(red: 0.2 + 0.6 * t, green: 0.9 - 0.1 * t, blue: 0.5 - 0.3 * t)
            } else {
                // Orange to Purple (completing cycle)
                let t = (progress - 0.8) / 0.2
                color1 = Color(red: 0.9 - 0.4 * t, green: 0.7 - 0.7 * t, blue: 0.2 + 0.6 * t)
                color2 = Color(red: 1.0 - 0.7 * t, green: 0.7 - 0.7 * t, blue: 0.0 + 0.9 * t)
                color3 = Color(red: 0.8 - 0.2 * t, green: 0.8 - 0.7 * t, blue: 0.2 + 0.5 * t)
            }
            
            return LinearGradient(
                colors: [color1, color2, color3],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
