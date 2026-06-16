//
//  ScreenPresetSettings.swift
//  Moonlight Vision
//

import Foundation
import simd
import ARKit

private enum ScreenPresetMigration {
    static let initializedKey = "screenPreset.v1.initialized"
}

enum ScreenPresetSlot: Int, CaseIterable {
    case one = 1
    case two = 2
    case three = 3

    static let maxDisplayNameLength = 10

    var defaultDisplayName: String {
        "Preset \(rawValue)"
    }
}

struct ScreenPresetValues: Equatable {
    var position: SIMD3<Float>
    var scale: Float
    var curveMagnitude: Float
    var tiltAngle: Float
    var yawAngle: Float
    /// UUID of a persisted WorldAnchor at the saved screen location (room-fixed positioning).
    var worldAnchorID: UUID?

    /// Matches `CurvedFirstLaunch` defaults (position, scale, 1800R curvature).
    static var firstLaunchDefault: ScreenPresetValues {
        ScreenPresetValues(
            position: SIMD3<Float>(0, 1.55, -2.75),
            scale: 1.62,
            curveMagnitude: CurvatureTick.defaultTick.magnitude,
            tiltAngle: 0,
            yawAngle: 0,
            worldAnchorID: nil
        )
    }
}

private func screenPresetKey(_ slot: ScreenPresetSlot, _ field: String) -> String {
    "screenPreset.\(slot.rawValue).\(field)"
}

private func persistedFloat(forKey key: String, default defaultValue: Float) -> Float {
    guard let v = UserDefaults.standard.object(forKey: key) else { return defaultValue }
    switch v {
    case let f as Float: return f
    case let d as Double: return Float(d)
    case let n as NSNumber: return n.floatValue
    default: return defaultValue
    }
}

class ScreenPresetSettings: ObservableObject {
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

    @Published private(set) var presetDisplayNames: [String]

    private static let activeSlotKey = "screenPreset.activeSlot"

    init() {
        Self.initializePresetsIfNeeded()

        let storedSlot = UserDefaults.standard.integer(forKey: Self.activeSlotKey)
        activePresetSlot = storedSlot >= 1 && storedSlot <= 3 ? storedSlot : 1
        presetDisplayNames = ScreenPresetSlot.allCases.map { Self.loadDisplayName(for: $0) }
    }

    func displayName(for slot: Int) -> String {
        let idx = Self.clampSlot(slot) - 1
        guard presetDisplayNames.indices.contains(idx) else {
            return ScreenPresetSlot(rawValue: Self.clampSlot(slot))?.defaultDisplayName ?? "Preset"
        }
        return presetDisplayNames[idx]
    }

    func selectActiveSlot(_ slot: Int) {
        activePresetSlot = Self.clampSlot(slot)
    }

    /// Long-press cycle: 1 → 2 → 3 → 1. Returns the new active slot.
    func cycleActivePreset() -> Int {
        let next = activePresetSlot >= 3 ? 1 : activePresetSlot + 1
        activePresetSlot = next
        return next
    }

    func setDisplayName(for slot: Int, _ rawName: String) {
        let clamped = Self.clampSlot(slot)
        let trimmed = Self.sanitizeDisplayName(
            rawName,
            fallback: ScreenPresetSlot(rawValue: clamped)!.defaultDisplayName
        )
        UserDefaults.standard.set(trimmed, forKey: screenPresetKey(ScreenPresetSlot(rawValue: clamped)!, "displayName"))
        let idx = clamped - 1
        guard presetDisplayNames.indices.contains(idx) else { return }
        var names = presetDisplayNames
        names[idx] = trimmed
        presetDisplayNames = names
    }

    static func hasSavedData(for slot: Int) -> Bool {
        guard let s = ScreenPresetSlot(rawValue: clampSlot(slot)) else { return false }
        return UserDefaults.standard.bool(forKey: screenPresetKey(s, "saved"))
    }

    static func loadValues(for slot: Int) -> ScreenPresetValues? {
        guard let s = ScreenPresetSlot(rawValue: clampSlot(slot)), hasSavedData(for: slot) else { return nil }
        guard let packed = UserDefaults.standard.array(forKey: screenPresetKey(s, "position")) as? [Float],
              packed.count == 3 else { return nil }
        let scale = persistedFloat(forKey: screenPresetKey(s, "scale"), default: 0)
        guard scale > 0 else { return nil }
        let curveKey = screenPresetKey(s, "curveMagnitude")
        let curveMagnitude: Float
        if UserDefaults.standard.object(forKey: curveKey) != nil {
            curveMagnitude = persistedFloat(forKey: curveKey, default: CurvatureTick.defaultTick.magnitude)
        } else {
            let legacy = UserDefaults.standard.integer(forKey: screenPresetKey(s, "curvaturePreset"))
            curveMagnitude = CurvedCurvatureMapping.migrateFromLegacyPreset(rawValue: legacy)
        }
        var anchorID: UUID? = nil
        if let uuidString = UserDefaults.standard.string(forKey: screenPresetKey(s, "worldAnchorID")) {
            anchorID = UUID(uuidString: uuidString)
        }
        return ScreenPresetValues(
            position: SIMD3<Float>(packed[0], packed[1], packed[2]),
            scale: scale,
            curveMagnitude: curveMagnitude,
            tiltAngle: persistedFloat(forKey: screenPresetKey(s, "tiltAngle"), default: 0),
            yawAngle: persistedFloat(forKey: screenPresetKey(s, "yawAngle"), default: 0),
            worldAnchorID: anchorID
        )
    }

    static func saveValues(_ values: ScreenPresetValues, for slot: Int) {
        guard let s = ScreenPresetSlot(rawValue: clampSlot(slot)) else { return }
        UserDefaults.standard.set([values.position.x, values.position.y, values.position.z], forKey: screenPresetKey(s, "position"))
        UserDefaults.standard.set(values.scale, forKey: screenPresetKey(s, "scale"))
        UserDefaults.standard.set(values.curveMagnitude, forKey: screenPresetKey(s, "curveMagnitude"))
        UserDefaults.standard.set(values.tiltAngle, forKey: screenPresetKey(s, "tiltAngle"))
        UserDefaults.standard.set(values.yawAngle, forKey: screenPresetKey(s, "yawAngle"))
        if let anchorID = values.worldAnchorID {
            UserDefaults.standard.set(anchorID.uuidString, forKey: screenPresetKey(s, "worldAnchorID"))
        } else {
            UserDefaults.standard.removeObject(forKey: screenPresetKey(s, "worldAnchorID"))
        }
        UserDefaults.standard.set(true, forKey: screenPresetKey(s, "saved"))
    }

    static func clearWorldAnchorID(for slot: Int) {
        guard let s = ScreenPresetSlot(rawValue: clampSlot(slot)) else { return }
        UserDefaults.standard.removeObject(forKey: screenPresetKey(s, "worldAnchorID"))
    }

    static func clampSlot(_ slot: Int) -> Int {
        min(3, max(1, slot))
    }

    static func sanitizeDisplayName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return String(trimmed.prefix(ScreenPresetSlot.maxDisplayNameLength))
    }

    private static func loadDisplayName(for slot: ScreenPresetSlot) -> String {
        let key = screenPresetKey(slot, "displayName")
        guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else {
            return slot.defaultDisplayName
        }
        return sanitizeDisplayName(stored, fallback: slot.defaultDisplayName)
    }

    private static func initializePresetsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: ScreenPresetMigration.initializedKey) else { return }
        UserDefaults.standard.set(true, forKey: ScreenPresetMigration.initializedKey)

        for slot in ScreenPresetSlot.allCases {
            UserDefaults.standard.set(slot.defaultDisplayName, forKey: screenPresetKey(slot, "displayName"))
        }

        let active = UserDefaults.standard.integer(forKey: activeSlotKey)
        if active < 1 || active > 3 {
            UserDefaults.standard.set(1, forKey: activeSlotKey)
        }
    }
}
