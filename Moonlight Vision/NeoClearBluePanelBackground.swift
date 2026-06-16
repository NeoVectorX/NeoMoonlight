//
//  NeoClearBluePanelBackground.swift
//  Neo Moonlight
//

import SwiftUI

enum NeoBrandColors {
    static let navy = Color(red: 0.12, green: 0.18, blue: 0.37)
    static let orange = Color(red: 0.976, green: 0.627, blue: 0.251)
}

/// Tutorial navy tint over blurred material — blue, but still see-through.
struct NeoClearBluePanelBackground: View {
    var cornerRadius: CGFloat = 24
    var layoutScale: CGFloat = 1.0

    var body: some View {
        let scale = max(layoutScale, 0.01)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            NeoBrandColors.orange.opacity(0.10),
                            NeoBrandColors.navy.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: cornerRadius * 14
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            NeoBrandColors.navy.opacity(0.38),
                            NeoBrandColors.navy.opacity(0.30),
                            NeoBrandColors.navy.opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1, scale * 1.25)
                )
        }
    }
}

extension View {
    func neoClearBluePanelChrome(cornerRadius: CGFloat = 24, layoutScale: CGFloat = 1.0) -> some View {
        let scale = max(layoutScale, 0.01)
        return background(NeoClearBluePanelBackground(cornerRadius: cornerRadius, layoutScale: layoutScale))
            .shadow(color: NeoBrandColors.navy.opacity(0.22), radius: 22 * scale, x: 0, y: 12 * scale)
            .shadow(color: .black.opacity(0.18), radius: 28 * scale, x: 0, y: 14 * scale)
    }
}
