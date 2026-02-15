//
//  ObservableConnectionManager.swift
//  Moonlight
//
//  Created by tht7 on 29/12/2024.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//


import Foundation
import Combine
@MainActor
@objc class ObservableConnectionManager: NSObject, ObservableObject, ConnectionCallbacks {
    
    // Published properties for SwiftUI to observe
    @Published var connectionStatus: Int32 = 0
    @Published var currentStage: String = ""
    @Published var errorMessage: String?
    @Published var isHDRModeEnabled: Bool = false
    @Published var videoShown: Bool = false
    @Published var showAlert = false
    
    // Reference to ControllerSupport for rumble forwarding
    weak var controllerSupport: ControllerSupport?
    
    // Implement the protocol methods
    func connectionStarted() {
        print("Connection started")
    }
    
    func connectionTerminated(_ errorCode: Int32) {
        print("Connection terminated with error code: \(errorCode)")
        errorMessage = "Connection terminated with error code: \(errorCode)"
        showAlert = true

        // Post a separate notification so the ViewModel can trigger shouldCloseStream
        // for unexpected disconnects. We do NOT post RKStreamDidTeardown here because
        // that would set streamState to .idle before LiStopConnection() finishes.
        // The view's performCompleteTeardown will post RKStreamDidTeardown after
        // LiStopConnection() fully completes via stopStreamWithCompletion.
        print("[RKCallbacks] connectionTerminated - posting ConnectionLost for view cleanup")
        NotificationCenter.default.post(name: Notification.Name("ConnectionLost"), object: nil)
    }
    
    func stageStarting(_ stageName: UnsafePointer<CChar>!) {
        if let stage = stageName {
            currentStage = String(cString: stage)
            print("Stage starting: \(currentStage)")
        }
    }
    
    func stageComplete(_ stageName: UnsafePointer<CChar>!) {
        if let stage = stageName {
            currentStage = String(cString: stage)
            print("Stage complete: \(currentStage)")
        }
    }
    
    func stageFailed(_ stageName: UnsafePointer<CChar>!, withError errorCode: Int32, portTestFlags: Int32) {
        if let stage = stageName {
            let stageStr = String(cString: stage)
            print("Stage failed: \(stageStr), Error code: \(errorCode), Port test flags: \(portTestFlags)")
            errorMessage = "Stage \(stageStr) failed with error \(errorCode)"
            showAlert = true

            print("[RKCallbacks] Posting StreamStartFailed from stageFailed")
            NotificationCenter.default.post(name: Notification.Name("StreamStartFailed"), object: nil)
        }
    }
    
    func launchFailed(_ message: String!) {
        print("Launch failed: \(message ?? "Unknown error")")
        errorMessage = message
        showAlert = true

        print("[RKCallbacks] Posting StreamStartFailed from launchFailed")
        NotificationCenter.default.post(name: Notification.Name("StreamStartFailed"), object: nil)
    }
    
    func rumble(_ controllerNumber: UInt16, lowFreqMotor: UInt16, highFreqMotor: UInt16) {
        print("Rumble controller \(controllerNumber), LowFreq: \(lowFreqMotor), HighFreq: \(highFreqMotor)")
        
        // Forward rumble to ControllerSupport which will handle haptics
        controllerSupport?.rumble(controllerNumber, lowFreqMotor: lowFreqMotor, highFreqMotor: highFreqMotor)
    }
    
    func connectionStatusUpdate(_ status: Int32) {
        print("Connection status updated to: \(status)")
        connectionStatus = status
    }
    
    func setHdrMode(_ enabled: Bool) {
        print("HDR Mode set to: \(enabled)")
        isHDRModeEnabled = enabled
    }
    
    func rumbleTriggers(_ controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16) {
        print("Rumble triggers for controller \(controllerNumber): Left \(leftTrigger), Right \(rightTrigger)")
        
        // Forward trigger rumble to ControllerSupport
        controllerSupport?.rumbleTriggers(controllerNumber, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
    }
    
    func setMotionEventState(_ controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16) {
        print("Set motion event state: Controller \(controllerNumber), Motion type \(motionType), Report rate \(reportRateHz) Hz")
    }
    
    func setControllerLed(_ controllerNumber: UInt16, r: UInt8, g: UInt8, b: UInt8) {
        print("Set LED for controller \(controllerNumber): R \(r), G \(g), B \(b)")
    }
    
    func videoContentShown() {
        print("Video content shown")
        videoShown = true
        showAlert = false

        print("[RKCallbacks] Posting RKStreamFirstFrameShown")
        NotificationCenter.default.post(name: Notification.Name("RKStreamFirstFrameShown"), object: nil)
    }
}