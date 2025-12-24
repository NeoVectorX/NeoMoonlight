//
//  MainViewModel.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import Foundation
import OrderedCollections
import VideoToolbox
import AVFoundation
import SwiftUI

// Centralized lifecycle state for serialized stream operations
enum StreamLifecycleState: String {
    case idle
    case starting
    case running
    case stopping
}

// NOTE: Renderer enum is assumed to be defined in TemporarySettings.swift or similar.
// If missing, uncomment this:
// enum Renderer: Codable, CaseIterable {
//     case classicMetal
//     case curvedDisplay
// }

@MainActor
class MainViewModel: NSObject, ObservableObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    @objc
    static let shared = MainViewModel()

    @Published var hosts: [TemporaryHost] = []

    @Published var pairingInProgress = false
    @Published var currentPin = ""

    @Published var errorAddingHost = false
    @Published var addHostErrorMessage = ""

    @Published var currentStreamConfig = StreamConfiguration()
    @Published var activelyStreaming = false
    @Published var streamSettings: TemporarySettings
    
    @Published var currentlyStreamingAppId: String? = nil
    
    @Published var savedStreamWindowSize: CGSize? = nil
    @Published var classicWindowNeedsManualClose: Bool = false
    @Published var realityWindowNeedsManualClose: Bool = false

    @Published var shouldCloseStream = false

    @Published var volumeSliderValue: Float = 1.0

    // Central lifecycle state
    @Published var streamState: StreamLifecycleState = .idle

    @Published var isMainViewVisible: Bool = false

    @Published var vol: Float = 127
    @Published var mute: Bool = false

    @Published var reconnectCooldownUntil: Date? = nil
    
    @Published var isSwappingRenderers: Bool = false

    private var lastSwapAt: Date? = nil
    private let minSwapInterval: TimeInterval = 1.2

    private var dataManager: DataManager
    private var discoveryManager: DiscoveryManager? = nil
    private var appManager: AppAssetManager?
    private var boxArtCache: NSCache<TemporaryApp, UIImage>
    private var clientCert: Data
    private var uniqueId: String

    private var opQueue = OperationQueue()
    private var currentlyPairingHost: TemporaryHost?

    override init() {
        print("INITING MAIN MODEL")
        boxArtCache = NSCache<TemporaryApp, UIImage>()
        dataManager = DataManager()
        CryptoManager.generateKeyPairUsingSSL()
        clientCert = CryptoManager.readCertFromFile()
        uniqueId = IdManager.getUniqueId()
        streamSettings = dataManager.getSettings()

        super.init()
        appManager = AppAssetManager(callback: self)
        discoveryManager = DiscoveryManager(hosts: hosts, andCallback: self)

        // Observe first-frame and teardown events to drive lifecycle state
        let center = NotificationCenter.default

        center.addObserver(forName: Notification.Name("StreamFirstFrameShownNotification"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                print("[Lifecycle] First frame shown (UIKit). streamState -> running")
                self.streamState = .running
            }
        }

        center.addObserver(forName: Notification.Name("RKStreamFirstFrameShown"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                print("[Lifecycle] First frame shown (RealityKit). streamState -> running")
                self.streamState = .running
            }
        }

        center.addObserver(forName: Notification.Name("StreamDidTeardownNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.onTeardownComplete()
        }

        center.addObserver(forName: Notification.Name("RKStreamDidTeardown"), object: nil, queue: .main) { [weak self] _ in
            self?.onTeardownComplete()
        }
    }
    
    private func onTeardownComplete() {
        Task { @MainActor in
            guard streamState == .stopping else {
                print("[Lifecycle] Ignoring teardown notification because state is not 'stopping' (current: \(streamState.rawValue))")
                return
            }
            print("[Lifecycle] Teardown observed. streamState -> idle")
            self.shouldCloseStream = false
            self.currentlyStreamingAppId = nil
            self.streamState = .idle
            
            // If we are not in a swap operation, the disconnect is complete.
            if !self.isSwappingRenderers {
                self.activelyStreaming = false
            }
        }
    }
    
    var hostsWithPairState: [TemporaryHost] {
        let filteredHosts = hosts.filter { host in
            let isPaired = host.pairState == .paired
            let isUnpaired = host.pairState == .unpaired
            return isPaired || isUnpaired
        }
        return filteredHosts
    }
    
    // MARK: - Host Management Logic
    
    func upsertDiscoveredHosts(_ discoveredHosts: [TemporaryHost]) {
        for discoveredHost in discoveredHosts {
            if let existingHost = hosts.first(where: { $0.uuid == discoveredHost.uuid }) {
                existingHost.state = discoveredHost.state
                existingHost.name = discoveredHost.name
                existingHost.address = discoveredHost.address
                existingHost.localAddress = discoveredHost.localAddress
                existingHost.externalAddress = discoveredHost.externalAddress
                existingHost.ipv6Address = discoveredHost.ipv6Address

                if !existingHost.updatePending {
                    Task {
                        await updateHost(host: existingHost)
                    }
                }
            } else {
                print("Discovered a new host, adding to list: \(discoveredHost.name)")
                hosts.append(discoveredHost)
                Task {
                    await updateHost(host: discoveredHost, force: true)
                }
            }
        }
    }

    func removeHost(_ hostToRemove: TemporaryHost) {
        print("removeHost - START - Attempting to remove host: \(hostToRemove.name), UUID: \(hostToRemove.uuid), Current hosts count: \(hosts.count)")
        if hosts.contains(hostToRemove) {
            print("removeHost - Host found. Removing...")
            discoveryManager?.removeHost(fromDiscovery: hostToRemove)
            dataManager.remove(hostToRemove)
            hosts.removeAll(where: { $0 == hostToRemove })
            print("removeHost - Host removed. Current hosts count: \(hosts.count)")
            print("removeHost - END - Host removed successfully")
        } else {
            print("removeHost - Warning: Attempted to remove host \(hostToRemove.name) (UUID: \(hostToRemove.uuid)) but it was NOT found in the hosts list.")
            print("removeHost - END - Host not found, not removed")
        }
    }


    func wakeHost(_ host: TemporaryHost) {
        WakeOnLanManager.wake(host)
    }

    // MARK: - App Icons

    nonisolated func receivedAsset(for app: TemporaryApp!) {
        // pass
    }

    // MARK: - Pairing

    func manuallyDiscoverHost(hostOrIp: String) {
        discoveryManager?.discoverHost(hostOrIp, withCallback: hostMaybeFound)
    }

    nonisolated func hostMaybeFound(host: TemporaryHost?, error: String?) {
        Task { @MainActor in
            if let host {
                print("Discovered host: \(host.name)")
                self.upsertDiscoveredHosts([host])
            } else {
                print("Error discovering host: \(error ?? "Unknown error")")
                self.errorAddingHost = true
                self.addHostErrorMessage = error ?? "Unknown Error"
            }
        }
    }

    func tryPairHost(_ host: TemporaryHost) {
        discoveryManager?.stopDiscoveryBlocking()
        let httpManager = HttpManager(host: host)
        let pairManager = PairManager(manager: httpManager, clientCert: clientCert, callback: self)
        opQueue.addOperation(pairManager!)
        currentlyPairingHost = host
        print("trying to pair")
    }

    nonisolated func startPairing(_ PIN: String!) {
        Task { @MainActor in
            pairingInProgress = true
            currentPin = PIN
        }
        print("startPairing - Pairing started with PIN: \(PIN ?? "N/A")")
    }

    nonisolated func pairSuccessful(_ serverCert: Data!) {
        Task { @MainActor in
            if let pairingHost = currentlyPairingHost {
                print("pairSuccessful - Pairing successful for host: \(pairingHost.name)")
                pairingHost.serverCert = serverCert
                await updateHost(host: pairingHost, force: true)
            } else {
                print("pairSuccessful - Warning: currentlyPairingHost is nil.")
            }
            endPairing()
        }
    }

    nonisolated func pairFailed(_ message: String!) {
        Task { @MainActor in
            print("pairFailed - Pairing failed for host: \(currentlyPairingHost?.name ?? "Unknown"). Reason: \(message ?? "Unknown error")")
            endPairing()
        }
    }

    nonisolated func alreadyPaired() {
        Task { @MainActor in
            print("alreadyPaired - Host \(currentlyPairingHost?.name ?? "Unknown") is already paired.")
            if let host = currentlyPairingHost {
                if host.pairState != .paired {
                    host.pairState = .paired
                    print("alreadyPaired - Corrected host pairState to paired.")
                }
                await updateHost(host: host, force: true)
            }
            endPairing()
        }
    }

    nonisolated func endPairing() {
        Task { @MainActor in
            pairingInProgress = false
            currentPin = ""
            currentlyPairingHost = nil

            discoveryManager?.startDiscovery()
            print("endPairing - Pairing process finished, discovery starting.")

            do {
                try await Task.sleep(for: .seconds(5))
                discoveryManager?.stopDiscovery()
                print("endPairing - Discovery stopped after 5 seconds.")
            } catch {
                print("endPairing - Sleep task cancelled, discovery stop might have been skipped.")
            }
        }
    }

    // MARK: - Host & App Data Sync

    func updateHost(host: TemporaryHost, force: Bool = false) async {
        guard force || host.state != .offline else {
            print("updateHost: Host \(host.name) is marked offline and force is false. Skipping request.")
            await MainActor.run {
                if host.updatePending { host.updatePending = false }
            }
            return
        }

        print("updateHost: Proceeding with server info request for \(host.name). State: \(host.state), Force: \(force)")

        let httpManager = HttpManager(host: host)
        
        await MainActor.run {
            discoveryManager?.pauseDiscovery(for: host)
            host.updatePending = true
        }

        let serverInfoResponse = ServerInfoResponse()
        let request = HttpRequest(for: serverInfoResponse, with: httpManager?.newServerInfoRequest(false), fallbackError: 401, fallbackRequest: httpManager?.newHttpServerInfoRequest())

        print("Executing server info request for host: \(host.name) at \(host.activeAddress ?? host.address ?? "N/A")")
        
        await Task.detached {
            httpManager?.executeRequestSynchronously(request)
        }.value

        await MainActor.run {
            host.updatePending = false

            guard hosts.contains(where: { $0.uuid == host.uuid }) else {
                print("updateHost: Host \(host.name) (UUID: \(host.uuid)) no longer in list after request. Discarding result.")
                discoveryManager?.resumeDiscovery(for: host)
                return
            }

            if serverInfoResponse.isStatusOk() {
                print("Successfully updated host: \(host.name). Populating host data.")
                if host.state != .online {
                    print("updateHost: Host \(host.name) was previously \(host.state), setting to Online after successful update.")
                    host.state = .online
                }
                serverInfoResponse.populateHost(host)
                dataManager.update(host)
            } else {
                print("Failed to update host: \(host.name) during server info request. Error: \(serverInfoResponse.statusMessage ?? "unknown error"). Setting state to offline.")
                if host.state != .offline {
                    host.state = .offline
                }
            }
            discoveryManager?.resumeDiscovery(for: host)
        }
    }

    func refreshAppsFor(host: TemporaryHost) {
        print("refreshAppsFor - Refreshing apps for host: \(host.name)")
        discoveryManager?.pauseDiscovery(for: host)
        let appListResponse = ConnectionHelper.getAppList(for: host)
        discoveryManager?.resumeDiscovery(for: host)
        if appListResponse?.isStatusOk() == true {
            let serverApps = (appListResponse!.getAppList() as! Set<TemporaryApp>)
            print("refreshAppsFor - Received \(serverApps.count) apps from server.")

            var newAppList = OrderedSet<TemporaryApp>()
            for serverApp in serverApps {
                var matchFound = false
                for oldApp in host.appList {
                    if serverApp.id == oldApp.id {
                        oldApp.name = serverApp.name
                        oldApp.hdrSupported = serverApp.hdrSupported
                        oldApp.setHost(host)
                        matchFound = true
                        newAppList.append(oldApp)
                        break
                    }
                }
                if !matchFound {
                    serverApp.setHost(host)
                    newAppList.append(serverApp)
                }
            }

            let removedApps = host.appList.subtracting(newAppList)
            if !removedApps.isEmpty {
                print("refreshAppsFor - Removing \(removedApps.count) apps no longer present on server.")
                let database = DataManager()
                for removedApp in removedApps {
                    database.remove(removedApp)
                }
                database.updateApps(forExisting: host)
            }

            if host.appList != newAppList {
                print("refreshAppsFor - App list changed. Updating host.")
                host.appList = newAppList
            } else {
                print("refreshAppsFor - App list unchanged.")
            }

        } else {
            print("refreshAppsFor - Failed to retrieve app list for host: \(host.name). Status: \(appListResponse?.statusMessage ?? "Unknown error")")
            host.state = .offline
        }
    }

    // MARK: - Host Discovery

    func loadSavedHosts() {
        if let savedHosts = dataManager.getHosts() as? [TemporaryHost] {
            print("Loaded saved hosts: \(savedHosts.count)")
            self.hosts = savedHosts
        } else {
            print("Unable to fetch saved hosts")
        }

        for host in hosts {
            if host.activeAddress == nil {
                host.activeAddress = host.localAddress
            }
            if host.activeAddress == nil {
                host.activeAddress = host.externalAddress
            }
            if host.activeAddress == nil {
                host.activeAddress = host.address
            }
            if host.activeAddress == nil {
                host.activeAddress = host.ipv6Address
            }
        }
    }
    
    nonisolated func updateAllHosts(_ newHosts: [Any]!) {
        if let newHosts = newHosts as? [TemporaryHost] {
            Task { @MainActor in
                self.upsertDiscoveredHosts(newHosts)
            }
        }
    }
      
    @objc func beginRefresh() {
        discoveryManager?.resetDiscoveryState()
        discoveryManager?.startDiscovery()
    }
      
    func stopRefresh() {
        discoveryManager?.stopDiscovery()
    }
      
    // MARK: - Stream Control

    func stream(app: TemporaryApp) -> StreamConfiguration? {
        guard canStartNewStream() else {
            print("stream - Cannot start new stream - system not ready")
            return nil
        }
        
        let config = StreamConfiguration()

        guard let host = app.host() else {
            print("stream - ERROR: App \(app.name) has no associated host.")
            return nil
        }

        print("stream - Preparing stream configuration for app: \(app.name) on host: \(host.name)")

        print("[Lifecycle] stream(app:) invoked. streamState -> starting")
        streamState = .starting

        config.host = host.activeAddress ?? host.address
        if config.host == nil {
            print("stream - ERROR: Host \(host.name) has no valid address (activeAddress or address).")
            return nil
        }

        config.httpsPort = host.httpsPort
        config.appID = app.id
        config.appName = app.name
        config.serverCert = host.serverCert
        if config.serverCert == nil {
            print("stream - WARNING: Host \(host.name) has no server certificate. Streaming might fail if pairing is required.")
        }

        config.frameRate = streamSettings.framerate
        config.height = streamSettings.height
        config.width = streamSettings.width
        config.bitRate = streamSettings.bitrate
        config.optimizeGameSettings = streamSettings.optimizeGames
        config.playAudioOnPC = streamSettings.playAudioOnPC
        config.useFramePacing = streamSettings.useFramePacing
        config.swapABXYButtons = streamSettings.swapABXYButtons
        config.multiController = streamSettings.multiController
        config.gamepadMask = ControllerSupport.getConnectedGamepadMask(config, settings: streamSettings)
        config.audioConfiguration = (0x63f << 16) | (8 << 8) | 0xca // 7.1 Surround
        config.serverCodecModeSupport = host.serverCodecModeSupport

        let AV1_MAIN8: Int32 = 0x1000
        let AV1_MAIN10: Int32 = 0x2000
        let H265: Int32 = 0x0100
        let H264: Int32 = 0x0001
        let H265_MAIN10: Int32 = 0x0200

        let av1_supported = VideoToolbox.VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        let hevc_supported = VideoToolbox.VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let hdr10_supported = AVPlayer.availableHDRModes.contains(AVPlayer.HDRMode.hdr10)

        config.supportedVideoFormats = 0

        // Respect Preferred Codec selection strictly (except Auto)
        switch streamSettings.preferredCodec {
        case .av1 where av1_supported:
            config.supportedVideoFormats |= AV1_MAIN8
            print("stream - Preferred codec: AV1 (Main8)")
        case .hevc where hevc_supported:
            config.supportedVideoFormats |= H265
            print("stream - Preferred codec: HEVC")
        case .h264:
            config.supportedVideoFormats |= H264
            print("stream - Preferred codec: H.264")
        case .auto:
            if av1_supported { config.supportedVideoFormats |= AV1_MAIN8; print("stream - Auto: Adding AV1_MAIN8") }
            if hevc_supported { config.supportedVideoFormats |= H265; print("stream - Auto: Adding H265") }
            config.supportedVideoFormats |= H264
            print("stream - Auto: Adding H264 (fallback)")
        default:
            if hevc_supported { config.supportedVideoFormats |= H265; print("stream - Default: Adding H265") }
            config.supportedVideoFormats |= H264
            print("stream - Default: Adding H264 (fallback)")
        }

        // Only add HDR/10-bit variants for the selected codec (Auto adds all)
        if streamSettings.enableHdr || config.width > 4096 || config.height > 4096 {
            switch streamSettings.preferredCodec {
            case .auto:
                // Auto: Allow all compatible HDR variants
                if hevc_supported {
                    if (config.supportedVideoFormats & H265) != 0 {
                        if streamSettings.enableHdr && hdr10_supported {
                            config.supportedVideoFormats |= H265_MAIN10
                            print("stream - Auto HDR: Adding H265_MAIN10")
                        }
                    } else {
                        // If HEVC base wasn't added above (unlikely), still add main profile when HDR/8K forces it
                        config.supportedVideoFormats |= H265
                        if streamSettings.enableHdr && hdr10_supported {
                            config.supportedVideoFormats |= H265_MAIN10
                            print("stream - Auto HDR: Adding H265 + H265_MAIN10 (forced)")
                        } else {
                            print("stream - Auto HDR: Adding H265 (forced)")
                        }
                    }
                }
                if av1_supported && streamSettings.enableHdr && hdr10_supported {
                    config.supportedVideoFormats |= AV1_MAIN10
                    print("stream - Auto HDR: Adding AV1_MAIN10")
                }
            case .hevc:
                if hevc_supported && streamSettings.enableHdr && hdr10_supported {
                    config.supportedVideoFormats |= H265_MAIN10
                    print("stream - HEVC HDR: Adding H265_MAIN10")
                }
            case .av1:
                if av1_supported && streamSettings.enableHdr && hdr10_supported {
                    config.supportedVideoFormats |= AV1_MAIN10
                    print("stream - AV1 HDR: Adding AV1_MAIN10")
                }
            case .h264:
                // H.264 has no HDR/10-bit in this path — do nothing
                if streamSettings.enableHdr {
                    print("stream - H.264 selected with HDR enabled. HDR not available on H.264; not advertising HEVC/AV1.")
                }
            default:
                break
            }
        }

        print("stream - Final supportedVideoFormats: \(String(format: "0x%04X", config.supportedVideoFormats))")

        currentStreamConfig = config
        currentlyStreamingAppId = app.id ?? app.name
        classicWindowNeedsManualClose = false
        realityWindowNeedsManualClose = false
        activelyStreaming = true
        print("stream - Stream configuration complete. Ready to start streaming.")
        return currentStreamConfig
    }
    
    private func canStartNewStream() -> Bool {
        // Check if we're in an appropriate state
        guard streamState == .idle else {
            print("[Safety] Cannot start stream - current state: \(streamState.rawValue)")
            return false
        }
        
        // Check cooldown
        guard canReconnectNow() else {
            let remaining = reconnectCooldownRemaining()
            print("[Safety] Cannot start stream - cooldown active (\(remaining)s remaining)")
            return false
        }
        
        // Ensure we're not in a renderer swap
        guard !isSwappingRenderers else {
            print("[Safety] Cannot start stream - renderer swap in progress")
            return false
        }
        
        return true
    }

    func userDidRequestDisconnect() {
        print("[ViewModel] User requested disconnect. Setting activelyStreaming to false.")
        self.activelyStreaming = false
        
        // Let the UI update before we start the teardown
        DispatchQueue.main.async {
            self.beginDisconnect()
        }
    }
    
    private func beginDisconnect() {
        print("[ViewModel] Graceful disconnect initiated.")
        
        guard streamState == .running || streamState == .starting else {
            print("[ViewModel] Aborting disconnect, not in a running state. State: \(streamState.rawValue)")
            return
        }

        print("[ViewModel] Setting state to 'stopping'. Firing 'shouldCloseStream'.")
        self.streamState = .stopping
        self.shouldCloseStream = true

        beginReconnectCooldown(2.0)
        
        Task {
            await cleanupAudioSession()
        }
    }

    private func cleanupAudioSession() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // First, try to set to a basic category
            try audioSession.setCategory(.ambient, mode: .default, options: [])
            
            // Then deactivate
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            print("beginDisconnect - Audio session cleaned up successfully")
        } catch {
            print("beginDisconnect - Failed to cleanup audio session: \(error)")
        }
        
        // Give a moment for the audio session to settle
        try? await Task.sleep(for: .milliseconds(200))
    }

    func beginReconnectCooldown(_ seconds: TimeInterval = 1.0) {
        reconnectCooldownUntil = Date().addingTimeInterval(seconds)
    }

    func reconnectCooldownRemaining() -> TimeInterval {
        guard let until = reconnectCooldownUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    func canReconnectNow() -> Bool {
        reconnectCooldownRemaining() <= 0
    }

    // Centralized await for teardown completion or timeout
    func waitForTeardown(timeout: TimeInterval = 1.5) async {
        print("[Lifecycle] Waiting for teardown... (timeout \(timeout)s)")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let center = NotificationCenter.default
            var fired = false
            var obs1: NSObjectProtocol?
            var obs2: NSObjectProtocol?

            func cleanup(label: String, timedOut: Bool = false) {
                if fired { return }
                fired = true
                if let o = obs1 { center.removeObserver(o) }
                if let o = obs2 { center.removeObserver(o) }

                Task { @MainActor in
                    if timedOut {
                        print("[Lifecycle] Teardown wait timed out; proceeding")
                    } else {
                        print("[Lifecycle] Teardown observed via \(label)")
                    }

                    if self.streamState == .stopping {
                        print("[Lifecycle] Releasing lifecycle gate. streamState -> idle")
                        self.streamState = .idle
                    }
                    cont.resume()
                }
            }

            obs1 = center.addObserver(forName: Notification.Name("StreamDidTeardownNotification"), object: nil, queue: .main) { _ in
                cleanup(label: "StreamDidTeardownNotification")
            }
            obs2 = center.addObserver(forName: Notification.Name("RKStreamDidTeardown"), object: nil, queue: .main) { _ in
                cleanup(label: "RKStreamDidTeardown")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                cleanup(label: "timeout", timedOut: true)
            }
        }
    }
    
    // BEGIN SwapSafetyGuardrails: First-frame watchdog with IDR retry
    private func waitForFirstFrameWithWatchdog(firstRetryAt: TimeInterval = 1.8, hardTimeout: TimeInterval = 3.5) async {
        print("[SwapGuard] Waiting for first frame (retry at \(firstRetryAt)s, hard timeout \(hardTimeout)s)")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let center = NotificationCenter.default
            var fired = false
            var obs1: NSObjectProtocol?
            var obs2: NSObjectProtocol?

            func complete(_ label: String) {
                if fired { return }
                fired = true
                if let o = obs1 { center.removeObserver(o) }
                if let o = obs2 { center.removeObserver(o) }
                print("[SwapGuard] First-frame gate released via \(label)")
                cont.resume()
            }

            obs1 = center.addObserver(forName: Notification.Name("StreamFirstFrameShownNotification"), object: nil, queue: .main) { _ in
                complete("UIKit first-frame")
            }
            obs2 = center.addObserver(forName: Notification.Name("RKStreamFirstFrameShown"), object: nil, queue: .main) { _ in
                complete("RealityKit first-frame")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + firstRetryAt) {
                if !fired {
                    print("[SwapGuard] First frame not seen by \(firstRetryAt)s -> requesting IDR")
                    LiRequestIdrFrame()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + hardTimeout) {
                if !fired {
                    print("[SwapGuard] Hard timeout reached without first frame; proceeding")
                    complete("hard-timeout")
                }
            }
        }
        // Small cushion to let materials/layers bind
        try? await Task.sleep(for: .milliseconds(250))
    }
    // END SwapSafetyGuardrails

    // MARK: - Renderer Swap Support
    
    @MainActor
    func performRendererSwap(openWindow: OpenWindowAction, openImmersiveSpace: OpenImmersiveSpaceAction, dismissWindow: DismissWindowAction, dismissImmersiveSpace: DismissImmersiveSpaceAction? = nil) async {
        if let last = lastSwapAt {
            let delta = Date().timeIntervalSince(last)
            if delta < minSwapInterval {
                let wait = minSwapInterval - delta
                print("[ViewModel] Swap requested too soon (Δ=\(String(format: "%.2f", delta))s). Waiting \(String(format: "%.2f", wait))s...")
                try? await Task.sleep(for: .milliseconds(Int((wait * 1000).rounded())))
            }
        }

        guard !isSwappingRenderers else {
            print("[ViewModel] Swap already in progress.")
            return
        }
        
        print("[ViewModel] 🔀 Starting Renderer Swap...")
        
        // --- 0. SAFETY LOCK (NEW FIX) ---
        // Tell all renderers to stop drawing immediately to prevent Metal crash during swap
        print("[ViewModel] 🛑 Swap: Posting ForceStopRendering to freeze the engine.")
        NotificationCenter.default.post(name: .forceStopRendering, object: nil)
        try? await Task.sleep(for: .milliseconds(32))
        // --------------------------------
        
        isSwappingRenderers = true
        
        // 1. Capture the essential stream configuration
        let configToRestore = self.currentStreamConfig
        let appIdToRestore = self.currentlyStreamingAppId
        let currentRenderer = streamSettings.renderer
        let targetRenderer: Renderer = (currentRenderer == .classic || currentRenderer == .classicMetal) ? .curvedDisplay : .classicMetal
        
        // PRE-CLOSE: If we're on the classic window, try dismissing it up-front to avoid hanging "Disconnected" view.
        if currentRenderer == .classic || currentRenderer == .classicMetal {
            print("[ViewModel] Swap: Pre-closing classicStreamingWindow")
            dismissWindow(id: Renderer.classicMetal.windowId)
        }
        
        // 2. Trigger a disconnect
        beginDisconnect()
        
        // 3. Wait for teardown with a safer timeout + cushion
        // BEGIN SwapSafetyGuardrails: teardown fence with timeout + cushion
        await waitForTeardown(timeout: 2.0)
        try? await Task.sleep(for: .milliseconds(300))
        // END SwapSafetyGuardrails
        
        print("[ViewModel] ✅ Swap: Teardown confirmed.")
        
        // 4. Dismiss the old surface (again, post-teardown to be extra sure)
        if targetRenderer == .classicMetal {
            print("[ViewModel] Swap: Dismissing immersive space (post-teardown)")
            await dismissImmersiveSpace?()
            // BEGIN SwapSafetyGuardrails: immersive dismissal settle buffer INCREASED for reliability
            try? await Task.sleep(for: .milliseconds(1800))
            // END SwapSafetyGuardrails
        } else {
            print("[ViewModel] Swap: Dismissing classicStreamingWindow (post-teardown)")
            dismissWindow(id: "classicStreamingWindow")
            // BEGIN SwapSafetyGuardrails: window server settle buffer INCREASED for curved reopening
            try? await Task.sleep(for: .milliseconds(1800))
            // END SwapSafetyGuardrails
        }

        // 5. Update settings for the new renderer
        streamSettings.renderer = targetRenderer
        
        // 6. Restore the stream config and "arm" the system for reconnection
        self.currentStreamConfig = configToRestore
        self.currentlyStreamingAppId = appIdToRestore
        self.activelyStreaming = true
        self.streamState = .starting
        
        print("[ViewModel] 🚀 Swap: Armed for reconnection with renderer '\(targetRenderer)'. Opening surface...")

        // 7. Open the new renderer deterministically on the main actor
        if let cfg = Optional(configToRestore) {
            if targetRenderer == .classicMetal {
                await MainActor.run {
                    openWindow(id: targetRenderer.windowId, value: cfg)
                }
                print("[ViewModel] Swap: openWindow(classic) requested")
            } else {
                let result = try? await openImmersiveSpace(id: targetRenderer.windowId, value: cfg)
                print("[ViewModel] Swap: openImmersiveSpace result: \(String(describing: result))")
            }
        }

        // 8. Best-effort cleanup for any stray classic windows
        if targetRenderer == .curvedDisplay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                print("[ViewModel] Swap: Post-open cleanup of classicStreamingWindow (safety)")
                dismissWindow(id: "classicStreamingWindow")
            }
        }

        // BEGIN SwapSafetyGuardrails: IDR discipline + first-frame watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { LiRequestIdrFrame() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { LiRequestIdrFrame() }
        await waitForFirstFrameWithWatchdog(firstRetryAt: 1.8, hardTimeout: 3.5)
        // END SwapSafetyGuardrails

        // 9. Reset the swap flag after first frame + cushion
        // BEGIN SwapSafetyGuardrails: release swap lock conservatively
        self.isSwappingRenderers = false
        self.lastSwapAt = Date()
        // END SwapSafetyGuardrails
    }
}

extension String {
    func dropSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}

// Ensure the new notification name exists globally
extension Notification.Name {
    static let forceStopRendering = Notification.Name("ForceStopRendering")
}