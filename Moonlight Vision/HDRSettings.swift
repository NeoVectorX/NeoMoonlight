//
//  HDRSettings.swift
//  Moonlight Vision
//
//  Created by AI Assistant on 1/19/25. Updated May 2026 by NeoVector X.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import Combine

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

    // PQ-only exposure trim — scales HDR content luminance without affecting SDR.
    // Range 0.5–2.0, default 1.0 (neutral). Persisted separately to avoid conflicts with
    // the legacy luminance/gamma/peakBrightness keys from previous builds.
    @Published var pqExposure: Float {
        didSet { UserDefaults.standard.set(pqExposure, forKey: "hdrPqExposure") }
    }

    init() {
        self.brightness  = UserDefaults.standard.object(forKey: "hdrBrightness")  as? Float ?? 1.35
        self.contrast    = UserDefaults.standard.object(forKey: "hdrContrast")    as? Float ?? 1.15
        self.saturation  = UserDefaults.standard.object(forKey: "hdrSaturation")  as? Float ?? 1.4
        self.pqExposure  = UserDefaults.standard.object(forKey: "hdrPqExposure")  as? Float ?? 1.0
    }

    func save() {
        // Values auto-saved in each didSet.
    }

    func reset() {
        brightness  = 1.35
        contrast    = 1.15
        saturation  = 1.4
        pqExposure  = 1.0
    }
}
