import SwiftUI

struct MainMenuPopover: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var viewModel: MainViewModel
    
    let onResume: () -> Void
    let onDisconnect: () -> Void
    let onOpenFullMenu: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Neo Moonlight")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Stream actions
            HStack(spacing: 12) {
                Button {
                    onResume()
                } label: {
                    Label("Resume", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    Label("Disconnect", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Quick links
            VStack(spacing: 10) {
                Button {
                    onOpenFullMenu()
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("Open Full Menu")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    openWindow(id: "mainView")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        viewModel.streamSettings.save()
                    }
                    onClose()
                } label: {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    openWindow(id: "mainView")
                    onClose()
                } label: {
                    HStack {
                        Image(systemName: "book.closed.fill")
                        Text("Guide")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    openWindow(id: "mainView")
                    onClose()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.clipboard.fill")
                        Text("About")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}