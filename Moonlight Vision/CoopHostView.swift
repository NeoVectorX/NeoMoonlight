//
//  CoopHostView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI
import GroupActivities

struct CoopHostView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var coordinator = CoopSessionCoordinator.shared
    
    let host: TemporaryHost
    @Binding var isPresented: Bool
    @Binding var parentIsPresented: Bool  // To dismiss the entire co-op flow
    
    @State private var selectedApp: TemporaryApp?
    @State private var isStartingSession = false
    @State private var errorMessage: String?
    @State private var selectedCoopBitrate: Int32 = 30000  // Default 30 Mbps
    @State private var showRemoteSetupHelp = false
    @State private var isHelpExpanded = false
    @State private var isOnlineMode = false
    
    // Brand colors
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 16) {
                // Header
                VStack(spacing: 10) {
                    Text("Host Co-op Session")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 100)
                .padding(.bottom, 0)
            
            // Content
            if coordinator.sessionActive && coordinator.isHosting {
                hostWaitingView
            } else {
                appSelectionView
            }
            
            Spacer()
                .allowsHitTesting(false)
        }
        .frame(width: 600, height: 860)
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
        .overlay(alignment: .topLeading) {
            // Back button in top-left corner
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(16)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .clipShape(Circle())
            .hoverEffect()
            .padding(.leading, 24)
            .padding(.top, 24)
        }
        .sheet(isPresented: $showRemoteSetupHelp) {
            remoteSetupHelpSheet
        }
        .onAppear {
            // Refresh host data to ensure app list is populated
            print("[CoopHost] View appeared, refreshing host data for: \(host.name)")
            Task {
                await viewModel.updateHost(host: host)
                // Also refresh the app list (critical for co-op host view)
                viewModel.refreshAppsFor(host: host)
            }
            
            // Load last-used co-op bitrate from UserDefaults
            let savedBitrate = UserDefaults.standard.integer(forKey: "lastCoopBitrate")
            if savedBitrate > 0 {
                selectedCoopBitrate = Int32(savedBitrate)
                print("[CoopHost] Loaded saved co-op bitrate: \(selectedCoopBitrate / 1000) Mbps")
            } else {
                print("[CoopHost] Using default co-op bitrate: 30 Mbps")
            }
        }
    }
    
    // MARK: - App Selection View
    
    private var appSelectionView: some View {
        VStack(spacing: 20) {
            // Connection Info Card
            connectionInfoCard
            
            Text("Select a co-op session to host")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            // Scrollable app list
            ScrollView {
                VStack(spacing: 12) {
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
            .frame(height: 220)
            
            // Connection Type
            connectionTypeCard
            
            // Bitrate Picker
            bitratePickerCard
            
            // Start button
            VStack(spacing: 0) {
                Button(action: {
                    print("[CoopHost] BUTTON TAPPED!")
                    startCoopSession()
                }) {
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
                .buttonStyle(ScaleButtonStyle())
                .disabled(selectedApp == nil || isStartingSession)
                .opacity(selectedApp == nil ? 0.5 : 1.0)
                
                // Error message with fixed reserved space
                VStack {
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }
                .frame(height: 40)
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Connection Info Card
    
    private var connectionInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .semibold))
                Text("Connection Info")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // PC Name
            HStack {
                Text("🖥️ \(host.name)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Combined Local and External Address on one line
            HStack(spacing: 12) {
                // Local Address
                if let localAddr = host.localAddress {
                    HStack(spacing: 4) {
                        Text("Local:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                        Text(localAddr)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                
                // External Address
                if let externalAddr = host.externalAddress, !externalAddr.isEmpty {
                    HStack(spacing: 4) {
                        Text("External:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                        Text(externalAddr)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("External:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Not detected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        // Help button
                        Button {
                            showRemoteSetupHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Network reminder
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                Text("For online co-op, see User Guide for network setup")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - Connection Type Card
    
    private var connectionTypeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Type")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Button {
                    isOnlineMode = false
                } label: {
                    Text("Local")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isOnlineMode ? Color.white.opacity(0.1) : brandViolet.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .hoverEffect()
                
                Button {
                    isOnlineMode = true
                } label: {
                    Text("Online")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isOnlineMode ? brandViolet.opacity(0.6) : Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 24)
    }
    
    // MARK: - Bitrate Picker Card
    
    private var bitratePickerCard: some View {
        HStack {
            Text("Co-op Mode Bitrate")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Picker("", selection: $selectedCoopBitrate) {
                Text("25 Mbps").tag(Int32(25000))
                Text("30 Mbps").tag(Int32(30000))
                Text("50 Mbps").tag(Int32(50000))
                Text("75 Mbps").tag(Int32(75000))
                Text("100 Mbps").tag(Int32(100000))
                Text("120 Mbps").tag(Int32(120000))
                Text("150 Mbps").tag(Int32(150000))
            }
            .pickerStyle(.menu)
            .contentShape(Rectangle())
            .hoverEffect()
            .onChange(of: selectedCoopBitrate) { _, newValue in
                UserDefaults.standard.set(Int(newValue), forKey: "lastCoopBitrate")
                print("[CoopHost] Saved co-op bitrate: \(newValue / 1000) Mbps")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 24)
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
                            .fill(brandViolet.opacity(0.15))
                    )
            }
        }
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func startCoopSession() {
        print("[CoopHost] ========== startCoopSession called ==========")
        guard let app = selectedApp else {
            print("[CoopHost] ERROR: No app selected")
            return
        }
        guard !isStartingSession else {
            print("[CoopHost] ERROR: Already starting session")
            return
        }
        
        print("[CoopHost] Starting session for app: \(app.name)")
        isStartingSession = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                // Force 90 FPS for co-op compatibility (M2 Vision Pro max)
                let frameRate: Int32 = 90
                print("[CoopHost] Co-op frame rate locked to 90 FPS for M2 compatibility")
                
                // Export pairing data for sharing
                print("[CoopHost] Exporting pairing data...")
                let dataManager = DataManager()
                guard let pairingData = dataManager.exportPairingData(for: host) else {
                    print("[CoopHost] ERROR: Failed to export pairing data")
                    throw CoopError.failedToExportPairing
                }
                print("[CoopHost] Pairing data exported successfully")
                
                // Use IP based on connection mode toggle
                let targetAddress: String
                if isOnlineMode {
                    guard let external = host.externalAddress, !external.isEmpty else {
                        errorMessage = "No external IP available for Online mode"
                        isStartingSession = false
                        return
                    }
                    targetAddress = external
                    print("[CoopHost] Online mode - using external IP: \(targetAddress)")
                } else {
                    guard let local = host.localAddress, !local.isEmpty else {
                        errorMessage = "No local IP available"
                        isStartingSession = false
                        return
                    }
                    targetAddress = local
                    print("[CoopHost] Local mode - using local IP: \(targetAddress)")
                }
                
                let isInternetAccessible = coordinator.isInternetAccessible(host: host)
                
                // Create activity with connection info (but DON'T activate yet!)
                let activity = MoonlightCoopActivity(
                    hostPCAddress: targetAddress,
                    hostPCName: host.name,
                    hostPCPort: host.httpsPort,
                    isInternetAccessible: isInternetAccessible,
                    connectionMode: isOnlineMode ? "Online" : "Local",
                    appID: app.id ?? app.name,
                    appName: app.name,
                    sessionID: UUID().uuidString,
                    hostFrameRate: frameRate,
                    pairingData: pairingData
                )
                print("[CoopHost] Activity created (NOT activated yet - waiting for first frame)")
                
                // Update ViewModel with co-op state
                viewModel.isCoopSession = true
                viewModel.assignedControllerSlot = 0  // Host is slot 0 (player 1)
                
                // Set co-op bitrate override before launching stream
                viewModel.coopBitrateOverride = selectedCoopBitrate
                print("[CoopHost] Set co-op bitrate override: \(selectedCoopBitrate / 1000) Mbps")
                
                // STEP 1: Wait for any previous teardown to complete before starting
                if viewModel.streamState != .idle {
                    print("[CoopHost] Waiting for previous stream teardown to complete (state: \(viewModel.streamState.rawValue))...")
                    for _ in 0..<100 {  // Up to 10 seconds
                        try? await Task.sleep(for: .milliseconds(100))
                        if viewModel.streamState == .idle { break }
                    }
                    if viewModel.streamState != .idle {
                        print("[CoopHost] ERROR: Timed out waiting for previous stream to finish teardown")
                        errorMessage = "Previous stream is still shutting down. Please try again."
                        isStartingSession = false
                        return
                    }
                    print("[CoopHost] Previous teardown complete, proceeding with stream launch")
                }
                
                // STEP 2: Launch the stream FIRST (before SharePlay activation)
                print("[CoopHost] Launching stream FIRST (before SharePlay)...")
                let streamStarted = launchCoopStream(app: app, host: host)
                
                guard streamStarted else {
                    print("[CoopHost] ERROR: Failed to start stream")
                    errorMessage = "Failed to start stream. Please try again."
                    isStartingSession = false
                    viewModel.isCoopSession = false
                    viewModel.coopBitrateOverride = nil
                    return
                }
                
                // Wait a moment for the stream window to open
                try? await Task.sleep(for: .milliseconds(300))
                
                // Dismiss the co-op flow UI so user sees the stream
                isPresented = false
                parentIsPresented = false
                
                // STEP 2: Wait for first frame before activating SharePlay
                // This ensures the guest won't see the session until host stream is working
                print("[CoopHost] Waiting for first frame before activating SharePlay...")
                let firstFrameReceived = await waitForFirstFrame(timeout: 30.0)
                
                if firstFrameReceived {
                    print("[CoopHost] First frame received! Now activating SharePlay...")
                    
                    // STEP 3: NOW activate SharePlay - guest will see session only after stream is working
                    try await coordinator.startHosting(activity: activity)
                    print("[CoopHost] SharePlay activated - session now visible to guest!")
                } else {
                    print("[CoopHost] WARNING: First frame timeout, activating SharePlay anyway")
                    // Still activate SharePlay, but warn that timing might not be ideal
                    try await coordinator.startHosting(activity: activity)
                }
                
                isStartingSession = false
                print("[CoopHost] ========== Session started successfully! ==========")
            } catch {
                print("[CoopHost] ========== ERROR ==========")
                print("[CoopHost] Error: \(error)")
                print("[CoopHost] Error description: \(error.localizedDescription)")
                errorMessage = "Failed: \(error.localizedDescription)"
                isStartingSession = false
            }
        }
    }
    
    /// Wait for the first frame notification with a timeout
    /// Returns true if first frame was received, false if timeout
    private func waitForFirstFrame(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            var observer1: NSObjectProtocol?
            var observer2: NSObjectProtocol?
            var timeoutTask: DispatchWorkItem?
            var resumed = false
            
            let cleanup = {
                if let obs = observer1 { NotificationCenter.default.removeObserver(obs) }
                if let obs = observer2 { NotificationCenter.default.removeObserver(obs) }
                timeoutTask?.cancel()
            }
            
            // Listen for RealityKit first frame (Curved Display)
            observer1 = NotificationCenter.default.addObserver(
                forName: Notification.Name("RKStreamFirstFrameShown"),
                object: nil,
                queue: .main
            ) { _ in
                guard !resumed else { return }
                resumed = true
                print("[CoopHost] Received RKStreamFirstFrameShown notification")
                cleanup()
                continuation.resume(returning: true)
            }
            
            // Listen for UIKit first frame (Flat Display)
            observer2 = NotificationCenter.default.addObserver(
                forName: Notification.Name("StreamFirstFrameShownNotification"),
                object: nil,
                queue: .main
            ) { _ in
                guard !resumed else { return }
                resumed = true
                print("[CoopHost] Received StreamFirstFrameShownNotification")
                cleanup()
                continuation.resume(returning: true)
            }
            
            // Timeout fallback
            timeoutTask = DispatchWorkItem {
                guard !resumed else { return }
                resumed = true
                print("[CoopHost] First frame wait timed out after \(timeout)s")
                cleanup()
                continuation.resume(returning: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutTask!)
        }
    }
    
    // MARK: - Stream Launch
    
    @discardableResult
    private func launchCoopStream(app: TemporaryApp, host: TemporaryHost) -> Bool {
        // Configure the stream
        guard let config = viewModel.stream(app: app) else {
            errorMessage = "Failed to configure stream"
            return false
        }
        
        let renderer = viewModel.streamSettings.renderer
        
        // Dismiss any existing streaming windows
        dismissWindow(id: "flatDisplayWindow")
        dismissWindow(id: "classicStreamingWindow")
        
        print("[CoopHost] Opening stream with renderer: \(renderer), windowId: \(renderer.windowId)")
        
        if renderer == .curvedDisplay {
            Task {
                let result = try? await openImmersiveSpace(id: renderer.windowId, value: config)
                print("[CoopHost] Immersive space result: \(String(describing: result))")
            }
        } else {
            openWindow(id: renderer.windowId, value: config)
            print("[CoopHost] Window opened: \(renderer.windowId)")
        }
        return true
    }
    
    // MARK: - Remote Setup Help Sheet
    
    private var remoteSetupHelpSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(brandOrange)
                
                Text("Remote Co-op Setup")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showRemoteSetupHelp = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Warning message
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your router is blocking remote connections")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Your guest needs to connect to your gaming PC from the internet.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.15))
                    )
                    
                    // Step 1: Automatic (UPnP)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            Text("Step 1: Try Automatic (UPnP)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Most modern routers handle this automatically.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            helpStep(number: "1", text: "Open Sunshine Web UI on your PC")
                            helpStep(number: "2", text: "Go to Configuration → Network")
                            helpStep(number: "3", text: "Enable \"UPnP\" (if not already on)")
                            helpStep(number: "4", text: "Restart Sunshine")
                            helpStep(number: "5", text: "Return here and check if External IP shows ✅ green")
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    
                    // Expandable Manual Setup
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isHelpExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.orange)
                                
                                Text("Step 2: Manual Setup (If needed)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Image(systemName: isHelpExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if isHelpExpanded {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Only if Step 1 didn't work:")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                // Port forwarding info
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Forward these ports on your router:")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    portRangeRow(protocol: "TCP", ports: "47984-47990, 48000-48010")
                                    portRangeRow(protocol: "UDP", ports: "47998-48010")
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                )
                                
                                // How to forward ports
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundColor(brandBlue)
                                        Text("How to forward ports:")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    helpStep(number: "1", text: "Find your router IP (usually on a sticker on the router)")
                                    
                                    Text("   Common: 192.168.1.1 or 192.168.0.1")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.5))
                                        .padding(.leading, 28)
                                    
                                    helpStep(number: "2", text: "Log into router admin page in a web browser")
                                    helpStep(number: "3", text: "Look for \"Port Forwarding\" section")
                                    
                                    if let localIP = host.localAddress {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("4")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(brandBlue)
                                                .frame(width: 20)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Forward ports to your PC's local IP:")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.white.opacity(0.8))
                                                
                                                Text(localIP)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(brandOrange)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(brandOrange.opacity(0.15))
                                                    )
                                            }
                                        }
                                    } else {
                                        helpStep(number: "4", text: "Forward ports to your PC's local IP address")
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    
                    // Security tip
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.purple)
                            Text("Security Tip")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Consider using Tailscale or ZeroTier for a more secure connection instead of port forwarding.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.1))
                    )
                }
                .padding(28)
            }
            
            // Close button
            Button {
                showRemoteSetupHelp = false
            } label: {
                Text("Close")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(brandOrange)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 550, height: 700)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func helpStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(brandBlue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func portRangeRow(protocol protocolName: String, ports: String) -> some View {
        HStack(spacing: 12) {
            Text(protocolName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(brandOrange)
                .frame(width: 40, alignment: .leading)
            
            Text(ports)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - App Card Component

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
        .hoverEffect()
    }
}
