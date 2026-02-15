//
//  ComputerView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import OrderedCollections // Keep if AppsView or TemporaryHost uses it
import SwiftUI

struct ComputerView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.isEmbeddedInCurved) private var isEmbeddedInCurved
    @Environment(\.dismiss) private var dismiss

    // Stick with @Binding to ensure changes propagate back up if needed
    // (e.g., when pairing succeeds, the parent view should see the updated host).
    @Binding public var host: TemporaryHost

    // State to manage view-specific behavior like stopping automatic checks
    @State private var stopAutomaticStateUpdate = false
    @State private var showCustomPairingAlert = false

    let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    
    /// Gatekeeper for modals. Prevents presentation when the Curved Display renderer is active.
    private var canShowModal: Bool {
        !isEmbeddedInCurved
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    RadialGradient(
                        colors: [
                            brandBlue.opacity(0.25),
                            babyBlue.opacity(0.15),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 400
                    )
                )
                .blur(radius: 50)
                .scaleEffect(1.05)

            RoundedRectangle(cornerRadius: 32)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.95))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.14),
                            Color(red: 0.28, green: 0.46, blue: 0.88).opacity(0.10),
                            Color(red: 0.5, green: 0.7, blue: 1.0).opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 40, x: 0, y: 20)

            VStack(spacing: 20) {
                if host.state != .unknown || host.updatePending {
                    Text(host.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }

                if host.updatePending {
                    UpdatingHUD(title: "Updating…", subtitle: host.name)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                } else {
                    switch host.state {
                    case .online:
                        onlineView
                    case .offline:
                        offlineView
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    case .unknown:
                        VStack(spacing: 16) {
                            ProgressView("Connecting to \(host.name)...")
                                .tint(brandViolet)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .navigationTitle(host.name)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        print("Manual Refresh triggered for \(host.name)")
                        stopAutomaticStateUpdate = false
                        await viewModel.updateHost(host: host, force: true)
                        if host.state == .online && host.pairState == .paired {
                            print("Manual Refresh resulted in Online/Paired state, refreshing apps for \(host.name)")
                            viewModel.refreshAppsFor(host: host)
                        }
                    }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .disabled(host.updatePending)
            }
        }
        .onAppear {
            print("ComputerView appearing for \(host.name). Resetting stop flag.")
            stopAutomaticStateUpdate = false
        }
        .task(id: host.id) {
            // FIXED: Don't run task if actively streaming
            guard !viewModel.activelyStreaming else {
                print("ComputerView.task: Skipping because actively streaming")
                return
            }
            if !stopAutomaticStateUpdate && (host.state == .unknown || host.pairState == .unknown) {
                print("ComputerView.task: Running initial updateHost for \(host.name) (State: \(host.state), PairState: \(host.pairState)).")
                await viewModel.updateHost(host: host)
                if host.state == .online && host.pairState == .paired && host.appList.isEmpty {
                    print("ComputerView.task: Host \(host.name) is Online/Paired after update, refreshing apps.")
                    viewModel.refreshAppsFor(host: host)
                }
            } else {
                print("ComputerView.task: Skipping automatic updateHost for \(host.name). StopFlag: \(stopAutomaticStateUpdate), State: \(host.state), PairState: \(host.pairState)")
            }
        }
        .onChange(of: host.state) { oldState, newState in
            guard !viewModel.activelyStreaming else {
                print("Host \(host.name) state changed from \(oldState) to \(newState), but ignoring during streaming")
                return
            }
            print("Host \(host.name) state changed from \(oldState) to \(newState)")
            if newState == .online && host.pairState == .paired {
                if host.appList.isEmpty {
                    print("Host \(host.name) became Online/Paired, refreshing apps.")
                    Task {
                        viewModel.refreshAppsFor(host: host)
                    }
                }
            }
        }
        .alert(
            "Ready to Pair",
            isPresented: Binding(
                get: { canShowModal && viewModel.pairingInProgress },
                set: { viewModel.pairingInProgress = $0 }
            )
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.endPairing()
            }
        } message: {
            Text("Enter PIN: \(viewModel.currentPin)\n\nThis computer is online but needs to be paired with this device.\n\nIf your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        }
    }

    // MARK: - Subviews for States

    /// View displayed when the host is online. Handles pairing status.
    @ViewBuilder // Use ViewBuilder for cleaner conditional logic if needed
    private var onlineView: some View {
        // Switch based on pairing state *only when online*
        switch host.pairState {
        case .paired:
            // Host is Online and Paired -> Show Apps
             // Ensure AppsView takes a Binding<TemporaryHost>
            AppsView(host: $host)

        case .unpaired:
            // Host is Online but Unpaired -> Show Pairing UI
            VStack(spacing: 0) {
                // X button to dismiss
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 24) {
                
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [babyBlue.opacity(0.3), babyBlue.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .blur(radius: 10)
                    
                    Image(systemName: "lock.desktopcomputer")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [babyBlue, babyBlue.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .padding(.bottom, 8)
                
                Text("Ready to Pair")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("This computer is online but needs to be paired with this device.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)

                Button {
                    viewModel.tryPairHost(host)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Start Pairing")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(babyBlue.opacity(0.3))
                                .offset(y: 4)
                                .blur(radius: 6)
                            
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [babyBlue, babyBlue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
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
                    .shadow(color: babyBlue.opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

        case .unknown:
             // Host is Online, but we haven't determined pairing status yet
             VStack(spacing: 18) {
                 Label("Checking Pairing Status...", systemImage: "questionmark.circle")
                      .font(.title3)
                      .foregroundColor(.white.opacity(0.85))
                 ProgressView()
                      .tint(brandViolet)

                 HStack(spacing: 12) {
                     Button("Start Pairing Anyway") {
                         print("User initiated pairing while pairState is unknown for \(host.name).")
                         viewModel.tryPairHost(host)
                     }
                     .controlSize(.regular)

                     Button("Stop Automatic Checks") {
                         print("User stopped automatic checks for \(host.name).")
                         stopAutomaticStateUpdate = true // Stop this view's task modifier
                         // Optionally tell ViewModel to pause background *polling* if implemented
                         // viewModel.pauseBackgroundDiscovery(for: host)
                     }
                     .controlSize(.small)
                     .tint(.yellow) // Make stop button distinct
                 }
             }
             .padding(24)
             .background(
                 RoundedRectangle(cornerRadius: 20)
                     .fill(.ultraThinMaterial)
                     .overlay(
                         RoundedRectangle(cornerRadius: 20)
                             .strokeBorder(
                                 LinearGradient(
                                     colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing
                                 ),
                                 lineWidth: 1
                             )
                     )
             )
             .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
             .padding(.horizontal, 24)
             .padding(.bottom, 12)

        // No default needed if PairState enum covers all cases
        }
    }

    /// View displayed when the host is offline.
    private var offlineView: some View {
        VStack(spacing: 0) {
            // X button to dismiss
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 15) {
            Label("Offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundColor(.red) // Clear offline indicator
            Text("Moonlight cannot connect to this computer. Ensure it is turned on and connected to the network.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal)

            //force refresh
            Button {
                Task {
                    print("Manual Refresh triggered for \(host.name)")
                    stopAutomaticStateUpdate = false
                    //viewModel.resumeBackgroundDiscovery(for: host) // Optional

                    // --- Call with force: true ---
                    await viewModel.updateHost(host: host, force: true)

                    // Refresh apps if needed *after* the forced update
                    if host.state == .online && host.pairState == .paired {
                         print("Manual Refresh resulted in Online/Paired state, refreshing apps for \(host.name)")
                         viewModel.refreshAppsFor(host: host)
                    }
                }
            } label: {
                Label("Force Refresh Status", systemImage: "arrow.clockwise")
            }
            .disabled(host.updatePending)
            // Wake-on-LAN button
            Button {
                viewModel.wakeHost(host)
            } label: {
                Label("Wake PC", systemImage: "sun.horizon")
            }
            .controlSize(.large)
            // Disable if MAC address is missing or invalid
            .disabled(host.mac == nil || host.mac == "00:00:00:00:00:00")
            // Visually indicate disabled state
            .opacity((host.mac == nil || host.mac == "00:00:00:00:00:00") ? 0.5 : 1.0)
            }
        }
        .padding(.bottom) // Add some vertical padding to the offline view
    }
}

// UpdatingHUD – centered, unclipped loading view
struct UpdatingHUD: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 14) {
                Text(subtitle)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(title)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
        }
    }
}