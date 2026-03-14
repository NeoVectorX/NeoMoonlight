//
//  RemoteMicManager.swift
//  Neo Moonlight
//
//  Created by NeoVectorX
//
//

import SwiftUI
import Network
import Combine

@MainActor
class RemoteMicManager: ObservableObject {
    @Published var isMuted: Bool = false
    @Published var isConnected: Bool = false
    @Published var inputLevel: Float = 0.0
    
    private let host: NWEndpoint.Host = "127.0.0.1"
    private let port: NWEndpoint.Port = 5006
    
    private var connection: NWConnection?
    private var visualizerTimer: Timer?
    private var connectionRefreshTimer: Timer?
    
    init() {
        setupConnection()
        startVisualizer()
        startConnectionRefresh()
    }
    
    // MARK: - Network
    
    private func setupConnection() {
        connection = NWConnection(host: host, port: port, using: .udp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    print("[RemoteMic] Connected to Mic Streamer on port 5006")
                case .failed(let error):
                    self?.isConnected = false
                    print("[RemoteMic] Connection failed: \(error)")
                    // Auto-reconnect after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self?.setupConnection()
                    }
                case .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: .global(qos: .userInitiated))
    }
    
    private func sendCommand(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[RemoteMic] Send error: \(error)")
                Task { @MainActor in
                    self?.setupConnection()
                }
            } else {
                print("[RemoteMic] Sent: \(command)")
            }
        })
    }
    
    private func sendCommandWithRetry(_ command: String) {
        if connection?.state != .ready {
            setupConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendCommandWithRetry(command)
            }
            return
        }
        
        sendCommand(command)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.sendCommand(command)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.sendCommand(command)
        }
    }
    
    private func startConnectionRefresh() {
        connectionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshConnection()
            }
        }
    }
    
    private func refreshConnection() {
        connection?.cancel()
        setupConnection()
    }
    
    // MARK: - Actions
    
    func toggleMute() {
        isMuted.toggle()
        let command = isMuted ? "MUTE" : "UNMUTE"
        sendCommandWithRetry(command)
    }
    
    // MARK: - Visualizer
    
    private func startVisualizer() {
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isMuted {
                // Simulate audio input levels
                self.inputLevel = Float.random(in: 0.15...0.85)
            } else {
                self.inputLevel = 0.0
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        connectionRefreshTimer?.invalidate()
        connectionRefreshTimer = nil
        connection?.cancel()
        connection = nil
    }
}
