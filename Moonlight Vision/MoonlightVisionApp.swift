//
//  MoonlightVisionApp.swift
//  Neo Moonlight
//
//  Copyright © 2025 Neo Moonlight. All rights reserved.
//  Forked from Moonlight Game Streaming Project
//

import SwiftUI

struct MoonlightVisionApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var showSplash = true
    
    @State private var splashOpacity: Double = 0.0
    @State private var splashScale: CGFloat = 0.95
    
    var body: some Scene {
        WindowGroup("Main view", id: "mainView") {
            if showSplash {
                ZStack {
                    Image("neomoonlight-banner")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 600)
                        .opacity(splashOpacity)
                        .scaleEffect(splashScale)
                        .animation(.easeInOut(duration: 0.6), value: splashOpacity)
                        .animation(.easeInOut(duration: 0.6), value: splashScale)
                }
                .frame(width: 700, height: 920)
                .glassBackgroundEffect()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        splashOpacity = 1.0
                        splashScale = 1.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        splashOpacity = 0.0
                        splashScale = 1.05
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            showSplash = false
                        }
                    }
                }
            } else {
                MainRootView {
                    MainContentView()
                        .persistentSystemOverlays(.visible)
                        .transition(.opacity)
                        .environment(\.isEmbeddedInCurved, false)
                }
                .environmentObject(appDelegate.mainViewModel)
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { content, context in
            return WindowPlacement(.utilityPanel)
        }

        WindowGroup("LoadingStream", id: "dummy") {
            DummyView()
                .environmentObject(appDelegate.mainViewModel)
        }
        .handlesExternalEvents(matching: ["dummy"])
        
        // Curved Display - ImmersiveSpace
        ImmersiveSpace(id: "curvedDisplayImmersiveSpace", for: StreamConfiguration.self) { streamConfig in
            CurvedDisplayStreamView(
                streamConfig: streamConfig,
                needsHdr: appDelegate.mainViewModel.streamSettings.enableHdr
            )
            // CRITICAL: Same as flatDisplayWindow — force fresh view on each session
            .id(streamConfig.wrappedValue?.sessionUUID ?? "none")
            .environmentObject(appDelegate.mainViewModel)
            .environment(\.isEmbeddedInCurved, true)
            .onDisappear {
                // Do not mutate streamConfig during swap teardown; coordinator handles lifecycle.
            }
            .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                if isSwapping { return }
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .full)
        .upperLimbVisibility(.automatic)
        .immersiveEnvironmentBehavior(.coexist)
        .restorationBehavior(.disabled)

        // Flat Display - RealityKit in WindowGroup
        WindowGroup(id: "flatDisplayWindow", for: StreamConfiguration.self) { streamConfig in
            FlatDisplayStreamView(
                streamConfig: streamConfig,
                needsHdr: appDelegate.mainViewModel.streamSettings.enableHdr
            )
            // CRITICAL: Force SwiftUI to destroy the old view and create a fresh one
            // whenever a new stream session starts. Without this, SwiftUI may reuse
            // the previous FlatDisplayStreamView instance with stale @State variables
            // (hasPerformedTeardown=true, windowDecommissioned=true, streamMan=old ref)
            // which causes a crash/black screen on co-op rejoin.
            .id(streamConfig.wrappedValue?.sessionUUID ?? "none")
            .environmentObject(appDelegate.mainViewModel)
            .onDisappear {
                // Do not clear streamConfig here; lifecycle managed centrally to avoid races.
            }
            .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                if isSwapping { return }
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: ["flatDisplayWindow"])
        
        // Classic Display - UIKit-based streaming (for keyboard+mouse compatibility)
        WindowGroup(id: "classicStreamingWindow", for: StreamConfiguration.self) { $streamConfig in
            UIKitStreamView(streamConfig: $streamConfig)
                .id(streamConfig?.sessionUUID ?? "none")
                .environmentObject(appDelegate.mainViewModel)
                .onDisappear {
                    // Do not clear streamConfig here; lifecycle managed centrally to avoid races.
                }
                .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                    if isSwapping { return }
                    AudioHelpers.fixAudioForSurroundForCurrentWindow()
                }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: ["classicStreamingWindow"])
        
        // Kickstarter Window - Forces visionOS to recalculate Shared Space visibility
        // This enables external apps (Spotify, Discord, etc.) to appear in Curved Display mode
        WindowGroup(id: "Kickstarter") {
            Color.clear
                .frame(width: 1, height: 1)
                .opacity(0.001) // Invisible but rendered
                .allowsHitTesting(false) // Let clicks pass through
        }
        .windowStyle(.plain)
        .defaultSize(width: 0.1, height: 0.1, depth: 0.0, in: .meters)
    }
}

private struct MainRootView<Content: View>: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var vm: MainViewModel
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .onChange(of: vm.shouldRelaunchStream) { shouldRelaunch in
                guard shouldRelaunch else { return }
                vm.shouldRelaunchStream = false
                Task { await relaunchStream() }
            }
    }
    
    @MainActor
    private func relaunchStream() async {
        let renderer = vm.streamSettings.renderer
        
        guard let config = vm.currentStreamConfig.copy() as? StreamConfiguration else {
            print("[Relaunch] Failed to copy stream config")
            return
        }
        
        let newToken = UUID().uuidString
        config.sessionUUID = newToken
        vm.activeSessionToken = newToken
        vm.currentStreamConfig = config
        vm.streamState = .starting
        
        print("[Relaunch] Re-opening \(renderer) with new session \(newToken)")
        
        if renderer == .curvedDisplay {
            dismissWindow(id: "mainView")
            try? await Task.sleep(for: .milliseconds(300))
            let result = try? await openImmersiveSpace(id: renderer.windowId, value: config)
            print("[Relaunch] Immersive space result: \(String(describing: result))")
        } else {
            try? await Task.sleep(for: .milliseconds(150))
            openWindow(id: renderer.windowId, value: config)
            print("[Relaunch] \(renderer.description) window opened")
        }
    }
}

@main
struct MainWrapper {
    static func main() -> Void {
        SDLMainWrapper.setMainReady();
        MoonlightVisionApp.main()
    }
}
