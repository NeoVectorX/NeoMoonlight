//
//  StreamControls.swift
//  Moonlight
//
//  Created by tht7 on 24/01/2025.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct StreamControls<Additions: View>: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow // <-- ADDED
    
    let horizontal: Bool
    @Binding var streamConfig: StreamConfiguration
    let closeAction: () -> Void // <-- ADDED: The new action parameter
    
    @State private var spatialAudioMode: Bool = true // true = spatial (from screen), false = direct (from ears)
    @State private var volumeBeforeMute: Float = 127

    @ViewBuilder var additions: () -> Additions

    var body: some View {
        Group {
            if (horizontal) {
                HStack(alignment: .firstTextBaseline) { controls }
            } else {
                VStack(alignment: .leading) { controls }
            }
        }
        .onChange(of: viewModel.vol) { newVal, _ in
            setVolume(Int32(newVal))
        }
        .labelStyle(.iconOnly)
        .padding()
        .hoverEffect { effect, isActive, _ in
            effect.opacity(isActive ? 1 : 0.3)
        }
    }

    var controls: some View {
        Group {
            // --- START ADDITION ---
            Button("Home", systemImage: "house.fill") {
               // openWindow(id: "mainView")
                closeAction() // Call the provided close action
            }
            // --- END ADDITION ---
            
            Button(spatialAudioMode ? "Spatial Audio" : "Direct Audio", 
                   systemImage: spatialAudioMode ? "person.spatialaudio.fill" : "headphones") {
                spatialAudioMode.toggle()
                if spatialAudioMode {
                    // Switch to spatial audio (sound from screen)
                    AudioHelpers.fixAudioForSurroundForCurrentWindow()
                } else {
                    // Switch to direct audio (sound from ears)
                    AudioHelpers.fixAudioForDirectStereo()
                }
            }
            
            HStack {
                Button("Volume", systemImage: viewModel.vol == 0 ? "speaker.slash.fill" : "speaker.fill" ) {
                    Task { @MainActor in
                        if viewModel.vol == 0 {
                            let restoreVolume = volumeBeforeMute > 0 ? volumeBeforeMute : 127
                            viewModel.vol = restoreVolume
                        } else {
                            volumeBeforeMute = viewModel.vol
                            viewModel.vol = 0
                        }
                    }
                }
                Slider(value: $viewModel.vol, in: 0...127)
                    .frame(width: 300)
                    .padding([.trailing])
            }
            .hoverEffect { effect, isActive, proxy in
                effect.clipShape(.capsule.size(
                    width: isActive ? proxy.size.width : proxy.size.height,
                    height: proxy.size.height,
                    anchor: .leading
                ))
                //effect.scaleEffect(x: isActive ? 1: 0.5, y: 1, anchor: .leading)
            }
             // .help("Adjust window to stream aspect ratio") // Accessibility hint
            additions()
        }
    }
}

struct aspectRatioRectangle: View {
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.0001)) // Invisible fill for interaction
                Rectangle()
                    .stroke(Color.primary, lineWidth: 2)
                    .padding(geometry.size.width * 0.1) // Adjust padding for visual aspect ratio
                    .aspectRatio(aspectRatio, contentMode: .fit)
            }
        }
        .frame(width: 30, height: 20) // Adjust size as needed
    }
}