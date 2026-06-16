//
//  AudioHelpers.swift
//  Moonlight
//
//  Created by Max Thomas on 2/6/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import AVFoundation
import UIKit

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

    private static var sessionActivated = false
    private static var pinnedStreamSceneIdentifier: String?

    /// While streaming, spatial audio stays anchored to this scene (immersive space or stream window),
    /// even if the main menu window becomes frontmost.
    static func pinStreamAudioToScene(_ identifier: String?) {
        pinnedStreamSceneIdentifier = identifier
        if let identifier {
            print("AudioHelpers - Pinned stream audio to scene: \(identifier)")
        } else {
            print("AudioHelpers - Cleared stream audio scene pin")
        }
    }

    static func pinnedStreamSceneIdentifierForSurround() -> String? {
        pinnedStreamSceneIdentifier
    }

    #if os(visionOS)
    static func immersiveSpaceSceneIdentifier() -> String? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.session.role == .immersiveSpaceApplication {
                return windowScene.session.persistentIdentifier
            }
        }
        return nil
    }
    #else
    static func immersiveSpaceSceneIdentifier() -> String? { nil }
    #endif

    static func keyWindowSceneIdentifier() -> String? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.windows.contains(where: \.isKeyWindow) {
                return windowScene.session.persistentIdentifier
            }
        }
        return nil
    }

    @discardableResult
    static func captureAndPinStreamAudioScene(preferredIdentifier: String? = nil) -> String? {
        let identifier = preferredIdentifier
            ?? pinnedStreamSceneIdentifier
            ?? immersiveSpaceSceneIdentifier()
            ?? keyWindowSceneIdentifier()
        pinStreamAudioToScene(identifier)
        return identifier
    }

    private static func preferredSurroundSceneIdentifier() -> String? {
        pinnedStreamSceneIdentifier
            ?? immersiveSpaceSceneIdentifier()
            ?? keyWindowSceneIdentifier()
            ?? UIApplication.shared.connectedScenes.first?.session.persistentIdentifier
    }

    static func isStreamSceneForegroundActive(_ identifier: String) -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.session.persistentIdentifier == identifier else { continue }
            return windowScene.activationState == .foregroundActive
        }
        return false
    }

    private static func fixCategoryAndMic() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            if !sessionActivated {
                try audioSession.setActive(true)
                sessionActivated = true
            }
        }
        catch {
            print("Failed to set the audio session category configuration?")
        }
    }

    static func resetSessionState() {
        sessionActivated = false
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
    
    /// Ensure that the audio session is surround and anchored to the stream scene when pinned,
    /// otherwise the active window.
    static func fixAudioForSurroundForCurrentWindow(soundStageSize: SoundStageSize = .medium) {
        AudioHelpers.fixCategoryAndMic()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if let id = preferredSurroundSceneIdentifier() {
                print("AudioHelpers - Anchoring surround audio to scene \(id) with sound stage: \(soundStageSize.rawValue)")

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

    /// Prefer an explicit stream scene, then the pinned stream scene, then the active window.
    /// If the stream scene is not foreground-active yet (e.g. menu still dismissing), keep bypassed
    /// playback so Moonlight's SDL audio path stays alive until the scene is ready.
    static func fixAudioForSurroundForStream(
        soundStageSize: SoundStageSize = .medium,
        sceneIdentifier: String? = nil
    ) {
        let targetScene = sceneIdentifier ?? pinnedStreamSceneIdentifier

        if let targetScene {
            guard isStreamSceneForegroundActive(targetScene) else {
                print("AudioHelpers - Stream scene not foreground-active (\(targetScene)); keeping bypassed playback")
                fixAudioForDirectStereo()
                return
            }
            fixAudioForScene(identifier: targetScene, soundStageSize: soundStageSize)
        } else {
            fixAudioForSurroundForCurrentWindow(soundStageSize: soundStageSize)
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