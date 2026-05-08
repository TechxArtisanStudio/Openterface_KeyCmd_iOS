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
    // Function keys row (F1-F12)
    let functionKeys = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]

    // Legacy flat keys for landscape fallback (F-row removed)
    let keys: [[String]] = [
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    // Legacy keys for 101-key extra panel
    let extraKeys: [[String?]] = [
        ["PrtSc", "Scroll Lock", "Pause"],
        ["Insert", "Home", "PgUp"],
        ["Delete", "End", "PgDn"],
        [nil, nil, "↑", nil, nil],
        [nil, "←", "↓", "→", nil]
    ]

    // Extra number keys for portrait keyboard-only mode
    let extraNumberKeys: [String] = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0", "."]

    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var compositeKeyManager: CompositeKeyManager
    @ObservedObject var orientationManager: OrientationManager

    // Pointer tip overlay state
    @StateObject private var pointerTipState = PointerTipState()

    // Alternates popup state
    @State private var alternatesPopup: (options: [AlternateOption], anchor: CGRect, keyDef: KeyboardManager.KeyDef)? = nil
    /// Tracks whether the current touch was resolved by the alternates popup.
    /// Prevents the Button action from also sending the original key (matches Android ACTION_UP behavior).
    @State private var alternatesCommitHandled = false

    // Track if a key press is currently in progress to prevent multiple triggers
    @State private var keyPressInProgress = false
    
    // Track long press timer for alternates popup
    @State private var longPressTimer: Timer?
    
    // Track which key is currently being pressed (for visual feedback)
    @State private var currentlyPressedKey: String?

    // Key repeat controller
    @State private var keyRepeatController = KeyRepeatController()

    // Shortcut panel state
    @State private var shortcutPage = 0
    
    // Text input mode state
    @State private var isTextInputMode = false
    @State private var textInputContent = ""
    @State private var savedTextInputContent = ""
    @State private var isTextInputExpanded = false
    
    // Keyboard height for avoiding keyboard obstruction
    @State private var keyboardHeight: CGFloat = 0

    // Symbol mode layout keys
    let symbolKeysPortrait: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["@", "#", "$", "_", "&", "-", "+", "(", ")", "/"],
        ["=", "*", "\"", "'", ":", ";", "!", "?", "Backspace"],
        ["ABC", ",", "12/34", "Space", ".", "=", "Enter"]
    ]

    // Symbol mode landscape keys (operator column + number grid)
    let symbolKeysLandscape: [[String]] = [
        ["+", "1", "2", "3", "%"],
        ["-", "4", "5", "6", "Space"],
        ["*", "7", "8", "9", "Backspace"],
        ["/", "ABC", ",", "!?#", "0", "=", ".", "Enter"]
    ]

    /// Shortcut pages: Standard default panel first, then user favorited shortcuts from profiles.
    private var shortcutPages: [ShortcutPage] {
        var pages: [ShortcutPage] = []
        let pageSize = 14 // 7 columns × 2 rows
        let profileMgr = ShortcutProfileManager.shared

        // 1. "Standard" default panel — always shown, matching Android buildStandardTopPanelKeys()
        let isMacOS = UserDefaults.standard.string(forKey: "target_os") ?? "macos" == "macos"
        let primaryModifier = isMacOS ? "Cmd" : "Ctrl"
        let combo = { (mods: [String], key: String) in
            self.keyboardManager.handleKeyCombo(modifiers: mods, key: key)
        }
        let standardEntries: [ShortcutEntry] = [
            ShortcutEntry(label: "ALL", icon: "text.badge.checkmark") { combo([primaryModifier], "A") },
            ShortcutEntry(label: "COPY", icon: "doc.on.doc") { combo([primaryModifier], "C") },
            ShortcutEntry(label: "CUT", icon: "scissors") { combo([primaryModifier], "X") },
            ShortcutEntry(label: "PASTE", icon: "clipboard") { combo([primaryModifier], "V") },
            ShortcutEntry(label: "SAVE", icon: "externaldrive") { combo([primaryModifier], "S") },
            ShortcutEntry(label: "UP", icon: "arrow.up") { self.keyboardManager.handleKeyPress("Up") },
            ShortcutEntry(label: "UNDO", icon: "arrow.uturn.backward") { combo([primaryModifier], "Z") },
            ShortcutEntry(label: "ESC", icon: nil) { self.keyboardManager.handleKeyPress("Escape") },
            ShortcutEntry(label: "CTRL", icon: nil) { self.keyboardManager.handleModifierToggle("Ctrl") },
            ShortcutEntry(label: "ALT", icon: nil) { self.keyboardManager.handleModifierToggle("Alt") },
            ShortcutEntry(label: "TAB", icon: "arrow.right.to.line.compact") { self.keyboardManager.handleKeyPress("Tab") },
            ShortcutEntry(label: "LEFT", icon: "arrow.left") { self.keyboardManager.handleKeyPress("Left") },
            ShortcutEntry(label: "DOWN", icon: "arrow.down") { self.keyboardManager.handleKeyPress("Down") },
            ShortcutEntry(label: "RIGHT", icon: "arrow.right") { self.keyboardManager.handleKeyPress("Right") },
        ]
        pages.append(ShortcutPage(title: "Standard", entries: standardEntries))

        // 2. User favorited shortcuts from profiles
        for profile in profileMgr.allProfiles {
            let myShortcuts = profileMgr.myShortcuts(for: profile.id)
            if myShortcuts.isEmpty { continue }

            let entries = myShortcuts.map { item -> ShortcutEntry in
                let mods = (item.modifier ?? "").split(separator: "+").map(String.init)
                return ShortcutEntry(
                    label: String(item.description.prefix(8)),
                    icon: nil
                ) {
                    if mods.isEmpty {
                        self.keyboardManager.handleSpecialKey(item.keyCode)
                    } else {
                        self.keyboardManager.handleKeyCombo(modifiers: mods, key: item.keyCode)
                    }
                }
            }

            let chunked = stride(from: 0, to: entries.count, by: pageSize).map {
                Array(entries[$0..<min($0 + pageSize, entries.count)])
            }

            for (pageIdx, pageEntries) in chunked.enumerated() {
                let title = chunked.count > 1
                    ? "\(profile.name) \(pageIdx + 1)/\(chunked.count)"
                    : profile.name
                pages.append(ShortcutPage(title: title, entries: pageEntries))
            }
        }

        return pages
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

    // Compute the display value for each key based on current modifiers
    func getDisplayValue(for key: String) -> String {
        let specialKeys = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
                          "Tab", "Caps", "Enter", "Shift", "Ctrl", "Alt", "Space", "Backspace"]

        if specialKeys.contains(key) {
            return key
        }

        let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
        let isCapsActive = keyboardManager.capsLockActive

        if key.count == 1 && key.first!.isLetter {
            let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
            return shouldBeUppercase ? key.uppercased() : key.lowercased()
        }

        if isShiftActive {
            let shiftMap: [String: String] = [
                "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
                "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
                "-": "_", "=": "+", "[": "{", "]": "}",
                ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
            ]
            return shiftMap[key] ?? key
        }

        return key
    }

    /// Get display label for a KeyDef, respecting Shift/Caps/Fn state.
    func displayLabel(for kd: KeyboardManager.KeyDef) -> String {
        // Fn lock: show F1-F12
        if let fnKey = keyboardManager.resolveFnKey(kd.label) {
            return fnKey
        }
        // Symbol mode: show symbolLabel if available
        if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty {
            return kd.symbolLabel
        }
        // Normal letter key
        if kd.label.count == 1 && kd.label.first!.isLetter {
            let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
            let isCapsActive = keyboardManager.capsLockActive
            let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
            return shouldBeUppercase ? kd.label.uppercased() : kd.label.lowercased()
        }
        return kd.label
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    // Conditional layout based on orientation
                    if orientationManager.isLandscape {
                    if displayMode == .touchpad {
                        // Touchpad only mode: occupy all screen area, but show toggle button and tips overlay
                        ZStack {
                            TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Rectangle()
                                .foregroundColor(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
                                .allowsHitTesting(false)
                            // Toggle button (handle) at the top edge, horizontally centered
                            VStack {
                                Button(action: { displayMode.toggle() }) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(UIColor.secondarySystemBackground))
                                        .frame(width: 48, height: 24)
                                        .overlay(
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.6))
                                                .frame(width: 36, height: 3)
                                                .cornerRadius(1.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            // Overlay: Text at the bottom
                            VStack {
                                Spacer()
                                VStack(spacing: 4) {
                                    Text("Touch Pad")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Openterface")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                .padding(.bottom, 8)
                            }
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HStack(spacing: 0) {
                            if displayMode != .keyboard {
                                // Touchpad area (30% of width)
                                VStack(spacing: 0) {
                                    ZStack {
                                        Rectangle()
                                            .foregroundColor(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
                                        
                                        TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState)
                                        
                                        VStack {
                                            Spacer()
                                            VStack(spacing: 4) {
                                                Text("Touch Pad")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text("Openterface")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary.opacity(0.7))
                                            }
                                            .padding(.bottom, 8)
                                        }
                                        .allowsHitTesting(false)
                                        .zIndex(1)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .frame(maxWidth: geometry.size.width * 0.3)
                            }
                            // Handle removed to save space
                            // VStack {
                            //     Spacer()
                            //     Button(action: { displayMode.toggle() }) {
                            //         RoundedRectangle(cornerRadius: 8)
                            //             .fill(Color(UIColor.secondarySystemBackground))
                            //             .frame(width: 20, height: 48)
                            //             .overlay(
                            //                 Rectangle()
                            //                     .fill(Color.gray.opacity(0.6))
                            //                     .frame(width: 3, height: 36)
                            //                     .cornerRadius(1.5)
                            //             )
                            //             .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                            //     }
                            //     .buttonStyle(PlainButtonStyle())
                            //     Spacer(minLength: 2)
                            // }
                            // .frame(width: 36)
                            if displayMode != .touchpad {
                                HStack(spacing: 0) {
                                    // Add black space for camera area only on the top side in landscape keyboard-only mode
                                    if displayMode == .keyboard && orientationManager.isLandscape && isTopOnLeft {
                                        Color.black.frame(width: 60)
                                    }
                                    VStack(spacing: 0) {
                                        // In landscape keyboard-only mode, make the keyboard rows fill all available vertical space
                                        if displayMode == .keyboard && orientationManager.isLandscape {
                                            GeometryReader { innerGeometry in
                                                VStack(spacing: 0) {
                                                    ForEach(keysForCurrentOrientation, id: \.self) { row in
                                                        HStack(spacing: 0) {
                                                            ForEach(row, id: \.self) { key in
                                                                Button(action: {
                                                                    keyboardManager.handleSpecialKey(key)
                                                                }) {
                                                                    if key == "Backspace" {
                                                                        Image(systemName: "delete.left")
                                                                            .font(.system(size: 16))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(Self.functionKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(.primary)
                                                                    } else if key == "Enter" {
                                                                        Image(systemName: "return")
                                                                            .font(.system(size: 16))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(Self.functionKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(.primary)
                                                                    } else if key == "Shift" {
                                                                        Image(systemName: "shift")
                                                                            .font(.system(size: 16))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.activeModifiers.contains("Shift") ? Color.blue : Self.functionKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(keyboardManager.activeModifiers.contains("Shift") ? .white : .primary)
                                                                    } else if ["Ctrl", "Alt", "Cmd"].contains(key) {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.activeModifiers.contains(key) ? Color.blue : Self.functionKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(keyboardManager.activeModifiers.contains(key) ? .white : .primary)
                                                                    } else if key == "Caps" {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.capsLockActive ? Color.green : Self.functionKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(keyboardManager.capsLockActive ? .white : .primary)
                                                                    } else {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(Self.regularKeyBg)
                                                                            .cornerRadius(9)
                                                                            .foregroundColor(.primary)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        .frame(maxHeight: innerGeometry.size.height / CGFloat(keysForCurrentOrientation.count))
                                                    }
                                                }
                                            }
                                        } else {
                                            keyboardLayoutView
                                        }
                                        // Show extra keys only in keyboard-only mode and only in portrait
                                        if displayMode == .keyboard && !orientationManager.isLandscape {
                                            extraKeysView
                                                .padding(.top, 4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    if displayMode == .keyboard && orientationManager.isLandscape && isTopOnRight {
                                        Color.black.frame(width: 60)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ZStack {
                        VStack(spacing: 0) {
                            if displayMode != .keyboard {
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
                                    
                                    TouchpadView(mouseManager: mouseManager, pointerTipState: pointerTipState)
                                    
                                    VStack {
                                        Spacer()
                                        VStack(spacing: 4) {
                                            Text("Touch Pad")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("Openterface")
                                                .font(.caption2)
                                                .foregroundColor(.secondary.opacity(0.7))
                                        }
                                        .padding(.bottom, 8)
                                    }
                                    .allowsHitTesting(false)
                                    .zIndex(1)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(isTextInputMode && isTextInputExpanded ? 0 : 1)
                            }
                            // Handle removed to save space
                            // HStack {
                            //     Spacer()
                            //     // Portrait handle
                            //     Button(action: { displayMode.toggle() }) {
                            //         RoundedRectangle(cornerRadius: 6)
                            //             .fill(Color(UIColor.secondarySystemBackground))
                            //             .frame(width: 48, height: 20)
                            //             .overlay(
                            //                 Rectangle()
                            //                     .fill(Color.gray.opacity(0.6))
                            //                     .frame(width: 36, height: 3)
                            //                     .cornerRadius(1.5)
                            //             )
                            //             .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                            //     }
                            //     .buttonStyle(PlainButtonStyle())
                            //     Spacer()
                            // }
                            // .frame(height: 36)
                            if displayMode != .touchpad {
                                if isTextInputMode && !isTextInputExpanded {
                                    // Text input mode with ScrollView for keyboard avoidance
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            // Swipeable shortcut panels
                                            if !shortcutPages.isEmpty {
                                                ShortcutPanelPager(pages: shortcutPages)
                                                    .padding(.horizontal, 4)
                                                    .padding(.top, 4)
                                                    .padding(.bottom, 2)
                                            }
                                            
                                            textInputView
                                                .frame(height: 140)
                                                .padding(.bottom, 10)
                                            
                                            // Bottom toolbar
                                            bottomToolbar
                                                .padding(.horizontal, 4)
                                                .padding(.bottom, 4)
                                        }
                                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
                                    }
                            } else if !isTextInputMode {
                                // Keyboard mode
                                // Swipeable shortcut panels
                                if !shortcutPages.isEmpty {
                                    ShortcutPanelPager(pages: shortcutPages)
                                        .padding(.horizontal, 4)
                                        .padding(.top, 4)
                                        .padding(.bottom, 2)
                                }

                                // Keyboard layout
                                keyboardLayoutView
                                    .frame(height: 240)
                                    .padding(.bottom, 10)
                                // Show extra keys only in keyboard-only mode and only in portrait
                                if displayMode == .keyboard && !orientationManager.isLandscape {
                                    extraKeysView
                                        .padding(.top, 8)
                                }
                                
                                // Bottom toolbar
                                bottomToolbar
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    
                    // Expanded text input overlay
                    if isTextInputMode && isTextInputExpanded {
                        VStack(spacing: 8) {
                            textInputView
                                .frame(maxHeight: geometry.size.height * 0.50)
                            
                            bottomToolbar
                                .padding(.horizontal, 4)
                        }
                        .padding(.top, 90)  // Increased from 10 to 80 to move down by two button heights
                        .padding(.bottom, 30)
                        .padding(.horizontal, 8)
                        .background(Color(UIColor.systemBackground))
                        .zIndex(10)
                    }
                }
                // Alternates popup overlay (3x3 grid)
                if let popup = alternatesPopup {
                    KeyAlternatesPopupView(
                        options: popup.options,
                        anchorFrame: popup.anchor,
                        onCommit: { option in
                            alternatesCommitHandled = true
                            HapticFeedbackManager.shared.triggerButtonPress()
                            if option.requiresShift {
                                keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: option.keyCode)
                            } else {
                                keyboardManager.handleKeyPress(option.keyCode)
                            }
                            dismissAlternatesPopup()
                        },
                        onCancel: {
                            // Cancelled — let the Button action send the normal key
                            alternatesCommitHandled = false
                            dismissAlternatesPopup()
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
            }
            }
            .offset(y: isTextInputMode ? (keyboardHeight > 0 ? -keyboardHeight * 0.65 : 30) : 0)
            .animation(.easeOut(duration: 0.3), value: keyboardHeight)
            .animation(.easeOut(duration: 0.3), value: isTextInputMode)
            .onAppear {
                // Listen for keyboard show/hide notifications
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillShowNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                        keyboardHeight = keyboardFrame.height
                    }
                }
                
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    keyboardHeight = 0
                }
            }
            .onDisappear {
                // Clean up notification observers
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
            }
        }
    }

    // Helper to determine if the top is on the left or right in landscape
    private var isTopOnLeft: Bool {
        guard orientationManager.isLandscape else { return false }
        let deviceOrientation = UIDevice.current.orientation
        return deviceOrientation == .landscapeLeft
    }
    private var isTopOnRight: Bool {
        guard orientationManager.isLandscape else { return false }
        let deviceOrientation = UIDevice.current.orientation
        return deviceOrientation == .landscapeRight
    }

    // Helper: in landscape F-row is hidden, but since our keys no longer include F-row, return as-is
    var keysForCurrentOrientation: [[String]] {
        return keys
    }

    @ViewBuilder
    private var keyboardLayoutView: some View {
        VStack(spacing: 0) {
            // F-row (hidden in landscape, matches Android)
            if !orientationManager.isLandscape {
                functionKeyRow
            }
            // Letter/symbol keys from portraitLetterKeys
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

    /// F1-F12 row (hidden in landscape, matching Android)
    private var functionKeyRow: some View {
        HStack(spacing: 0) {
            ForEach(functionKeys, id: \.self) { key in
                Button(action: { keyboardManager.handleSpecialKey(key) }) {
                    Text(key)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, maxHeight: 36)
                        .background(Self.functionKeyBg)
                        .cornerRadius(9)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 1)
    }

    /// Width proportion for a key in its row, matching Android android:keyWidth percentages.
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
        let isCapsActive = kd.label == "Caps" && keyboardManager.capsLockActive
        let isFnActive = kd.label == "Fn" && keyboardManager.isFnLocked

        keyContent(for: kd, displayText: displayText)
            .frame(maxWidth: .infinity, maxHeight: 48)
            .background(keyBackground(for: kd, pressed: isPressed, active: isCapsActive || isFnActive))
            .cornerRadius(9)
            .foregroundColor(isPressed || isCapsActive || isFnActive ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                cornerHint(for: kd),
                alignment: .topTrailing
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Only trigger action once when touch begins
                        if !keyPressInProgress {
                            keyPressInProgress = true
                            currentlyPressedKey = kd.label
                            handleKeyPress(kd)
                            
                            // Start timer for long press (alternates popup after 0.4s)
                            if keyboardManager.shouldShowAlternates(for: kd.label) {
                                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                                    showAlternatesPopup(for: kd)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        // Cancel long press timer
                        longPressTimer?.invalidate()
                        longPressTimer = nil
                        
                        keyPressInProgress = false
                        currentlyPressedKey = nil
                        handleKeyRelease()
                    }
            )
    }
    
    /// Unified handler for key press - handles both single tap and long press
    private func handleKeyPress(_ kd: KeyboardManager.KeyDef) {
        // If the alternates popup was committed for this touch, skip normal key action
        if alternatesCommitHandled {
            alternatesCommitHandled = false
            return
        }

        HapticFeedbackManager.shared.triggerButtonPress()

        // Fn toggle
        if kd.label == "Fn" {
            keyboardManager.isFnLocked.toggle()
            return
        }
        // Symbol mode toggle
        if kd.label == "ABC" || kd.label == "12/34" {
            keyboardManager.isSymbolMode.toggle()
            return
        }
        if kd.label == "!?#" {
            keyboardManager.isSymbolMode = true
            return
        }
        // Modifiers
        if ["Ctrl", "Alt", "Cmd", "Win", "Shift"].contains(kd.label) {
            keyboardManager.handleSpecialKey(kd.label)
            return
        }
        
        // Fn-resolved key
        let effectiveKey = keyboardManager.resolveFnKey(kd.keyCode) ?? kd.keyCode
        
        // For repeatable keys (arrows, backspace): execute once immediately, then start repeat timer
        if KeyRepeatController.repeatableKeys.contains(effectiveKey) {
            // Execute immediately for single tap
            keyboardManager.handleSpecialKey(effectiveKey)
            // Start repeat controller for long press (will repeat after 0.4s)
            keyRepeatController.startRepeating(keyAction: {
                keyboardManager.handleSpecialKey(effectiveKey)
            })
        } else {
            // For normal keys: just execute once
            keyRepeatController.stopRepeating()
            keyboardManager.handleSpecialKey(effectiveKey)
        }
    }

    @ViewBuilder
    private func keyContent(for kd: KeyboardManager.KeyDef, displayText: String) -> some View {
        if kd.label == "Backspace" {
            Image(systemName: "delete.left")
                .font(.system(size: 16))
                .rotationEffect(kd.symbolLabel.isEmpty && keyboardManager.activeModifiers.contains("Shift") ? .degrees(180) : .degrees(0))
        } else if kd.label == "Enter" {
            Image(systemName: "return")
                .font(.system(size: 16))
        } else if kd.label == "Shift" {
            Image(systemName: "shift")
                .font(.system(size: 16))
        } else if ["Ctrl", "Alt", "Cmd"].contains(kd.label) {
            Text(getDisplayValue(for: kd.label))
                .font(.system(size: 12))
        } else if kd.label == "Caps" {
            Text("Caps")
                .font(.system(size: 11))
        } else if kd.label == "Fn" {
            Text("Fn")
                .font(.system(size: 12, weight: .bold))
        } else if kd.label == "Cmd" {
            // Target OS label: show Cmd/Win/Super based on settings
            let targetOs = UserDefaults.standard.string(forKey: "target_os") ?? "macos"
            switch targetOs {
            case "windows": Text("Win").font(.system(size: 12))
            case "linux": Text("Super").font(.system(size: 10))
            default: Text("Cmd").font(.system(size: 12))
            }
        } else if keyboardManager.isSymbolMode && !kd.symbolLabel.isEmpty {
            Text(kd.symbolLabel)
                .font(.system(size: 14))
        } else {
            Text(displayText)
                .font(.system(size: 12))
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
        VStack(spacing: 4) {
            ForEach(0..<extraKeys.count, id: \.self) { rowIndex in
                HStack(spacing: 4) {
                    ForEach(0..<extraKeys[rowIndex].count, id: \.self) { colIndex in
                        if let key = extraKeys[rowIndex][colIndex] {
                            Button(action: {
                                let mappedKey: String
                                switch key {
                                case "↑": mappedKey = "Up"
                                case "↓": mappedKey = "Down"
                                case "←": mappedKey = "Left"
                                case "→": mappedKey = "Right"
                                default: mappedKey = key
                                }
                                keyboardManager.handleSpecialKey(mappedKey)
                            }) {
                                Text(key)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(Self.functionKeyBg)
                                    .cornerRadius(9)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            Spacer()
                        }
                    }
                }
            }
            // Number pad in portrait keyboard-only mode
            if displayMode == .keyboard && !orientationManager.isLandscape {
                numberPadView
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var numberPadView: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in
                        let key = extraNumberKeys[row * 3 + col]
                        numberPadButton(key: key)
                    }
                }
            }
            HStack(spacing: 3) {
                numberPadButton(key: "0", width: 2)
                numberPadButton(key: ".")
            }
        }
    }

    private func numberPadButton(key: String, width: Int = 1) -> some View {
        Button(action: {
            let mappedKey: String
            switch key {
            case "0": mappedKey = "Numpad0"
            case ".": mappedKey = "NumpadDot"
            default: mappedKey = "Numpad\(key)"
            }
            keyboardManager.handleSpecialKey(mappedKey)
        }) {
            Text(key)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Self.functionKeyBg)
                .cornerRadius(9)
                .foregroundColor(.primary)
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

        // Center slot: key label itself (capital for a-z)
        if let centerOpt = centerAlternateOption(for: kd), !seen.contains(centerOpt.display) {
            slotMap[AlternatePopupGeometry.slotCenter] = centerOpt
            seen.insert(centerOpt.display)
        }

        // Cardinal slots from alternates: Up, Down, Left, Right (tokens 0-3)
        let cardinalSlots = [
            AlternatePopupGeometry.slotUp,
            AlternatePopupGeometry.slotDown,
            AlternatePopupGeometry.slotLeft,
            AlternatePopupGeometry.slotRight,
        ]
        for (i, slot) in cardinalSlots.enumerated() where i < kd.alternates.count {
            let alt = kd.alternates[i]
            if let mapped = mapAsciiAlternate(alt), !seen.contains(mapped.display) {
                slotMap[slot] = AlternateOption(
                    display: mapped.display, keyCode: mapped.keyCode, requiresShift: mapped.requiresShift, slot: slot
                )
                seen.insert(mapped.display)
            }
        }

        // Corner slots from alternates: UL, UR, DL, DR (tokens 4-7)
        let cornerSlots = [
            AlternatePopupGeometry.slotUpLeft,
            AlternatePopupGeometry.slotUpRight,
            AlternatePopupGeometry.slotDownLeft,
            AlternatePopupGeometry.slotDownRight,
        ]
        for (i, slot) in cornerSlots.enumerated() where (i + 4) < kd.alternates.count {
            let alt = kd.alternates[i + 4]
            if let mapped = mapAsciiAlternate(alt), !seen.contains(mapped.display) {
                slotMap[slot] = AlternateOption(
                    display: mapped.display, keyCode: mapped.keyCode, requiresShift: mapped.requiresShift, slot: slot
                )
                seen.insert(mapped.display)
            }
        }

        let options = Array(slotMap.values)
        guard options.count >= 2 else { return }
        alternatesPopup = (options, CGRect.zero, kd)
    }

    /// Build the center (default) option for a key.
    private func centerAlternateOption(for kd: KeyboardManager.KeyDef) -> AlternateOption? {
        // For a-z keys, center = uppercase letter
        if kd.label.count == 1, let c = kd.label.first, c.isLetter {
            let display = kd.label.uppercased()
            return AlternateOption(display: display, keyCode: kd.label, requiresShift: true, slot: AlternatePopupGeometry.slotCenter)
        }
        // Otherwise use the base key label
        if let mapped = mapAsciiAlternate(kd.label) {
            return AlternateOption(display: mapped.display, keyCode: mapped.keyCode, requiresShift: mapped.requiresShift, slot: AlternatePopupGeometry.slotCenter)
        }
        return nil
    }

    private func mapAsciiAlternate(_ char: String) -> (display: String, keyCode: String, requiresShift: Bool)? {
        switch char {
        case "a"..."z": return (char, char, false)
        case "A"..."Z": return (char, char.lowercased(), true)
        case "1": return ("1", "1", false); case "!": return ("!", "1", true)
        case "2": return ("2", "2", false); case "@": return ("@", "2", true)
        case "3": return ("3", "3", false); case "#": return ("#", "3", true)
        case "4": return ("4", "4", false); case "$": return ("$", "4", true)
        case "5": return ("5", "5", false); case "%": return ("%", "5", true)
        case "6": return ("6", "6", false); case "^": return ("^", "6", true)
        case "7": return ("7", "7", false); case "&": return ("&", "7", true)
        case "8": return ("8", "8", false); case "*": return ("*", "8", true)
        case "9": return ("9", "9", false); case "(": return ("(", "9", true)
        case "0": return ("0", "0", false); case ")": return (")", "0", true)
        case "-": return ("-", "-", false); case "_": return ("_", "-", true)
        case "=": return ("=", "=", false); case "+": return ("+", "=", true)
        case "[": return ("[", "[", false); case "{": return ("{", "[", true)
        case "]": return ("]", "]", false); case "}": return ("}", "]", true)
        case ",": return (",", ",", false); case "<": return ("<", ",", true)
        case ".": return (".", ".", false); case ">": return (">", ".", true)
        case "/": return ("/", "/", false); case "?": return ("?", "/", true)
        case ";": return (";", ";", false); case ":": return (":", ";", true)
        case "'": return ("'", "'", false); case "\"": return ("\"", "'", true)
        case "`": return ("`", "`", false); case "~": return ("~", "`", true)
        default: return nil
        }
    }

    private func commitAlternatesSelection() {
        // Selection is now handled by KeyAlternatesPopupView's onCommit
    }

    private func dismissAlternatesPopup() {
        alternatesPopup = nil
    }
    
    // MARK: - Text Input View
    
    /// Text input area with placeholder and send functionality
    private var textInputView: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $textInputContent)
                    .font(.system(size: 14))
                    .padding(8)
                    .padding(.trailing, 40)  // Make space for expand button
                    .padding(.bottom, 40)  // Make space for expand button
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.separator), lineWidth: 1)
                    )
                
                if textInputContent.isEmpty {
                    Text("Type and edit long text here - tap Send to send it to the connected device")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                
                // Expand button at bottom-right corner
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                isTextInputExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isTextInputExpanded ? "chevron.down" : "chevron.up")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(6)
                        }
                        .padding(8)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    /// Bottom toolbar with mode switch, restore, and clear buttons
    private var bottomToolbar: some View {
        HStack(spacing: 4) {
            // Switch mode button
            Button(action: {
                withAnimation {
                    isTextInputMode.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isTextInputMode ? "keyboard" : "text.alignleft")
                        .font(.system(size: 12))
                    Text(isTextInputMode ? "Key" : "Text")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(6)
            }
            
            // Restore button
            Button(action: {
                textInputContent = savedTextInputContent
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                    Text("Restore")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(6)
            }
            .disabled(savedTextInputContent.isEmpty)
            
            // Clear button
            Button(action: {
                savedTextInputContent = textInputContent
                textInputContent = ""
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(6)
            }
            .disabled(textInputContent.isEmpty)
            
            Spacer()
            
            // Send button
            Button(action: {
                sendTextToDevice()
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                    Text("Send")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(textInputContent.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(6)
            }
            .disabled(textInputContent.isEmpty)
        }
    }
    
    /// Send text content to the connected device
    private func sendTextToDevice() {
        guard !textInputContent.isEmpty else { return }
        
        // Save current content before sending
        savedTextInputContent = textInputContent
        
        // Send each character to the keyboard manager with delay
        let characters = Array(textInputContent)
        for (index, char) in characters.enumerated() {
            // Use delay to ensure each character is properly sent and released
            // KeyboardManager releases keys after 0.1s, so we need at least 0.12s between characters
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                let charString = String(char)
                if char.isNewline {
                    self.keyboardManager.handleKeyPress("Enter")
                } else {
                    self.keyboardManager.handleKeyPress(charString)
                }
            }
        }
        
        // Clear the input after all characters are queued for sending
        textInputContent = ""
        
        // Show feedback
        HapticFeedbackManager.shared.triggerButtonPress()
    }
}
