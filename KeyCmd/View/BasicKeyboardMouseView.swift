//
//  BasicKeyboardMouseView.swift
//  KeyMod
//
//  Tabbed submode view matching Android's KM Basic (fragment_keyboard_mouse.xml):
//  Keyboard | Touchpad | Numpad tabs with a horizontal scrollable tab bar.

import SwiftUI
import UIKit

/// Collects the actual rendered frame of every key in "keyboardLayout" space.
private struct KeyFramePreferenceKey: PreferenceKey {
    static var defaultValue: [KeyRegistration] { [] }

    static func reduce(value: inout [KeyRegistration], nextValue: () -> [KeyRegistration]) {
        value.append(contentsOf: nextValue())
    }
}

private struct KeyFrameReporter: ViewModifier {
    let keyName: String
    let keyType: KeyType

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: KeyFramePreferenceKey.self,
                    value: [KeyRegistration(
                        keyId: keyName,
                        keyName: keyName,
                        keyType: keyType,
                        frame: geo.frame(in: .named("keyboardLayout"))
                    )]
                )
            }
        )
    }
}

private extension View {
    func reportKeyFrame(_ keyName: String, _ keyType: KeyType) -> some View {
        modifier(KeyFrameReporter(keyName: keyName, keyType: keyType))
    }
}

struct BasicKeyboardMouseView: View {
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager
    @Binding var selectedSubmode: Submode
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var prefs = KmBasicKeyboardPrefs.shared
    @ObservedObject private var layoutManager = KeyboardLayoutManager.shared
    /// Key frames reported by the rendered key views, in "keyboardLayout" space.
    /// The visual bottom row (inverted-T arrows, fixed-width Space) is not a plain
    /// grid, so the touch registry must follow the real geometry.
    @State private var measuredKeyFrames: [KeyRegistration] = []

    // Keyboard backlight level (0=off, 1=low, 2=high) for F5/F6 dynamic icons
    @State private var keyboardBacklightLevel: Int = 0

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

    /// Space reserved under the bottom row. The keyboard ignores the bottom safe area
    /// and would otherwise end flush with the physical edge, inside the home-indicator
    /// gesture strip, where the system delays or cancels taps — the short ↓ key was
    /// effectively unresponsive there on notched devices.
    static let bottomGestureInset: CGFloat = 24

    // Landscape keyboard rows matching Android keyboard_lower_landscape.xml
    let landscapeKeys: [[String]] = [
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    // MARK: - Keyboard Layout Rows (from KeyboardLayoutManager)

    /// Extract key names from the current layout for visual rendering
    private var currentLayoutRows: [[String]] {
        let layout = layoutManager.currentLayout
        return layout.rows.map { row in
            row.map { $0.keyName }
        }
    }

    /// Function row (F1-F12, Esc)
    private var currentFRow: [String] {
        currentLayoutRows.first ?? []
    }

    /// Number row (1-12 keys)
    private var currentNumberRow: [String] {
        currentLayoutRows.count > 1 ? currentLayoutRows[1] : []
    }

    /// QWERTY/AZERTY/QWERTZ row
    private var currentRow3: [String] {
        gridRow(2)
    }

    /// ASDF row
    private var currentRow4: [String] {
        gridRow(3)
    }

    /// ZXCV row
    private var currentRow5: [String] {
        gridRow(4)
    }

    /// Bottom modifier row
    private var currentRow6: [String] {
        gridRow(5)
    }

    /// Arrow keys are drawn by the dedicated inverted-T cluster, never as grid keys.
    /// Layout files still carry Up/Down/Left/Right for their HID metadata, but several
    /// place "Up" inside the ZXCV row, which used to render a second up-arrow key.
    private static let gridArrowKeyNames: Set<String> = ["Up", "Down", "Left", "Right"]

    private func gridRow(_ index: Int) -> [String] {
        guard currentLayoutRows.count > index else { return [] }
        return currentLayoutRows[index].filter { !Self.gridArrowKeyNames.contains($0) }
    }

    /// Look up the KeyDefinition for a given key name from the current layout
    private func keyDefinition(for keyName: String) -> KeyDefinition? {
        return layoutManager.currentLayout.keyDefinition(for: keyName)
    }

    /// Get the display label for a key from the layout definition
    private func layoutLabel(for keyName: String) -> String {
        return keyDefinition(for: keyName)?.label ?? keyName
    }

    /// Get the shift label for a key from the layout definition
    private func layoutShiftLabel(for keyName: String) -> String? {
        return keyDefinition(for: keyName)?.shiftLabel
    }

    /// Get the AltGr label for a key from the layout definition
    private func layoutAltGrLabel(for keyName: String) -> String? {
        return keyDefinition(for: keyName)?.altGrLabel
    }

    /// The Mac layout relabels the PC Menu key as "fn". Fn has no HID usage of
    /// its own, so it is handled as a local layer rather than a sent key.
    private func isFnKey(_ keyName: String) -> Bool {
        layoutLabel(for: keyName).lowercased() == "fn"
    }

    /// Check if a key is a function key (F1-F12)
    private func isFunctionKey(_ keyName: String) -> Bool {
        ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"].contains(keyName)
    }

    /// Check if a key has media/Apple function support (F1-F4, F7-F12).
    /// F1-F4: Apple function row (brightness, Mission Control, Launchpad)
    /// F5-F6: Regular F-keys (keyboard backlight not supported by firmware)
    /// F7-F12: Consumer Page media keys (volume, playback)
    private func isMediaKey(_ keyName: String) -> Bool {
        ["F1", "F2", "F3", "F4", "F7", "F8", "F9", "F10", "F11", "F12"].contains(keyName)
    }

    /// Return SF Symbol name for macOS media icons on F7-F12.
    /// F1-F6 are Apple-specific (brightness, Mission Control, etc.) and not
    /// supported by standard Consumer Page — show as regular F-keys.
    @ViewBuilder
    private func mediaIcon(for keyName: String) -> some View {
        let symbol = mediaSymbolName(for: keyName)
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaSymbolName(for keyName: String) -> String {
        switch keyName {
        case "F1":  return "sun.min"           // Display brightness down
        case "F2":  return "sun.max"           // Display brightness up
        case "F3":  return "rectangle.3.group" // Mission Control
        case "F4":  return "square.grid.3x3"   // Launchpad
        case "F7":  return "backward"          // Rewind
        case "F8":  return "playpause"         // Play/Pause
        case "F9":  return "forward"           // Fast forward
        case "F10": return "speaker.slash"     // Mute
        case "F11": return "speaker.minus"     // Volume down
        case "F12": return "speaker.plus"      // Volume up
        default:    return "circle"
        }
    }

    /// Map F-key names to Consumer page media key bitmaps (Report ID 0x02).
    /// Bitmap layout from firmware usbd_desc.c:
    ///   byte1: Vol+(bit0), Vol-(bit1), Mute(bit2), Play/Pause(bit3),
    ///          Next(bit4), Prev(bit5), Stop(bit6), Eject(bit7)
    ///   byte2: Email, Search, Bookmarks, Home, Back, Forward, Stop, Refresh
    ///   byte3: Media, Browser, Calculator, ScreenSaver, MyComputer, Minimize, Record, Rewind
    private func mediaKeyBitmap(for keyName: String) -> (UInt8, UInt8, UInt8)? {
        switch keyName {
        case "F7":  return (0, 0, 1 << 7)           // Rewind (byte3 bit7)
        case "F8":  return (1 << 3, 0, 0)           // Play/Pause (byte1 bit3)
        case "F9":  return (1 << 4, 0, 0)           // Scan Next Track (byte1 bit4)
        case "F10": return (1 << 2, 0, 0)           // Mute (byte1 bit2)
        case "F11": return (1 << 1, 0, 0)           // Volume Decrement (byte1 bit1)
        case "F12": return (1 << 0, 0, 0)           // Volume Increment (byte1 bit0)
        default:    return nil
        }
    }

    /// Map F1-F4 to Apple function row bitmap (Report ID 0x03).
    /// Firmware maps these to Consumer page HID usages:
    ///   bit0: F1 → 0x0070 Display Brightness Decrement
    ///   bit1: F2 → 0x006F Display Brightness Increment
    ///   bit2: F3 → 0x029F Mission Control
    ///   bit3: F4 → 0x02A2 Launchpad
    private func appleFnBitmap(for keyName: String) -> UInt8? {
        switch keyName {
        case "F1": return 1 << 0  // Display brightness down
        case "F2": return 1 << 1  // Display brightness up
        case "F3": return 1 << 2  // Mission Control
        case "F4": return 1 << 3  // Launchpad
        default:   return nil
        }
    }

    // Windows-style layout rows (kept for backward compatibility, will be removed)
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

    // Mac-specific bottom row (kept for backward compatibility, will be removed)
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
            .onPreferenceChange(KeyFramePreferenceKey.self) { frames in
                if frames != measuredKeyFrames {
                    measuredKeyFrames = frames
                }
            }
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
                    ForEach(currentFRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: currentFRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 2: Number row (half height)
                HStack(spacing: 3) {
                    ForEach(currentNumberRow.indices, id: \.self) { idx in
                        windowsKeyButton(key: currentNumberRow[idx])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: topRowHeight)

                // Row 3: QWERTY/AZERTY/QWERTZ row
                HStack(spacing: 3) {
                    ForEach(currentRow3.indices, id: \.self) { idx in
                        windowsKeyButton(key: currentRow3[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 4: ASDF row
                HStack(spacing: 3) {
                    ForEach(currentRow4.indices, id: \.self) { idx in
                        windowsKeyButton(key: currentRow4[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 5: ZXCV row
                HStack(spacing: 3) {
                    ForEach(currentRow5.indices, id: \.self) { idx in
                        windowsKeyButton(key: currentRow5[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Row 6: Bottom modifier row with arrow cluster
                HStack(alignment: .center, spacing: 3) {
                    // Render modifier keys from the layout
                    ForEach(currentRow6.indices, id: \.self) { idx in
                        let key = currentRow6[idx]
                        if key == "Space" {
                            // Special handling for Space key with logo
                            let isSpacePressed = keyboardManager.isKeyPressed(hid: .keyboardSpace)
                            Image("openterface_wordmark")
                                .resizable()
                                .renderingMode(.template)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 82.5)
                                .frame(width: 200, alignment: .center)
                                .frame(maxHeight: .infinity)
                                .background(isSpacePressed ? themeManager.accentColor : Self.functionKeyBg)
                                .cornerRadius(6)
                                .foregroundColor(isSpacePressed ? Self.keyIconPressed : Self.keyIconIdle)
                                .reportKeyFrame("Space", keyType(for: "Space"))
                        } else {
                            windowsBottomKey(key)
                        }
                    }
                    // Arrow cluster (inverted-T)
                    arrowButton("Left", image: "left")
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
            .padding(.bottom, Self.bottomGestureInset)
            .overlay(
                MultiTouchKeyboardContainer(
                    layout: buildLayoutDescription(for: geo.size, isWindowsLayout: false),
                    measuredFrames: measuredKeyFrames,
                    keyTypeResolver: keyType(for:),
                    onPress: { keyName, keyType in
                        handleMultiTouchPress(keyName: keyName, keyType: keyType)
                    },
                    onRelease: { keyName, keyType in
                        handleMultiTouchRelease(keyName: keyName, keyType: keyType)
                    },
                    onMoved: { point, keyName in
                        handleMultiTouchMoved(point: point, keyName: keyName)
                    }
                )
            )
        }
    }

    private var macKeyboardLayout: some View {
        GeometryReader { geo in
            let remainingHeight = max(0, geo.size.height - 30)
            let topRowHeight = remainingHeight / 10

            ZStack {
                // Existing visual keyboard layout (unchanged — per-key touch handlers still active)
                VStack(spacing: 6) {
                    // Row 1: Esc + F1-F12 (half height)
                    HStack(spacing: 3) {
                        ForEach(currentFRow.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentFRow[idx])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)

                    // Row 2: Number row (half height)
                    HStack(spacing: 3) {
                        ForEach(currentNumberRow.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentNumberRow[idx])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)

                    // Row 3: QWERTY/AZERTY/QWERTZ row
                    HStack(spacing: 3) {
                        ForEach(currentRow3.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow3[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 4: ASDF row
                    HStack(spacing: 3) {
                        ForEach(currentRow4.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow4[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 5: ZXCV row
                    HStack(spacing: 3) {
                        ForEach(currentRow5.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow5[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 6: Bottom modifier row with arrow cluster (Mac-style)
                    HStack(alignment: .center, spacing: 3) {
                        // Render modifier keys from the layout
                        ForEach(currentRow6.indices, id: \.self) { idx in
                            let key = currentRow6[idx]
                            if key == "Space" {
                                // Special handling for Space key with logo
                                let isSpacePressed = keyboardManager.isKeyPressed(hid: .keyboardSpace)
                                Image("openterface_wordmark")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 82.5)
                                    .frame(width: 200, alignment: .center)
                                    .frame(maxHeight: .infinity)
                                    .background(isSpacePressed ? themeManager.accentColor : Self.functionKeyBg)
                                    .cornerRadius(6)
                                    .foregroundColor(isSpacePressed ? Self.keyIconPressed : Self.keyIconIdle)
                                    .reportKeyFrame("Space", keyType(for: "Space"))
                            } else {
                                windowsBottomKey(key)
                            }
                        }
                        // Arrow cluster (inverted-T for Mac)
                        arrowButton("Left", image: "left")
                        VStack(spacing: 3) {
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
                .padding(.bottom, Self.bottomGestureInset)

                // Multi-touch overlay — unified container handles all touch events
                MultiTouchKeyboardContainer(
                    layout: buildLayoutDescription(for: geo.size, isWindowsLayout: false),
                    measuredFrames: measuredKeyFrames,
                    keyTypeResolver: keyType(for:),
                    onPress: { keyName, keyType in
                        handleMultiTouchPress(keyName: keyName, keyType: keyType)
                    },
                    onRelease: { keyName, keyType in
                        handleMultiTouchRelease(keyName: keyName, keyType: keyType)
                    },
                    onMoved: { point, keyName in
                        handleMultiTouchMoved(point: point, keyName: keyName)
                    }
                )
            }
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

            ZStack {
                // Existing visual keyboard layout (unchanged — per-key touch handlers still active)
                VStack(spacing: 6) {
                    // Row 1: Esc + F1-F12 (half height)
                    HStack(spacing: 3) {
                        ForEach(currentFRow.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentFRow[idx])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)

                    // Row 2: Number row (half height)
                    HStack(spacing: 3) {
                        ForEach(currentNumberRow.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentNumberRow[idx])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)

                    // Row 3: QWERTY/AZERTY/QWERTZ row
                    HStack(spacing: 3) {
                        ForEach(currentRow3.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow3[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 4: ASDF row
                    HStack(spacing: 3) {
                        ForEach(currentRow4.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow4[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 5: ZXCV row
                    HStack(spacing: 3) {
                        ForEach(currentRow5.indices, id: \.self) { idx in
                            windowsKeyButton(key: currentRow5[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    // Row 6: Bottom modifier row with arrow cluster (Windows-style)
                    HStack(alignment: .center, spacing: 3) {
                        // Render modifier keys from the layout
                        ForEach(currentRow6.indices, id: \.self) { idx in
                            let key = currentRow6[idx]
                            if key == "Space" {
                                // Special handling for Space key with logo
                                let isSpacePressed = keyboardManager.isKeyPressed(hid: .keyboardSpace)
                                Image("openterface_wordmark")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 82.5)
                                    .frame(width: 200, alignment: .center)
                                    .frame(maxHeight: .infinity)
                                    .background(isSpacePressed ? themeManager.accentColor : Self.functionKeyBg)
                                    .cornerRadius(6)
                                    .foregroundColor(isSpacePressed ? Self.keyIconPressed : Self.keyIconIdle)
                                    .reportKeyFrame("Space", keyType(for: "Space"))
                            } else {
                                windowsBottomKey(key)
                            }
                        }
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
                .padding(.bottom, Self.bottomGestureInset)

                // Multi-touch overlay — unified container handles all touch events
                MultiTouchKeyboardContainer(
                    layout: buildLayoutDescription(for: geo.size, isWindowsLayout: true),
                    measuredFrames: measuredKeyFrames,
                    keyTypeResolver: keyType(for:),
                    onPress: { keyName, keyType in
                        handleMultiTouchPress(keyName: keyName, keyType: keyType)
                    },
                    onRelease: { keyName, keyType in
                        handleMultiTouchRelease(keyName: keyName, keyType: keyType)
                    },
                    onMoved: { point, keyName in
                        handleMultiTouchMoved(point: point, keyName: keyName)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func windowsBottomKey(_ key: String) -> some View {
        // Mirror the layout's user-facing label instead of the internal key
        // name, so LeftCtrl/RightCtrl render as "Ctrl" rather than "LeftCtrl".
        let displayLabel: String = {
            if let label = keyDefinition(for: key)?.label { return label }
            switch key {
            case "Cmd": return "⌘"
            case "Option": return "⌥"
            default: return key
            }
        }()
        let isSuperKey = ["Super", "Win", "LeftWin", "RightWin"].contains(key)
        let isModifierKey = keyDefinition(for: key)?.keyType == .modifier
        // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
        let isPressed: Bool
        if isModifierKey {
            isPressed = keyboardManager.activeModifiers.contains(key) || keyboardManager.lockedModifiers.contains(key)
        } else if isFnKey(key) {
            isPressed = keyboardManager.isFnPressed
        } else {
            isPressed = keyboardManager.isKeyPressed(key)
        }
        return Group {
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
        .background(isPressed ? themeManager.accentColor : Self.functionKeyBg)
        .cornerRadius(6)
        .foregroundColor(isPressed ? Self.keyLabelPressed : Self.keyLabelIdle)
        .reportKeyFrame(key, keyType(for: key))
    }

    @ViewBuilder
    private func arrowButton(_ action: String, image: String) -> some View {
        let dir: KeyboardArrow.Direction = {
            switch image {
            case "up": return .up
            case "down": return .down
            case "left": return .left
            case "right": return .right
            default: return .up
            }
        }()
        // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
        let isPressed = keyboardManager.isKeyPressed(action)
        return KeyboardArrow(direction: dir)
            .fill(isPressed ? Self.keyIconPressed : Self.keyIconIdle)
            .frame(width: 24, height: 24)
            .frame(width: 58)
            .frame(maxHeight: .infinity)
            .background(isPressed ? themeManager.accentColor : Self.functionKeyBg)
            .cornerRadius(6)
            .reportKeyFrame(action, .regular)
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
        } else if keyDefinition(for: key)?.keyType == .modifier
                    || ["Ctrl", "Alt", "Win", "Cmd", "Option", "Super"].contains(key) {
            Text(displayText).font(.system(size: 12, weight: .bold))
        } else if key == "Space" {
            Text("").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isMediaKey(key) {
            // F7-F12: show media icons, switch to F7-F12 labels when Fn is pressed
            if keyboardManager.isFnPressed {
                Text(displayText).font(.system(size: 14, weight: .bold))
            } else {
                mediaIcon(for: key)
            }
        } else {
            // Use layout definition for labels
            let shiftLabel = layoutShiftLabel(for: key)
            let altGrLabel = layoutAltGrLabel(for: key)
            let hasShiftLabel = shiftLabel != nil
            let hasAltGrLabel = altGrLabel != nil

            if hasShiftLabel || hasAltGrLabel {
                VStack(spacing: 0) {
                    // Top row: shift label (top-left) and altGr label (top-right)
                    HStack {
                        if let shiftLabel = shiftLabel {
                            Text(shiftLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }
                        Spacer()
                        if let altGrLabel = altGrLabel {
                            Text(altGrLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 4)
                        }
                    }
                    .padding(.top, 2)

                    // Main label centered
                    Text(displayText)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(displayText)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private func windowsKeyButton(key: String) -> some View {
        let keyLabel = windowsLabelOnKey(for: key)
        let previewText = windowsDisplayValue(for: key)
        let isModifierKey = keyDefinition(for: key)?.keyType == .modifier
            || ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"].contains(key)
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive
        // First two rows: left-half keys popup RIGHT (left hand), right-half keys popup LEFT (right hand).
        // Rows 3-6: popup ABOVE.
        let leftSideFirstTwoRows: Set<String> = ["Esc", "F1", "F2", "F3", "F4", "F5", "`", "1", "2", "3", "4", "5"]
        let rightSideFirstTwoRows: Set<String> = ["F6", "F7", "F8", "F9", "F10", "F11", "F12", "6", "7", "8", "9", "0", "-", "=", "Backspace"]
        let previewRight = leftSideFirstTwoRows.contains(key)
        let previewLeft = rightSideFirstTwoRows.contains(key)
        let previewBelow = false

        return Group {
            if isModifierKey {
                // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
                let isPressed = keyboardManager.activeModifiers.contains(key) || keyboardManager.lockedModifiers.contains(key)
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isPressed)
            } else if key == "Caps" {
                // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isCapsActive)
            } else {
                // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
                let isPressed = isFnKey(key) ? keyboardManager.isFnPressed
                                             : keyboardManager.isKeyPressed(key)
                windowsKeyVisual(key: key, displayText: keyLabel, isPressed: isPressed)
            }
        }
        .reportKeyFrame(key, keyType(for: key))
    }

    /// Base label shown ON the key (physical-keyboard style: uppercase letters, raw symbols).
    private func windowsLabelOnKey(for key: String) -> String {
        // Use layout definition if available
        if let keyDef = keyDefinition(for: key) {
            return keyDef.label
        }
        // Fallback for keys not in layout definition
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
        // Use layout definition if available
        if let keyDef = keyDefinition(for: key) {
            let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
            let isCapsActive = keyboardManager.capsLockActive
            let isAltGrActive = keyboardManager.isAltGrActive

            // AltGr layer takes precedence: it can add symbols to letter keys
            // (e.g. DE q → @, e → €).
            if isAltGrActive, let altGrLabel = keyDef.altGrLabel {
                return altGrLabel
            }

            // For letter keys, handle caps lock and shift
            if key.count == 1 && key.first!.isLetter {
                let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
                return shouldBeUppercase ? key.uppercased() : key.lowercased()
            }

            // For other keys, return shift label if shift is active
            if isShiftActive, let shiftLabel = keyDef.shiftLabel {
                return shiftLabel
            }

            return keyDef.label
        }

        // Fallback for keys not in layout definition
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
            // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
            let isPressed = keyboardManager.activeModifiers.contains(key) || keyboardManager.lockedModifiers.contains(key)
            landscapeKeyContent(for: key, displayText: keyLabel)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isPressed ? themeManager.accentColor : keyBackground(for: key, pressed: false, active: false))
                .cornerRadius(9)
                .foregroundColor(isPressed ? Self.keyLabelPressed : Self.keyLabelIdle)
        } else if key == "Caps" {
            // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
            landscapeKeyContent(for: key, displayText: keyLabel)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(keyBackground(for: key, pressed: isCapsActive, active: isCapsActive))
                .cornerRadius(9)
                .foregroundColor(isCapsActive ? Self.keyLabelPressed : Self.keyLabelIdle)
        } else {
            // Visual-only: touch handled by MultiTouchKeyboardContainer overlay
            let isPressed = keyboardManager.isKeyPressed(key)
            landscapeKeyContent(for: key, displayText: keyLabel)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(keyBackground(for: key, pressed: isPressed, active: false))
                .cornerRadius(9)
                .foregroundColor(isPressed ? Self.keyLabelPressed : Self.keyLabelIdle)
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
        // Use layout definition if available
        if let keyDef = keyDefinition(for: key) {
            return keyDef.label
        }
        // Fallback
        let specialKeys = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Space", "Backspace"]
        if specialKeys.contains(key) { return key }
        if key.count == 1 && key.first!.isLetter { return key.uppercased() }
        return key
    }

    private func landscapeDisplayValue(for key: String) -> String {
        // Use layout definition if available
        if let keyDef = keyDefinition(for: key) {
            let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
            let isCapsActive = keyboardManager.capsLockActive
            let isAltGrActive = keyboardManager.isAltGrActive

            // AltGr layer takes precedence over the base letter cap.
            if isAltGrActive, let altGrLabel = keyDef.altGrLabel {
                return altGrLabel
            }

            if key.count == 1 && key.first!.isLetter {
                let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
                return shouldBeUppercase ? key.uppercased() : key.lowercased()
            }

            if isShiftActive, let shiftLabel = keyDef.shiftLabel {
                return shiftLabel
            }

            return keyDef.label
        }

        // Fallback
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

    // MARK: - Multi-touch support

    /// Build a KeyboardLayoutDescription from the current keyboard layout and container size.
    /// This mirrors the SwiftUI layout math so the touch container's key frames match the visual positions.
    private func buildLayoutDescription(for size: CGSize, isWindowsLayout: Bool) -> KeyboardLayoutDescription {
        // Use the new layout system from KeyboardLayoutManager
        let layout = layoutManager.currentLayout
        return layout.toLayoutDescription(containerSize: size)
    }

    /// Map key names to their KeyType for the touch container.
    /// Uses the layout's keyTypeResolver for accurate type information.
    private func keyType(for keyName: String) -> KeyType {
        return layoutManager.currentLayout.keyTypeResolver()(keyName)
    }

    /// Resolve the layout's authoritative HID usage ID for an on-screen key.
    private func hidUsageID(for keyName: String) -> HIDUsageID? {
        keyboardManager.hidUsageID(forKey: keyName)
    }

    // MARK: - Multi-touch event handlers

    private func handleMultiTouchPress(keyName: String, keyType: KeyType) {
        switch keyType {
        case .modifier:
            let prefs = KmBasicKeyboardPrefs.shared
            switch prefs.modifierBehavior {
            case .sticky:
                break // Toggle fires on release
            case .momentaryChord:
                if prefs.chordSustainHid, let hid = hidUsageID(for: keyName) {
                    keyboardManager.handleKeyDown(hid: hid)
                } else {
                    keyboardManager.addModifierTrackedOnly(keyName)
                }
            }
        case .regular:
            if isFnKey(keyName) {
                keyboardManager.setFnPressed(true)
                return
            }
            // F5/F6 adjust keyboard backlight level locally for dynamic icons
            if !keyboardManager.isFnPressed {
                if keyName == "F5" {
                    keyboardBacklightLevel = max(0, keyboardBacklightLevel - 1)
                } else if keyName == "F6" {
                    keyboardBacklightLevel = min(2, keyboardBacklightLevel + 1)
                }
            }
            // F1-F4 send Apple function row reports when Fn is not pressed.
            // Firmware CMD=0x03 Report ID 0x03 maps to Consumer page Apple usages.
            if !keyboardManager.isFnPressed,
               let appleBitmap = appleFnBitmap(for: keyName) {
                keyboardManager.sendAppleFnKey(bitmap: appleBitmap)
                return
            }
            // F7-F12 send Consumer page media keys when Fn is not pressed.
            // Consumer page is standard USB HID — works for any target OS.
            if !keyboardManager.isFnPressed,
               let mediaBitmap = mediaKeyBitmap(for: keyName) {
                keyboardManager.sendMediaKey(bitmap: mediaBitmap)
                return
            }
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            guard let hid = hidUsageID(for: keyName) else { return }
            if repeatMode {
                keyboardManager.startKeyRepeat(hid: hid)
            } else {
                keyboardManager.handleKeyDown(hid: hid)
            }
        case .special:
            keyboardManager.handleSpecialKey(keyName)
        case .japaneseSpecial:
            // Japanese special keys (変換, 無変換, ひらがな) are ordinary HID keys.
            guard let hid = hidUsageID(for: keyName) else { return }
            keyboardManager.handleKeyDown(hid: hid)
        }
    }

    private func handleMultiTouchRelease(keyName: String, keyType: KeyType) {
        switch keyType {
        case .modifier:
            let prefs = KmBasicKeyboardPrefs.shared
            switch prefs.modifierBehavior {
            case .sticky:
                // Tap-toggle
                if keyboardManager.lockedModifiers.contains(keyName) {
                    keyboardManager.unlockModifier(keyName)
                } else {
                    keyboardManager.lockModifier(keyName)
                }
            case .momentaryChord:
                guard let hid = hidUsageID(for: keyName) else { return }
                keyboardManager.handleKeyUp(hid: hid)
            }
        case .regular:
            if isFnKey(keyName) {
                keyboardManager.setFnPressed(false)
                return
            }
            // Apple function row (F1-F4) and media keys (F7-F12) were already
            // press+released on key down; skip release
            if !keyboardManager.isFnPressed,
               appleFnBitmap(for: keyName) != nil || mediaKeyBitmap(for: keyName) != nil {
                return
            }
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            guard let hid = hidUsageID(for: keyName) else { return }
            if repeatMode {
                keyboardManager.stopKeyRepeat()
            } else {
                keyboardManager.handleKeyUp(hid: hid)
            }
        case .special:
            break // Caps has no release behavior
        case .japaneseSpecial:
            guard let hid = hidUsageID(for: keyName) else { return }
            keyboardManager.handleKeyUp(hid: hid)
        }
    }

    private func handleMultiTouchMoved(point: CGPoint, keyName: String) {
        // Slide-to-lock detection for modifier keys in momentary-chord mode.
        // Placeholder — full implementation needs lock icon position which
        // depends on the visual layout of each modifier key.
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
                    keyboardManager.handleKeyDown(KeyboardLayoutManager.shared.hidKeyName(for: key))
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
                keyboardManager.handleKeyUp(KeyboardLayoutManager.shared.hidKeyName(for: key))
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
                keyboardManager.handleKeyUp(KeyboardLayoutManager.shared.hidKeyName(for: key))
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
