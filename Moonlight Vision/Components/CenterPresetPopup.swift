import SwiftUI

struct CenterPresetPopup: View {
    var text: String
    var icon: String
    
    var body: some View {
        let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
        let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)
        
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [brandBlue.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 420, height: 420)
                .blur(radius: 24)
            
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [babyBlue, brandBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(text)
                    .font(.custom("Fredoka-SemiBold", size: 20))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [babyBlue.opacity(0.65), brandBlue.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: brandBlue.opacity(0.35), radius: 28, x: 0, y: 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}