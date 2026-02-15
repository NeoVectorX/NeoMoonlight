//

import Foundation
import Observation
import AppIntents

#if os(visionOS)
@Observable
#endif
@objc
@MainActor
public class TemporarySettings: NSObject {
    @objc public var bitrate: Int32
    @objc public var framerate: Int32
    @objc public var height: Int32
    @objc public var width: Int32
    @objc public var audioConfig: Int32
    @objc public var onscreenControls: OnScreenControlsLevel
    @objc public var uniqueId: String
    @objc public var preferredCodec = PreferredCodec.auto
    @objc public var renderer: Renderer = .classicMetal

    @objc public var realitykitRendererAnimateOpening: Bool = false
    @objc public var realitykitRendererCurvature: Float = 0.0

    @objc public var useFramePacing = false
    @objc public var multiController = false
    @objc public var swapABXYButtons = false
    @objc public var playAudioOnPC = false
    @objc public var optimizeGames = false
    @objc public var enableHdr = false
    @objc public var btMouseSupport = false
    @objc public var absoluteTouchMode = false
    @objc public var curvedDefaultControlMode = 2  // 0: Screen Adjust, 1: Controller, 2: Gaze (default)
    @objc public var curvedGazeUseTouchMode = false  // false: Eye tracking (gaze), true: Hand drag (touch/trackpad)
    @objc public var gazeCursorOffsetX: Int = 0  // -15 to +15 pixels horizontal calibration
    @objc public var gazeCursorOffsetY: Int = 0  // -15 to +15 pixels vertical calibration
    @objc public var statsOverlay = false
    @objc public var dimPassthrough = true
    @objc public var hideSystemCursor = false
    @objc public var showMicButton = false
    @objc public var hideHandsIn360Environment = false

    // --- HDR / Color Settings ---
    @objc public var brightness: Float = 2.2
    @objc public var gamma: Float = 1.0
    @objc public var saturation: Float = 1.0

    @objc public var uikitPreset: Int32 = 0

    @objc public var parent: MoonlightSettings?

    override public init() {
        self.bitrate = 50000
        self.framerate = 0
        self.height = 0
        self.width = 0
        self.audioConfig = 0
        self.uniqueId = ""
        self.onscreenControls = OnScreenControlsLevel.off
        self.renderer = .classicMetal
        self.realitykitRendererAnimateOpening = false
        self.realitykitRendererCurvature = 0.0
        self.dimPassthrough = false
        self.hideSystemCursor = false
        self.showMicButton = false
        self.hideHandsIn360Environment = false
        
        // HDR Defaults
        self.brightness = 2.2
        self.gamma = 1.0
        self.saturation = 1.0
        super.init()
    }

    @objc public init(fromSettings settings: MoonlightSettings) {
        #if TARGET_OS_TV
        let settingsBundle = NSBundle.main.path(forResource: "Settings", ofType: "bundle")
        let settingsData = NSDictionary(contentsOf: settingsBundle)
        // TODO: Finish the tvos part
        #else

        self.bitrate = settings.bitrate?.int32Value ?? 0
        self.framerate = settings.framerate?.int32Value ?? 0
        self.height = settings.height?.int32Value ?? 0
        self.width = settings.width?.int32Value ?? 0
        self.audioConfig = settings.audioConfig?.int32Value ?? 0
        self.preferredCodec = PreferredCodec(rawValue: Int(settings.preferredCodec)) ?? PreferredCodec.auto
        self.onscreenControls = OnScreenControlsLevel(rawValue: settings.onscreenControls?.intValue ?? 0) ?? OnScreenControlsLevel.off
        
        if let ren = settings.renderer?.uint8Value {
            let rawValue = UInt8(ren)
            // Old values: classic = 0, classicMetal = 1
            if rawValue == 0 || rawValue == 1 {
                self.renderer = .classicMetal
            } else {
                self.renderer = Renderer(rawValue: rawValue) ?? .classicMetal
            }
        } else {
            self.renderer = .classicMetal
        }
        
        self.uniqueId = settings.uniqueId ?? ""

        self.useFramePacing = settings.useFramePacing
        self.multiController = settings.multiController
        self.swapABXYButtons = settings.swapABXYButtons
        self.playAudioOnPC = settings.playAudioOnPC
        self.optimizeGames = settings.optimizeGames
        self.enableHdr = settings.enableHdr
        self.btMouseSupport = settings.btMouseSupport
        self.absoluteTouchMode = settings.absoluteTouchMode
        self.statsOverlay = settings.statsOverlay

        self.realitykitRendererAnimateOpening = settings.realitykitRendererAnimateOpening == 1
        self.realitykitRendererCurvature = settings.realitykitRendererCurvature?.floatValue ?? 0
        self.dimPassthrough = settings.dimPassthrough?.boolValue ?? false
        self.hideSystemCursor = settings.hideSystemCursor?.boolValue ?? false
        // TODO: Uncomment after adding showMicButton to Core Data model
        // self.showMicButton = settings.showMicButton?.boolValue ?? false
        self.showMicButton = false
        self.hideHandsIn360Environment = settings.hideHandsIn360Environment?.boolValue ?? false
        
        // HDR / COLOR DEFAULTS (not stored in database, local only)
        self.brightness = 2.2
        self.gamma = 1.0
        self.saturation = 1.0
        #endif

        super.init()
    }

    @objc public func save() {
        // save settings to parent
        let dataManager = DataManager()
        dataManager.saveSettings(withBitrate: Int(bitrate), framerate: Int(framerate), height: Int(height), width: Int(width), audioConfig: Int(audioConfig), onscreenControls: Int(onscreenControls.rawValue), optimizeGames: optimizeGames, multiController: multiController, swapABXYButtons: swapABXYButtons, audioOnPC: playAudioOnPC, preferredCodec: UInt32(preferredCodec.rawValue), renderer: renderer.rawValue, useFramePacing: useFramePacing, enableHdr: enableHdr, btMouseSupport: btMouseSupport, absoluteTouchMode: absoluteTouchMode, statsOverlay: statsOverlay, realitykitRendererAnimateOpening: realitykitRendererAnimateOpening, realitykitRendererCurvature: NSNumber(value: realitykitRendererCurvature), dimPassthrough: dimPassthrough, hideSystemCursor: hideSystemCursor, showMicButton: showMicButton, hideHandsIn360Environment: hideHandsIn360Environment)
    }
}

@objc public enum PreferredCodec: Int {
    case auto
    case h264
    case hevc
    case av1
}

@objc public enum Renderer: UInt8, Codable, Sendable, AppEnum, CaseIterable {
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
            TypeDisplayRepresentation(
                stringLiteral: "Renderer"
            )
        }
    
    public static var caseDisplayRepresentations: [Renderer : DisplayRepresentation] = [
        .classicMetal: .init(stringLiteral: "Flat Display"),
        .curvedDisplay: .init(stringLiteral: "Curved Display"),
    ]
    
    case classicMetal = 0
    case curvedDisplay = 2

    var windowId: String {
        switch self {
        case .classicMetal: return "flatDisplayWindow"
        case .curvedDisplay: return "curvedDisplayImmersiveSpace"
        }
    }
    
    var description: String {
        switch self {
        case .classicMetal: return "Flat Display"
        case .curvedDisplay: return "Curved Display"
        }
    }
}