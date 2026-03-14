//
//  BatteryIndicatorView.swift
//  Moonlight Vision
//
//  Created by NeoVectorX
//

import SwiftUI

struct BatteryIndicatorView: View {
    @ObservedObject var batteryState = ControllerBatteryState.shared
    @Binding var controlsHighlighted: Bool
    @Binding var hideControls: Bool
    var startHighlightTimer: () -> Void
    var startHideTimer: () -> Void
    
    @State private var showPercentage = false
    @State private var hideTimer: Timer?
    
    var body: some View {
        if batteryState.hasController {
            Button {
                if !controlsHighlighted && hideControls {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hideControls = false
                        controlsHighlighted = true
                    }
                    startHighlightTimer()
                    return
                }
                controlsHighlighted = false
                hideControls = false
                
                showPercentage.toggle()
                
                if showPercentage {
                    hideTimer?.invalidate()
                    hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            showPercentage = false
                        }
                    }
                } else {
                    hideTimer?.invalidate()
                }
                
                startHideTimer()
            } label: {
                Label {
                    Text("Battery")
                } icon: {
                    ZStack {
                        if showPercentage {
                            Text("\(batteryState.batteryLevel)%")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .transition(.opacity)
                        } else {
                            batteryIcon
                                .font(.system(size: 24.07))
                                .transition(.opacity)
                        }
                    }
                }
                .font(.system(size: 24.07))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(width: 50, height: 50)
            }
            .labelStyle(.iconOnly)
            .animation(.easeInOut(duration: 0.15), value: showPercentage)
        } else {
            EmptyView()
                .onAppear {
                    batteryState.refreshBatteryState()
                }
        }
    }
    
    private var batteryIcon: some View {
        ZStack {
            Image(systemName: batterySymbolName)
            
            if batteryState.batteryState.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
            }
        }
    }
    
    private var batterySymbolName: String {
        if batteryState.batteryState == .full {
            return "battery.100"
        }
        
        let level = batteryState.batteryLevel
        if level >= 75 {
            return "battery.100"
        } else if level >= 50 {
            return "battery.75"
        } else if level >= 25 {
            return "battery.50"
        } else if level >= 10 {
            return "battery.25"
        } else {
            return "battery.0"
        }
    }
}
