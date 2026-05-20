//
//  GamepadLayout.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

/// Represents different gamepad layout configurations
enum GamepadLayout: String, CaseIterable {
    case xbox = "Xbox Layout"
    case playStation = "PlayStation Layout"
    case nes = "NES Layout"
    case simple = "Simple Layout"
    
    /// Returns the action button configuration for this layout
    var actionButtons: [ActionButtonConfig] {
        switch self {
        case .xbox:
            return [
                ActionButtonConfig(label: "Y", color: .green, position: .top),
                ActionButtonConfig(label: "X", color: .blue, position: .left),
                ActionButtonConfig(label: "B", color: .red, position: .right),
                ActionButtonConfig(label: "A", color: .orange, position: .bottom)
            ]
        case .playStation:
            return [
                ActionButtonConfig(label: "△", color: .green, position: .top),
                ActionButtonConfig(label: "☐", color: .blue, position: .left),
                ActionButtonConfig(label: "○", color: .red, position: .right),
                ActionButtonConfig(label: "✕", color: .orange, position: .bottom)
            ]
        case .nes:
            return [
                ActionButtonConfig(label: "B", color: .red, position: .left),
                ActionButtonConfig(label: "A", color: .orange, position: .right)
            ]
        case .simple:
            return [
                ActionButtonConfig(label: "A", color: .green, position: .bottom),
                ActionButtonConfig(label: "B", color: .red, position: .right)
            ]
        }
    }
    
    /// Returns the shoulder button labels for this layout
    var shoulderButtons: [String] {
        switch self {
        case .xbox:
            return ["LB", "RB", "LT", "RT"]
        case .playStation:
            return ["L1", "R1", "L2", "R2"]
        case .nes:
            return [] // NES has no shoulder buttons
        case .simple:
            return ["L", "R"]
        }
    }
    
    /// Returns the center button labels for this layout
    var centerButtons: [String] {
        switch self {
        case .xbox:
            return ["Menu", "View"]
        case .playStation:
            return ["Options", "Share"]
        case .nes:
            return ["Start", "Select"]
        case .simple:
            return ["Start"]
        }
    }
}

/// Configuration for an action button
struct ActionButtonConfig {
    let label: String
    let color: Color
    let position: ActionButtonPosition
}

/// Position of an action button in the button cluster
enum ActionButtonPosition {
    case top, bottom, left, right
}
