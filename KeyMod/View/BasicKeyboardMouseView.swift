//
//  BasicKeyboardMouseView.swift
//  KeyMod
//
//  Tabbed submode view matching Android's KM Basic (fragment_keyboard_mouse.xml):
//  Keyboard | Touchpad | Numpad tabs with a horizontal scrollable tab bar.

import SwiftUI

struct BasicKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager
    @Binding var selectedSubmode: Submode
    @ObservedObject private var aiSettings = AISettings.shared

    enum Submode: String, CaseIterable {
        case keyboard = "Keyboard"
        case touchpad = "Touchpad"
        case numpad = "Numpad"
    }

    init(mouseManager: MouseManager, keyboardManager: KeyboardManager, orientationManager: OrientationManager, selectedSubmode: Binding<Submode>) {
        self.mouseManager = mouseManager
        self.keyboardManager = keyboardManager
        self.orientationManager = orientationManager
        self._selectedSubmode = selectedSubmode
    }

    // Landscape keyboard rows matching Android keyboard_lower_landscape.xml
    let landscapeKeys: [[String]] = [
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    // Windows-style layout rows
    let windowsFRow: [String] = [
        "Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]
    let windowsNumberRow: [String] = [
        "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"
    ]
    let windowsRow3: [String] = [
        "Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "\\"
    ]
    let windowsRow4: [String] = [
        "Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"
    ]
    let windowsRow5: [String] = [
        "Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"
    ]
    let windowsRow6: [String] = [
        "Ctrl", "Win", "Alt", "Space", "Alt", "Ctrl", "Left", "Down", "Right"
    ]

    // Mac-specific bottom row
    let macRow6: [String] = [
        "Ctrl", "Option", "Cmd", "Space", "Cmd", "Option"
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Tab bar only in portrait — in landscape it moves to ContentView's top bar
                if !orientationManager.isLandscape {
                    tabBar
                }

                // MARK: - Submode content
                Group {
                    switch selectedSubmode {
                    case .keyboard:
                        landscapeKeyboardSubmode
                    case .touchpad:
                        touchpadSubmode
                    case .numpad:
                        numpadSubmode
                    }
                }
                .id(selectedSubmode.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: selectedSubmode) { newSubmode in
                    if newSubmode == .keyboard {
                        lockToLandscape()
                    } else {
                        unlockOrientation()
                    }
                }
            }
            .padding(.leading, orientationManager.isLandscape ? max(geometry.safeAreaInsets.leading, 45) : 0)
            .onAppear {
                if selectedSubmode == .keyboard { lockToLandscape() }
            }
            .onDisappear {
                unlockOrientation()
            }
            // Snap back to landscape if user physically tilts device while on keyboard tab
            .onChange(of: orientationManager.isLandscape) { isLandscape in
                if !isLandscape && selectedSubmode == .keyboard {
                    guard !OrientationManager.launchPanelVisible else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        lockToLandscape()
                    }
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Submode.allCases, id: \.self) { submode in
                    tabButton(for: submode)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 36)
        .background(Color(UIColor.secondarySystemBackground))
    }

    /// Tab bar variant for landscape top bar (compact, inline with title)
    var landscapeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Submode.allCases, id: \.self) { submode in
                    landscapeTabButton(for: submode)
                }
            }
        }
    }

    private func tabButton(for submode: Submode) -> some View {
        let isSelected = selectedSubmode == submode
        return Button(action: { withAnimation { selectedSubmode = submode } }) {
            Text(submode.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .blue : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func landscapeTabButton(for submode: Submode) -> some View {
        let isSelected = selectedSubmode == submode
        return Button(action: { withAnimation { selectedSubmode = submode } }) {
            Text(submode.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .blue : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Landscape Keyboard Submode

    private var isWindowsTarget: Bool { aiSettings.targetOS == .windows }

    private var landscapeKeyboardSubmode: some View {
        GeometryReader { innerGeometry in
            ZStack {
                Color.red.opacity(0.05)
                switch aiSettings.targetOS {
                case .windows:
                    windowsKeyboardLayout
                case .linux:
                    linuxKeyboardLayout
                default:
                    macKeyboardLayout
                }
            }
            .coordinateSpace(name: "keyboardLayout")
            .overlayPreferenceValue(KeyCalloutInfoKey.self) { info in
                if let info = info {
                    Text(info.text)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.82)))
                        .position(x: info.frame.midX,
                                  y: info.below ? info.frame.maxY + 36 : info.frame.minY - 36)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                print("🔴 LANDSCAPE KEYBOARD APPEARED — \(innerGeometry.size.width)x\(innerGeometry.size.height)")
                lockToLandscape()
            }
            // NOTE: No .onDisappear here — it fires during rotation and would unlock prematurely.
            // Unlock is handled by the outer VStack's .onDisappear and onChange(selectedSubmode).
        }
    }

    private func lockToLandscape() {
        guard !OrientationManager.launchPanelVisible else { return }
        // 1. Tell AppDelegate to deny portrait from now on
        AppDelegate.orientationLock = .landscape
        // 2. Force rotation to landscape unconditionally — same pattern as OrientationManager.lockToPortrait()
        //    (requestGeometryUpdate only calls its closure on error, so we cannot rely on it to force rotation)
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
            }
        }
    }

    private func unlockOrientation() {
        AppDelegate.orientationLock = .all
        // Reset forced orientation value so the system re-reads the physical sensor
        UIDevice.current.setValue(UIInterfaceOrientation.unknown.rawValue, forKey: "orientation")
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { _ in }
            }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private var linuxKeyboardLayout: some View {
        VStack(spacing: 1) {
            // Row 1: Esc + F1-F12
            HStack(spacing: 1) {
                ForEach(windowsFRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsFRow[idx], height: 36)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 38)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            // Row 3: Tab q w e r t y u i o p [ ] \
            HStack(spacing: 1) {
                ForEach(windowsRow3.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow3[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 4: Caps a s d f g h j k l ; ' Enter
            HStack(spacing: 1) {
                ForEach(windowsRow4.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow4[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 5: Shift z x c v b n m , . / Shift
            HStack(spacing: 1) {
                ForEach(windowsRow5.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow5[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 6: Ctrl Super Alt Space Alt Ctrl + inverted-T arrow cluster
            HStack(alignment: .center, spacing: 1) {
                windowsBottomKey("Ctrl")
                windowsBottomKey("Super")
                windowsBottomKey("Alt")
                // Space key — wide
                KeyPressButton(
                    onPress: { keyboardManager.handleKeyDown("Space") },
                    onRelease: { keyboardManager.handleKeyUp("Space") },
                    keyPreview: "Space"
                ) { isActive in
                    Text("Openterface")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 150)
                        .frame(maxHeight: .infinity)
                        .background(Self.functionKeyBg)
                        .cornerRadius(6)
                        .foregroundColor(isActive ? .white : .primary)
                }
                windowsBottomKey("Alt")
                windowsBottomKey("Ctrl")
                Spacer()
                // Inverted-T: ↑ centered on top, ← ↓ → on bottom
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        Color.clear.frame(width: 58, height: 38)
                        arrowButton("Up", image: "arrow.up", height: 38)
                        Color.clear.frame(width: 58, height: 38)
                    }
                    HStack(spacing: 1) {
                        arrowButton("Left", image: "arrow.left", height: 38)
                        arrowButton("Down", image: "arrow.down", height: 38)
                        arrowButton("Right", image: "arrow.right", height: 38)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 80)
            .padding(.horizontal, 2)
        }
    }

    private var macKeyboardLayout: some View {
        VStack(spacing: 1) {
            // Row 1: Esc + F1-F12
            HStack(spacing: 1) {
                ForEach(windowsFRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsFRow[idx], height: 36)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 38)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            // Row 3: Tab q w e r t y u i o p [ ] \
            HStack(spacing: 1) {
                ForEach(windowsRow3.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow3[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 4: Caps a s d f g h j k l ; ' Enter
            HStack(spacing: 1) {
                ForEach(windowsRow4.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow4[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 5: Shift z x c v b n m , . / Shift
            HStack(spacing: 1) {
                ForEach(windowsRow5.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow5[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 6: Ctrl Option Cmd Space Cmd Option + inverted-T arrow cluster
            HStack(alignment: .center, spacing: 1) {
                windowsBottomKey("Ctrl")
                windowsBottomKey("Option")
                windowsBottomKey("Cmd")
                // Space key — wide
                KeyPressButton(
                    onPress: { keyboardManager.handleKeyDown("Space") },
                    onRelease: { keyboardManager.handleKeyUp("Space") },
                    keyPreview: "Space"
                ) { isActive in
                    Text("Openterface")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 150)
                        .frame(maxHeight: .infinity)
                        .background(Self.functionKeyBg)
                        .cornerRadius(6)
                        .foregroundColor(isActive ? .white : .primary)
                }
                windowsBottomKey("Cmd")
                windowsBottomKey("Option")
                Spacer()
                // Inverted-T: ↑ centered on top, ← ↓ → on bottom
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        Color.clear.frame(width: 58, height: 38)
                        arrowButton("Up", image: "arrow.up", height: 38)
                        Color.clear.frame(width: 58, height: 38)
                    }
                    HStack(spacing: 1) {
                        arrowButton("Left", image: "arrow.left", height: 38)
                        arrowButton("Down", image: "arrow.down", height: 38)
                        arrowButton("Right", image: "arrow.right", height: 38)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 80)
            .padding(.horizontal, 2)
        }
    }

    private var originalKeyboardLayout: some View {
        VStack(spacing: 0) {
            ForEach(landscapeKeys.indices, id: \.self) { rowIdx in
                let row = landscapeKeys[rowIdx]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { colIdx in
                        landscapeKeyButton(key: row[colIdx], previewBelow: rowIdx < 2)
                    }
                }
            }
        }
    }

    private var windowsKeyboardLayout: some View {
        VStack(spacing: 1) {
            // Row 1: Esc + F1-F12
            HStack(spacing: 1) {
                ForEach(windowsFRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsFRow[idx], height: 36)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 38)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)

            // Row 3: Tab q w e r t y u i o p [ ] \
            HStack(spacing: 1) {
                ForEach(windowsRow3.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow3[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 4: Caps a s d f g h j k l ; ' Enter
            HStack(spacing: 1) {
                ForEach(windowsRow4.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow4[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 5: Shift z x c v b n m , . / Shift
            HStack(spacing: 1) {
                ForEach(windowsRow5.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsRow5[idx], height: 52)
                }
            }
            .padding(.horizontal, 2)

            // Row 6: Ctrl Win Alt Space Alt Ctrl + inverted-T arrow cluster
            HStack(alignment: .center, spacing: 1) {
                // Modifier keys — same width as regular keys
                windowsBottomKey("Ctrl")
                windowsBottomKey("Win")
                windowsBottomKey("Alt")
                // Space key — wide
                KeyPressButton(
                    onPress: { keyboardManager.handleKeyDown("Space") },
                    onRelease: { keyboardManager.handleKeyUp("Space") },
                    keyPreview: "Space"
                ) { isActive in
                    Text("Openterface")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 150)
                        .frame(maxHeight: .infinity)
                        .background(Self.functionKeyBg)
                        .cornerRadius(6)
                        .foregroundColor(isActive ? .white : .primary)
                }
                windowsBottomKey("Alt")
                windowsBottomKey("Ctrl")
                Spacer()
                // Inverted-T: ↑ centered on top, ← ↓ → on bottom
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        Color.clear.frame(width: 58, height: 38)
                        arrowButton("Up", image: "arrow.up", height: 38)
                        Color.clear.frame(width: 58, height: 38)
                    }
                    HStack(spacing: 1) {
                        arrowButton("Left", image: "arrow.left", height: 38)
                        arrowButton("Down", image: "arrow.down", height: 38)
                        arrowButton("Right", image: "arrow.right", height: 38)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 80)
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func windowsBottomKey(_ key: String) -> some View {
        let displayLabel: String = {
            switch key {
            case "Cmd": return "⌘"
            case "Option": return "⌥"
            case "Super": return "❖"
            default: return key
            }
        }()
        ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: displayLabel) { isPhysical, isLocked in
            Text(displayLabel)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isLocked ? Color.blue : (isPhysical ? Color.blue.opacity(0.6) : Self.functionKeyBg))
                .cornerRadius(6)
                .foregroundColor(isPhysical || isLocked ? .white : .primary)
        }
    }

    @ViewBuilder
    private func arrowButton(_ action: String, image: String, height: CGFloat = 52) -> some View {
        let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
        KeyPressButton(
            onPress: { repeatMode ? keyboardManager.startKeyRepeat(action) : keyboardManager.handleKeyDown(action) },
            onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(action) },
            keyPreview: action
        ) { isActive in
            Image(systemName: image)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 58, height: height)
                .background(isActive ? Color.blue : Self.functionKeyBg)
                .cornerRadius(6)
                .foregroundColor(isActive ? .white : .primary)
        }
    }

    @ViewBuilder
    private func windowsKeyVisual(key: String, displayText: String, isPressed: Bool) -> some View {
        let content: AnyView = {
            if key == "Backspace" {
                AnyView(Image(systemName: "delete.left").font(.system(size: 14)))
            } else if key == "Enter" {
                AnyView(Image(systemName: "return").font(.system(size: 14)))
            } else if key == "Shift" {
                AnyView(Image(systemName: "shift").font(.system(size: 14)))
            } else if key == "Tab" {
                AnyView(Image(systemName: "arrow.right.to.line.compact").font(.system(size: 11)))
            } else if key == "Caps" {
                AnyView(Image(systemName: keyboardManager.capsLockActive ? "lock.fill" : "lock.open").font(.system(size: 12)))
            } else if ["Ctrl", "Alt", "Win", "Cmd", "Option", "Super"].contains(key) {
                AnyView(Text(displayText).font(.system(size: 10, weight: .medium)))
            } else if key == "Space" {
                AnyView(Text("").frame(maxWidth: .infinity, maxHeight: .infinity))
            } else {
                AnyView(Text(displayText).font(.system(size: 12)))
            }
        }()
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed ? Color.blue : Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed ? .white : .primary)
    }

    @ViewBuilder
    private func windowsKeyButton(key: String, height: CGFloat) -> some View {
        let displayText = windowsDisplayValue(for: key)
        let modifierKeys: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"]
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive
        // F-row (height 36) and number row (height 38) show preview below; other rows above
        let previewBelow = height <= 38

        if modifierKeys.contains(key) {
            ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: displayText, previewBelow: previewBelow) { isPhysical, isLocked in
                windowsKeyVisual(key: key, displayText: displayText, isPressed: isPhysical || isLocked)
            }
            .frame(height: height)
        } else if key == "Caps" {
            KeyPressButton(
                onPress: { keyboardManager.handleSpecialKey("Caps") },
                onRelease: { },
                keyPreview: "⇪",
                previewBelow: previewBelow
            ) { isActive in
                windowsKeyVisual(key: key, displayText: displayText, isPressed: isActive || isCapsActive)
            }
            .frame(height: height)
        } else {
            let effectiveKey = key == "Esc" ? "Escape" : key
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            KeyPressButton(
                onPress: { repeatMode ? keyboardManager.startKeyRepeat(effectiveKey) : keyboardManager.handleKeyDown(effectiveKey) },
                onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(effectiveKey) },
                keyPreview: displayText,
                previewBelow: previewBelow
            ) { isActive in
                windowsKeyVisual(key: key, displayText: displayText, isPressed: isActive)
            }
            .frame(height: height)
        }
    }

    private func windowsDisplayValue(for key: String) -> String {
        if key == "Cmd" { return "⌘" }
        if key == "Option" { return "⌥" }
        if key == "Super" { return "❖" }
        let specialKeys = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Space", "Backspace", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Win", "Cmd", "Option", "Super"]
        if specialKeys.contains(key) { return key }
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

    // MARK: - Landscape Key Buttons

    @ViewBuilder
    private func landscapeKeyButton(key: String, previewBelow: Bool = false) -> some View {
        let displayText = landscapeDisplayValue(for: key)
        let modifierKeys: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Shift"]
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive

        if modifierKeys.contains(key) {
            ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: displayText, previewBelow: previewBelow) { isPhysical, isLocked in
                landscapeKeyContent(for: key, displayText: displayText)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isLocked ? Color.blue : (isPhysical ? Color.blue.opacity(0.7) : keyBackground(for: key, pressed: false, active: false)))
                    .cornerRadius(9)
                    .foregroundColor(isPhysical || isLocked ? .white : .primary)
            }
        } else if key == "Caps" {
            KeyPressButton(
                onPress: { keyboardManager.handleSpecialKey("Caps") },
                onRelease: { },
                keyPreview: "⇪",
                previewBelow: previewBelow
            ) { isActive in
                landscapeKeyContent(for: key, displayText: displayText)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(keyBackground(for: key, pressed: isActive, active: isCapsActive))
                    .cornerRadius(9)
                    .foregroundColor(isActive || isCapsActive ? .white : .primary)
            }
        } else {
            let effectiveKey = key == "Esc" ? "Escape" : key
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            KeyPressButton(
                onPress: { repeatMode ? keyboardManager.startKeyRepeat(effectiveKey) : keyboardManager.handleKeyDown(effectiveKey) },
                onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(effectiveKey) },
                keyPreview: displayText,
                previewBelow: previewBelow
            ) { isActive in
                landscapeKeyContent(for: key, displayText: displayText)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(keyBackground(for: key, pressed: isActive, active: false))
                    .cornerRadius(9)
                    .foregroundColor(isActive ? .white : .primary)
            }
        }
    }

    @ViewBuilder
    private func landscapeKeyContent(for key: String, displayText: String) -> some View {
        if key == "Backspace" {
            Image(systemName: "delete.left").font(.system(size: 16))
        } else if key == "Enter" {
            Image(systemName: "return").font(.system(size: 16))
        } else if key == "Shift" {
            Image(systemName: "shift").font(.system(size: 16))
        } else {
            Text(displayText)
        }
    }

    private func landscapeDisplayValue(for key: String) -> String {
        let specialKeys = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Space", "Backspace"]
        if specialKeys.contains(key) { return key }
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

    // MARK: - Shared

    private static let functionKeyBg = Color(UIColor.secondarySystemBackground)
    private static let regularKeyBg = Color(UIColor.systemBackground)
    /// Keys that should NOT repeat while held (modifiers and function keys).
    private static let noRepeatKeys: Set<String> = [
        "Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Win", "Cmd", "Option", "Super",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]

    private func keyBackground(for key: String, pressed: Bool, active: Bool) -> Color {
        let functionLabels = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Backspace", "Enter"]
        if pressed || active { return .blue }
        if functionLabels.contains(key) { return Self.functionKeyBg }
        return Self.regularKeyBg
    }

    // MARK: - Touchpad Submode

    @State private var isLeftButtonHeld = false
    @State private var isMiddleButtonHeld = false
    @State private var isRightButtonHeld = false
    @State private var pointerMoving: Bool = false

    private var isAnyButtonHeld: Bool { isLeftButtonHeld || isMiddleButtonHeld || isRightButtonHeld }

    private var touchpadButtonsText: String {
        var parts: [String] = []
        if mouseManager.isSelectMode {
            parts.append("drag")
        }
        if isLeftButtonHeld { parts.append("left held") }
        if isMiddleButtonHeld { parts.append("middle held") }
        if isRightButtonHeld { parts.append("right held") }
        return parts.isEmpty ? "up (no drag)" : parts.joined(separator: " + ")
    }

    private var touchpadTouchText: String {
        pointerMoving ? "moving pointer" : "idle"
    }

    private var touchpadSubmode: some View {
        let isLandscape = orientationManager.isLandscape
        let scrollFontSize: CGFloat = isLandscape ? 13 : 7
        let buttonRowHeight: CGFloat = (isLandscape ? 50 : 60) * 4

        return GeometryReader { stripGeo in
            VStack(spacing: 0) {
                // Touchpad + scroll strip
                HStack(spacing: 0) {
                    ZStack {
                        TouchpadView(
                            mouseManager: mouseManager,
                            pointerTipState: PointerTipState(),
                            onPointerMoving: { moving in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    pointerMoving = moving
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Glow border when drag or buttons are held
                        if isAnyButtonHeld || mouseManager.isSelectMode {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.6), lineWidth: 3)
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 0)
                                .transition(.opacity)
                        }

                        // Centered status overlay
                        VStack(spacing: 4) {
                            Text("TouchPad")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Buttons: \(touchpadButtonsText)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Touch: \(touchpadTouchText)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(UIColor.secondarySystemBackground).opacity(0.88))
                        )
                        .allowsHitTesting(false)

                        // Visual indicator when left button is held (matches Android hold-lock feedback)
                        if isLeftButtonHeld {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.35))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    BasicTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: scrollFontSize)
                        .frame(width: stripGeo.size.width * 0.3)
                }
                .frame(maxHeight: .infinity)

                // Mouse buttons row
                HStack(spacing: 8) {
                    mouseButton(label: "L", icon: "cursorarrow", button: .left, onStateChange: { held in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isLeftButtonHeld = held
                        }
                    })
                    .frame(maxWidth: .infinity)
                    mouseButton(label: "M", icon: "cursorarrow", button: .middle, onStateChange: { held in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isMiddleButtonHeld = held
                        }
                    })
                    .frame(maxWidth: .infinity)
                    mouseButton(label: "R", icon: "cursorarrow", button: .right, onStateChange: { held in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            isRightButtonHeld = held
                        }
                    })
                }
                .frame(height: buttonRowHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, isLandscape ? 4 : 8)
            }
        }
    }

    private func mouseButton(label: String, icon: String, button: MouseButton, onStateChange: ((Bool) -> Void)? = nil) -> some View {
        let bits: UInt8 = button == .left ? 0x01 : button == .right ? 0x02 : 0x04
        return MouseLockButton(
            onDown: {
                HapticFeedbackManager.shared.triggerButtonPress()
                onStateChange?(true)
                mouseManager.sendButtonDown(buttons: bits)
            },
            onUp: {
                onStateChange?(false)
                mouseManager.sendButtonUp(buttons: bits)
            },
            onLockChange: button == .left ? { locked in
                onStateChange?(locked)
            } : nil
        ) { isPressed, isLocked in
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isPressed || isLocked ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isLocked ? Color.blue : (isPressed ? Color.blue.opacity(0.7) : Color(UIColor.tertiarySystemBackground)))
                .cornerRadius(8)
                .overlay(
                    isLocked ? RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 2) : nil
                )
        }
    }

    enum MouseButton { case left, middle, right }

    // MARK: - Numpad Submode

    private var numpadSubmode: some View {
        BasicNumPadView(keyboardManager: keyboardManager, orientationManager: orientationManager)
    }

}

// MARK: - Key Callout Preview

private struct KeyCalloutInfo: Equatable {
    let text: String
    let frame: CGRect
    let below: Bool
}

private struct KeyCalloutInfoKey: PreferenceKey {
    static var defaultValue: KeyCalloutInfo? = nil
    static func reduce(value: inout KeyCalloutInfo?, nextValue: () -> KeyCalloutInfo?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - Repeating Key Button

/// Modifier key with two behaviour modes controlled by KmBasicKeyboardPrefs:
///
/// **Momentary-chord (default):** Press = key-down, release = key-up.
///   Long-press (0.5 s) reveals a floating lock icon; slide onto it to latch the modifier
///   so it persists across multiple key strokes (tap the locked key again to release).
///   Chord-sustain setting controls whether a real HID modifier-down is sent immediately
///   on press, or only when a regular key is chorded.
///
/// **Sticky:** Tap to latch the modifier on (it stays active until tapped again).
///   No momentary press behaviour — the modifier is fully toggled on release.
///
/// The label closure receives (isPhysicallyPressed, isLocked/latched).
struct ModifierKeyButton<Label: View>: View {
    let key: String
    let keyboardManager: KeyboardManager
    var keyPreview: String? = nil
    var previewBelow: Bool = false
    let label: (Bool, Bool) -> Label

    @ObservedObject private var prefs = KmBasicKeyboardPrefs.shared
    @State private var isPressed = false
    @State private var isLocked = false
    @State private var longPressTimer: Timer?
    @State private var showLockHint = false
    /// True during the finger-lift that immediately follows sliding to the lock icon.
    /// Prevents that release from being counted as an "unlock" tap.
    @State private var justLocked = false

    private let lockThreshold: TimeInterval = 0.5
    /// How far above the top edge the lock icon floats (pt)
    private let lockIconAbove: CGFloat = 32
    /// Tap radius to register the lock icon as hit (pt)
    private let lockIconRadius: CGFloat = 30

    init(key: String, keyboardManager: KeyboardManager, keyPreview: String? = nil, previewBelow: Bool = false, @ViewBuilder label: @escaping (Bool, Bool) -> Label) {
        self.key = key
        self.keyboardManager = keyboardManager
        self.keyPreview = keyPreview
        self.previewBelow = previewBelow
        self.label = label
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                label(isPressed, isLocked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Lock hint only shown in momentary-chord mode
                if showLockHint && prefs.modifierBehavior == .momentaryChord {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.orange))
                        // Center of ZStack is (w/2, h/2); shift up so icon sits lockIconAbove pt above top edge
                        .offset(y: -(geo.size.height / 2 + lockIconAbove))
                        .allowsHitTesting(false)
                        .zIndex(99)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: showLockHint)
            .overlay(
                PressDetectorView(
                    isPressed: $isPressed,
                    onPress: { handlePress() },
                    onRelease: { handleRelease() },
                    onMoved: { pt in handleMoved(pt, size: geo.size) }
                )
            )
            .preference(
                key: KeyCalloutInfoKey.self,
                value: isPressed && keyPreview != nil ?
                    KeyCalloutInfo(text: keyPreview!, frame: geo.frame(in: .named("keyboardLayout")), below: previewBelow)
                    : nil
            )
        }
        .onDisappear { cleanup() }
    }

    private func handlePress() {
        switch prefs.modifierBehavior {
        case .sticky:
            // In sticky mode nothing happens on press — the toggle fires on release.
            break
        case .momentaryChord:
            if isLocked {
                // Don't unlock on press — wait for release so mid-combo touches don't break the lock
            } else {
                // Send modifier-down (or only track it locally when chord sustain is off)
                if prefs.chordSustainHid {
                    keyboardManager.handleKeyDown(key)
                } else {
                    keyboardManager.addModifierTrackedOnly(key)
                }
                longPressTimer = Timer.scheduledTimer(withTimeInterval: lockThreshold, repeats: false) { _ in
                    DispatchQueue.main.async { self.showLockHint = true }
                }
            }
        }
    }

    private func handleRelease() {
        switch prefs.modifierBehavior {
        case .sticky:
            // Tap-toggle: latch on if not active, latch off if active.
            if isLocked {
                isLocked = false
                keyboardManager.unlockModifier(key)
            } else {
                isLocked = true
                keyboardManager.lockModifier(key)
            }
        case .momentaryChord:
            longPressTimer?.invalidate()
            longPressTimer = nil
            showLockHint = false
            if isLocked {
                if justLocked {
                    // This is the lift that completed the slide-to-lock gesture — don't unlock.
                    justLocked = false
                } else {
                    // Deliberate press+release on locked modifier → unlock
                    isLocked = false
                    keyboardManager.unlockModifier(key)
                }
            } else {
                keyboardManager.handleKeyUp(key)
            }
        }
    }

    /// Called when finger moves. Only active in momentary-chord mode.
    private func handleMoved(_ pt: CGPoint, size: CGSize) {
        guard prefs.modifierBehavior == .momentaryChord else { return }
        guard showLockHint && !isLocked else { return }
        // Icon center in PressDetectorView's local coords: x = w/2, y = -lockIconAbove
        let iconCenter = CGPoint(x: size.width / 2, y: -lockIconAbove)
        let dx = pt.x - iconCenter.x
        let dy = pt.y - iconCenter.y
        if sqrt(dx * dx + dy * dy) < lockIconRadius {
            longPressTimer?.invalidate()
            longPressTimer = nil
            isLocked = true
            justLocked = true  // mark so the upcoming finger-lift doesn't unlock
            showLockHint = false
            keyboardManager.lockModifier(key)
        }
    }

    private func cleanup() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        if isLocked {
            isLocked = false
            keyboardManager.unlockModifier(key)
        } else if isPressed {
            isPressed = false
            switch prefs.modifierBehavior {
            case .sticky:
                break  // nothing to release — was never pressed down
            case .momentaryChord:
                keyboardManager.handleKeyUp(key)
            }
        }
    }
}

/// Sends key-down on touch, key-up on release. Label closure receives current pressed state.
struct KeyPressButton<Label: View>: View {
    let onPress: () -> Void
    let onRelease: () -> Void
    var keyPreview: String? = nil
    var previewBelow: Bool = false
    let label: (Bool) -> Label

    @State private var isPressed = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void, keyPreview: String? = nil, previewBelow: Bool = false, @ViewBuilder label: @escaping (Bool) -> Label) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.keyPreview = keyPreview
        self.previewBelow = previewBelow
        self.label = label
    }

    var body: some View {
        label(isPressed)
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: KeyCalloutInfoKey.self,
                    value: isPressed && keyPreview != nil ?
                        KeyCalloutInfo(text: keyPreview!, frame: geo.frame(in: .named("keyboardLayout")), below: previewBelow)
                        : nil
                )
            })
            .overlay(
                PressDetectorView(isPressed: $isPressed, onPress: onPress, onRelease: onRelease)
            )
    }
}

/// UIKit-backed press detector to avoid SwiftUI gesture cancellation during multi-touch.
/// UILongPressGestureRecognizer with minimumPressDuration=0 and unlimited allowableMovement
/// fires .began on first touch, .ended/.cancelled when the finger lifts — reliably.
private struct PressDetectorView: UIViewRepresentable {
    @Binding var isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    var onMoved: ((CGPoint) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(isPressed: $isPressed, onPress: onPress, onRelease: onRelease, onMoved: onMoved)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let gr = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        gr.minimumPressDuration = 0
        gr.allowableMovement = .greatestFiniteMagnitude
        gr.cancelsTouchesInView = false
        gr.delaysTouchesBegan = false
        view.addGestureRecognizer(gr)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        @Binding var isPressed: Bool
        let onPress: () -> Void
        let onRelease: () -> Void
        let onMoved: ((CGPoint) -> Void)?

        init(isPressed: Binding<Bool>, onPress: @escaping () -> Void, onRelease: @escaping () -> Void, onMoved: ((CGPoint) -> Void)?) {
            self._isPressed = isPressed
            self.onPress = onPress
            self.onRelease = onRelease
            self.onMoved = onMoved
        }

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            switch gr.state {
            case .began:
                DispatchQueue.main.async { self.isPressed = true; self.onPress() }
            case .changed:
                if let onMoved = onMoved {
                    let pt = gr.location(in: gr.view)
                    DispatchQueue.main.async { onMoved(pt) }
                }
            case .ended, .cancelled, .failed:
                DispatchQueue.main.async { self.isPressed = false; self.onRelease() }
            default:
                break
            }
        }
    }
}

/// Mouse button with lock support: short tap = click, long press (0.5s) = lock held down, tap again to unlock.
struct MouseLockButton<Label: View>: View {
    let onDown: () -> Void
    let onUp: () -> Void
    /// Called with the new "held" state whenever the button is pressed/released or locked/unlocked.
    let onLockChange: ((Bool) -> Void)?
    let label: (Bool, Bool) -> Label

    @State private var isPressed = false
    @State private var isLocked = false
    @State private var longPressTimer: Timer?
    @State private var showLockHint = false
    @State private var justLocked = false

    private let lockThreshold: TimeInterval = 0.5
    private let lockIconAbove: CGFloat = 32
    private let lockIconRadius: CGFloat = 30

    init(onDown: @escaping () -> Void, onUp: @escaping () -> Void, onLockChange: ((Bool) -> Void)? = nil, @ViewBuilder label: @escaping (Bool, Bool) -> Label) {
        self.onDown = onDown
        self.onUp = onUp
        self.onLockChange = onLockChange
        self.label = label
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                label(isPressed, isLocked)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showLockHint {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.orange))
                        .offset(y: -(geo.size.height / 2 + lockIconAbove))
                        .allowsHitTesting(false)
                        .zIndex(99)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: showLockHint)
            .overlay(
                PressDetectorView(
                    isPressed: $isPressed,
                    onPress: { handlePress() },
                    onRelease: { handleRelease() },
                    onMoved: { pt in handleMoved(pt, size: geo.size) }
                )
            )
        }
        .onDisappear {
            longPressTimer?.invalidate()
            longPressTimer = nil
            if isLocked { isLocked = false; onLockChange?(false); onUp() }
            else if isPressed { isPressed = false; onLockChange?(false); onUp() }
        }
    }

    private func handlePress() {
        if isLocked {
            // Don't unlock on press — wait for release
        } else {
            onDown()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: lockThreshold, repeats: false) { _ in
                DispatchQueue.main.async { self.showLockHint = true }
            }
        }
    }

    private func handleRelease() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        showLockHint = false
        if isLocked {
            if justLocked {
                justLocked = false  // lift after slide-to-lock — stay locked
                onLockChange?(true)
            } else {
                isLocked = false
                onLockChange?(false)
                onUp()
            }
        } else {
            onLockChange?(false)
            onUp()
        }
    }

    private func handleMoved(_ pt: CGPoint, size: CGSize) {
        guard showLockHint && !isLocked else { return }
        let iconCenter = CGPoint(x: size.width / 2, y: -lockIconAbove)
        let dx = pt.x - iconCenter.x
        let dy = pt.y - iconCenter.y
        if sqrt(dx * dx + dy * dy) < lockIconRadius {
            longPressTimer?.invalidate()
            longPressTimer = nil
            isLocked = true
            justLocked = true
            showLockHint = false
            // button is already held down via onDown() — nothing extra needed
        }
    }
}

/// Sends press on touch-down and release on touch-up, supporting hold.
struct MousePressButton<Label: View>: View {
    let onPress: () -> Void
    let onRelease: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false

    var body: some View {
        label()
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isPressed ? 0.18 : 0))
            )
            .overlay(
                PressDetectorView(isPressed: $isPressed, onPress: onPress, onRelease: onRelease)
            )
    }
}

/// Fires its action on touch-down, then repeats at key-repeat rate while held.
/// Use this for all regular (non-modifier) keys.
struct RepeatingKeyButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var repeatTimer: Timer?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard repeatTimer == nil else { return }
                        action()
                        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                            action()
                        }
                    }
                    .onEnded { _ in
                        repeatTimer?.invalidate()
                        repeatTimer = nil
                    }
            )
            .onDisappear {
                repeatTimer?.invalidate()
                repeatTimer = nil
            }
    }
}
