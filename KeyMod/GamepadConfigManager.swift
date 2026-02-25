//
//  GamepadConfigManager.swift
//  KeyMod
//
//  Created by System on 2025/7/16.
//

import Foundation
import Combine

/// Represents a component position in the gamepad layout
struct ComponentPosition: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    
    init(x: CGFloat = 0, y: CGFloat = 0) {
        self.x = x
        self.y = y
    }
    
    static let zero = ComponentPosition(x: 0, y: 0)
}

/// Stores layout positions for all components
struct LayoutPositions: Codable, Equatable {
    var dpad: ComponentPosition = ComponentPosition()
    var leftStick: ComponentPosition = ComponentPosition()
    var rightStick: ComponentPosition = ComponentPosition()
    var actionButtons: ComponentPosition = ComponentPosition()
    var shoulderButtons: [ComponentPosition] = []
    var centerButtons: [ComponentPosition] = []
}

/// Manages custom gamepad button configurations and layout positions
class GamepadConfigManager: ObservableObject {
    @Published var customMappings: [String: [String: String]] = [:]
    @Published var layoutPositions: [String: LayoutPositions] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "GamepadCustomMappings"
    private let positionsKey = "GamepadLayoutPositions"
    
    init() {
        loadMappings()
        loadPositions()
    }
    
    // MARK: - Position Management
    
    /// Get the position for a component in a specific layout
    func getComponentPosition(layout: GamepadLayout, component: String) -> ComponentPosition {
        let positions = layoutPositions[layout.rawValue] ?? LayoutPositions()
        switch component {
        case "DPad":
            return positions.dpad
        case "LeftStick":
            return positions.leftStick
        case "RightStick":
            return positions.rightStick
        case "ActionButtons":
            return positions.actionButtons
        default:
            // Handle shoulder and center buttons by index
            if component.hasPrefix("ShoulderButton_") {
                if let index = Int(component.replacingOccurrences(of: "ShoulderButton_", with: "")),
                   index < positions.shoulderButtons.count {
                    return positions.shoulderButtons[index]
                }
            } else if component.hasPrefix("CenterButton_") {
                if let index = Int(component.replacingOccurrences(of: "CenterButton_", with: "")),
                   index < positions.centerButtons.count {
                    return positions.centerButtons[index]
                }
            }
            return ComponentPosition()
        }
    }
    
    /// Set the position for a component in a specific layout
    func setComponentPosition(layout: GamepadLayout, component: String, position: ComponentPosition) {
        if layoutPositions[layout.rawValue] == nil {
            layoutPositions[layout.rawValue] = LayoutPositions()
        }
        
        switch component {
        case "DPad":
            layoutPositions[layout.rawValue]?.dpad = position
        case "LeftStick":
            layoutPositions[layout.rawValue]?.leftStick = position
        case "RightStick":
            layoutPositions[layout.rawValue]?.rightStick = position
        case "ActionButtons":
            layoutPositions[layout.rawValue]?.actionButtons = position
        default:
            // Handle shoulder and center buttons by index
            if component.hasPrefix("ShoulderButton_") {
                if let index = Int(component.replacingOccurrences(of: "ShoulderButton_", with: "")) {
                    // Ensure array is large enough
                    while layoutPositions[layout.rawValue]!.shoulderButtons.count <= index {
                        layoutPositions[layout.rawValue]!.shoulderButtons.append(ComponentPosition())
                    }
                    layoutPositions[layout.rawValue]!.shoulderButtons[index] = position
                }
            } else if component.hasPrefix("CenterButton_") {
                if let index = Int(component.replacingOccurrences(of: "CenterButton_", with: "")) {
                    // Ensure array is large enough
                    while layoutPositions[layout.rawValue]!.centerButtons.count <= index {
                        layoutPositions[layout.rawValue]!.centerButtons.append(ComponentPosition())
                    }
                    layoutPositions[layout.rawValue]!.centerButtons[index] = position
                }
            }
        }
        savePositions()
    }
    
    /// Reset all positions for a layout to default
    func resetLayoutPositions(layout: GamepadLayout) {
        print("🔄 GamepadConfigManager: Resetting positions for \(layout.rawValue)")
        layoutPositions[layout.rawValue] = LayoutPositions()
        savePositions()
        print("🔄 GamepadConfigManager: Reset complete, positions saved")
    }
    
    /// Check if a layout has any custom positions
    func hasCustomPositions(layout: GamepadLayout) -> Bool {
        guard let positions = layoutPositions[layout.rawValue] else { return false }
        
        return positions.dpad != ComponentPosition() ||
               positions.leftStick != ComponentPosition() ||
               positions.rightStick != ComponentPosition() ||
               positions.actionButtons != ComponentPosition() ||
               !positions.shoulderButtons.allSatisfy { $0 == ComponentPosition() } ||
               !positions.centerButtons.allSatisfy { $0 == ComponentPosition() }
    }
    
    // MARK: - Key Mapping Management
    
    /// Get the key mapping for a specific button in a layout
    func getKeyMapping(layout: GamepadLayout, button: String) -> String? {
        return customMappings[layout.rawValue]?[button]
    }
    
    /// Set a custom key mapping for a button
    func setKeyMapping(layout: GamepadLayout, button: String, key: String) {
        print("💾 setKeyMapping called: layout=\(layout.rawValue), button='\(button)', key='\(key)'")
        
        if customMappings[layout.rawValue] == nil {
            customMappings[layout.rawValue] = [:]
            print("💾 Created new layout mapping for \(layout.rawValue)")
        }
        
        let oldValue = customMappings[layout.rawValue]?[button]
        customMappings[layout.rawValue]?[button] = key
        print("💾 Updated mapping: \(button) '\(oldValue ?? "nil")' -> '\(key)'")
        
        saveMappings()
        print("💾 Mappings saved to UserDefaults")
        
        // Verify the mapping was stored
        let storedValue = customMappings[layout.rawValue]?[button]
        print("💾 Verification: stored value for \(button) = '\(storedValue ?? "nil")'")
    }
    
    /// Remove custom mapping for a button (revert to default)
    func removeKeyMapping(layout: GamepadLayout, button: String) {
        customMappings[layout.rawValue]?[button] = nil
        if customMappings[layout.rawValue]?.isEmpty == true {
            customMappings[layout.rawValue] = nil
        }
        saveMappings()
    }
    
    /// Get the effective key for a button (custom or default)
    func getEffectiveKey(layout: GamepadLayout, button: String) -> String {
        // Check for custom mapping first
        if let customKey = getKeyMapping(layout: layout, button: button) {
            print("🔍 ConfigManager: Found custom mapping for \(button): '\(customKey)'")
            return customKey
        }
        
        // Fall back to default mapping
        let defaultKey = getDefaultKey(layout: layout, button: button)
        print("🔍 ConfigManager: Using default mapping for \(button): '\(defaultKey)'")
        return defaultKey
    }
    
    /// Get analog stick directional key mappings
    func getAnalogStickKeys(layout: GamepadLayout, stick: String) -> (up: String, down: String, left: String, right: String) {
        let upKey = getEffectiveKey(layout: layout, button: "\(stick)_Up")
        let downKey = getEffectiveKey(layout: layout, button: "\(stick)_Down")
        let leftKey = getEffectiveKey(layout: layout, button: "\(stick)_Left")
        let rightKey = getEffectiveKey(layout: layout, button: "\(stick)_Right")
        
        return (up: upKey, down: downKey, left: leftKey, right: rightKey)
    }
    
    /// Check if a button name represents an analog stick direction
    func isAnalogStickDirection(_ buttonName: String) -> Bool {
        return buttonName.contains("LeftStick_") || buttonName.contains("RightStick_")
    }
    
    /// Get the stick type and direction from a button name
    func parseAnalogStickButton(_ buttonName: String) -> (stick: String, direction: String)? {
        if buttonName.hasPrefix("LeftStick_") {
            let direction = String(buttonName.dropFirst("LeftStick_".count))
            return (stick: "LeftStick", direction: direction)
        } else if buttonName.hasPrefix("RightStick_") {
            let direction = String(buttonName.dropFirst("RightStick_".count))
            return (stick: "RightStick", direction: direction)
        }
        return nil
    }
    
    /// Get the default key mapping for a button
    private func getDefaultKey(layout: GamepadLayout, button: String) -> String {
        print("🔍 ConfigManager getDefaultKey: layout=\(layout.rawValue), button='\(button)'")
        
        // Handle D-Pad direction keys that are common across all layouts
        switch button {
        case "Up": return "Up"
        case "Down": return "Down"
        case "Left": return "Left"
        case "Right": return "Right"
        default: break
        }
        
        // Handle analog stick directional mappings
        switch button {
        case "LeftStick_Up": return "W"
        case "LeftStick_Down": return "S"
        case "LeftStick_Left": return "A"
        case "LeftStick_Right": return "D"
        case "RightStick_Up": return "Up"
        case "RightStick_Down": return "Down"
        case "RightStick_Left": return "Left"
        case "RightStick_Right": return "Right"
        default: break
        }
        
        switch layout {
        case .xbox:
            switch button {
            case "LB": return "Tab"
            case "RB": return "Enter"
            case "LT": return "Shift"
            case "RT": return "Ctrl"
            case "View": return "Escape"
            case "Menu": return "Space"
            case "A": 
                print("🔍 ConfigManager: A button -> Space")
                return "Space"
            case "B": return "Backspace"
            case "X": 
                print("🔍 ConfigManager: X button -> Tab")
                return "Tab"
            case "Y": return "Enter"
            default: 
                print("🔍 ConfigManager: Unknown button '\(button)' for xbox layout, returning empty")
                return ""
            }
        case .playStation:
            switch button {
            case "L1": return "Tab"
            case "R1": return "Enter"
            case "L2": return "Shift"
            case "R2": return "Ctrl"
            case "Share": return "Escape"
            case "Options": return "Space"
            case "✕": return "Space"
            case "○": return "Backspace"
            case "☐": return "Tab"
            case "△": return "Enter"
            default: return ""
            }
        case .nes:
            switch button {
            case "Select": return "Escape"
            case "Start": return "Space"
            case "A": return "Space"
            case "B": return "Backspace"
            default: return ""
            }
        }
    }
    
    /// Save mappings to UserDefaults
    private func saveMappings() {
        if let data = try? JSONEncoder().encode(customMappings) {
            userDefaults.set(data, forKey: configKey)
        }
    }
    
    /// Load mappings from UserDefaults
    private func loadMappings() {
        if let data = userDefaults.data(forKey: configKey),
           let mappings = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            customMappings = mappings
        }
    }
    
    /// Save positions to UserDefaults
    private func savePositions() {
        if let data = try? JSONEncoder().encode(layoutPositions) {
            userDefaults.set(data, forKey: positionsKey)
        }
    }
    
    /// Load positions from UserDefaults
    private func loadPositions() {
        if let data = userDefaults.data(forKey: positionsKey),
           let positions = try? JSONDecoder().decode([String: LayoutPositions].self, from: data) {
            layoutPositions = positions
        }
    }
    
    // MARK: - Debug Functions
    
    /// Clear a specific button mapping for debugging
    func clearButtonMapping(layout: GamepadLayout, button: String) {
        let layoutKey = layout.rawValue
        print("🧹 Clearing mapping for \(button) in layout \(layoutKey)")
        
        if customMappings[layoutKey] != nil {
            let oldValue = customMappings[layoutKey]?[button]
            customMappings[layoutKey]?[button] = nil
            print("🧹 Removed mapping: \(button) -> \(oldValue ?? "nil")")
            saveMappings()
        }
    }
    
    /// Print all stored mappings for debugging
    func debugPrintAllMappings() {
        print("🔍 === All Stored Mappings ===")
        for (layoutKey, mappings) in customMappings {
            print("🔍 Layout: \(layoutKey)")
            for (button, action) in mappings {
                print("🔍   \(button) -> \(action)")
            }
        }
        print("🔍 === End Mappings ===")
    }
    
    /// Clean up invalid mappings (empty button names, component names, etc.)
    func cleanupInvalidMappings() {
        print("🧹 Cleaning up invalid mappings...")
        var cleaned = false
        
        for (layoutKey, mappings) in customMappings {
            var cleanMappings: [String: String] = [:]
            
            for (button, action) in mappings {
                // Skip empty button names
                if button.isEmpty {
                    print("🧹 Removing empty button name -> '\(action)'")
                    cleaned = true
                    continue
                }
                
                // Skip component names that shouldn't be button mappings
                if button == "ActionButtons" || button == "DPad" || button == "LeftStick" || button == "RightStick" {
                    print("🧹 Removing component name '\(button)' -> '\(action)'")
                    cleaned = true
                    continue
                }
                
                // Keep valid mappings
                cleanMappings[button] = action
            }
            
            customMappings[layoutKey] = cleanMappings
        }
        
        if cleaned {
            saveMappings()
            print("🧹 Invalid mappings cleaned and saved")
        } else {
            print("🧹 No invalid mappings found")
        }
    }
}
