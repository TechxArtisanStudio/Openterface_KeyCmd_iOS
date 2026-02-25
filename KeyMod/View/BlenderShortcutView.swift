//
//  BlenderShortcutView.swift
//  KeyMod
//
//  Created by System on 2025/6/22.
//

import SwiftUI

struct BlenderShortcut {
    let key: String
    let modifier: String?
    let description: String
    let category: String
}

struct BlenderShortcutView: View {
    @StateObject private var keyboardManager: KeyboardManager
    
    init(keyboardManager: KeyboardManager) {
        _keyboardManager = StateObject(wrappedValue: keyboardManager)
    }
    
    let shortcuts: [BlenderShortcut] = [
        // Transform
        BlenderShortcut(key: "G", modifier: nil, description: "Move", category: "Transform"),
        BlenderShortcut(key: "R", modifier: nil, description: "Rotate", category: "Transform"),
        BlenderShortcut(key: "S", modifier: nil, description: "Scale", category: "Transform"),
        BlenderShortcut(key: "E", modifier: nil, description: "Extrude", category: "Transform"),
        
        // Selection
        BlenderShortcut(key: "A", modifier: nil, description: "Select all", category: "Selection"),
        BlenderShortcut(key: "L", modifier: "Alt", description: "Select linked", category: "Selection"),
        BlenderShortcut(key: "L", modifier: "Ctrl", description: "Select linked all", category: "Selection"),
        BlenderShortcut(key: "🖱", modifier: "Ctrl", description: "Select shortest path", category: "Selection"),
        BlenderShortcut(key: "🖱", modifier: "Alt", description: "Select loop", category: "Selection"),
        BlenderShortcut(key: "🖱", modifier: "Ctrl+Alt", description: "Select ring", category: "Selection"),
        BlenderShortcut(key: "Shift", modifier: nil, description: "Accumulate selection", category: "Selection"),
        BlenderShortcut(key: "I", modifier: "Ctrl", description: "Invert selection", category: "Selection"),
        BlenderShortcut(key: "C", modifier: nil, description: "Circle select", category: "Selection"),
        BlenderShortcut(key: "+", modifier: "Ctrl", description: "Grow selection", category: "Selection"),
        BlenderShortcut(key: "-", modifier: "Ctrl", description: "Shrink selection", category: "Selection"),
        
        // Mode & Editing
        BlenderShortcut(key: "Tab", modifier: nil, description: "Edit mode ↔ Object mode", category: "Mode"),
        BlenderShortcut(key: "X", modifier: nil, description: "Delete", category: "Edit"),
        BlenderShortcut(key: "1", modifier: nil, description: "Vertex", category: "Component"),
        BlenderShortcut(key: "2", modifier: nil, description: "Edge", category: "Component"),
        BlenderShortcut(key: "3", modifier: nil, description: "Face", category: "Component"),
        
        // View
        BlenderShortcut(key: "7", modifier: nil, description: "Top", category: "View"),
        BlenderShortcut(key: "1", modifier: nil, description: "Front", category: "View"),
        BlenderShortcut(key: "3", modifier: nil, description: "Right", category: "View"),
        BlenderShortcut(key: "9", modifier: nil, description: "Opposite", category: "View"),
        BlenderShortcut(key: "0", modifier: nil, description: "Camera view", category: "View"),
        BlenderShortcut(key: "F3", modifier: nil, description: "Search function", category: "Tools"),
        
        // Object Operations
        BlenderShortcut(key: "M", modifier: nil, description: "Merge", category: "Mesh"),
        BlenderShortcut(key: "R", modifier: "Ctrl", description: "Loop cut", category: "Mesh"),
        BlenderShortcut(key: "F", modifier: nil, description: "Create face", category: "Mesh"),
        BlenderShortcut(key: "D", modifier: "Alt", description: "Duplicate", category: "Object"),
        BlenderShortcut(key: "B", modifier: "Ctrl", description: "Bevel", category: "Mesh"),
        BlenderShortcut(key: "W", modifier: "Shift", description: "Bend", category: "Mesh"),
        BlenderShortcut(key: "V", modifier: nil, description: "Rip", category: "Mesh"),
        BlenderShortcut(key: "I", modifier: nil, description: "Inset faces", category: "Mesh"),
        BlenderShortcut(key: "K", modifier: nil, description: "Knife", category: "Mesh"),
        
        // Viewport
        BlenderShortcut(key: "T", modifier: nil, description: "Toggle toolbar menu (left)", category: "UI"),
        BlenderShortcut(key: "N", modifier: nil, description: "Toggle sidebar menu (right)", category: "UI"),
        BlenderShortcut(key: "N", modifier: "Shift", description: "Recalculate normals", category: "Mesh"),
        BlenderShortcut(key: "Z", modifier: "Alt", description: "Toggle X-Ray", category: "View"),
        BlenderShortcut(key: "P", modifier: nil, description: "Separate selection", category: "Object"),
        BlenderShortcut(key: "J", modifier: "Ctrl", description: "Join objects", category: "Object"),
        
        // Camera & Navigation
        BlenderShortcut(key: "+", modifier: nil, description: "Zoom in", category: "Navigation"),
        BlenderShortcut(key: "-", modifier: nil, description: "Zoom out", category: "Navigation"),
        BlenderShortcut(key: "C", modifier: "Shift", description: "Reset cursor to origin", category: "Navigation"),
        BlenderShortcut(key: "🖱", modifier: "Shift", description: "Place cursor", category: "Navigation"),
        BlenderShortcut(key: "🖱", modifier: "Shift", description: "Drag view position", category: "Navigation"),
        BlenderShortcut(key: "R", modifier: "Shift", description: "Repeat last action", category: "Tools"),
        
        // Materials & Shading
        BlenderShortcut(key: "Z", modifier: nil, description: "Shading pie menu", category: "Shading"),
        BlenderShortcut(key: "U", modifier: nil, description: "UV Mapping menu", category: "UV"),
        BlenderShortcut(key: "F", modifier: nil, description: "Connect nodes", category: "Shading"),
        BlenderShortcut(key: "T", modifier: "Ctrl", description: "Add Texture Setup", category: "Shading"),
        BlenderShortcut(key: "T", modifier: "Ctrl+Shift", description: "Add Principled Setup", category: "Shading"),
        
        // Animation
        BlenderShortcut(key: "I", modifier: nil, description: "Add keyframe on frame", category: "Animation"),
        BlenderShortcut(key: "0", modifier: "Ctrl+Alt", description: "Set camera", category: "Animation")
    ]
    
    @State private var selectedCategory = "All"
    
    private var categories: [String] {
        let allCategories = Set(shortcuts.map { $0.category })
        return ["All"] + Array(allCategories).sorted()
    }
    
    private var filteredShortcuts: [BlenderShortcut] {
        if selectedCategory == "All" {
            return shortcuts
        } else {
            return shortcuts.filter { $0.category == selectedCategory }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Half - Shortcuts Section
                VStack(spacing: 0) {
                    // Header with Blender logo styling
                    HStack {
                        Image(systemName: "cube.box.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Blender Shortcuts")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Beginners Cheat Sheet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(Color(UIColor.systemBackground))
                    
                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                }) {
                                    Text(category)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            selectedCategory == category ? 
                                            Color.orange : Color(UIColor.secondarySystemBackground)
                                        )
                                        .foregroundColor(
                                            selectedCategory == category ? .white : .primary
                                        )
                                        .cornerRadius(15)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 6)
                    
                    // Shortcuts Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ], spacing: 8) {
                            ForEach(Array(filteredShortcuts.enumerated()), id: \.offset) { index, shortcut in
                                CompactShortcutCard(shortcut: shortcut, keyboardManager: keyboardManager)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .frame(height: geometry.size.height * 0.5)
                .background(Color(UIColor.systemGroupedBackground))
                
                // Divider
                Divider()
                    .background(Color.orange.opacity(0.5))
                
                // Bottom Half - Numpad Viewport
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "grid.circle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Viewport Numpad")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(Color(UIColor.systemBackground))
                    
                    BlenderNumPadView(keyboardManager: keyboardManager)
                }
                .frame(height: geometry.size.height * 0.5)
                .background(Color(UIColor.systemBackground))
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct ShortcutCard: View {
    let shortcut: BlenderShortcut
    let keyboardManager: KeyboardManager
    @State private var isPressed = false
    
    private var categoryColor: Color {
        switch shortcut.category {
        case "Transform":
            return .blue
        case "Selection":
            return .green
        case "View":
            return .purple
        case "Edit", "Mesh":
            return .red
        case "Mode":
            return .orange
        case "Component":
            return .yellow
        case "Object":
            return .pink
        case "Tools":
            return .indigo
        case "UI":
            return .teal
        case "Navigation":
            return .mint
        case "Shading", "UV":
            return .brown
        case "Animation":
            return .cyan
        default:
            return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category badge
            HStack {
                Text(shortcut.category)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.2))
                    .foregroundColor(categoryColor)
                    .cornerRadius(4)
                Spacer()
            }
            
            // Key combination - Now clickable
            Button(action: {
                executeShortcut()
            }) {
                HStack {
                    if let modifier = shortcut.modifier {
                        ForEach(modifier.components(separatedBy: "+"), id: \.self) { mod in
                            ClickableKeyView(key: mod.trimmingCharacters(in: .whitespaces), isModifier: true, isPressed: isPressed)
                        }
                        Text("+")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ClickableKeyView(key: shortcut.key, isModifier: false, isPressed: isPressed)
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            
            // Description
            Text(shortcut.description)
                .font(.caption)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func executeShortcut() {
        isPressed = true
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Execute the shortcut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPressed = false
            
            // Parse and send the shortcut
            if let modifier = shortcut.modifier {
                let modifiers = modifier.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
                let mainKey = convertKeyToKeyboardManagerFormat(shortcut.key)
                
                // Skip mouse actions
                if mainKey == "🖱" {
                    return
                }
                
                // Send key combination
                keyboardManager.handleKeyCombo(modifiers: modifiers, key: mainKey)
            } else {
                // Just send the main key
                let mainKey = convertKeyToKeyboardManagerFormat(shortcut.key)
                
                // Skip mouse actions
                if mainKey == "🖱" {
                    return
                }
                
                keyboardManager.handleKeyPress(mainKey)
            }
        }
    }
    
    private func convertKeyToKeyboardManagerFormat(_ key: String) -> String {
        // Convert key to format expected by KeyboardManager
        switch key.lowercased() {
        case "🖱":
            return "🖱" // Skip mouse actions
        case "space":
            return "Space"
        case "tab":
            return "Tab"
        case "enter", "return":
            return "Enter"
        case "escape", "esc":
            return "Escape"
        case "backspace":
            return "Backspace"
        case "delete":
            return "Delete"
        case "+":
            return "+"
        case "-":
            return "-"
        case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12":
            return key.uppercased()
        default:
            // For regular keys, return uppercase
            return key.uppercased()
        }
    }
}

struct CompactShortcutCard: View {
    let shortcut: BlenderShortcut
    let keyboardManager: KeyboardManager
    @State private var isPressed = false
    
    private var categoryColor: Color {
        switch shortcut.category {
        case "Transform":
            return .blue
        case "Selection":
            return .green
        case "View":
            return .purple
        case "Edit", "Mesh":
            return .red
        case "Mode":
            return .orange
        case "Component":
            return .yellow
        case "Object":
            return .pink
        case "Tools":
            return .indigo
        case "UI":
            return .teal
        case "Navigation":
            return .mint
        case "Shading", "UV":
            return .brown
        case "Animation":
            return .cyan
        default:
            return .gray
        }
    }
    
    var body: some View {
        Button(action: {
            executeShortcut()
        }) {
            VStack(spacing: 4) {
                // Key combination
                HStack(spacing: 2) {
                    if let modifier = shortcut.modifier {
                        ForEach(modifier.components(separatedBy: "+"), id: \.self) { mod in
                            CompactKeyView(key: mod.trimmingCharacters(in: .whitespaces), isModifier: true, isPressed: isPressed)
                        }
                        Text("+")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    CompactKeyView(key: shortcut.key, isModifier: false, isPressed: isPressed)
                }
                
                // Description
                Text(shortcut.description)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                // Category indicator
                Rectangle()
                    .fill(categoryColor)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
            .padding(6)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func executeShortcut() {
        isPressed = true
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Execute the shortcut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPressed = false
            
            // Parse and send the shortcut
            if let modifier = shortcut.modifier {
                let modifiers = modifier.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
                let mainKey = convertKeyToKeyboardManagerFormat(shortcut.key)
                
                // Skip mouse actions
                if mainKey == "🖱" {
                    return
                }
                
                // Send key combination
                keyboardManager.handleKeyCombo(modifiers: modifiers, key: mainKey)
            } else {
                // Just send the main key
                let mainKey = convertKeyToKeyboardManagerFormat(shortcut.key)
                
                // Skip mouse actions
                if mainKey == "🖱" {
                    return
                }
                
                keyboardManager.handleKeyPress(mainKey)
            }
        }
    }
    
    private func convertKeyToKeyboardManagerFormat(_ key: String) -> String {
        // Convert key to format expected by KeyboardManager
        switch key.lowercased() {
        case "🖱":
            return "🖱" // Skip mouse actions
        case "space":
            return "Space"
        case "tab":
            return "Tab"
        case "enter", "return":
            return "Enter"
        case "escape", "esc":
            return "Escape"
        case "backspace":
            return "Backspace"
        case "delete":
            return "Delete"
        case "+":
            return "+"
        case "-":
            return "-"
        case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12":
            return key.uppercased()
        default:
            // For regular keys, return uppercase
            return key.uppercased()
        }
    }
}

struct CompactKeyView: View {
    let key: String
    let isModifier: Bool
    let isPressed: Bool
    
    var body: some View {
        Text(key)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                isPressed ? 
                (isModifier ? Color.orange.opacity(0.6) : Color.blue.opacity(0.6)) :
                (isModifier ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8))
            )
            .foregroundColor(.white)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: isPressed ? 1 : 0)
            )
    }
}

struct ClickableKeyView: View {
    let key: String
    let isModifier: Bool
    let isPressed: Bool
    
    var body: some View {
        Text(key)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isPressed ? 
                (isModifier ? Color.orange.opacity(0.6) : Color.blue.opacity(0.6)) :
                (isModifier ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8))
            )
            .foregroundColor(.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.3), lineWidth: isPressed ? 2 : 0)
            )
    }
}

// Keep the old KeyView for backward compatibility
struct KeyView: View {
    let key: String
    let isModifier: Bool
    
    var body: some View {
        ClickableKeyView(key: key, isModifier: isModifier, isPressed: false)
    }
}

struct BlenderNumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    
    // Blender-specific viewport numpad layout
    private let blenderKeys: [[BlenderNumKey]] = [
        [BlenderNumKey(display: "7", description: "Top", key: "7"), 
         BlenderNumKey(display: "8", description: "↑", key: "Up"), 
         BlenderNumKey(display: "9", description: "Opposite", key: "9"),
         BlenderNumKey(display: "+", description: "Zoom In", key: "+")],
        [BlenderNumKey(display: "4", description: "←", key: "Left"),
         BlenderNumKey(display: "5", description: "Orthographic", key: "5"),
         BlenderNumKey(display: "6", description: "→", key: "Right"),
         BlenderNumKey(display: "-", description: "Zoom Out", key: "-")],
        [BlenderNumKey(display: "1", description: "Front", key: "1"),
         BlenderNumKey(display: "2", description: "↓", key: "Down"), 
         BlenderNumKey(display: "3", description: "Right View", key: "3"),
         BlenderNumKey(display: "G", description: "Move", key: "G")],
        [BlenderNumKey(display: "0", description: "Camera", key: "0"), 
         BlenderNumKey(display: ".", description: "Focus", key: "."), 
         BlenderNumKey(display: "/", description: "Isolate", key: "/"),
         BlenderNumKey(display: "*", description: "Global", key: "*")]
    ]
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 16 // Account for outer padding
            let availableHeight = geometry.size.height - 16 // Account for outer padding
            let keyWidth = (availableWidth - 12) / 4 // 4 columns with 3 gaps of 4 points each
            let keyHeight = (availableHeight - 12) / 4 // 4 rows with 3 gaps of 4 points each
            
            VStack(spacing: 4) {
                ForEach(0..<blenderKeys.count, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<blenderKeys[row].count, id: \.self) { col in
                            BlenderNumButton(
                                key: blenderKeys[row][col],
                                keyboardManager: keyboardManager,
                                width: keyWidth,
                                height: keyHeight
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
    }
}

struct BlenderNumKey {
    let display: String
    let description: String
    let key: String
}

struct BlenderNumButton: View {
    let key: BlenderNumKey
    let keyboardManager: KeyboardManager
    let width: CGFloat
    let height: CGFloat
    @State private var isPressed = false
    
    private var buttonColor: Color {
        switch key.key {
        case "Up", "Down", "Left", "Right":
            return .blue.opacity(0.8)
        case "1", "3", "7", "9":
            return .orange.opacity(0.8)
        case "/":
            return .purple.opacity(0.8)
        case "+", "-":
            return .green.opacity(0.8)
        case "0":
            return .red.opacity(0.8)
        case "G":
            return .cyan.opacity(0.8)
        default:
            return .gray.opacity(0.6)
        }
    }
    
    var body: some View {
        Button(action: {
            executeKey()
        }) {
            VStack(spacing: 2) {
                Text(key.display)
                    .font(.system(size: min(width, height) * 0.25, weight: .bold))
                    .foregroundColor(.white)
                
                Text(key.description)
                    .font(.system(size: min(width, height) * 0.12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(buttonColor)
                    .shadow(color: .black.opacity(0.2), radius: isPressed ? 1 : 3, x: 0, y: isPressed ? 1 : 2)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func executeKey() {
        isPressed = true
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPressed = false
            
            // Send the appropriate numpad key based on the key type
            switch key.key {
            case "Up":
                keyboardManager.handleKeyPress("Numpad8")
            case "Down":
                keyboardManager.handleKeyPress("Numpad2")
            case "Left":
                keyboardManager.handleKeyPress("Numpad4")
            case "Right":
                keyboardManager.handleKeyPress("Numpad6")
            case "0":
                keyboardManager.handleKeyPress("Numpad0")
            case "1":
                keyboardManager.handleKeyPress("Numpad1")
            case "2":
                keyboardManager.handleKeyPress("Numpad2")
            case "3":
                keyboardManager.handleKeyPress("Numpad3")
            case "4":
                keyboardManager.handleKeyPress("Numpad4")
            case "5":
                keyboardManager.handleKeyPress("Numpad5")
            case "6":
                keyboardManager.handleKeyPress("Numpad6")
            case "7":
                keyboardManager.handleKeyPress("Numpad7")
            case "8":
                keyboardManager.handleKeyPress("Numpad8")
            case "9":
                keyboardManager.handleKeyPress("Numpad9")
            case ".":
                keyboardManager.handleKeyPress("NumpadDot")
            case "/":
                keyboardManager.handleKeyPress("NumpadSlash")
            case "*":
                keyboardManager.handleKeyPress("NumpadAsterisk")
            case "-":
                keyboardManager.handleKeyPress("NumpadMinus")
            case "+":
                keyboardManager.handleKeyPress("NumpadPlus")
            default:
                // For other keys like 'G', send as regular key
                keyboardManager.handleKeyPress(key.key)
            }
        }
    }
}

#Preview {
    let bleManager = BLEManager()
    let keyboardManager = KeyboardManager(bleManager: bleManager)
    return BlenderShortcutView(keyboardManager: keyboardManager)
}
