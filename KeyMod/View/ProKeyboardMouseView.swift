//
//  ProKeyboardMouseView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//  Renamed to align with Android's KM Pro view.
//

import SwiftUI
import UIKit

/// Transparent UITextField that captures system-keyboard (IME) input in portrait B mode.
/// Matches Android's km_pro_ime_host: transparent background, 1sp text, no cursor, no suggestions.
private struct ImeCaptureTextField: UIViewRepresentable {
    @Binding var text: String
    var isActive: Bool

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.backgroundColor = .clear
        tf.textColor = .clear
        tf.tintColor = .clear
        tf.borderStyle = .none
        tf.font = .systemFont(ofSize: 1)
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.returnKeyType = .default
        tf.inputAssistantItem.leadingBarButtonGroups = []
        tf.inputAssistantItem.trailingBarButtonGroups = []
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        tf.delegate = context.coordinator
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if isActive && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isActive && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ImeCaptureTextField
        init(_ parent: ImeCaptureTextField) { self.parent = parent }

        @objc func textChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        // Append newline so LCP diff sends HID Enter; return false keeps keyboard visible.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let newText = (textField.text ?? "") + "\n"
            textField.text = newText
            parent.text = newText
            return false
        }
    }
}

struct ProKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @ObservedObject var orientationManager: OrientationManager

    @StateObject private var pointerTipState = PointerTipState()

    @State private var alternatesPopup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)? = nil
    @State private var alternatesGestureStart: CGPoint? = nil
    @State private var alternatesPick: AlternatesPick = .none
    @State private var currentDragLocation: CGPoint? = nil

    @State private var keyPressInProgress = false
    @State private var longPressTimer: Timer?
    @State private var currentlyPressedKey: String?

    @State private var keyRepeatController = KeyRepeatController()

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

    // MARK: - Landscape full/split layout & portrait BI/IME persistence

    private enum LandscapeLayout: String { case full = "full", split = "split" }
    private enum PortraitInput: String { case builtIn = "built_in", ime = "ime" }

    private static let landscapeLayoutKey = "km_pro_landscape_layout"
    @AppStorage("km_pro_landscape_layout") private var persistedLandscapeLayoutRawValue: String = LandscapeLayout.full.rawValue
    private static let portraitInputKey = "km_pro_portrait_input_surface"

    private var persistedLandscapeLayout: LandscapeLayout {
        LandscapeLayout(rawValue: persistedLandscapeLayoutRawValue) ?? .full
    }

    private var persistedPortraitInput: PortraitInput {
        let raw = UserDefaults.standard.string(forKey: Self.portraitInputKey) ?? PortraitInput.builtIn.rawValue
        return PortraitInput(rawValue: raw) ?? .builtIn
    }

    @State private var isSplitLayout: Bool = false       // landscape full vs split
    @State private var isImeSurface: Bool = false         // portrait built-in vs IME
    @State private var imeLastSent: String = ""           // last text diff-sent to HID in IME mode

    @State private var splitShortcutCurrentPage: Int = 0
    @State private var splitShortcutDragOffset: CGFloat = 0
    @State private var splitShortcutIsDragging: Bool = false

    @State private var splitShortcutTopCurrentPage: Int = 1
    @State private var splitShortcutTopDragOffset: CGFloat = 0
    @State private var splitShortcutTopIsDragging: Bool = false
    @State private var splitShortcutBottomCurrentPage: Int = 1
    @State private var splitShortcutBottomDragOffset: CGFloat = 0
    @State private var splitShortcutBottomIsDragging: Bool = false


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
            let keyboardToggleBadge = orientationManager.isLandscape
                ? (isSplitLayout ? "S" : "F")
                : (!isImeSurface ? "A" : "B")
            row1 = [
                Self.keyEntry(keyboardManager, label: "SCR", icon: "", key: "Scroll Lock"),
                Self.keyEntry(keyboardManager, label: "PRT", icon: "", key: "PrtSc"),
                Self.keyEntry(keyboardManager, label: "CAPS", icon: "", key: "Caps"),
                Self.keyEntry(keyboardManager, label: "PAUSE", icon: "", key: "Pause"),
                Self.keyEntry(keyboardManager, label: "HOME", icon: "", key: "Home"),
                Self.keyEntry(keyboardManager, label: "PGUP", icon: "", key: "PgUp"),
                ShortcutEntry(label: "", icon: "keyboard", badge: keyboardToggleBadge) {
                    withAnimation {
                        if orientationManager.isLandscape {
                            isSplitLayout.toggle()
                            persistedLandscapeLayoutRawValue = isSplitLayout ? LandscapeLayout.split.rawValue : LandscapeLayout.full.rawValue
                        } else {
                            isImeSurface.toggle()
                            UserDefaults.standard.set(isImeSurface ? PortraitInput.ime.rawValue : PortraitInput.builtIn.rawValue,
                                                      forKey: Self.portraitInputKey)
                        }
                    }
                },
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
            let keyboardToggleBadge = orientationManager.isLandscape
                ? (isSplitLayout ? "S" : "F")
                : (!isImeSurface ? "A" : "B")
            row1 = modifierEntries + [
                Self.keyEntry(keyboardManager, label: "TAB", icon: "arrow.right.to.line.compact", key: "Tab"),
                Self.keyEntry(keyboardManager, label: "UP", icon: "arrow.up", key: "Up"),
                Self.keyEntry(keyboardManager, label: "ENTER", icon: "return", key: "Enter"),
                ShortcutEntry(label: "", icon: "keyboard", badge: keyboardToggleBadge) {
                    withAnimation {
                        if orientationManager.isLandscape {
                            isSplitLayout.toggle()
                            persistedLandscapeLayoutRawValue = isSplitLayout ? LandscapeLayout.split.rawValue : LandscapeLayout.full.rawValue
                        } else {
                            isImeSurface.toggle()
                            UserDefaults.standard.set(isImeSurface ? PortraitInput.ime.rawValue : PortraitInput.builtIn.rawValue,
                                                      forKey: Self.portraitInputKey)
                        }
                    }
                },
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
                    KeyAlternatesPopupView(options: popup.options, anchorFrame: popup.anchor, pick: alternatesPick)
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
                isSplitLayout = persistedLandscapeLayout == .split
                isImeSurface = persistedPortraitInput == .ime
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
        let barWidth: CGFloat = 50
        HStack(spacing: 0) {
            Color(UIColor.tertiarySystemBackground)
                .frame(width: barWidth)
            VStack(spacing: 0) {
                if displayMode == .touchpad {
                    VStack(spacing: 0) {
                        landscapeShortcutPanel(width: geometry.size.width - barWidth)
                        ZStack {
                            touchpadOverlay().frame(maxWidth: .infinity, maxHeight: .infinity)
                            landscapeHandleButton
                        }
                    }
                } else if isSplitLayout {
                    let contentWidth = geometry.size.width - barWidth
                    let touchpadWidth = contentWidth * 0.33
                    let sideWidth = max(0, (contentWidth - touchpadWidth) / 2)
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            splitTopSidePanel(pageIndex: splitShortcutTopCurrentPage, side: .left, width: sideWidth)
                                .frame(height: 44)
                            splitBottomSidePanel(pageIndex: splitShortcutBottomCurrentPage, side: .left, width: sideWidth)
                                .frame(height: 88)
                            splitKeyboardColumn(side: .left)
                        }
                        .frame(width: sideWidth)
                        .clipped()

                        touchpadOverlay().frame(width: touchpadWidth)

                        VStack(spacing: 0) {
                            splitTopSidePanel(pageIndex: splitShortcutTopCurrentPage, side: .right, width: sideWidth)
                                .frame(height: 44)
                            splitBottomSidePanel(pageIndex: splitShortcutBottomCurrentPage, side: .right, width: sideWidth)
                                .frame(height: 88)
                            splitKeyboardColumn(side: .right)
                        }
                        .frame(width: sideWidth)
                        .clipped()
                    }
                } else {
                    // Full mode: shortcut strip at top + keyboard fills remaining space
                    VStack(spacing: 0) {
                        landscapeShortcutPanel(width: geometry.size.width - barWidth)
                        landscapeKeyboardView
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    enum SplitSide { case left, right }

    @ViewBuilder
    private func splitKeyboardColumn(side: SplitSide) -> some View {
        let keys = side == .left ? splitLeftKeys : splitRightKeys
        GeometryReader { innerGeometry in
            VStack(spacing: 0) {
                ForEach(keys.indices, id: \.self) { rowIdx in
                    let row = keys[rowIdx]
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { colIdx in
                            let kd = row[colIdx]
                            let width = keyWidthSplit(for: kd, row: row, side: side, rowIndex: rowIdx)
                            keyButton(for: kd, width: width)
                                .frame(width: innerGeometry.size.width * width)
                        }
                    }
                    .frame(maxHeight: innerGeometry.size.height / CGFloat(keys.count))
                }
            }
        }
    }

    private func keyWidthSplit(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef], side: SplitSide, rowIndex: Int) -> CGFloat {
        let weights = row.map { splitKeyWeight(for: $0, rowIndex: rowIndex) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 1.0 / CGFloat(row.count) }
        return splitKeyWeight(for: kd, rowIndex: rowIndex) / totalWeight
    }

    private func splitKeyWeight(for kd: KeyboardManager.KeyDef, rowIndex: Int) -> CGFloat {
        switch rowIndex {
        case 0:
            // Row1: Tab + q-p + Backspace are equal weight in Android
            return 10
        case 1:
            // Row2: Fn 9.5, a 10.6, s-l 8.35, delete 11.55
            switch kd.label {
            case "Fn": return 9.5
            case "a": return 10.6
            case "s", "d", "f", "g", "h", "j", "k", "l": return 8.35
            case "Delete", "FwdDel": return 11.55
            default: return 10
            }
        case 2:
            // Row3: Shift 16, z-m and slash 9, Enter 12
            switch kd.label {
            case "Shift": return 16
            case "Enter": return 12
            default: return 9
            }
        case 3:
            // Bottom row: Space is wide, others are standard
            return kd.label == "Space" ? 40 : 10
        default:
            return 10
        }
    }

    private var landscapeHandleButton: some View {
        VStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSplitLayout.toggle()
                    UserDefaults.standard.set(isSplitLayout ? LandscapeLayout.split.rawValue : LandscapeLayout.full.rawValue,
                                              forKey: Self.landscapeLayoutKey)
                }
            }) {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground))
                        .frame(width: 48, height: 24)
                        .overlay(Image(systemName: isSplitLayout ? "rectangle.split.3x1" : "rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary))
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
                    Text(isSplitLayout ? "Split" : "Full")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }.buttonStyle(PlainButtonStyle())
            Spacer()
        }.padding(.top, 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func landscapeShortcutPanel(width: CGFloat) -> AnyView {
        if isSplitLayout {
            return AnyView(landscapeSplitShortcutPanel(totalWidth: width)
                .id(profileMgr.activeProfileId))
        } else {
            return AnyView(landscapeFullShortcutPanel)
        }
    }

    private var landscapeFullShortcutPanel: some View {
        VStack(spacing: 0) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4).padding(.bottom, 2)
        }
    }

    private var splitShortcutPageCount: Int {
        max(shortcutPages.count, fixedRowsPages.count)
    }

    private func splitShortcutPageView(shortcutPage: ShortcutPage, fixedPage: FixedRowsPage, totalWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ShortcutStripRowView(entries: shortcutPage.entries, background: Color.orange.opacity(0.18))
                .frame(height: 40)
            ShortcutStripRowView(entries: fixedPage.row1, background: Color(UIColor.tertiarySystemBackground))
                .frame(height: 40)
            ShortcutStripRowView(entries: fixedPage.row2, background: Color(UIColor.tertiarySystemBackground))
                .frame(height: 40)
        }
    }

    private func landscapeSplitShortcutPanel(totalWidth: CGFloat) -> AnyView {
        guard splitShortcutPageCount > 0 else { return AnyView(EmptyView()) }
        return AnyView(
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    ForEach(0..<splitShortcutPageCount, id: \.self) { idx in
                        let shortcutPage = shortcutPages.isEmpty ? ShortcutPage(title: "", entries: []) : shortcutPages[min(idx, shortcutPages.count - 1)]
                        let fixedPage = idx < fixedRowsPages.count ? fixedRowsPages[idx] : FixedRowsPage(row1: [], row2: [])
                        splitShortcutPageView(shortcutPage: shortcutPage, fixedPage: fixedPage, totalWidth: totalWidth)
                            .frame(width: w)
                            .allowsHitTesting(!splitShortcutIsDragging)
                    }
                }
                .offset(x: -CGFloat(splitShortcutCurrentPage) * w + splitShortcutDragOffset)
                .animation(splitShortcutIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: splitShortcutCurrentPage)
                .animation(splitShortcutIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: splitShortcutDragOffset)
                .frame(width: w, alignment: .leading)
                .clipped()
                .highPriorityGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .local)
                        .onChanged { v in
                            splitShortcutIsDragging = true
                            splitShortcutDragOffset = v.translation.width
                        }
                        .onEnded { v in
                            let threshold = w * 0.12
                            if v.translation.width < -threshold,
                               splitShortcutCurrentPage < splitShortcutPageCount - 1 {
                                splitShortcutCurrentPage += 1
                            } else if v.translation.width > threshold,
                                      splitShortcutCurrentPage > 0 {
                                splitShortcutCurrentPage -= 1
                            }
                            splitShortcutDragOffset = 0
                            splitShortcutIsDragging = false
                        }
                )
            }
            .frame(height: 120)
        )
    }

    private func splitTopSidePanel(pageIndex: Int, side: SplitSide, width: CGFloat) -> some View {
        GeometryReader { geo in
            let pageCount = max(shortcutPages.count, 1)
            let currentPage = min(pageIndex, pageCount - 1)
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    let page = shortcutPages.indices.contains(idx) ? shortcutPages[idx] : ShortcutPage(title: "", entries: [])
                    let maxSlots = side == .left ? 3 : 4
                    let entries = side == .left
                        ? Array(page.entries.prefix(maxSlots))
                        : Array(page.entries.dropFirst(3).prefix(maxSlots))
                    HStack(spacing: 2) {
                        ForEach(0..<maxSlots, id: \.self) { slotIdx in
                            if slotIdx < entries.count {
                                ShortcutButton(entry: entries[slotIdx], background: Color(UIColor.tertiarySystemBackground))
                            } else {
                                ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: Color(UIColor.tertiarySystemBackground))
                                    .disabled(true)
                                    .opacity(0.3)
                            }
                        }
                    }
                    .frame(width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .offset(x: -CGFloat(currentPage) * geo.size.width + splitShortcutTopDragOffset)
            .animation(splitShortcutTopIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: currentPage)
            .animation(splitShortcutTopIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: splitShortcutTopDragOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { v in
                        splitShortcutTopIsDragging = true
                        splitShortcutTopDragOffset = v.translation.width
                    }
                    .onEnded { v in
                        let threshold = geo.size.width * 0.12
                        if v.translation.width < -threshold,
                           splitShortcutTopCurrentPage < pageCount - 1 {
                            splitShortcutTopCurrentPage += 1
                        } else if v.translation.width > threshold,
                                  splitShortcutTopCurrentPage > 0 {
                            splitShortcutTopCurrentPage -= 1
                        }
                        splitShortcutTopDragOffset = 0
                        splitShortcutTopIsDragging = false
                    }
            )
            .clipped()
        }
        .frame(width: width)
    }

    private func splitBottomSidePanel(pageIndex: Int, side: SplitSide, width: CGFloat) -> some View {
        GeometryReader { geo in
            let pageCount = max(fixedRowsPages.count, 1)
            let currentPage = min(pageIndex, pageCount - 1)
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    let page = fixedRowsPages.indices.contains(idx) ? fixedRowsPages[idx] : FixedRowsPage(row1: [], row2: [])
                    let maxSlots = side == .left ? 3 : 4
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            let row1Entries = side == .left
                                ? Array(page.row1.prefix(maxSlots))
                                : Array(page.row1.dropFirst(3).prefix(maxSlots))
                            ForEach(0..<maxSlots, id: \.self) { slotIdx in
                                if slotIdx < row1Entries.count {
                                    ShortcutButton(entry: row1Entries[slotIdx], background: Color(UIColor.tertiarySystemBackground))
                                } else {
                                    ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: Color(UIColor.tertiarySystemBackground))
                                        .disabled(true)
                                        .opacity(0.3)
                                }
                            }
                        }
                        HStack(spacing: 2) {
                            let row2Entries = side == .left
                                ? Array(page.row2.prefix(maxSlots))
                                : Array(page.row2.dropFirst(3).prefix(maxSlots))
                            ForEach(0..<maxSlots, id: \.self) { slotIdx in
                                if slotIdx < row2Entries.count {
                                    ShortcutButton(entry: row2Entries[slotIdx], background: Color(UIColor.tertiarySystemBackground))
                                } else {
                                    ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: Color(UIColor.tertiarySystemBackground))
                                        .disabled(true)
                                        .opacity(0.3)
                                }
                            }
                        }
                    }
                    .frame(width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .offset(x: -CGFloat(currentPage) * geo.size.width + splitShortcutBottomDragOffset)
            .animation(splitShortcutBottomIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: currentPage)
            .animation(splitShortcutBottomIsDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: splitShortcutBottomDragOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { v in
                        splitShortcutBottomIsDragging = true
                        splitShortcutBottomDragOffset = v.translation.width
                    }
                    .onEnded { v in
                        let threshold = geo.size.width * 0.12
                        if v.translation.width < -threshold,
                           splitShortcutBottomCurrentPage < pageCount - 1 {
                            splitShortcutBottomCurrentPage += 1
                        } else if v.translation.width > threshold,
                                  splitShortcutBottomCurrentPage > 0 {
                            splitShortcutBottomCurrentPage -= 1
                        }
                        splitShortcutBottomDragOffset = 0
                        splitShortcutBottomIsDragging = false
                    }
            )
            .clipped()
        }
        .frame(width: width)
    }

    @ViewBuilder
    private var landscapeKeyboardView: some View {
        GeometryReader { innerGeometry in
            VStack(spacing: 0) {
                ForEach(currentKeys.indices, id: \.self) { rowIdx in
                    let row = currentKeys[rowIdx]
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { colIdx in
                            let kd = row[colIdx]
                            let width = keyWidth(for: kd, row: row)
                            keyButton(for: kd, width: width)
                                .frame(width: innerGeometry.size.width * width)
                        }
                    }
                    .frame(maxHeight: innerGeometry.size.height / CGFloat(currentKeys.count))
                }
            }
        }
    }

    // MARK: - Portrait layout

    @ViewBuilder
    private func portraitContent(_ geometry: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if displayMode != .keyboard {
                    touchpadOverlay().frame(maxWidth: .infinity).frame(height: geometry.size.height * 0.40)
                        .opacity(isTextInputMode && isTextInputExpanded ? 0 : 1)
                }
                if displayMode != .touchpad {
                    if isTextInputMode && !isTextInputExpanded { ScrollView { shortcutPanelContent } }
                    else { VStack(spacing: 0) { shortcutPanelContent }.frame(maxWidth: .infinity) }
                }
            }
            if isTextInputMode && isTextInputExpanded { expandedTextInputView(geometry) }
            if isImeSurface { imeCaptureOverlay }
        }
    }

    /// Invisible 2pt-tall UITextField capture surface — portrait B (IME) mode.
    /// Mirrors Android's km_pro_ime_host: transparent, no cursor, no suggestions.
    /// Focus is managed inside ImeCaptureTextField.updateUIView via isImeSurface.
    private var imeCaptureOverlay: some View {
        ImeCaptureTextField(text: $textInputContent, isActive: isImeSurface)
            .frame(width: 1, height: 2)
            .onChange(of: textInputContent) { newValue in
                applyImeDiff(newText: newValue)
            }
            .onAppear {
                textInputContent = ""
                imeLastSent = ""
            }
    }

    /// Compute the LCP diff between the last-sent text and new text, then send HID events.
    /// Backspaces are sent for deleted characters; inserted characters are sent as keystrokes.
    private func applyImeDiff(newText: String) {
        let old = imeLastSent
        guard old != newText else { return }
        var lcp = 0
        let oldChars = Array(old)
        let newChars = Array(newText)
        let minLen = min(oldChars.count, newChars.count)
        while lcp < minLen && oldChars[lcp] == newChars[lcp] { lcp += 1 }
        let deleteCount = oldChars.count - lcp
        let insertStr = String(newChars.dropFirst(lcp))
        imeLastSent = newText  // update immediately to prevent re-entrancy
        DispatchQueue.global(qos: .userInteractive).async {
            // 1. Send backspaces for deleted characters
            for _ in 0..<deleteCount {
                self.keyboardManager.sendKeyPressSynchronous("Backspace")
            }
            // 2. Send inserted characters using the same threading pattern as handleTextInput
            for char in insertStr {
                let scalar = char.unicodeScalars.first?.value ?? 0
                if scalar > 0x7E {
                    UnicodeManager.shared.sendChar(char, keyboardManager: self.keyboardManager)
                    usleep(50_000)
                    continue
                }
                DispatchQueue.main.sync {
                    self.keyboardManager.sendASCIICharInline(char)
                }
                usleep(50_000)
            }
        }
    }

    private var shortcutPanelContent: some View {
        VStack(spacing: 0) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4).padding(.bottom, 2)
            if !isImeSurface {
                keyboardLayoutView.frame(height: 260).padding(.bottom, 10)
            }
        }
    }

    private var landscapeShortcutPanel: some View {
        VStack(spacing: 0) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4).padding(.bottom, 2)
        }
    }

    private func expandedTextInputView(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            textInputView.frame(maxHeight: geometry.size.height * 0.50)
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

    var currentKeys: [[KeyboardManager.KeyDef]] {
        if orientationManager.isLandscape {
            return isSplitLayout ? splitLeftKeys : keyboardManager.landscapeKeys(for: aiSettings.targetOS)
        }
        return keyboardManager.portraitLetterKeys
    }

    /// Split the landscape keyboard at the midpoint of each row.
    /// Android splits at (row.size + 1) / 2 and rescales widths to 50%.
    private func splitRow(_ row: [KeyboardManager.KeyDef]) -> ([KeyboardManager.KeyDef], [KeyboardManager.KeyDef]) {
        if row.count == 7, row[3].label == "Space" {
            return (Array(row.prefix(3)), Array(row.suffix(4)))
        }
        let leftCount = (row.count + 1) / 2
        return (Array(row.prefix(leftCount)), Array(row.suffix(row.count - leftCount)))
    }

    private var splitLeftKeys: [[KeyboardManager.KeyDef]] {
        keyboardManager.landscapeKeys(for: aiSettings.targetOS).map { row in
            splitRow(row).0
        }
    }
    private var splitRightKeys: [[KeyboardManager.KeyDef]] {
        keyboardManager.landscapeKeys(for: aiSettings.targetOS).map { row in
            splitRow(row).1
        }
    }

    /// Toggle layout mode — matches Android onSecondaryLayoutToggleRequested().
    /// Portrait: switches between built-in HID keyboard and system IME.
    /// Landscape: switches between full and split keyboard layout.
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

    private func keyWeight(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef]) -> CGFloat {
        // Portrait layout widths (Android keyboard_lower_portrait_no_gui.xml)
        if !orientationManager.isLandscape {
            switch kd.label {
            case "Shift": return 16
            case "Enter": return 12
            case "Fn": return 9.5
            case "Ctrl": return 10
            case "Space": return 47
            case "Alt": return 10
            case "Win": return 19
            case "Tab": return 10
            case "Del": return 11.5
            default: return 100 / CGFloat(row.count)
            }
        }

        // Landscape layout weights from Android KM Pro landscape XML.
        if row.contains(where: { $0.label == "Space" }) {
            // Bottom row uses a wide space key.
            return kd.label == "Space" ? 40 : 10
        }
        if row.contains(where: { $0.label == "Fn" }) && row.contains(where: { $0.label == "Delete" || $0.label == "FwdDel" }) {
            switch kd.label {
            case "Fn": return 9.5
            case "a": return 10.6
            case "s", "d", "f", "g", "h", "j", "k", "l": return 8.35
            case "Delete", "FwdDel": return 11.55
            default: return 10
            }
        }
        if row.contains(where: { $0.label == "Shift" }) && row.contains(where: { $0.label == "Enter" }) {
            switch kd.label {
            case "Shift": return 16
            case "Enter": return 12
            default: return 9
            }
        }
        // Row1 / fallback: equal-width keys
        return 10
    }

    private func keyWidth(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef]) -> CGFloat {
        let weights = row.map { keyWeight(for: $0, row: row) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 1.0 / CGFloat(row.count) }
        return keyWeight(for: kd, row: row) / totalWeight
    }

    /// Build a single key button with long-press alternates and repeat support.
    @ViewBuilder
    private func keyButton(for kd: KeyboardManager.KeyDef, width: CGFloat) -> some View {
        let displayText = displayLabel(for: kd)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Shift", "Option"].contains(kd.label)
        let isPressed = isModifier && keyboardManager.activeModifiers.contains(kd.label)
        let isActive = (kd.label == "Caps" && keyboardManager.capsLockActive) || (kd.label == "Fn" && keyboardManager.isFnLocked)

        if isModifier {
            KeyPressButton(
                onPress: {
                    HapticFeedbackManager.shared.triggerButtonPress()
                    keyboardManager.handleKeyDown(kd.label)
                },
                onRelease: {
                    keyboardManager.handleKeyUp(kd.label)
                }
            ) { _ in
                keyContent(for: kd, displayText: displayText)
                    .frame(maxWidth: .infinity, maxHeight: 56)
                    .background(keyBackground(for: kd, pressed: isPressed, active: isActive))
                    .cornerRadius(9).foregroundColor(isPressed || isActive ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(cornerHint(for: kd), alignment: .topTrailing)
                    .contentShape(Rectangle())
                    .background(GeometryReader { geo -> Color in
                        DispatchQueue.main.async { self.keyFrames[kd.label] = geo.frame(in: .named("proKMView")) }
                        return Color.clear
                    })
            }
        } else {
            keyContent(for: kd, displayText: displayText)
                .frame(maxWidth: .infinity, maxHeight: 56)
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
                            currentDragLocation = value.location
                            // Update pickSlot when popup is showing
                            if alternatesPopup != nil, let start = alternatesGestureStart {
                                let dx = value.location.x - start.x
                                let dy = value.location.y - start.y
                                let slotMap = Dictionary(uniqueKeysWithValues: alternatesPopup!.options.map { ($0.slot, true) })
                                var occ: [Bool] = Array(repeating: false, count: AlternatePopupGeometry.slotCount)
                                for (slot, _) in slotMap { occ[slot] = true }
                                let rawPick = AlternatePopupGeometry.pickSlot(
                                    dx: dx, dy: dy,
                                    rMinPx: 12, rCancelPx: 228, axisDeadzonePx: 18,
                                    slotOccupied: occ)
                                if rawPick == AlternatePopupGeometry.resultDefault {
                                    alternatesPick = .defaultSlot
                                } else if rawPick == AlternatePopupGeometry.resultCancel {
                                    alternatesPick = .cancel
                                } else {
                                    alternatesPick = .slot(rawPick)
                                }
                            }
                        }
                        .onEnded { value in
                            longPressTimer?.invalidate(); longPressTimer = nil
                            keyPressInProgress = false; currentlyPressedKey = nil
                            if let popup = alternatesPopup {
                                // Commit based on final pick
                                if case .slot(let s) = alternatesPick,
                                   let option = popup.options.first(where: { $0.slot == s }) {
                                    HapticFeedbackManager.shared.triggerButtonPress()
                                    if option.requiresShift {
                                        keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: option.keyCode)
                                    } else {
                                        keyboardManager.handleKeyPress(option.keyCode)
                                    }
                                } else if case .defaultSlot = alternatesPick,
                                          let option = popup.options.first(where: { $0.slot == AlternatePopupGeometry.slotCenter }) {
                                    HapticFeedbackManager.shared.triggerButtonPress()
                                    if option.requiresShift {
                                        keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: option.keyCode)
                                    } else {
                                        keyboardManager.handleKeyPress(option.keyCode)
                                    }
                                }
                                // cancel → send nothing
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
    }
    
    /// Unified handler for key press - handles both single tap and long press
    private func handleKeyPress(_ kd: KeyboardManager.KeyDef) {
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
        case "Del", "Delete", "FwdDel":
            Image(systemName: "delete.forward").font(.system(size: 16))
        case "Cmd":
            // Target OS label: show Cmd/Win/Super based on settings
            switch aiSettings.targetOS {
            case .windows: Text("Win").font(.system(size: 12))
            case .linux: Text("Super").font(.system(size: 10))
            default: Text("Cmd").font(.system(size: 12))
            }
        case "Option":
            switch aiSettings.targetOS {
            case .windows: Text("Alt").font(.system(size: 12))
            case .linux: Text("AltGr").font(.system(size: 11))
            default: Text("Opt").font(.system(size: 12))
            }
        case "App":
            Image(systemName: "app").font(.system(size: 14))
        case "Ctrl", "Alt", "Win":
            Text(getDisplayValue(for: kd.label)).font(.system(size: 12))
        case "Caps": Text("Caps").font(.system(size: 11))
        case "Fn": Text("Fn").font(.system(size: 12, weight: .bold))
        case "Tab": Image(systemName: "arrow.right.to.line.compact").font(.system(size: 14))
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
        let functionLabels = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Fn", "Backspace", "Enter", "Delete", "Forward Delete", "FwdDel", "Del", "App", "Option"]
        return functionLabels.contains(kd.label) || keyboardManager.isSymbolMode && ["ABC", "12/34", "!?#"].contains(kd.label)
    }

    /// System-adaptive backgrounds for keys (auto light/dark).
    private static let functionKeyBg = Color(UIColor.secondarySystemBackground)
    private static let regularKeyBg = Color(UIColor.systemBackground)

    @ViewBuilder
    private func keyBackground(for kd: KeyboardManager.KeyDef, pressed: Bool, active: Bool) -> Color {
        if pressed || active { return .blue }
        return Self.functionKeyBg
    }
    @ViewBuilder private func cornerHint(for kd: KeyboardManager.KeyDef) -> some View {
        if kd.cornerHint.isEmpty {
            EmptyView()
        } else {
            Text(kd.cornerHint)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.trailing, 6)
                .padding(.top, 2)
                .allowsHitTesting(false)
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
        // Gesture start = finger position at popup appearance (matches Android)
        if let current = currentDragLocation {
            alternatesGestureStart = current
        }
        alternatesPick = .defaultSlot
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
        alternatesGestureStart = nil
        alternatesPick = .none
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
