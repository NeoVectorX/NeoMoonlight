//
//  HDRSettings.swift
//  Moonlight Vision
//
//  Created by AI Assistant on 1/19/25. Updated May 2026 by NeoVector X.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import Combine

private enum HDRSettingsMigration {
    /// One-shot: restores pre-overhaul trims for installs that persisted contrast/sat both 1.0.
    static let legacyTrimsKey = "hdrTrimsRestoredLegacy_v1"
}

class HDRSettings: ObservableObject {
    @Published var brightness: Float {
        didSet { UserDefaults.standard.set(brightness, forKey: "hdrBrightness") }
    }

    @Published var contrast: Float {
        didSet { UserDefaults.standard.set(contrast, forKey: "hdrContrast") }
    }

    @Published var saturation: Float {
        didSet { UserDefaults.standard.set(saturation, forKey: "hdrSaturation") }
    }

    // Exposure trim — applied after brightness in Metal (PQ + SDR paths for consistent panel behavior).
    @Published var pqExposure: Float {
        didSet { UserDefaults.standard.set(pqExposure, forKey: "hdrPqExposure") }
    }

    /// Minimal client grading: PQ + gamut + one tone map (no panel boost/sat/con/radial in shader).
    @Published var referenceHDR: Bool {
        didSet { UserDefaults.standard.set(referenceHDR, forKey: "hdrReferenceMode") }
    }

    init() {
        // Match pre-overhaul defaults (NeoMoonlight Vision): strong SDR/headset match without flat “clinical” mids.
        let defaultsBrightness: Float = 1.35
        let defaultsContrast: Float = 1.15
        let defaultsSaturation: Float = 1.40

        var contrastIn = UserDefaults.standard.object(forKey: "hdrContrast") as? Float ?? defaultsContrast
        var saturationIn = UserDefaults.standard.object(forKey: "hdrSaturation") as? Float ?? defaultsSaturation

        let alreadyMigrated = UserDefaults.standard.bool(forKey: HDRSettingsMigration.legacyTrimsKey)
        if !alreadyMigrated {
            UserDefaults.standard.set(true, forKey: HDRSettingsMigration.legacyTrimsKey)
            // Brief “neutral 1/1/…” window left dull trims in UserDefaults; restore historical punch.
            if UserDefaults.standard.object(forKey: "hdrContrast") as? Float == 1.0
                && UserDefaults.standard.object(forKey: "hdrSaturation") as? Float == 1.0 {
                contrastIn = defaultsContrast
                saturationIn = defaultsSaturation
                UserDefaults.standard.set(contrastIn, forKey: "hdrContrast")
                UserDefaults.standard.set(saturationIn, forKey: "hdrSaturation")
            }
        }

        self.brightness = UserDefaults.standard.object(forKey: "hdrBrightness") as? Float ?? defaultsBrightness
        self.contrast = contrastIn
        self.saturation = saturationIn
        self.pqExposure = UserDefaults.standard.object(forKey: "hdrPqExposure") as? Float ?? 1.0
        self.referenceHDR = UserDefaults.standard.bool(forKey: "hdrReferenceMode")
    }

    func save() {
        // Values auto-saved in each didSet.
    }

    func reset() {
        brightness  = 1.35
        contrast    = 1.15
        saturation  = 1.40
        pqExposure  = 1.0
        // Intentionally leave referenceHDR unchanged — user toggles a pipeline mode, not a trim.
    }
}
