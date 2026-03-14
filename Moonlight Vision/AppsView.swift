//
//  AppView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/27/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    
    @State private var nowLoading: String?
    @State private var nowLoadingTimeout: DispatchWorkItem?
    
    @State private var firstFrameObserver: NSObjectProtocol?
    @State private var firstFrameFallback: DispatchWorkItem?
    
    @Binding
    public var host: TemporaryHost
    
    // Brand colors
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)  // #f9a040
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 0) {
            headerCard
            AppsScrollList(
                host: host,
                nowLoading: $nowLoading,
                onSelectApp: { app in handleAppSelection(app: app) },
                onDisconnect: handleDisconnect,
                onQuit: { app in handleQuit(app: app) }
            )
        }
        .onAppear() {
            // FIXED: Don't refresh if actively streaming
            guard !viewModel.activelyStreaming else {
                print("[AppsView] Skipping refresh because actively streaming")
                return
            }
            
            // this MUST be async lmao
            Task {
                print("LOAD")
                viewModel.refreshAppsFor(host: host)
            }
        }
    }
    
    private var headerCard: some View {
        HStack(spacing: 20) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandViolet, brandViolet.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)
            
            Image(systemName: "macbook.and.vision.pro")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(brandBlue.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(host.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("\(host.appList.count) app\(host.appList.count == 1 ? "" : "s") available")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
        }
        .padding(28)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
    
    private func handleAppSelection(app: TemporaryApp) {
        if nowLoading != nil { return }
        nowLoading = app.id ?? app.name
        
        // CRITICAL FIX: Safety timeout to prevent nowLoading from getting stuck
        // This prevents the "Launch locks up" bug where user can't tap any app
        nowLoadingTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak viewModel] in
            if self.nowLoading != nil {
                print("[AppsView] ⚠️ Safety timeout: Clearing stuck nowLoading after 5s")
                self.nowLoading = nil
                // Also reset any potentially stuck state
                if viewModel?.streamState == .stopping {
                    print("[AppsView] ⚠️ Force resetting stuck streamState")
                    viewModel?.streamState = .idle
                }
            }
        }
        nowLoadingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)
        
        // Stop discovery before starting stream to prevent interference
        viewModel.stopRefresh()

        if viewModel.streamState == .stopping {
            print("[AppsView] Connect requested while stopping; waiting for teardown...")
            Task {
                await viewModel.waitForTeardown()
                openAppStream(app: app)
            }
            return
        }

        let cooldown = viewModel.reconnectCooldownRemaining()
        if cooldown > 0 {
            print("[AppsView] Reconnect cooldown active (\(cooldown)s). Delaying connect.")
            DispatchQueue.main.asyncAfter(deadline: .now() + cooldown + 0.05) {
                // Re-check state after cooldown before opening
                if self.viewModel.streamState != .idle {
                    Task {
                        await self.viewModel.waitForTeardown()
                        self.openAppStream(app: app)
                    }
                } else if self.viewModel.canReconnectNow() {
                    self.openAppStream(app: app)
                } else {
                    // If still not ready, add a minimal delay and try once more
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.openAppStream(app: app)
                    }
                }
            }
            return
        }
        
        if viewModel.activelyStreaming || viewModel.streamState != .idle {
            print("[AppsView] Requesting new stream while another is active. Disconnecting first.")
            viewModel.userDidRequestDisconnect()

            Task {
                await viewModel.waitForTeardown()
                print("[AppsView] Teardown complete. Now opening new stream.")
                openAppStream(app: app)
            }
        } else {
            if let stale = _UIKitStreamView.controllerReference.object {
                print("[AppsView] Stale controller found; requesting stop before connect")
                stale.stopStream()
                _UIKitStreamView.controllerReference.object = nil
            }
            openAppStream(app: app)
        }
    }
    
    private func openAppStream(app: TemporaryApp) {
        // Gate: do not start a new connection until any in-progress stop has truly
        // completed (LiStopConnection returned). The ConnectionSerializer is the
        // authoritative gate — no timers, no guessing.
        if ConnectionSerializer.shared.isStopInProgress {
            print("[AppsView] ConnectionSerializer gate is closed — waiting for stop to complete before starting")
            Task {
                await ConnectionSerializer.shared.waitUntilReadyToStart()
                print("[AppsView] ConnectionSerializer gate opened — proceeding with stream start")
                openAppStream(app: app)
            }
            return
        }

        // CRITICAL FIX: Defensively clear any stale state before starting
        viewModel.prepareForNewStream()
        
        if let config = viewModel.stream(app: app) {
            var renderer = viewModel.streamSettings.renderer

            // Before opening a new stream, ensure any existing streaming window is closed
            dismissWindow(id: "flatDisplayWindow")
            dismissWindow(id: "classicStreamingWindow")

            if renderer == .curvedDisplay {
                dismissWindow(id: "mainView")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Task {
                        print("[AppsView] Opening curved display immersive space...")
                        let result = try await openImmersiveSpace(id: renderer.windowId, value: config)
                        print("[AppsView] Immersive space result: \(result)")
                        self.viewModel.isImmersiveSpaceOpen = true
                        self.clearNowLoading()
                    }
                }
            } else {
                // Flat Display or Classic Display renderer
                Task {
                    // Only dismiss immersive space if one is actually open
                    if viewModel.isImmersiveSpaceOpen {
                        await dismissImmersiveSpace()
                        viewModel.isImmersiveSpaceOpen = false
                    }
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            openWindow(id: renderer.windowId, value: config)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismissWindow(id: "mainView")
                        }
                        self.clearNowLoading()
                    }
                }
            }
        } else {
            clearNowLoading()
        }
    }
    
    /// Clears nowLoading and cancels the safety timeout
    private func clearNowLoading() {
        nowLoadingTimeout?.cancel()
        nowLoadingTimeout = nil
        nowLoading = nil
    }

    private func clearFirstFrameObservers() {
        if let obs = firstFrameObserver {
            NotificationCenter.default.removeObserver(obs)
            firstFrameObserver = nil
        }
        firstFrameFallback?.cancel()
        firstFrameFallback = nil
    }
    
    private func handleDisconnect() {
        print("[AppsView] Disconnect button tapped. Requesting disconnect from ViewModel.")
        viewModel.userDidRequestDisconnect()
        clearNowLoading()
    }
    
    private func handleQuit(app: TemporaryApp) {
        let httpManager = HttpManager(host: app.host())
        let httpResponse = HttpResponse()
        let quitRequest = HttpRequest(for: httpResponse, with: httpManager?.newQuitAppRequest())
        Task {
            httpManager?.executeRequestSynchronously(quitRequest)
        }
    }
}

// Extract Scroll List to smaller view for type-check performance
private struct AppsScrollList: View {
    let host: TemporaryHost
    @Binding var nowLoading: String?
    let onSelectApp: (TemporaryApp) -> Void
    let onDisconnect: () -> Void
    let onQuit: (TemporaryApp) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(host.appList.sorted(by: { $0.name ?? "" < $1.name ?? "" }), id: \.id) { app in
                    AppCard(
                        app: app,
                        host: host,
                        isLoading: nowLoading == (app.id ?? app.name),
                        isStreaming: false, // Simplifying, adjust as needed for your logic
                        onTap: { onSelectApp(app) },
                        onDisconnect: onDisconnect,
                        onQuit: { onQuit(app) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - App Card Component
struct AppCard: View {
    let app: TemporaryApp
    let host: TemporaryHost
    let isLoading: Bool
    let isStreaming: Bool
    let onTap: () -> Void
    let onDisconnect: () -> Void
    let onQuit: () -> Void
    
    @State private var isHovered = false
    
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)  // #f9a040
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandRed = Color(red: 1.0, green: 0.3, blue: 0.3)  // Disconnect red
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var isRunning: Bool {
        app.id == host.currentGame
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // App Icon Placeholder
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [brandBlue.opacity(0.3), brandBlue.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 70, height: 70)
                    .blur(radius: 8)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brandBlue.opacity(0.3), brandBlue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [brandBlue.opacity(0.6), brandBlue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: brandBlue.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .rotation3DEffect(
                .degrees(isHovered ? 10 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            
            // App Info
            VStack(alignment: .leading, spacing: 8) {
                Text(app.name ?? "Unknown")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                if isRunning || isStreaming {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: .green.opacity(0.8), radius: 4, x: 0, y: 2)
                        
                        Text(isStreaming ? "Streaming" : "Running")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .tint(brandViolet)
            } else if isStreaming {
                // Disconnect Button with red/orange theme
                Button(action: onDisconnect) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Disconnect")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(brandRed.opacity(0.3))
                                .offset(y: 4)
                                .blur(radius: 6)
                            
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [brandRed, brandRed.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        }
                    )
                    .shadow(color: brandRed.opacity(0.5), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(.scale.combined(with: .opacity))
            } else {
                // Launch Button with violet theme
                Button(action: onTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Launch")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(brandOrange.opacity(0.3))
                                .offset(y: 4)
                                .blur(radius: 6)
                            
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [brandOrange, brandOrange.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                        }
                    )
                    .shadow(color: brandOrange.opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 6)
                    .blur(radius: 12)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: isStreaming 
                                        ? [brandRed.opacity(0.4), brandRed.opacity(0.2)]
                                        : [.white.opacity(0.15), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isStreaming ? 2 : 1
                            )
                    )
            }
        )
        .shadow(
            color: isStreaming ? brandRed.opacity(0.3) : .black.opacity(0.2), 
            radius: isStreaming ? 20 : 16, 
            x: 0, 
            y: 8
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .rotation3DEffect(
            .degrees(isHovered ? 2 : 0),
            axis: (x: 1, y: 0, z: 0)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if isRunning {
                Button {
                    onQuit()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
            }
        }
    }
}

private func waitForTeardownThen(_ block: @escaping () -> Void) {
    let center = NotificationCenter.default
    var fired = false
    var obs1: NSObjectProtocol?
    var obs2: NSObjectProtocol?
    var obs3: NSObjectProtocol?

    func cleanupAndFire() {
        if fired { return }
        fired = true
        if let o = obs1 { center.removeObserver(o) }
        if let o = obs2 { center.removeObserver(o) }
        if let o = obs3 { center.removeObserver(o) }
        block()
    }

    obs1 = center.addObserver(forName: Notification.Name("StreamDidTeardownNotification"), object: nil, queue: .main) { _ in
        print("[AppsView] Received StreamDidTeardownNotification")
        cleanupAndFire()
    }

    obs2 = center.addObserver(forName: Notification.Name("RKStreamDidTeardown"), object: nil, queue: .main) { _ in
        print("[AppsView] Received RKStreamDidTeardown")
        cleanupAndFire()
    }

    obs3 = center.addObserver(forName: Notification.Name("StreamStartFailed"), object: nil, queue: .main) { _ in
        print("[AppsView] Received StreamStartFailed")
        cleanupAndFire()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        if !fired {
            print("[AppsView] Teardown wait timed out; proceeding")
            cleanupAndFire()
        }
    }
}