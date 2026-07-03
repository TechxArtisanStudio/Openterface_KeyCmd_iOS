//
//  BasicKeyboardMouseView.swift
//  KeyMod
//
//  Tabbed submode view matching Android's KM Basic (fragment_keyboard_mouse.xml):
//  Keyboard | Touchpad | Numpad tabs with a horizontal scrollable tab bar.

import SwiftUI
import UIKit

struct BasicKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager
    @Binding var selectedSubmode: Submode
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var prefs = KmBasicKeyboardPrefs.shared

    enum Submode: String, CaseIterable {
        case touchpad = "Touchpad"
        case keyboard = "Keyboard"
        case numpad = "Numpad"
    }

    init(mouseManager: MouseManager, keyboardManager: KeyboardManager, orientationManager: OrientationManager, selectedSubmode: Binding<Submode>) {
        self.mouseManager = mouseManager
        self.keyboardManager = keyboardManager
        self.orientationManager = orientationManager
        self._selectedSubmode = selectedSubmode
    }

    // Fixed safe-area inset reserved on the camera side in landscape.
    // Dynamic Island on iPhone 14/15/16 Pro creates ~59pt of safe area in landscape.
    // Used as a fallback when GeometryReader reports zero safe area insets.
    static let cameraSafeInset: CGFloat = 60

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
                    } else if newSubmode == .touchpad {
                        lockToPortrait()
                    } else {
                        unlockOrientation()
                    }
                }
            }
            // Camera-side-only padding: keyboard extends flush to the non-camera edge;
            // camera side reserves space for the Dynamic Island / camera bump.
            // Falls back to a fixed inset if the GeometryReader reports zero safe area
            // (which happens when the view hierarchy doesn't propagate safe areas).
            // Only apply for keyboard submode — touchpad/numpad should fill the full
            // available area with safe area on the physical top (portrait top) instead.
            .padding(.leading, selectedSubmode == .keyboard && orientationManager.isLandscape && !orientationManager.cameraOnRight ? max(geometry.safeAreaInsets.leading, Self.cameraSafeInset) : 0)
            .padding(.trailing, selectedSubmode == .keyboard && orientationManager.isLandscape && orientationManager.cameraOnRight ? max(geometry.safeAreaInsets.trailing, Self.cameraSafeInset) : 0)
            .onAppear {
                if selectedSubmode == .keyboard {
                    lockToLandscape()
                } else if selectedSubmode == .touchpad {
                    lockToPortrait()
                } else {
                    unlockOrientation()
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
        return Button(action: {
            // Lock orientation BEFORE switching view to prevent flash
            if submode == .keyboard {
                lockToLandscape()
            } else if submode == .touchpad {
                lockToPortrait()
            } else {
                unlockOrientation()
            }
            withAnimation { selectedSubmode = submode }
        }) {
            Text(submode.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? themeManager.accentColor.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func landscapeTabButton(for submode: Submode) -> some View {
        let isSelected = selectedSubmode == submode
        return Button(action: {
            // Lock orientation BEFORE switching view to prevent flash
            if submode == .keyboard {
                lockToLandscape()
            } else if submode == .touchpad {
                lockToPortrait()
            } else {
                unlockOrientation()
            }
            withAnimation { selectedSubmode = submode }
        }) {
            Text(submode.rawValue)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? themeManager.accentColor.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Landscape Keyboard Submode

    private var isWindowsTarget: Bool { aiSettings.targetOS == .windows }

    private var landscapeKeyboardSubmode: some View {
        GeometryReader { innerGeometry in
            // Align the keyboard away from the camera/Dynamic Island.
            // cameraOnRight is detected from UIDevice.current.orientation (see OrientationManager).
            let alignment: Alignment = orientationManager.cameraOnRight ? .leading : .trailing

            ZStack {
                switch aiSettings.targetOS {
                case .windows:
                    windowsKeyboardLayout
                case .linux:
                    linuxKeyboardLayout
                default:
                    macKeyboardLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .coordinateSpace(name: "keyboardLayout")
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
            .onAppear {
                LogManager.shared.log("LANDSCAPE KEYBOARD APPEARED — \(innerGeometry.size.width)x\(innerGeometry.size.height)", category: "Keyboard")
                lockToLandscape()
            }
            // NOTE: No .onDisappear here — it fires during rotation and would unlock prematurely.
            // Unlock is handled by the outer VStack's .onDisappear and onChange(selectedSubmode).
        }
    }

    private func lockToLandscape() {
        guard !OrientationManager.launchPanelVisible else { return }
        orientationManager.lockToLandscape()
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
            }
        }
    }

    private func lockToPortrait() {
        guard !OrientationManager.launchPanelVisible else { return }
        orientationManager.lockToPortrait()
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                DispatchQueue.main.async {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                }
            }
        }
    }

    private func unlockOrientation() {
        AppDelegate.orientationLock = .all
        orientationManager.preferredOrientation = .all
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { _ in }
            }
        }
        UIViewController.attemptRotationToDeviceOrientation()
        // Refresh isLandscape from actual device orientation — without this the
        // stale value from the previous landscape-locked submode persists and
        // numpad/touchpad render their landscape layout in portrait.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.orientationManager.updateOrientation()
        }
    }

    private var linuxKeyboardLayout: some View {
        GeometryReader { geo in
            let remainingHeight = max(0, geo.size.height - 15)
            let topRowHeight = remainingHeight / 10

            VStack(spacing: 6) {
                // Row 1: Esc + F1-F12 (half height)
                HStack(spacing: 3) {
                    ForEach(windowsFRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsFRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace (half height)
                HStack(spacing: 3) {
                    ForEach(windowsNumberRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsNumberRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 3: Tab q w e r t y u i o p [ ] \
                HStack(spacing: 3) {
                    ForEach(windowsRow3.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow3[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 4: Caps a s d f g h j k l ; ' Enter
                HStack(spacing: 3) {
                    ForEach(windowsRow4.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow4[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 5: Shift z x c v b n m , . / Shift
                HStack(spacing: 3) {
                    ForEach(windowsRow5.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow5[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 6: Ctrl Super Alt Space Alt Ctrl + inverted-T arrow cluster
                HStack(alignment: .center, spacing: 3) {
                    windowsBottomKey("Ctrl")
                    windowsBottomKey("Super")
                    windowsBottomKey("Alt")
                    // Space key — wide
                    KeyPressButton(
                        onPress: { keyboardManager.handleKeyDown("Space") },
                        onRelease: { keyboardManager.handleKeyUp("Space") },
                        keyPreview: "Space"
                    ) { isActive in
                        Image("openterface_wordmark")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82.5)
                            .frame(width: 200, alignment: .center)
                            .frame(maxHeight: .infinity)
                            .background(Self.functionKeyBg)
                            .cornerRadius(6)
                            .foregroundColor(isActive ? Self.keyIconPressed : Self.keyIconIdle)
                    }
                    windowsBottomKey("Alt")
                    windowsBottomKey("Ctrl")
                    arrowButton("Left", image: "left")
                    // Inverted-T with arrows matching modifier key height
                    HStack(spacing: 3) {
                        VStack(spacing: 0) {
                            arrowButton("Up", image: "up")
                                .frame(width: 58)
                            arrowButton("Down", image: "down")
                                .frame(width: 58)
                        }
                    }
                    arrowButton("Right", image: "right")
                    .padding(.trailing, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
    }

    private var macKeyboardLayout: some View {
        GeometryReader { geo in
            let remainingHeight = max(0, geo.size.height - 15)
            let topRowHeight = remainingHeight / 10

            VStack(spacing: 6) {
                // Row 1: Esc + F1-F12 (half height)
                HStack(spacing: 3) {
                    ForEach(windowsFRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsFRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace (half height)
                HStack(spacing: 3) {
                    ForEach(windowsNumberRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsNumberRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 3: Tab q w e r t y u i o p [ ] \
                HStack(spacing: 3) {
                    ForEach(windowsRow3.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow3[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 4: Caps a s d f g h j k l ; ' Enter
                HStack(spacing: 3) {
                    ForEach(windowsRow4.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow4[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 5: Shift z x c v b n m , . / Shift
                HStack(spacing: 3) {
                    ForEach(windowsRow5.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow5[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 6: Ctrl Option Cmd Space Cmd Option + inverted-T arrow cluster
                HStack(alignment: .center, spacing: 3) {
                    windowsBottomKey("Ctrl")
                    windowsBottomKey("Option")
                    windowsBottomKey("Cmd")
                    // Space key — wide
                    KeyPressButton(
                        onPress: { keyboardManager.handleKeyDown("Space") },
                        onRelease: { keyboardManager.handleKeyUp("Space") },
                        keyPreview: "Space"
                    ) { isActive in
                        Image("openterface_wordmark")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82.5)
                            .frame(width: 200, alignment: .center)
                            .frame(maxHeight: .infinity)
                            .background(Self.functionKeyBg)
                            .cornerRadius(6)
                            .foregroundColor(isActive ? Self.keyIconPressed : Self.keyIconIdle)
                    }
                    windowsBottomKey("Cmd")
                    windowsBottomKey("Option")
                    // Inverted-T: ↑ centered on top, ← ↓ → on bottom
                    arrowButton("Left", image: "left")
                    VStack(spacing: 3) {
                        // Top row: Up arrow centered (same width as single arrow)
                        arrowButton("Up", image: "up").frame(width: 58)
                        arrowButton("Down", image: "down")
                    }
                    arrowButton("Right", image: "right")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
    }

    private var originalKeyboardLayout: some View {
        VStack(spacing: 6) {
            ForEach(landscapeKeys.indices, id: \.self) { rowIdx in
                let row = landscapeKeys[rowIdx]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { colIdx in
                        // First two rows: left half popup RIGHT (left hand), right half popup LEFT (right hand)
                        let midCol = row.count / 2
                        let previewRight = rowIdx < 2 && colIdx < midCol
                        let previewLeft = rowIdx < 2 && colIdx >= midCol
                        landscapeKeyButton(key: row[colIdx], previewLeft: previewLeft, previewRight: previewRight)
                    }
                }
            }
        }
    }

    private var windowsKeyboardLayout: some View {
        GeometryReader { geo in
            // Top 2 rows at half the height of bottom 4 rows.
            // Total spacing: 5 gaps × 6pt = 30pt. Remaining: geo.size.height - 30.
            // 2h + 4(2h) = 10h = remaining → h = remaining / 10, 2h = remaining / 5.
            let remainingHeight = max(0, geo.size.height - 30)
            let topRowHeight = remainingHeight / 10
            let bottomRowHeight = remainingHeight / 5

            VStack(spacing: 6) {
                // Row 1: Esc + F1-F12 (half height)
                HStack(spacing: 3) {
                    ForEach(windowsFRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsFRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace (half height)
                HStack(spacing: 3) {
                    ForEach(windowsNumberRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsNumberRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 3: Tab q w e r t y u i o p [ ] \
                HStack(spacing: 3) {
                    ForEach(windowsRow3.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow3[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 4: Caps a s d f g h j k l ; ' Enter
                HStack(spacing: 3) {
                    ForEach(windowsRow4.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow4[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 5: Shift z x c v b n m , . / Shift
                HStack(spacing: 3) {
                    ForEach(windowsRow5.indices, id: \.self) { idx in
                        windowsKeyButton(key: windowsRow5[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 6: Ctrl Win Alt Space Alt Ctrl + inverted-T arrow cluster
                HStack(alignment: .center, spacing: 3) {
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
                        Image("openterface_wordmark")
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82.5)
                            .frame(width: 200, alignment: .center)
                            .frame(maxHeight: .infinity)
                            .background(Self.functionKeyBg)
                            .cornerRadius(6)
                            .foregroundColor(isActive ? Self.keyIconPressed : Self.keyIconIdle)
                    }
                    windowsBottomKey("Alt")
                    windowsBottomKey("Ctrl")
                    // Inverted-T: ↑ centered on top, ← ↓ → on bottom
                    VStack(spacing: 3) {
                        // Top row: Up arrow centered (same width as single arrow)
                        arrowButton("Up", image: "up")
                            .frame(width: 58)
                        // Bottom row: Left, Down, Right (narrower to fit closer to modifiers)
                        HStack(spacing: 3) {
                            arrowButton("Left", image: "left")
                            arrowButton("Down", image: "down")
                            arrowButton("Right", image: "right")
                        }
                    }
                    .padding(.trailing, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func windowsBottomKey(_ key: String) -> some View {
        let displayLabel: String = {
            switch key {
            case "Cmd": return "⌘"
            case "Option": return "⌥"
            default: return key
            }
        }()
        let isSuperKey = key == "Super" || key == "Win"
        return ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: displayLabel) { isPhysical, isLocked in
            Group {
                if isSuperKey && aiSettings.targetOS == .windows {
                    Image("targetos_windows")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(.gray)
                } else if isSuperKey && aiSettings.targetOS == .linux {
                    Image("targetos_linux")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(.gray)
                } else {
                    Text(displayLabel)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isLocked ? themeManager.accentColor : (isPhysical ? themeManager.accentColor.opacity(0.6) : Self.functionKeyBg))
            .cornerRadius(6)
            .foregroundColor(isPhysical || isLocked ? Self.keyLabelPressed : Self.keyLabelIdle)
        }
    }

    @ViewBuilder
    private func arrowButton(_ action: String, image: String) -> some View {
        let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
        let dir: KeyboardArrow.Direction = {
            switch image {
            case "up": return .up
            case "down": return .down
            case "left": return .left
            case "right": return .right
            default: return .up
            }
        }()
        return KeyPressButton(
            onPress: { repeatMode ? keyboardManager.startKeyRepeat(action) : keyboardManager.handleKeyDown(action) },
            onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(action) },
            keyPreview: action
        ) { isActive in
            KeyboardArrow(direction: dir)
                .fill(isActive ? Self.keyIconPressed : Self.keyIconIdle)
                .frame(width: 24, height: 24)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(isActive ? themeManager.accentColor : Self.functionKeyBg)
                .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func windowsKeyContent(key: String, displayText: String) -> some View {
        if key == "Backspace" {
            Image("backspace_24")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10)
        } else if key == "Enter" {
            Text("Enter").font(.system(size: 12, weight: .bold))
        } else if key == "Shift" {
            Text("Shift").font(.system(size: 12, weight: .bold))
        } else if key == "Tab" {
            Text("Tab").font(.system(size: 12, weight: .bold))
        } else if key == "Caps" {
            Text("Caps").font(.system(size: 12, weight: .bold))
        } else if ["Ctrl", "Alt", "Win", "Cmd", "Option", "Super"].contains(key) {
            Text(displayText).font(.system(size: 12, weight: .bold))
        } else if key == "Space" {
            Text("").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // For number and symbol keys, show dual labels: small symbol in top-right corner, main character centered below
            let shouldShowDualLabels = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"].contains(key)

            if shouldShowDualLabels {
                let shiftMap: [String: String] = [
                    "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
                    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
                    "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|",
                    ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
                ]
                let symbolLabel = shiftMap[key] ?? ""

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text(symbolLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }
                    .padding(.top, 2)

                    Text(displayText)
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(displayText).font(.system(size: 14, weight: .bold))
            }
        }
    }

    private func windowsKeyVisual(key: String, displayText: String, isPressed: Bool) -> some View {
        windowsKeyContent(key: key, displayText: displayText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed ? themeManager.accentColor : Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed ? Self.keyIconPressed : Self.keyIconIdle)
    }

    @ViewBuilder
    private func windowsKeyButton(key: String) -> some View {
        let keyLabel = windowsLabelOnKey(for: key)
        let previewText = windowsDisplayValue(for: key)
        let modifierKeys: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"]
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive
        // First two rows: left-half keys popup RIGHT (left hand), right-half keys popup LEFT (right hand).
        // Rows 3-6: popup ABOVE.
        let leftSideFirstTwoRows: Set<String> = ["Esc", "F1", "F2", "F3", "F4", "F5", "`", "1", "2", "3", "4", "5"]
        let rightSideFirstTwoRows: Set<String> = ["F6", "F7", "F8", "F9", "F10", "F11", "F12", "6", "7", "8", "9", "0", "-", "=", "Backspace"]
        let previewRight = leftSideFirstTwoRows.contains(key)
        let previewLeft = rightSideFirstTwoRows.contains(key)
        let previewBelow = false

        if modifierKeys.contains(key) {
            ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: previewText, previewBelow: previewBelow, previewLeft: previewLeft, previewRight: previewRight) { isPhysical, isLocked in
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isPhysical || isLocked)
            }
        } else if key == "Caps" {
            KeyPressButton(
                onPress: { keyboardManager.handleSpecialKey("Caps") },
                onRelease: { },
                keyPreview: "⇪",
                previewBelow: previewBelow,
                previewLeft: previewLeft,
                previewRight: previewRight
            ) { isActive in
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isActive || isCapsActive)
            }
        } else {
            let effectiveKey = key == "Esc" ? "Escape" : key
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            KeyPressButton(
                onPress: { repeatMode ? keyboardManager.startKeyRepeat(effectiveKey) : keyboardManager.handleKeyDown(effectiveKey) },
                onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(effectiveKey) },
                keyPreview: previewText,
                previewBelow: previewBelow,
                previewLeft: previewLeft,
                previewRight: previewRight
            ) { isActive in
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isActive)
            }
        }
    }

    /// Base label shown ON the key (physical-keyboard style: uppercase letters, raw symbols).
    private func windowsLabelOnKey(for key: String) -> String {
        if key == "Cmd" { return "⌘" }
        if key == "Option" { return "⌥" }
        if key == "Super" { return "❖" }
        let specialKeys = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Space", "Backspace", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Win", "Cmd", "Option", "Super"]
        if specialKeys.contains(key) { return key }
        if key.count == 1 && key.first!.isLetter { return key.uppercased() }
        return key
    }

    /// Shift-aware value for the preview popup (the actual char sent to target).
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
    private func landscapeKeyButton(key: String, previewBelow: Bool = false, previewLeft: Bool = false, previewRight: Bool = false) -> some View {
        let keyLabel = landscapeLabelOnKey(for: key)
        let previewText = landscapeDisplayValue(for: key)
        let modifierKeys: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Shift"]
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive

        if modifierKeys.contains(key) {
            ModifierKeyButton(key: key, keyboardManager: keyboardManager, keyPreview: previewText, previewBelow: previewBelow, previewLeft: previewLeft, previewRight: previewRight) { isPhysical, isLocked in
                landscapeKeyContent(for: key, displayText: keyLabel)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isLocked ? themeManager.accentColor : (isPhysical ? themeManager.accentColor.opacity(0.7) : keyBackground(for: key, pressed: false, active: false)))
                    .cornerRadius(9)
                    .foregroundColor(isPhysical || isLocked ? Self.keyLabelPressed : Self.keyLabelIdle)
            }
        } else if key == "Caps" {
            KeyPressButton(
                onPress: { keyboardManager.handleSpecialKey("Caps") },
                onRelease: { },
                keyPreview: "⇪",
                previewBelow: previewBelow,
                previewLeft: previewLeft,
                previewRight: previewRight
            ) { isActive in
                landscapeKeyContent(for: key, displayText: keyLabel)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(keyBackground(for: key, pressed: isActive, active: isCapsActive))
                    .cornerRadius(9)
                    .foregroundColor(isActive || isCapsActive ? Self.keyLabelPressed : Self.keyLabelIdle)
            }
        } else {
            let effectiveKey = key == "Esc" ? "Escape" : key
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            KeyPressButton(
                onPress: { repeatMode ? keyboardManager.startKeyRepeat(effectiveKey) : keyboardManager.handleKeyDown(effectiveKey) },
                onRelease: { repeatMode ? keyboardManager.stopKeyRepeat() : keyboardManager.handleKeyUp(effectiveKey) },
                keyPreview: previewText,
                previewBelow: previewBelow,
                previewLeft: previewLeft,
                previewRight: previewRight
            ) { isActive in
                landscapeKeyContent(for: key, displayText: keyLabel)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(keyBackground(for: key, pressed: isActive, active: false))
                    .cornerRadius(9)
                    .foregroundColor(isActive ? Self.keyLabelPressed : Self.keyLabelIdle)
            }
        }
    }

    @ViewBuilder
    private func landscapeKeyContent(for key: String, displayText: String) -> some View {
        if key == "Backspace" {
            Image("backspace_24")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if key == "Enter" {
            Image("keyboard_return_24px")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else if key == "Shift" {
            Image("shift_24px")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            // For number and symbol keys, show dual labels: small symbol in top-right corner, main character centered below
            // Check if this is a number/symbol key that should have dual labels
            let shouldShowDualLabels = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "[", "]", ";", "'", ",", ".", "/"].contains(key)

            if shouldShowDualLabels {
                // Get the symbol label from the shiftMap or use default
                let shiftMap: [String: String] = [
                    "`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
                    "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
                    "-": "_", "=": "+", "[": "{", "]": "}",
                    ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?"
                ]
                let symbolLabel = shiftMap[key] ?? ""

                VStack(spacing: 0) {
                    // Top-right aligned symbol
                    HStack {
                        Spacer()
                        Text(symbolLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)

                    // Centered main character
                    Text(displayText)
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(displayText)
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }

    private func landscapeLabelOnKey(for key: String) -> String {
        let specialKeys = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Space", "Backspace"]
        if specialKeys.contains(key) { return key }
        if key.count == 1 && key.first!.isLetter { return key.uppercased() }
        return key
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

    private static let functionKeyBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 74/255, green: 74/255, blue: 78/255, alpha: 1)
            : UIColor(red: 233/255, green: 233/255, blue: 236/255, alpha: 1)
    })
    private static let regularKeyBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 58/255, green: 58/255, blue: 60/255, alpha: 1)
            : UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)
    })
    // KM Basic key label colors (matches Android basic_key_label_color.xml)
    private static let keyLabelIdle = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)  // #FFFFFFFF
            : UIColor(red: 33/255, green: 33/255, blue: 33/255, alpha: 1)    // #FF212121
    })
    private static let keyLabelPressed = Color.white  // text on accent (blue) background
    // KM Basic hint colors (matches Android basic_key_hint_color.xml)
    private static let keyHintIdle = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 142/255, green: 142/255, blue: 147/255, alpha: 1) // #FF8E8E93
            : UIColor(red: 117/255, green: 117/255, blue: 117/255, alpha: 1) // #FF757575
    })
    private static let keyHintPressed = Color.white.opacity(0.85)
    // KM Basic icon tint (matches Android basic_key_icon_tint.xml)
    private static let keyIconIdle = keyLabelIdle
    private static let keyIconSelected = Color.blue  // held-lock accent (e.g. Caps Lock)
    private static let keyIconPressed = Color.white
    private static let touchpadBase = Color(red: 28/255, green: 28/255, blue: 30/255)
    private static let touchpadPanel = Color(red: 44/255, green: 44/255, blue: 46/255)
    private static let touchpadButton = Color(red: 44/255, green: 44/255, blue: 46/255)
    private static let touchpadButtonPressed = Color(red: 58/255, green: 58/255, blue: 60/255)
    private static let touchpadAccent = Color.white.opacity(0.07)
    private static let touchpadText = Color.white.opacity(0.92)
    /// Keys that should NOT repeat while held (modifiers and function keys).
    private static let noRepeatKeys: Set<String> = [
        "Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Win", "Cmd", "Option", "Super",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]

    private func keyBackground(for key: String, pressed: Bool, active: Bool) -> Color {
        let functionLabels = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Backspace", "Enter"]
        if pressed || active { return themeManager.accentColor }
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
                        .background(
                            ZStack {
                                Self.touchpadPanel
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.07), Color.clear]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.08), Color.clear]),
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                                RadialGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.09), Color.clear]),
                                    center: .init(x: 0.28, y: 0.24),
                                    startRadius: 0,
                                    endRadius: 260
                                )
                                RadialGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.11), Color.clear]),
                                    center: .init(x: 0.78, y: 0.82),
                                    startRadius: 0,
                                    endRadius: 280
                                )
                            }
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)

                        // Glow border when drag or buttons are held
                        if isAnyButtonHeld || mouseManager.isSelectMode {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 0)
                                .transition(.opacity)
                        }

                        // Openterface logo in the touchpad surface.
                        VStack {
                            HStack {
                                Spacer()
                                Image("openterface_wordmark")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 12)
                                    .opacity(0.50)
                                Spacer()
                            }
                            .padding(.top, 12)
                            Spacer()
                        }
                        .allowsHitTesting(false)

                        // Visual indicator when left button is held (matches Android hold-lock feedback)
                        if isLeftButtonHeld {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.40))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .stroke(Color.black.opacity(0.28), lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    let stripWidth = max(28, (stripGeo.size.width / 6) * 0.9)
                    BasicTouchpadScrollStripView(mouseManager: mouseManager, labelFontSize: scrollFontSize)
                        .frame(width: stripWidth)
                }
                .frame(maxHeight: .infinity)
                .background(Self.touchpadBase)

                // Mouse buttons row
                GeometryReader { buttonGeo in
                    let totalSpacing = 16.0 + 24.0  // 8*2 between buttons + 12*2 padding
                    let availableWidth = buttonGeo.size.width - totalSpacing
                    let unitWidth = availableWidth / 5.0  // 2:1:2 ratio = 5 units
                    let sideWidth = unitWidth * 2.0
                    let middleWidth = unitWidth

                    HStack(spacing: 8) {
                        mouseButton(label: "L", icon: "cursorarrow", button: .left, onStateChange: { held in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                isLeftButtonHeld = held
                            }
                        })
                        .frame(width: sideWidth)
                        mouseButton(label: "M", icon: "cursorarrow", button: .middle, onStateChange: { held in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                isMiddleButtonHeld = held
                            }
                        })
                        .frame(width: middleWidth)
                        mouseButton(label: "R", icon: "cursorarrow", button: .right, onStateChange: { held in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                isRightButtonHeld = held
                            }
                        })
                        .frame(width: sideWidth)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: buttonRowHeight)
                .padding(.horizontal, 12)
                .padding(.vertical, isLandscape ? 4 : 8)
                .background(Self.touchpadPanel)
            }
        }
    }

    private func mouseButton(label: String, icon: String, button: MouseButton, onStateChange: ((Bool) -> Void)? = nil) -> some View {
        let bits: UInt8 = button == .left ? 0x01 : button == .right ? 0x02 : 0x04
        return MouseLockButton(
            onDown: {
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isPressed || isLocked ? .white : Self.touchpadText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLocked ? Self.touchpadButtonPressed : (isPressed ? Self.touchpadButtonPressed : Self.touchpadButton))
                    .shadow(color: Color.black.opacity(0.22), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(isPressed || isLocked ? 0.04 : 0.08), Color.clear]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(.screen)
                    )
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(isPressed || isLocked ? 0.05 : 0.08), lineWidth: 1)
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

struct KeyCalloutInfo: Equatable {
    let text: String
    let frame: CGRect
    let below: Bool
    let left: Bool
    let right: Bool
}

struct KeyCalloutInfoKey: PreferenceKey {
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
    var previewLeft: Bool = false
    var previewRight: Bool = false
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

    init(key: String, keyboardManager: KeyboardManager, keyPreview: String? = nil, previewBelow: Bool = false, previewLeft: Bool = false, previewRight: Bool = false, @ViewBuilder label: @escaping (Bool, Bool) -> Label) {
        self.key = key
        self.keyboardManager = keyboardManager
        self.keyPreview = keyPreview
        self.previewBelow = previewBelow
        self.previewLeft = previewLeft
        self.previewRight = previewRight
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
                        .font(.system(size: 24, weight: .bold))
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
                value: prefs.keyTapPreviewEnabled && isPressed && keyPreview != nil ?
                    KeyCalloutInfo(text: keyPreview!, frame: geo.frame(in: .named("keyboardLayout")), below: previewBelow, left: previewLeft, right: previewRight)
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
    var previewLeft: Bool = false
    var previewRight: Bool = false
    let label: (Bool) -> Label

    @ObservedObject private var prefs = KmBasicKeyboardPrefs.shared
    @State private var isPressed = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void, keyPreview: String? = nil, previewBelow: Bool = false, previewLeft: Bool = false, previewRight: Bool = false, @ViewBuilder label: @escaping (Bool) -> Label) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.keyPreview = keyPreview
        self.previewBelow = previewBelow
        self.previewLeft = previewLeft
        self.previewRight = previewRight
        self.label = label
    }

    var body: some View {
        label(isPressed)
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: KeyCalloutInfoKey.self,
                    value: prefs.keyTapPreviewEnabled && isPressed && keyPreview != nil ?
                        KeyCalloutInfo(text: keyPreview!, frame: geo.frame(in: .named("keyboardLayout")), below: previewBelow, left: previewLeft, right: previewRight)
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
                        .font(.system(size: 24, weight: .bold))
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
