//
//  Reactive1ChromosphereReach.swift
//  Neo Moonlight
//
//  
//

import Foundation

enum Reactive1ChromosphereReach {
    /// Stored index 0...(scales.count-1)
    static let userDefaultsKey = "ambient.reactive1.reach.variant"

    /// Isotropic halo scale (`DrawableVideoDecoder.chromaHaloScale` / Chromosphere mesh). Index 0 matches historical default `1.55`.
    /// If `haloScales.last` changes, update `Shaders.metal` `kChromaHaloScaleSpan` to `(last − 1.55)` so reach-tier blur ramps correctly.
    static let haloScales: [Float] = [1.55, 2.08, 2.72, 3.48]

    static var tierCount: Int { haloScales.count }

    static func haloScale(forIndex index: Int) -> Float {
        let i = (0..<haloScales.count).clamp(index)
        return haloScales[i]
    }

    static func clampedSavedIndex() -> Int {
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        guard raw >= 0, raw < haloScales.count else { return 0 }
        return raw
    }

    static func saveIndex(_ index: Int) {
        UserDefaults.standard.set((0..<haloScales.count).clamp(index), forKey: userDefaultsKey)
    }

    static func advanceWrappedAndSave() {
        let next = (clampedSavedIndex() + 1) % haloScales.count
        saveIndex(next)
    }

    /// Short labels for the inline preset overlay while cycling.
    static func overlayDisplayName(forIndex index: Int) -> String {
        switch (0..<haloScales.count).clamp(index) {
        case 0: return "Standard"
        case 1: return "Wide"
        case 2: return "Expanded"
        default: return "Maximum"
        }
    }
}

private extension Range<Int> {
    func clamp(_ value: Int) -> Int {
        Swift.min(upperBound - 1, Swift.max(lowerBound, value))
    }
}
