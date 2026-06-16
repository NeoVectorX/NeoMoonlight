//
//  EnvironmentPickerView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//
//

import SwiftUI

/// Baseline sizing for the environment sheet; multiply with ``pt(_:)`` for uniform layout/fonts.
private enum EnvironmentPickerMetrics {
    /// 25% smaller than original design (`1 − 0.25`).
    static let scale: CGFloat = 0.75
    static func pt(_ base: CGFloat) -> CGFloat { base * scale }
    /// One grid cell: thumbnail + label stack (baseline units before ``pt(_:)``).
    static var gridCellHeight: CGFloat { pt(100 + 8 + 24) }
    /// Two rows of cells plus inter-row grid spacing.
    static var gridPageHeight: CGFloat { gridCellHeight * 2 + pt(20) }
    /// Inner width between outer padding (700 − 32×2 at baseline).
    static var gridPageWidth: CGFloat { pt(636) }
}

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
    /// Drives horizontal paging scroll position (kept in sync with ``currentPage``).
    @State private var scrollPageID: Int?
    private let itemsPerPage = 6
    private let pageSwipeMinimumDistance: CGFloat = 24
    private let pageSwipeTriggerDistance: CGFloat = 40
    
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
    
    private func items(for page: Int) -> [EnvItem] {
        let start = page * itemsPerPage
        let end = min(start + itemsPerPage, allItems.count)
        guard start < end else { return [] }
        return Array(allItems[start..<end])
    }
    
    // Theme Colors
    private let brandOrange = Color(red: 0.976, green: 0.627, blue: 0.251)
    
    var body: some View {
        VStack(spacing: EnvironmentPickerMetrics.pt(20)) {
            // Header
            HStack {
                Text("Select Environment")
                    .font(.system(size: EnvironmentPickerMetrics.pt(24), weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: EnvironmentPickerMetrics.pt(32)))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .neoMenuItemGazeHighlight(.circle)
            }
            .padding(.horizontal, EnvironmentPickerMetrics.pt(8))
            
            // Pages: horizontal swipe triggers the same animated page jump as the arrows.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        environmentPageGrid(items: items(for: page))
                            .frame(
                                width: EnvironmentPickerMetrics.gridPageWidth,
                                height: EnvironmentPickerMetrics.gridPageHeight,
                                alignment: .top
                            )
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPageID)
            .scrollDisabled(true)
            .gesture(pageSwipeGesture)
            .frame(height: EnvironmentPickerMetrics.gridPageHeight)
            .onAppear { scrollPageID = currentPage }
            .onChange(of: scrollPageID) { _, newID in
                guard let newID, newID != currentPage else { return }
                currentPage = newID
            }
            .onChange(of: currentPage) { _, page in
                if scrollPageID != page { scrollPageID = page }
            }
            
            // Pagination
            HStack(spacing: EnvironmentPickerMetrics.pt(20)) {
                Button {
                    goToPage(currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: EnvironmentPickerMetrics.pt(32)))
                    .foregroundColor(currentPage > 0 ? .white : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                
                HStack(spacing: EnvironmentPickerMetrics.pt(8)) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? brandOrange : Color.white.opacity(0.3))
                            .frame(
                                width: EnvironmentPickerMetrics.pt(8),
                                height: EnvironmentPickerMetrics.pt(8)
                            )
                    }
                }
                
                Button {
                    goToPage(currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: EnvironmentPickerMetrics.pt(32)))
                    .foregroundColor(currentPage < pageCount - 1 ? .white : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= pageCount - 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(EnvironmentPickerMetrics.pt(32))
        .neoClearBluePanelChrome(
            cornerRadius: EnvironmentPickerMetrics.pt(24),
            layoutScale: EnvironmentPickerMetrics.scale
        )
        .frame(width: EnvironmentPickerMetrics.pt(700))
        .onAppear {
            scrollToSelection()
        }
    }
    
    @ViewBuilder
    private func environmentPageGrid(items: [EnvItem]) -> some View {
        let thumbRadius = EnvironmentPickerMetrics.pt(12)

        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: EnvironmentPickerMetrics.pt(20)
        ) {
            ForEach(items) { item in
                VStack(spacing: EnvironmentPickerMetrics.pt(8)) {
                    Button {
                        selectItem(item)
                    } label: {
                        environmentThumbnail(for: item, cornerRadius: thumbRadius)
                    }
                    .buttonStyle(.plain)

                    Text(item.displayName)
                        .font(.system(size: EnvironmentPickerMetrics.pt(16), weight: .medium))
                        .foregroundColor(isSelected(item) ? brandOrange : .white)
                        .lineLimit(1)
                        .hoverEffectDisabled(true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectItem(item)
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func environmentThumbnail(for item: EnvItem, cornerRadius: CGFloat) -> some View {
        Group {
            if item.type == .disable {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: EnvironmentPickerMetrics.pt(40)))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                EnvironmentThumbnailView(displayName: item.displayName)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: EnvironmentPickerMetrics.pt(100))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected(item) ? brandOrange : Color.white.opacity(0.2),
                    lineWidth: isSelected(item) ? EnvironmentPickerMetrics.pt(3) : EnvironmentPickerMetrics.pt(1)
                )
        )
        .neoMenuItemGazeHighlight(.roundedRect(cornerRadius: cornerRadius))
    }
    
    private func goToPage(_ page: Int) {
        let clamped = min(max(0, page), pageCount - 1)
        guard clamped != currentPage else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = clamped
            scrollPageID = clamped
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: pageSwipeMinimumDistance, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal <= -pageSwipeTriggerDistance {
                    goToPage(currentPage + 1)
                } else if horizontal >= pageSwipeTriggerDistance {
                    goToPage(currentPage - 1)
                }
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
            let page = idx / itemsPerPage
            currentPage = page
            scrollPageID = page
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

extension EnvironmentPickerView {
    /// Curved stream attachment width in meters (matches ``EnvironmentPickerMetrics.scale``).
    static var curvedDesiredLocalWidth: Float { 0.96 * Float(EnvironmentPickerMetrics.scale) }
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
