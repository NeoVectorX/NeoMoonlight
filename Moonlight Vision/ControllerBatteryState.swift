//
//  ControllerBatteryState.swift
//  Moonlight Vision
//
//  Created by NeoVectorX
//

import Foundation
import Combine
import GameController

@objc class ControllerBatteryState: NSObject, ObservableObject {
    @objc static let shared = ControllerBatteryState()
    
    @Published var batteryLevel: Int = 0  // 0-100
    @Published var batteryState: BatteryState = .unknown
    @Published var hasController: Bool = false
    
    /// Check for existing connected controllers and update battery state (primary controller only)
    func refreshBatteryState() {
        // Use GCController.current for the active controller, or fall back to first with playerIndex 0
        let controller: GCController?
        if let current = GCController.current {
            controller = current
        } else {
            // Fall back to first controller with playerIndex .index1 (player 1) or unset
            controller = GCController.controllers().first(where: { 
                $0.playerIndex == .index1 || $0.playerIndex == .indexUnset 
            }) ?? GCController.controllers().first
        }
        
        guard let controller = controller, let battery = controller.battery else {
            return
        }
        
        let level = Int(battery.batteryLevel * 100)
        let state: UInt8
        switch battery.batteryState {
        case .full:
            state = 5 // LI_BATTERY_STATE_FULL
        case .charging:
            state = 3 // LI_BATTERY_STATE_CHARGING
        case .discharging:
            state = 2 // LI_BATTERY_STATE_DISCHARGING
        default:
            state = 0 // LI_BATTERY_STATE_UNKNOWN
        }
        
        updateBattery(level: level, state: state, hasController: true)
    }
    
    enum BatteryState {
        case unknown
        case discharging
        case charging
        case full
        
        var isCharging: Bool {
            return self == .charging
        }
    }
    
    private override init() {
        super.init()
    }
    
    @objc func updateBattery(level: Int, state: UInt8, hasController: Bool) {
        print("[Battery-Swift] updateBattery called: level=\(level), state=\(state), hasController=\(hasController), isMainThread=\(Thread.isMainThread)")
        
        // Ensure we're on main thread for @Published updates
        if Thread.isMainThread {
            self.batteryLevel = level
            self.hasController = hasController
            
            switch state {
            case 5: // LI_BATTERY_STATE_FULL
                self.batteryState = .full
            case 3: // LI_BATTERY_STATE_CHARGING
                self.batteryState = .charging
            case 2: // LI_BATTERY_STATE_DISCHARGING
                self.batteryState = .discharging
            default:
                self.batteryState = .unknown
            }
            print("[Battery-Swift] State updated: level=\(self.batteryLevel), hasController=\(self.hasController), batteryState=\(self.batteryState)")
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateBattery(level: level, state: state, hasController: hasController)
            }
        }
    }
}
