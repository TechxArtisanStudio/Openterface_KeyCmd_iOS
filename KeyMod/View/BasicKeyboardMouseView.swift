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
        // 1. Tell AppDelegate to deny portrait from now on
        AppDelegate.orientationLock = .landscape
        // 2. Programmatically rotate the scene
        //    IMPORTANT: do NOT call setNeedsUpdateOfSupportedInterfaceOrientations() after this.
        //    UIHostingController.supportedInterfaceOrientations returns .all (it is not overridden),
        //    so that call makes the system re-evaluate against the physical device orientation (portrait)
        //    and snap back. AppDelegate.orientationLock is sufficient to hold the lock.
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in
                    // requestGeometryUpdate may be refused by UIHostingController's default
                    // supportedInterfaceOrientations; fall back to the legacy API.
                    DispatchQueue.main.async {
                        UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue,
                                                  forKey: "orientation")
                        UIViewController.attemptRotationToDeviceOrientation()
                    }
                }
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
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
                    windowsKeyButton(key: windowsFRow[idx], height: 28)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 30)
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
                Text("Openterface")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 150)
                    .frame(maxHeight: .infinity)
                    .background(Self.functionKeyBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
                    .onTapGesture { keyboardManager.handleSpecialKey("Space") }
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
                    windowsKeyButton(key: windowsFRow[idx], height: 28)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 30)
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
                Text("Openterface")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 150)
                    .frame(maxHeight: .infinity)
                    .background(Self.functionKeyBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
                    .onTapGesture { keyboardManager.handleSpecialKey("Space") }
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
                        landscapeKeyButton(key: row[colIdx])
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
                    windowsKeyButton(key: windowsFRow[idx], height: 28)
                }
            }
            .padding(.horizontal, 2)

            // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace
            HStack(spacing: 1) {
                ForEach(windowsNumberRow.indices, id: \.self) { idx in
                    windowsKeyButton(key: windowsNumberRow[idx], height: 30)
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
                Text("Openterface")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 150)
                    .frame(maxHeight: .infinity)
                    .background(Self.functionKeyBg)
                    .cornerRadius(6)
                    .foregroundColor(.primary)
                    .onTapGesture { keyboardManager.handleSpecialKey("Space") }
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
        let isPressed = keyboardManager.activeModifiers.contains(key)
        let displayLabel: String = {
            switch key {
            case "Cmd": return "⌘"
            case "Option": return "⌥"
            case "Super": return "❖"
            default: return key
            }
        }()
        Text(displayLabel)
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed ? .white : .primary)
            .onTapGesture { keyboardManager.handleSpecialKey(key) }
    }

    @ViewBuilder
    private func arrowButton(_ action: String, image: String, height: CGFloat = 52) -> some View {
        RepeatingKeyButton(action: { keyboardManager.handleSpecialKey(action) }) {
            Image(systemName: image)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 58, height: height)
                .background(Self.functionKeyBg)
                .cornerRadius(6)
                .foregroundColor(.primary)
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
            .background(Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed ? .white : .primary)
    }

    @ViewBuilder
    private func windowsKeyButton(key: String, height: CGFloat) -> some View {
        let displayText = windowsDisplayValue(for: key)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"].contains(key)
        let isPressed = isModifier && keyboardManager.activeModifiers.contains(key)

        if Self.noRepeatKeys.contains(key) {
            Button(action: { keyboardManager.handleSpecialKey(key) }) {
                windowsKeyVisual(key: key, displayText: displayText, isPressed: isPressed)
            }
            .frame(height: height)
            .buttonStyle(PlainButtonStyle())
        } else {
            RepeatingKeyButton(action: { keyboardManager.handleSpecialKey(key) }) {
                windowsKeyVisual(key: key, displayText: displayText, isPressed: isPressed)
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
    private func landscapeKeyButton(key: String) -> some View {
        let displayText = landscapeDisplayValue(for: key)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Shift"].contains(key)
        let isPressed = isModifier && keyboardManager.activeModifiers.contains(key)
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive

        Button(action: { keyboardManager.handleSpecialKey(key) }) {
            landscapeKeyContent(for: key, displayText: displayText)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(keyBackground(for: key, pressed: isPressed, active: isCapsActive))
                .cornerRadius(9)
                .foregroundColor(isPressed || isCapsActive ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
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

    private var touchpadSubmode: some View {
        let isLandscape = orientationManager.isLandscape
        let scrollWidth: CGFloat = isLandscape ? 72 : 28
        let scrollFontSize: CGFloat = isLandscape ? 13 : 7
        let buttonRowHeight: CGFloat = isLandscape ? 50 : 60

        return VStack(spacing: 0) {
            // Touchpad + scroll strip
            HStack(spacing: 0) {
                TouchpadView(mouseManager: mouseManager, pointerTipState: PointerTipState())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BasicTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: scrollFontSize)
                    .frame(width: scrollWidth)
            }
            .frame(maxHeight: .infinity)

            // Mouse buttons row
            HStack(spacing: 8) {
                mouseButton(label: "L", icon: "cursorarrow", button: .left)
                    .frame(maxWidth: .infinity)
                mouseButton(label: "M", icon: "cursorarrow", button: .middle)
                    .frame(maxWidth: .infinity)
                mouseButton(label: "R", icon: "cursorarrow", button: .right)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: buttonRowHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, isLandscape ? 4 : 8)
        }
    }

    private func mouseButton(label: String, icon: String, button: MouseButton) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.triggerButtonPress()
            switch button {
            case .left: mouseManager.handleClick()
            case .middle: mouseManager.handleMiddleClick()
            case .right: mouseManager.handleRightClick()
            }
        }) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    enum MouseButton { case left, middle, right }

    // MARK: - Numpad Submode

    private var numpadSubmode: some View {
        NumPadView(keyboardManager: keyboardManager, orientationManager: orientationManager)
    }
}

// MARK: - Repeating Key Button

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
