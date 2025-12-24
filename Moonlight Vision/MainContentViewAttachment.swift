//
//  MainContentViewAttachment.swift
//  NeoMoonlight - UIHostingController wrapper for MainContentView in RealityKit
//
//  This wrapper bypasses the SwiftUI → RealityKit compilation bottleneck
//  by using UIHostingController to render MainContentView at runtime
//

import SwiftUI
import UIKit

// MARK: - Main Attachment Wrapper

struct MainContentViewAttachment: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        HostedMainContentView()
            .environmentObject(viewModel)
            .frame(width: 700, height: 920)
    }
}

// MARK: - UIViewRepresentable Host

struct HostedMainContentView: UIViewRepresentable {
    @EnvironmentObject var viewModel: MainViewModel
    
    func makeUIView(context: Context) -> UIView {
        let hostingController = UIHostingController(rootView: 
            MainContentView()
                .environmentObject(viewModel)
                .environment(\.isEmbeddedInCurved, true)
        )
        
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        
        return hostingController.view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Updates are handled automatically by SwiftUI's environment
    }
}