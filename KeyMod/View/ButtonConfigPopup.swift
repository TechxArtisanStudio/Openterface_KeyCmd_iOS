//
//  ButtonConfigPopup.swift
//  KeyMod
//
//  Created by System on 2025/7/16.
//

import SwiftUI

struct ButtonConfigPopup: View {
    let layout: GamepadLayout
    let buttonName: String
    @ObservedObject var configManager: GamepadConfigManager
    @Binding var isPresented: Bool
    
    @State private var selectedKey: String = ""
    @State private var customKey: String = ""
    @State private var isCustomKeyMode: Bool = false
    @State private var selectedMouseAction: String = ""
    
    // Analog stick configuration states
    @State private var isAnalogStick: Bool = false
    @State private var analogStickKeys = (up: "", down: "", left: "", right: "")
    @State private var selectedDirection: String = "Up"
    
    private let directions = ["Up", "Down", "Left", "Right"]
    
    private let commonKeys = [
        "Space", "Enter", "Escape", "Tab", "Backspace",
        "Shift", "Ctrl", "Alt", "Cmd",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "Up", "Down", "Left", "Right",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]
    
    private let mouseActions = [
        "Left Click", "Right Click", "Double Click", "Drag Toggle", "Scroll Up", "Scroll Down"
    ]
    
    @State private var actionType: ActionType = .keyboard
    
    enum ActionType: String, CaseIterable {
        case keyboard = "Keyboard"
        case mouse = "Mouse"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header - Fixed at top
                VStack(spacing: 10) {
                    Text(buttonName == "RightStick" ? "Right Stick Configuration" : (isAnalogStick ? "Configure Analog Stick" : "Configure Button"))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(buttonName == "RightStick" ? "Mouse Control" : (isAnalogStick ? "Stick: \(buttonName)" : "Button: \(buttonName)"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Layout: \(layout.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 20) {
                        if buttonName == "RightStick" {
                            rightStickConfigurationView()
                        } else if isAnalogStick {
                            // Analog stick configuration UI
                            analogStickConfigurationView()
                        } else {
                            // Regular button configuration UI
                            regularButtonConfigurationView()
                        }
                        
                        // Add some bottom padding for the scrollable content
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons - Fixed at bottom
                VStack(spacing: 12) {
                    // Apply and Cancel buttons in horizontal layout (hide for right stick)
                    if buttonName != "RightStick" {
                        HStack(spacing: 12) {
                            Button(action: {
                                isPresented = false
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            
                            Button(action: applyMapping) {
                                Text("Apply")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(canApply ? Color.blue : Color.gray)
                                    .cornerRadius(12)
                            }
                            .disabled(!canApply)
                        }
                        
                        // Reset button (if applicable) stays full width
                        if (isAnalogStick && buttonName == "LeftStick" && hasAnyCustomAnalogMapping()) || (!isAnalogStick && configManager.getKeyMapping(layout: layout, button: buttonName) != nil) {
                            Button(action: resetToDefault) {
                                Text("Reset to Default")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    } else {
                        // For right stick, just show a close button
                        Button(action: { isPresented = false }) {
                            Text("Close")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            print("🎯 ButtonConfigPopup onAppear for button: '\(buttonName)'")
            // Check if this is an analog stick configuration
            isAnalogStick = buttonName == "LeftStick" || buttonName == "RightStick"
            print("🎯 isAnalogStick: \(isAnalogStick)")
            
            if isAnalogStick && buttonName == "LeftStick" {
                // Initialize analog stick mappings for left stick only
                analogStickKeys = configManager.getAnalogStickKeys(layout: layout, stick: buttonName)
            } else if buttonName == "RightStick" {
                // Right stick is now used for mouse control, no key mappings needed
                // We'll show a different UI for this case
                print("🎯 Right stick - showing mouse control info")
            } else {
                // Initialize with current mapping for regular buttons
                print("🎯 Initializing regular button mapping")
                if let currentMapping = configManager.getKeyMapping(layout: layout, button: buttonName) {
                    print("🎯 Found existing mapping: '\(currentMapping)'")
                    // Check if it's a mouse action
                    if mouseActions.contains(currentMapping) {
                        selectedMouseAction = currentMapping
                        actionType = .mouse
                        print("🎯 Set as mouse action: '\(selectedMouseAction)'")
                    } else if commonKeys.contains(currentMapping) {
                        selectedKey = currentMapping
                        isCustomKeyMode = false
                        actionType = .keyboard
                        print("🎯 Set as common keyboard key: '\(selectedKey)'")
                    } else {
                        customKey = currentMapping
                        isCustomKeyMode = true
                        actionType = .keyboard
                        print("🎯 Set as custom keyboard key: '\(customKey)'")
                    }
                } else {
                    print("🎯 No existing mapping found, using default")
                    // Use default mapping
                    let defaultKey = configManager.getEffectiveKey(layout: layout, button: buttonName)
                    print("🎯 Default key: '\(defaultKey)'")
                    if mouseActions.contains(defaultKey) {
                        selectedMouseAction = defaultKey
                        actionType = .mouse
                        print("🎯 Default is mouse action: '\(selectedMouseAction)'")
                    } else if commonKeys.contains(defaultKey) {
                        selectedKey = defaultKey
                        isCustomKeyMode = false
                        actionType = .keyboard
                        print("🎯 Default is common keyboard key: '\(selectedKey)'")
                    } else {
                        customKey = defaultKey
                        isCustomKeyMode = true
                        actionType = .keyboard
                        print("🎯 Default is custom keyboard key: '\(customKey)'")
                    }
                }
                print("🎯 Final state - actionType: \(actionType.rawValue), selectedMouseAction: '\(selectedMouseAction)', selectedKey: '\(selectedKey)', customKey: '\(customKey)'")
            }
        }
    }
    
    @ViewBuilder
    private func analogStickConfigurationView() -> some View {
        VStack(spacing: 20) {
            // Current mappings display
            VStack(alignment: .leading, spacing: 12) {
                Text("Current Mappings:")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ForEach(directions, id: \.self) { direction in
                        HStack {
                            Text("\(direction):")
                                .frame(width: 50, alignment: .leading)
                                .foregroundColor(.secondary)
                            
                            let currentKey = getCurrentKeyForDirection(direction)
                            Text(currentKey)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            
                            if hasCustomMappingForDirection(direction) {
                                Text("(Custom)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("(Default)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Direction selection and key mapping
            VStack(alignment: .leading, spacing: 15) {
                Text("Configure Direction:")
                    .font(.headline)
                
                // Direction picker
                Picker("Direction", selection: $selectedDirection) {
                    ForEach(directions, id: \.self) { direction in
                        Text(direction).tag(direction)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Key selection for selected direction
                VStack(alignment: .leading, spacing: 15) {
                    Text("Select Key for \(selectedDirection):")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Toggle between preset and custom
                    Picker("Input Mode", selection: $isCustomKeyMode) {
                        Text("Preset Keys").tag(false)
                        Text("Custom Key").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if isCustomKeyMode {
                        // Custom key input
                        TextField("Type key name", text: $customKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        // Preset key grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                            ForEach(commonKeys, id: \.self) { key in
                                Button(action: {
                                    selectedKey = key
                                    updateAnalogStickDirection(selectedDirection, key: key)
                                }) {
                                    Text(key)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(selectedKey == key ? .white : .primary)
                                        .frame(maxWidth: .infinity, minHeight: 35)
                                        .background(selectedKey == key ? Color.blue : Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: selectedDirection) { _ in
            updateSelectedKeyForDirection()
        }
        .onChange(of: customKey) { newValue in
            if isCustomKeyMode && !newValue.isEmpty {
                updateAnalogStickDirection(selectedDirection, key: newValue)
            }
        }
    }
    
    @ViewBuilder
    private func regularButtonConfigurationView() -> some View {
        VStack(spacing: 20) {
            // Current mapping display
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Mapping:")
                    .font(.headline)
                
                HStack {
                    let effectiveMapping = configManager.getEffectiveKey(layout: layout, button: buttonName)
                    let mappingType = mouseActions.contains(effectiveMapping) ? "Mouse Action" : "Key"
                    
                    Text("\(mappingType):")
                        .foregroundColor(.secondary)
                    Text(effectiveMapping)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(mouseActions.contains(effectiveMapping) ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    if configManager.getKeyMapping(layout: layout, button: buttonName) != nil {
                        Text("(Custom)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("(Default)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Key selection
            VStack(alignment: .leading, spacing: 15) {
                Text("Select New Action:")
                    .font(.headline)
                
                // Action type selection (Keyboard vs Mouse)
                Picker("Action Type", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: actionType) { newType in
                    print("🔄 Action type changed to: \(newType.rawValue)")
                    // Clear selections when switching types
                    if newType == .mouse {
                        selectedKey = ""
                        customKey = ""
                        print("🔄 Cleared keyboard selections")
                    } else {
                        selectedMouseAction = ""
                        print("🔄 Cleared mouse selection")
                    }
                }
                
                if actionType == .keyboard {
                    // Keyboard configuration
                    VStack(alignment: .leading, spacing: 15) {
                        // Toggle between preset and custom
                        Picker("Input Mode", selection: $isCustomKeyMode) {
                            Text("Preset Keys").tag(false)
                            Text("Custom Key").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        if isCustomKeyMode {
                            // Custom key input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Enter custom key:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                TextField("Type key name", text: $customKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                        } else {
                            // Preset key grid
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                                ForEach(commonKeys, id: \.self) { key in
                                    Button(action: {
                                        selectedKey = key
                                    }) {
                                        Text(key)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(selectedKey == key ? .white : .primary)
                                            .frame(maxWidth: .infinity, minHeight: 35)
                                            .background(selectedKey == key ? Color.blue : Color.gray.opacity(0.2))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                } else {
                    // Mouse action configuration
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Select Mouse Action:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                            ForEach(mouseActions, id: \.self) { action in
                                Button(action: {
                                    selectedMouseAction = action
                                    print("🖱️ Selected mouse action: '\(action)'")
                                }) {
                                    HStack {
                                        Image(systemName: iconForMouseAction(action))
                                            .foregroundColor(selectedMouseAction == action ? .white : .orange)
                                        Text(action)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(selectedMouseAction == action ? .white : .primary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(selectedMouseAction == action ? Color.orange : Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func rightStickConfigurationView() -> some View {
        VStack(spacing: 20) {
            // Explanation of right stick mouse control
            VStack(alignment: .leading, spacing: 12) {
                Text("Mouse Control Mode")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "computermouse")
                            .foregroundColor(.blue)
                        Text("The right analog stick controls mouse movement")
                            .font(.body)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .foregroundColor(.green)
                        Text("Move the stick to move the mouse cursor")
                            .font(.body)
                    }
                    
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.orange)
                        Text("Stick deflection controls movement speed")
                            .font(.body)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Features section
            VStack(alignment: .leading, spacing: 12) {
                Text("Features:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Relative mouse movement")
                    Text("• Acceleration curve for precision control")
                    Text("• Dead zone to prevent drift")
                    Text("• Natural directional control")
                }
                .font(.body)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Info note
            Text("This stick cannot be remapped to keyboard keys as it provides superior mouse control for gaming and productivity.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
    
    // Helper functions for analog stick configuration
    private func getCurrentKeyForDirection(_ direction: String) -> String {
        switch direction {
        case "Up": return analogStickKeys.up
        case "Down": return analogStickKeys.down
        case "Left": return analogStickKeys.left
        case "Right": return analogStickKeys.right
        default: return ""
        }
    }
    
    private func hasCustomMappingForDirection(_ direction: String) -> Bool {
        let buttonName = "\(buttonName)_\(direction)"
        return configManager.getKeyMapping(layout: layout, button: buttonName) != nil
    }
    
    private func updateAnalogStickDirection(_ direction: String, key: String) {
        switch direction {
        case "Up": analogStickKeys.up = key
        case "Down": analogStickKeys.down = key
        case "Left": analogStickKeys.left = key
        case "Right": analogStickKeys.right = key
        default: break
        }
    }
    
    private func updateSelectedKeyForDirection() {
        let currentKey = getCurrentKeyForDirection(selectedDirection)
        if commonKeys.contains(currentKey) {
            selectedKey = currentKey
            isCustomKeyMode = false
        } else {
            customKey = currentKey
            isCustomKeyMode = true
        }
    }
    
    
    private func iconForMouseAction(_ action: String) -> String {
        switch action {
        case "Left Click": return "cursorarrow.click"
        case "Right Click": return "cursorarrow.click.2"
        case "Double Click": return "cursorarrow.click.badge.clock"
        case "Drag Toggle": return "cursorarrow.and.square.on.square.dashed"
        case "Scroll Up": return "scroll.up"
        case "Scroll Down": return "scroll.down"
        default: return "computermouse"
        }
    }
    
    private var canApply: Bool {
        if isAnalogStick {
            return true // Always allow applying analog stick changes
        } else {
            if actionType == .mouse {
                return !selectedMouseAction.isEmpty
            } else {
                if isCustomKeyMode {
                    return !customKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } else {
                    return !selectedKey.isEmpty
                }
            }
        }
    }
    
    private func applyMapping() {
        print("🔧 applyMapping called for button: '\(buttonName)'")
        print("🔧 isAnalogStick: \(isAnalogStick)")
        
        if isAnalogStick {
            // Apply all four directional mappings for analog stick
            configManager.setKeyMapping(layout: layout, button: "\(buttonName)_Up", key: analogStickKeys.up)
            configManager.setKeyMapping(layout: layout, button: "\(buttonName)_Down", key: analogStickKeys.down)
            configManager.setKeyMapping(layout: layout, button: "\(buttonName)_Left", key: analogStickKeys.left)
            configManager.setKeyMapping(layout: layout, button: "\(buttonName)_Right", key: analogStickKeys.right)
        } else {
            // Apply mapping for regular button
            print("🔧 actionType: \(actionType.rawValue)")
            print("🔧 selectedMouseAction: '\(selectedMouseAction)'")
            print("🔧 selectedKey: '\(selectedKey)'")
            print("🔧 isCustomKeyMode: \(isCustomKeyMode)")
            print("🔧 customKey: '\(customKey)'")
            
            let actionToApply: String
            
            if actionType == .mouse {
                actionToApply = selectedMouseAction
                print("🖱️ Applying mouse action '\(actionToApply)' to button '\(buttonName)'")
            } else {
                actionToApply = isCustomKeyMode ? customKey.trimmingCharacters(in: .whitespacesAndNewlines) : selectedKey
                print("⌨️ Applying keyboard action '\(actionToApply)' to button '\(buttonName)'")
            }
            
            if !actionToApply.isEmpty {
                print("🔧 Saving mapping for \(buttonName): '\(actionToApply)'")
                print("🔧 Layout: \(layout.rawValue)")
                configManager.setKeyMapping(layout: layout, button: buttonName, key: actionToApply)
                print("� Mapping saved successfully")
                
                // Verify the save worked
                let verifyMapping = configManager.getEffectiveKey(layout: layout, button: buttonName)
                print("🔧 Verification: \(buttonName) now maps to '\(verifyMapping)'")
            } else {
                print("🔧 ⚠️ actionToApply is empty, not saving")
            }
        }
        isPresented = false
    }
    
    private func resetToDefault() {
        if isAnalogStick {
            // Reset all directional mappings for analog stick
            configManager.removeKeyMapping(layout: layout, button: "\(buttonName)_Up")
            configManager.removeKeyMapping(layout: layout, button: "\(buttonName)_Down")
            configManager.removeKeyMapping(layout: layout, button: "\(buttonName)_Left")
            configManager.removeKeyMapping(layout: layout, button: "\(buttonName)_Right")
            // Refresh the displayed keys
            analogStickKeys = configManager.getAnalogStickKeys(layout: layout, stick: buttonName)
        } else {
            configManager.removeKeyMapping(layout: layout, button: buttonName)
        }
        isPresented = false
    }
    
    private func hasAnyCustomAnalogMapping() -> Bool {
        return configManager.getKeyMapping(layout: layout, button: "\(buttonName)_Up") != nil ||
               configManager.getKeyMapping(layout: layout, button: "\(buttonName)_Down") != nil ||
               configManager.getKeyMapping(layout: layout, button: "\(buttonName)_Left") != nil ||
               configManager.getKeyMapping(layout: layout, button: "\(buttonName)_Right") != nil
    }
}

struct ButtonConfigPopup_Previews: PreviewProvider {
    static var previews: some View {
        ButtonConfigPopupPreviewWrapper()
    }
}

private struct ButtonConfigPopupPreviewWrapper: View {
    @State private var isPresented = true
    
    var body: some View {
        ButtonConfigPopup(
            layout: .xbox,
            buttonName: "LeftStick", // Test with analog stick
            configManager: GamepadConfigManager(),
            isPresented: $isPresented
        )
    }
}
