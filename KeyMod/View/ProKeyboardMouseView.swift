//
//  ProKeyboardMouseView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//  Renamed to align with Android's KM Pro view.
//

import SwiftUI
import UIKit

struct ProKeyboardMouseView: View {
    let keys: [[String]] = [
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    let extraKeys: [[String?]] = [
        ["PrtSc", "Scroll Lock", "Pause"],
        ["Insert", "Home", "PgUp"],
        ["Delete", "End", "PgDn"],
        [nil, nil, "↑", nil, nil],
        [nil, "←", "↓", "→", nil]
    ]

    let extraNumberKeys: [String] = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0", "."]

    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @ObservedObject var orientationManager: OrientationManager

    @StateObject private var pointerTipState = PointerTipState()

    @State private var alternatesPopup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)? = nil
    @State private var alternatesCommitHandled = false
    @State private var alternateDragLocation: CGPoint? = nil
    @State private var alternatesSelectedIndex: Int = 0

    @State private var keyPressInProgress = false
    @State private var longPressTimer: Timer?
    @State private var currentlyPressedKey: String?

    @State private var keyRepeatController = KeyRepeatController()

    @State private var shortcutPage = 0
    @State private var fixedRowsLocalFnLocked = false

    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var profileMgr = ShortcutProfileManager.shared

    @State private var keyboardHeight: CGFloat = 0
    @State private var keyFrames: [String: CGRect] = [:]

    @State private var isTextInputMode = false
    @State private var textInputContent = ""
    @State private var savedTextInputContent = ""
    @State private var isTextInputExpanded = false
    @State private var showTouchpadHelp = false


    // MARK: - Android-parity shortcut strip data

    private var shortcutPages: [ShortcutPage] {
        let primaryMod = aiSettings.targetOS == .macOS ? "Cmd" : "Ctrl"
        let combo = { (mods: [String], key: String) in self.keyboardManager.handleKeyCombo(modifiers: mods, key: key) }

        var sourceItems: [ShortcutItem] = []
        if let active = profileMgr.activeProfile {
            let myItems = profileMgr.myShortcuts(for: active.id)
            if !myItems.isEmpty { sourceItems = myItems }
            else if let firstCat = active.categories.first { sourceItems = Array(firstCat.shortcuts.prefix(7)) }
        }
        if !sourceItems.isEmpty {
            let entries = sourceItems.map { item -> ShortcutEntry in
                let mods = (item.modifier ?? "").split(separator: "+").map(String.init)
                return ShortcutEntry(label: String(item.description.prefix(8)), icon: nil) {
                    mods.isEmpty ? self.keyboardManager.handleSpecialKey(item.keyCode) : self.keyboardManager.handleKeyCombo(modifiers: mods, key: item.keyCode)
                }
            }
            let chunks = stride(from: 0, to: entries.count, by: 7).map { Array(entries[$0..<min($0+7, entries.count)]) }
            let name = profileMgr.activeProfile?.name ?? ""
            return chunks.enumerated().map { (idx, c) in ShortcutPage(title: c.count > 1 ? "\(name) \(idx+1)/\(c.count)" : name, entries: c) }
        }
        return [ShortcutPage(title: "Standard", entries: [
            ShortcutEntry(label: "ALL",   icon: "text.badge.checkmark") { combo([primaryMod], "A") },
            ShortcutEntry(label: "COPY",  icon: "doc.on.doc")           { combo([primaryMod], "C") },
            ShortcutEntry(label: "CUT",   icon: "scissors")             { combo([primaryMod], "X") },
            ShortcutEntry(label: "PASTE", icon: "clipboard")            { combo([primaryMod], "V") },
            ShortcutEntry(label: "SAVE",  icon: "externaldrive")        { combo([primaryMod], "S") },
            ShortcutEntry(label: "UNDO",  icon: "arrow.uturn.backward") { combo([primaryMod], "Z") },
            ShortcutEntry(label: "FIND",  icon: "magnifyingglass")      { combo(["Ctrl"], "F") },
        ])]
    }

    private var fixedRowsPages: [FixedRowsPage] {
        [fixedRowsPage0, fixedRowsPage1, fixedRowsPage2, fixedRowsPage3]
    }

    private var fixedRowsToggleEntry: ShortcutEntry {
        ShortcutEntry(label: "", icon: "arrow.left.arrow.right", isActive: fixedRowsLocalFnLocked) {
            withAnimation(.easeInOut(duration: 0.15)) { fixedRowsLocalFnLocked.toggle() }
        }
    }

    /// Page 0 — F-keys / number-symbol converted layer
    private var fixedRowsPage0: FixedRowsPage {
        let row1: [ShortcutEntry]
        let row2: [ShortcutEntry]

        if fixedRowsLocalFnLocked {
            row1 = ["7", "8", "9", "0", "+", "-", "*"].map { Self.textEntry(keyboardManager, label: $0) }
            row2 = ["1", "2", "3", "4", "5", "6"].map { Self.textEntry(keyboardManager, label: $0) }
                + [fixedRowsToggleEntry]
        } else {
            row1 = ["F7", "F8", "F9", "F10", "F11", "F12"].map { Self.keyEntry(keyboardManager, label: $0, icon: "") }
                + [Self.textEntry(keyboardManager, label: "#")]
            row2 = ["F1", "F2", "F3", "F4", "F5", "F6"].map { Self.keyEntry(keyboardManager, label: $0, icon: "") }
                + [fixedRowsToggleEntry]
        }

        return FixedRowsPage(
            row1: row1,
            row2: row2
        )
    }

    /// Page 1 — Modifiers + Navigation / converted navigation layer
    private var fixedRowsPage1: FixedRowsPage {
        let isMacOS   = aiSettings.targetOS == .macOS
        let isWindows = aiSettings.targetOS == .windows
        let modifierConfigs: [(key: String, label: String, icon: String)] = isMacOS
            ? [("Ctrl", "", "control"), ("Alt", "", "option"), ("Cmd", "", "command")]
            : isWindows
                ? [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "", "logo.windows")]
                : [("Ctrl", "CTRL", ""), ("Alt", "ALT", ""), ("Cmd", "SUP", "")]

        let modifierEntries = modifierConfigs.map { config -> ShortcutEntry in
            ShortcutEntry(label: config.label, icon: config.icon.isEmpty ? nil : config.icon,
                          isActive: keyboardManager.activeModifiers.contains(config.key))
                { keyboardManager.handleModifierToggle(config.key) }
        }

        let row1: [ShortcutEntry]
        let row2: [ShortcutEntry]

        if fixedRowsLocalFnLocked {
            row1 = [
                Self.keyEntry(keyboardManager, label: "SCR", icon: "", key: "Scroll Lock"),
                Self.keyEntry(keyboardManager, label: "PRT", icon: "", key: "PrtSc"),
                Self.keyEntry(keyboardManager, label: "CAPS", icon: "", key: "Caps"),
                Self.keyEntry(keyboardManager, label: "PAUSE", icon: "", key: "Pause"),
                Self.keyEntry(keyboardManager, label: "HOME", icon: "", key: "Home"),
                Self.keyEntry(keyboardManager, label: "PGUP", icon: "", key: "PgUp"),
                ShortcutEntry(label: "", icon: "keyboard", badge: isTextInputMode ? "A" : "B")
                    { withAnimation { isTextInputMode.toggle() } },
            ]
            row2 = [
                Self.keyEntry(keyboardManager, label: "SPACE", icon: "", key: "Space"),
                Self.keyEntry(keyboardManager, label: "BKSP", icon: "delete.left", key: "Backspace"),
                Self.keyEntry(keyboardManager, label: "DEL", icon: "delete.forward", key: "Delete"),
                Self.keyEntry(keyboardManager, label: "INS", icon: "", key: "Insert"),
                Self.keyEntry(keyboardManager, label: "END", icon: "", key: "End"),
                Self.keyEntry(keyboardManager, label: "PGDN", icon: "", key: "PgDn"),
                fixedRowsToggleEntry,
            ]
        } else {
            row1 = modifierEntries + [
                Self.keyEntry(keyboardManager, label: "TAB", icon: "arrow.right.to.line.compact", key: "Tab"),
                Self.keyEntry(keyboardManager, label: "UP", icon: "arrow.up", key: "Up"),
                Self.keyEntry(keyboardManager, label: "ENTER", icon: "return", key: "Enter"),
                ShortcutEntry(label: "", icon: "keyboard", badge: isTextInputMode ? "A" : "B")
                    { withAnimation { isTextInputMode.toggle() } },
            ]
            row2 = [
                Self.keyEntry(keyboardManager, label: "ESC", icon: "escape", key: "Escape"),
                Self.modifierEntry(keyboardManager, label: "SHIFT", icon: "shift", key: "Shift"),
                Self.keyEntry(keyboardManager, label: "DEL", icon: "delete.forward", key: "Delete"),
                Self.keyEntry(keyboardManager, label: "LEFT", icon: "arrow.left", key: "Left"),
                Self.keyEntry(keyboardManager, label: "DOWN", icon: "arrow.down", key: "Down"),
                Self.keyEntry(keyboardManager, label: "RIGHT", icon: "arrow.right", key: "Right"),
                fixedRowsToggleEntry,
            ]
        }

        return FixedRowsPage(
            row1: row1,
            row2: row2
        )
    }

    /// Page 2 — Punctuation symbols / converted punctuation layer
    private var fixedRowsPage2: FixedRowsPage {
        FixedRowsPage(
            row1: (fixedRowsLocalFnLocked
                ? ["`", "~", "'", "\"", "%", "^", "|"]
                : ["(", ")", "[", "]", ":", "#", "@"])
                .map { Self.textEntry(keyboardManager, label: $0) },
            row2: (fixedRowsLocalFnLocked
                ? ["<", ">", "*", "&", ",", "."]
                : ["/", "\\", "|", "?", "-", "_"])
                .map { Self.textEntry(keyboardManager, label: $0) }
                + [fixedRowsToggleEntry]
        )
    }

    /// Page 3 — Profile quick-switch + converted-layer toggle
    private var fixedRowsPage3: FixedRowsPage {
        let profiles = profileMgr.allProfiles
        let activeid = profileMgr.activeProfileId
        func profileRow(start: Int, capacity: Int) -> [ShortcutEntry] {
            (0..<capacity).map { i -> ShortcutEntry in
                guard start + i < profiles.count else { return ShortcutEntry(label: "", icon: nil) {} }
                let p = profiles[start + i]
                return ShortcutEntry(label: String(p.name.prefix(6)), icon: nil, isActive: p.id == activeid)
                    { withAnimation { profileMgr.activeProfileId = p.id } }
            }
        }
        return FixedRowsPage(
            row1: profileRow(start: 0, capacity: 7),
            row2: profileRow(start: 7, capacity: 6) + [fixedRowsToggleEntry]
        )
    }

    /// Profile switcher dropdown — shows current profile name, tap to pick another.
    @ViewBuilder
    private var profileSwitcher: some View {
        Menu {
            ForEach(profileMgr.profilesForPicking, id: \.id) { profile in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { profileMgr.activeProfileId = profile.id; shortcutPage = 0 }
                }) {
                    HStack {
                        if profile.id == profileMgr.activeProfileId { Image(systemName: "checkmark") }
                        Text(profile.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 11))
                Text(profileMgr.activeProfile?.name ?? "Profile")
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundColor(.secondary).padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(UIColor.secondarySystemBackground)).cornerRadius(8)
        }
    }

    // MARK: - Shortcut helpers

    private static func modifierEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        return ShortcutEntry(label: label, icon: icon, isActive: km.activeModifiers.contains(k)) { km.handleModifierToggle(k) }
    }
    private static func keyEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        return ShortcutEntry(label: label, icon: icon.isEmpty ? nil : icon) { km.handleKeyPress(k) }
    }
    private static func textEntry(_ km: KeyboardManager, label: String) -> ShortcutEntry {
        return ShortcutEntry(label: label, icon: nil) { km.handleTextInput(label) }
    }

    // MARK: - Touchpad helper

    private func touchpadOverlay(showLabel: Bool = true) -> some View {
        GeometryReader { geo in
            let stripWidth = max(28, geo.size.width * 0.30)
            HStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Button(action: { showTouchpadHelp = true }) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.9))
                            .clipShape(Circle())
                    }
                    .padding(8)

                    if showLabel {
                        touchpadLabel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: max(0, geo.size.width - stripWidth))

                BasicTouchpadScrollStripView(
                    mouseManager: mouseManager,
                    labelFontSize: orientationManager.isLandscape ? 10 : 7
                )
                .frame(width: stripWidth)
            }
            .background(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
        }
    }

    private var touchpadLabel: some View {
        VStack(spacing: 4) {
            Text("Touch Pad").font(.caption).foregroundColor(.secondary)
            Text("Openterface").font(.caption2).foregroundColor(.secondary.opacity(0.7))
        }
    }

    private var touchpadHelpSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Touchpad Help")
                    .font(.headline)
                Spacer()
                Button("Done") { showTouchpadHelp = false }
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use these gestures in Pro Keyboard & Mouse mode:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Group {
                        Text("1. One finger drag: move pointer")
                        Text("2. Single tap: left click")
                        Text("3. Double tap: double click")
                        Text("4. Two-finger tap: right click")
                        Text("5. Two-finger drag: wheel scrolling")
                        Text("6. Long press: toggle drag mode")
                        Text("7. Right vertical strip: quick page scroll")
                    }
                    .font(.body)

                    Text("Tip: While drag mode is active, the touchpad background turns blue.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    enum DisplayMode: Int, CaseIterable {
        case both = 0
        case keyboard
        case touchpad

        mutating func toggle() {
            self = DisplayMode(rawValue: (self.rawValue + 1) % 3) ?? .both
        }

        var icon: String {
            switch self {
            case .both: return "rectangle.split.3x1"
            case .keyboard: return "keyboard"
            case .touchpad: return "rectangle.and.hand.point.up.left.filled"
            }
        }
    }
    @State private var displayMode: DisplayMode = .both

    // Compute display value for a legacy string key (used by fallback keyboard layout)
    func getDisplayValue(for key: String) -> String {
        let kd = KeyboardManager.KeyDef(key, "")
        if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty { return kd.symbolLabel }
        if let letter = letterDisplay(kd.label) { return letter }
        if keyboardManager.activeModifiers.contains("Shift") {
            return shiftMap[key] ?? key
        }
        return key
    }

    /// Get display label for a KeyDef, respecting Shift/Caps/Fn state.
    func displayLabel(for kd: KeyboardManager.KeyDef) -> String {
        if let fnKey = keyboardManager.resolveFnKey(kd.label) { return fnKey }
        if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty { return kd.symbolLabel }
        if let letter = letterDisplay(kd.label) { return letter }
        return kd.label
    }

    private func letterDisplay(_ char: String) -> String? {
        guard char.count == 1, let c = char.first, c.isLetter else { return nil }
        let isShift = keyboardManager.activeModifiers.contains("Shift")
        let isCaps = keyboardManager.capsLockActive
        return (isShift != isCaps) ? char.uppercased() : char.lowercased()
    }

    private var shiftMap: [String: String] {
        ["`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
         "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
         "-": "_", "=": "+", "[": "{", "]": "}",
         ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    if orientationManager.isLandscape { landscapeContent(geometry) }
                    else { portraitContent(geometry) }
                }
                // Alternates popup overlay
                if let popup = alternatesPopup {
                    KeyAlternatesPopupView(options: popup.options, anchorFrame: popup.anchor,
                        dragLocation: alternateDragLocation,
                        selectedIndex: $alternatesSelectedIndex,
                        onCommit: { option in
                            alternatesCommitHandled = true
                            HapticFeedbackManager.shared.triggerButtonPress()
                            if option.requiresShift {
                                keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: option.keyCode)
                            } else { keyboardManager.handleKeyPress(option.keyCode) }
                            dismissAlternatesPopup()
                        },
                        onCancel: { alternatesCommitHandled = false; dismissAlternatesPopup() })
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .coordinateSpace(name: "proKMView")
            .sheet(isPresented: $showTouchpadHelp) {
                touchpadHelpSheet
            }
            .offset(y: isTextInputMode ? (keyboardHeight > 0 ? -keyboardHeight * 0.65 : 30) : 0)
            .animation(.easeOut(duration: 0.3), value: keyboardHeight)
            .animation(.easeOut(duration: 0.3), value: isTextInputMode)
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
                    if let kf = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect { keyboardHeight = kf.height }
                }
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in keyboardHeight = 0 }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
            }
        }
    }

    // MARK: - Landscape layout

    @ViewBuilder
    private func landscapeContent(_ geometry: GeometryProxy) -> some View {
        if displayMode == .touchpad {
            ZStack {
                touchpadOverlay().frame(maxWidth: .infinity, maxHeight: .infinity)
                landscapeHandleButton
            }
        } else {
            HStack(spacing: 0) {
                if displayMode != .keyboard { touchpadOverlay().frame(maxWidth: geometry.size.width * 0.3) }
                if displayMode != .touchpad {
                    HStack(spacing: 0) {
                        if displayMode == .keyboard && isTopOnLeft { Color.black.frame(width: 60) }
                        VStack(spacing: 0) {
                            if displayMode == .keyboard { landscapeKeyboardView }
                            else { keyboardLayoutView }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if displayMode == .keyboard && isTopOnRight { Color.black.frame(width: 60) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var landscapeHandleButton: some View {
        VStack {
            Button(action: { displayMode.toggle() }) {
                RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 48, height: 24)
                    .overlay(Rectangle().fill(Color.gray.opacity(0.6)).frame(width: 36, height: 3).cornerRadius(1.5))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
            }.buttonStyle(PlainButtonStyle())
            Spacer()
        }.padding(.top, 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var landscapeKeyboardView: some View {
        GeometryReader { innerGeometry in
            VStack(spacing: 0) {
                ForEach(keysForCurrentOrientation, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { key in legacyKeyButton(key) }
                    }
                    .frame(maxHeight: innerGeometry.size.height / CGFloat(keysForCurrentOrientation.count))
                }
            }
        }
    }

    @ViewBuilder
    private func legacyKeyButton(_ key: String) -> some View {
        Button(action: { keyboardManager.handleSpecialKey(key) }) {
            legacyKeyContent(key)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(legacyKeyBg(key)).cornerRadius(9)
                .foregroundColor(legacyKeyFg(key))
        }
    }

    @ViewBuilder
    private func legacyKeyContent(_ key: String) -> some View {
        switch key {
        case "Backspace": Image(systemName: "delete.left").font(.system(size: 16))
        case "Enter": Image(systemName: "return").font(.system(size: 16))
        case "Shift":
            Image(systemName: "shift").font(.system(size: 16))
        default:
            Text(getDisplayValue(for: key)).font(.system(size: 12))
        }
    }

    private func legacyKeyBg(_ key: String) -> Color {
        if key == "Shift" { return keyboardManager.activeModifiers.contains("Shift") ? .blue : Self.functionKeyBg }
        if ["Ctrl", "Alt", "Cmd"].contains(key) { return keyboardManager.activeModifiers.contains(key) ? .blue : Self.functionKeyBg }
        if key == "Caps" { return keyboardManager.capsLockActive ? .green : Self.functionKeyBg }
        return Self.regularKeyBg
    }

    private func legacyKeyFg(_ key: String) -> Color {
        if ["Shift", "Ctrl", "Alt", "Cmd"].contains(key) { return keyboardManager.activeModifiers.contains(key) ? .white : .primary }
        if key == "Caps" { return keyboardManager.capsLockActive ? .white : .primary }
        return .primary
    }

    // MARK: - Portrait layout

    @ViewBuilder
    private func portraitContent(_ geometry: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if displayMode != .keyboard {
                    touchpadOverlay().frame(maxWidth: .infinity).frame(height: geometry.size.height * 0.50)
                        .opacity(isTextInputMode && isTextInputExpanded ? 0 : 1)
                }
                if displayMode != .touchpad {
                    if isTextInputMode && !isTextInputExpanded { ScrollView { shortcutPanelContent } }
                    else { VStack(spacing: 0) { shortcutPanelContent }.frame(maxWidth: .infinity) }
                }
            }
            if isTextInputMode && isTextInputExpanded { expandedTextInputView(geometry) }
        }
    }

    private var shortcutPanelContent: some View {
        VStack(spacing: 0) {
            HStack { profileSwitcher; Spacer() }.padding(.horizontal, 8).padding(.bottom, 2)
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4).padding(.bottom, 2)
            keyboardLayoutView.frame(height: 240).padding(.bottom, 10)
            if displayMode == .keyboard && !orientationManager.isLandscape { extraKeysView.padding(.top, 8) }
            if isTextInputMode && !isTextInputExpanded { textInputView.frame(height: 140).padding(.bottom, 10) }
            bottomToolbar.padding(.horizontal, 4).padding(.bottom, 4)
        }
    }

    private func expandedTextInputView(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            textInputView.frame(maxHeight: geometry.size.height * 0.50)
            bottomToolbar.padding(.horizontal, 4)
        }.padding(.top, 90).padding(.bottom, 30).padding(.horizontal, 8)
            .background(Color(UIColor.systemBackground)).zIndex(10)
    }

    // Helper to determine if the top is on the left or right in landscape
    private var isTopOnLeft: Bool {
        guard orientationManager.isLandscape else { return false }
        return UIDevice.current.orientation == .landscapeLeft
    }
    private var isTopOnRight: Bool {
        guard orientationManager.isLandscape else { return false }
        return UIDevice.current.orientation == .landscapeRight
    }

    var keysForCurrentOrientation: [[String]] { keys }

    @ViewBuilder
    private var keyboardLayoutView: some View {
        VStack(spacing: 0) {
            ForEach(keyboardManager.portraitLetterKeys.indices, id: \.self) { rowIdx in
                let row = keyboardManager.portraitLetterKeys[rowIdx]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { colIdx in
                        let kd = row[colIdx]
                        keyButton(for: kd, width: keyWidth(for: kd, row: row))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyWidth(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef]) -> CGFloat {
        // Special widths matching Android layout
        switch kd.label {
        case "Shift": return 0.15
        case "Fn": return 0.15
        case "Cmd", "Win": return 0.10
        case "Space": return 0.40
        case "Enter": return 0.15
        case "Backspace": return 0.095
        case ",", ".": return 0.10
        case "/": return 0.15
        default: return 1.0 / CGFloat(row.count)
        }
    }

    /// Build a single key button with long-press alternates and repeat support.
    @ViewBuilder
    private func keyButton(for kd: KeyboardManager.KeyDef, width: CGFloat) -> some View {
        let displayText = displayLabel(for: kd)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Shift"].contains(kd.label)
        let isPressed = isModifier && keyboardManager.activeModifiers.contains(kd.label)
        let isActive = (kd.label == "Caps" && keyboardManager.capsLockActive) || (kd.label == "Fn" && keyboardManager.isFnLocked)

        keyContent(for: kd, displayText: displayText)
            .frame(maxWidth: .infinity, maxHeight: 48)
            .background(keyBackground(for: kd, pressed: isPressed, active: isActive))
            .cornerRadius(9).foregroundColor(isPressed || isActive ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(cornerHint(for: kd), alignment: .topTrailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("proKMView"))
                    .onChanged { value in
                        if !keyPressInProgress {
                            keyPressInProgress = true; currentlyPressedKey = kd.label
                            handleKeyPress(kd)
                            if keyboardManager.shouldShowAlternates(for: kd.label) {
                                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                                    showAlternatesPopup(for: kd)
                                }
                            }
                        }
                        // Forward drag location to popup if it is showing
                        if alternatesPopup != nil {
                            alternateDragLocation = value.location
                        }
                    }
                    .onEnded { value in
                        longPressTimer?.invalidate(); longPressTimer = nil
                        keyPressInProgress = false; currentlyPressedKey = nil
                        if let popup = alternatesPopup {
                            // Commit the currently highlighted alternate option
                            let sorted = popup.options.sorted { a, b in
                                let order = [AlternatePopupGeometry.slotCenter, AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotRight,
                                             AlternatePopupGeometry.slotUp, AlternatePopupGeometry.slotDown,
                                             AlternatePopupGeometry.slotUpLeft, AlternatePopupGeometry.slotUpRight,
                                             AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDownRight]
                                let ai = order.firstIndex(of: a.slot) ?? 99
                                let bi = order.firstIndex(of: b.slot) ?? 99
                                return ai < bi
                            }
                            if alternatesSelectedIndex < sorted.count {
                                let option = sorted[alternatesSelectedIndex]
                                alternatesCommitHandled = true
                                HapticFeedbackManager.shared.triggerButtonPress()
                                if option.requiresShift {
                                    keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: option.keyCode)
                                } else {
                                    keyboardManager.handleKeyPress(option.keyCode)
                                }
                            }
                            dismissAlternatesPopup()
                        }
                        handleKeyRelease()
                    }
            )
            .background(GeometryReader { geo -> Color in
                DispatchQueue.main.async { self.keyFrames[kd.label] = geo.frame(in: .named("proKMView")) }
                return Color.clear
            })
    }
    
    /// Unified handler for key press - handles both single tap and long press
    private func handleKeyPress(_ kd: KeyboardManager.KeyDef) {
        if alternatesCommitHandled { alternatesCommitHandled = false; return }
        HapticFeedbackManager.shared.triggerButtonPress()

        switch kd.label {
        case "Fn": keyboardManager.isFnLocked.toggle()
        case "ABC", "12/34": keyboardManager.isSymbolMode.toggle()
        case "!?#": keyboardManager.isSymbolMode = true
        case "Ctrl", "Alt", "Cmd", "Win", "Shift": keyboardManager.handleSpecialKey(kd.label)
        default:
            let effectiveKey = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
            if KeyRepeatController.repeatableKeys.contains(effectiveKey) {
                keyboardManager.handleSpecialKey(effectiveKey)
                keyRepeatController.startRepeating { keyboardManager.handleSpecialKey(effectiveKey) }
            } else {
                keyRepeatController.stopRepeating()
                keyboardManager.handleSpecialKey(effectiveKey)
            }
        }
    }

    @ViewBuilder
    private func keyContent(for kd: KeyboardManager.KeyDef, displayText: String) -> some View {
        switch kd.label {
        case "Backspace":
            Image(systemName: "delete.left")
                .font(.system(size: 16))
                .rotationEffect(kd.symbolLabel.isEmpty && keyboardManager.activeModifiers.contains("Shift") ? .degrees(180) : .degrees(0))
        case "Enter":
            Image(systemName: "return").font(.system(size: 16))
        case "Shift":
            Image(systemName: "shift").font(.system(size: 16))
        case "Cmd":
            // Target OS label: show Cmd/Win/Super based on settings
            switch aiSettings.targetOS {
            case .windows: Text("Win").font(.system(size: 12))
            case .linux: Text("Super").font(.system(size: 10))
            default: Text("Cmd").font(.system(size: 12))
            }
        case "Ctrl", "Alt":
            Text(getDisplayValue(for: kd.label)).font(.system(size: 12))
        case "Caps": Text("Caps").font(.system(size: 11))
        case "Fn": Text("Fn").font(.system(size: 12, weight: .bold))
        default:
            if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty {
                Text(kd.symbolLabel).font(.system(size: 14))
            } else {
                Text(displayText).font(.system(size: 12))
            }
        }
    }

    /// Whether a key is a "function" key (F-row, modifiers, special action keys) that gets a gray bg.
    private func isFunctionKey(_ kd: KeyboardManager.KeyDef) -> Bool {
        let functionLabels = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Fn", "Backspace", "Enter"]
        return functionLabels.contains(kd.label) || keyboardManager.isSymbolMode && ["ABC", "12/34", "!?#"].contains(kd.label)
    }

    /// System-adaptive backgrounds for keys (auto light/dark).
    private static let functionKeyBg = Color(UIColor.secondarySystemBackground)
    private static let regularKeyBg = Color(UIColor.systemBackground)

    private func keyBackground(for kd: KeyboardManager.KeyDef, pressed: Bool, active: Bool) -> Color {
        if pressed || active { return .blue }
        if isFunctionKey(kd) { return Self.functionKeyBg }
        return Self.regularKeyBg
    }

    @ViewBuilder
    private func cornerHint(for kd: KeyboardManager.KeyDef) -> some View {
        if !kd.cornerHint.isEmpty && !keyboardManager.isFnLocked && keyboardManager.isSymbolMode == false {
            Text(kd.cornerHint)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.25))
                .padding(.trailing, 6)
                .padding(.top, 2)
                .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private var extraKeysView: some View {
        let arrowMap = ["↑": "Up", "↓": "Down", "←": "Left", "→": "Right"]
        VStack(spacing: 4) {
            ForEach(extraKeys.indices, id: \.self) { rowIdx in
                HStack(spacing: 4) {
                    ForEach(extraKeys[rowIdx].indices, id: \.self) { colIdx in
                        if let key = extraKeys[rowIdx][colIdx] {
                            let mapped = arrowMap[key] ?? key
                            Button(action: { keyboardManager.handleSpecialKey(mapped) }) {
                                Text(key).font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(Self.functionKeyBg).cornerRadius(9).foregroundColor(.primary)
                            }
                        } else { Spacer() }
                    }
                }
            }
            if displayMode == .keyboard && !orientationManager.isLandscape { numberPadView }
        }.padding(.horizontal, 8)
    }

    @ViewBuilder
    private var numberPadView: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in numberPadButton(extraNumberKeys[row * 3 + col]) }
                }
            }
            HStack(spacing: 3) { numberPadButton("0"); numberPadButton(".") }
        }
    }

    private func numberPadButton(_ key: String) -> some View {
        let mapped = key == "0" ? "Numpad0" : key == "." ? "NumpadDot" : "Numpad\(key)"
        return Button(action: { keyboardManager.handleSpecialKey(mapped) }) {
            Text(key).font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Self.functionKeyBg).cornerRadius(9).foregroundColor(.primary)
        }
    }

    // MARK: - Key Action Handler

    /// Called when finger lifts off any key — stops key repeat if active.
    private func handleKeyRelease() {
        keyRepeatController.stopRepeating()
    }

    // MARK: - Alternates Popup

    private func showAlternatesPopup(for kd: KeyboardManager.KeyDef) {
        guard keyboardManager.shouldShowAlternates(for: kd.label) else { return }
        var slotMap: [Int: AlternateOption] = [:]
        var seen: Set<String> = []

        func addOption(_ slot: Int, _ alt: String) {
            guard let mapped = mapAsciiAlternate(alt), !seen.contains(mapped.display) else { return }
            slotMap[slot] = AlternateOption(display: mapped.display, keyCode: mapped.keyCode, requiresShift: mapped.requiresShift, slot: slot)
            seen.insert(mapped.display)
        }

        if let centerOpt = centerAlternateOption(for: kd), !seen.contains(centerOpt.display) {
            slotMap[AlternatePopupGeometry.slotCenter] = centerOpt; seen.insert(centerOpt.display)
        }
        let cardinalSlots = [AlternatePopupGeometry.slotUp, AlternatePopupGeometry.slotDown, AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotRight]
        for (i, slot) in cardinalSlots.enumerated() where i < kd.alternates.count { addOption(slot, kd.alternates[i]) }
        let cornerSlots = [AlternatePopupGeometry.slotUpLeft, AlternatePopupGeometry.slotUpRight, AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDownRight]
        for (i, slot) in cornerSlots.enumerated() where i + 4 < kd.alternates.count { addOption(slot, kd.alternates[i + 4]) }

        let options = Array(slotMap.values)
        guard options.count >= 2 else { return }
        alternatesPopup = (options, keyFrames[kd.label] ?? .zero, kd)
    }

    /// Build the center (default) option for a key.
    private func centerAlternateOption(for kd: KeyboardManager.KeyDef) -> AlternateOption? {
        if kd.label.count == 1, let c = kd.label.first, c.isLetter {
            return AlternateOption(display: kd.label.uppercased(), keyCode: kd.label, requiresShift: true, slot: AlternatePopupGeometry.slotCenter)
        }
        guard let mapped = mapAsciiAlternate(kd.label) else { return nil }
        return AlternateOption(display: mapped.display, keyCode: mapped.keyCode, requiresShift: mapped.requiresShift, slot: AlternatePopupGeometry.slotCenter)
    }

    private static let shiftKeyMap: [String: (base: String, display: String)] = [
        "!": ("1", "!"), "@": ("2", "@"), "#": ("3", "#"), "$": ("4", "$"), "%": ("5", "%"),
        "^": ("6", "^"), "&": ("7", "&"), "*": ("8", "*"), "(": ("9", "("), ")": ("0", ")"),
        "_": ("-", "_"), "+": ("=", "+"), "{": ("[", "{"), "}": ("]", "}"),
        "<": (",", "<"), ">": (".", ">"), "?": ("/", "?"), ":": (";", ":"),
        "\"": ("'", "\""), "~": ("`", "~"),
    ]

    private func mapAsciiAlternate(_ char: String) -> (display: String, keyCode: String, requiresShift: Bool)? {
        guard char.count == 1 else { return nil }
        let c = char.first!
        if c.isLetter {
            return c.isLowercase ? (char, char, false) : (char, char.lowercased(), true)
        }
        if let entry = Self.shiftKeyMap[char] {
            return (entry.display, entry.base, true)
        }
        if "0123456789".contains(c) || "-=[];',./`".contains(c) {
            return (char, char, false)
        }
        return nil
    }

    private func dismissAlternatesPopup() {
        alternatesPopup = nil
        alternateDragLocation = nil
        alternatesCommitHandled = false
    }
    
    // MARK: - Text Input View

    private var textInputView: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $textInputContent)
                    .font(.system(size: 14)).padding(8).padding(.trailing, 40).padding(.bottom, 40)
                    .background(Color(UIColor.systemBackground)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 1))
                if textInputContent.isEmpty {
                    Text("Type and edit long text here - tap Send to send it to the connected device")
                        .font(.system(size: 14)).foregroundColor(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 16).allowsHitTesting(false)
                }
                VStack { Spacer(); HStack { Spacer(); expandButton } }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }

    private var expandButton: some View {
        Button(action: { withAnimation { isTextInputExpanded.toggle() } }) {
            Image(systemName: isTextInputExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 14)).foregroundColor(.blue).padding(8)
                .background(Color(UIColor.secondarySystemBackground)).cornerRadius(6)
        }.padding(8)
    }

    /// Bottom toolbar with mode switch, restore, and clear buttons
    private var bottomToolbar: some View {
        HStack(spacing: 4) {
            if isTextInputMode {
                toolbarButton("Restore", "arrow.uturn.backward", .orange, disabled: savedTextInputContent.isEmpty) {
                    textInputContent = savedTextInputContent
                }
                toolbarButton("Clear", "trash", .red, disabled: textInputContent.isEmpty) {
                    savedTextInputContent = textInputContent; textInputContent = ""
                }
                Spacer()
                Button(action: { sendTextToDevice() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "paperplane.fill").font(.system(size: 12))
                        Text("Send").font(.system(size: 11, weight: .medium))
                    }.foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(textInputContent.isEmpty ? Color.gray : Color.blue).cornerRadius(6)
                }.disabled(textInputContent.isEmpty)
            }
        }
    }

    private func toolbarButton(_ title: String, _ icon: String, _ color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 11, weight: .medium))
            }.foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground)).cornerRadius(6)
        }.disabled(disabled)
    }

    /// Send text content to the connected device
    private func sendTextToDevice() {
        guard !textInputContent.isEmpty else { return }
        savedTextInputContent = textInputContent
        let characters = Array(textInputContent)
        for (index, char) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                self.keyboardManager.handleKeyPress(char.isNewline ? "Enter" : String(char))
            }
        }
        textInputContent = ""
        HapticFeedbackManager.shared.triggerButtonPress()
    }
}
