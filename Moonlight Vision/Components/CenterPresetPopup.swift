import SwiftUI

struct CenterPresetPopup: View {
    var text: String
    var icon: String
    var width: CGFloat = 713
    
    var body: some View {
        let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
        let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
        let radius: CGFloat = 24
        
        HStack(spacing: 12) {
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
                    .frame(width: 83, height: 83)
                    .shadow(color: brandOrange.opacity(0.5), radius: 12, x: 0, y: 8)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(text.uppercased())
                .font(.custom("Fredoka-SemiBold", size: 50))
                .tracking(1.2)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .frame(width: width, height: 132)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(brandNavy.opacity(0.4))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .allowsHitTesting(false)
    }
}