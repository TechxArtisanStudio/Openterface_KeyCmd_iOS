//
//  ShortcutProfile.swift
//  KeyMod
//
//  Data models for the unified Shortcut Hub profile system.
//  Built-in profiles are loaded from bundled JSON files in KeyMod/Profiles/.
//  User-created profiles are stored in app Documents directory.
//

import Foundation

// MARK: - Top-level profile

struct ShortcutProfileData: Codable, Identifiable {
    let id: String
    let name: String
    /// SF Symbol name used as the profile icon
    let icon: String
    /// Hex color string (e.g. "#FF6A00") used as the theme accent
    let themeColorHex: String
    /// Whether this profile shows a numpad panel below the shortcut grid
    let hasNumpad: Bool
    let categories: [ShortcutCategoryData]
    /// Optional numpad grid defined as rows of keys. Only used when hasNumpad is true.
    let numpad: [[NumpadKeyData]]?
}

// MARK: - Category within a profile

struct ShortcutCategoryData: Codable, Identifiable {
    let id: String
    let name: String
    /// Optional SF Symbol for the category tab
    let icon: String?
    /// Hex color string for category badge/accent
    let colorHex: String
    let shortcuts: [ShortcutItem]
}

// MARK: - Individual shortcut

struct ShortcutItem: Codable, Identifiable, Equatable {
    /// Stable string ID — bundled JSON files use meaningful IDs (e.g. "b-t-1"),
    /// user-created items fall back to a UUID string.
    var id: String
    /// Human-readable label (e.g. "Move", "Zoom In")
    let description: String
    /// Display string for the main key (e.g. "G", "F1", "Ctrl+S")
    let key: String
    /// Optional modifier string, "+" separated (e.g. "Ctrl", "Shift", "Ctrl+Alt")
    let modifier: String?
    /// Key code string passed to KeyboardManager (e.g. "G", "F1", "Ctrl+S")
    let keyCode: String
    /// Optional custom background colour hex for "My Shortcuts" cards.
    var colorHex: String?

    init(id: String = UUID().uuidString,
         description: String,
         key: String,
         modifier: String? = nil,
         keyCode: String,
         colorHex: String? = nil) {
        self.id = id
        self.description = description
        self.key = key
        self.modifier = modifier
        self.keyCode = keyCode
        self.colorHex = colorHex
    }

    // Content-based equality so drag-and-drop deduplication works correctly
    static func == (lhs: ShortcutItem, rhs: ShortcutItem) -> Bool {
        lhs.description == rhs.description &&
        lhs.key == rhs.key &&
        lhs.modifier == rhs.modifier &&
        lhs.keyCode == rhs.keyCode
    }
}

// MARK: - Numpad key

struct NumpadKeyData: Codable {
    /// Display label on the key (e.g. "7", "+")
    let display: String
    /// Short description (e.g. "Top", "Zoom In")
    let description: String
    /// Key code sent to KeyboardManager (e.g. "Numpad7", "NumpadPlus")
    let keyCode: String
    /// Hex colour for this key
    let colorHex: String
}
