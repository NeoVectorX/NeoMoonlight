//
//  AudioHelpers.swift
//  Moonlight
//
//  Created by Max Thomas on 2/6/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import AVFoundation

enum SoundStageSize: String, Codable, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    var avAudioSessionSize: AVAudioSession.SoundStageSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }
    
    func next() -> SoundStageSize {
        let all = SoundStageSize.allCases
        let currentIndex = all.firstIndex(of: self) ?? 0
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }
}

class AudioHelpers {

    private static func fixCategoryAndMic() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setMode(.voiceChat)
            try audioSession.setPreferredInputNumberOfChannels(1)
        }
        catch {
            print("Failed to set the audio session mic/category configuration?")
        }
    }

    /// Ensure that the audio session is direct stereo
    /// Also ensures that the microphone uses voice chat noise cancellation.
    static func fixAudioForDirectStereo() {
        print("AudioHelpers - Fix for direct stereo")
        AudioHelpers.fixCategoryAndMic()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setIntendedSpatialExperience(.bypassed)
        } catch {
            print("Failed to set the audio session configuration?")
        }
    }
    
    /// Ensure that the audio session is surround and anchored to the active window
    /// Also ensures that the microphone uses voice chat noise cancellation.
    static func fixAudioForSurroundForCurrentWindow(soundStageSize: SoundStageSize = .medium) {
        AudioHelpers.fixCategoryAndMic()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if let id = UIApplication.shared.connectedScenes.first?.session.persistentIdentifier {
                print("AudioHelpers - Found current window \(id) with sound stage: \(soundStageSize.rawValue)")

                try audioSession.setPreferredOutputNumberOfChannels(audioSession.maximumOutputNumberOfChannels)
                try audioSession.setIntendedSpatialExperience(.headTracked(soundStageSize: soundStageSize.avAudioSessionSize, anchoringStrategy: .scene(identifier: id)))
            }
            else {
                print("AudioHelpers - Couldn't find current window?")
                fixAudioForDirectStereo()
            }
        } catch {
            print("Failed to set the audio session configuration?")
        }
    }
    
    static func fixAudioForSurroundForUIKitWindow(_ window: UIWindow, soundStageSize: SoundStageSize = .medium) {
        AudioHelpers.fixCategoryAndMic()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            print(window, window.windowScene?.session.persistentIdentifier)
            if let id = window.windowScene?.session.persistentIdentifier {
                print("AudioHelpers - Found UIKit window \(id) with sound stage: \(soundStageSize.rawValue)")
                
                try audioSession.setPreferredOutputNumberOfChannels(audioSession.maximumOutputNumberOfChannels)
                try audioSession.setIntendedSpatialExperience(.headTracked(soundStageSize: soundStageSize.avAudioSessionSize, anchoringStrategy: .scene(identifier: id)))
            }
            else {
                fixAudioForDirectStereo()
            }
        } catch {
            print("AudioHelpers - Couldn't find UIKit window?")
            print("Failed to set the audio session configuration?")
        }
    }
    
    /// Anchor audio to a specific scene by its identifier
    static func fixAudioForScene(identifier: String, soundStageSize: SoundStageSize = .medium) {
        AudioHelpers.fixCategoryAndMic()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            print("AudioHelpers - Anchoring audio to scene: \(identifier) with sound stage: \(soundStageSize.rawValue)")
            try audioSession.setPreferredOutputNumberOfChannels(audioSession.maximumOutputNumberOfChannels)
            try audioSession.setIntendedSpatialExperience(.headTracked(soundStageSize: soundStageSize.avAudioSessionSize, anchoringStrategy: .scene(identifier: identifier)))
        } catch {
            print("AudioHelpers - Failed to anchor to scene \(identifier): \(error)")
        }
    }
}