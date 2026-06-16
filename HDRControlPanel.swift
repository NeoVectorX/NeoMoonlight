//
//  HDRControlPanel.swift
//  Moonlight Vision
//
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct HDRControlPanel: View {
    @ObservedObject var settings: HDRSettings
    @Binding var isPresented: Bool
    /// Pushed on every slider tick from this panel (RealityKit attachments do not always propagate parent `onChange`).
    var onLiveUpdate: (() -> Void)? = nil
    /// Curved-display attachment uses `0.6`; flat display passes `1.0` where the panel is not embedded as a shrunk attachment.
    var attachmentLayoutScale: CGFloat = 0.6
    /// When `true` and Reference HDR is on: grading sliders keep full layout but lose orange accent and do not accept drags (flat and curved pass this).
    var dimInactiveGradingControlsWhenReferenceHDR: Bool = false
    /// Curved stream uses this to pause screen gestures while the preset rename field is focused.
    var onRenamingActiveChanged: ((Bool) -> Void)? = nil

    @State private var renamingSlot: Int?
    @State private var renameDraft: String = ""
    @State private var renameCancelled = false
    @FocusState private var renameFieldFocused: Bool

    private var referenceHDRNeutralGradingSliderChrome: Bool {
        dimInactiveGradingControlsWhenReferenceHDR && settings.referenceHDR
    }

    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

    private let presetPillWidth: CGFloat = 140

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
                        .foregroundColor(.white)
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
                .neoMenuItemGazeHighlight(.circle)
            }

            dividerLine

            // Display Quality
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Display Quality")

                HDRSlider(title: "Brightness", value: $settings.brightness, range: 0.5...2.0, defaultValue: HDRPlatoDefaults.brightness, icon: "sun.max.fill", brandOrange: brandOrange, neutralChrome: referenceHDRNeutralGradingSliderChrome)
                HDRSlider(title: "Contrast", value: $settings.contrast, range: 0.5...2.0, defaultValue: HDRPlatoDefaults.contrast, icon: "circle.lefthalf.filled", brandOrange: brandOrange, neutralChrome: referenceHDRNeutralGradingSliderChrome)
                Text("Values below 1.0 brighten dark areas toward mid-tones.")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                HDRSlider(title: "Saturation", value: $settings.saturation, range: 0.0...2.0, defaultValue: HDRPlatoDefaults.saturation, icon: "paintpalette.fill", brandOrange: brandOrange, neutralChrome: referenceHDRNeutralGradingSliderChrome)
            }

            dividerLine

            // Exposure
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Exposure")
                HDRSlider(title: "Exposure", value: $settings.pqExposure, range: 0.5...2.0, defaultValue: HDRPlatoDefaults.pqExposure, icon: "dial.medium.fill", brandOrange: brandOrange, neutralChrome: referenceHDRNeutralGradingSliderChrome)
            }

            dividerLine

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Accuracy")
                Toggle(isOn: $settings.referenceHDR) {
                    (
                        Text("Reference HDR")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        + Text(" – Adjustments via sliders or filters do not apply when enabled.")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .tint(brandOrange)
                .foregroundStyle(.white)
            }

            dividerLine

            // HDR Presets (flat + curved Enhanced HDR only)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionLabel("HDR Presets")
                    Spacer()
                    if renamingSlot == nil {
                        Button {
                            beginRenaming(slot: settings.activePresetSlot)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Edit")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                        .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 8))
                        .accessibilityLabel("Edit preset name")
                    }
                }

                Text("Applies to Enhanced HDR sliders")
                    .font(.system(size: 11))
                    .foregroundColor(.white)

                if let slot = renamingSlot {
                    hdrPresetRenameInline(slot: slot)
                } else {
                    HStack(spacing: 12) {
                        ForEach(HDRPresetSlot.allCases, id: \.rawValue) { slot in
                            hdrPresetPill(slot: slot.rawValue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if renamingSlot == nil {
                dividerLine

                // Reset current preset
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { settings.reset() }
                    } label: {
                        Label("Reset current preset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                }
            }
        }
        .padding(32)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .neoClearBluePanelChrome(cornerRadius: 24)
        .scaleEffect(attachmentLayoutScale)
        .foregroundStyle(.white)
        .onChange(of: settings.brightness)  { _, _ in notifyPanelValueChanged() }
        .onChange(of: settings.contrast)    { _, _ in notifyPanelValueChanged() }
        .onChange(of: settings.saturation)  { _, _ in notifyPanelValueChanged() }
        .onChange(of: settings.pqExposure)  { _, _ in notifyPanelValueChanged() }
        .onChange(of: settings.referenceHDR) { _, _ in notifyPanelValueChanged() }
        .onChange(of: settings.activePresetSlot) { _, _ in notifyPanelValueChanged() }
        .onChange(of: renamingSlot) { _, newSlot in
            onRenamingActiveChanged?(newSlot != nil)
        }
        .onDisappear {
            onRenamingActiveChanged?(false)
        }
    }

    @ViewBuilder
    private func hdrPresetPill(slot: Int) -> some View {
        let isActive = settings.activePresetSlot == slot
        let title = settings.displayName(for: slot)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.selectPreset(slot: slot)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: presetPillWidth, height: 40)
                .id("hdr-preset-\(slot)-\(title)")
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? brandOrange.opacity(0.35) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? brandOrange : Color.white.opacity(0.2), lineWidth: isActive ? 2 : 1)
        )
        .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func beginRenaming(slot: Int) {
        renameCancelled = false
        renameDraft = settings.displayName(for: slot)
        renamingSlot = slot
        renameFieldFocused = true
    }

    private func cancelRenaming() {
        renameCancelled = true
        renameFieldFocused = false
        renamingSlot = nil
    }

    private func commitRenaming(slot: Int) {
        settings.setDisplayName(for: slot, renameDraft)
        renameFieldFocused = false
        renamingSlot = nil
    }

    /// Inline rename (sheets do not present reliably from stream HDR attachments on visionOS).
    private func hdrPresetRenameInline(slot: Int) -> some View {
        VStack(spacing: 12) {
            Text("Rename preset \(slot)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            TextField("Name", text: $renameDraft, prompt: Text("Name").foregroundColor(.white))
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .submitLabel(.done)
                .focused($renameFieldFocused)
                .onSubmit { commitRenaming(slot: slot) }
                .onChange(of: renameFieldFocused) { wasFocused, isFocused in
                    guard wasFocused, !isFocused, !renameCancelled, renamingSlot == slot else {
                        if !isFocused { renameCancelled = false }
                        return
                    }
                    commitRenaming(slot: slot)
                }
                .onChange(of: renameDraft) { _, newValue in
                    if newValue.count > HDRPresetSlot.maxDisplayNameLength {
                        renameDraft = String(newValue.prefix(HDRPresetSlot.maxDisplayNameLength))
                    }
                }

            Text("\(renameDraft.count)/\(HDRPresetSlot.maxDisplayNameLength) · e.g. COD, GTA5")
                .font(.system(size: 11))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Button { cancelRenaming() } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button { commitRenaming(slot: slot) } label: {
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(brandOrange.opacity(0.85))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(minHeight: 148, alignment: .top)
        .padding(.vertical, 4)
    }

    private func notifyPanelValueChanged() {
        settings.save()
        onLiveUpdate?()
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
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
    /// Reference HDR + stream flag: no orange accent, sliders do not move (layout unchanged).
    var neutralChrome: Bool = false

    @State private var isResetting = false

    private var sliderTint: Color {
        neutralChrome ? Color.white.opacity(0.28) : brandOrange
    }

    private var chromeInteractive: Bool { !neutralChrome }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Text(String(format: "%.2f", value))
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundColor(.white)
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
                .disabled(!chromeInteractive || abs(value - defaultValue) < 0.01)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in value = (newValue / step).rounded() * step }
                ),
                in: range
            )
            .tint(sliderTint)
            .disabled(!chromeInteractive)
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true
    @StateObject var settings = HDRSettings()
    return HDRControlPanel(settings: settings, isPresented: $isPresented)
        .padding()
}
