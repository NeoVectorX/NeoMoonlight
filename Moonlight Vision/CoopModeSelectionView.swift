//
//  CoopModeSelectionView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI
import GroupActivities

struct CoopModeSelectionView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var coordinator = CoopSessionCoordinator.shared
    
    @Binding var isPresented: Bool
    
    @State private var showHostView = false
    @State private var showJoinView = false
    @State private var selectedHost: TemporaryHost?
    
    // Brand colors
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    // FaceTime call detection - default to false to show reminder
    // Users need to have an active FaceTime call for SharePlay to work
    @State private var isInFaceTimeCall = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandViolet, brandViolet.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Co-op Play")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Play local co-op games with a friend")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 32)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Upload Speed Warning Banner
            HStack(spacing: 14) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandBlue, brandBlue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload Speed Required")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("For remote co-op: Strong internet connection required (30+ Mbps recommended)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [brandBlue.opacity(0.4), brandBlue.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 32)
            
            // FaceTime Info Banner
            if !isInFaceTimeCall {
                HStack(spacing: 14) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [brandViolet, brandBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FaceTime Call Required")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Start a FaceTime call with your friend first")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [brandViolet.opacity(0.4), brandBlue.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 32)
            }
            
            // Mode Selection Buttons
            VStack(spacing: 20) {
                // Host Button
                Button {
                    showHostView = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host Session")
                                .font(.system(size: 24, weight: .bold))
                            Text("Start a new co-op session")
                                .font(.system(size: 15))
                                .opacity(0.7)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .opacity(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [brandViolet, brandViolet.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: brandViolet.opacity(0.3), radius: 15, x: 0, y: 8)
                }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(coordinator.sessionActive)
                .opacity(coordinator.sessionActive ? 0.5 : 1.0)
                
                // Join Button
                Button {
                    showJoinView = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "person.badge.plus.fill")
                            .font(.system(size: 32, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join Session")
                                .font(.system(size: 24, weight: .bold))
                            Text("Join an active co-op session")
                                .font(.system(size: 15))
                                .opacity(0.7)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .opacity(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [brandBlue, brandBlue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: brandBlue.opacity(0.3), radius: 15, x: 0, y: 8)
                }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(coordinator.sessionActive)
                .opacity(coordinator.sessionActive ? 0.5 : 1.0)
                
                // Status message if already in session
                if coordinator.sessionActive {
                    Text("Already in an active co-op session")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(width: 600, height: 800)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topLeading) {
            // Back button in top-left corner
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(16)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .clipShape(Circle())
            .hoverEffect()
            .padding(.leading, 24)
            .padding(.top, 24)
        }
        .sheet(isPresented: $showHostView) {
            if let host = selectedHost {
                CoopHostView(host: host, isPresented: $showHostView, parentIsPresented: $isPresented)
                    .environmentObject(viewModel)
            } else {
                CoopHostSelectorView(selectedHost: $selectedHost, isPresented: $showHostView)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showJoinView) {
            CoopJoinView(isPresented: $showJoinView, parentIsPresented: $isPresented)
                .environmentObject(viewModel)
        }
        .onChange(of: selectedHost) { _, newHost in
            // When a host is selected, automatically show the host view
            if newHost != nil {
                showHostView = true
            }
        }
    }
}

// MARK: - Co-op Host Selector View
struct CoopHostSelectorView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Binding var selectedHost: TemporaryHost?
    @Binding var isPresented: Bool
    
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    var body: some View {
        VStack(spacing: 32) {
            headerSection
            hostListSection
        }
        .frame(width: 600, height: 700)
        .background(backgroundView)
        .overlay(borderOverlay)
        .overlay(alignment: .topLeading) { backButton }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [brandViolet, brandViolet.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Select Your Gaming PC")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Choose which computer to host the co-op session")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }
    
    private var hostListSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.hostsWithPairState.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.hostsWithPairState, id: \.id) { host in
                        hostCardButton(for: host)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxHeight: 400)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(brandOrange)
            
            Text("No Gaming PCs Found")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Make sure your gaming PC is:\n• Powered on\n• Connected to the network\n• Running Moonlight/Sunshine")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
    
    private func hostCardButton(for host: TemporaryHost) -> some View {
        Button {
            selectedHost = host
            isPresented = false
        } label: {
            HStack(spacing: 16) {
                Circle()
                    .fill(host.state == .online ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: (host.state == .online ? Color.green : Color.red).opacity(0.8), radius: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(host.state == .online ? "Online" : "Offline")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(host.state != .online || host.pairState != .paired)
        .opacity((host.state == .online && host.pairState == .paired) ? 1.0 : 0.5)
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 32)
            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
    }
    
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 32)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    private var backButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .padding(16)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
        .hoverEffect()
        .padding(.leading, 24)
        .padding(.top, 24)
    }
}
