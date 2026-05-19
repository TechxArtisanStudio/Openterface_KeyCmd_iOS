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
        if isActive && !tf.isFirstResponder { DispatchQueue.main.async { tf.becomeFirstResponder() } }
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

struct ProKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @ObservedObject var orientationManager: OrientationManager
    @Binding var proSubmode: ProSubmode

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
    @State private var isTextInputExpanded = false
    @State private var showTouchpadHelp = false

    // MARK: - Landscape full/split layout & portrait BI/IME persistence

    private enum LandscapeLayout: String { case full = "full", split = "split" }
    private enum PortraitInput: String { case builtIn = "built_in", ime = "ime" }

    enum ProSubmode: Int, CaseIterable {
        case keyboard, compose, numpad
        var icon: String { switch self { case .keyboard: return "keyboard"; case .compose: return "pencil.and.outline"; case .numpad: return "0.square" } }
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
            ShortcutEntry(label: "ALL",   icon: "text.badge.checkmark") { combo([pm], "A") },
            ShortcutEntry(label: "COPY",  icon: "doc.on.doc")           { combo([pm], "C") },
            ShortcutEntry(label: "CUT",   icon: "scissors")             { combo([pm], "X") },
            ShortcutEntry(label: "PASTE", icon: "clipboard")            { combo([pm], "V") },
            ShortcutEntry(label: "SAVE",  icon: "externaldrive")        { combo([pm], "S") },
            ShortcutEntry(label: "UNDO",  icon: "arrow.uturn.backward") { combo([pm], "Z") },
            ShortcutEntry(label: "FIND",  icon: "magnifyingglass")      { combo(["Ctrl"], "F") },
        ])
    }

    private var fixedRowsToggleEntry: ShortcutEntry {
        ShortcutEntry(label: "", icon: "arrow.left.arrow.right", isActive: fixedRowsLocalFnLocked) {
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
        let ke = { Self.keyEntry(km, label: $0, icon: "") }
        let keKey = { (label: String, key: String) in Self.keyEntry(km, label: label, icon: "", key: key) }
        let tog = fixedRowsToggleEntry
        let kbdTog = keyboardToggleEntry

        // Page 0 — F-keys / number-symbol
        let p0Fkeys = [("F1","1"),("F2","2"),("F3","3"),("F4","4"),("F5","5"),("F6","6")]
            .map { Self.keyEntry(km, label: $0.0, icon: "", badge: $0.1) }
        let p0FnKeys = [("F7","7"),("F8","8"),("F9","9"),("F10","0"),("F11","+"),("F12","-")]
            .map { Self.keyEntry(km, label: $0.0, icon: "", badge: $0.1) }
        let p0 = FixedRowsPage(
            row1: lock ? ["7","8","9","0","+","-","*"].map { te($0) } : p0FnKeys + [Self.textEntry(km, label: "#", badge: "*")],
            row2: lock ? ["1","2","3","4","5","6"].map { te($0) } + [tog] : p0Fkeys + [tog]
        )

        // Page 1 — Modifiers + Navigation
        let isMacOS = aiSettings.targetOS == .macOS
        let isWindows = aiSettings.targetOS == .windows
        let modCfg: [(String, String, String)] = isMacOS
            ? [("Ctrl","","control"),("Alt","","option"),("Cmd","","command")]
            : isWindows ? [("Ctrl","CTRL",""),("Alt","ALT",""),("Cmd","WIN","")]
                        : [("Ctrl","CTRL",""),("Alt","ALT",""),("Cmd","SUP","")]
        let modEntries = modCfg.map { cfg in ShortcutEntry(label: cfg.1, icon: cfg.2.isEmpty ? nil : cfg.2, isActive: keyboardManager.activeModifiers.contains(cfg.0)) { km.handleModifierToggle(cfg.0) } }
        let p1Locked = FixedRowsPage(
            row1: [keKey("SCR","Scroll Lock"),keKey("PRT","PrtSc"),keKey("CAPS","Caps"),keKey("PAUSE","Pause"),keKey("HOME","Home"),keKey("PGUP","PgUp"),kbdTog],
            row2: [keKey("SPACE","Space"),keKey("BKSP","Backspace"),keKey("DEL","Delete"),keKey("INS","Insert"),keKey("END","End"),keKey("PGDN","PgDn"),tog]
        )
        let p1Unlocked = FixedRowsPage(
            row1: modEntries + [keKey("TAB","Tab"),keKey("UP","Up"),keKey("ENTER","Enter"),kbdTog],
            row2: [keKey("ESC","Escape"),Self.modifierEntry(km,label:"SHIFT",icon:"shift",key:"Shift"),keKey("DEL","Delete"),keKey("LEFT","Left"),keKey("DOWN","Down"),keKey("RIGHT","Right"),tog]
        )

        // Page 2 — Punctuation
        let p2Row1: [(String, String)] = [
            ("(","`"),(")","~"),("[","'"),("]","\""),(":",":"),("#","#"),("@","@"),
        ]
        let p2Row2: [(String, String)] = [
            ("/","<"),("\\",">"),("|","*"),("?","&"),("-","/"),("_","."),
        ]
        let p2 = FixedRowsPage(
            row1: lock ? ["`","~","'","\"","%","^","|"].map { te($0) }
                       : p2Row1.map { Self.textEntry(km, label: $0.0, badge: $0.1) },
            row2: lock ? ["<",">","*","&",",","."].map { te($0) } + [tog]
                       : p2Row2.map { Self.textEntry(km, label: $0.0, badge: $0.1) } + [tog]
        )

        return [p0, lock ? p1Locked : p1Unlocked, p2]
    }

    // MARK: - Shortcut helpers

    private static func modifierEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        return ShortcutEntry(label: label, icon: icon, isActive: km.activeModifiers.contains(k)) { km.handleModifierToggle(k) }
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
            let stripWidth = max(28, geo.size.width * 0.30)
            HStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState)
                    Button(action: { showTouchpadHelp = true }) {
                        Image(systemName: "questionmark.circle.fill").font(.system(size: 18, weight: .semibold)).foregroundColor(.secondary)
                            .padding(8).background(Color(UIColor.secondarySystemBackground).opacity(0.9)).clipShape(Circle())
                    }.padding(8)
                    if showLabel { touchpadLabel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).allowsHitTesting(false) }
                }.frame(width: max(0, geo.size.width - stripWidth))
                BasicTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: orientationManager.isLandscape ? 10 : 7).frame(width: stripWidth)
            }.background(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.secondarySystemBackground))
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
            HStack { Text("Touchpad Help").font(.headline); Spacer(); Button("Done") { showTouchpadHelp = false }.font(.subheadline) }
                .padding(.horizontal, 16).padding(.vertical, 12).background(Color(UIColor.secondarySystemBackground))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use these gestures in Pro Keyboard & Mouse mode:").font(.subheadline).foregroundColor(.secondary)
                    ForEach(["1. One finger drag: move pointer", "2. Single tap: left click", "3. Double tap: double click",
                             "4. Two-finger tap: right click", "5. Two-finger drag: wheel scrolling", "6. Long press: toggle drag mode",
                             "7. Right vertical strip: quick page scroll"], id: \.self) { Text($0).font(.body) }
                    Text("Tip: While drag mode is active, the touchpad background turns blue.")
                        .font(.footnote).foregroundColor(.secondary).padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }.background(Color(UIColor.systemBackground))
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
                .overlay { if proSubmode == .keyboard, let p = alternatesPopup { KeyAlternatesPopupView(options: p.options, anchorFrame: p.anchor, pick: alternatesPick).allowsHitTesting(false) } }
                .sheet(isPresented: $showTouchpadHelp) { touchpadHelpSheet }
                .offset(y: isTextInputMode ? (keyboardHeight > 0 ? -keyboardHeight * 0.65 : 30) : 0)
                .animation(.easeOut(duration: 0.3), value: keyboardHeight).animation(.easeOut(duration: 0.3), value: isTextInputMode)
                .onAppear {
                    isSplitLayout = persistedLandscapeLayout == .split; isImeSurface = persistedPortraitInput == .ime
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
                NumPadView(keyboardManager: keyboardManager, orientationManager: orientationManager)
                    .background(Color(UIColor.secondarySystemBackground))
                    .transaction { $0.animation = nil }
            }
            submodeView(active: .keyboard) {
                let barWidth: CGFloat = 50
                HStack(spacing: 0) {
                    Color(UIColor.secondarySystemBackground).frame(width: barWidth)
                    VStack(spacing: 0) {
                        if displayMode == .touchpad {
                            VStack(spacing: 0) { landscapeShortcutPanel; ZStack { touchpadOverlay(); landscapeHandleButton } }
                        } else if isSplitLayout {
                            let cw = geometry.size.width - barWidth, tw = cw * 0.33, sw = max(0, (cw - tw) / 2)
                            HStack(spacing: 0) {
                                splitSideColumn(side: .left, width: sw); touchpadOverlay().frame(width: tw); splitSideColumn(side: .right, width: sw)
                            }
                        } else {
                            VStack(spacing: 0) { landscapeShortcutPanel; keyboardRows.layoutPriority(1) }
                        }
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
        case 3: return kd.label == "Space" ? 40 : 10
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
        }.buttonStyle(PlainButtonStyle()).padding(.top, 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var landscapeShortcutPanel: some View {
        VStack(spacing: 0) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1)
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
        VStack(spacing: 0) {
            ForEach(currentKeys.indices, id: \.self) { r in
                let row = currentKeys[r]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { c in
                        let kd = row[c]
                        keyButton(for: kd, width: keyWidth(for: kd, row: row))
                    }
                }.frame(maxWidth: .infinity)
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
                NumPadView(keyboardManager: keyboardManager, orientationManager: orientationManager)
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
                }.background(Color(UIColor.secondarySystemBackground))
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
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<deleteCount { self.keyboardManager.sendKeyPressSynchronous("Backspace") }
            for char in insertStr {
                let s = char.unicodeScalars.first?.value ?? 0
                if s > 0x7E { UnicodeManager.shared.sendChar(char, keyboardManager: self.keyboardManager); usleep(50_000); continue }
                DispatchQueue.main.sync { self.keyboardManager.sendASCIICharInline(char) }
                usleep(50_000)
            }
        }
    }

    private var shortcutPanelContent: some View {
        VStack(spacing: 0) {
            ShortcutStripPager(pages: shortcutPages).id(profileMgr.activeProfileId).padding(.horizontal, 4)
            FixedRowsPager(pages: fixedRowsPages, defaultPageIndex: 1).padding(.horizontal, 4)
            if !isImeSurface { keyboardRows.frame(height: 380).padding(.top, -40).padding(.bottom, 10) }
        }
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
            case "Shift": return 16; case "Enter": return 12; case "Fn": return 9.5
            case "Space": return 47; case "Win": return 19; case "Del": return 11.5
            default: return 100 / CGFloat(row.count)
            }
        }
        if row.contains(where: { $0.label == "Space" }) { return kd.label == "Space" ? 40 : 10 }
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
        let isPressed = isModifier && keyboardManager.activeModifiers.contains(kd.label)
        let isActive = (kd.label == "Caps" && keyboardManager.capsLockActive) || (kd.label == "Fn" && keyboardManager.isFnLocked)
        let h = orientationManager.isLandscape ? 56.0 : 72.0
        let bg = GeometryReader { g in DispatchQueue.main.async { keyFrames[kd.label] = g.frame(in: .named("proKMView")) }; return Color.clear }
        let content = keyContent(for: kd, displayText: displayText)
            .frame(maxWidth: .infinity, maxHeight: h).background(keyBackground(for: kd, pressed: isPressed, active: isActive))
            .cornerRadius(9).foregroundColor(isPressed || isActive ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading).overlay(cornerHint(for: kd), alignment: .topTrailing)
            .contentShape(Rectangle()).background(bg)
        if isModifier {
            return AnyView(KeyPressButton(
                onPress: { HapticFeedbackManager.shared.triggerButtonPress(); keyboardManager.handleKeyDown(kd.label) },
                onRelease: { keyboardManager.handleKeyUp(kd.label) }
            ) { _ in content })
        } else {
            return AnyView(content
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("proKMView"))
                    .onChanged { v in
                        if !keyPressInProgress { keyPressInProgress = true; currentlyPressedKey = kd.label; handleKeyPress(kd) }
                        currentDragLocation = v.location
                        if alternatesPopup != nil, let start = alternatesGestureStart {
                            let dx = v.location.x - start.x, dy = v.location.y - start.y
                            let occ = Array(repeating: false, count: AlternatePopupGeometry.slotCount)
                                .enumerated().map { slot, _ in alternatesPopup!.options.contains { $0.slot == slot } }
                            let raw = AlternatePopupGeometry.pickSlot(dx: dx, dy: dy, rMinPx: 12, rCancelPx: 228, axisDeadzonePx: 18, slotOccupied: occ)
                            alternatesPick = raw == AlternatePopupGeometry.resultDefault ? .defaultSlot : raw == AlternatePopupGeometry.resultCancel ? .cancel : .slot(raw)
                        }
                        if keyboardManager.shouldShowAlternates(for: kd.label), longPressTimer == nil {
                            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in showAlternatesPopup(for: kd) }
                        }
                    }
                    .onEnded { _ in
                        longPressTimer?.invalidate(); longPressTimer = nil; keyPressInProgress = false; currentlyPressedKey = nil
                        if let popup = alternatesPopup { commitAlternate(from: popup); dismissAlternatesPopup() }
                        handleKeyRelease()
                    }
                ))
        }
    }

    private func commitAlternate(from popup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)) {
        let option: AlternateOption?
        if case .slot(let s) = alternatesPick { option = popup.options.first(where: { $0.slot == s }) }
        else if case .defaultSlot = alternatesPick { option = popup.options.first(where: { $0.slot == AlternatePopupGeometry.slotCenter }) }
        else { option = nil }
        guard let opt = option else { return }
        HapticFeedbackManager.shared.triggerButtonPress()
        if opt.requiresShift { keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: opt.keyCode) }
        else { keyboardManager.handleKeyPress(opt.keyCode) }
    }

    @ViewBuilder
    private func keyContent(for kd: KeyboardManager.KeyDef, displayText: String) -> some View {
        switch kd.label {
        case "Backspace":
            Image(systemName: "delete.left").font(.system(size: 16))
                .rotationEffect(kd.symbolLabel.isEmpty && keyboardManager.activeModifiers.contains("Shift") ? .degrees(180) : .degrees(0))
        case "Enter": Image(systemName: "return").font(.system(size: 16))
        case "Shift": Image(systemName: "shift").font(.system(size: 16))
        case "Del", "Delete", "FwdDel": Image(systemName: "delete.forward").font(.system(size: 16))
        case "Cmd": cmdKeyLabel
        case "Option": optionKeyLabel
        case "App": Image(systemName: "app").font(.system(size: 14))
        case "Tab": Image(systemName: "arrow.right.to.line.compact").font(.system(size: 14))
        case "Ctrl", "Alt", "Win": Text(getDisplayValue(for: kd.label)).font(.system(size: 12))
        case "Caps": Text("Caps").font(.system(size: 11))
        case "Fn": Text("Fn").font(.system(size: 12, weight: .bold))
        default:
            Text(keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty ? kd.symbolLabel : displayText)
                .font(.system(size: keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty ? 14 : 12))
        }
    }

    private var cmdKeyLabel: some View {
        let t: String
        switch aiSettings.targetOS {
        case .windows: t = "Win"; case .linux: t = "Super"; default: t = "Cmd"
        }
        return Text(t).font(.system(size: aiSettings.targetOS == .linux ? 10 : 12))
    }
    private var optionKeyLabel: some View {
        let t: String
        switch aiSettings.targetOS {
        case .windows: t = "Alt"; case .linux: t = "AltGr"; default: t = "Opt"
        }
        return Text(t).font(.system(size: aiSettings.targetOS == .linux ? 11 : 12))
    }

    private func handleKeyPress(_ kd: KeyboardManager.KeyDef) {
        HapticFeedbackManager.shared.triggerButtonPress()
        switch kd.label {
        case "Fn": keyboardManager.isFnLocked.toggle()
        case "ABC", "12/34": keyboardManager.isSymbolMode.toggle()
        case "!?#": keyboardManager.isSymbolMode = true
        case "Ctrl","Alt","Cmd","Win","Shift": keyboardManager.handleSpecialKey(kd.label)
        default:
            let ek = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
            keyboardManager.handleSpecialKey(ek)
            if KeyRepeatController.repeatableKeys.contains(ek) { keyRepeatController.startRepeating { keyboardManager.handleSpecialKey(ek) } }
            else { keyRepeatController.stopRepeating() }
        }
    }

    private static let functionKeyBg = Color(UIColor.secondarySystemBackground)
    private func keyBackground(for kd: KeyboardManager.KeyDef, pressed: Bool, active: Bool) -> Color {
        pressed || active ? .blue : Self.functionKeyBg
    }
    @ViewBuilder private func cornerHint(for kd: KeyboardManager.KeyDef) -> some View {
        if kd.cornerHint.isEmpty { EmptyView() }
        else { Text(kd.cornerHint).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary.opacity(0.6))
                .padding(.trailing, 6).padding(.top, 2).allowsHitTesting(false) }
    }

    // MARK: - Key Action Handler
    private func handleKeyRelease() { keyRepeatController.stopRepeating() }

    // MARK: - Alternates Popup

    private func showAlternatesPopup(for kd: KeyboardManager.KeyDef) {
        guard keyboardManager.shouldShowAlternates(for: kd.label) else { return }
        var slotMap: [Int: AlternateOption] = [:], seen: Set<String> = []
        func addOpt(_ slot: Int, _ alt: String) {
            guard let m = mapAsciiAlternate(alt), !seen.contains(m.display) else { return }
            slotMap[slot] = AlternateOption(display: m.display, keyCode: m.keyCode, requiresShift: m.requiresShift, slot: slot)
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
            return AlternateOption(display: kd.label.uppercased(), keyCode: kd.label, requiresShift: true, slot: sc)
        }
        guard let m = mapAsciiAlternate(kd.label) else { return nil }
        return AlternateOption(display: m.display, keyCode: m.keyCode, requiresShift: m.requiresShift, slot: sc)
    }

    private static let shiftKeyMap: [String: (base: String, display: String)] = [
        "!": ("1", "!"), "@": ("2", "@"), "#": ("3", "#"), "$": ("4", "$"), "%": ("5", "%"),
        "^": ("6", "^"), "&": ("7", "&"), "*": ("8", "*"), "(": ("9", "("), ")": ("0", ")"),
        "_": ("-", "_"), "+": ("=", "+"), "{": ("[", "{"), "}": ("]", "}"),
        "<": (",", "<"), ">": (".", ">"), "?": ("/", "?"), ":": (";", ":"),
        "\"": ("'", "\""), "~": ("`", "~"),
    ]

    private static let extraSymbolMap: [Character: (String, String, Bool)] = [
        "\\": ("]", "]", true), "|": ("]", "]", true), "+": ("=", "+", true),
        "#": ("3", "#", true), "$": ("4", "$", true), "%": ("5", "%", true),
        "^": ("6", "^", true), "&": ("7", "&", true), "*": ("8", "*", true),
        "€": ("4", "€", true), "¥": ("[", "¥", false), "£": ("'", "£", false),
    ]

    private func mapAsciiAlternate(_ char: String) -> (display: String, keyCode: String, requiresShift: Bool)? {
        guard char.count == 1 else { return nil }
        let c = char.first!
        if c.isLetter { return c.isLowercase ? (char, char, false) : (char, char.lowercased(), true) }
        if let e = Self.shiftKeyMap[char] { return (e.display, e.base, true) }
        if "0123456789".contains(c) || "-=[];',./`".contains(c) { return (char, char, false) }
        if let e = Self.extraSymbolMap[c] { return (e.0, e.1, e.2) }
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
