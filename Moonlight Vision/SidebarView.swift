//
//  SidebarView.swift
//  Moonlight Vision
//
//  Created by Alex Haugland on 1/22/24.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: MainViewModel

    var body: some View {
        VStack {
            Text("Servers").font(.largeTitle)
            List(viewModel.hosts) { host in
                Text(host.name)
            }
            // servers
            Spacer()
            HStack {
                Text("Add Server")
                Text("Settings")
            }
        }
    }
}

#Preview {
    // embed this in the right vertical size
    VStack {
        SidebarView()
    }
    .padding()
    .glassBackgroundEffect()
}
