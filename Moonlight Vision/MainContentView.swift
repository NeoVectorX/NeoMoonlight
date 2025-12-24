//
//  MainContentView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright 2024 Moonlight Game Streaming Project.
//

import SwiftUI

// Environment flag to detect when MainContentView is embedded inside Curved Display attachment
private struct EmbeddedInCurvedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}
extension EnvironmentValues {
    var isEmbeddedInCurved: Bool {
        get { self[EmbeddedInCurvedKey.self] }
        set { self[EmbeddedInCurvedKey.self] = newValue }
    }
}

struct MainContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.isEmbeddedInCurved) private var isEmbeddedInCurved
    var isPopover: Bool = false
    
    @State private var selectedHost: TemporaryHost?
    @State private var addingHost = false
    @State private var isDeletingHost = false
    @State private var hostToDelete: TemporaryHost?
    @State private var newHostIp = ""
    @State private var isRefreshingDiscovery = false
    @State private var showDeletionTriggeredMessage = false
    @State private var selectedTab = 0
    @State private var showCannotCloseAlert = false
    @Environment(\.scenePhase) private var scenePhase
    
    /// Gatekeeper for modals. Prevents presentation when the Curved Display renderer is active.
    private var canShowModal: Bool {
        !isEmbeddedInCurved
    }

    // Brand colors
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    let brandPink = Color(red: 1.0, green: 0.4, blue: 0.7)
    let brandViolet = Color(red: 0.85, green: 0.6, blue: 0.95)
    let brandPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandYellow = Color(red: 1.0, green: 0.85, blue: 0.35)
    
    var body: some View {
        ZStack {
            // Background image
            Image("MoonBG-11")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // Outer glow aura
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    RadialGradient(
                        colors: [
                            brandPurple.opacity(0.25),
                            brandViolet.opacity(0.15),
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
                .fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.65),
                            brandPurple.opacity(0.20)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // NeoMoonlight Logo at top - full width edge to edge
                Image("neomoonlight-logo8")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                
                // Floating Top Navigation Bar
                HStack(spacing: 12) {
                    TabButton(
                        icon: "desktopcomputer",
                        title: "Computers",
                        isSelected: selectedTab == 0,
                        gradient: [brandBlue, brandBlue.opacity(0.7)]
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = 0
                        }
                    }
                    
                    TabButton(
                        icon: "gearshape.fill",
                        title: "Settings",
                        isSelected: selectedTab == 1,
                        gradient: [brandPink, brandPink.opacity(0.7)]
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = 1
                        }
                    }
                    
                    TabButton(
                        icon: "book.closed.fill",
                        title: "Guide",
                        isSelected: selectedTab == 2,
                        gradient: [brandViolet, brandViolet.opacity(0.7)]
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = 2
                        }
                    }
                    
                    TabButton(
                        icon: "list.bullet.clipboard.fill",
                        title: "About",
                        isSelected: selectedTab == 3,
                        gradient: [brandPurple, brandPurple.opacity(0.7)]
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = 3
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.3))
                            .offset(y: 6)
                            .blur(radius: 12)
                        
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
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
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 24)
                
                // Content Area with 3D depth
                TabView(selection: $selectedTab) {
                    // Computers Tab
                    ComputersTabView(
                        viewModel: viewModel,
                        selectedHost: $selectedHost,
                        addingHost: $addingHost,
                        isDeletingHost: $isDeletingHost,
                        hostToDelete: $hostToDelete,
                        newHostIp: $newHostIp,
                        isRefreshingDiscovery: $isRefreshingDiscovery,
                        showDeletionTriggeredMessage: $showDeletionTriggeredMessage
                    )
                    .tag(0)
                    
                    // Settings Tab
                    SettingsView(settings: $viewModel.streamSettings)
                        .tag(1)
                    
                    // Guide Tab
                    UserGuideView()
                        .tag(2)
                    
                    // About Tab
                    UpdatesView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.top, 16)
                .onChange(of: selectedTab) { oldValue, newValue in
                    if canShowModal {
                        if newValue == 0 {
                            viewModel.beginRefresh()
                        } else {
                            viewModel.stopRefresh()
                        }
                    }
                }
            }
        }
        .frame(width: isPopover ? 560 : 700, height: isPopover ? 600 : 920)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .alert("Cannot Close Menu", isPresented: Binding(get: { canShowModal && showCannotCloseAlert }, set: { showCannotCloseAlert = $0 })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please use the Disconnect button to close the menu while streaming")
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            // When mainView window closes or goes inactive, notify stream view to restore audio
            if oldValue == .active && (newValue == .inactive || newValue == .background) {
                print("[MainView] Window closing/backgrounding, posting notification")
                NotificationCenter.default.post(name: Notification.Name("MainViewWindowClosed"), object: nil)
            }
        }
        .onAppear {
            guard !isEmbeddedInCurved else {
                print("MainContentView: Embedded in Curved - skipping host load/refresh")
                return
            }
            guard !viewModel.activelyStreaming else {
                print("MainContentView: Skipping loadSavedHosts and discovery because actively streaming")
                // When returning to the menu while streaming, update what's running
                if let streamingHost = viewModel.hosts.first(where: { $0.appList.contains(where: { $0.id == viewModel.currentlyStreamingAppId }) }) {
                    self.selectedHost = streamingHost
                }
                return
            }
            
            viewModel.loadSavedHosts()
            if !viewModel.activelyStreaming {
                viewModel.beginRefresh()
            }
            Task {
                for host in viewModel.hosts {
                    await viewModel.updateHost(host: host, force: false)
                }
            }
            
            NotificationCenter.default.addObserver(
                viewModel,
                selector: #selector(viewModel.beginRefresh),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
            if selectedHost == nil,
               let firstHost = viewModel.hosts.first(where: { $0.pairState == .paired }) {
                selectedHost = firstHost
            }
        }
        .onDisappear {
            viewModel.isMainViewVisible = false
        }
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    @State private var animate = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.05, blue: 0.2),
                Color(red: 0.05, green: 0.1, blue: 0.25)
            ],
            startPoint: animate ? .topLeading : .bottomLeading,
            endPoint: animate ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - 3D Tab Button Component
struct TabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let gradient: [Color]
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var hasFocus = false
    @FocusState private var isFocused: Bool

    private var primary: Color { gradient.first ?? .accentColor }
    private var secondary: Color { gradient.count > 1 ? gradient[1] : (gradient.first ?? .accentColor) }
    
    private var showCycleGlow: Bool { isSelected || hasFocus }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if showCycleGlow {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [primary.opacity(0.4), primary.opacity(0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 30
                                )
                            )
                            .frame(width: 60, height: 60)
                            .blur(radius: 10)
                            .scaleEffect(pulseScale)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected ? [primary, secondary] : [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: isSelected ? primary.opacity(0.5) : .clear, radius: 12, x: 0, y: 6)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                            ? LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                        )
                }
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .rotation3DEffect(
                    .degrees(isHovered ? 5 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? primary : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onChange(of: isFocused) { _, newValue in
            hasFocus = newValue
            updateGlowState()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .onAppear {
            updateGlowState()
        }
        .onChange(of: isSelected) { _, _ in
            updateGlowState()
        }
    }
    
    private func updateGlowState() {
        if showCycleGlow {
            startPulsing()
        } else {
            pulseScale = 1.0
        }
    }
    
    private func startPulsing() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
        }
    }
}


// MARK: - Computers Tab View
struct ComputersTabView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var selectedHost: TemporaryHost?
    @Binding var addingHost: Bool
    @Binding var isDeletingHost: Bool
    @Binding var hostToDelete: TemporaryHost?
    @Binding var newHostIp: String
    @Binding var isRefreshingDiscovery: Bool
    @Binding var showDeletionTriggeredMessage: Bool
    
    @State private var selectedHostForDetail: TemporaryHost?
    @State private var headerIconPulseScale: CGFloat = 1.0
    @State private var headerIconGlowRotation: Double = 0.0
    @Environment(\.openWindow) private var openWindow
    @Environment(\.isEmbeddedInCurved) private var isEmbeddedInCurved
    
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    private var canShowModal: Bool { !isEmbeddedInCurved }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.hostsWithPairState.isEmpty {
                            EmptyStateCard().padding(.top, 40)
                        } else {
                            ForEach(viewModel.hostsWithPairState, id: \.id) { host in
                                ComputerCard3D(
                                    host: host,
                                    isSelected: selectedHost?.id == host.id,
                                    onTap: { handleTap(on: host) },
                                    onWake: { viewModel.wakeHost(host) },
                                    onPair: { viewModel.tryPairHost(host) },
                                    onDelete: {
                                        hostToDelete = host
                                        isDeletingHost = true
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                            }
                        }
                        
                        Spacer().frame(height: 180)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
            }
            
            VStack {
                Spacer()
                DiscoveryToggleCard(isRefreshingDiscovery: $isRefreshingDiscovery) {
                    isRefreshingDiscovery.toggle()
                    if isRefreshingDiscovery { viewModel.beginRefresh() }
                    else { viewModel.stopRefresh() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
            }
            
            VStack {
                Spacer()
                Text("KEPLER EDITION V11.1")
                    .font(.custom("Fredoka-Medium", size: 14))
                    .kerning(2.0)
                    .foregroundColor(Color(red: 0.482, green: 0.502, blue: 0.863))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 25)
            }
            .allowsHitTesting(false)
        }
        .sheet(item: $selectedHostForDetail) { host in
             if canShowModal, let index = viewModel.hosts.firstIndex(where: { $0.id == host.id }) {
                 let binding = Binding<TemporaryHost>(
                     get: { viewModel.hosts[index] },
                     set: { viewModel.hosts[index] = $0 }
                 )
                ComputerView(host: binding)
                    .environmentObject(viewModel)
            }
        }
        .alert("Add Computer", isPresented: Binding(get: { canShowModal && addingHost }, set: { addingHost = $0 })) {
            TextField("IP Address or Hostname", text: $newHostIp)
            Button("Add") {
                addingHost = false
                viewModel.manuallyDiscoverHost(hostOrIp: newHostIp)
                newHostIp = ""
            }
            Button("Cancel", role: .cancel) {
                addingHost = false
                newHostIp = ""
            }
        } message: {
            Text("Enter the IP address or hostname of your gaming PC")
        }
        .alert("Delete Computer?", isPresented: Binding(get: { canShowModal && isDeletingHost }, set: { isDeletingHost = $0 })) {
            Button("Delete", role: .destructive) {
                if let host = hostToDelete { viewModel.removeHost(host) }
                if selectedHost?.id == hostToDelete?.id { selectedHost = nil }
                isDeletingHost = false
                hostToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                isDeletingHost = false
                hostToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this computer?")
        }
        .onChange(of: addingHost) { _, newValue in
            updateHeaderIconGlow()
        }
        .onAppear {
            updateHeaderIconGlow()
        }
    }
    
    private func handleTap(on host: TemporaryHost) {
        if viewModel.activelyStreaming && selectedHost?.id == host.id {
            viewModel.userDidRequestDisconnect()
        } else {
            if !canShowModal {
                openWindow(id: "mainView")
                return
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selectedHost = host
                selectedHostForDetail = host
            }
        }
    }
    
    private func updateHeaderIconGlow() {
        if addingHost {
            startHeaderIconPulsing()
            startHeaderIconCycleGlow()
        } else {
            headerIconPulseScale = 1.0
            headerIconGlowRotation = 0.0
        }
    }
    
    private func startHeaderIconPulsing() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            headerIconPulseScale = 1.2
        }
    }
    
    private func startHeaderIconCycleGlow() {
        headerIconGlowRotation = 0.0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            headerIconGlowRotation = 360.0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                // My Computers Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [brandBlue.opacity(0.3), brandBlue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "desktopcomputer.and.macbook")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                }
                .frame(width: 64, height: 64)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("My Computers")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Circle().fill(brandBlue).frame(width: 8, height: 8)
                        Text("\(viewModel.hostsWithPairState.count) computer\(viewModel.hostsWithPairState.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                Button {
                    addingHost = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Add PC")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(buttonBackground(color: Color(red: 0.85, green: 0.6, blue: 0.95)))
                    .shadow(color: Color(red: 0.85, green: 0.6, blue: 0.95).opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(28)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
    
    private func buttonBackground(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.3))
                .offset(y: 4)
                .blur(radius: 6)
            
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                )
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
    }
}


// MARK: - 3D Computer Card Refactor
struct ComputerCard3D: View {
    let host: TemporaryHost
    let isSelected: Bool
    let onTap: () -> Void
    let onWake: () -> Void
    let onPair: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var iconPulseScale: CGFloat = 1.0
    @State private var iconGlowRotation: Double = 0.0
    @EnvironmentObject private var viewModel: MainViewModel
    
    let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    let babyBlue = Color(red: 0.72, green: 0.85, blue: 1.0)

    var statusColor: Color {
        switch host.state {
        case .online: return host.pairState == .paired ? brandOrange : .orange
        case .offline: return .red
        default: return .gray
        }
    }
    
    var iconCircleColor: Color {
        // Use blue for the icon circle background
        return brandBlue
    }
    
    var hostIcon: String {
        switch host.state {
        case .online: return host.pairState == .paired ? "desktopcomputer" : "lock.desktopcomputer"
        case .offline: return "desktopcomputer.trianglebadge.exclamationmark"
        default: return "questionmark.circle"
        }
    }
    
    var statusText: String {
        switch host.state {
        case .online: return host.pairState == .paired ? "Ready to Stream" : "Needs Pairing"
        case .offline: return "Offline"
        default: return "Unknown"
        }
    }
    
    var isCurrentlyStreamingThisHost: Bool {
        viewModel.activelyStreaming && viewModel.currentStreamConfig.host == host.activeAddress
    }
    
    // TEMP: Always show glow for testing. Will switch to: host.state == .online
    var shouldShowGradientGlow: Bool {
        return host.state == .online && host.pairState == .paired
    }
    
    var shouldShowIconGlow: Bool {
        return host.state == .online && host.pairState == .paired
    }
    
    var body: some View {
        HStack(spacing: 20) {
            hostStatusIcon
            hostInfo
            Spacer()
            actionButtons
        }
        .padding(24)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .rotation3DEffect(.degrees(isHovered ? 2 : 0), axis: (x: 1, y: 0, z: 0))
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isHovered = hovering }
        }
        .contextMenu {
            if host.state == .offline {
                Button(action: onWake) { Label("Wake on LAN", systemImage: "power") }
            }
            if host.pairState == .unpaired {
                Button(action: onPair) { Label("Pair", systemImage: "lock.open") }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onAppear {
            updateIconGlow()
        }
        .onChange(of: host.state) { _, _ in
            updateIconGlow()
        }
    }
    
    private func updateIconGlow() {
        if shouldShowIconGlow {
            startIconPulsing()
            startIconCycleGlow()
        } else {
            iconPulseScale = 1.0
            iconGlowRotation = 0.0
        }
    }
    
    private func startIconPulsing() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            iconPulseScale = 1.2
        }
    }
    
    private func startIconCycleGlow() {
        iconGlowRotation = 0.0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            iconGlowRotation = 360.0
        }
    }

    @ViewBuilder
    private var hostStatusIcon: some View {
        ZStack {
            if shouldShowIconGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [brandOrange.opacity(0.4), brandOrange.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)
                    .blur(radius: 10)
                    .scaleEffect(iconPulseScale)
            }
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [iconCircleColor.opacity(0.3), iconCircleColor.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .shadow(color: shouldShowIconGlow ? brandOrange.opacity(0.5) : .clear, radius: 12, x: 0, y: 6)
            
            if shouldShowIconGlow {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: brandOrange.opacity(0.0), location: 0.0),
                                .init(color: brandOrange.opacity(0.0), location: 0.60),
                                .init(color: babyBlue.opacity(0.7), location: 0.75),
                                .init(color: brandOrange.opacity(0.8), location: 0.90),
                                .init(color: brandOrange.opacity(0.0), location: 1.0),
                            ]),
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(iconGlowRotation))
                    .blur(radius: 8)
                    .opacity(0.85)
                
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: brandOrange.opacity(0.0), location: 0.0),
                                .init(color: brandOrange.opacity(0.0), location: 0.60),
                                .init(color: babyBlue, location: 0.75),
                                .init(color: brandOrange, location: 0.90),
                                .init(color: brandOrange, location: 1.0),
                            ]),
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(iconGlowRotation))
                    .shadow(color: brandOrange.opacity(0.7), radius: 6, x: 0, y: 0)
                    .opacity(0.98)
                    .animation(.linear(duration: 3.2).repeatForever(autoreverses: false), value: iconGlowRotation)
            }
            
            Image(systemName: hostIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: iconCircleColor.opacity(0.5), radius: 8, x: 0, y: 4)
        }
        .rotation3DEffect(.degrees(isHovered ? 10 : 0), axis: (x: 0, y: 1, z: 0))
    }

    @ViewBuilder
    private var hostInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(host.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.8), radius: 4, x: 0, y: 2)
                
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isCurrentlyStreamingThisHost {
            resumeButton
            disconnectButton
        } else {
            connectButton
        }
    }

    @ViewBuilder
    private var resumeButton: some View {
        Button {
            NotificationCenter.default.post(name: Notification.Name("ResumeStreamFromMenu"), object: nil)
        } label: {
            Text("Resume")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(buttonBackground(color: .green))
                .shadow(color: Color.green.opacity(0.4), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var disconnectButton: some View {
        Button(action: onTap) {
            Text("Disconnect")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(buttonBackground(color: .red))
                .shadow(color: Color.red.opacity(0.4), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var connectButton: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Connect")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(buttonBackground(color: brandOrange))
            .shadow(color: brandOrange.opacity(0.4), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private func buttonBackground(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.3))
                .offset(y: 4)
                .blur(radius: 6)
            
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                )
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                .offset(y: 6)
                .blur(radius: 12)

            // Gradient glow border (TEMP: Always visible. Switch to shouldShowGradientGlow condition later)
            if shouldShowGradientGlow {
                // Outer glow layer
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [brandOrange, babyBlue, brandOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 10
                    )
                    .blur(radius: 16)
                    .opacity(1.0)
                
                // Inner glow layer for more intensity
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [brandOrange, babyBlue, brandOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 6
                    )
                    .blur(radius: 8)
                    .opacity(0.9)
            }

            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.92))
            
            // Sharp gradient stroke border to enhance/define the glow - NOW ON TOP
            if shouldShowGradientGlow {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [brandOrange, babyBlue, brandOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            }
            
            // Original selection border overlay (if needed)
            if !shouldShowGradientGlow {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: isSelected
                            ? [statusColor.opacity(0.6), statusColor.opacity(0.3)]
                            : [.white.opacity(0.15), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
        }
        .shadow(
            color: isSelected ? statusColor.opacity(0.4) : .black.opacity(0.2),
            radius: isSelected ? 24 : 16,
            x: 0,
            y: isSelected ? 12 : 8
        )
    }
}


// MARK: - Empty State Card
struct EmptyStateCard: View {
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brandBlue.opacity(0.2), brandBlue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandBlue, brandBlue.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Computers Found")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Add your gaming PC to get started")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.1), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Discovery Toggle Card
struct DiscoveryToggleCard: View {
    @Binding var isRefreshingDiscovery: Bool
    let onToggle: () -> Void
    
    let brandBlue = Color(red: 0.5, green: 0.7, blue: 1.0)
    
    var body: some View {
        HStack(spacing: 20) {
            // Network Discovery Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [brandBlue.opacity(0.3), brandBlue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: isRefreshingDiscovery ? "antenna.radiowaves.left.and.right" : "network")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Network Discovery")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(isRefreshingDiscovery ? .green : .gray)
                        .frame(width: 10, height: 10)
                        .shadow(color: isRefreshingDiscovery ? .green.opacity(0.8) : .gray.opacity(0.8), radius: 4, x: 0, y: 2)
                    
                    Text(isRefreshingDiscovery ? "Scanning..." : "Tap to scan for computers")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()

            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isRefreshingDiscovery ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(isRefreshingDiscovery ? "Stop" : "Start")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                     RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [brandBlue, brandBlue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                )
                .shadow(color: brandBlue.opacity(0.4), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                    .offset(y: 6)
                    .blur(radius: 12)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.37).opacity(0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    MainContentView().environmentObject(MainViewModel.shared)
}
