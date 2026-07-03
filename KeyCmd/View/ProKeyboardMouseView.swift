//
//  ProKeyboardMouseView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//  Renamed to align with Android's KM Pro view.
//

import SwiftUI
import UIKit

extension Color {
    func darker(by amount: CGFloat = 0.2) -> Color {
        Color(UIColor(self).mixed(with: .black, by: amount))
    }
}

extension UIColor {
    func mixed(with other: UIColor, by t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * (1 - t) + r2 * t,
                       green: g1 * (1 - t) + g2 * t,
                       blue: b1 * (1 - t) + b2 * t,
                       alpha: a1 * (1 - t) + a2 * t)
    }
}

/// Transparent UITextField that captures system-keyboard (IME) input in portrait B mode.
private struct ImeCaptureTextField: UIViewRepresentable {
    @Binding var text: String; var isActive: Bool
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.backgroundColor = .clear; tf.textColor = .clear; tf.tintColor = .clear; tf.borderStyle = .none
        tf.font = .systemFont(ofSize: 1); tf.autocorrectionType = .no; tf.autocapitalizationType = .none
        tf.spellCheckingType = .no; tf.smartDashesType = .no; tf.smartQuotesType = .no; tf.returnKeyType = .default
        tf.inputAssistantItem.leadingBarButtonGroups = []; tf.inputAssistantItem.trailingBarButtonGroups = []
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        tf.delegate = context.coordinator; return tf
    }
    func updateUIView(_ tf: UITextField, context: Context) {
        // ponytail: delay keyboard presentation to avoid blocking UI during view transitions
        // (system input method initialization can hang the main thread for seconds)
        if isActive && !tf.isFirstResponder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !tf.isFirstResponder { tf.becomeFirstResponder() }
            }
        }
        else if !isActive && tf.isFirstResponder { tf.resignFirstResponder() }
        if tf.text != text { tf.text = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ImeCaptureTextField
        init(_ parent: ImeCaptureTextField) { self.parent = parent }
        @objc func textChanged(_ tf: UITextField) { parent.text = tf.text ?? "" }
        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            let nt = (tf.text ?? "") + "\n"; tf.text = nt; parent.text = nt; return false
        }
    }
}

/// Generic horizontal paging view with drag gesture — replaces 3 duplicate paging blocks.
private struct SplitPagingView<PageContent: View>: View {
    let pageCount: Int
    let currentPage: Int
    let isDragging: Bool
    let dragOffset: CGFloat
    let onPageChanged: (Int) -> Void
    let onDraggingChanged: (Bool) -> Void
    let onDragOffsetChanged: (CGFloat) -> Void
    @ViewBuilder let pageContent: (Int) -> PageContent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { idx in pageContent(idx).frame(width: w) }
            }
            .offset(x: -CGFloat(currentPage) * w + dragOffset)
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: currentPage)
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0), value: dragOffset)
            .frame(width: w, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { v in onDraggingChanged(true); onDragOffsetChanged(v.translation.width) }
                .onEnded { v in
                    let threshold = w * 0.12
                    if v.translation.width < -threshold, currentPage < pageCount - 1 { onPageChanged(currentPage + 1) }
                    else if v.translation.width > threshold, currentPage > 0 { onPageChanged(currentPage - 1) }
                    onDragOffsetChanged(0); onDraggingChanged(false)
                }
            )
        }
    }
}

/// Shared touchpad control background color for Pro mode (scroll strip, LMR buttons).
private let touchpadControlGray = Color(UIColor.secondarySystemBackground)

/// Button style that flashes accent color on press and stays accent when held.
private struct ProMouseButtonStyle: ButtonStyle {
    var held: Bool = false
    var accentColor: Color = .blue
    func makeBody(configuration: Configuration) -> some View {
        let active = configuration.isPressed || held
        return configuration.label
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(active ? accentColor.opacity(held ? 0.7 : 0.5) : touchpadControlGray, in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(active ? .white : .white.opacity(0.85))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ProKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @ObservedObject var orientationManager: OrientationManager
    @Binding var proSubmode: ProSubmode
    @ObservedObject private var prefs = KmProPrefs.shared

    @StateObject private var pointerTipState = PointerTipState()

    @State private var alternatesPopup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)? = nil
    @State private var alternatesGestureStart: CGPoint? = nil
    @State private var alternatesPick: AlternatesPick = .none
    @State private var currentDragLocation: CGPoint? = nil

    @State private var keyPressInProgress = false
    @State private var longPressTimer: Timer?
    @State private var currentlyPressedKey: String?
    /// True when the alternates popup became visible during the current finger-down.
    /// Used to suppress the original key on release and only send the selected alternate.
    @State private var alternatesShownThisPress = false

    // MARK: - Pro key repeat (deferred — never holds key-down to avoid host OS auto-repeat)
    @State private var proRepeatKey: String? = nil
    @State private var proRepeatStarter: Timer? = nil
    @State private var proRepeatTimer: Timer? = nil
    /// True only after the 400ms starter timer fires and the first key tap is sent.
    /// Used to distinguish "repeat actually ran" from "repeat was merely scheduled".
    @State private var proRepeatDidFire = false

    @State private var fixedRowsLocalFnLocked = false

    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var profileMgr = ShortcutProfileManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var keyboardHeight: CGFloat = 0
    @State private var keyFrames: [String: CGRect] = [:]

    @State private var isTextInputMode = false
    @State private var textInputContent = ""
    @State private var isTextInputExpanded = false
    @State private var showTouchpadHelp = false
    @State private var pointerMoving = false

    // MARK: - Mouse button state
    private var isLHeld: Bool { (mouseManager.heldButtons & 0x01) != 0 || mouseManager.isSelectMode || (mouseManager.clickFlash & 0x01) != 0 }
    private var isMHeld: Bool { (mouseManager.heldButtons & 0x04) != 0 || (mouseManager.clickFlash & 0x04) != 0 }
    private var isRHeld: Bool { (mouseManager.heldButtons & 0x02) != 0 || (mouseManager.clickFlash & 0x02) != 0 }
    private var buttonStateText: String {
        let drag = mouseManager.isSelectMode
        if drag {
            return "Buttons: left held (drag)"
        }
        return "Button: up (no drag)"
    }
    private var touchStateText: String {
        pointerMoving ? "Touch: moving pointer" : "Touch: idle"
    }

    // MARK: - Landscape full/split layout & portrait BI/IME persistence

    private enum LandscapeLayout: String { case full = "full", split = "split" }
    private enum PortraitInput: String { case builtIn = "built_in", ime = "ime" }

    enum ProSubmode: Int, CaseIterable {
        case keyboard, compose, numpad
        var icon: String { switch self { case .keyboard: return "ic_km_pro_submode_keyboard"; case .compose: return "ic_km_pro_submode_compose"; case .numpad: return "ic_km_pro_submode_numpad" } }
        var label: String { switch self { case .keyboard: return "Keyboard"; case .compose: return "Compose"; case .numpad: return "Numpad" } }
    }

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

    @State private var fixedRowsCurrentPage: Int = 1  // Track current page for fixed rows pager


    // MARK: - Shortcut strip data

    private var shortcutPages: [ShortcutPage] {
        let pm = aiSettings.targetOS == .macOS ? "Cmd" : "Ctrl"
        let combo: ([String], String) -> Void = { self.keyboardManager.handleKeyCombo(modifiers: $0, key: $1) }
        let source = profileEntries()
        guard !source.isEmpty else { return [standardShortcuts(combo, pm)] }
        let chunks = stride(from: 0, to: source.count, by: 7).map { Array(source[$0..<min($0+7, source.count)]) }
        let name = profileMgr.activeProfile?.name ?? ""
        return chunks.enumerated().map { (i, c) in ShortcutPage(title: c.count > 1 ? "\(name) \(i+1)/\(c.count)" : name, entries: c) }
    }

    private func profileEntries() -> [ShortcutEntry] {
        guard let active = profileMgr.activeProfile else { return [] }
        let items = !profileMgr.myShortcuts(for: active.id).isEmpty ? profileMgr.myShortcuts(for: active.id) : Array(active.categories.first?.shortcuts.prefix(7) ?? [])
        return items.map { item in
            let mods = (item.modifier ?? "").split(separator: "+").map(String.init)
            return ShortcutEntry(label: String(item.description.prefix(8)), icon: nil) {
                mods.isEmpty ? keyboardManager.handleSpecialKey(item.keyCode) : keyboardManager.handleKeyCombo(modifiers: mods, key: item.keyCode)
            }
        }
    }

    private func standardShortcuts(_ combo: @escaping ([String], String) -> Void, _ pm: String) -> ShortcutPage {
        ShortcutPage(title: "Standard", entries: [
            ShortcutEntry(label: "ALL",   icon: "select_all_24")   { combo([pm], "A") },
            ShortcutEntry(label: "COPY",  icon: "content_copy_24") { combo([pm], "C") },
            ShortcutEntry(label: "CUT",   icon: "content_cut_24")  { combo([pm], "X") },
            ShortcutEntry(label: "PASTE", icon: "content_paste_24"){ combo([pm], "V") },
            ShortcutEntry(label: "SAVE",  icon: "save_24")         { combo([pm], "S") },
            ShortcutEntry(label: "UNDO",  icon: "undo_24")         { combo([pm], "Z") },
            ShortcutEntry(label: "FIND",  icon: "magnifyingglass") { combo(["Ctrl"], "F") },
        ])
    }

    private var fixedRowsToggleEntry: ShortcutEntry {
        ShortcutEntry(label: "Sw", icon: "ic_swap_horiz_24", isActive: fixedRowsLocalFnLocked) {
            withAnimation(.easeInOut(duration: 0.15)) { fixedRowsLocalFnLocked.toggle() }
        }
    }

    private var keyboardToggleEntry: ShortcutEntry {
        ShortcutEntry(label: keyboardToggleLabel, icon: "keyboard") {
            withAnimation {
                if orientationManager.isLandscape {
                    isSplitLayout.toggle()
                    persistedLandscapeLayoutRawValue = isSplitLayout ? LandscapeLayout.split.rawValue : LandscapeLayout.full.rawValue
                } else {
                    isImeSurface.toggle()
                    UserDefaults.standard.set(isImeSurface ? PortraitInput.ime.rawValue : PortraitInput.builtIn.rawValue, forKey: Self.portraitInputKey)
                }
            }
        }
    }

    private var keyboardToggleLabel: String {
        orientationManager.isLandscape ? (isSplitLayout ? "Split" : "Full") : (isImeSurface ? "IME" : "BI")
    }

    private var fixedRowsPages: [FixedRowsPage] {
        let km = keyboardManager
        let lock = fixedRowsLocalFnLocked
        let te = { Self.textEntry(km, label: $0) }
        let fKeyFont: Font = .system(size: 11, weight: .bold)
        let keKey = { (label: String, key: String) in
            // ponytail: Material icon assets for keys that have them; SF Symbol
            // fallbacks for keys Android shows as text-only (Home, End, etc.).
            // iconImage() picks asset first, falls back to Image(systemName:).
            let iconMap: [String: String] = [
                "Tab": "keyboard_tab_24", "Up": "keyboard_arrow_up_24",
                "Enter": "keyboard_return_24px", "Delete": "backspace_24",
                "Left": "keyboard_arrow_left_24", "Down": "keyboard_arrow_down_24",
                "Right": "keyboard_arrow_right_24", "Backspace": "backspace_24",
                "Space": "space_bar_24px",
                // ponytail: Nav/lock keys always show text names, not icons
            ]
            var entry = Self.keyEntry(km, label: label, icon: iconMap[key] ?? "", key: key)
            entry.font = fKeyFont
            if key == "Delete" { entry.iconRotation = 180 }
            return entry
        }
        let tog = fixedRowsToggleEntry
        let kbdTog = keyboardToggleEntry

        // Page 0 — F-keys / number-symbol
        let p0Fkeys = [("F1","1"),("F2","2"),("F3","3"),("F4","4"),("F5","5"),("F6","6")]
            .map { (pair) -> ShortcutEntry in
                var entry = Self.keyEntry(km, label: pair.0, icon: "", badge: pair.1)
                entry.font = fKeyFont
                return entry
            }
        let p0FnKeys = [("F7","7"),("F8","8"),("F9","9"),("F10","0"),("F11","+"),("F12","-")]
            .map { (pair) -> ShortcutEntry in
                var entry = Self.keyEntry(km, label: pair.0, icon: "", badge: pair.1)
                entry.font = fKeyFont
                return entry
            }
        let p0NumKeysTop = [("7","&"),("8","*"),("9","("),("0",")"),("+","="),("-","_"),("*","=")]
            .map { (pair) -> ShortcutEntry in
                var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                entry.font = fKeyFont
                return entry
            }
        let p0NumKeysBottom = [("1","!"),("2","@"),("3","£"),("4","¥"),("5","%"),("6","^")]
            .map { (pair) -> ShortcutEntry in
                var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                entry.font = fKeyFont
                return entry
            }
        let p0EqKey: ShortcutEntry = {
            var entry = Self.textEntry(km, label: "=", badge: "*")
            entry.font = fKeyFont
            return entry
        }()
        let p0 = FixedRowsPage(
            row1: lock ? p0NumKeysTop : p0FnKeys + [p0EqKey],
            row2: lock ? p0NumKeysBottom + [tog] : p0Fkeys + [tog]
        )

        // Page 1 — Modifiers + Navigation
        let isMacOS = aiSettings.targetOS == .macOS
        let isWindows = aiSettings.targetOS == .windows
        let winIcon = aiSettings.targetOS == .windows ? "targetos_windows" : "targetos_linux"
        let modCfg: [(String, String, String)] = isMacOS
            ? [("Ctrl","","keyboard_control_key_24px"),("Alt","","keyboard_option_key_24px"),("Cmd","","keyboard_command_key_24px")]
            : isWindows ? [("Ctrl","Ctrl",""),("Alt","Alt",""),("Win","Win",winIcon)]
                        : [("Ctrl","Ctrl",""),("Alt","Alt",""),("Win","Super",winIcon)]
        let modEntries = modCfg.map { cfg -> ShortcutEntry in
            var entry = ShortcutEntry(label: cfg.1, icon: cfg.2.isEmpty ? nil : cfg.2, isActive: keyboardManager.activeModifiers.contains(cfg.0)) { km.handleModifierToggle(cfg.0) }
            entry.font = fKeyFont
            return entry
        }
        let p1Locked = FixedRowsPage(
            row1: [keKey("SCR LK","Scroll Lock"),keKey("PRT SC","PrtSc"),keKey("CAPS","Caps"),keKey("PAUSE","Pause"),keKey("HOME","Home"),keKey("PGUP","PgUp"),kbdTog],
            row2: [keKey("SPACE","Space"),keKey("BKSP","Backspace"),keKey("DEL","Delete"),keKey("INS","Insert"),keKey("END","End"),keKey("PGDN","PgDn"),tog]
        )
        let p1Unlocked = FixedRowsPage(
            row1: modEntries + [keKey("Tab","Tab"),keKey("UP","Up"),keKey("ENTER","Enter"),kbdTog],
            row2: [keKey("ESC","Escape"),Self.modifierEntry(km,label:"SHIFT",icon:"shift_24px",key:"Shift",font:fKeyFont),keKey("DEL","Delete"),keKey("LEFT","Left"),keKey("DOWN","Down"),keKey("RIGHT","Right"),tog]
        )

        // Page 2 — Punctuation
        let p2 = FixedRowsPage(
            row1: lock ? PunctuationPageData.lockedRow1.map { (pair) -> ShortcutEntry in
                            var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = fKeyFont
                            return entry
                        }
                       : PunctuationPageData.unlockedRow1.map { (pair) -> ShortcutEntry in
                            var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = fKeyFont
                            return entry
                        },
            row2: lock ? PunctuationPageData.lockedRow2.map { (pair) -> ShortcutEntry in
                            var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = fKeyFont
                            return entry
                        } + [tog]
                       : PunctuationPageData.unlockedRow2.map { (pair) -> ShortcutEntry in
                            var entry = Self.textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = fKeyFont
                            return entry
                        } + [tog]
        )

        return [p0, lock ? p1Locked : p1Unlocked, p2]
    }

    // MARK: - Shortcut helpers

    private static func modifierEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil, font: Font? = nil) -> ShortcutEntry {
        let k = key ?? label
        var entry = ShortcutEntry(label: label, icon: icon, isActive: km.activeModifiers.contains(k)) { km.handleModifierToggle(k) }
        entry.font = font
        return entry
    }
    private static func keyEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil, badge: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        var entry = ShortcutEntry(label: label, icon: icon.isEmpty ? nil : icon) { km.handleKeyPress(k) }
        entry.badge = badge
        return entry
    }
    private static func textEntry(_ km: KeyboardManager, label: String, badge: String? = nil) -> ShortcutEntry {
        var entry = ShortcutEntry(label: label, icon: nil) { km.handleTextInput(label) }
        entry.badge = badge
        return entry
    }

    // MARK: - Touchpad helper

    private func touchpadOverlay(showLabel: Bool = true) -> some View {
        GeometryReader { geo in
            let stripWidth = max(14, geo.size.width * 0.165)
            let showMouseButtons = prefs.showsMouseKeyStrip
            let padGesturesEnabled = prefs.padClickDragGesturesEnabled
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState, padClickDragGesturesEnabled: padGesturesEnabled, onPointerMoving: { moving in pointerMoving = moving })
                        Button(action: { showTouchpadHelp = true }) {
                            Image("ic_touchpad_info_24")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundColor(.secondary)
                                .padding(8).background(Color(UIColor.secondarySystemBackground).opacity(0.9)).clipShape(Circle())
                        }
                        .alert("Gestures", isPresented: $showTouchpadHelp) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text("One finger: move, tap, double-tap; long-press starts drag (tap again to release).\n\nTwo fingers: scroll; lift both without sliding for right-click.")
                        }
                        if showLabel {
                            VStack(spacing: 2) {
                                Text("TouchPad")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(buttonStateText)
                                    .font(.system(size: 9.45, weight: .light))
                                    .foregroundColor(mouseManager.isSelectMode ? themeManager.accentColor.darker(by: 0.15) : .secondary.opacity(0.7))
                                Text(touchStateText)
                                    .font(.system(size: 9.45, weight: .light))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // ponytail: floating keyboard-toggle so the user can exit
                        // touchpad-only mode — without it there's no way to get back
                        // when the shortcut panel is hidden (displayMode == .touchpad).
                        Button {
                            withAnimation { displayMode = .both }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(orientationManager.isLandscape
                                     ? (isSplitLayout ? "Split Layout" : "Full Layout")
                                     : (isImeSurface ? "Input Method" : "Built-in"))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.primary.opacity(0.6))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.9))
                            .cornerRadius(6)
                        }
                        .padding(6)
                    }
                    .frame(width: max(0, geo.size.width - stripWidth))
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 0.5)
                    ProTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: orientationManager.isLandscape ? 10 : 7).frame(width: stripWidth)
                }
                if showMouseButtons {
                    proTouchpadMouseButtons
                }
            }.background(Color(UIColor.secondarySystemBackground))
        }
    }

    /// L/M/R mouse button strip below the touchpad (matching Android include_pro_touchpad_mouse_keys).
    /// Layout: Left 2/5, Middle 1/5, Right 2/5.
    private var proTouchpadMouseButtons: some View {
        HStack(spacing: 8) {
            proMouseButton(label: "L", held: isLHeld, action: { mouseManager.handleClick() })
            proMouseButton(label: "M", held: isMHeld, action: { mouseManager.handleMiddleClick() })
                .frame(maxWidth: .infinity, minHeight: 36)
            proMouseButton(label: "R", held: isRHeld, action: { mouseManager.handleRightClick() })
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(touchpadControlGray)
    }

    private func proMouseButton(label: String, held: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(ProMouseButtonStyle(held: held, accentColor: themeManager.accentColor))
    }

    enum DisplayMode: Int, CaseIterable {
        case both = 0, keyboard, touchpad
        mutating func toggle() { self = DisplayMode(rawValue: (rawValue + 1) % 3) ?? .both }
        var icon: String {
            switch self { case .both: return "rectangle.split.3x1"; case .keyboard: return "keyboard"; case .touchpad: return "rectangle.and.hand.point.up.left.filled" }
        }
    }
    @State private var displayMode: DisplayMode = .both

    func getDisplayValue(for key: String) -> String {
        let kd = KeyboardManager.KeyDef(key, "")
        if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty { return kd.symbolLabel }
        if let l = letterDisplay(kd.label) { return l }
        return keyboardManager.activeModifiers.contains("Shift") ? (shiftMap[key] ?? key) : key
    }
    func displayLabel(for kd: KeyboardManager.KeyDef) -> String {
        if let f = keyboardManager.resolveFnKey(kd.label) { return f }
        if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty { return kd.symbolLabel }
        return letterDisplay(kd.label) ?? kd.label
    }
    private func letterDisplay(_ char: String) -> String? {
        guard char.count == 1, let c = char.first, c.isLetter else { return nil }
        return (keyboardManager.activeModifiers.contains("Shift") != keyboardManager.capsLockActive) ? char.uppercased() : char.lowercased()
    }
    private var shiftMap: [String: String] {
        ["`":"~","1":"!","2":"@","3":"#","4":"$","5":"%","6":"^","7":"&","8":"*","9":"(","0":")",
         "-":"_","=":"+","[":"{","]":"}",";":":","'":"\"",",":"<",".":">","/":"?"]
    }

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                if orientationManager.isLandscape { landscapeContent(g) } else { portraitContent(g) }
            }
                .coordinateSpace(name: "proKMView")
                .coordinateSpace(name: "keyboardLayout")
                .overlay { if proSubmode == .keyboard, let p = alternatesPopup { KeyAlternatesPopupView(options: p.options, anchorFrame: p.anchor, pick: alternatesPick).allowsHitTesting(false) } }
                .overlayPreferenceValue(KeyCalloutInfoKey.self) { info in
                    if let info = info {
                        Text(info.text)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.accentColor)
                                    .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .position(
                                x: info.left ? info.frame.minX - 60 : (info.right ? info.frame.maxX + 60 : info.frame.midX),
                                y: (info.left || info.right) ? info.frame.midY : (info.below ? info.frame.maxY + 36 : info.frame.minY - 36)
                            )
                            .allowsHitTesting(false)
                    }
                }
                .offset(y: isTextInputMode ? (keyboardHeight > 0 ? -keyboardHeight * 0.65 : 30) : 0)
                .animation(.easeOut(duration: 0.3), value: keyboardHeight).animation(.easeOut(duration: 0.3), value: isTextInputMode)
                .onAppear {
                    isSplitLayout = persistedLandscapeLayout == .split; isImeSurface = persistedPortraitInput == .ime
                    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
                        if let kf = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect { keyboardHeight = kf.height }
                    }
                    NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in keyboardHeight = 0 }
                    // Compose and Numpad are portrait-only — force rotation on appear
                    if proSubmode != .keyboard {
                        orientationManager.lockToPortrait()
                    } else {
                        // Keyboard mode supports both orientations — unlock any previous lock
                        // (e.g., from gamepad or compose) and sync to current device orientation.
                        orientationManager.unlockOrientation()
                        // Force an immediate orientation refresh so the layout reflects the
                        // current physical device orientation rather than a stale cached state.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            orientationManager.updateOrientation()
                            orientationManager.forceUIRefresh()
                        }
                    }
                }
                .onDisappear {
                    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
                    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                    // Compose and Numpad are portrait-only — re-force if device rotated
                    if proSubmode != .keyboard {
                        orientationManager.lockToPortrait()
                    } else if proSubmode == .keyboard {
                        // Keyboard: sync layout state to persisted values for the new orientation
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSplitLayout = persistedLandscapeLayout == .split
                            isImeSurface = persistedPortraitInput == .ime
                        }
                    }
                }
        }
    }

    /// Helper that keeps submode views alive in the view tree to avoid expensive
    /// recreate-on-switch. Only the active submode is visible and interactive.
    @ViewBuilder
    private func submodeView<Content: View>(active: ProSubmode, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(proSubmode == active ? 1 : 0)
            .allowsHitTesting(proSubmode == active)
    }

    // MARK: - Landscape layout

    @ViewBuilder
    private func landscapeContent(_ geometry: GeometryProxy) -> some View {
        ZStack {
            if proSubmode == .compose {
                ComposeTextView(keyboardManager: keyboardManager)
                    .background(Color(UIColor.secondarySystemBackground))
                    .transaction { $0.animation = nil }
            }
            if proSubmode == .numpad {
                ProNumPadView(keyboardManager: keyboardManager, mouseManager: mouseManager)
                    .background(Color(UIColor.secondarySystemBackground))
                    .transaction { $0.animation = nil }
            }
            submodeView(active: .keyboard) {
                let barWidth: CGFloat = 50
                HStack(spacing: 0) {
                    Color(UIColor.secondarySystemBackground).frame(width: barWidth)
                    VStack(spacing: 0) {
                        if displayMode == .touchpad {
                            VStack(spacing: 0) { landscapeShortcutPanel; touchpadOverlay() }
                        } else if isSplitLayout {
                            let cw = geometry.size.width - barWidth, tw = cw * 0.33, sw = max(0, (cw - tw) / 2)
                            HStack(spacing: 0) {
                                splitSideColumn(side: .left, width: sw); touchpadOverlay().frame(width: tw); splitSideColumn(side: .right, width: sw)
                            }
                        } else {
                            VStack(spacing: 0) { landscapeShortcutPanel; keyboardRows.layoutPriority(1) }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // ponytail: handle button must be visible in every displayMode
                        // (touchpad-only, split, keyboard-only), not just when touchpad shows.
                        landscapeHandleButton.padding(8)
                    }
                }.background(Color(UIColor.secondarySystemBackground))
            }
        }
    }

    @ViewBuilder private func splitSideColumn(side: SplitSide, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            splitTopSidePanel(pageIndex: splitShortcutTopCurrentPage, side: side, width: width).frame(height: 44)
            splitBottomSidePanel(pageIndex: splitShortcutBottomCurrentPage, side: side, width: width).frame(height: 88)
            splitKeyboardColumn(side: side)
        }.frame(width: width).clipped()
    }

    enum SplitSide { case left, right }

    @ViewBuilder
    private func splitKeyboardColumn(side: SplitSide) -> some View {
        let keys = side == .left ? splitLeftKeys : splitRightKeys
        GeometryReader { g in
            VStack(spacing: 0) {
                ForEach(keys.indices, id: \.self) { r in
                    let row = keys[r]
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { c in
                            let kd = row[c], w = keyWidthSplit(for: kd, row: row, side: side, rowIndex: r)
                            keyButton(for: kd, width: w).frame(width: g.size.width * w)
                        }
                    }.frame(maxHeight: g.size.height / CGFloat(keys.count))
                }
            }
        }
    }

    private func keyWidthSplit(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef], side: SplitSide, rowIndex: Int) -> CGFloat {
        let w = row.map { splitKeyWeight(for: $0, rowIndex: rowIndex) }; let t = w.reduce(0, +)
        guard t > 0 else { return 1.0 / CGFloat(row.count) }
        return splitKeyWeight(for: kd, rowIndex: rowIndex) / t
    }
    private func splitKeyWeight(for kd: KeyboardManager.KeyDef, rowIndex: Int) -> CGFloat {
        switch rowIndex {
        case 0: return 10
        case 1:
            switch kd.label {
            case "Fn": return 9.5; case "a": return 10.6
            case "s","d","f","g","h","j","k","l": return 8.35; case "Delete","FwdDel": return 11.55
            default: return 10
            }
        case 2:
            switch kd.label { case "Shift": return 16; case "Enter": return 12; default: return 9 }
        case 3:
            switch kd.label {
            case "Space": return 42
            case "Ctrl", "Win", "Alt", "App": return 13
            default: return 10
            }
        default: return 10
        }
    }

    private var landscapeHandleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isSplitLayout.toggle()
                UserDefaults.standard.set(isSplitLayout ? LandscapeLayout.split.rawValue : LandscapeLayout.full.rawValue, forKey: Self.landscapeLayoutKey)
            }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 48, height: 24)
                    .overlay(Image(systemName: isSplitLayout ? "rectangle.split.3x1" : "rectangle").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)
                Text(isSplitLayout ? "Split" : "Full").font(.caption2).foregroundColor(.secondary)
            }
        }.buttonStyle(PlainButtonStyle())
    }

    private var landscapeShortcutPanel: some View {
        VStack(spacing: 6) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1, refreshKey: fixedRowsLocalFnLocked)
        }.background(Color(UIColor.secondarySystemBackground))
    }
    @ViewBuilder private var landscapeSplitShortcutPanel: some View {
        let pc = max(shortcutPages.count, fixedRowsPages.count)
        if pc > 0 {
            SplitPagingView(pageCount: pc, currentPage: splitShortcutCurrentPage, isDragging: splitShortcutIsDragging, dragOffset: splitShortcutDragOffset, onPageChanged: { splitShortcutCurrentPage = $0 }, onDraggingChanged: { splitShortcutIsDragging = $0 }, onDragOffsetChanged: { splitShortcutDragOffset = $0 }) { i in
                let sp = shortcutPages.indices.contains(i) ? shortcutPages[i] : ShortcutPage(title: "", entries: [])
                let fp = i < fixedRowsPages.count ? fixedRowsPages[i] : FixedRowsPage(row1: [], row2: [])
                shortcutPageView(sp, fp).allowsHitTesting(!splitShortcutIsDragging)
            }.background(Color(UIColor.secondarySystemBackground))
        }
    }
    private func shortcutPageView(_ sp: ShortcutPage, _ fp: FixedRowsPage) -> some View {
        VStack(spacing: 0) {
            ShortcutStripRowView(entries: sp.entries, background: Color.orange.opacity(0.18)).frame(height: 40)
            ShortcutStripRowView(entries: fp.row1, background: Color(UIColor.secondarySystemBackground)).frame(height: 40)
            ShortcutStripRowView(entries: fp.row2, background: Color(UIColor.secondarySystemBackground)).frame(height: 40)
        }
    }
    private func sideEntries(from entries: [ShortcutEntry], side: SplitSide) -> [ShortcutEntry] {
        side == .left ? Array(entries.prefix(3)) : Array(entries.dropFirst(3).prefix(4))
    }
    private func shortcutSlotRow(entries: [ShortcutEntry], maxSlots: Int, background: Color = Color(UIColor.tertiarySystemBackground)) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<maxSlots, id: \.self) { i in
                if i < entries.count { ShortcutButton(entry: entries[i], background: background) }
                else { ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: background).disabled(true).opacity(0.3) }
            }
        }
    }

    private func splitTopSidePanel(pageIndex: Int, side: SplitSide, width: CGFloat) -> some View {
        let ms = side == .left ? 3 : 4
        return SplitPagingView(pageCount: shortcutPages.count, currentPage: pageIndex, isDragging: splitShortcutTopIsDragging, dragOffset: splitShortcutTopDragOffset, onPageChanged: { splitShortcutTopCurrentPage = $0 }, onDraggingChanged: { splitShortcutTopIsDragging = $0 }, onDragOffsetChanged: { splitShortcutTopDragOffset = $0 }) { idx in
            let page = shortcutPages.indices.contains(idx) ? shortcutPages[idx] : ShortcutPage(title: "", entries: [])
            shortcutSlotRow(entries: sideEntries(from: page.entries, side: side), maxSlots: ms, background: Color.orange.opacity(0.18))
        }.frame(width: width)
    }
    private func splitBottomSidePanel(pageIndex: Int, side: SplitSide, width: CGFloat) -> some View {
        let ms = side == .left ? 3 : 4
        return SplitPagingView(pageCount: fixedRowsPages.count, currentPage: pageIndex, isDragging: splitShortcutBottomIsDragging, dragOffset: splitShortcutBottomDragOffset, onPageChanged: { splitShortcutBottomCurrentPage = $0 }, onDraggingChanged: { splitShortcutBottomIsDragging = $0 }, onDragOffsetChanged: { splitShortcutBottomDragOffset = $0 }) { idx in
            let page = fixedRowsPages.indices.contains(idx) ? fixedRowsPages[idx] : FixedRowsPage(row1: [], row2: [])
            VStack(spacing: 2) {
                shortcutSlotRow(entries: sideEntries(from: page.row1, side: side), maxSlots: ms)
                shortcutSlotRow(entries: sideEntries(from: page.row2, side: side), maxSlots: ms)
            }
        }.frame(width: width)
    }

    private var keyboardRows: some View {
        VStack(spacing: 6) {
            ForEach(currentKeys.indices, id: \.self) { r in
                let row = currentKeys[r]
                GeometryReader { rowGeo in
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { c in
                            let kd = row[c]
                            let widthFraction = keyWidth(for: kd, row: row)
                            keyButton(for: kd, width: widthFraction)
                                .frame(width: max(0, rowGeo.size.width * widthFraction))
                        }
                    }
                    .frame(width: rowGeo.size.width, height: rowGeo.size.height, alignment: .leading)
                }
                .frame(height: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Portrait layout

    @ViewBuilder
    private func portraitContent(_ g: GeometryProxy) -> some View {
        ZStack {
            if proSubmode == .compose {
                ComposeTextView(keyboardManager: keyboardManager)
                    .background(Color(UIColor.secondarySystemBackground))
                    .transaction { $0.animation = nil }
            }
            if proSubmode == .numpad {
                ProNumPadView(keyboardManager: keyboardManager, mouseManager: mouseManager)
                    .background(Color(UIColor.secondarySystemBackground))
                    .transaction { $0.animation = nil }
            }
            submodeView(active: .keyboard) {
                VStack(spacing: 0) {
                    if displayMode != .keyboard { touchpadOverlay().frame(height: g.size.height * 0.42).opacity(isTextInputMode && isTextInputExpanded ? 0 : 1) }
                    if displayMode != .touchpad {
                        if isTextInputMode && !isTextInputExpanded { ScrollView { shortcutPanelContent } }
                        else { shortcutPanelContent.frame(maxWidth: .infinity) }
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .overlay(alignment: .bottom) {
                    if !isImeSurface {
                        portraitLogoOverlay.padding(.bottom, 44)
                    }
                }
                if isTextInputMode && isTextInputExpanded { expandedTextInputView(g) }
                if isImeSurface && proSubmode == .keyboard { imeCaptureOverlay }
            }
        }
    }

    private var imeCaptureOverlay: some View {
        ImeCaptureTextField(text: $textInputContent, isActive: isImeSurface)
            .frame(width: 1, height: 2)
            .onChange(of: textInputContent) { v in applyImeDiff(newText: v) }
            .onAppear { textInputContent = ""; imeLastSent = "" }
    }

    private func applyImeDiff(newText: String) {
        let old = imeLastSent; guard old != newText else { return }
        var lcp = 0; let oldC = Array(old), newC = Array(newText)
        while lcp < min(oldC.count, newC.count) && oldC[lcp] == newC[lcp] { lcp += 1 }
        let deleteCount = oldC.count - lcp; let insertStr = String(newC.dropFirst(lcp))
        imeLastSent = newText
        // ponytail: process all keys on a background queue — sendKeyPressAndRelease
        // and sendASCIICharInline are thread-safe (build HID packets, no UI access).
        // Running them on the main thread (via DispatchQueue.main.sync) blocks the
        // main thread for ~100ms per character due to usleep(commitDelayUs) inside
        // sendKeyPressAndRelease, causing a 20s+ hang for long text inputs.
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<deleteCount { self.keyboardManager.sendKeyPressSynchronous("Backspace") }
            for char in insertStr {
                let s = char.unicodeScalars.first?.value ?? 0
                if s > 0x7E { UnicodeManager.shared.sendChar(char, keyboardManager: self.keyboardManager); usleep(50_000); continue }
                // ponytail: call directly from background thread (thread-safe); avoids
                // blocking the main thread for the duration of sendKeyPressAndRelease
                self.keyboardManager.sendASCIICharInline(char)
                usleep(50_000)
            }
        }
    }

    private var shortcutPanelContent: some View {
        VStack(spacing: 6) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1, refreshKey: fixedRowsLocalFnLocked).padding(.horizontal, 4)
            if !isImeSurface { keyboardRows.frame(height: 360).padding(.top, -40).padding(.bottom, 10) }
        }
    }

    private var portraitLogoOverlay: some View {
        Image("openterface_wordmark")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 64, height: 12)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }

    private func expandedTextInputView(_ g: GeometryProxy) -> some View {
        VStack(spacing: 8) { textInputView.frame(maxHeight: g.size.height * 0.50) }
            .padding(.top, 90).padding(.bottom, 30).padding(.horizontal, 8)
            .background(Color(UIColor.systemBackground)).zIndex(10)
    }

    var currentKeys: [[KeyboardManager.KeyDef]] {
        orientationManager.isLandscape ? (isSplitLayout ? splitLeftKeys : keyboardManager.landscapeKeys(for: aiSettings.targetOS)) : keyboardManager.portraitLetterKeys
    }

    private func splitRow(_ row: [KeyboardManager.KeyDef]) -> ([KeyboardManager.KeyDef], [KeyboardManager.KeyDef]) {
        if row.count == 7, row[3].label == "Space" { return (Array(row.prefix(3)), Array(row.suffix(4))) }
        let n = (row.count + 1) / 2; return (Array(row.prefix(n)), Array(row.suffix(row.count - n)))
    }

    private var splitLeftKeys: [[KeyboardManager.KeyDef]] { keyboardManager.landscapeKeys(for: aiSettings.targetOS).map { splitRow($0).0 } }
    private var splitRightKeys: [[KeyboardManager.KeyDef]] { keyboardManager.landscapeKeys(for: aiSettings.targetOS).map { splitRow($0).1 } }

    private func keyWeight(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef]) -> CGFloat {
        if !orientationManager.isLandscape {
            switch kd.label {
            case "Shift": return 16; case "Enter": return 12; case "Fn": return 11
            case "Space": return 47; case "Win": return 12; case "Del": return 11.5
            case "Alt", "Ctrl": return 7.5
            default: return 100 / CGFloat(row.count)
            }
        }
        if isSplitLayout && row.count == 4 && row.contains(where: { $0.label == "Space" }) {
            switch kd.label {
            case "Space": return 30
            case "Ctrl", "Win", "Alt", "App": return 18
            default: return 12
            }
        }
        if row.contains(where: { $0.label == "Space" }) {
            switch kd.label {
            case "Space": return 50
            case "Ctrl", "Win", "Alt", "Cmd", "Option", "App": return 10
            default: return 8
            }
        }
        if row.contains(where: { $0.label == "Fn" }) && row.contains(where: { $0.label == "Delete" || $0.label == "FwdDel" }) {
            switch kd.label {
            case "Fn": return 9.5; case "a": return 10.6
            case "s","d","f","g","h","j","k","l": return 8.35; case "Delete","FwdDel": return 11.55
            default: return 10
            }
        }
        if row.contains(where: { $0.label == "Shift" }) && row.contains(where: { $0.label == "Enter" }) {
            switch kd.label { case "Shift": return 16; case "Enter": return 12; default: return 9 }
        }
        return 10
    }

    private func keyWidth(for kd: KeyboardManager.KeyDef, row: [KeyboardManager.KeyDef]) -> CGFloat {
        let weights = row.map { keyWeight(for: $0, row: row) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 1.0 / CGFloat(row.count) }
        return keyWeight(for: kd, row: row) / totalWeight
    }

    private func keyButton(for kd: KeyboardManager.KeyDef, width: CGFloat) -> AnyView {
        let displayText = displayLabel(for: kd)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Shift", "Option"].contains(kd.label)
        let visualOnlyModifier = ["Ctrl", "Alt", "Win"].contains(kd.label)
        let isPressed = (isModifier && !visualOnlyModifier && keyboardManager.activeModifiers.contains(kd.label)) ||
                        ((visualOnlyModifier || !isModifier) && keyPressInProgress && currentlyPressedKey == kd.label)
        let isActive = (kd.label == "Caps" && keyboardManager.capsLockActive) || (kd.label == "Fn" && keyboardManager.isFnLocked)
        let h = orientationManager.isLandscape ? 56.0 : 72.0
        let bg = GeometryReader { g in DispatchQueue.main.async { keyFrames[kd.label] = g.frame(in: .named("proKMView")) }; return Color.clear }
        let content = keyContent(for: kd, displayText: displayText)
            .frame(maxWidth: .infinity, maxHeight: h)
            .background(isModifier ? Color.clear : keyBackground(for: kd, pressed: isPressed, active: isActive))
            .cornerRadius(9).foregroundColor(isPressed || isActive ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { self.keyHints(for: kd) }
            .contentShape(Rectangle()).background(bg)
        if isModifier {
            return AnyView(ProModifierKey(kd: kd, keyboardManager: keyboardManager, displayText: displayText, content: AnyView(content), height: h))
        } else {
            let ek = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
            let isRepeatable = KeyRepeatController.repeatableKeys.contains(kd.label)
            let previewBg = GeometryReader { geo in
                Color.clear.preference(
                    key: KeyCalloutInfoKey.self,
                    value: prefs.keyTapPreviewEnabled && keyPressInProgress && currentlyPressedKey == kd.label
                        ? KeyCalloutInfo(text: displayText, frame: geo.frame(in: .named("keyboardLayout")), below: false, left: false, right: false)
                        : nil
                )
            }
            return AnyView(content
                .background(previewBg)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("proKMView"))
                    .onChanged { v in
                        if !keyPressInProgress {
                            keyPressInProgress = true
                            currentlyPressedKey = kd.label
                            HapticFeedbackManager.shared.triggerButtonPress()
                            if isRepeatable {
                                // Start deferred repeat — waits 400ms then sends key-down/up pairs.
                                // Does NOT send key-down immediately, so host OS won't auto-repeat.
                                proRepeatStart(for: ek)
                            }
                            // For non-repeatable keys: do NOT send key-down yet.
                            // The key will be sent on finger lift in onEnded.
                        }
                        currentDragLocation = v.location
                        if alternatesPopup != nil, let start = alternatesGestureStart {
                            let dx = v.location.x - start.x, dy = v.location.y - start.y
                            let occ = Array(repeating: false, count: AlternatePopupGeometry.slotCount)
                                .enumerated().map { slot, _ in alternatesPopup!.options.contains { $0.slot == slot } }
                            let raw = AlternatePopupGeometry.pickSlot(dx: dx, dy: dy, rMinPx: 12, rCancelPx: 228, axisDeadzonePx: 18, slotOccupied: occ)
                            alternatesPick = raw == AlternatePopupGeometry.resultDefault ? .defaultSlot : raw == AlternatePopupGeometry.resultCancel ? .cancel : .slot(raw)
                        }
                        if keyboardManager.shouldShowAlternates(for: kd.label), longPressTimer == nil {
                            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                                DispatchQueue.main.async {
                                    // For repeatable keys: stop the deferred repeat cycle
                                    if isRepeatable {
                                        proRepeatStop()
                                    }
                                    self.showAlternatesPopup(for: kd)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        longPressTimer?.invalidate(); longPressTimer = nil
                        keyPressInProgress = false
                        currentlyPressedKey = nil
                        defer { alternatesShownThisPress = false }

                        if alternatesShownThisPress {
                            // Popup was shown — commit the selected alternate character
                            if let popup = alternatesPopup {
                                // Stop any remaining repeat, then commit alternate
                                proRepeatStop()
                                commitAlternate(from: popup)
                            } else {
                                // Popup was already dismissed (e.g. swipe-cancel);
                                // still need to stop any pending proRepeat timers.
                                proRepeatStop()
                                dismissAlternatesPopup()
                            }
                        } else {
                            // Short tap — popup never appeared
                            dismissAlternatesPopup()
                            if isRepeatable {
                                // Stop repeat and send one final key tap.
                                // If repeat had already started, this stops it cleanly.
                                // If finger lifted before repeat delay, sends one tap.
                                proRepeatStopAndFinalize(for: ek)
                            } else {
                                // Non-repeatable key: send full press+release cycle on finger lift
                                handleKeyDownFor(kd)
                                handleKeyUpFor(kd)
                            }
                        }
                    }
                ))
        }
    }

    private func commitAlternate(from popup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)) {
        let option: AlternateOption?
        if case .slot(let s) = alternatesPick { option = popup.options.first(where: { $0.slot == s }) }
        else if case .defaultSlot = alternatesPick { option = popup.options.first(where: { $0.slot == AlternatePopupGeometry.slotCenter }) }
        else { option = nil }

        handleKeyUpFor(popup.keyDef)
        dismissAlternatesPopup()

        guard let opt = option else { return }
        HapticFeedbackManager.shared.triggerButtonPress()

        // Build modifier list from requiresShift + modifierMask (matching Android sendAlternateOption)
        var mods: [String] = []
        if opt.requiresShift { mods.append("Shift") }
        if (opt.modifierMask & 0x01) != 0 { mods.append("Ctrl") }
        if (opt.modifierMask & 0x02) != 0 { mods.append("Shift") }
        if (opt.modifierMask & 0x04) != 0 { mods.append("Alt") }
        if (opt.modifierMask & 0x08) != 0 { mods.append("Win") }

        if mods.isEmpty {
            keyboardManager.handleKeyPress(opt.keyCode)
        } else {
            keyboardManager.handleKeyCombo(modifiers: mods, key: opt.keyCode)
        }
    }

    /// Returns icon/text/both based on the KeysDisplayMode setting.
    @ViewBuilder
    private func keyDisplay(icon: String, text: String, fallbackText: String? = nil, font: Font? = nil) -> some View {
        let mode = prefs.keysDisplayMode
        let hasIcon = !icon.isEmpty
        let showIcon = (mode == .icons || mode == .combo) && hasIcon
        let showText = mode == .names || mode == .combo || !hasIcon
        let label = fallbackText ?? text
        VStack(spacing: 1) {
            if showIcon {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
            if showText {
                Text(label).font(font ?? .system(size: mode == .combo ? 7 : 11))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func keyContent(for kd: KeyboardManager.KeyDef, displayText: String) -> some View {
        switch kd.label {
        case "Backspace":
            keyDisplay(icon: "backspace_24", text: "⌫")
                .rotationEffect(kd.symbolLabel.isEmpty && keyboardManager.activeModifiers.contains("Shift") ? .degrees(180) : .degrees(0))
        case "Enter":
            keyDisplay(icon: "keyboard_return_24px", text: "↵")
        case "Shift":
            keyDisplay(icon: "shift_24px", text: "⇧")
        case "Del", "Delete", "FwdDel":
            keyDisplay(icon: "backspace_24", text: "Del")
                .rotationEffect(.degrees(180))
        case "Space":
            if orientationManager.isLandscape && !isSplitLayout {
                Image("openterface_wordmark")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 60, height: 25)
                    .padding(.horizontal, 8)
            } else {
                Text("Space").font(.system(size: 12))
            }
        case "Cmd": cmdKeyLabel
        case "Option": optionKeyLabel
        case "App":
            keyDisplay(icon: "ic_list_alt_24", text: "App")
        case "Tab":
            keyDisplay(icon: "keyboard_tab_24", text: "Tab")
        case "Ctrl":
            keyDisplay(icon: aiSettings.targetOS == .macOS ? "keyboard_control_key_24px" : "", text: "Ctrl", font: aiSettings.targetOS == .macOS ? nil : .system(size: 11, weight: .bold))
        case "Alt":
            keyDisplay(icon: aiSettings.targetOS == .macOS ? "keyboard_option_key_24px" : "", text: "Alt", font: aiSettings.targetOS == .macOS ? nil : .system(size: 11, weight: .bold))
        case "Win":
            keyDisplay(icon: aiSettings.targetOS == .windows ? "targetos_windows" : aiSettings.targetOS == .linux ? "targetos_linux" : "keyboard_command_key_24px", text: "Win")
        case "Caps": Text("Caps").font(.system(size: 11))
        case "Fn": Text("Fn").font(.system(size: 12, weight: .bold))
        default:
            Text(keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty ? kd.symbolLabel : displayText)
                .font(.system(size: keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty ? 14 : 12))
        }
    }

    private var cmdKeyLabel: some View {
        keyDisplay(icon: "keyboard_command_key_24px", text: "Cmd")
    }
    private var optionKeyLabel: some View {
        keyDisplay(icon: "keyboard_option_key_24px", text: "Opt")
    }

    // MARK: - Pro Key Repeat (deferred — never holds key-down)

    /// Start deferred key repeat. Waits 400ms, then sends key-down/up pairs every 80ms.
    /// The key is NOT sent on initial touch, so the host OS won't start its own auto-repeat.
    private func proRepeatStart(for key: String) {
        proRepeatStop()
        proRepeatKey = key
        proRepeatDidFire = false
        proRepeatStarter = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [self] _ in
            guard let k = proRepeatKey else { return }
            proRepeatStarter = nil
            proRepeatDidFire = true  // mark that at least one key tap has been sent
            // First key tap
            keyboardManager.handleKeyPress(k)
            // Start bouncing every 80ms
            proRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [self] _ in
                guard let k = proRepeatKey else { return }
                keyboardManager.handleKeyPress(k)
            }
        }
    }

    /// Stop deferred repeat. Does NOT send any key — caller decides what to commit.
    /// Returns true only if the repeat actually fired (i.e. ≥1 key tap was sent).
    @discardableResult
    private func proRepeatStop() -> Bool {
        let didFire = proRepeatDidFire
        proRepeatStarter?.invalidate(); proRepeatStarter = nil
        proRepeatTimer?.invalidate(); proRepeatTimer = nil
        proRepeatKey = nil
        proRepeatDidFire = false
        return didFire
    }

    /// Stop repeat and send one final key tap.
    /// If the repeat already fired (starter timer ran), just stops — keys already sent.
    /// If finger lifted before the 400ms delay, sends a single key tap.
    private func proRepeatStopAndFinalize(for key: String) {
        if proRepeatStop() {
            // Repeat fired — already sent key taps. Nothing more to do.
        } else {
            // Finger lifted before repeat delay — send one key tap
            keyboardManager.handleKeyPress(key)
        }
    }

    /// Send key-down for a non-modifier key. For repeatable keys (arrows, backspace),
    /// starts a proper key-repeat cycle (up-down bounce). For non-repeatable keys,
    /// just sends a key-down.
    private func handleKeyDownFor(_ kd: KeyboardManager.KeyDef) {
        switch kd.label {
        case "Fn": keyboardManager.isFnLocked.toggle()
        case "ABC", "12/34": keyboardManager.isSymbolMode.toggle()
        case "!?#": keyboardManager.isSymbolMode = true
        default:
            let ek = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
            if KeyRepeatController.repeatableKeys.contains(ek) {
                // Proper key repeat: sends key-down, then up-down bounces after initial delay
                keyboardManager.startKeyRepeat(ek)
            } else {
                keyboardManager.handleKeyDown(ek)
            }
        }
    }

    /// Send key-up for a non-modifier key. For repeatable keys, stops the
    /// key-repeat cycle (which internally sends a final key-up).
    private func handleKeyUpFor(_ kd: KeyboardManager.KeyDef) {
        switch kd.label {
        case "Fn", "ABC", "12/34", "!?#":
            break // Toggle-only keys — no key-up needed
        default:
            let ek = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
            if KeyRepeatController.repeatableKeys.contains(ek) {
                keyboardManager.stopKeyRepeat()
            } else {
                keyboardManager.handleKeyUp(ek)
            }
        }
    }

    private static let functionKeyBg = Color(UIColor.secondarySystemBackground)
    private func keyBackground(for kd: KeyboardManager.KeyDef, pressed: Bool, active: Bool) -> Color {
        pressed || active ? themeManager.accentColor : Self.functionKeyBg
    }
    /// Build a top-center hint row from the first 4 (cardinal) alternates.
    /// Returns nil if there are no valid cardinal alternates.
    private func cardinalAlternatesHint(for kd: KeyboardManager.KeyDef) -> String? {
        let symbols = kd.alternates.prefix(4).compactMap { alt -> String? in
            let trimmed = alt.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return symbols.isEmpty ? nil : symbols.joined(separator: " ")
    }

    @ViewBuilder private func keyHints(for kd: KeyboardManager.KeyDef) -> some View {
        if let hint = cardinalAlternatesHint(for: kd) {
            // Multi-symbol row at top-center (matching Android keycap hint row)
            Text(hint)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .allowsHitTesting(false)
        } else if !kd.cornerHint.isEmpty {
            // Fallback: single corner hint when no cardinal alternates exist
            Text(kd.cornerHint)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.trailing, 6)
                .padding(.top, 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Alternates Popup

    private func showAlternatesPopup(for kd: KeyboardManager.KeyDef) {
        alternatesShownThisPress = true
        guard keyboardManager.shouldShowAlternates(for: kd.label) else { return }
        var slotMap: [Int: AlternateOption] = [:], seen: Set<String> = []
        func addOpt(_ slot: Int, _ alt: String) {
            guard let m = mapAsciiAlternate(alt), !seen.contains(m.display) else { return }
            slotMap[slot] = AlternateOption(display: m.display, keyCode: m.keyCode, requiresShift: m.requiresShift, modifierMask: m.modifierMask, slot: slot)
            seen.insert(m.display)
        }
        if let c = centerAlternateOption(for: kd), !seen.contains(c.display) { slotMap[AlternatePopupGeometry.slotCenter] = c; seen.insert(c.display) }
        let allSlots = [AlternatePopupGeometry.slotUp, AlternatePopupGeometry.slotDown, AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotRight, AlternatePopupGeometry.slotUpLeft, AlternatePopupGeometry.slotUpRight, AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDownRight]
        for (i, slot) in allSlots.enumerated() where i < kd.alternates.count { addOpt(slot, kd.alternates[i]) }
        let options = Array(slotMap.values)
        guard options.count >= 2 else { return }
        alternatesPopup = (options, keyFrames[kd.label] ?? .zero, kd)
        alternatesGestureStart = currentDragLocation; alternatesPick = .defaultSlot
    }
    private func centerAlternateOption(for kd: KeyboardManager.KeyDef) -> AlternateOption? {
        let sc = AlternatePopupGeometry.slotCenter
        if kd.label.count == 1, let c = kd.label.first, c.isLetter {
            return AlternateOption(display: kd.label.uppercased(), keyCode: kd.label, requiresShift: true, modifierMask: 0, slot: sc)
        }
        guard let m = mapAsciiAlternate(kd.label) else { return nil }
        return AlternateOption(display: m.display, keyCode: m.keyCode, requiresShift: m.requiresShift, modifierMask: m.modifierMask, slot: sc)
    }

    private static let shiftKeyMap: [String: (base: String, display: String)] = [
        "!": ("1", "!"), "@": ("2", "@"), "#": ("3", "#"), "$": ("4", "$"), "%": ("5", "%"),
        "^": ("6", "^"), "&": ("7", "&"), "*": ("8", "*"), "(": ("9", "("), ")": ("0", ")"),
        "_": ("-", "_"), "+": ("=", "+"), "{": ("[", "{"), "}": ("]", "}"),
        "<": (",", "<"), ">": (".", ">"), "?": ("/", "?"), ":": (";", ":"),
        "\"": ("'", "\""), "~": ("`", "~"),
    ]

    // Modifier masks matching Android: 0x04 = Alt, 0x02 = Shift
    // Currency symbols: ¥=Alt+'7', £=Alt+'3', €=Alt+Shift+'4'
    // Uses String keys to avoid Unicode Character normalization mismatches.
    private static let extraSymbolMap: [String: (baseKey: String, display: String, requiresShift: Bool, modifierMask: UInt8)] = [
        "\\": ("]", "]", true, 0), "|": ("]", "]", true, 0), "+": ("=", "+", true, 0),
        "#": ("3", "#", true, 0), "$": ("4", "$", true, 0), "%": ("5", "%", true, 0),
        "^": ("6", "^", true, 0), "&": ("7", "&", true, 0), "*": ("8", "*", true, 0),
        "\u{20AC}": ("4", "\u{20AC}", true, 0x04),  // €
        "\u{00A5}": ("7", "\u{00A5}", false, 0x04), // ¥
        "\u{00A3}": ("3", "\u{00A3}", false, 0x04), // £
    ]

    private func mapAsciiAlternate(_ char: String) -> (display: String, keyCode: String, requiresShift: Bool, modifierMask: UInt8)? {
        guard char.count == 1 else { return nil }
        if let c = char.first, c.isLetter { return (char, char, false, 0) }
        if let e = Self.shiftKeyMap[char] { return (e.display, e.base, true, 0) }
        if "0123456789".contains(char) || "-=[];',./`".contains(char) { return (char, char, false, 0) }
        if let e = Self.extraSymbolMap[char] { return (e.display, e.baseKey, e.requiresShift, e.modifierMask) }
        return nil
    }

    private func dismissAlternatesPopup() {
        alternatesPopup = nil; alternatesGestureStart = nil; alternatesPick = .none
    }
    
    // MARK: - Text Input View

    private var textInputView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $textInputContent).font(.system(size: 14)).padding(8).padding(.trailing, 40).padding(.bottom, 40)
                .background(Color(UIColor.systemBackground)).cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(UIColor.separator), lineWidth: 1))
            if textInputContent.isEmpty {
                Text("Type and edit long text here - tap Send to send it to the connected device").font(.system(size: 14)).foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 16).allowsHitTesting(false)
            }
            VStack { Spacer(); HStack { Spacer(); textExpandBtn } }
        }.padding(.horizontal, 8).padding(.vertical, 4).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }
    private var textExpandBtn: some View {
        Button { withAnimation { isTextInputExpanded.toggle() } } label: {
            Image(systemName: isTextInputExpanded ? "chevron.down" : "chevron.up").font(.system(size: 14)).foregroundColor(.blue).padding(8)
                .background(Color(UIColor.secondarySystemBackground)).cornerRadius(6)
        }.padding(8)
    }
}

struct ProTouchpadScrollStripView: View {
    let mouseManager: MouseManager
    var labelFontSize: CGFloat = 7

    @State private var lastScrollY: CGFloat?
    @State private var isScrolling: Bool = false

    private let pixelsPerWheelUnit: CGFloat = 5.0
    private var sensitivity: Double { KmProPrefs.shared.stripScrollSensitivity }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.secondarySystemBackground)
                VStack(spacing: 0) {
                    let chevronSize = min(24, max(14, geometry.size.width * 0.85))
                    let chevronHeight = chevronSize * 0.6
                    Image(systemName: "chevron.up")
                        .font(.system(size: labelFontSize * 3))
                        .foregroundColor(.secondary)
                        .frame(width: chevronSize, height: chevronHeight)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: labelFontSize * 3))
                        .foregroundColor(.secondary)
                        .frame(width: chevronSize, height: chevronHeight)
                }
                .padding(.vertical, 6)
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if lastScrollY == nil {
                            lastScrollY = value.location.y
                            isScrolling = true
                        }
                        guard let prevY = lastScrollY else { return }
                        let deltaY = value.location.y - prevY
                        if abs(deltaY) > pixelsPerWheelUnit {
                            let wheelUnits = Int(deltaY / pixelsPerWheelUnit * sensitivity)
                            if wheelUnits != 0 {
                                mouseManager.handleScroll(deltaX: 0, deltaY: -wheelUnits)
                                lastScrollY = value.location.y
                                HapticFeedbackManager.shared.triggerScrollTick()
                            }
                        }
                    }
                    .onEnded { _ in
                        lastScrollY = nil
                        isScrolling = false
                    }
            )
        }
        .clipped()
    }
}

/// Modifier key wrapper for Pro mode — uses ModifierKeyButton with lock/sticky support,
/// matching BasicKeyboardMouseView's modifier behavior.
private struct ProModifierKey: View {
    let kd: KeyboardManager.KeyDef
    let keyboardManager: KeyboardManager
    let displayText: String
    let content: AnyView
    let height: CGFloat

    @ObservedObject private var prefs = KmProPrefs.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ModifierKeyButton(key: kd.label, keyboardManager: keyboardManager, keyPreview: displayText) { physical, locked in
            let isModActive = keyboardManager.activeModifiers.contains(kd.label)
            let isActive = locked || physical || isModActive
            content
                .background(
                    isModActive ? themeManager.accentColor : (physical ? themeManager.accentColor.opacity(0.7) : Color(UIColor.secondarySystemBackground)),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .foregroundColor(isActive ? .white : .primary)
        }
        .frame(height: height)

    }
}

