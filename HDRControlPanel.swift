//
//  HDRControlPanel.swift
//  Moonlight Vision
//
//  Created by AI Assistant on 1/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct HDRControlPanel: View {
    @ObservedObject var settings: HDRSettings
    @Binding var isPresented: Bool
    
    @State private var showAdvanced = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enhanced HDR")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Fine-tune your display quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Display Quality Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Display Quality")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                HDRSlider(
                    title: "Brightness",
                    value: $settings.brightness,
                    range: 0.5...2.0,
                    defaultValue: 1.0,
                    icon: "sun.max.fill"
                )
                
                HDRSlider(
                    title: "Contrast",
                    value: $settings.contrast,
                    range: 0.5...2.0,
                    defaultValue: 1.15,
                    icon: "circle.lefthalf.filled"
                )
                
                HDRSlider(
                    title: "Saturation",
                    value: $settings.saturation,
                    range: 0.0...2.0,
                    defaultValue: 1.0,
                    icon: "paintpalette.fill"
                )
            }
            
            Divider()
            
            // Advanced Section
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 16) {
                    HDRSlider(
                        title: "Luminance",
                        value: $settings.luminance,
                        range: 100...1000,
                        defaultValue: 300,
                        icon: "lightbulb.fill",
                        unit: " nits",
                        step: 10
                    )
                    
                    HDRSlider(
                        title: "Gamma",
                        value: $settings.gamma,
                        range: 1.8...2.8,
                        defaultValue: 2.2,
                        icon: "chart.line.uptrend.xyaxis",
                        step: 0.1
                    )
                    
                    HDRSlider(
                        title: "Peak Brightness",
                        value: $settings.peakBrightness,
                        range: 400...1600,
                        defaultValue: 800,
                        icon: "sun.max.circle.fill",
                        unit: " nits",
                        step: 50
                    )
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Text("Advanced")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .tint(.primary)
            
            Divider()
            
            // Reset Button
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        settings.reset()
                    }
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(28)
        .frame(width: 450)
        .glassBackgroundEffect()
        .onChange(of: settings.brightness) { _, _ in settings.save() }
        .onChange(of: settings.contrast) { _, _ in settings.save() }
        .onChange(of: settings.saturation) { _, _ in settings.save() }
        .onChange(of: settings.luminance) { _, _ in settings.save() }
        .onChange(of: settings.gamma) { _, _ in settings.save() }
        .onChange(of: settings.peakBrightness) { _, _ in settings.save() }
    }
}

// Custom HDR Slider Component
struct HDRSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let icon: String
    var unit: String = ""
    var step: Float = 0.01
    
    @State private var isResetting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Value display with unit
                Text(String(format: unit.isEmpty ? "%.2f" : "%.0f", value) + unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .trailing)
                
                // Reset to default button
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        value = defaultValue
                        isResetting = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isResetting = false
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(abs(value - defaultValue) < 0.01 ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .scaleEffect(isResetting ? 0.8 : 1.0)
                .disabled(abs(value - defaultValue) < 0.01)
            }
            
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        value = (newValue / step).rounded() * step
                    }
                ),
                in: range
            )
            .tint(.blue)
        }
    }
}

#Preview {
    @State var isPresented = true
    @StateObject var settings = HDRSettings()
    
    return HDRControlPanel(settings: settings, isPresented: $isPresented)
        .frame(width: 600, height: 800)
}
