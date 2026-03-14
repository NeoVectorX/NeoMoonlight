//
//  CoopSetupView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI
import GroupActivities

struct CoopSetupView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var coordinator = CoopSessionCoordinator.shared
    
    let host: TemporaryHost
    @Binding var isPresented: Bool
    
    @State private var selectedApp: TemporaryApp?
    @State private var isStartingSession = false
    @State private var errorMessage: String?
    
    // Brand colors
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandViolet, brandViolet.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Co-op Play")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Play local co-op games with a friend")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 32)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Status or App Selection
            if coordinator.sessionActive && coordinator.isGuest {
                guestJoiningView
            } else if coordinator.sessionActive && coordinator.isHosting {
                hostWaitingView
            } else {
                appSelectionView
            }
            
            Spacer()
            
            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            
            // Close Button
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(width: 700, height: 800)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            // If we're automatically joining as guest, handle it
            if coordinator.isGuest && coordinator.sessionActive {
                handleGuestAutoJoin()
            }
        }
    }
    
    // MARK: - App Selection View (Host)
    
    private var appSelectionView: some View {
        VStack(spacing: 24) {
            Text("Select a co-op game to play")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(host.appList.sorted(by: { $0.name ?? "" < $1.name ?? "" }), id: \.id) { app in
                        CoopAppCard(
                            app: app,
                            isSelected: selectedApp?.id == app.id,
                            onTap: { selectedApp = app }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 400)
            
            Button {
                startCoopSession()
            } label: {
                HStack(spacing: 12) {
                    if isStartingSession {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    Text(isStartingSession ? "Starting..." : "Start Co-op Session")
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [brandViolet, brandViolet.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: brandViolet.opacity(0.3), radius: 15, x: 0, y: 8)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedApp == nil || isStartingSession)
            .opacity(selectedApp == nil ? 0.5 : 1.0)
        }
    }
    
    // MARK: - Host Waiting View
    
    private var hostWaitingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(brandViolet)
            
            Text("Waiting for friend to join...")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Participants: \(coordinator.participants.count)/2")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
            
            if coordinator.participants.count >= 2 {
                Text("Friend joined! Starting game...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(brandViolet)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(brandViolet.opacity(0.1))
                    )
            }
        }
        .padding(40)
    }
    
    // MARK: - Guest Joining View
    
    private var guestJoiningView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(brandViolet)
            
            if let activity = coordinator.currentActivity {
                Text("Joining co-op session")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(activity.appName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(brandOrange)
                
                Text("on \(activity.hostPCName)")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func startCoopSession() {
        guard let app = selectedApp else { return }
        guard !isStartingSession else { return }
        
        isStartingSession = true
        errorMessage = nil
        
        Task {
            do {
                // Force 90 FPS for co-op compatibility (M2 Vision Pro max)
                let frameRate: Int32 = 90
                print("[CoopSetup] Co-op frame rate locked to 90 FPS for M2 compatibility")
                
                // Export pairing data for sharing
                let dataManager = DataManager()
                guard let pairingData = dataManager.exportPairingData(for: host) else {
                    throw CoopError.failedToExportPairing
                }
                
                // Create activity
                let activity = MoonlightCoopActivity(
                    hostPCAddress: host.activeAddress ?? host.address ?? "",
                    hostPCName: host.name,
                    hostPCPort: host.httpsPort,
                    isInternetAccessible: coordinator.isInternetAccessible(host: host),
                    connectionMode: "Local",
                    appID: app.id ?? app.name,
                    appName: app.name,
                    sessionID: UUID().uuidString,
                    hostFrameRate: frameRate,
                    pairingData: pairingData
                )
                
                // Start hosting
                try await coordinator.startHosting(activity: activity)
                
                // Update ViewModel with co-op state
                viewModel.isCoopSession = true
                viewModel.assignedControllerSlot = 0  // Host is slot 0 (player 1)
                
                // Small delay to let SharePlay UI appear
                try await Task.sleep(for: .milliseconds(500))
                
                // Now launch the stream normally
                await MainActor.run {
                    // Close this setup view
                    isPresented = false
                    
                    // Start the stream
                    launchCoopStream(app: app, host: host)
                }
                
                isStartingSession = false
            } catch {
                errorMessage = "Failed to start co-op session: \(error.localizedDescription)"
                isStartingSession = false
                print("[CoopSetup] Error starting session: \(error)")
            }
        }
    }
    
    private func handleGuestAutoJoin() {
        print("[CoopSetup] Guest auto-join triggered")
        
        Task {
            // Give SharePlay a moment to fully establish
            try await Task.sleep(for: .milliseconds(300))
            
            guard let activity = coordinator.currentActivity else {
                errorMessage = "No session activity found"
                return
            }
            
            // Validate frame rate
            let guestFrameRate = viewModel.streamSettings.framerate
            if !coordinator.validateFrameRate(guestFrameRate) {
                let required = coordinator.getRequiredFrameRate() ?? 0
                errorMessage = "Frame rate mismatch! Host: \(required)fps, Yours: \(guestFrameRate)fps. Change your settings to match."
                return
            }
            
            // Import pairing data
            let dataManager = DataManager()
            guard let host = dataManager.importPairingData(
                activity.pairingData,
                address: activity.hostPCAddress,
                name: activity.hostPCName,
                coopTag: "Friend"
            ) else {
                errorMessage = "Failed to import host pairing data"
                return
            }
            
            // Find the app
            // If the host has apps, try to find matching app
            let app = TemporaryApp(id: activity.appID, name: activity.appName)
            app.maybeHost = host
            
            // Update ViewModel with co-op state
            viewModel.isCoopSession = true
            viewModel.assignedControllerSlot = 1  // Guest is slot 1 (player 2)
            
            // Small delay
            try await Task.sleep(for: .milliseconds(500))
            
            // Launch the stream
            await MainActor.run {
                isPresented = false
                launchCoopStream(app: app, host: host)
            }
        }
    }
    
    // MARK: - Stream Launch
    
    private func launchCoopStream(app: TemporaryApp, host: TemporaryHost) {
        // Configure the stream
        guard let config = viewModel.stream(app: app) else {
            errorMessage = "Failed to configure stream"
            return
        }
        
        let renderer = viewModel.streamSettings.renderer
        
        // Dismiss any existing streaming windows
        dismissWindow(id: "flatDisplayWindow")
        dismissWindow(id: "classicStreamingWindow")
        
        if renderer == .curvedDisplay {
            // Curved Display
            dismissWindow(id: "mainView")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task {
                    print("[CoopSetup] Opening curved display for co-op...")
                    _ = try await self.openImmersiveSpace(id: renderer.windowId, value: config)
                    self.viewModel.isImmersiveSpaceOpen = true
                }
            }
        } else {
            // Flat Display or Classic Display
            Task {
                if viewModel.isImmersiveSpaceOpen {
                    await dismissImmersiveSpace()
                    viewModel.isImmersiveSpaceOpen = false
                }
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.openWindow(id: renderer.windowId, value: config)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.dismissWindow(id: "mainView")
                    }
                }
            }
        }
    }
}

// MARK: - Co-op App Card

private struct CoopAppCard: View {
    let app: TemporaryApp
    let isSelected: Bool
    let onTap: () -> Void
    
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // App Icon/Thumbnail placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(app.id ?? "Unknown ID")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(brandViolet)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? brandViolet.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? brandViolet : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Error Types

