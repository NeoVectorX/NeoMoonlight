//
//  CoopJoinView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI
import GroupActivities

struct CoopJoinView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var coordinator = CoopSessionCoordinator.shared
    
    @Binding var isPresented: Bool
    @Binding var parentIsPresented: Bool  // To dismiss the entire co-op flow
    
    @State private var availableSessions: [MoonlightCoopActivity] = []
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var connectionProgress: String?
    @State private var selectedCoopBitrate: Int32 = 30000  // Default 30 Mbps
    
    // Brand colors
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandBlue, brandBlue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Join Co-op Session")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Select a session to join")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 48)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Session List or Empty State
            if isJoining {
                joiningView
            } else if availableSessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
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
                    .padding(.bottom, 32)
            }
        }
        .frame(width: 600, height: 800)
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
        .task {
            await observeSessions()
        }
        .onAppear {
            // Load last-used co-op bitrate from UserDefaults
            let savedBitrate = UserDefaults.standard.integer(forKey: "lastCoopBitrateGuest")
            if savedBitrate > 0 {
                selectedCoopBitrate = Int32(savedBitrate)
                print("[CoopJoin] Loaded saved co-op bitrate: \(selectedCoopBitrate / 1000) Mbps")
            } else {
                print("[CoopJoin] Using default co-op bitrate: 30 Mbps")
            }
        }
    }
    
    // MARK: - Session List View
    
    private var sessionListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Bitrate picker at top
                bitratePickerCard
                
                ForEach(availableSessions, id: \.sessionID) { session in
                    SessionCard(
                        session: session,
                        guestFrameRate: viewModel.streamSettings.framerate,
                        onJoin: { joinSession(session) },
                        onChangeSettings: { openSettings() }
                    )
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 500)
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
                UserDefaults.standard.set(Int(newValue), forKey: "lastCoopBitrateGuest")
                print("[CoopJoin] Saved co-op bitrate: \(newValue / 1000) Mbps")
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
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No sessions available")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Start a FaceTime call with a friend to join their co-op session.")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(40)
    }
    
    // MARK: - Joining View
    
    private var joiningView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(brandBlue)
            
            Text(connectionProgress ?? "Connecting...")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Host stream is ready!")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func observeSessions() async {
        print("[CoopJoin] Starting to observe sessions...")
        // Observe available SharePlay sessions
        for await sessions in coordinator.observeAvailableSessions() {
            print("[CoopJoin] Received \(sessions.count) sessions")
            await MainActor.run {
                availableSessions = sessions
            }
        }
        print("[CoopJoin] Session observation ended")
    }
    
    private func joinSession(_ session: MoonlightCoopActivity) {
        guard !isJoining else { return }
        
        // Auto-match frame rate to host's if different
        let guestFrameRate = viewModel.streamSettings.framerate
        if guestFrameRate != session.hostFrameRate {
            print("[CoopJoin] Auto-matching frame rate: \(guestFrameRate)fps -> \(session.hostFrameRate)fps")
            viewModel.streamSettings.framerate = session.hostFrameRate
        }
        
        isJoining = true
        errorMessage = nil
        connectionProgress = "Checking pairing status..."
        
        Task {
            do {
                // Join the SharePlay session first
                try await coordinator.joinPendingSession(session)
                
                // Check if already paired with this PC
                let existingHost = await checkIfAlreadyPaired(
                    address: session.hostPCAddress,
                    name: session.hostPCName
                )
                
                let host: TemporaryHost
                
                if let existingHost = existingHost {
                    // ✅ Already paired - update connection info from session
                    print("[CoopJoin] Already paired with \(session.hostPCName), updating connection info")
                    print("[CoopJoin] Mode: \(session.connectionMode), Address: \(session.hostPCAddress)")
                    
                    // Clean the address: Strip port if included (format: "IP:PORT")
                    let rawAddr = session.hostPCAddress
                    let cleanIP = rawAddr.components(separatedBy: ":").first ?? rawAddr
                    
                    // Use the cleaned IP for address fields
                    existingHost.address = cleanIP
                    existingHost.activeAddress = session.hostPCAddress  // Keep original for HTTP calls
                    existingHost.httpsPort = session.hostPCPort
                    connectionProgress = "Already paired - launching stream..."
                    host = existingHost
                } else {
                    // ❌ NOT paired - need PIN flow
                    print("[CoopJoin] Not paired - starting PIN flow")
                    connectionProgress = "Pairing with \(session.hostPCName)..."
                    
                    host = try await pairWithHostUsingPIN(
                        address: session.hostPCAddress,
                        name: session.hostPCName,
                        port: session.hostPCPort
                    )
                }
                
                // Create app reference
                let app = TemporaryApp(id: session.appID, name: session.appName)
                app.maybeHost = host
                
                // Update ViewModel with co-op state
                viewModel.isCoopSession = true
                viewModel.assignedControllerSlot = 1  // Guest is slot 1 (player 2)
                
                // Set co-op bitrate override before launching stream
                viewModel.coopBitrateOverride = selectedCoopBitrate
                print("[CoopJoin] Set co-op bitrate override: \(selectedCoopBitrate / 1000) Mbps")
                
                print("[CoopJoin] Launching stream...")
                connectionProgress = "Launching stream..."
                try await Task.sleep(for: .milliseconds(500))
                
                // Clear any stale state from the guest's previous stream
                // (cooldowns, stuck streamState, etc.) before launching
                debugLog("[CoopJoin] Calling prepareForNewStream before launch")
                viewModel.prepareForNewStream()
                
                debugLog("[CoopJoin] About to call launchCoopStream")
                let launched = await launchCoopStream(app: app, host: host)
                debugLog("[CoopJoin] launchCoopStream returned: \(launched)")
                
                if launched {
                    // launchCoopStream already waited for window to open
                    await MainActor.run {
                        isPresented = false
                        parentIsPresented = false
                    }
                } else {
                    // Stream failed to launch - don't dismiss the UI so user
                    // can see the error and try again. Clean up co-op state.
                    viewModel.isCoopSession = false
                    viewModel.assignedControllerSlot = 0
                    viewModel.coopBitrateOverride = nil
                }
                
                isJoining = false
            } catch CoopError.hostNotFound {
                errorMessage = "Session not found. The host may have cancelled."
                isJoining = false
                connectionProgress = nil
            } catch CoopError.connectionTimeout {
                errorMessage = "Pairing timed out. Host did not enter PIN in time."
                isJoining = false
                connectionProgress = nil
            } catch {
                errorMessage = "Failed to join: \(error.localizedDescription)"
                isJoining = false
                connectionProgress = nil
            }
        }
    }
    
    /// Check if guest is already paired with this PC
    /// Returns host only if it has a valid serverCert (actually paired, not just discovered)
    private func checkIfAlreadyPaired(address: String, name: String) async -> TemporaryHost? {
        return await withCheckedContinuation { continuation in
            // Check all saved hosts for matching address
            let dataManager = DataManager()
            guard let allHosts = dataManager.getHosts() else {
                print("[CoopJoin] No hosts found in database")
                continuation.resume(returning: nil)
                return
            }
            
            print("[CoopJoin] Checking \(allHosts.count) saved hosts for pairing")
            
            for host in allHosts {
                print("[CoopJoin] Checking host: \(host.name), address: \(host.address ?? "nil"), localAddress: \(host.localAddress ?? "nil"), serverCert: \(host.serverCert != nil ? "YES" : "NO")")
                
                // Match by address or name
                let addressMatch = host.address == address || 
                                   host.localAddress == address ||
                                   host.externalAddress == address ||
                                   host.name == name
                
                if addressMatch {
                    print("[CoopJoin] Address match found for \(name)")
                    
                    // Must have a valid serverCert to be considered "paired"
                    if host.serverCert != nil {
                        print("[CoopJoin] ✅ Host has valid serverCert - using existing pairing")
                        continuation.resume(returning: host)
                        return
                    } else {
                        print("[CoopJoin] ❌ Host has NO serverCert - not paired, will show PIN")
                    }
                }
            }
            
            print("[CoopJoin] No valid pairing found for \(name) - will show PIN prompt")
            continuation.resume(returning: nil)
        }
    }
    
    /// Pair with host using PIN flow
    private func pairWithHostUsingPIN(address: String, name: String, port: UInt16) async throws -> TemporaryHost {
        // Strip port from address if it's included (format: "IP:PORT")
        let cleanAddress = address.components(separatedBy: ":").first ?? address
        
        // HttpManager expects activeAddress in "IP:PORT" format for HTTP port (47989)
        let httpPort: UInt16 = 47989
        let activeAddressWithPort = "\(cleanAddress):\(httpPort)"
        
        print("[CoopJoin] Starting PIN pairing with \(name) at \(cleanAddress)")
        
        // Create temporary host for pairing
        let host = TemporaryHost()
        host.name = name
        host.address = cleanAddress
        host.activeAddress = activeAddressWithPort  // Format: "IP:47989" for HTTP
        host.localAddress = activeAddressWithPort
        host.httpsPort = port  // HTTPS port (47984)
        
        // Add host to viewModel.hosts so updateHost can save serverCert to database after pairing
        // This ensures the pairing persists and guest won't need PIN next time
        await MainActor.run {
            if !viewModel.hosts.contains(where: { $0.uuid == host.uuid }) {
                viewModel.hosts.append(host)
            }
            viewModel.tryPairHost(host)
        }
        
        // Wait for PIN to be generated (usually instant)
        let pin = try await waitForPIN(timeout: 5.0)
        
        print("[CoopJoin] PIN generated: \(pin)")
        connectionProgress = "PIN: \(pin)\n\nTell host to enter this PIN in Sunshine"
        
        // Poll for pairing approval (host enters PIN in Sunshine)
        let approved = try await waitForPairingApproval(host: host, timeout: 120.0)
        
        if approved {
            print("[CoopJoin] Pairing approved!")
            connectionProgress = "Pairing successful!"
            return host
        } else {
            print("[CoopJoin] Pairing timed out")
            throw CoopError.connectionTimeout
        }
    }
    
    /// Wait for PIN to be generated by PairManager
    private func waitForPIN(timeout: TimeInterval) async throws -> String {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let pin = await MainActor.run { viewModel.currentPin }
            if !pin.isEmpty {
                return pin
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        throw CoopError.connectionTimeout
    }
    
    /// Poll Sunshine to check if pairing was approved
    private func waitForPairingApproval(host: TemporaryHost, timeout: TimeInterval) async throws -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Check if pairing completed successfully
            let pairingComplete = await MainActor.run {
                !viewModel.pairingInProgress && host.serverCert != nil
            }
            
            if pairingComplete {
                return true
            }
            
            // Check if pairing failed
            let pairingFailed = await MainActor.run {
                !viewModel.pairingInProgress && host.serverCert == nil && viewModel.currentPin == nil
            }
            
            if pairingFailed {
                return false
            }
            
            // Wait 1 second before checking again
            try await Task.sleep(for: .seconds(1))
        }
        
        return false  // Timeout
    }
    
    private func openSettings() {
        // Navigate to settings to change frame rate
        // This opens the settings view
        print("[CoopJoin] Opening settings to change frame rate")
    }
    
    @discardableResult
    private func launchCoopStream(app: TemporaryApp, host: TemporaryHost) async -> Bool {
        // Configure the stream FIRST (creates new sessionUUID)
        guard let config = viewModel.stream(app: app) else {
            errorMessage = "Failed to configure stream"
            return false
        }
        
        let renderer = viewModel.streamSettings.renderer
        debugLog("[CoopJoin] launchCoopStream - renderer: \(renderer), sessionUUID: \(config.sessionUUID)")
        
        
        // Without this delay, the old view may still be alive when we open the new one,
        // causing "ghost" views that fight over C-level resources (StreamManager, audio).
        debugLog("[CoopJoin] Dismissing old windows...")
        dismissWindow(id: "flatDisplayWindow")
        dismissWindow(id: "classicStreamingWindow")
        if viewModel.isImmersiveSpaceOpen {
            await dismissImmersiveSpace()
            viewModel.isImmersiveSpaceOpen = false
        }
        
        // Wait 500ms for OS to fully tear down old window and release resources
        debugLog("[CoopJoin] Waiting 500ms for old window cleanup...")
        try? await Task.sleep(for: .milliseconds(500))
        debugLog("[CoopJoin] Wait complete, opening fresh window")
        
        // Now open the new window with the new config
        if renderer == .curvedDisplay {
            let result = try? await openImmersiveSpace(id: renderer.windowId, value: config)
            viewModel.isImmersiveSpaceOpen = true
            debugLog("[CoopJoin] Immersive space result: \(String(describing: result))")
        } else {
            openWindow(id: renderer.windowId, value: config)
            debugLog("[CoopJoin] Window opened: \(renderer.windowId)")
        }
        
        return true
    }
}

// MARK: - Session Card Component

private struct SessionCard: View {
    let session: MoonlightCoopActivity
    let guestFrameRate: Int32
    let onJoin: () -> Void
    let onChangeSettings: () -> Void
    
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    private var hasFrameRateMismatch: Bool {
        session.hostFrameRate != guestFrameRate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 28))
                    .foregroundColor(brandBlue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.hostPCName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(session.appName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(brandOrange)
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Connection Mode
            HStack(spacing: 8) {
                Text("Mode:")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(session.connectionMode)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(session.connectionMode == "Online" ? brandViolet : brandBlue)
            }
            
            // Frame Rate Info
            HStack(spacing: 8) {
                Text("Frame rate:")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("\(session.hostFrameRate)fps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                // Green checkmark to indicate compatibility
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            
            // Frame Rate Auto-Match Info
            if hasFrameRateMismatch {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brandBlue)
                    
                    Text("Your frame rate will be adjusted to \(session.hostFrameRate)fps")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(brandBlue.opacity(0.1))
                )
            }
            
            // Join Button
            Button {
                onJoin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                    Text("Join Session")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [brandBlue, brandBlue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    hasFrameRateMismatch ? Color.orange.opacity(0.5) : Color.white.opacity(0.1),
                    lineWidth: hasFrameRateMismatch ? 2 : 1
                )
        )
    }
}
