//
//  CoopSessionCoordinator.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import Foundation
import GroupActivities
import Combine

@MainActor
class CoopSessionCoordinator: ObservableObject {
    // MARK: - Published State
    
    @Published var isHosting: Bool = false
    @Published var isGuest: Bool = false
    @Published var assignedControllerSlot: Int = 0
    @Published var participants: [Participant] = []
    @Published var sessionActive: Bool = false
    @Published var currentActivity: MoonlightCoopActivity?
    @Published var friendJoinedNotification: Bool = false  // Triggers notification UI
    @Published var disconnectNotification: Bool = false  // Triggers disconnect notification UI
    @Published var disconnectMessage: String = ""  // "Guest Disconnected" or "Host Disconnected"
    
    // MARK: - Private Properties
    
    private var groupSession: GroupSession<MoonlightCoopActivity>?
    private var subscriptions = Set<AnyCancellable>()
    private var sessionTask: Task<Void, Never>?
    
    // Store pending sessions for the Join flow
    private var pendingSessions: [String: GroupSession<MoonlightCoopActivity>] = [:]
    
    // MARK: - Singleton
    
    static let shared = CoopSessionCoordinator()
    
    private init() {
        observeGroupSessions()
    }
    
    // MARK: - Session Management
    
    /// Start hosting a co-op session
    func startHosting(activity: MoonlightCoopActivity) async throws {
        print("[CoopCoordinator] ========== Starting host session ==========")
        print("[CoopCoordinator] App: \(activity.appName)")
        print("[CoopCoordinator] Session ID: \(activity.sessionID)")
        
        // Clear any existing session
        await endSession()
        print("[CoopCoordinator] Previous session ended")
        
        // Set as host and assign slot 0
        isHosting = true
        isGuest = false
        assignedControllerSlot = 0  // Host is slot 0 (player 1)
        currentActivity = activity
        print("[CoopCoordinator] State set: isHosting=true, slot=0")
        
        // IMPORTANT: Restart session observation BEFORE activating
        // so we receive our own session back for participant tracking
        observeGroupSessions()
        print("[CoopCoordinator] Session observation restarted")
        
        // Check if SharePlay is available before activating
        print("[CoopCoordinator] Checking if SharePlay is available...")
        let prepareResult = await activity.prepareForActivation()
        print("[CoopCoordinator] prepareForActivation() returned: \(prepareResult)")
        
        switch prepareResult {
        case .activationDisabled:
            print("[CoopCoordinator] ERROR: SharePlay is disabled - no FaceTime call")
            throw CoopError.noFaceTimeCall
        case .activationPreferred:
            print("[CoopCoordinator] SharePlay is available and preferred!")
        case .cancelled:
            print("[CoopCoordinator] ERROR: SharePlay activation was cancelled")
            throw CoopError.noFaceTimeCall
        @unknown default:
            print("[CoopCoordinator] Unknown prepareForActivation result")
        }
        
        // Activate the GroupActivity
        print("[CoopCoordinator] Calling activity.activate()...")
        let result = try await activity.activate()
        print("[CoopCoordinator] activity.activate() returned: \(result)")
        
        // Check if activation failed (no FaceTime call)
        if !result {
            print("[CoopCoordinator] ERROR: activity.activate() returned false - no FaceTime call detected")
            throw CoopError.noFaceTimeCall
        }
        
        print("[CoopCoordinator] Host session activated, waiting for guest...")
    }
    
    /// End the current co-op session
    func endSession() async {
        // Guard against redundant calls - don't restart listeners if already cleaned up
        guard sessionActive || groupSession != nil || isHosting || isGuest else {
            debugLog("[CoopCoordinator] endSession() called but already inactive - skipping")
            return
        }
        
        debugLog("[CoopCoordinator] Ending co-op session - isHosting: \(isHosting), isGuest: \(isGuest)")
        
        groupSession?.leave()
        debugLog("[CoopCoordinator] groupSession.leave() called")
        groupSession = nil
        
        isHosting = false
        isGuest = false
        assignedControllerSlot = 0
        sessionActive = false
        currentActivity = nil
        participants = []
        subscriptions.removeAll()
        
        // ALWAYS clear pending sessions - they become invalid after leave()
        // SharePlay will re-advertise active sessions when we start listening again
        pendingSessions.removeAll()
        print("[CoopCoordinator] Cleared pending sessions (session objects invalidated by leave())")
        
        // Restart background listener so we can discover sessions again
        // observeGroupSessions() handles cancelling any existing listener internally
        print("[CoopCoordinator] Restarting background session listener after disconnect")
        observeGroupSessions()
    }
    
    // MARK: - SharePlay Session Observation
    
    private func observeGroupSessions() {
        // Cancel any existing listener first to avoid duplicates
        sessionTask?.cancel()
        sessionTask = nil
        
        print("[CoopCoordinator] observeGroupSessions() - Starting background session listener")
        sessionTask = Task {
            print("[CoopCoordinator] Background listener: waiting for sessions...")
            for await session in MoonlightCoopActivity.sessions() {
                print("[CoopCoordinator] Background listener: *** SESSION RECEIVED *** App: \(session.activity.appName)")
                await handleNewSession(session)
            }
            print("[CoopCoordinator] Background listener: loop ended")
        }
    }
    
    private func handleNewSession(_ session: GroupSession<MoonlightCoopActivity>) async {
        print("[CoopCoordinator] New GroupSession received")
        
        let activity = session.activity
        
        // Determine if we're host or guest
        if isHosting {
            // We're the HOST - we started this session, join automatically
            print("[CoopCoordinator] We are HOST - auto-joining our own session")
            currentActivity = activity
            await actuallyJoinSession(session)
        } else {
            // We're a potential GUEST - don't auto-join!
            // Store the session for the Join UI to display
            print("[CoopCoordinator] We are GUEST - storing session for UI (not auto-joining)")
            print("[CoopCoordinator] Session available: \(activity.appName) on \(activity.hostPCName)")
            
            // Store in pendingSessions so CoopJoinView can display it
            pendingSessions[activity.sessionID] = session
            
            // Don't set isGuest or sessionActive yet - wait for user to click Join
            // But store the activity so UI can access it
            currentActivity = activity
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get the current frame rate from the activity (for guest to match)
    func getRequiredFrameRate() -> Int32? {
        return currentActivity?.hostFrameRate
    }
    
    /// Check if frame rate matches requirement
    func validateFrameRate(_ frameRate: Int32) -> Bool {
        guard let required = currentActivity?.hostFrameRate else { return true }
        return frameRate == required
    }
    
    /// Get pairing data for guest auto-pairing
    func getPairingData() -> Data? {
        return currentActivity?.pairingData
    }
    
    /// Get host PC connection info
    func getHostInfo() -> (address: String, port: UInt16, name: String)? {
        guard let activity = currentActivity else { return nil }
        return (activity.hostPCAddress, activity.hostPCPort, activity.hostPCName)
    }
    
    /// Get app info to launch
    func getAppInfo() -> (id: String, name: String)? {
        guard let activity = currentActivity else { return nil }
        return (activity.appID, activity.appName)
    }
    
    // MARK: - New Methods for Polished Flow
    
    /// Select the best address for connection (prefer local for fast same-network, external as fallback)
    func selectBestAddress(for host: TemporaryHost) -> String {
        // Prefer LOCAL address first - works instantly on same network
        // Remote users will fail fast on local and use external fallback in Moonlight's connection logic
        if let localAddr = host.localAddress, !localAddr.isEmpty {
            print("[CoopCoordinator] Using local address (preferred): \(localAddr)")
            return localAddr
        }
        
        // Fall back to active address
        if let activeAddr = host.activeAddress, !activeAddr.isEmpty {
            print("[CoopCoordinator] Using active address: \(activeAddr)")
            return activeAddr
        }
        
        // Fall back to external address for remote connections
        if let externalAddr = host.externalAddress, !externalAddr.isEmpty {
            print("[CoopCoordinator] Using external address (fallback): \(externalAddr)")
            return externalAddr
        }
        
        // Last resort: use address field
        print("[CoopCoordinator] Using fallback address: \(host.address ?? "unknown")")
        return host.address ?? ""
    }
    
    /// Check if host is internet accessible (has valid external IP)
    func isInternetAccessible(host: TemporaryHost) -> Bool {
        guard let externalAddr = host.externalAddress, !externalAddr.isEmpty else {
            return false
        }
        
        // Check if it's a valid external IP (not local)
        let isLocal = externalAddr.starts(with: "192.168.") ||
                      externalAddr.starts(with: "10.") ||
                      externalAddr.starts(with: "172.16.") ||
                      externalAddr == "127.0.0.1"
        
        return !isLocal
    }
    
    /// Observe available SharePlay sessions (for join view)
    func observeAvailableSessions() -> AsyncStream<[MoonlightCoopActivity]> {
        print("[CoopCoordinator] observeAvailableSessions() called - starting to listen for sessions")
        
        // Cancel background listener to avoid competing for sessions
        print("[CoopCoordinator] Cancelling background listener to avoid competition")
        sessionTask?.cancel()
        sessionTask = nil
        
        return AsyncStream { continuation in
            // First, yield any sessions already stored by the background listener
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.pendingSessions.isEmpty {
                    print("[CoopCoordinator] Found \(self.pendingSessions.count) existing pending sessions, yielding them")
                    let activities = Array(self.pendingSessions.values.map { $0.activity })
                    continuation.yield(activities)
                }
            }
            
            let task = Task { [weak self] in
                print("[CoopCoordinator] Starting MoonlightCoopActivity.sessions() iteration...")
                for await session in MoonlightCoopActivity.sessions() {
                    print("[CoopCoordinator] *** SESSION RECEIVED *** App: \(session.activity.appName)")
                    let activity = session.activity
                    
                    // Store the session so we can use it when user clicks Join
                    await MainActor.run {
                        self?.pendingSessions[activity.sessionID] = session
                        print("[CoopCoordinator] Stored pending session: \(activity.sessionID)")
                    }
                    
                    // Yield the activity for UI display
                    continuation.yield([activity])
                }
                print("[CoopCoordinator] MoonlightCoopActivity.sessions() iteration ended")
            }
            
            continuation.onTermination = { [weak self] _ in
                print("[CoopCoordinator] Session observation terminated")
                task.cancel()
                
                // Restart background listener when Join view closes
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("[CoopCoordinator] Restarting background listener after Join view closed")
                    self.observeGroupSessions()
                }
            }
        }
    }
    
    /// Join a stored pending session (called when user clicks Join)
    func joinPendingSession(_ activity: MoonlightCoopActivity) async throws {
        print("[CoopCoordinator] Attempting to join pending session: \(activity.sessionID)")
        
        guard let session = pendingSessions[activity.sessionID] else {
            print("[CoopCoordinator] ERROR: No pending session found for ID: \(activity.sessionID)")
            throw CoopError.hostNotFound
        }
        
        // Remove from pending
        pendingSessions.removeValue(forKey: activity.sessionID)
        
        // Set guest state
        isGuest = true
        isHosting = false
        assignedControllerSlot = 1  // Guest is slot 1 (player 2)
        currentActivity = activity
        
        // Actually join the session and set up observation
        await actuallyJoinSession(session)
        
        print("[CoopCoordinator] Successfully joined pending session")
    }
    
    /// Actually join a session and set up participant observation
    /// Called by host (auto) and guest (explicit click)
    private func actuallyJoinSession(_ session: GroupSession<MoonlightCoopActivity>) async {
        print("[CoopCoordinator] Actually joining session...")
        
        groupSession = session
        session.join()
        sessionActive = true
        
        // Observe participants
        session.$activeParticipants
            .sink { [weak self] activeParticipants in
                guard let self = self else { return }
                
                let oldCount = self.participants.count
                let newCount = activeParticipants.count
                
                // Protect against spurious 0-participant updates for hosts
                // The host should always count as at least 1 participant
                if self.isHosting && newCount == 0 && self.sessionActive {
                    print("[CoopCoordinator] Ignoring spurious 0-participant update for host")
                    return
                }
                
                // Convert to our simple Participant struct
                self.participants = activeParticipants.map { _ in Participant() }
                print("[CoopCoordinator] Active participants: \(newCount)")
                
                // Trigger notification when guest joins (count goes from 1 to 2 and we're hosting)
                if self.isHosting && oldCount == 1 && newCount == 2 {
                    print("[CoopCoordinator] Guest joined! Triggering notification")
                    self.friendJoinedNotification = true
                    
                    // Auto-dismiss notification after 3 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        await MainActor.run {
                            self.friendJoinedNotification = false
                        }
                    }
                    
                    // AGGRESSIVE IDR FRAME REQUESTING FOR GUEST
                    // Request IDR frames repeatedly to help guest connect faster
                    print("[CoopCoordinator] Starting aggressive IDR frame requests for guest")
                    Task {
                        // Request immediately
                        LiRequestIdrFrame()
                        
                        // Then request every 2 seconds for 10 seconds
                        for i in 1...5 {
                            try? await Task.sleep(for: .seconds(2))
                            print("[CoopCoordinator] IDR request #\(i) for guest")
                            LiRequestIdrFrame()
                        }
                        
                        print("[CoopCoordinator] Aggressive IDR requesting complete")
                    }
                }
                
                // Trigger notification when someone disconnects (count goes from 2 to 1)
                if oldCount == 2 && newCount == 1 {
                    if self.isHosting {
                        print("[CoopCoordinator] Guest disconnected! Host continues streaming as player 1/2")
                        self.disconnectMessage = "Guest Disconnected"
                        
                        // DO NOT activate a new activity here. The host should keep
                        // streaming normally on the existing session. Calling activate()
                        // on a new activity while already in an active SharePlay session
                        // triggers a system "Replace existing SharePlay activity?" dialog,
                        // which breaks the host's stream (frozen video on either choice).
                        // The host just keeps going as player 1 — the guest can rejoin
                        // via the existing FaceTime call's SharePlay session.
                    } else {
                        print("[CoopCoordinator] Host disconnected! Triggering notification")
                        self.disconnectMessage = "Host Disconnected"
                    }
                    
                    self.disconnectNotification = true
                    
                    // Auto-dismiss notification after 4 seconds (slightly longer for disconnect)
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run {
                            self.disconnectNotification = false
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
        // Observe session state
        session.$state
            .sink { [weak self] state in
                guard let self = self else { return }
                print("[CoopCoordinator] Session state: \(state)")
                if case .invalidated = state {
                    // Only auto-end session for guests
                    // Hosts should keep their session active so guests can rejoin
                    if self.isGuest {
                        print("[CoopCoordinator] Guest session invalidated - ending session")
                        Task { await self.endSession() }
                    } else if self.isHosting {
                        print("[CoopCoordinator] Host session invalidated - keeping session active for guest rejoin")
                        // Don't call endSession() - host can still invite/wait for guest
                    }
                }
            }
            .store(in: &subscriptions)
        
        print("[CoopCoordinator] Session joined and observers set up")
    }
    
    /// Join a session with timeout
    func joinSessionWithTimeout(_ activity: MoonlightCoopActivity, timeout: TimeInterval) async throws {
        print("[CoopCoordinator] Attempting to join session: \(activity.sessionID)")
        
        // Check if already in a session
        if sessionActive {
            throw CoopError.alreadyInSession
        }
        
        // Set guest state
        isGuest = true
        isHosting = false
        assignedControllerSlot = 1  // Guest is slot 1 (player 2)
        currentActivity = activity
        
        // Create timeout task
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            throw CoopError.connectionTimeout
        }
        
        // Create join task
        let joinTask = Task {
            // Wait for the session to be established
            for await session in MoonlightCoopActivity.sessions() {
                if session.activity.sessionID == activity.sessionID {
                    await handleNewSession(session)
                    return
                }
            }
        }
        
        // Race between timeout and join
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await timeoutTask.value }
                group.addTask { await joinTask.value }
                
                // Wait for first to complete
                try await group.next()
                
                // Cancel the other task
                timeoutTask.cancel()
                joinTask.cancel()
            }
        } catch {
            // Clean up on failure
            await endSession()
            throw error
        }
        
        print("[CoopCoordinator] Successfully joined session")
    }
    
    /// Check if we can start a new session (not already in one)
    func canStartNewSession() -> Bool {
        return !sessionActive
    }
    
    /// Re-invite a guest by re-activating the existing activity.
    /// We do NOT create a new activity/session ID because:
    /// 1. Creating a new activity triggers "Replace existing session?" dialog
    /// 2. Replacing tears down the SharePlay stack for everyone, causing crashes
    /// 3. The guest's stale view state is already fixed by .id(sessionUUID) on the view
    /// Re-activating the same activity just nudges SharePlay to re-broadcast it.
    func reInviteGuest() async {
        guard isHosting, let activity = currentActivity else {
            print("[CoopCoordinator] reInviteGuest() - not hosting or no activity, skipping")
            return
        }
        
        print("[CoopCoordinator] Re-inviting guest (re-activating existing session: \(activity.sessionID))")
        do {
            let result = try await activity.activate()
            print("[CoopCoordinator] Existing session re-activated: \(result)")
        } catch {
            print("[CoopCoordinator] Re-activation failed: \(error)")
        }
    }
    
    /// Suppress SharePlay system UI (call before activating)
    func suppressSystemUI() async {
        
        print("[CoopCoordinator] System UI suppression requested (placeholder)")
    }
}

// MARK: - Participant Helper

struct Participant: Identifiable, Hashable {
    let id: UUID
    
    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Error Types

enum CoopError: LocalizedError {
    case failedToExportPairing
    case frameRateMismatch
    case hostNotFound
    case connectionTimeout
    case hostUnreachable
    case portForwardingRequired
    case alreadyInSession
    case noFaceTimeCall
    
    var errorDescription: String? {
        switch self {
        case .failedToExportPairing:
            return "Failed to export pairing data"
        case .frameRateMismatch:
            return "Frame rate mismatch between host and guest"
        case .hostNotFound:
            return "Host not found"
        case .connectionTimeout:
            return "Pairing timed out. Host did not enter PIN within 2 minutes."
        case .hostUnreachable:
            return "Cannot reach host PC. Check network connection."
        case .portForwardingRequired:
            return "Port forwarding may be required for remote connections. Check ports 47984, 47989, 48010."
        case .alreadyInSession:
            return "Already in an active co-op session. Leave current session first."
        case .noFaceTimeCall:
            return "No Active FaceTime Call Detected."
        }
    }
}
