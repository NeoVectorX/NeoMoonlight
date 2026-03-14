//
//  SettingsView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @Binding public var settings: TemporarySettings
    @AppStorage("classic.absoluteTouchMode") private var classicAbsoluteTouchMode: Bool = false
    @State private var selectedAspectRatio: AspectRatio?
    @State private var isCustomAspectRatio: Bool = false
    @State private var isCustomResolution: Bool = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Video Settings Section
                SettingsSection(title: "Video Settings") {
                    HStack {
                        Text("Resolution")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: Binding(
                            get: {
                                isCustomResolution ? Resolution(width: -1, height: -1) : settings.resolution
                            },
                            set: { newValue in
                                if newValue.width == -1 && newValue.height == -1 {
                                    isCustomResolution = true
                                    customWidth = String(settings.resolution.width)
                                    customHeight = String(settings.resolution.height)
                                } else {
                                    isCustomResolution = false
                                    settings.resolution = newValue
                                }
                            }
                        )) {
                            Text("Custom").tag(Resolution(width: -1, height: -1))
                            
                            ForEach(Self.resolutionsGroupedByType, id: \.0) { aspectRatio, resolutions in
                                Section(header: Text(aspectRatio.displayString)) {
                                    ForEach(resolutions, id: \.self) { resolution in
                                        Text(resolution.description).tag(resolution)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    // Custom Resolution Input Panel
                    if isCustomResolution {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Width")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    TextField("", text: $customWidth)
                                        .textFieldStyle(.plain)
                                        .keyboardType(.numberPad)
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .onChange(of: customWidth) { _, newValue in
                                            let filtered = newValue.filter { $0.isNumber }
                                            if filtered != newValue {
                                                customWidth = filtered
                                            }
                                            if let width = Int(filtered), width > 0,
                                               let height = Int(customHeight), height > 0 {
                                                settings.resolution = Resolution(width: width, height: height)
                                            }
                                        }
                                }
                                
                                Text("×")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.top, 18)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Height")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    TextField("", text: $customHeight)
                                        .textFieldStyle(.plain)
                                        .keyboardType(.numberPad)
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .onChange(of: customHeight) { _, newValue in
                                            let filtered = newValue.filter { $0.isNumber }
                                            if filtered != newValue {
                                                customHeight = filtered
                                            }
                                            if let width = Int(customWidth), width > 0,
                                               let height = Int(filtered), height > 0 {
                                                settings.resolution = Resolution(width: width, height: height)
                                            }
                                        }
                                }
                            }
                            
                            Text("Enter custom resolution (e.g., 3440×1440)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.top, 8)
                    }
                    
                    // Aspect Ratio picker hidden - redundant with grouped resolution picker
                    // HStack {
                    //     Text("Aspect Ratio")
                    //         .foregroundColor(.white)
                    //     Spacer()
                    //     Picker("", selection: $selectedAspectRatio) {
                    //         ForEach(Self.resolutionsGroupedByType.map { $0.0 }, id: \.self) { aspectRatio in
                    //             Text(aspectRatio.displayString).tag(aspectRatio as AspectRatio?)
                    //         }
                    //     }
                    //     .pickerStyle(.menu)
                    //     .onChange(of: selectedAspectRatio) { newValue in
                    //         if let newAspectRatio = newValue {
                    //             Task { @MainActor in
                    //                 updateResolutionForAspectRatio(newAspectRatio)
                    //             }
                    //             isCustomAspectRatio = false
                    //         }
                    //     }
                    // }
                    // .padding(.vertical, 4)
                    
                    HStack {
                        Text("Framerate")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.framerate) {
                            ForEach(Self.framerateTable, id: \.self) { framerate in
                                Text("\(framerate) FPS").tag(framerate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Bitrate")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.bitrate) {
                            ForEach(Self.bitrateTable, id: \.self) { bitrate in
                                Text("\(bitrate / 1000) Mbps").tag(bitrate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    if settings.bitrate > 300000 {
                        Label("Bitrates exceeding 300 Mbps require an extreme high-performance network.", systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Display Mode")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("Display Mode", selection: $settings.renderer) {
                                Text(Renderer.classicMetal.description).tag(Renderer.classicMetal)
                                Text(Renderer.curvedDisplay.description).tag(Renderer.curvedDisplay)
                                Text(Renderer.classicDisplay.description).tag(Renderer.classicDisplay)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: settings.renderer) { _, _ in
                                settings.save()
                            }
                        }
                        
                        if settings.renderer == .curvedDisplay {
                            Text("Curved Display offers an immersive experience with customizable screen curvature, 360° environments, and advanced visual effects. External apps are not visible in this mode.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        } else if settings.renderer == .classicMetal {
                            Text("Flat Display provides a traditional flat screen experience with RealityKit rendering and modern visual enhancements. External apps remain visible.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        } else if settings.renderer == .classicDisplay {
                            Text("Classic Display uses the original UIKit rendering for improved compatibility with keyboard and mouse input. External apps remain visible.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Display Settings
                SettingsSection(title: "Display Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Curved Display Default Controls")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $settings.curvedDefaultControlMode) {
                                Text("Gaze/Touch Control").tag(2)      // gazeControl = 2
                                Text("Screen Adjust").tag(0)    // screenMove = 0
                                Text("Controller").tag(1)       // controller = 1
                            }
                            .pickerStyle(.menu)
                            .onChange(of: settings.curvedDefaultControlMode) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "curved.defaultControlMode")
                            }
                        }
                        
                        Text("Choose the default control at the top when streaming. **Gaze Control/Touch Control**: Move the cursor with your eyes or drag and double pinch to click. **Screen Adjust**: Drag or resize the display using hand gestures. **Controller**: Use a game controller connected to Vision Pro bluetooth. You can switch between modes anytime during streaming.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    // Gaze Control Method
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Curved Display Control Method")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $settings.curvedGazeUseTouchMode) {
                                Text("Gaze (Eye Tracking)").tag(false)
                                Text("Touch (Hand Drag)").tag(true)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: settings.curvedGazeUseTouchMode) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "curved.gazeUseTouchMode")
                            }
                        }
                        
                        Text("Choose how you control the cursor in Gaze Control mode:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        
                        Text("**Gaze (Eye Tracking)**: Look where you want the cursor to go, then pinch to click. Quick double pinch = click, hold pinch = right-click.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                           
                        
                        Text("**Touch (Hand Drag)**: Works like a trackpad. Pinch and drag to move the cursor. Quick double pinch = click, hold pinch = right-click.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    // Gaze Cursor Calibration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gaze Cursor Calibration")
                            .foregroundColor(.white)
                        
                        // Horizontal and Vertical controls on one line
                        HStack(spacing: 8) {
                            // Horizontal: - LEFT, + RIGHT
                            Button(action: {
                                if settings.gazeCursorOffsetX > -100 {
                                    settings.gazeCursorOffsetX -= 2
                                    UserDefaults.standard.set(settings.gazeCursorOffsetX, forKey: "gaze.cursorOffsetX")
                                }
                            }) {
                                Text("- LEFT")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Text(settings.gazeCursorOffsetX >= 0 ? "+\(settings.gazeCursorOffsetX)" : "\(settings.gazeCursorOffsetX)")
                                .foregroundColor(.white)
                                .frame(width: 35)
                            
                            Button(action: {
                                if settings.gazeCursorOffsetX < 100 {
                                    settings.gazeCursorOffsetX += 2
                                    UserDefaults.standard.set(settings.gazeCursorOffsetX, forKey: "gaze.cursorOffsetX")
                                }
                            }) {
                                Text("+ RIGHT")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 30)
                            
                            // Vertical: - DOWN, + UP
                            Button(action: {
                                if settings.gazeCursorOffsetY > -100 {
                                    settings.gazeCursorOffsetY -= 2
                                    UserDefaults.standard.set(settings.gazeCursorOffsetY, forKey: "gaze.cursorOffsetY")
                                }
                            }) {
                                Text("- DOWN")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            
                            Text(settings.gazeCursorOffsetY >= 0 ? "+\(settings.gazeCursorOffsetY)" : "\(settings.gazeCursorOffsetY)")
                                .foregroundColor(.white)
                                .frame(width: 35)
                            
                            Button(action: {
                                if settings.gazeCursorOffsetY < 100 {
                                    settings.gazeCursorOffsetY += 2
                                    UserDefaults.standard.set(settings.gazeCursorOffsetY, forKey: "gaze.cursorOffsetY")
                                }
                            }) {
                                Text("+ UP")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 20)
                            
                            Button(action: {
                                settings.gazeCursorOffsetX = 0
                                settings.gazeCursorOffsetY = 0
                                UserDefaults.standard.set(0, forKey: "gaze.cursorOffsetX")
                                UserDefaults.standard.set(0, forKey: "gaze.cursorOffsetY")
                            }) {
                                Text("Reset")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Fine-tune gaze cursor alignment if the cursor appears offset from where you're looking in Curved Display mode.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Flat Display Default Controls")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $settings.absoluteTouchMode) {
                                Text("Touch Control").tag(false)
                                Text("Gaze Control").tag(true)
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Text("Choose your default cursor control method. **Gaze Control**: Use your eyes and pinch to control the cursor. Quick double pinch = click, hold pinch = right-click. **Touch Control**: Use trackpad-style hand dragging with pinch to control cursor. Quick double pinch = click, hold pinch = right-click. Toggle between modes anytime during streaming.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Classic Display Default Controls")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $classicAbsoluteTouchMode) {
                                Text("Touch Control").tag(false)
                                Text("Gaze Control").tag(true)
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Text("Choose your cursor control method for Classic Display. **Gaze Control**: Touch position follows your gaze. **Touch Control**: Trackpad-style relative movement. This setting is applied when the stream starts and cannot be changed mid-stream.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("On-Screen Controls")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.onscreenControls) {
                            Text("Off").tag(OnScreenControlsLevel.off)
                            Text("Auto").tag(OnScreenControlsLevel.auto)
                            Text("Simple").tag(OnScreenControlsLevel.simple)
                            Text("Full").tag(OnScreenControlsLevel.full)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    if settings.renderer == .curvedDisplay {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Hide Hands in 360° Environments", isOn: $settings.hideHandsIn360Environment)
                                .onChange(of: settings.hideHandsIn360Environment) { _, _ in
                                    settings.save()
                                }
                            
                            Text("When enabled, your hands and arms will be hidden when a 360° environment is active.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Additional Options
                SettingsSection(title: "Additional Options") {
                    VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Controller Mode")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.multiController) {
                                Text("Single / Co-op").tag(false)
                                Text("Multi").tag(true)
                        }
                        .pickerStyle(.menu)
                        }
                        Text("Single/Co-op: Single player or co-op requires this mode. Multi: Multiple controllers connected to the same Vision Pro.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Swap A/B and X/Y Buttons", isOn: $settings.swapABXYButtons)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Play Audio on PC", isOn: $settings.playAudioOnPC)
                        
                        Text("Plays audio on your PC speakers/headphones instead of streaming to Vision Pro.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Mic Streamer Compatibility Mode", isOn: $settings.showMicButton)
                        
                        Text("Adds a mute button to control Mic Streamer app while in Curved Display mode.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show Task Manager Button", isOn: Binding(
                            get: { settings.showTaskManagerButton },
                            set: { newValue in
                                settings.showTaskManagerButton = newValue
                                UserDefaults.standard.set(newValue, forKey: "showTaskManagerButton")
                            }
                        ))
                        
                        Text("Adds a button to the top controls that quickly opens Task Manager on your PC.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show Controller Battery Level", isOn: Binding(
                            get: { settings.showControllerBattery },
                            set: { newValue in
                                settings.showControllerBattery = newValue
                                UserDefaults.standard.set(newValue, forKey: "showControllerBattery")
                            }
                        ))
                        
                        Text("Displays battery level and charging status for the primary controller.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Dynamic Controls Menu", isOn: Binding(
                            get: { settings.useCollapsedControlsMenu },
                            set: { newValue in
                                settings.useCollapsedControlsMenu = newValue
                                UserDefaults.standard.set(newValue, forKey: "useCollapsedControlsMenu")
                            }
                        ))
                        
                        Text("Top bar becomes a single less distracting icon that expands on tap. Turn off for the classic always-visible bar.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Remove Rounded Corners", isOn: Binding(
                            get: { settings.removeRoundedCorners },
                            set: { newValue in
                                settings.removeRoundedCorners = newValue
                                UserDefaults.standard.set(newValue, forKey: "removeRoundedCorners")
                            }
                        ))
                        
                        Text("Disables the rounded corners on the stream display. Requires relaunch.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Dark Mode", isOn: Binding(
                            get: { settings.darkControlsMode },
                            set: { newValue in
                                settings.darkControlsMode = newValue
                                UserDefaults.standard.set(newValue, forKey: "darkControlsMode")
                            }
                        ))
                        
                        Text("Further reduces control bar visibility for enhanced immersion in dark environments. (Flat and Curved display mode only)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
                
                // Advanced Settings
                SettingsSection(title: "Advanced") {
                    HStack {
                        Text("Preferred Codec")
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $settings.preferredCodec) {
                            Text("H.264").tag(PreferredCodec.h264)
                            Text("HEVC").tag(PreferredCodec.hevc)
                            Text("AV1 (M5 only)").tag(PreferredCodec.av1)
                            Text("Auto").tag(PreferredCodec.auto)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Enable HDR", isOn: $settings.enableHdr)
                        .padding(.vertical, 4)
                    
                    if settings.enableHdr {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "sun.max.fill")
                                    .foregroundColor(.yellow)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("HDR Setup Required")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("To use HDR, enable it on your host PC: Settings → Display → Use HDR. Your monitor must support HDR. For virtual displays (Apollo), HDR is supported automatically.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.yellow.opacity(0.15))
                            )
                        }
                        .padding(.top, 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Frame Pacing")
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $settings.useFramePacing) {
                                Text("Lowest Latency").tag(false)
                                Text("Smoothest Video").tag(true)
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Text("Lowest Latency: minimal lag, ideal for competitive games. Smoothest Video: no stutters, ideal for cinematic games.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 24)
        }
        .onDisappear {
            settings.save()
        }
        .onAppear {
            selectedAspectRatio = settings.resolution.aspectRatio
            isCustomAspectRatio = !Self.resolutionTable.contains(settings.resolution)
            
            // Check if current resolution is custom (not in preset table)
            if !Self.resolutionTable.contains(settings.resolution) {
                isCustomResolution = true
                customWidth = String(settings.resolution.width)
                customHeight = String(settings.resolution.height)
            }
            
            // Load curved display default control mode from UserDefaults
            settings.curvedDefaultControlMode = UserDefaults.standard.integer(forKey: "curved.defaultControlMode")
            
            // Load gaze control method from UserDefaults
            settings.curvedGazeUseTouchMode = UserDefaults.standard.bool(forKey: "curved.gazeUseTouchMode")
            
            // Load gaze cursor calibration from UserDefaults
            settings.gazeCursorOffsetX = UserDefaults.standard.integer(forKey: "gaze.cursorOffsetX")
            settings.gazeCursorOffsetY = UserDefaults.standard.integer(forKey: "gaze.cursorOffsetY")
        }
        .onChange(of: settings.resolution) { _, newValue in
            selectedAspectRatio = newValue.aspectRatio
        }
    }

    @MainActor
    private func updateResolutionForAspectRatio(_ newAspectRatio: AspectRatio) {
        let currentWidth = settings.resolution.width
        let currentHeight = settings.resolution.height

        if currentWidth >= currentHeight {
            settings.resolution = Resolution(width: currentWidth, height: (currentWidth * newAspectRatio.height) / newAspectRatio.width)
        } else {
            settings.resolution = Resolution(width: (currentHeight * newAspectRatio.width) / newAspectRatio.height, height: currentHeight)
        }
        isCustomAspectRatio = false
    }
}

// MARK: - Settings Section Component
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 24)
            
            VStack(spacing: 12) {
                content
            }
            .padding(24)
            .background(
                ZStack {
                    // Depth shadow
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                        .offset(y: 6)
                        .blur(radius: 12)
                    
                    // Main card
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Setting Row Component
struct SettingRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.white.opacity(0.7))
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 4)
    }
}

private extension TemporarySettings {
    var resolution: SettingsView.Resolution {
        get {
            SettingsView.Resolution(width: Int(width), height: Int(height))
        }
        set {
            width = Int32(newValue.width)
            height = Int32(newValue.height)
        }
    }
}

extension SettingsView {
    struct AspectRatio: Equatable, Hashable, Comparable {
        private(set) var width: Int
        private(set) var height: Int

        init(width: Int, height: Int) {
            let reduced = simplifyFraction(numerator: width, denominator: height)
            self.width = reduced.numerator
            self.height = reduced.denominator
        }

        var casualDescription: LocalizedStringKey {
            switch self {
            case AspectRatio(width: 16, height: 9):
                "16:9"
            case AspectRatio(width: 16, height: 10):
                "16:10"
            case AspectRatio(width: 4, height: 3):
                "4:3"
            case AspectRatio(width: 64, height: 27):
                "21:9"
            case AspectRatio(width: 43, height: 18):
                "21:9"
            case AspectRatio(width: 24, height: 10):
                "24:10"
            case AspectRatio(width: 32, height: 10):
                "32:10"
            case AspectRatio(width: 64, height: 18):
                "32:9"
            default:
                "\(width):\(height)"
            }
        }
        
        var displayString: String {
            switch self {
            case AspectRatio(width: 16, height: 9):
                return "16:9"
            case AspectRatio(width: 16, height: 10):
                return "16:10"
            case AspectRatio(width: 4, height: 3):
                return "4:3"
            case AspectRatio(width: 64, height: 27):
                return "21:9"
            case AspectRatio(width: 43, height: 18):
                return "21:9"
            case AspectRatio(width: 24, height: 10):
                return "24:10"
            case AspectRatio(width: 32, height: 10):
                return "32:10"
            case AspectRatio(width: 64, height: 18):
                return "32:9"
            default:
                return "\(width):\(height)"
            }
        }

        static func < (lhs: SettingsView.AspectRatio, rhs: SettingsView.AspectRatio) -> Bool {
            (Double(lhs.width) / Double(lhs.height)) < (Double(rhs.width) / Double(rhs.height))
        }
    }

    struct Resolution: Equatable, Hashable, CustomStringConvertible {
        var width: Int
        var height: Int

        var aspectRatio: AspectRatio {
            AspectRatio(width: width, height: height)
        }

        var description: String {
            switch self {
            case Resolution(width: 3840, height: 2160):
                "3840x2160 (4K)"
            case Resolution(width: 5120, height: 2880):
                "5120x2880 (5K)"
            case Resolution(width: 7680, height: 4320):
                "7680x4320 (8K)"
            case Resolution(width: 1280, height: 720):
                "1280x720 (720p)"
            case Resolution(width: 1920, height: 1080):
                "1920x1080 (1080p)"
            case Resolution(width: 2560, height: 1440):
                "2560x1440 (1440p)"
            default:
                "\(width)x\(height)"
            }
        }
    }

    static let resolutionTable = [
        // 16:9 Standard
        Resolution(width: 1280, height: 720),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 2560, height: 1440),
        Resolution(width: 3840, height: 2160),
        Resolution(width: 5120, height: 2880),
        Resolution(width: 7680, height: 4320),  // 8K
        
        // 16:10 Widescreen
        Resolution(width: 1280, height: 800),
        Resolution(width: 1440, height: 900),
        Resolution(width: 1680, height: 1050),
        Resolution(width: 1920, height: 1200),
        Resolution(width: 2560, height: 1600),
        Resolution(width: 3840, height: 2400),
        
        // 21:9 Ultrawide
        Resolution(width: 2560, height: 1080),
        Resolution(width: 3440, height: 1440),
        Resolution(width: 3840, height: 1600),
        Resolution(width: 5120, height: 2160),
        
        // 32:9 Super Ultrawide
        Resolution(width: 3840, height: 1080),
        Resolution(width: 5120, height: 1440),
        Resolution(width: 7680, height: 2160),
        
        // 32:10 Ultrawide
        Resolution(width: 3840, height: 1200),
        
        // Other Ultrawide
        Resolution(width: 5120, height: 1080),  // Super ultrawide 21:9 variant
    ]

    static var resolutionsGroupedByType: [(AspectRatio, [Resolution])] {
        // Group resolutions, but use displayString for grouping to combine similar aspect ratios
        let grouped = Dictionary(grouping: resolutionTable) { resolution -> String in
            resolution.aspectRatio.displayString
        }
        
        // Convert back to AspectRatio keys, using the first resolution's aspect ratio as representative
        return grouped.map { (displayString, resolutions) -> (AspectRatio, [Resolution]) in
            let representativeAspectRatio = resolutions.first!.aspectRatio
            return (representativeAspectRatio, resolutions.sorted { $0.width < $1.width })
        }.sorted { $0.0 < $1.0 }
    }

    static let framerateTable: [Int32] = [30, 60, 90, 100, 120]

    static let bitrateTable: [Int32] = [5000, 10000, 30000, 50000, 75000, 100000, 120000, 150000, 175000, 200000, 225000, 250000, 300000, 325000, 350000, 400000, 450000, 500000]
}

private func gcd<I: BinaryInteger>(_ a: I, _ b: I) -> I {
    var a = a
    var b = b
    while b != 0 {
        let temp = b
        b = a % b
        a = temp
    }
    return a
}

private func simplifyFraction<I: BinaryInteger>(numerator: I, denominator: I) -> (numerator: I, denominator: I) {
    let divisor = gcd(numerator, denominator)
    return (numerator / divisor, denominator / divisor)
}

#Preview {
    @State var settings = TemporarySettings()
    return SettingsView(settings: $settings)
}
