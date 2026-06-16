//
//  DimmingPickerView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//

import SwiftUI

/// Baseline sizing for the lighting preset sheet; multiply with ``pt(_:)`` for uniform layout/fonts.
private enum DimmingPickerMetrics {
    /// 30% smaller than original design (`1 − 0.30`).
    static let scale: CGFloat = 0.7
    static func pt(_ base: CGFloat) -> CGFloat { base * scale }
}

struct DimmingPickerView: View {
    @Binding var dimLevel: Int
    @Binding var isPresented: Bool
    @Binding var environmentSphereLevel: Int
    @Binding var newsetLevel: Int
    @Binding var presetBrightness: [Int: Double]
    let defaultPresetBrightness: [Int: Double]
    /// Starfield: each tap selects preset and advances star distance one step (curved display only).
    var onStarfieldTapCycle: (() -> Void)? = nil
    /// Reactive 1 (Chromosphere): each tap expands glow size / reach (curved display only).
    var onReactive1TapCycle: (() -> Void)? = nil
    // Dimming preset items
    struct DimItem: Identifiable {
        let id: String
        let displayName: String
        let dimLevel: Int
        let supportsAdjustment: Bool
    }
    
    // Presets that support brightness adjustment via long-press
    private let adjustablePresets: Set<Int> = [1, 5, 6, 7, 8, 9, 10, 14]
    
    private var allItems: [DimItem] {
        [
            DimItem(id: "0", displayName: "Off", dimLevel: 0, supportsAdjustment: false),
            DimItem(id: "1", displayName: "Night", dimLevel: 1, supportsAdjustment: true),
            DimItem(id: "2", displayName: "Reactive", dimLevel: 2, supportsAdjustment: false),
            DimItem(id: "12", displayName: "Starfield", dimLevel: 12, supportsAdjustment: false),
            DimItem(id: "4", displayName: "Eclipse", dimLevel: 4, supportsAdjustment: false),
            DimItem(id: "5", displayName: "Midnight", dimLevel: 5, supportsAdjustment: true),
            DimItem(id: "6", displayName: "Twilight", dimLevel: 6, supportsAdjustment: true),
            DimItem(id: "7", displayName: "Dawn", dimLevel: 7, supportsAdjustment: true),
            DimItem(id: "8", displayName: "Sunrise", dimLevel: 8, supportsAdjustment: true),
            DimItem(id: "9", displayName: "Woodland", dimLevel: 9, supportsAdjustment: true),
            DimItem(id: "10", displayName: "Tide", dimLevel: 10, supportsAdjustment: true),
            DimItem(id: "14", displayName: "Desert", dimLevel: 14, supportsAdjustment: true)
        ]
    }
    
    // Theme Colors
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    // State for tracking which preset is currently being adjusted
    @State private var cyclingPresetLevel: Int? = nil
    
    var body: some View {
        VStack(spacing: DimmingPickerMetrics.pt(20)) {
            // Header
            HStack {
                Text("Select Lighting Preset")
                    .font(.system(size: DimmingPickerMetrics.pt(24), weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DimmingPickerMetrics.pt(32)))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .neoMenuItemGazeHighlight(.circle)
            }
            .padding(.horizontal, DimmingPickerMetrics.pt(8))
            
            // Grid (6 columns × 2 rows)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: DimmingPickerMetrics.pt(20)) {
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
                    } else if item.dimLevel == 2, onReactive1TapCycle != nil {
                        // Reactive 1 — each tap selects preset and advances chromosphere reach one tier (curved).
                        lightingPresetGridCell(
                            isSelected: isSelected(item),
                            brandOrange: brandOrange,
                            thumbnail: {
                                DimmingThumbnailView(
                                    displayName: item.displayName,
                                    dimLevel: item.dimLevel,
                                    isPickerOpen: isPresented,
                                    brightness: nil,
                                    isCycling: false
                                )
                            },
                            label: {
                                HStack(spacing: DimmingPickerMetrics.pt(3)) {
                                    Text(item.displayName)
                                        .font(.system(size: DimmingPickerMetrics.pt(14), weight: .medium))
                                        .foregroundColor(isSelected(item) ? brandOrange : .white)
                                        .lineLimit(1)
                                    Image(systemName: "rays")
                                        .font(.system(size: DimmingPickerMetrics.pt(9)))
                                        .foregroundColor(isSelected(item) ? brandOrange.opacity(0.7) : .white.opacity(0.5))
                                }
                            },
                            action: {
                                selectItem(item)
                                onReactive1TapCycle?()
                            }
                        )
                    } else if item.dimLevel == 12, onStarfieldTapCycle != nil {
                        // Starfield — each tap selects preset and advances star distance one step (curved).
                        lightingPresetGridCell(
                            isSelected: isSelected(item),
                            brandOrange: brandOrange,
                            thumbnail: {
                                DimmingThumbnailView(
                                    displayName: item.displayName,
                                    dimLevel: item.dimLevel,
                                    isPickerOpen: isPresented,
                                    brightness: nil,
                                    isCycling: false
                                )
                            },
                            label: {
                                HStack(spacing: DimmingPickerMetrics.pt(3)) {
                                    Text(item.displayName)
                                        .font(.system(size: DimmingPickerMetrics.pt(14), weight: .medium))
                                        .foregroundColor(isSelected(item) ? brandOrange : .white)
                                        .lineLimit(1)
                                    Image(systemName: "lightbulb.circle")
                                        .font(.system(size: DimmingPickerMetrics.pt(9)))
                                        .foregroundColor(isSelected(item) ? brandOrange.opacity(0.7) : .white.opacity(0.5))
                                }
                            },
                            action: {
                                selectItem(item)
                                onStarfieldTapCycle?()
                            }
                        )
                    } else {
                        // Non-adjustable preset (tap only)
                        lightingPresetGridCell(
                            isSelected: isSelected(item),
                            brandOrange: brandOrange,
                            thumbnail: {
                                DimmingThumbnailView(
                                    displayName: item.displayName,
                                    dimLevel: item.dimLevel,
                                    isPickerOpen: isPresented,
                                    brightness: nil,
                                    isCycling: false
                                )
                            },
                            label: {
                                Text(item.displayName)
                                    .font(.system(size: DimmingPickerMetrics.pt(14), weight: .medium))
                                    .foregroundColor(isSelected(item) ? brandOrange : .white)
                                    .lineLimit(1)
                            },
                            action: { selectItem(item) }
                        )
                    }
                }
            }
            .frame(minHeight: DimmingPickerMetrics.pt(220))
            
            // Hint for adjustable presets (top-align icon with first line when text wraps)
            HStack(alignment: .top, spacing: DimmingPickerMetrics.pt(8)) {
                Image(systemName: "lightbulb.circle")
                    .font(.system(size: DimmingPickerMetrics.pt(11)))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, DimmingPickerMetrics.pt(1.5))
                Text("Long press on dimmable presets adjusts brightness. Tap Reactive to expand glow size. Tap Starfield to cycle star distance.")
                    .font(.system(size: DimmingPickerMetrics.pt(11)))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DimmingPickerMetrics.pt(4))
        }
        .padding(DimmingPickerMetrics.pt(32))
        .neoClearBluePanelChrome(
            cornerRadius: DimmingPickerMetrics.pt(24),
            layoutScale: DimmingPickerMetrics.scale
        )
        .frame(width: DimmingPickerMetrics.pt(700))
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

// MARK: - Lighting preset icon chrome

@ViewBuilder
private func lightingPresetCircularIcon<Content: View>(
    isSelected: Bool,
    brandOrange: Color,
    @ViewBuilder content: () -> Content
) -> some View {
    let size = DimmingPickerMetrics.pt(80)
    content()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    isSelected ? brandOrange : Color.white.opacity(0.2),
                    lineWidth: isSelected ? DimmingPickerMetrics.pt(3) : DimmingPickerMetrics.pt(1)
                )
        )
        .neoMenuItemGazeHighlight(.circle)
        .contentShape(Circle())
}

@ViewBuilder
private func lightingPresetGridCell<Label: View, Thumbnail: View>(
    isSelected: Bool,
    brandOrange: Color,
    @ViewBuilder thumbnail: () -> Thumbnail,
    @ViewBuilder label: () -> Label,
    action: @escaping () -> Void
) -> some View {
    VStack(spacing: DimmingPickerMetrics.pt(8)) {
        Button(action: action) {
            lightingPresetCircularIcon(isSelected: isSelected, brandOrange: brandOrange, content: thumbnail)
        }
        .buttonStyle(.plain)

        label()
            .hoverEffectDisabled(true)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
    .frame(maxWidth: .infinity)
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
        VStack(spacing: DimmingPickerMetrics.pt(8)) {
            Button {
                if !isCycling {
                    onSelect()
                }
            } label: {
                lightingPresetCircularIcon(isSelected: isSelected, brandOrange: brandOrange) {
                    DimmingThumbnailView(
                        displayName: item.displayName,
                        dimLevel: item.dimLevel,
                        isPickerOpen: isPickerOpen,
                        brightness: currentBrightness,
                        isCycling: isCycling
                    )
                }
                .shadow(color: .white.opacity(isCycling ? currentBrightness * 0.8 : 0.0), radius: isCycling ? DimmingPickerMetrics.pt(12) : 0)
                .shadow(color: .white.opacity(isCycling ? currentBrightness * 0.4 : 0.0), radius: isCycling ? DimmingPickerMetrics.pt(24) : 0)
                .animation(.easeInOut(duration: 0.15), value: currentBrightness)
                .animation(.easeOut(duration: 0.4), value: isCycling)
            }
            .buttonStyle(HoldablePlainButtonStyle(
                onHold: { startBrightnessCycle() },
                onRelease: {
                    if isCycling {
                        stopBrightnessCycle()
                    }
                }
            ))

            HStack(spacing: DimmingPickerMetrics.pt(3)) {
                Text(item.displayName)
                    .font(.system(size: DimmingPickerMetrics.pt(14), weight: .medium))
                    .foregroundColor(isSelected ? brandOrange : .white)
                    .lineLimit(1)

                Image(systemName: "lightbulb.circle")
                    .font(.system(size: DimmingPickerMetrics.pt(9)))
                    .foregroundColor(isSelected ? brandOrange.opacity(0.7) : .white.opacity(0.5))
            }
            .hoverEffectDisabled(true)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isCycling {
                    onSelect()
                }
            }
        }
        .frame(maxWidth: .infinity)
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
    
    var body: some View {
        Group {
            if dimLevel == 12, let _ = UIImage(named: "starfield") {
                // Use custom image for Starfield preset
                Image("starfield")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: DimmingPickerMetrics.pt(80), height: DimmingPickerMetrics.pt(80))
                    .clipShape(Circle())
            } else if usesAnimatedReactiveGradient {
                TimelineView(.animation(minimumInterval: 0.15, paused: !isPickerOpen)) { context in
                    Circle()
                        .fill(gradientForPreset(animationPhase: reactiveAnimationPhase(for: context.date)))
                        .frame(width: DimmingPickerMetrics.pt(80), height: DimmingPickerMetrics.pt(80))
                        .opacity(thumbnailOpacity)
                }
            } else if usesAnimatedTideGradient {
                TimelineView(.animation(minimumInterval: 0.12, paused: !isPickerOpen)) { context in
                    let phase = tideAnimationPhase(for: context.date)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: TideGradientPalette.swiftUIColors(atPhase: phase),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: DimmingPickerMetrics.pt(80), height: DimmingPickerMetrics.pt(80))
                        .opacity(thumbnailOpacity)
                }
            } else {
                // Use gradient for all other presets
                Circle()
                    .fill(gradientForPreset())
                    .frame(width: DimmingPickerMetrics.pt(80), height: DimmingPickerMetrics.pt(80))
                    // Apply brightness to thumbnail opacity for adjustable presets
                    .opacity(thumbnailOpacity)
                    .overlay(
                        Group {
                            if dimLevel == 0 {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: DimmingPickerMetrics.pt(40)))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    )
            }
        }
    }

    private var usesAnimatedReactiveGradient: Bool {
        dimLevel == 2
    }

    private var usesAnimatedTideGradient: Bool {
        dimLevel == 10
    }

    private func tideAnimationPhase(for date: Date) -> CGFloat {
        let cycle = TideGradientPalette.cycleDuration
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat(t)
    }

    private func reactiveAnimationPhase(for date: Date) -> Double {
        let cycle: Double = 6.0
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        return t
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
    
    private func gradientForPreset(animationPhase: Double = 0) -> LinearGradient {
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

extension DimmingPickerView {
    /// Curved-display RealityKit sizing: historically `0.96` screen fraction at 1.0 UI scale; scale with ``DimmingPickerMetrics`` so spatial size matches SwiftUI shrink.
    static var curvedDesiredLocalWidth: Float { 0.96 * Float(DimmingPickerMetrics.scale) }
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

// MARK: - Tide morphing gradient (water hues: navy → blue → teal → teal-green)

enum TideGradientPalette {
    struct Stop {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
        var a: CGFloat
    }

    /// Full loop duration (~50% slower than the original 36s).
    static let cycleDuration: TimeInterval = 54.0

    private static let locations: [CGFloat] = [0.0, 0.30, 0.60, 1.0]
    private static let fixedAlphas: [CGFloat] = [0.65, 0.75, 0.88, 0.98]

    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    /// RGB-only keyframes; alpha held constant per stop to avoid brightness flicker.
    private static let keyframes: [[RGB]] = [
        // Deep navy abyss
        [(0.02, 0.06, 0.16), (0.03, 0.12, 0.26), (0.04, 0.18, 0.32), (0.02, 0.08, 0.14)],
        // Midnight ocean
        [(0.03, 0.10, 0.28), (0.04, 0.18, 0.36), (0.06, 0.26, 0.42), (0.02, 0.10, 0.18)],
        // Ocean blue
        [(0.04, 0.14, 0.34), (0.05, 0.22, 0.42), (0.07, 0.30, 0.48), (0.03, 0.12, 0.22)],
        // Teal
        [(0.04, 0.22, 0.38), (0.06, 0.30, 0.44), (0.08, 0.38, 0.46), (0.03, 0.14, 0.24)],
        // Teal-green
        [(0.04, 0.28, 0.36), (0.06, 0.34, 0.40), (0.08, 0.40, 0.42), (0.03, 0.16, 0.22)],
        // Shallow aqua (wraps smoothly back to deep navy)
        [(0.05, 0.30, 0.40), (0.06, 0.28, 0.38), (0.05, 0.22, 0.34), (0.02, 0.08, 0.16)]
    ]

    static func stops(atPhase phase: CGFloat) -> [Stop] {
        let wrapped = phase - floor(phase)
        let segmentCount = CGFloat(keyframes.count)
        let segment = wrapped * segmentCount
        let index = Int(segment) % keyframes.count
        // Linear drift — no ease-in/out pauses at keyframe boundaries.
        let localT = segment - floor(segment)
        let from = keyframes[index]
        let to = keyframes[(index + 1) % keyframes.count]
        return zip(zip(from, to), fixedAlphas).map { rgbPair, alpha in
            let (fromRGB, toRGB) = rgbPair
            return Stop(
                r: fromRGB.r + (toRGB.r - fromRGB.r) * localT,
                g: fromRGB.g + (toRGB.g - fromRGB.g) * localT,
                b: fromRGB.b + (toRGB.b - fromRGB.b) * localT,
                a: alpha
            )
        }
    }

    static func swiftUIColors(atPhase phase: CGFloat) -> [Color] {
        stops(atPhase: phase).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    static func makeCGImage(size: Int, phase: CGFloat) -> CGImage? {
        let s = max(size, 32)
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let stops = stops(atPhase: phase)
        let colors = stops.map {
            UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: $0.a).cgColor
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
            ctx.cgContext.fill(rect)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors as CFArray,
                locations: locations
            ) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: [.drawsAfterEndLocation]
                )
            }
        }
        return image.cgImage
    }
}

// MARK: - Persisted lighting preset (flat + curved)

enum AmbientDimmingPersistence {
    static let userDefaultsKey = "ambient.dimming.level"

    /// All dim levels exposed in `DimmingPickerView` plus legacy moonlight cycle (11).
    static let validLevels: Set<Int> = [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14]

    static func load() -> Int {
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return validLevels.contains(raw) ? raw : 0
    }

    static func save(_ level: Int) {
        let clamped = validLevels.contains(level) ? level : 0
        UserDefaults.standard.set(clamped, forKey: userDefaultsKey)
    }
}

// MARK: - Persisted 360° environment (curved display)

enum CurvedEnvironmentPersistence {
    static let sphereKey = "curved.environmentSphereLevel"
    static let newsetKey = "curved.newsetLevel"

    static func maxSphereLevel(extraSkyboxCount: Int) -> Int {
        SkyboxCatalog.builtinNames.count + extraSkyboxCount
    }

    static func load(extraSkyboxCount: Int) -> (sphere: Int, newset: Int) {
        let maxSphere = maxSphereLevel(extraSkyboxCount: extraSkyboxCount)
        let maxNewset = SkyboxCatalog.newsetNames.count

        var sphere = UserDefaults.standard.integer(forKey: sphereKey)
        var newset = UserDefaults.standard.integer(forKey: newsetKey)

        if newset < 0 || newset > maxNewset { newset = 0 }
        if sphere < 0 { sphere = 0 }
        if sphere > maxSphere {
            // Extra skyboxes load asynchronously; keep saved index until bundle extras arrive.
            if extraSkyboxCount == 0, sphere <= SkyboxCatalog.builtinNames.count + 64 {
                // defer clamp
            } else {
                sphere = 0
            }
        }

        if newset > 0 {
            sphere = 0
        } else if sphere > 0 {
            newset = 0
        }

        return (sphere, newset)
    }

    static func save(sphere: Int, newset: Int) {
        let maxNewset = SkyboxCatalog.newsetNames.count
        let clampedNewset = (newset >= 0 && newset <= maxNewset) ? newset : 0
        let clampedSphere = max(0, sphere)

        if clampedNewset > 0 {
            UserDefaults.standard.set(0, forKey: sphereKey)
            UserDefaults.standard.set(clampedNewset, forKey: newsetKey)
        } else {
            UserDefaults.standard.set(clampedSphere, forKey: sphereKey)
            UserDefaults.standard.set(0, forKey: newsetKey)
        }
    }
}
