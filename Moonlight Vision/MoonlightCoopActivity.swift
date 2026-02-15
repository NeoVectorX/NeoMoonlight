//
//  MoonlightCoopActivity.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import Foundation
import GroupActivities

struct MoonlightCoopActivity: GroupActivity {
    // PC Connection Info
    let hostPCAddress: String
    let hostPCName: String
    let hostPCPort: UInt16
    let isInternetAccessible: Bool  // Whether host has external IP
    let connectionMode: String  // "Local" or "Online"
    
    // App Info
    let appID: String
    let appName: String
    
    // Session Info
    let sessionID: String
    let hostFrameRate: Int32  // Frame rate must match between players
    
    // Pairing Data (for auto-pairing guest)
    let pairingData: Data
    
    // GroupActivity Protocol Requirements
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Moonlight: \(appName)"
        metadata.subtitle = "Co-op on \(hostPCName)"
        metadata.type = .generic
        
        // Optional: Add fallback URL for invitations
        if let url = URL(string: "moonlight://coop/\(sessionID)") {
            metadata.fallbackURL = url
        }
        
        return metadata
    }
}

// Make it Codable for SharePlay transmission
extension MoonlightCoopActivity: Codable {
    enum CodingKeys: String, CodingKey {
        case hostPCAddress
        case hostPCName
        case hostPCPort
        case isInternetAccessible
        case connectionMode
        case appID
        case appName
        case sessionID
        case hostFrameRate
        case pairingData
    }
}

// Equatable for comparing activities
extension MoonlightCoopActivity: Equatable {
    static func == (lhs: MoonlightCoopActivity, rhs: MoonlightCoopActivity) -> Bool {
        return lhs.sessionID == rhs.sessionID &&
               lhs.hostPCAddress == rhs.hostPCAddress &&
               lhs.appID == rhs.appID
    }
}

// Hashable for using in collections
extension MoonlightCoopActivity: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(hostPCAddress)
        hasher.combine(appID)
    }
}
