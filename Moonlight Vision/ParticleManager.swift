//
//  ParticleManager.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 
//
//

import SwiftUI
import RealityKit
import UIKit

enum StarDistancePreset: Int, CaseIterable {
    case close = 0
    case medium = 1
    case far = 2
    
    var distances: (near: Float, mid: Float, distant: Float) {
        switch self {
        case .close:   return (7.0, 11.0, 15.0)
        case .medium:  return (10.0, 15.0, 20.0)
        case .far:     return (14.0, 19.0, 25.0)
        }
    }
    
    var displayName: String {
        switch self {
        case .close:  return "Close"
        case .medium: return "Medium"
        case .far:    return "Far"
        }
    }
    
    func next() -> StarDistancePreset {
        let allCases = Self.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        return allCases[nextIndex]
    }
}

@MainActor
class ParticleManager {
    public let rootEntity = Entity()
    private var distantStarsEmitter: Entity?
    private var midStarsEmitter: Entity?
    private var nearStarsEmitter: Entity?
    
    private var currentPreset: StarDistancePreset = .close
   
    // This absorbs the jitter caused by UI clicks/fades.
    private var smoothedBrightness: Float = 0.0
    
    init(preset: StarDistancePreset = .close) {
        self.currentPreset = preset
        setupEmitters()
    }
    
    // NOTE: resetDelta removed - smoothing handles "waking up" naturally.
    
    // Call this from your AmbientLightEngine update block
    func update(color: UIColor, brightness: Float) {
        guard let distantEmitter = distantStarsEmitter,
              let midEmitter = midStarsEmitter,
              let nearEmitter = nearStarsEmitter else { return }
        
      
        // This filters out high-frequency noise (UI glitches) but keeps low-frequency signal (Movie explosions).
        let oldSmoothed = smoothedBrightness
        
        // 0.1 = Very smooth/dreamy. 0.3 = Snappy. 0.15 is the sweet spot for "Nebula".
        let smoothingFactor: Float = 0.15
        smoothedBrightness += (brightness - smoothedBrightness) * smoothingFactor
        
        // 2. Calculate Delta from the SMOOTHED values
        // This value will now be silky smooth, even if the UI stutters.
        let delta = max(0, smoothedBrightness - oldSmoothed)
        
        // 3. Base Reactivity (Color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        // Keep saturation moderate so they look like stars, not LEDs
        let particleColor = UIColor(hue: h, saturation: s, brightness: 1.0, alpha: 1.0)
        
        // 4. Update Physics
        let baseSpeed: Float = 0.05
        
        // Reaction multiplier needs to be higher now because 'smoothed' delta is smaller/gentler
        let reactionMultiplier: Float = 4.0
        
        let targetSpeed = baseSpeed + (delta * reactionMultiplier)
        
        // Birth Rate:
        // Use the smoothed delta. If it's a tiny jitter (UI click), delta is ~0.001 -> No change.
        // If it's a movie explosion, delta is ~0.05 -> Spawn extra stars.
        let spawnBonus: Float = (delta > 0.005) ? (delta * 4000) : 0
        
        // 5. Update DISTANT stars (far layer - 1.5cm)
        var distantParticles = distantEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        
        distantParticles.mainEmitter.color = .constant(.single(particleColor))
        distantParticles.mainEmitter.birthRate = 2000 + (spawnBonus * 0.5) // Half bonus for distant
        distantParticles.speed = targetSpeed
        
        let distantPulseSize: Float = 0.015 + (delta * 0.05)
        distantParticles.mainEmitter.size = distantPulseSize
        
        distantEmitter.components.set(distantParticles)
        
        // 6. Update MID stars (middle layer - 1.4cm)
        var midParticles = midEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        
        midParticles.mainEmitter.color = .constant(.single(particleColor))
        midParticles.mainEmitter.birthRate = 500 + (spawnBonus * 0.125) // Quarter bonus for mid
        midParticles.speed = targetSpeed
        
        let midPulseSize: Float = 0.014 + (delta * 0.05)
        midParticles.mainEmitter.size = midPulseSize
        
        midEmitter.components.set(midParticles)
        
        // 7. Update NEAR stars (close layer - 1.8cm)
        var nearParticles = nearEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        
        nearParticles.mainEmitter.color = .constant(.single(particleColor))
        nearParticles.mainEmitter.birthRate = 300 + (spawnBonus * 0.075) // Smaller bonus for near
        nearParticles.speed = targetSpeed
        
        let nearPulseSize: Float = 0.018 + (delta * 0.05)
        nearParticles.mainEmitter.size = nearPulseSize
        
        nearEmitter.components.set(nearParticles)
    }
    
    func setEnabled(_ enabled: Bool) {
        rootEntity.isEnabled = enabled
        // No need to reset math; the lerp will catch up smoothly automatically.
    }
    
    func updateDistancePreset(_ preset: StarDistancePreset) {
        currentPreset = preset
        
        // Update existing emitters with new distances
        guard let distantEmitter = distantStarsEmitter,
              let midEmitter = midStarsEmitter,
              let nearEmitter = nearStarsEmitter else { return }
        
        let distances = preset.distances
        
        // Update distant layer
        var distantParticles = distantEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        distantParticles.emitterShapeSize = [distances.distant, distances.distant, distances.distant]
        distantEmitter.components.set(distantParticles)
        
        // Update mid layer
        var midParticles = midEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        midParticles.emitterShapeSize = [distances.mid, distances.mid, distances.mid]
        midEmitter.components.set(midParticles)
        
        // Update near layer
        var nearParticles = nearEmitter.components[ParticleEmitterComponent.self] ?? ParticleEmitterComponent()
        nearParticles.emitterShapeSize = [distances.near, distances.near, distances.near]
        nearEmitter.components.set(nearParticles)
    }
    
    private func setupEmitters() {
        // GENERATE TEXTURE: A sharp, glowing dot
        guard let texture = generateStarTexture() else { return }
        
        let distances = currentPreset.distances
        
        // LAYER 1: DISTANT STARS (dense, smallest)
        let distantEntity = Entity()
        var distantParticles = ParticleEmitterComponent()
        
        distantParticles.emitterShape = .sphere
        distantParticles.emitterShapeSize = [distances.distant, distances.distant, distances.distant] // Far layer
        
        distantParticles.mainEmitter.birthRate = 2000      // Dense starfield
        distantParticles.mainEmitter.size = 0.015          // 1.5 cm
        distantParticles.mainEmitter.lifeSpan = 15.0
        distantParticles.mainEmitter.sizeVariation = 0.005
        
        distantParticles.mainEmitter.acceleration = [0, 0, 0]
        distantParticles.mainEmitter.dampingFactor = 5.0
        distantParticles.mainEmitter.spreadingAngle = 0.0
        
        distantParticles.mainEmitter.image = texture
        distantParticles.mainEmitter.blendMode = .additive
        
        distantParticles.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.1)),
            end: .single(.white.withAlphaComponent(0))
        )
        
        distantEntity.components.set(distantParticles)
        distantEntity.position = SIMD3<Float>(0, 1.5, 0)
        
        distantStarsEmitter = distantEntity
        rootEntity.addChild(distantEntity)
        
        // LAYER 2: MID STARS (medium density, medium size)
        let midEntity = Entity()
        var midParticles = ParticleEmitterComponent()
        
        midParticles.emitterShape = .sphere
        midParticles.emitterShapeSize = [distances.mid, distances.mid, distances.mid] // Middle layer
        
        midParticles.mainEmitter.birthRate = 500           // Medium density
        midParticles.mainEmitter.size = 0.014             // 1.4 cm
        midParticles.mainEmitter.lifeSpan = 15.0
        midParticles.mainEmitter.sizeVariation = 0.006
        
        midParticles.mainEmitter.acceleration = [0, 0, 0]
        midParticles.mainEmitter.dampingFactor = 5.0
        midParticles.mainEmitter.spreadingAngle = 0.0
        
        midParticles.mainEmitter.image = texture
        midParticles.mainEmitter.blendMode = .additive
        
        midParticles.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.1)),
            end: .single(.white.withAlphaComponent(0))
        )
        
        midEntity.components.set(midParticles)
        midEntity.position = SIMD3<Float>(0, 1.5, 0)
        
        midStarsEmitter = midEntity
        rootEntity.addChild(midEntity)
        
        // LAYER 3: NEAR STARS (sparse, largest)
        let nearEntity = Entity()
        var nearParticles = ParticleEmitterComponent()
        
        nearParticles.emitterShape = .sphere
        nearParticles.emitterShapeSize = [distances.near, distances.near, distances.near] // Closest layer for parallax
        
        nearParticles.mainEmitter.birthRate = 300         // Sparse (creates depth)
        nearParticles.mainEmitter.size = 0.018           // 1.8 cm (largest)
        nearParticles.mainEmitter.lifeSpan = 15.0
        nearParticles.mainEmitter.sizeVariation = 0.007
        
        nearParticles.mainEmitter.acceleration = [0, 0, 0]
        nearParticles.mainEmitter.dampingFactor = 5.0
        nearParticles.mainEmitter.spreadingAngle = 0.0
        
        nearParticles.mainEmitter.image = texture
        nearParticles.mainEmitter.blendMode = .additive
        
        nearParticles.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.1)),
            end: .single(.white.withAlphaComponent(0))
        )
        
        nearEntity.components.set(nearParticles)
        nearEntity.position = SIMD3<Float>(0, 1.5, 0)
        
        nearStarsEmitter = nearEntity
        rootEntity.addChild(nearEntity)
    }
    
    // Generates a sharper "Hot Core" glow texture for stars
    private func generateStarTexture() -> TextureResource? {
        let size = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let context = ctx.cgContext
            // White center -> Transparent edge
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            
            // Sharper falloff than smoke (starts fading at 0.2 instead of 0.0)
            let locations: [CGFloat] = [0.1, 1.0] 
            
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            
            let center = CGPoint(x: size/2, y: size/2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size/2), options: .drawsAfterEndLocation)
        }
        
        return try? TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
    }
}
