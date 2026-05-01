//
//  HDRControlPanel.swift
//  Moonlight Vision
//
//  Created by AI Assistant on 1/19/25. Updated May 2026 by NeoVector X.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct HDRControlPanel: View {
    @ObservedObject var settings: HDRSettings
    @Binding var isPresented: Bool

    private let brandNavy   = Color(red: 0.12, green: 0.18, blue: 0.37)
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enhanced HDR")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("Fine-tune color and exposure")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
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

            dividerLine

            // Display Quality
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Display Quality")

                HDRSlider(title: "Brightness",  value: $settings.brightness, range: 0.5...2.0, defaultValue: 1.35, icon: "sun.max.fill",          brandOrange: brandOrange)
                VStack(alignment: .leading, spacing: 4) {
                    HDRSlider(title: "Contrast", value: $settings.contrast, range: 0.5...2.0, defaultValue: 1.15, icon: "circle.lefthalf.filled", brandOrange: brandOrange)
                    Text("Values below 1.0 brighten dark areas toward mid-tones.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HDRSlider(title: "Saturation",  value: $settings.saturation, range: 0.0...2.0, defaultValue: 1.40, icon: "paintpalette.fill",       brandOrange: brandOrange)
            }

            dividerLine

            // Exposure
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Exposure")
                HDRSlider(title: "Exposure", value: $settings.pqExposure, range: 0.5...2.0, defaultValue: 1.0, icon: "dial.medium.fill", brandOrange: brandOrange)
            }

            dividerLine

            // Reset
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { settings.reset() }
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(32)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(brandNavy.opacity(0.4))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .scaleEffect(0.6)
        .onChange(of: settings.brightness)  { _, _ in settings.save() }
        .onChange(of: settings.contrast)    { _, _ in settings.save() }
        .onChange(of: settings.saturation)  { _, _ in settings.save() }
        .onChange(of: settings.pqExposure)  { _, _ in settings.save() }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.45))
            .textCase(.uppercase)
            .kerning(1.0)
    }
}

// MARK: - HDR Slider

struct HDRSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let icon: String
    let brandOrange: Color
    var step: Float = 0.01

    @State private var isResetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Text(String(format: "%.2f", value))
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
                    .frame(minWidth: 44, alignment: .trailing)

                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        value = defaultValue
                        isResetting = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isResetting = false }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundColor(abs(value - defaultValue) < 0.01 ? Color.white.opacity(0.2) : Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .scaleEffect(isResetting ? 0.8 : 1.0)
                .disabled(abs(value - defaultValue) < 0.01)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in value = (newValue / step).rounded() * step }
                ),
                in: range
            )
            .tint(brandOrange)
        }
    }
}

#Preview {
    @State var isPresented = true
    @StateObject var settings = HDRSettings()
    return HDRControlPanel(settings: settings, isPresented: $isPresented)
        .padding()
}
