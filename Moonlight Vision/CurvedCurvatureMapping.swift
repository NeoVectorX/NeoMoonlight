//
//  CurvedCurvatureMapping.swift
//  Moonlight Vision
//

import Foundation

enum CurvatureTick: CaseIterable, Comparable {
    case flat
    case r1800
    case r1600
    case r1400
    case r1200
    case r1000
    case r800
    case r600

    /// Mesh magnitude derived from radius (inverse-R interpolation between 1800R and 600R).
    var magnitude: Float {
        switch self {
        case .flat: return 0
        case .r1800: return Self.anchorMagnitude
        case .r1600: return Self.magnitudeForRadius(1600)
        case .r1400: return Self.magnitudeForRadius(1400)
        case .r1200: return Self.magnitudeForRadius(1200)
        case .r1000: return Self.magnitudeForRadius(1000)
        case .r800: return Self.magnitudeForRadius(800)
        case .r600: return Self.maxCurvatureMagnitude
        }
    }

    var label: String {
        switch self {
        case .flat: return "Flat"
        case .r1800: return "1800R"
        case .r1600: return "1600R"
        case .r1400: return "1400R"
        case .r1200: return "1200R"
        case .r1000: return "1000R"
        case .r800: return "800R"
        case .r600: return "600R"
        }
    }

    static func < (lhs: CurvatureTick, rhs: CurvatureTick) -> Bool {
        lhs.magnitude < rhs.magnitude
    }

    static var defaultTick: CurvatureTick { .r1800 }

    static var minMagnitude: Float { flat.magnitude }
    static var maxMagnitude: Float { r600.magnitude }

    private static let anchorMagnitude: Float = 0.4
    private static let maxCurvatureMagnitude: Float = 1.65

    private static func magnitudeForRadius(_ radius: Int) -> Float {
        let inv1800 = 1.0 / 1800.0
        let inv600 = 1.0 / 600.0
        let invR = 1.0 / Double(radius)
        let t = (invR - inv1800) / (inv600 - inv1800)
        let span = maxCurvatureMagnitude - anchorMagnitude
        return anchorMagnitude + Float(t) * span
    }
}

enum CurvedCurvatureMapping {
    private static let migrationKey = "curved.curveMagnitude.v1"
    private static let magnitudeKey = "curved.curveMagnitude"
    private static let legacyPresetKey = "curved.curvaturePreset"

    static let meshGenMinInterval: TimeInterval = 0.06

    static func runMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)

        if UserDefaults.standard.object(forKey: magnitudeKey) == nil {
            let legacyRaw = UserDefaults.standard.integer(forKey: legacyPresetKey)
            let migrated = migrateFromLegacyPreset(rawValue: legacyRaw)
            UserDefaults.standard.set(migrated, forKey: magnitudeKey)
        }
    }

    static func migrateFromLegacyPreset(rawValue: Int) -> Float {
        switch rawValue {
        case 0: return CurvatureTick.flat.magnitude
        case 1: return CurvatureTick.r1800.magnitude
        case 2: return CurvatureTick.r1000.magnitude
        case 3: return CurvatureTick.r800.magnitude
        case 4: return CurvatureTick.r600.magnitude
        default: return CurvatureTick.defaultTick.magnitude
        }
    }

    static func clampMagnitude(_ value: Float) -> Float {
        min(max(value, CurvatureTick.minMagnitude), CurvatureTick.maxMagnitude)
    }

    static func magnitudeToUnit(_ magnitude: Float) -> Float {
        let clamped = clampMagnitude(magnitude)
        let span = CurvatureTick.maxMagnitude - CurvatureTick.minMagnitude
        guard span > 0 else { return 0 }
        return (clamped - CurvatureTick.minMagnitude) / span
    }

    static func unitToMagnitude(_ unit: Float) -> Float {
        let clampedUnit = min(max(unit, 0), 1)
        let span = CurvatureTick.maxMagnitude - CurvatureTick.minMagnitude
        return clampMagnitude(CurvatureTick.minMagnitude + clampedUnit * span)
    }

    static func nearestTick(to magnitude: Float) -> CurvatureTick {
        let clamped = clampMagnitude(magnitude)
        return CurvatureTick.allCases.min(by: {
            abs($0.magnitude - clamped) < abs($1.magnitude - clamped)
        }) ?? .defaultTick
    }

    static func snappedMagnitude(_ magnitude: Float) -> Float {
        nearestTick(to: magnitude).magnitude
    }

    static func label(for magnitude: Float) -> String {
        nearestTick(to: magnitude).label
    }

    // Equal-step slider mapping (tick index), independent of mesh magnitude spacing.
    static func tickToSliderUnit(_ tick: CurvatureTick) -> Float {
        let ticks = CurvatureTick.allCases
        guard ticks.count > 1,
              let index = ticks.firstIndex(of: tick) else { return 0 }
        return Float(index) / Float(ticks.count - 1)
    }

    static func magnitudeToSliderUnit(_ magnitude: Float) -> Float {
        tickToSliderUnit(nearestTick(to: magnitude))
    }

    static func sliderUnitToMagnitude(_ unit: Float) -> Float {
        let ticks = CurvatureTick.allCases
        guard ticks.count > 1 else { return ticks.first?.magnitude ?? 0 }
        let clampedUnit = min(max(unit, 0), 1)
        let index = Int(round(clampedUnit * Float(ticks.count - 1)))
        return ticks[min(max(index, 0), ticks.count - 1)].magnitude
    }

    /// Smooth mesh magnitude while dragging — interpolates between adjacent tick values.
    static func sliderUnitToContinuousMagnitude(_ unit: Float) -> Float {
        let ticks = CurvatureTick.allCases
        guard ticks.count > 1 else { return ticks.first?.magnitude ?? 0 }
        let clampedUnit = min(max(unit, 0), 1)
        let scaled = clampedUnit * Float(ticks.count - 1)
        let lowerIndex = Int(floor(scaled))
        let upperIndex = min(lowerIndex + 1, ticks.count - 1)
        let fraction = scaled - Float(lowerIndex)
        let lowerMag = ticks[lowerIndex].magnitude
        let upperMag = ticks[upperIndex].magnitude
        return lowerMag + (upperMag - lowerMag) * fraction
    }

    static func nearestTick(toSliderUnit unit: Float) -> CurvatureTick {
        nearestTick(to: sliderUnitToMagnitude(unit))
    }
}
