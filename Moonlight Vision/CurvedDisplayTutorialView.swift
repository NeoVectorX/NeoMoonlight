//
//  CurvedDisplayTutorialView.swift
//  Neo Moonlight
//
// 
//

import SwiftUI

struct CurvedDisplayTutorialView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    
    // Match navy + orange theme from SBS confirmation
    let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandOrangeLight = Color(red: 1.0, green: 0.68, blue: 0.20)

    let tutorialSteps: [(icon: String, title: String, description: String)] = [
        (
            icon: "crown.fill",
            title: "Center the Screen",
            description: "Hold the Digital Crown to recenter the screen directly in front of you."
        ),
        (
            icon: "gamecontroller.fill",
            title: "Control Modes",
            description: "Switch between Gaze Control, Screen Adjust, and Accessory Mode using the toggle in top controls. Select Accessory Mode to enable gamepads and mice."
        ),
        (
            icon: "arrow.up.left.and.arrow.down.right",
            title: "Screen Adjust",
            description: "In Screen Adjust Mode pinch-drag the middle area of the screen to reposition. Pinch in/out to change the screen scale."
        ),
        (
            icon: "rectangle.fill.on.rectangle.angled.fill",
            title: "Screen Preset Mode",
            description: "Store up to 3 of your favorite screen positions. Long press the Screen Preset button to quickly cycle through each preset."
        ),
        (
            icon: "hand.point.up.left.fill",
            title: "Reveal & Unlock Controls",
            description: "Icons auto-hide. Tap any icon to reveal the controls and interact with them."
        ),
        (
            icon: "hand.tap.fill",
            title: "Long Press to Reset",
            description: "Long Press (Pinch & Hold) on Dimming, Environment and Screen Adjust icons to reset to default"
        ),
        (
            icon: "eye.slash.fill",
            title: "App Visibility",
            description: "In Curved Display mode, external apps and system windows are unable to be visible. Switch to Flat Display if you need external app visiblity."
        ),
        (
            icon: "person.2.fill",
            title: "Couch Co-op Mode",
            description: "Play couch co-op games locally or online with another Vision Pro player. Only the host needs to own the game. Requires a strong connection."
        ),
        (
            icon: "mountain.2.fill",
            title: "Apple Environments",
            description: "Select your preferred Apple environment. Connect to Curved Display, then rotate the digital crown to reveal the environment."
        )
    ]
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main tutorial card with premium styling
                VStack(spacing: 28) {
                    // Header with progress indicator
                    VStack(spacing: 14) {
                        Text("Welcome to Curved Display")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        // Premium progress dots with orange glow
                        HStack(spacing: 10) {
                            ForEach(0..<tutorialSteps.count, id: \.self) { index in
                                ZStack {
                                    if index == currentStep {
                                        Circle()
                                            .fill(brandOrange.opacity(0.4))
                                            .frame(width: 16, height: 16)
                                            .blur(radius: 6)
                                    }
                                    
                                    Circle()
                                        .fill(index == currentStep ? 
                                              LinearGradient(
                                                colors: [brandOrange, brandOrange.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                              ) :
                                              LinearGradient(
                                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                              )
                                        )
                                        .frame(width: index == currentStep ? 12 : 8, height: index == currentStep ? 12 : 8)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    index == currentStep ? 
                                                    Color.white.opacity(0.5) :
                                                    Color.white.opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: index == currentStep ? brandOrange.opacity(0.6) : .clear, radius: 8, x: 0, y: 4)
                                }
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.bottom, 4)
                    
                    // Premium icon with layered orange glow effects
                    ZStack {
                        // Outer diffused glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [brandOrange.opacity(0.35), brandOrange.opacity(0.12), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 90
                                )
                            )
                            .frame(width: 180, height: 180)
                            .blur(radius: 15)
                        
                        // Middle glow ring
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [brandOrangeLight.opacity(0.3), brandOrangeLight.opacity(0.08), .clear],
                                    center: .center,
                                    startRadius: 30,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)
                            .blur(radius: 8)
                        
                        // Icon circle with navy gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [brandNavy.opacity(0.6), brandNavy.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 110, height: 110)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [brandOrange.opacity(0.7), brandOrange.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: brandOrange.opacity(0.5), radius: 20, x: 0, y: 10)
                        
                        // Icon with glow
                        Image(systemName: tutorialSteps[currentStep].icon)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.95)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: brandOrange.opacity(0.6), radius: 10, x: 0, y: 4)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .frame(height: 180)
                    
                    // Step content with premium styling
                    VStack(spacing: 14) {
                        Text(tutorialSteps[currentStep].title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        
                        Text(tutorialSteps[currentStep].description)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .frame(maxWidth: 440)
                    }
                    .padding(.horizontal, 28)
                    
                    // Premium navigation buttons
                    HStack(spacing: 18) {
                        if currentStep > 0 {
                            // Back button with subtle style
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    currentStep -= 1
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Back")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 130, height: 52)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.black.opacity(0.3))
                                            .offset(y: 3)
                                            .blur(radius: 8)
                                        
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .strokeBorder(
                                                        LinearGradient(
                                                            colors: [.white.opacity(0.25), .white.opacity(0.08)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        
                        Spacer()
                        
                        // Premium orange CTA button
                        Button {
                            if currentStep < tutorialSteps.count - 1 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    currentStep += 1
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    UserDefaults.standard.set(true, forKey: "hasSeenCurvedDisplayTutorial_v3")
                                    isPresented = false
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if currentStep < tutorialSteps.count - 1 {
                                    Text("Next")
                                        .font(.system(size: 17, weight: .semibold))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 15, weight: .semibold))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Get Started")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(width: currentStep < tutorialSteps.count - 1 ? 130 : 180, height: 52)
                            .background(
                                ZStack {
                                    // Orange glow shadow
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(brandOrange.opacity(0.35))
                                        .offset(y: 5)
                                        .blur(radius: 8)
                                    
                                    // Orange gradient fill
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [brandOrange, brandOrange.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        )
                                }
                            )
                            .shadow(color: brandOrange.opacity(0.5), radius: 20, x: 0, y: 10)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .frame(maxWidth: 440)
                    .padding(.top, 6)
                }
                .padding(44)
                .frame(width: 560)
                .background(
                    ZStack {
                        // Outer shadow for depth
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color.black.opacity(0.35))
                            .offset(y: 8)
                            .blur(radius: 16)
                        
                        // Background radial gradient with orange
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        brandOrange.opacity(0.18),
                                        brandNavy.opacity(0.12),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 420
                                )
                            )
                            .blur(radius: 50)
                            .scaleEffect(1.08)
                        
                        // Base navy layer
                        RoundedRectangle(cornerRadius: 28)
                            .fill(brandNavy.opacity(0.92))
                        
                        // Premium glass overlay
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                )
                .shadow(color: brandOrange.opacity(0.25), radius: 35, x: 0, y: 18)
                .shadow(color: .black.opacity(0.35), radius: 45, x: 0, y: 22)
            }
        }
        .transition(.scale.combined(with: .opacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .compositingGroup()
    }
}

// MARK: - Head Follow first-use intro

struct HeadFollowIntroView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    private let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)

    private let steps: [(icon: String, title: String, description: String)] = [
        (
            icon: "figure.walk",
            title: "Follow Mode",
            description: "The screen stays with you while you move around."
        ),
        (
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            title: "Screen Adjust",
            description: "Drag to move the screen around you. Pinch to resize it smaller or larger."
        ),
        (
            icon: "crown.fill",
            title: "Reset Position",
            description: "Hold the Digital Crown to snap the screen back to its original in-front position and default size."
        ),
        (
            icon: "lock.open.fill",
            title: "Turn Off",
            description: "Tap Follow Mode on the top bar to exit and restore your previous layout."
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Follow Mode")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(brandNavy.opacity(0.85))
                            .overlay(Circle().strokeBorder(brandOrange.opacity(0.6), lineWidth: 2))
                    )

                VStack(spacing: 10) {
                    Text(steps[currentStep].title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text(steps[currentStep].description)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 380)

                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? brandOrange : Color.white.opacity(0.35))
                            .frame(width: index == currentStep ? 10 : 7, height: index == currentStep ? 10 : 7)
                    }
                }

                Button {
                    if currentStep < steps.count - 1 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentStep += 1
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                } label: {
                    Text(currentStep < steps.count - 1 ? "Next" : "Got It")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 140, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(brandOrange)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(36)
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(brandNavy.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
