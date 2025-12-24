//
//  RealityKitHelpers.swift
//  NeoMoonlight - Helper utilities for RealityKit views
//
//  Extracted from RikuKun's moonlight-ios-vision
//

import Foundation

// MARK: - Thread-Safe HDR Settings

class ThreadSafeHDRSettings: @unchecked Sendable {
    private var params: HDRParams
    private let lock = NSLock()
    
    init(params: HDRParams) { self.params = params }
    
    var value: HDRParams {
        get { lock.lock(); defer { lock.unlock() }; return params }
        set { lock.lock(); defer { lock.unlock() }; params = newValue }
    }
}

// MARK: - Comparable Extension

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}