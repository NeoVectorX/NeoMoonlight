//
//  HDRSettings.swift
//  Moonlight Vision
//
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import Combine

private enum HDRSettingsMigration {
    /// One-shot: restores pre-overhaul trims for installs that persisted contrast/sat both 1.0.
    static let legacyTrimsKey = "hdrTrimsRestoredLegacy_v1"
    /// One-shot: three named presets + active slot (flat/curved Enhanced HDR panel).
    static let presetsV1Key = "hdrPreset.v1.initialized"
}

enum HDRPresetSlot: Int, CaseIterable {
    case one = 1
    case two = 2
    case three = 3

    static let maxDisplayNameLength = 10

    var defaultDisplayName: String {
        "Preset \(rawValue)"
    }
}

/// Plato Enhanced HDR defaults (flat/curved panel).
enum HDRPlatoDefaults {
    static let brightness: Float = 1.35
    static let contrast: Float = 1.15
    static let saturation: Float = 1.40
    static let pqExposure: Float = 1.0
}

struct HDRPresetValues: Equatable {
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var pqExposure: Float

    static var plato: HDRPresetValues {
        HDRPresetValues(
            brightness: HDRPlatoDefaults.brightness,
            contrast: HDRPlatoDefaults.contrast,
            saturation: HDRPlatoDefaults.saturation,
            pqExposure: HDRPlatoDefaults.pqExposure
        )
    }
}

/// Robust Float reading from UserDefaults — handles Float, Double, or NSNumber storage
private func persistedFloat(forKey key: String, default defaultValue: Float) -> Float {
    guard let v = UserDefaults.standard.object(forKey: key) else { return defaultValue }
    switch v {
    case let f as Float: return f
    case let d as Double: return Float(d)
    case let n as NSNumber: return n.floatValue
    default: return defaultValue
    }
}

private func presetKey(_ slot: HDRPresetSlot, _ field: String) -> String {
    "hdrPreset.\(slot.rawValue).\(field)"
}

class HDRSettings: ObservableObject {
    /// Active bank (1–3). Persisted; applied at stream start via loaded slider values.
    @Published var activePresetSlot: Int {
        didSet {
            let clamped = Self.clampSlot(activePresetSlot)
            if clamped != activePresetSlot {
                activePresetSlot = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.activeSlotKey)
        }
    }

    @Published var brightness: Float {
        didSet { persistActivePresetTrim(key: "brightness", value: brightness) }
    }

    @Published var contrast: Float {
        didSet { persistActivePresetTrim(key: "contrast", value: contrast) }
    }

    @Published var saturation: Float {
        didSet { persistActivePresetTrim(key: "saturation", value: saturation) }
    }

    @Published var pqExposure: Float {
        didSet { persistActivePresetTrim(key: "pqExposure", value: pqExposure) }
    }

    /// Minimal client grading: PQ + gamut + one tone map (no panel boost/sat/con/radial in shader).
    @Published var referenceHDR: Bool {
        didSet { UserDefaults.standard.set(referenceHDR, forKey: "hdrReferenceMode") }
    }

    /// Display names for slots 1…3 (index 0 = preset 1).
    @Published private(set) var presetDisplayNames: [String]

    private var isApplyingPresetLoad = false

    private static let activeSlotKey = "hdrPreset.activeSlot"

    init() {
        Self.runLegacyTrimsMigrationIfNeeded()
        Self.initializePresetsIfNeeded()

        let storedSlot = UserDefaults.standard.integer(forKey: Self.activeSlotKey)
        let initialSlot = storedSlot >= 1 && storedSlot <= 3 ? storedSlot : 1

        presetDisplayNames = HDRPresetSlot.allCases.map { Self.loadDisplayName(for: $0) }

        isApplyingPresetLoad = true
        activePresetSlot = initialSlot
        let values = Self.loadPresetValues(for: HDRPresetSlot(rawValue: initialSlot)!)
        brightness = values.brightness
        contrast = values.contrast
        saturation = values.saturation
        pqExposure = values.pqExposure
        isApplyingPresetLoad = false

        referenceHDR = UserDefaults.standard.bool(forKey: "hdrReferenceMode")
    }

    func save() {
        // Trims auto-saved per active preset in didSet.
    }

    func displayName(for slot: Int) -> String {
        let idx = Self.clampSlot(slot) - 1
        guard presetDisplayNames.indices.contains(idx) else {
            return HDRPresetSlot(rawValue: Self.clampSlot(slot))?.defaultDisplayName ?? "Preset"
        }
        return presetDisplayNames[idx]
    }

    func selectPreset(slot: Int) {
        let clamped = Self.clampSlot(slot)
        guard clamped != activePresetSlot else { return }

        activePresetSlot = clamped
        applyLoadedValues(Self.loadPresetValues(for: HDRPresetSlot(rawValue: clamped)!))
    }

    func setDisplayName(for slot: Int, _ rawName: String) {
        let clamped = Self.clampSlot(slot)
        let trimmed = Self.sanitizeDisplayName(rawName, fallback: HDRPresetSlot(rawValue: clamped)!.defaultDisplayName)
        UserDefaults.standard.set(trimmed, forKey: presetKey(HDRPresetSlot(rawValue: clamped)!, "displayName"))
        let idx = clamped - 1
        guard presetDisplayNames.indices.contains(idx) else { return }
        // Replace the array so @Published emits (in-place element writes do not refresh SwiftUI).
        var names = presetDisplayNames
        names[idx] = trimmed
        presetDisplayNames = names
    }

    /// Resets slider values for the active preset only; keeps its display name.
    func reset() {
        applyLoadedValues(.plato)
        persistActivePresetFromPublishedValues()
    }

    // MARK: - Private

    private func applyLoadedValues(_ values: HDRPresetValues) {
        isApplyingPresetLoad = true
        brightness = values.brightness
        contrast = values.contrast
        saturation = values.saturation
        pqExposure = values.pqExposure
        isApplyingPresetLoad = false
    }

    private func persistActivePresetTrim(key: String, value: Float) {
        guard !isApplyingPresetLoad else { return }
        guard let slot = HDRPresetSlot(rawValue: activePresetSlot) else { return }
        UserDefaults.standard.set(value, forKey: presetKey(slot, key))
    }

    private func persistActivePresetFromPublishedValues() {
        guard let slot = HDRPresetSlot(rawValue: activePresetSlot) else { return }
        let v = HDRPresetValues(brightness: brightness, contrast: contrast, saturation: saturation, pqExposure: pqExposure)
        Self.savePresetValues(v, for: slot)
    }

    private static func clampSlot(_ slot: Int) -> Int {
        min(3, max(1, slot))
    }

    static func sanitizeDisplayName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(HDRPresetSlot.maxDisplayNameLength))
    }

    private static func loadDisplayName(for slot: HDRPresetSlot) -> String {
        let key = presetKey(slot, "displayName")
        guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else {
            return slot.defaultDisplayName
        }
        return sanitizeDisplayName(stored, fallback: slot.defaultDisplayName)
    }

    private static func loadPresetValues(for slot: HDRPresetSlot) -> HDRPresetValues {
        HDRPresetValues(
            brightness: persistedFloat(forKey: presetKey(slot, "brightness"), default: HDRPlatoDefaults.brightness),
            contrast: persistedFloat(forKey: presetKey(slot, "contrast"), default: HDRPlatoDefaults.contrast),
            saturation: persistedFloat(forKey: presetKey(slot, "saturation"), default: HDRPlatoDefaults.saturation),
            pqExposure: persistedFloat(forKey: presetKey(slot, "pqExposure"), default: HDRPlatoDefaults.pqExposure)
        )
    }

    private static func savePresetValues(_ values: HDRPresetValues, for slot: HDRPresetSlot) {
        UserDefaults.standard.set(values.brightness, forKey: presetKey(slot, "brightness"))
        UserDefaults.standard.set(values.contrast, forKey: presetKey(slot, "contrast"))
        UserDefaults.standard.set(values.saturation, forKey: presetKey(slot, "saturation"))
        UserDefaults.standard.set(values.pqExposure, forKey: presetKey(slot, "pqExposure"))
    }

    private static func initializePresetsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: HDRSettingsMigration.presetsV1Key) else { return }
        UserDefaults.standard.set(true, forKey: HDRSettingsMigration.presetsV1Key)

        // Migrate legacy global trims into preset 1; presets 2–3 start at Plato defaults.
        let legacy = HDRPresetValues(
            brightness: persistedFloat(forKey: "hdrBrightness", default: HDRPlatoDefaults.brightness),
            contrast: persistedFloat(forKey: "hdrContrast", default: HDRPlatoDefaults.contrast),
            saturation: persistedFloat(forKey: "hdrSaturation", default: HDRPlatoDefaults.saturation),
            pqExposure: persistedFloat(forKey: "hdrPqExposure", default: HDRPlatoDefaults.pqExposure)
        )
        savePresetValues(legacy, for: .one)
        savePresetValues(.plato, for: .two)
        savePresetValues(.plato, for: .three)

        for slot in HDRPresetSlot.allCases {
            UserDefaults.standard.set(slot.defaultDisplayName, forKey: presetKey(slot, "displayName"))
        }

        let active = UserDefaults.standard.integer(forKey: activeSlotKey)
        if active < 1 || active > 3 {
            UserDefaults.standard.set(1, forKey: activeSlotKey)
        }
    }

    private static func runLegacyTrimsMigrationIfNeeded() {
        let defaultsContrast = HDRPlatoDefaults.contrast
        let defaultsSaturation = HDRPlatoDefaults.saturation

        let alreadyMigrated = UserDefaults.standard.bool(forKey: HDRSettingsMigration.legacyTrimsKey)
        if !alreadyMigrated {
            UserDefaults.standard.set(true, forKey: HDRSettingsMigration.legacyTrimsKey)
            if persistedFloat(forKey: "hdrContrast", default: defaultsContrast) == 1.0
                && persistedFloat(forKey: "hdrSaturation", default: defaultsSaturation) == 1.0 {
                UserDefaults.standard.set(defaultsContrast, forKey: "hdrContrast")
                UserDefaults.standard.set(defaultsSaturation, forKey: "hdrSaturation")
            }
        }
    }
}
