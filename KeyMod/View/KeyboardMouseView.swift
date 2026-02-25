//
//  KeyboardMouseView.swift
//  KeyMod
//
//  Created by System on 2025/6/21.
//

import SwiftUI
import UIKit

struct KeyboardMouseView: View {
    let keys: [[String]] = [
        ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
        ["Esc", "`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["Caps", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "Enter"],
        ["Shift", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Shift"],
        ["Ctrl", "Alt", "Space", "Alt", "Ctrl"]
    ]

    // Extra keys for 101-key layout, arranged as on a real keyboard
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
        // Special keys that don't change
        let specialKeys = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", 
                          "Tab", "Caps", "Enter", "Shift", "Ctrl", "Alt", "Space", "Backspace"]
        
        if specialKeys.contains(key) {
            return key
        }
        
        let isShiftActive = keyboardManager.activeModifiers.contains("Shift")
        let isCapsActive = keyboardManager.capsLockActive
        
        // For letters
        if key.count == 1 && key.first!.isLetter {
            let shouldBeUppercase = (isShiftActive && !isCapsActive) || (!isShiftActive && isCapsActive)
            return shouldBeUppercase ? key.uppercased() : key.lowercased()
        }
        
        // For numbers and symbols with shift variants
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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Conditional layout based on orientation
                if orientationManager.isLandscape {
                    if displayMode == .touchpad {
                        // Touchpad only mode: occupy all screen area, but show toggle button and tips overlay
                        ZStack {
                            HStack(spacing: 0) {
                                // Main touchpad area, leave space for toggle button
                                TouchpadView(mouseManager: mouseManager)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                // Reserve space for toggle button
                                Color.clear.frame(width: 48)
                            }
                            Rectangle()
                                .foregroundColor(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
                                .allowsHitTesting(false)
                            // Overlay: Title and tips at the center
                            VStack(alignment: .center, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Touch Pad")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if mouseManager.isSelectMode {
                                        Text("Drag Mode ON")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Single tap → Click")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Double tap → Double click")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Two finger tap → Right click")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Two finger drag → Scroll")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Long press → Toggle drag mode")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(20)
                            .background(Color.clear)
                            .cornerRadius(12)
                            .shadow(radius: 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            // Toggle button (handle) on the right edge, vertically centered
                            HStack {
                                Spacer()
                                VStack {
                                    Spacer()
                                    Button(action: { displayMode.toggle() }) {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.5))
                                            .frame(width: 4, height: 48)
                                            .cornerRadius(2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(width: 36, height: 60)
                                    Spacer()
                                }
                            }
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
                                        
                                        VStack {
                                            Text("Touch Pad")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            if mouseManager.isSelectMode {
                                                Text("Drag Mode ON")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                            VStack(spacing: 2) {
                                                Text("Single tap → Click")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text("Double tap → Double click")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text("Two finger tap → Right click")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text("Two finger drag → Scroll")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                Text("Long press → Toggle drag mode")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        TouchpadView(mouseManager: mouseManager)
                                    }
                                    .frame(maxHeight: .infinity)
                                }
                                .frame(maxWidth: geometry.size.width * 0.3)
                            }
                            // Handle between touchpad and keyboard
                            VStack {
                                Spacer()
                                // Replace the handle button with two vertical grey lines as a tappable area
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.5))
                                        .frame(width: 4, height: 28)
                                        .cornerRadius(2)
                                    Spacer(minLength: 2)
                                }
                                .frame(width: 24)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    displayMode.toggle()
                                }
                            }
                            .frame(width: 36)
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
                                                                            .background(Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
                                                                            .foregroundColor(.primary)
                                                                    } else if key == "Enter" {
                                                                        Image(systemName: "return")
                                                                            .font(.system(size: 16))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
                                                                            .foregroundColor(.primary)
                                                                    } else if key == "Shift" {
                                                                        Image(systemName: "shift")
                                                                            .font(.system(size: 16))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.activeModifiers.contains("Shift") ? Color.blue : Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
                                                                            .foregroundColor(keyboardManager.activeModifiers.contains("Shift") ? .white : .primary)
                                                                    } else if ["Ctrl", "Alt", "Cmd"].contains(key) {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.activeModifiers.contains(key) ? Color.blue : Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
                                                                            .foregroundColor(keyboardManager.activeModifiers.contains(key) ? .white : .primary)
                                                                    } else if key == "Caps" {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(keyboardManager.capsLockActive ? Color.green : Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
                                                                            .foregroundColor(keyboardManager.capsLockActive ? .white : .primary)
                                                                    } else {
                                                                        Text(getDisplayValue(for: key))
                                                                            .font(.system(size: 12))
                                                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                                            .background(Color(UIColor.secondarySystemBackground))
                                                                            .cornerRadius(5)
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
                    VStack(spacing: 0) {
                        if displayMode != .keyboard {
                            ZStack {
                                Rectangle()
                                    .foregroundColor(mouseManager.isSelectMode ? Color.blue.opacity(0.3) : Color(UIColor.tertiarySystemBackground))
                                
                                VStack {
                                    Text("Touch Pad")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if mouseManager.isSelectMode {
                                        Text("Drag Mode ON")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    VStack(spacing: 2) {
                                        Text("Single tap → Click")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("Double tap → Double click")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("Two finger tap → Right click")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("Two finger drag → Scroll")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("Long press → Toggle drag mode")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                TouchpadView(mouseManager: mouseManager)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        // Handle between touchpad and keyboard (portrait)
                        HStack {
                            Spacer()
                            // Portrait handle
                            VStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 28, height: 4)
                                    .cornerRadius(2)
                            }
                            .frame(height: 24)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                displayMode.toggle()
                            }
                            Spacer()
                        }
                        .frame(height: 36)
                        if displayMode != .touchpad {
                            // Quick action shortcuts - scrollable
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // Get popular shortcuts from CompositeKeyManager
                                    ForEach(compositeKeyManager.getPopularShortcuts(), id: \.id) { shortcut in
                                        Button(shortcut.displayName) {
                                            compositeKeyManager.executeShortcut(shortcut.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    }
                                    
                                    // System shortcuts
                                    Button("Alt+F4") { compositeKeyManager.altF4() }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    Button("Ctrl+Alt+Del") { compositeKeyManager.ctrlAltDel() }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    Button("Win+L") { compositeKeyManager.winL() }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    Button("Win+D") { compositeKeyManager.winD() }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    
                                    // Additional shortcuts from different categories
                                    ForEach(compositeKeyManager.getShortcuts(for: .file).prefix(3), id: \.id) { shortcut in
                                        Button(shortcut.displayName) {
                                            compositeKeyManager.executeShortcut(shortcut.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    }
                                    
                                    ForEach(compositeKeyManager.getShortcuts(for: .editing).prefix(2), id: \.id) { shortcut in
                                        Button(shortcut.displayName) {
                                            compositeKeyManager.executeShortcut(shortcut.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                    }
                                    
                                    // Clear button at the end
                                    Button("Clear") { compositeKeyManager.clearModifiers() }
                                        .buttonStyle(.bordered)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 10)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(UIColor.secondarySystemBackground))

                            // Keyboard layout
                            keyboardLayoutView
                                .frame(height: 240)
                                .padding(.bottom, 10)
                            // Show extra keys only in keyboard-only mode and only in portrait
                            if displayMode == .keyboard && !orientationManager.isLandscape {
                                extraKeysView
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
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

    // Helper to get keys with F1-F12 hidden in landscape
    var keysForCurrentOrientation: [[String]] {
        if orientationManager.isLandscape {
            // Remove F1-F12 row
            return Array(keys.dropFirst(1))
        } else {
            return keys
        }
    }

    @ViewBuilder
    private var keyboardLayoutView: some View {
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
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(.primary)
                            } else if key == "Enter" {
                                Image(systemName: "return")
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(.primary)
                            } else if key == "Shift" {
                                Image(systemName: "shift")
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(keyboardManager.activeModifiers.contains("Shift") ? Color.blue : Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(keyboardManager.activeModifiers.contains("Shift") ? .white : .primary)
                            } else if ["Ctrl", "Alt", "Cmd"].contains(key) {
                                Text(getDisplayValue(for: key))
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(keyboardManager.activeModifiers.contains(key) ? Color.blue : Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(keyboardManager.activeModifiers.contains(key) ? .white : .primary)
                            } else if key == "Caps" {
                                Text(getDisplayValue(for: key))
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(keyboardManager.capsLockActive ? Color.green : Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(keyboardManager.capsLockActive ? .white : .primary)
                            } else {
                                Text(getDisplayValue(for: key))
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, maxHeight: 50)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(5)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            Spacer()
                        }
                    }
                }
            }
            // Add number pad below direction keys in portrait keyboard-only mode
            if displayMode == .keyboard && !orientationManager.isLandscape {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(extraNumberKeys.prefix(3), id: \.self) { key in
                            Button(action: {
                                let mappedKey: String
                                switch key {
                                case "7": mappedKey = "Numpad7"
                                case "8": mappedKey = "Numpad8"
                                case "9": mappedKey = "Numpad9"
                                default: mappedKey = key
                                }
                                keyboardManager.handleSpecialKey(mappedKey)
                            }) {
                                Text(key)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(extraNumberKeys[3..<6], id: \.self) { key in
                            Button(action: {
                                let mappedKey: String
                                switch key {
                                case "4": mappedKey = "Numpad4"
                                case "5": mappedKey = "Numpad5"
                                case "6": mappedKey = "Numpad6"
                                default: mappedKey = key
                                }
                                keyboardManager.handleSpecialKey(mappedKey)
                            }) {
                                Text(key)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(extraNumberKeys[6..<9], id: \.self) { key in
                            Button(action: {
                                let mappedKey: String
                                switch key {
                                case "1": mappedKey = "Numpad1"
                                case "2": mappedKey = "Numpad2"
                                case "3": mappedKey = "Numpad3"
                                default: mappedKey = key
                                }
                                keyboardManager.handleSpecialKey(mappedKey)
                            }) {
                                Text(key)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        Button(action: { keyboardManager.handleSpecialKey("Numpad0") }) {
                            Text("0")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .foregroundColor(.primary)
                        }
                        Button(action: { keyboardManager.handleSpecialKey("NumpadDot") }) {
                            Text(".")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }
}
