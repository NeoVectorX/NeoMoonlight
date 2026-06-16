//
//  RemoteMicManager.swift
//  Neo Moonlight
//
//  UDP commands to Mic Streamer on 127.0.0.1:5006.
//  Tap: "mute" / "unmute" (mic only, no game audio change).
//  Long-press: "mute_dim" / "unmute_dim" (mic + game audio dim on PC).
//

import SwiftUI

@MainActor
class RemoteMicManager: ObservableObject {
    @Published var isMuted: Bool = false
    @Published var isDimmed: Bool = false

    static let longPressDuration: TimeInterval = 0.8

    // MARK: - Tap (mic only)

    func toggleMute() {
        isMuted.toggle()
        sendMicCommand(isMuted ? "mute" : "unmute")
    }

    // MARK: - Long-press (mic + game audio dim)

    func longPressMute() {
        guard !isDimmed else { return }
        isMuted = true
        isDimmed = true
        sendMicCommand("mute_dim")
    }

    func longPressRelease() {
        guard isDimmed else { return }
        isMuted = false
        isDimmed = false
        sendMicCommand("unmute_dim")
    }

    // MARK: - UDP

    private func sendMicCommand(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }

            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { return }
            defer { close(fd) }

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(5006).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(fd, base, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        print("[RemoteMic] Sent: \(command)")
    }
}
