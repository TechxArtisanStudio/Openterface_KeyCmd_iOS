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

    enum Submode: String, CaseIterable {
        case keyboard = "Keyboard"
        case touchpad = "Touchpad"
        case numpad = "Numpad"
    }

    @State private var selectedSubmode: Submode = .keyboard

    // Landscape keyboard rows matching Android keyboard_lower_landscape.xml
    let landscapeKeys: [[String]] = [
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // MARK: - Top scrollable tab bar (matches Android km_basic_host_chrome.xml)
                tabBar

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                print("🔵 [BasicKeyboardMouseView] Appeared — size: \(geometry.size.width) x \(geometry.size.height), submode: \(selectedSubmode.rawValue)")
            }
            .onChange(of: selectedSubmode) { new in
                print("🔵 [BasicKeyboardMouseView] Submode changed to: \(new.rawValue)")
            }
            .onChange(of: geometry.size) { newSize in
                print("🔵 [BasicKeyboardMouseView] Geometry changed: \(newSize.width) x \(newSize.height)")
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

    // MARK: - Landscape Keyboard Submode

    @ViewBuilder
    private var landscapeKeyboardSubmode: some View {
        GeometryReader { innerGeometry in
            VStack(spacing: 0) {
                ForEach(landscapeKeys, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { key in
                            landscapeKeyButton(key: key)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Landscape Key Buttons

    @ViewBuilder
    private func landscapeKeyButton(key: String) -> some View {
        let displayText = landscapeDisplayValue(for: key)
        let isModifier = ["Ctrl", "Alt", "Cmd", "Win", "Shift"].contains(key)
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

    private func keyBackground(for key: String, pressed: Bool, active: Bool) -> Color {
        let functionLabels = ["Esc", "Tab", "Caps", "Shift", "Ctrl", "Alt", "Backspace", "Enter"]
        if pressed || active { return .blue }
        if functionLabels.contains(key) { return Self.functionKeyBg }
        return Self.regularKeyBg
    }

    // MARK: - Touchpad Submode

    private var touchpadSubmode: some View {
        VStack(spacing: 0) {
            // Touchpad + scroll strip (weight 5)
            HStack(spacing: 0) {
                TouchpadView(mouseManager: mouseManager, pointerTipState: PointerTipState())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BasicTouchpadScrollStripView(mouseManager: mouseManager)
                    .frame(width: 28)
            }
            .frame(maxHeight: .infinity)

            // Mouse buttons row (weight 2)
            HStack(spacing: 8) {
                mouseButton(label: "L", icon: "cursorarrow", button: .left)
                    .frame(maxWidth: .infinity)
                mouseButton(label: "M", icon: "cursorarrow", button: .middle)
                    .frame(maxWidth: .infinity)
                mouseButton(label: "R", icon: "cursorarrow", button: .right)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
            Image(systemName: icon)
                .font(.system(size: 16))
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
        NumPadView(keyboardManager: keyboardManager)
    }
}
