//
//  NeoMenuGazeHighlight.swift
//  Neo Moonlight
//

import SwiftUI

/// Gaze/hover clip shape — matches each item’s artwork, not a system capsule.
enum NeoMenuGazeHighlightShape: Equatable {
    case circle
    case roundedRect(cornerRadius: CGFloat)
}

extension View {
    @ViewBuilder
    func neoMenuItemGazeHighlight(_ shape: NeoMenuGazeHighlightShape) -> some View {
        switch shape {
        case .circle:
            self
                .contentShape(.hoverEffect, Circle())
                .hoverEffect { effect, _, _ in
                    effect.clipShape(Circle())
                }
        case .roundedRect(let cornerRadius):
            let rounded = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .contentShape(.hoverEffect, rounded)
                .hoverEffect { effect, _, _ in
                    effect.clipShape(rounded)
                }
        }
    }
}
