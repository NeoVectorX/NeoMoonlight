//
//  Neo Moonlight
//
//  Created by NeoVectorX
//
//

import SwiftUI

struct CenterPresetPopup: View {
    var text: String
    var icon: String
    var width: CGFloat = 713
    /// Scale for title/icon/sizing (e.g. 1.2 = 20% larger). Used in curved display only; default 1.0.
    var displayScale: CGFloat = 1.0
    
    var body: some View {
        let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
        let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
        let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)
        let radius: CGFloat = 24 * displayScale
        let spacing: CGFloat = 12 * displayScale
        let circleSize: CGFloat = 83 * displayScale
        let iconSize: CGFloat = 34 * displayScale
        let titleSize: CGFloat = 50 * displayScale
        let tracking: CGFloat = 1.2 * displayScale
        let height: CGFloat = (displayScale > 1.0) ? (160 * displayScale) : (132 * displayScale)
        let padH: CGFloat = 24 * displayScale
        let padV: CGFloat = 16 * displayScale
        
        HStack(spacing: spacing) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brandOrange, brandOrange.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: circleSize, height: circleSize)
                    .shadow(color: brandOrange.opacity(0.5), radius: 12 * displayScale, x: 0, y: 8 * displayScale)
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(text.uppercased())
                .font(.custom("Fredoka-SemiBold", size: titleSize))
                .tracking(tracking)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer()
        }
        .frame(width: width, height: height)
        .padding(.horizontal, padH)
        .padding(.vertical, padV)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(brandNavy.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 30 * displayScale, x: 0, y: 16 * displayScale)
        .allowsHitTesting(false)
    }
}
