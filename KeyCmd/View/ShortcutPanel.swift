//
//  ShortcutPanel.swift
//  KeyMod
//
//  Android-parity shortcut strip layout:
//    Row 1  — pageable favorites strip  (ShortcutStripPager, ~44px + 9px dots)
//    Rows 2–3 — pageable fixed strip    (FixedRowsPager, ~88px + 9px dots)
//               Page 0: F-keys (F7–F12/= | F1–F6/FN)
//               Page 1: Modifiers + Navigation (default)
//               Page 2: Punctuation symbols
//  Total ≈ 150px, matching Android's three-row shortcut strip.
//

import SwiftUI
import UIKit

// MARK: - Data models

/// A single shortcut entry with icon and action
struct ShortcutEntry: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?  // Asset catalog name, or SF Symbol name as fallback
    /// Chord display text for combo mode (e.g. "⌘S", "Ctrl+Alt+L")
    var comboText: String? = nil
    var badge: String? = nil  // optional badge shown bottom-right (e.g. "A"/"B")
    /// When true the button renders with a highlighted (tinted) background
    var isActive: Bool = false
    /// Optional custom font for the label (e.g. larger/bolder for F-keys)
    var font: Font? = nil
    /// Optional rotation for the icon in degrees (e.g. 180 for forward-delete)
    var iconRotation: Double = 0
    /// When true, always show label regardless of display mode (for modifier keys like Ctrl/Alt/Cmd)
    var forceNameOnly: Bool = false
    let action: () -> Void
    /// Optional long-press action (e.g. open favorites editor). Powers .contextMenu on ShortcutButton.
    var onLongPress: (() -> Void)? = nil
}

/// A page of shortcuts (7 entries = 1 row of 7 columns)
struct ShortcutPage {
    let title: String
    let entries: [ShortcutEntry]
}

/// A two-row page for the fixed rows 2–3 strip
struct FixedRowsPage {
    let row1: [ShortcutEntry]  // row 2 (top)
    let row2: [ShortcutEntry]  // row 3 (bottom)
}

// MARK: - Icon helper

/// Renders an icon from the asset catalog (template-tinted Material icons from Android),
/// falling back to an SF Symbol when no matching asset exists.
@ViewBuilder
func iconImage(_ name: String, size: CGFloat = 18) -> some View {
    if !name.isEmpty, UIImage(named: name) != nil {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    } else if !name.isEmpty {
        Image(systemName: name)
            .font(.system(size: size + 2))
    }
}

// MARK: - ShortcutButton (shared primitive)

struct ShortcutButton: View {
    let entry: ShortcutEntry
    var background: Color = Color(UIColor.tertiarySystemBackground)
    @ObservedObject private var prefs = KmProPrefs.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let mode = prefs.keysDisplayMode
        // ponytail: Three display modes — names (label), icons (icon), combo (chord text).
        // Matches Android TopShortcutDisplayModePrefs.
        // forceNameOnly entries (modifier keys) always show label regardless of mode.
        let hasIcon: Bool = {
            guard let name = entry.icon, !name.isEmpty else { return false }
            if UIImage(named: name) != nil { return true }
            return UIImage(systemName: name) != nil
        }()
        let (displayText, showIcon): (String, Bool) = {
            if entry.forceNameOnly {
                return (entry.label, false)
            }
            switch mode {
            case .names:
                return (entry.label, false)
            case .icons:
                // Icon mode — show icon if available, else fall back to label
                return hasIcon ? (entry.label, true) : (entry.label, false)
            case .combo:
                // Combo mode — show chord text (e.g. "⌘S"), fall back to label
                return (entry.comboText ?? entry.label, false)
            }
        }()
        Button(action: entry.action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    if showIcon, let icon = entry.icon {
                        iconImage(icon, size: 22)
                            .rotationEffect(.degrees(entry.iconRotation))
                    }
                    if !displayText.isEmpty {
                        Text(displayText)
                            .font(entry.font ?? .system(size: mode == .combo ? 10 : 8, weight: mode == .combo ? .semibold : .regular))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(entry.isActive ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(entry.isActive ? themeManager.accentColor : background)
                .cornerRadius(8)

                if let badge = entry.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.top, 3)
                        .offset(x: -3, y: 0)
                }
            }
        }
        .simultaneousGesture(
            // ponytail: long-press directly opens favorites editor (Android parity)
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    if entry.onLongPress != nil {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        entry.onLongPress?()
                    }
                }
        )
    }
}

// MARK: - ShortcutStripPager (row 1 — horizontally scrollable favorites)

/// Swipeable single-row pager — 7 shortcuts per page.
/// Matches Android behavior where the whole row flips page together.
/// Apply `.id(profileId)` at the call site to reset to page 0 on profile switch.
struct ShortcutStripPager: View {
    let pages: [ShortcutPage]

    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        if !pages.isEmpty {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { idx in
                            ShortcutStripRowView(
                                entries: pages[idx].entries,
                                background: ThemeManager.shared.accentColor.opacity(0.15)
                            )
                            .frame(width: w)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * w + dragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8),
                               value: currentPage)
                    .frame(width: w, alignment: .leading)
                    .clipped()
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { v in
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let threshold = w * 0.12
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if v.translation.width < -threshold,
                                       currentPage < pages.count - 1 {
                                        currentPage += 1
                                    } else if v.translation.width > threshold,
                                              currentPage > 0 {
                                        currentPage -= 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .frame(height: 40)
            }
        }
    }
}

// MARK: - FixedRowsPager (rows 2–3 — pageable, 4 pages)

/// Swipeable 2-row pager mirroring Android's fixedTopRowsViewport (4 pages).
/// Uses DragGesture + offset so it works correctly inside a vertical ScrollView.
/// Default page index 1 = modifiers + navigation (FIXED_TOP_ROWS_DEFAULT_PAGE_INDEX = 1).
struct FixedRowsPager: View {
    let pages: [FixedRowsPage]
    var defaultPageIndex: Int = 1
    /// ponytail: external key to force row refresh when content changes (e.g. Fn toggle)
    var refreshKey: AnyHashable? = nil

    @State private var currentPage: Int = -1
    @State private var dragOffset: CGFloat = 0

    private let rowBackground = Color(UIColor.tertiarySystemBackground)

    private var activePage: Int {
        currentPage < 0 ? min(defaultPageIndex, max(0, pages.count - 1)) : currentPage
    }

    var body: some View {
        if !pages.isEmpty {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(0..<pages.count, id: \.self) { idx in
                            VStack(spacing: 4) {
                                ShortcutStripRowView(entries: pages[idx].row1,
                                                    background: rowBackground)
                                    .id(refreshKey.map { "\($0)-\(idx)-r1" } ?? "\(idx)-r1")
                                ShortcutStripRowView(entries: pages[idx].row2,
                                                    background: rowBackground)
                                    .id(refreshKey.map { "\($0)-\(idx)-r2" } ?? "\(idx)-r2")
                            }
                            .padding(.horizontal, 0)
                            .frame(width: w)
                        }
                    }
                    .offset(x: -CGFloat(activePage) * w + dragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8),
                               value: activePage)
                    .frame(width: w, alignment: .leading)
                    .clipped()
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { v in
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let threshold = w * 0.12
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if v.translation.width < -threshold,
                                       activePage < pages.count - 1 {
                                        currentPage = activePage + 1
                                    } else if v.translation.width > threshold,
                                              activePage > 0 {
                                        currentPage = activePage - 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .frame(height: 88)
                .onAppear {
                    if currentPage < 0 {
                        currentPage = min(defaultPageIndex, pages.count - 1)
                    }
                }
            }
        }
    }
}

// MARK: - ShortcutFixedRowsView (rows 2–3 — static, kept for backward compat)

/// Two always-visible rows of 7 buttons each (non-pageable).
struct ShortcutFixedRowsView: View {
    let row1: [ShortcutEntry]
    let row2: [ShortcutEntry]

    private let rowBackground = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        VStack(spacing: 4) {
            ShortcutStripRowView(entries: row1, background: rowBackground)
            ShortcutStripRowView(entries: row2, background: rowBackground)
        }
        .frame(height: 88)
    }
}

// MARK: - ShortcutStripRowView (single row of 7)

struct ShortcutStripRowView: View {
    let entries: [ShortcutEntry]
    var background: Color = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { colIndex in
                if colIndex < entries.count {
                    ShortcutButton(entry: entries[colIndex], background: background)
                        .id(entries[colIndex].id)
                } else {
                    ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: background)
                        .disabled(true)
                        .opacity(0.3)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Punctuation page data (shared between ProKeyboardMouseView and ComposeTextView)

enum PunctuationPageData {
    static let unlockedRow1: [(String, String)] = [
        ("(","`"),(")","~"),("[","'"),("]","\""),(":","%"),("#","^"),("@","|"),
    ]
    static let unlockedRow2: [(String, String)] = [
        ("/","<"),("\\",">"),("|","*"),("?","&"),("-","/"),("_","."),
    ]
    static let lockedRow1: [(String, String)] = [
        ("`","("),("~",")"),("'","["),("\"","]"),("%",":"),("^","#"),("|","@")
    ]
    static let lockedRow2: [(String, String)] = [
        ("<","/"),(">","\\"),("*","|"),("&","?"),(",","-"),(".","_")
    ]
}

// MARK: - Shared shortcut panel builder
// ponytail: single source of truth for fixedRowsPages / shortcutPages / standardShortcuts
// so ProKeyboardMouseView and ComposeTextView render identical keys, icons, and fonts.

enum SharedShortcutPanel {
    static let keyFont: Font = .system(size: 11, weight: .bold)

    // MARK: Entry factories

    static func modifierEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil, font: Font? = nil) -> ShortcutEntry {
        let k = key ?? label
        var entry = ShortcutEntry(label: label, icon: icon, isActive: km.activeModifiers.contains(k)) { km.handleModifierToggle(k) }
        entry.font = font
        entry.forceNameOnly = true
        return entry
    }

    static func keyEntry(_ km: KeyboardManager, label: String, icon: String, key: String? = nil, badge: String? = nil) -> ShortcutEntry {
        let k = key ?? label
        var entry = ShortcutEntry(label: label, icon: icon.isEmpty ? nil : icon) { km.handleKeyPress(k) }
        entry.badge = badge
        return entry
    }

    static func textEntry(_ km: KeyboardManager, label: String, badge: String? = nil) -> ShortcutEntry {
        var entry = ShortcutEntry(label: label, icon: nil) { km.handleTextInput(label) }
        entry.badge = badge
        return entry
    }

    // MARK: Combo text formatting

    static func formatComboText(modifiers: [String], key: String, targetOS: TargetOS) -> String {
        guard !modifiers.isEmpty else { return key }
        if targetOS == .macOS {
            let glyphMap: [String: String] = [
                "Ctrl": "⌃", "Control": "⌃",
                "Alt": "⌥", "Option": "⌥",
                "Shift": "⇧",
                "Cmd": "⌘", "Command": "⌘", "Win": "⌘", "Super": "⌘", "Meta": "⌘"
            ]
            let modGlyphs = modifiers.map { glyphMap[$0] ?? $0 }
            return modGlyphs.joined() + key
        } else {
            return modifiers.joined(separator: "+") + "+" + key
        }
    }

    // MARK: Profile entries

    static func profileEntries(km: KeyboardManager, profileMgr: ShortcutProfileManager, targetOS: TargetOS, onLongPress: (() -> Void)? = nil) -> [ShortcutEntry] {
        guard let active = profileMgr.activeProfile else { return [] }
        let items = !profileMgr.myShortcuts(for: active.id).isEmpty
            ? profileMgr.myShortcuts(for: active.id)
            : Array(active.categories.first?.shortcuts.prefix(7) ?? [])
        return items.map { item in
            let mods = (item.modifier ?? "").split(separator: "+").map(String.init)
            let comboText = formatComboText(modifiers: mods, key: item.key, targetOS: targetOS)
            var entry = ShortcutEntry(label: String(item.description.prefix(8)), icon: item.icon, comboText: comboText) {
                mods.isEmpty ? km.handleSpecialKey(item.keyCode) : km.handleKeyCombo(modifiers: mods, key: item.keyCode)
            }
            entry.onLongPress = onLongPress
            return entry
        }
    }

    // MARK: Standard shortcuts (fallback when no profile)

    static func standardShortcuts(combo: @escaping ([String], String) -> Void, pm: String, targetOS: TargetOS) -> ShortcutPage {
        func stdEntry(_ label: String, _ icon: String, _ mods: [String], _ key: String) -> ShortcutEntry {
            let comboText = formatComboText(modifiers: mods, key: key, targetOS: targetOS)
            return ShortcutEntry(label: label, icon: icon, comboText: comboText) { combo(mods, key) }
        }
        return ShortcutPage(title: "Standard", entries: [
            stdEntry("ALL",   "select_all_24",    [pm], "A"),
            stdEntry("COPY",  "content_copy_24",  [pm], "C"),
            stdEntry("CUT",   "content_cut_24",   [pm], "X"),
            stdEntry("PASTE", "content_paste_24", [pm], "V"),
            stdEntry("SAVE",  "save_24",          [pm], "S"),
            stdEntry("UNDO",  "undo_24",          [pm], "Z"),
            stdEntry("FIND",  "magnifyingglass",  ["Ctrl"], "F"),
        ])
    }

    // MARK: Shortcut pages (row 1 — pageable favorites)

    static func shortcutPages(km: KeyboardManager, profileMgr: ShortcutProfileManager, targetOS: TargetOS, onLongPress: (() -> Void)? = nil) -> [ShortcutPage] {
        let pm = targetOS == .macOS ? "Cmd" : "Ctrl"
        let combo: ([String], String) -> Void = { km.handleKeyCombo(modifiers: $0, key: $1) }
        let source = profileEntries(km: km, profileMgr: profileMgr, targetOS: targetOS, onLongPress: onLongPress)
        guard !source.isEmpty else { return [standardShortcuts(combo: combo, pm: pm, targetOS: targetOS)] }
        let chunks = stride(from: 0, to: source.count, by: 7).map { Array(source[$0..<min($0 + 7, source.count)]) }
        let name = profileMgr.activeProfile?.name ?? ""
        return chunks.enumerated().map { (i, c) in ShortcutPage(title: c.count > 1 ? "\(name) \(i + 1)/\(c.count)" : name, entries: c) }
    }

    // MARK: Fixed rows pages (rows 2–3)

    /// Build the 3-page fixed rows strip.
    /// - trailingEntry: optional 7th-column entry for row1 (e.g. keyboard toggle or IME indicator)
    static func fixedRowsPages(km: KeyboardManager, lock: Bool, tog: ShortcutEntry, trailingEntry: ShortcutEntry? = nil, targetOS: TargetOS) -> [FixedRowsPage] {
        let f = keyFont
        let te = { textEntry(km, label: $0) }
        let keKey: (String, String) -> ShortcutEntry = { label, key in
            let iconMap: [String: String] = [
                "Tab": "keyboard_tab_24", "Up": "keyboard_arrow_up_24",
                "Enter": "keyboard_return_24px", "Delete": "backspace_24",
                "Left": "keyboard_arrow_left_24", "Down": "keyboard_arrow_down_24",
                "Right": "keyboard_arrow_right_24", "Backspace": "backspace_24",
                "Space": "space_bar_24px",
            ]
            var entry = keyEntry(km, label: label, icon: iconMap[key] ?? "", key: key)
            entry.font = f
            if key == "Delete" { entry.iconRotation = 180 }
            return entry
        }

        // Page 0 — F-keys / number-symbol
        let p0Fkeys = [("F1","1"),("F2","2"),("F3","3"),("F4","4"),("F5","5"),("F6","6")]
            .map { (pair) -> ShortcutEntry in
                var entry = keyEntry(km, label: pair.0, icon: "", badge: pair.1)
                entry.font = f
                return entry
            }
        let p0FnKeys = [("F7","7"),("F8","8"),("F9","9"),("F10","0"),("F11","+"),("F12","-")]
            .map { (pair) -> ShortcutEntry in
                var entry = keyEntry(km, label: pair.0, icon: "", badge: pair.1)
                entry.font = f
                return entry
            }
        let p0NumKeysTop = [("7","&"),("8","*"),("9","("),("0",")"),("+","="),("-","_"),("*","=")]
            .map { (pair) -> ShortcutEntry in
                var entry = textEntry(km, label: pair.0, badge: pair.1)
                entry.font = f
                return entry
            }
        let p0NumKeysBottom = [("1","!"),("2","@"),("3","£"),("4","¥"),("5","%"),("6","^")]
            .map { (pair) -> ShortcutEntry in
                var entry = textEntry(km, label: pair.0, badge: pair.1)
                entry.font = f
                return entry
            }
        let p0EqKey: ShortcutEntry = {
            var entry = textEntry(km, label: "=", badge: "*")
            entry.font = f
            return entry
        }()
        let p0 = FixedRowsPage(
            row1: lock ? p0NumKeysTop : p0FnKeys + [p0EqKey],
            row2: lock ? p0NumKeysBottom + [tog] : p0Fkeys + [tog]
        )

        // Page 1 — Modifiers + Navigation
        let isMacOS = targetOS == .macOS
        let isWindows = targetOS == .windows
        let winIcon = targetOS == .windows ? "targetos_windows" : "targetos_linux"
        let modCfg: [(String, String, String)] = isMacOS
            ? [("Ctrl","Ctrl","keyboard_control_key_24px"),("Alt","Opt","keyboard_option_key_24px"),("Cmd","Cmd","keyboard_command_key_24px")]
            : isWindows ? [("Ctrl","Ctrl",""),("Alt","Alt",""),("Win","Win",winIcon)]
                        : [("Ctrl","Ctrl",""),("Alt","Alt",""),("Win","Super",winIcon)]
        let modEntries = modCfg.map { cfg -> ShortcutEntry in
            var entry = ShortcutEntry(label: cfg.1, icon: cfg.2.isEmpty ? nil : cfg.2, isActive: km.activeModifiers.contains(cfg.0)) { km.handleModifierToggle(cfg.0) }
            entry.font = f
            entry.forceNameOnly = true
            return entry
        }

        let trailing = trailingEntry ?? tog
        let p1Locked = FixedRowsPage(
            row1: [keKey("SCR LK","Scroll Lock"),keKey("PRT SC","PrtSc"),keKey("CAPS","Caps"),keKey("PAUSE","Pause"),keKey("HOME","Home"),keKey("PGUP","PgUp"),trailing],
            row2: [keKey("SPACE","Space"),keKey("BKSP","Backspace"),keKey("DEL","Delete"),keKey("INS","Insert"),keKey("END","End"),keKey("PGDN","PgDn"),tog]
        )
        let p1Unlocked = FixedRowsPage(
            row1: modEntries + [keKey("Tab","Tab"),keKey("UP","Up"),keKey("ENTER","Enter"),trailing],
            row2: [keKey("ESC","Escape"),modifierEntry(km,label:"SHIFT",icon:"shift_24px",key:"Shift",font:f),keKey("DEL","Delete"),keKey("LEFT","Left"),keKey("DOWN","Down"),keKey("RIGHT","Right"),tog]
        )

        // Page 2 — Punctuation
        let p2 = FixedRowsPage(
            row1: lock ? PunctuationPageData.lockedRow1.map { (pair) -> ShortcutEntry in
                            var entry = textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = f
                            return entry
                        }
                       : PunctuationPageData.unlockedRow1.map { (pair) -> ShortcutEntry in
                            var entry = textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = f
                            return entry
                        },
            row2: lock ? PunctuationPageData.lockedRow2.map { (pair) -> ShortcutEntry in
                            var entry = textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = f
                            return entry
                        } + [tog]
                       : PunctuationPageData.unlockedRow2.map { (pair) -> ShortcutEntry in
                            var entry = textEntry(km, label: pair.0, badge: pair.1)
                            entry.font = f
                            return entry
                        } + [tog]
        )

        return [p0, lock ? p1Locked : p1Unlocked, p2]
    }
}
