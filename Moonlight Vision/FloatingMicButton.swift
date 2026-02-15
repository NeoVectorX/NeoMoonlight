//
//  FloatingMicButton.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//

import SwiftUI

struct FloatingMicButton: View {
    @StateObject private var micManager = RemoteMicManager()
    
    var body: some View {
        Button(action: {
            micManager.toggleMute()
        }) {
            micIcon
        }
        .buttonStyle(.plain)
        .padding(20)
    }
    
    @ViewBuilder
    private var micIcon: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .fill(iconGradient)
                )
                .shadow(
                    color: iconShadowColor,
                    radius: micManager.isMuted ? 5 : 8,
                    x: 0,
                    y: 3
                )
            
            Image(systemName: micManager.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    
    // MARK: - Computed Properties
    
    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: micManager.isMuted
                ? [.red.opacity(0.3), .red.opacity(0.2)]
                : [.blue.opacity(0.3), .blue.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var iconShadowColor: Color {
        micManager.isMuted ? .red.opacity(0.4) : .blue.opacity(0.4)
    }
}

#Preview {
    FloatingMicButton()
        .frame(width: 400, height: 400)
}
