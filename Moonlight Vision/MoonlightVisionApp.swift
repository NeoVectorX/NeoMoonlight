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
            .environmentObject(appDelegate.mainViewModel)
            .environment(\.isEmbeddedInCurved, true)
            .onDisappear {
                // Do not mutate streamConfig during swap teardown; coordinator handles lifecycle.
                // Previously cleared streamConfig.wrappedValue here, which could race with swap.
            }
            .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                if isSwapping { return }
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed, .full)
        .immersiveContentBrightness(.automatic)
        .upperLimbVisibility(.automatic)
        .immersiveEnvironmentBehavior(.coexist)

        WindowGroup(id: "realitykitStreamingWindow", for: StreamConfiguration.self) { streamConfig in
            RealityKitStreamView(streamConfig: streamConfig, needsHdr: appDelegate.mainViewModel.streamSettings.enableHdr)
            .environmentObject(appDelegate.mainViewModel)
            .onDisappear {
                // Do not clear streamConfig here; lifecycle managed centrally to avoid races.
            }
            .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                if isSwapping { return }
                AudioHelpers.fixAudioForSurroundForCurrentWindow()
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2, height: 2, depth: 2, in: .meters)

        WindowGroup(id: "realitykitClassic3DWindow", for: StreamConfiguration.self) { streamConfig in
                RealityKitClassic3DView(streamConfig: streamConfig, needsHdr: appDelegate.mainViewModel.streamSettings.enableHdr)
                .environmentObject(appDelegate.mainViewModel)
                .onDisappear {
                    // Do not clear streamConfig here; lifecycle managed centrally to avoid races.
                }
                .onChange(of: appDelegate.mainViewModel.isSwappingRenderers) { isSwapping in
                    if isSwapping { return }
                    AudioHelpers.fixAudioForSurroundForCurrentWindow()
                }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2, height: 2, depth: 2, in: .meters)
        
        WindowGroup(id: "hdrTestWindow", for: StreamConfiguration.self) { streamConfig in
            HDRTestStreamView(streamConfig: streamConfig)
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
        .defaultSize(width: 1920, height: 1080)
        .windowResizability(.contentSize)

        WindowGroup(id: "classicStreamingWindow", for: StreamConfiguration.self) { streamConfig in
            UIKitStreamView(streamConfig: streamConfig)
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
    }
}

private struct MainRootView<Content: View>: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject private var vm: MainViewModel
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .onAppear {
                if vm.streamSettings.renderer != .curvedDisplay {
                    Task { await dismissImmersiveSpace() }
                }
            }
            .onChange(of: vm.activelyStreaming) { active in
                if !active, vm.streamSettings.renderer != .curvedDisplay {
                    Task { await dismissImmersiveSpace() }
                }
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
