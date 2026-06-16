//
//  DesktopActionsPickerView.swift
//  Neo Moonlight
//
//  Created by NeoVectorX 2026
//

import SwiftUI

@_silgen_name("LiSendKeyboardEvent")
private func LiSendKeyboardEvent(_ keyCode: Int16, _ keyAction: Int8, _ modifiers: Int8) -> Int32

// MARK: - Actions

enum DesktopAction: Identifiable, Equatable {
    case taskManager
    case altTab
    case tab
    case shiftF1
    case home
    case escape
    case shiftTab
    case win
    case altZ
    case pageUp
    case pageDown
    case tilde
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    // macOS Commands page
    case cmdTab
    case spotlight
    case missionControl
    case spaceLeft
    case spaceRight
    case forceQuit

    var id: String {
        switch self {
        case .f1: return "f1"
        case .f2: return "f2"
        case .f3: return "f3"
        case .f4: return "f4"
        case .f5: return "f5"
        case .f6: return "f6"
        case .f7: return "f7"
        case .f8: return "f8"
        case .f9: return "f9"
        case .f10: return "f10"
        case .f11: return "f11"
        case .f12: return "f12"
        case .cmdTab: return "cmdTab"
        case .spotlight: return "spotlight"
        case .missionControl: return "missionControl"
        case .spaceLeft: return "spaceLeft"
        case .spaceRight: return "spaceRight"
        case .forceQuit: return "forceQuit"
        default: return String(describing: self)
        }
    }

    /// Five pages × six actions. Swipe horizontally between pages.
    static let pages: [[DesktopAction]] = [
        [.taskManager, .altTab, .tab, .shiftF1, .shiftTab, .escape],
        [.home, .win, .altZ, .pageUp, .pageDown, .tilde],
        [.cmdTab, .spotlight, .missionControl, .spaceLeft, .spaceRight, .forceQuit],
        [.f1, .f2, .f3, .f4, .f5, .f6],
        [.f7, .f8, .f9, .f10, .f11, .f12],
    ]

    static let macOSCommandsPageIndex = 2

    var title: String {
        switch self {
        case .taskManager: return "Task Mgr"
        case .altTab: return "Alt+Tab"
        case .tab: return "Tab"
        case .shiftF1: return "Shift+F1"
        case .home: return "Home"
        case .escape: return "Escape"
        case .shiftTab: return "Shift+Tab"
        case .win: return "Win"
        case .altZ: return "Alt+Z"
        case .pageUp: return "Pg Up"
        case .pageDown: return "Pg Dn"
        case .tilde: return "Tilde"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .cmdTab: return "App Switch"
        case .spotlight: return "Spotlight"
        case .missionControl: return "Mission Ctrl"
        case .spaceLeft: return "Space ←"
        case .spaceRight: return "Space →"
        case .forceQuit: return "Force Quit"
        }
    }

    var systemImage: String {
        switch self {
        case .taskManager: return "list.bullet.rectangle"
        case .altTab: return "rectangle.2.swap"
        case .tab: return "arrow.right.to.line"
        case .shiftF1, .shiftTab: return "keyboard"
        case .home: return "house.fill"
        case .escape: return "arrow.uturn.backward"
        case .win: return "square.grid.2x2"
        case .altZ: return "character.cursor.ibeam"
        case .pageUp: return "arrow.up.to.line"
        case .pageDown: return "arrow.down.to.line"
        case .tilde: return "textformat"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return "keyboard"
        case .cmdTab: return "rectangle.2.swap"
        case .spotlight: return "magnifyingglass"
        case .missionControl: return "rectangle.3.group"
        case .spaceLeft: return "arrow.left"
        case .spaceRight: return "arrow.right"
        case .forceQuit: return "xmark.octagon"
        }
    }

    var usesTextIcon: Bool {
        switch self {
        case .tab, .shiftF1, .shiftTab, .escape, .win, .altZ, .tilde,
             .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
             .cmdTab, .spotlight, .missionControl, .spaceLeft, .spaceRight, .forceQuit:
            return true
        default:
            return false
        }
    }

    var textIcon: String? {
        switch self {
        case .tab: return "Tab"
        case .shiftF1: return "⇧F1"
        case .shiftTab: return "⇧⇥"
        case .escape: return "Esc"
        case .win: return "Win"
        case .altZ: return "⌥Z"
        case .tilde: return "~"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .cmdTab: return "⌘⇥"
        case .spotlight: return "⌘Space"
        case .missionControl: return "⌃↑"
        case .spaceLeft: return "⌃←"
        case .spaceRight: return "⌃→"
        case .forceQuit: return "⌘⌥Esc"
        default: return nil
        }
    }

    var toastLabel: String {
        switch self {
        case .altTab: return "Desktop: Switch app (use gaze or controller)"
        case .cmdTab: return "Desktop: Switch app (use gaze or controller)"
        default: return "Desktop: \(title)"
        }
    }

    var functionKeyIndex: Int? {
        switch self {
        case .f1: return 1
        case .f2: return 2
        case .f3: return 3
        case .f4: return 4
        case .f5: return 5
        case .f6: return 6
        case .f7: return 7
        case .f8: return 8
        case .f9: return 9
        case .f10: return 10
        case .f11: return 11
        case .f12: return 12
        default: return nil
        }
    }
}

// MARK: - Keyboard chords (Win32 VK + Moonlight modifiers)

enum DesktopKeyboardSender {
    private static let keyDown: Int8 = 0x03
    private static let keyUp: Int8 = 0x04
    private static let modShift: Int8 = 0x01
    private static let modCtrl: Int8 = 0x02
    private static let modAlt: Int8 = 0x04
    private static let modMeta: Int8 = 0x08
    /// VK_LMENU — left Alt held on host after Alt+Tab until released (Windows confirms on Alt up).
    private static let leftAltVK: UInt16 = 0xA4
    private static let leftShiftVK: UInt16 = 0xA0
    private static let leftWinVK: UInt16 = 0x5B
    private static let leftCmdVK: UInt16 = 0x5B
    private static let leftCtrlVK: UInt16 = 0xA2
    private static var stickyAltHeldOnHost = false
    private static var stickyCmdHeldOnHost = false

    private static func vk(_ code: UInt16) -> Int16 {
        Int16(bitPattern: 0x8000 | code)
    }

    private static func sendKey(_ keyCode: Int16, down: Bool, modifiers: Int8 = 0) {
        LiSendKeyboardEvent(keyCode, down ? keyDown : keyUp, modifiers)
    }

    private static func pause(_ microseconds: UInt32 = 35_000) {
        usleep(microseconds)
    }

    private static func tap(_ keyCode: Int16, modifiers: Int8 = 0) {
        sendKey(keyCode, down: true, modifiers: modifiers)
        pause(50_000)
        sendKey(keyCode, down: false, modifiers: modifiers)
    }

    /// Press modifier keys, tap a letter key with modifiers held, then release modifiers.
    private static func chord(modifierVKs: [UInt16], keyVK: UInt16, keyModifiers: Int8) {
        releaseStickyModifiers()
        let modifiers = modifierVKs.map { vk($0) }
        for code in modifiers {
            sendKey(code, down: true, modifiers: 0)
        }
        pause()
        let key = vk(keyVK)
        sendKey(key, down: true, modifiers: keyModifiers)
        pause(50_000)
        sendKey(key, down: false, modifiers: keyModifiers)
        pause()
        for code in modifiers.reversed() {
            sendKey(code, down: false, modifiers: 0)
        }
    }

    private static func releaseStickyModifiers() {
        if stickyAltHeldOnHost {
            sendKey(vk(leftAltVK), down: false, modifiers: 0)
            stickyAltHeldOnHost = false
        }
        if stickyCmdHeldOnHost {
            sendKey(vk(leftCmdVK), down: false, modifiers: 0)
            stickyCmdHeldOnHost = false
        }
    }

    /// Alt down + Tab tap, leave Alt held so the Windows switcher stays open for Tab/Esc.
    private static func performAltTab() {
        releaseStickyModifiers()
        sendKey(vk(leftAltVK), down: true, modifiers: 0)
        pause()
        let tab = vk(0x09)
        sendKey(tab, down: true, modifiers: modAlt)
        pause(50_000)
        sendKey(tab, down: false, modifiers: modAlt)
        stickyAltHeldOnHost = true
    }

    /// Command down + Tab tap, leave Command held so the macOS switcher stays open for Tab/Esc.
    private static func performCmdTab() {
        releaseStickyModifiers()
        sendKey(vk(leftCmdVK), down: true, modifiers: 0)
        pause()
        let tab = vk(0x09)
        sendKey(tab, down: true, modifiers: modMeta)
        pause(50_000)
        sendKey(tab, down: false, modifiers: modMeta)
        stickyCmdHeldOnHost = true
    }

    private static func performFunctionKey(_ index: Int) {
        releaseStickyModifiers()
        let vkCode = UInt16(0x70 + index - 1)
        tap(vk(vkCode))
    }

    /// True while Left Alt is held on the host for an in-progress Alt+Tab session.
    static var isStickyAltHeldOnHost: Bool { stickyAltHeldOnHost }

    /// True while Command is held on the host for an in-progress Cmd+Tab session.
    static var isStickyCmdHeldOnHost: Bool { stickyCmdHeldOnHost }

    /// Release a sticky Alt (if any) when the desktop picker closes without Escape.
    static func releaseStickyModifiersOnHost() {
        DispatchQueue.global(qos: .userInteractive).async {
            releaseStickyModifiers()
        }
    }

    static func perform(_ action: DesktopAction) {
        DispatchQueue.global(qos: .userInteractive).async {
            switch action {
            case .taskManager:
                releaseStickyModifiers()
                tap(vk(0x1B), modifiers: modCtrl | modShift)
            case .altTab:
                performAltTab()
            case .tab:
                var tabModifiers: Int8 = 0
                if stickyAltHeldOnHost { tabModifiers |= modAlt }
                if stickyCmdHeldOnHost { tabModifiers |= modMeta }
                tap(vk(0x09), modifiers: tabModifiers)
            case .shiftF1:
                chord(modifierVKs: [leftShiftVK], keyVK: 0x70, keyModifiers: modShift)
            case .home:
                releaseStickyModifiers()
                tap(vk(0x24))
            case .escape:
                releaseStickyModifiers()
                tap(vk(0x1B), modifiers: 0)
            case .shiftTab:
                chord(modifierVKs: [leftShiftVK], keyVK: 0x09, keyModifiers: modShift)
            case .win:
                releaseStickyModifiers()
                tap(vk(leftWinVK))
            case .altZ:
                chord(modifierVKs: [leftAltVK], keyVK: 0x5A, keyModifiers: modAlt)
            case .pageUp:
                releaseStickyModifiers()
                tap(vk(0x21))
            case .pageDown:
                releaseStickyModifiers()
                tap(vk(0x22))
            case .tilde:
                releaseStickyModifiers()
                tap(vk(0xC0))
            case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
                if let index = action.functionKeyIndex {
                    performFunctionKey(index)
                }
            case .cmdTab:
                performCmdTab()
            case .spotlight:
                releaseStickyModifiers()
                chord(modifierVKs: [leftCmdVK], keyVK: 0x20, keyModifiers: modMeta)
            case .missionControl:
                releaseStickyModifiers()
                chord(modifierVKs: [leftCtrlVK], keyVK: 0x26, keyModifiers: modCtrl)
            case .spaceLeft:
                releaseStickyModifiers()
                chord(modifierVKs: [leftCtrlVK], keyVK: 0x25, keyModifiers: modCtrl)
            case .spaceRight:
                releaseStickyModifiers()
                chord(modifierVKs: [leftCtrlVK], keyVK: 0x27, keyModifiers: modCtrl)
            case .forceQuit:
                releaseStickyModifiers()
                chord(modifierVKs: [leftCmdVK, leftAltVK], keyVK: 0x1B, keyModifiers: modMeta | modAlt)
            }
        }
    }
}

// MARK: - Picker UI

private enum DesktopActionsPickerMetrics {
    static let baseScale: CGFloat = 0.7
}

struct DesktopActionsPickerView: View {
    @Binding var isPresented: Bool
    /// Extra layout scale for flat/classic ornaments (`1.3` = 30% larger). Curved stream uses `1.0`.
    var sizeScale: CGFloat = 1.0
    var onActionPerformed: ((DesktopAction) -> Void)?

    @State private var selectedPage = 0

    /// Flat + classic ornament sizing (curved attachment keeps default ``sizeScale``).
    static let flatClassicSizeScale: CGFloat = 1.3

    private let pageCount = DesktopAction.pages.count

    private var layoutScale: CGFloat { DesktopActionsPickerMetrics.baseScale * sizeScale }
    private func pt(_ base: CGFloat) -> CGFloat { base * layoutScale }

    static var curvedDesiredLocalWidth: Float { 0.72 * Float(DesktopActionsPickerMetrics.baseScale) }

    private var pageTitle: String {
        selectedPage == DesktopAction.macOSCommandsPageIndex ? "macOS Commands" : "Desktop Actions"
    }

    var body: some View {
        VStack(spacing: pt(16)) {
            HStack {
                Text(pageTitle)
                    .font(.system(size: pt(24), weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    DesktopKeyboardSender.releaseStickyModifiersOnHost()
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: pt(32)))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .neoMenuItemGazeHighlight(.circle)
            }
            .padding(.horizontal, pt(8))

            TabView(selection: $selectedPage) {
                ForEach(0..<pageCount, id: \.self) { pageIndex in
                    actionGrid(for: DesktopAction.pages[pageIndex])
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: pt(320))

            pageIndicatorDots
        }
        .padding(pt(32))
        .frame(width: pt(420))
        .neoClearBluePanelChrome(cornerRadius: pt(24), layoutScale: layoutScale)
    }

    private var pageIndicatorDots: some View {
        HStack(spacing: pt(10)) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == selectedPage ? Color.white : Color.white.opacity(0.32))
                    .frame(width: pt(8), height: pt(8))
                    .animation(.easeInOut(duration: 0.2), value: selectedPage)
            }
        }
        .padding(.top, pt(4))
        .accessibilityLabel("Page \(selectedPage + 1) of \(pageCount)")
    }

    private func actionGrid(for actions: [DesktopAction]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 3),
            spacing: pt(20)
        ) {
            ForEach(actions) { action in
                VStack(spacing: pt(8)) {
                    Button {
                        DesktopKeyboardSender.perform(action)
                        onActionPerformed?(action)
                        withAnimation { isPresented = false }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: pt(1))
                            desktopActionIcon(action)
                        }
                        .frame(width: pt(80), height: pt(80))
                        .neoMenuItemGazeHighlight(.circle)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text(action.title)
                        .font(.system(size: pt(14), weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .hoverEffectDisabled(true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DesktopKeyboardSender.perform(action)
                            onActionPerformed?(action)
                            withAnimation { isPresented = false }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func desktopActionIcon(_ action: DesktopAction) -> some View {
        if action.usesTextIcon, let label = action.textIcon {
            Text(label)
                .font(.system(size: pt(action.title.hasPrefix("F") ? 20 : 22), weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        } else {
            Image(systemName: action.systemImage)
                .font(.system(size: pt(28)))
                .foregroundColor(.white)
        }
    }
}
