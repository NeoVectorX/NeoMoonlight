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
    @Binding var presetBrightness: [Int: Double]
    let defaultPresetBrightness: [Int: Double]
    /// When set, long-pressing the Starfield preset calls this when hold starts (e.g. start cycling star distance). Curved display only.
    var onStarfieldLongPress: (() -> Void)? = nil
    /// When set, called when the user releases after a Starfield long-press (e.g. stop cycling).
    var onStarfieldLongPressEnd: (() -> Void)? = nil
    
    // Dimming preset items
    struct DimItem: Identifiable {
        let id: String
        let displayName: String
        let dimLevel: Int
        let supportsAdjustment: Bool
    }
    
    // Presets that support brightness adjustment via long-press
    private let adjustablePresets: Set<Int> = [1, 5, 6, 7, 8, 9, 14]
    
    private var allItems: [DimItem] {
        [
            DimItem(id: "0", displayName: "Off", dimLevel: 0, supportsAdjustment: false),
            DimItem(id: "1", displayName: "Night", dimLevel: 1, supportsAdjustment: true),
            DimItem(id: "2", displayName: "Reactive V1", dimLevel: 2, supportsAdjustment: false),
            DimItem(id: "10", displayName: "Reactive V2", dimLevel: 10, supportsAdjustment: false),
            DimItem(id: "12", displayName: "Starfield", dimLevel: 12, supportsAdjustment: false),
            DimItem(id: "4", displayName: "Eclipse", dimLevel: 4, supportsAdjustment: false),
            DimItem(id: "5", displayName: "Midnight", dimLevel: 5, supportsAdjustment: true),
            DimItem(id: "6", displayName: "Twilight", dimLevel: 6, supportsAdjustment: true),
            DimItem(id: "7", displayName: "Dawn", dimLevel: 7, supportsAdjustment: true),
            DimItem(id: "8", displayName: "Sunrise", dimLevel: 8, supportsAdjustment: true),
            DimItem(id: "9", displayName: "Woodland", dimLevel: 9, supportsAdjustment: true),
            DimItem(id: "14", displayName: "Desert", dimLevel: 14, supportsAdjustment: true)
        ]
    }
    
    // Theme Colors
    private let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    // State for tracking which preset is currently being adjusted
    @State private var cyclingPresetLevel: Int? = nil
    
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
                    if item.supportsAdjustment {
                        // Adjustable preset with long-press for brightness cycling
                        AdjustableDimItemView(
                            item: item,
                            dimLevel: $dimLevel,
                            presetBrightness: $presetBrightness,
                            cyclingPresetLevel: $cyclingPresetLevel,
                            defaultPresetBrightness: defaultPresetBrightness,
                            isSelected: isSelected(item),
                            brandOrange: brandOrange,
                            isPickerOpen: isPresented,
                            onSelect: { selectItem(item) }
                        )
                    } else if item.dimLevel == 12, onStarfieldLongPress != nil {
                        // Starfield preset: tap selects, long-press cycles star distance (curved display)
                        Button {
                            selectItem(item)
                        } label: {
                            VStack(spacing: 8) {
                                DimmingThumbnailView(
                                    displayName: item.displayName,
                                    dimLevel: item.dimLevel,
                                    isPickerOpen: isPresented,
                                    brightness: nil,
                                    isCycling: false
                                )
                                .frame(height: 80)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isSelected(item) ? brandOrange : Color.white.opacity(0.2), lineWidth: isSelected(item) ? 3 : 1)
                                )
                                
                                HStack(spacing: 3) {
                                    Text(item.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(isSelected(item) ? brandOrange : .white)
                                        .lineLimit(1)
                                    Image(systemName: "lightbulb.circle")
                                        .font(.system(size: 9))
                                        .foregroundColor(isSelected(item) ? brandOrange.opacity(0.7) : .white.opacity(0.5))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoldablePlainButtonStyle(
                            onHold: {
                                selectItem(item)
                                onStarfieldLongPress?()
                            },
                            onRelease: {
                                onStarfieldLongPressEnd?()
                            },
                            minimumHoldDuration: 0.2
                        ))
                    } else {
                        // Non-adjustable preset (tap only)
                        Button {
                            selectItem(item)
                        } label: {
                            VStack(spacing: 8) {
                                DimmingThumbnailView(
                                    displayName: item.displayName,
                                    dimLevel: item.dimLevel,
                                    isPickerOpen: isPresented,
                                    brightness: nil,
                                    isCycling: false
                                )
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
            }
            .frame(minHeight: 220)
            
            // Hint for adjustable presets
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                Text("Dimmable Preset: Long press (pinch hold) on preset to adjust dimming.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
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
    }
}

// MARK: - Adjustable Dim Item View (supports long-press brightness cycling)

private struct AdjustableDimItemView: View {
    let item: DimmingPickerView.DimItem
    @Binding var dimLevel: Int
    @Binding var presetBrightness: [Int: Double]
    @Binding var cyclingPresetLevel: Int?
    let defaultPresetBrightness: [Int: Double]
    let isSelected: Bool
    let brandOrange: Color
    let isPickerOpen: Bool
    let onSelect: () -> Void
    
    @State private var cycleTask: Task<Void, Never>? = nil
    @State private var cycleStartTime: Date? = nil
    
    private var currentBrightness: Double {
        presetBrightness[item.dimLevel] ?? defaultPresetBrightness[item.dimLevel] ?? 0.85
    }
    
    private var isCycling: Bool {
        cyclingPresetLevel == item.dimLevel
    }
    
    var body: some View {
        Button {
            if !isCycling {
                onSelect()
            }
        } label: {
            VStack(spacing: 8) {
                DimmingThumbnailView(
                    displayName: item.displayName,
                    dimLevel: item.dimLevel,
                    isPickerOpen: isPickerOpen,
                    brightness: currentBrightness,
                    isCycling: isCycling
                )
                .frame(height: 80)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? brandOrange : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                )
                // Glow effect during cycling
                .shadow(color: .white.opacity(isCycling ? currentBrightness * 0.8 : 0.0), radius: isCycling ? 12 : 0)
                .shadow(color: .white.opacity(isCycling ? currentBrightness * 0.4 : 0.0), radius: isCycling ? 24 : 0)
                .animation(.easeInOut(duration: 0.15), value: currentBrightness)
                .animation(.easeOut(duration: 0.4), value: isCycling)
                
                HStack(spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? brandOrange : .white)
                        .lineLimit(1)
                    
                    Image(systemName: "lightbulb.circle")
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? brandOrange.opacity(0.7) : .white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HoldablePlainButtonStyle(
            onHold: { startBrightnessCycle() },
            onRelease: {
                if isCycling {
                    stopBrightnessCycle()
                }
            }
        ))
        .onDisappear {
            cycleTask?.cancel()
            cycleTask = nil
        }
    }
    
    private func startBrightnessCycle() {
        // First, select this preset
        onSelect()
        
        cyclingPresetLevel = item.dimLevel
        cycleStartTime = Date()
        
        cycleTask?.cancel()
        cycleTask = Task {
            let cycleDuration: Double = 5.0 // seconds for full dark→light→dark
            
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(cycleStartTime ?? Date())
                // Sine wave: 0.5 + 0.5 * sin(...) gives range 0.0 to 1.0
                let brightness = 0.5 + 0.5 * sin(elapsed * 2.0 * .pi / cycleDuration)
                
                await MainActor.run {
                    presetBrightness[item.dimLevel] = brightness
                    // Save to UserDefaults as we cycle (will save final value on release too)
                    UserDefaults.standard.set(brightness, forKey: "preset.brightness.\(item.dimLevel)")
                }
                
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms updates (20 FPS)
            }
        }
    }
    
    private func stopBrightnessCycle() {
        cycleTask?.cancel()
        cycleTask = nil
        cycleStartTime = nil
        
        // Save the final brightness value
        let finalBrightness = presetBrightness[item.dimLevel] ?? defaultPresetBrightness[item.dimLevel] ?? 0.85
        UserDefaults.standard.set(finalBrightness, forKey: "preset.brightness.\(item.dimLevel)")
        
        withAnimation(.easeOut(duration: 0.4)) {
            cyclingPresetLevel = nil
        }
    }
}

private struct DimmingThumbnailView: View {
    let displayName: String
    let dimLevel: Int
    let isPickerOpen: Bool
    let brightness: Double?  // User-adjustable brightness for applicable presets
    let isCycling: Bool      // Whether brightness is currently being cycled via long-press
    
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
                    // Apply brightness to thumbnail opacity for adjustable presets
                    .opacity(thumbnailOpacity)
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
    
    private var thumbnailOpacity: Double {
        // For adjustable presets during cycling, mirror the brightness value
        if let brightness = brightness {
            // Scale brightness to a visible opacity range (0.3 to 1.0) so it's never invisible
            return 0.3 + (brightness * 0.7)
        }
        // Default opacities for non-adjustable presets
        return dimLevel == 2 ? 0.8 : 1.0
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

// MARK: - Holdable Plain Button Style (tap = native sound + select; hold = start cycle; release = stop cycle)

struct HoldablePlainButtonStyle: ButtonStyle {
    let onHold: () -> Void
    let onRelease: () -> Void
    /// Seconds before onHold fires (default 0.5). Use a shorter value (e.g. 0.2) for quicker response.
    var minimumHoldDuration: Double = 0.5
    
    @State private var holdTask: Task<Void, Never>?
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { oldValue, isPressed in
                if isPressed {
                    holdTask?.cancel()
                    let duration = minimumHoldDuration
                    holdTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                        if !Task.isCancelled {
                            await MainActor.run { onHold() }
                        }
                    }
                } else {
                    holdTask?.cancel()
                    onRelease()
                }
            }
    }
}
