//
//  MenuCardStyle.swift
//  Moonlight Vision
//

import SwiftUI

/// Navy menu card fills — slightly translucent so background themes show through.
enum MenuCardStyle {
    static let navy = Color(red: 0.12, green: 0.18, blue: 0.37)
    /// Was ~0.90–0.95 solid; lowered a touch for wallpaper bleed-through.
    static let fillOpacity: Double = 0.78

    static var fill: Color { navy.opacity(fillOpacity) }
}
