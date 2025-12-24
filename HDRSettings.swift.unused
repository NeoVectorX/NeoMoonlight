//
//  HDRSettings.swift
//  Moonlight Vision
//
//  Created by AI Assistant on 1/19/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import Combine

class HDRSettings: ObservableObject {
    @Published var brightness: Float {
        didSet {
            UserDefaults.standard.set(brightness, forKey: "hdrBrightness")
        }
    }
    
    @Published var contrast: Float {
        didSet {
            UserDefaults.standard.set(contrast, forKey: "hdrContrast")
        }
    }
    
    @Published var saturation: Float {
        didSet {
            UserDefaults.standard.set(saturation, forKey: "hdrSaturation")
        }
    }
    
    @Published var luminance: Float {
        didSet {
            UserDefaults.standard.set(luminance, forKey: "hdrLuminance")
        }
    }
    
    @Published var gamma: Float {
        didSet {
            UserDefaults.standard.set(gamma, forKey: "hdrGamma")
        }
    }
    
    @Published var peakBrightness: Float {
        didSet {
            UserDefaults.standard.set(peakBrightness, forKey: "hdrPeakBrightness")
        }
    }
    
    init() {
        // Load from UserDefaults with default values
        self.brightness = UserDefaults.standard.object(forKey: "hdrBrightness") as? Float ?? 1.35
        self.contrast = UserDefaults.standard.object(forKey: "hdrContrast") as? Float ?? 1.15
        self.saturation = UserDefaults.standard.object(forKey: "hdrSaturation") as? Float ?? 1.4
        self.luminance = UserDefaults.standard.object(forKey: "hdrLuminance") as? Float ?? 300
        self.gamma = UserDefaults.standard.object(forKey: "hdrGamma") as? Float ?? 2.2
        self.peakBrightness = UserDefaults.standard.object(forKey: "hdrPeakBrightness") as? Float ?? 800
    }
    
    func save() {
        // Values are automatically saved in didSet
    }
    
    func reset() {
        brightness = 1.35
        contrast = 1.15
        saturation = 1.4
        luminance = 300
        gamma = 2.2
        peakBrightness = 800
    }
}