//
//  ConnectionSerializer.swift
//  Moonlight Vision
//
//  Ensures LiStartConnection never races with LiStopConnection.
//  All stream start/stop operations must go through this serializer.
//  A new connection cannot begin until the previous stop is fully acknowledged
//  by the C library — no timers, no guessing.
//

import Foundation

/// A global serial gate that prevents LiStartConnection from racing with LiStopConnection.
///
/// Usage pattern:
///   1. Before stopping a stream, call `notifyStopBegun()`.
///   2. When the stop completion fires (after LiStopConnection returns), call `notifyStopComplete()`.
///   3. Before starting a new stream, call `waitUntilReadyToStart()` — this suspends
///      until any in-progress stop has fully completed.
///
/// This replaces the timer-based `waitForTeardown` approach with a proper gate.
@MainActor
final class ConnectionSerializer {
    static let shared = ConnectionSerializer()

    private var stopInProgress = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    private init() {}

    /// Call this immediately before initiating a stream stop.
    func notifyStopBegun() {
        stopInProgress = true
        print("[ConnectionSerializer] Stop begun — gate closed")
    }

    /// Call this inside the stop completion block, after LiStopConnection() returns.
    func notifyStopComplete() {
        guard stopInProgress else { return }
        stopInProgress = false
        print("[ConnectionSerializer] Stop complete — gate opened, resuming \(continuations.count) waiter(s)")
        let pending = continuations
        continuations.removeAll()
        for cont in pending {
            cont.resume()
        }
    }

    /// Suspends the caller until any in-progress stop has fully completed.
    /// If no stop is in progress, returns immediately.
    func waitUntilReadyToStart() async {
        guard stopInProgress else { return }
        print("[ConnectionSerializer] New start requested while stop in progress — waiting...")
        await withCheckedContinuation { cont in
            continuations.append(cont)
        }
        print("[ConnectionSerializer] Wait complete — proceeding with start")
    }

    /// Returns true if a stop is currently in progress.
    var isStopInProgress: Bool { stopInProgress }
}
