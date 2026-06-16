//
//  ScreenPresetPanel.swift
//  Moonlight Vision
//

import SwiftUI

struct ScreenPresetPanel: View {
    @ObservedObject var settings: ScreenPresetSettings
    @Binding var isPresented: Bool
    var attachmentLayoutScale: CGFloat = 0.6
    var onRenamingActiveChanged: ((Bool) -> Void)? = nil
    var onApplyPreset: (Int) -> Void
    var onSaveCurrentToActive: () -> Void
    var isHeadFollowActive: Bool = false

    @AppStorage("curved.restoreScreenPresetOnLaunch") private var restoreOnLaunch = false

    @State private var renamingSlot: Int?
    @State private var renameDraft: String = ""
    @State private var renameCancelled = false
    @FocusState private var renameFieldFocused: Bool

    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    private let presetPillWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Preset")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("Save and recall screen layout")
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Tap a preset to restore screen position, curve, and size. Use Save to store the current screen. For quicker access, Long-press the top-bar Screen Preset button to cycle through presets 1-3.")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dividerLine

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionLabel("Presets")
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

                if let slot = renamingSlot {
                    presetRenameInline(slot: slot)
                } else {
                    HStack(spacing: 12) {
                        ForEach(ScreenPresetSlot.allCases, id: \.rawValue) { slot in
                            presetPill(slot: slot.rawValue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if renamingSlot == nil {
                dividerLine

                HStack {
                    Spacer()
                    Button {
                        onSaveCurrentToActive()
                    } label: {
                        Label(
                            "Save current screen to \(settings.displayName(for: settings.activePresetSlot))",
                            systemImage: "square.and.arrow.down"
                        )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isHeadFollowActive ? .white.opacity(0.4) : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isHeadFollowActive)
                    .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                }
            }

            dividerLine

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Launch")
                Toggle(isOn: $restoreOnLaunch) {
                    (
                        Text("Restore Screen Preset on launch")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        + Text(" – When off, curved mode starts with the default position and size.")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .tint(brandOrange)
                .foregroundStyle(.white)
            }
        }
        .padding(32)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .neoClearBluePanelChrome(cornerRadius: 24)
        .scaleEffect(attachmentLayoutScale)
        .foregroundStyle(.white)
        .onChange(of: renamingSlot) { _, newSlot in
            onRenamingActiveChanged?(newSlot != nil)
        }
        .onDisappear {
            onRenamingActiveChanged?(false)
        }
    }

    @ViewBuilder
    private func presetPill(slot: Int) -> some View {
        let isActive = settings.activePresetSlot == slot
        let title = settings.displayName(for: slot)
        let hasData = ScreenPresetSettings.hasSavedData(for: slot)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.selectActiveSlot(slot)
                onApplyPreset(slot)
            }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                if !hasData {
                    Text("Empty")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .frame(width: presetPillWidth, height: 40)
            .id("screen-preset-\(slot)-\(title)")
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

    @ViewBuilder
    private func presetRenameInline(slot: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename \(ScreenPresetSlot(rawValue: slot)?.defaultDisplayName ?? "Preset")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 8) {
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                    .focused($renameFieldFocused)
                    .onSubmit { commitRenaming(slot: slot) }

                Button("Cancel") { cancelRenaming() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .buttonStyle(.plain)

                Button("Done") { commitRenaming(slot: slot) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(brandOrange)
                    .buttonStyle(.plain)
            }
        }
        .onChange(of: renameFieldFocused) { _, focused in
            if !focused && renamingSlot == slot && !renameCancelled {
                commitRenaming(slot: slot)
            }
        }
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.6))
    }
}
