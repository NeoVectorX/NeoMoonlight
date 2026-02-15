//
//  EnvironmentPickerView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI

struct EnvironmentPickerView: View {
    @Binding var environmentSphereLevel: Int
    @Binding var newsetLevel: Int
    @Binding var isPresented: Bool
    @Binding var dimLevel: Int
    
    // Dependencies to fetch names (Unused but kept for compatibility)
    var extraSkyboxNames: [String]
    
    // Derived Data
    private struct EnvItem: Identifiable {
        let id: String
        let displayName: String
        let type: EnvType
        let index: Int // The 1-based index expected by the main view logic (0 for Disable)
    }
    
    private enum EnvType {
        case disable
        case builtin
    }
    
    @State private var currentPage = 0
    private let itemsPerPage = 6
    
    private var allItems: [EnvItem] {
        var items: [EnvItem] = []
        
        // 1. "Disable Environment" option
        items.append(EnvItem(id: "disable", displayName: "None", type: .disable, index: 0))
        
        // 2. Built-in (environmentSphereLevel 1...N)
        // This strictly displays only the 21 named environments
        let builtins = SkyboxCatalog.builtinNames
        for (i, name) in builtins.enumerated() {
            let displayName = SkyboxCatalog.displayNames[name] ?? name.uppercased()
            items.append(EnvItem(id: "b-\(i)", displayName: displayName, type: .builtin, index: i + 1))
        }
        
        return items
    }
    
    private var pageCount: Int {
        max(1, Int(ceil(Double(allItems.count) / Double(itemsPerPage))))
    }
    
    private var currentItems: [EnvItem] {
        let start = currentPage * itemsPerPage
        let end = min(start + itemsPerPage, allItems.count)
        guard start < end else { return [] }
        return Array(allItems[start..<end])
    }
    
    // Theme Colors
    private let brandNavy = Color(red: 0.12, green: 0.18, blue: 0.37)
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Select Environment")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            // Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(currentItems) { item in
                    Button {
                        selectItem(item)
                    } label: {
                        VStack(spacing: 8) {
                            Group {
                                if item.type == .disable {
                                    ZStack {
                                        Color.white.opacity(0.1)
                                        Image(systemName: "slash.circle")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                } else {
                                    EnvironmentThumbnailView(displayName: item.displayName)
                                }
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected(item) ? brandOrange : Color.white.opacity(0.2), lineWidth: isSelected(item) ? 3 : 1)
                            )
                            
                            Text(item.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(isSelected(item) ? brandOrange : .white)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle()) // Make whole area tappable
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 260) // Keep stable height
            
            // Pagination
            HStack(spacing: 20) {
                Button {
                    withAnimation { currentPage = max(0, currentPage - 1) }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentPage > 0 ? .white : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? brandOrange : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Button {
                    withAnimation { currentPage = min(pageCount - 1, currentPage + 1) }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(currentPage < pageCount - 1 ? .white : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= pageCount - 1)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(brandNavy.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .frame(width: 700)
        .onAppear {
            scrollToSelection()
        }
    }
    
    private func scrollToSelection() {
        // Find which item is currently selected
        var selectedItem: EnvItem?
        
        if newsetLevel == 0 && environmentSphereLevel == 0 {
            // Disabled state selected
            selectedItem = allItems.first { $0.type == .disable }
        } else if newsetLevel > 0 {
            // Newset active, but hidden from this list
            selectedItem = nil
        } else if environmentSphereLevel > 0 {
            // Check builtin items
            selectedItem = allItems.first { $0.type == .builtin && $0.index == environmentSphereLevel }
        }
        
        if let item = selectedItem, let idx = allItems.firstIndex(where: { $0.id == item.id }) {
            currentPage = idx / itemsPerPage
        }
    }
    
    private func isSelected(_ item: EnvItem) -> Bool {
        if item.type == .disable {
            return newsetLevel == 0 && environmentSphereLevel == 0
        }
        return newsetLevel == 0 && environmentSphereLevel == item.index
    }
    
    private func selectItem(_ item: EnvItem) {
        if item.type == .disable {
            newsetLevel = 0
            environmentSphereLevel = 0
            // Close when disabling
            withAnimation {
                isPresented = false
            }
        } else {
            // Reset newset to 0
            newsetLevel = 0
            // Set the sphere level
            environmentSphereLevel = item.index
            
            // Reset dimming when selecting an environment (they're mutually exclusive)
            dimLevel = 0
            
            // Keep picker open to allow cycling
        }
    }
}

private struct EnvironmentThumbnailView: View {
    let displayName: String
    
    var body: some View {
        // Remove spaces from display name for asset lookup (e.g., "Full Moon" -> "Fullmoon")
        let thumbnailName = resolveThumbnailName()
        
        if let _ = UIImage(named: thumbnailName) {
            Image(thumbnailName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image("placeholderthumb")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
    
    private func resolveThumbnailName() -> String {
        let baseName = "thumb_\(displayName.replacingOccurrences(of: " ", with: ""))"
        
        // Special case: "Full Moon" -> "Fullmoon" (lowercase 'm' in moon)
        if baseName == "thumb_FullMoon" {
            return "thumb_Fullmoon"
        }
        
        // Try case-sensitive first
        if UIImage(named: baseName) != nil {
            return baseName
        }
        
        // Try lowercase fallback
        let lowerName = baseName.lowercased()
        if UIImage(named: lowerName) != nil {
            return lowerName
        }
        
        return baseName
    }
}
