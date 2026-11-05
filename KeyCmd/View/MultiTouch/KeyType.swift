import CoreGraphics

/// Classification of a keyboard key for touch dispatch.
enum KeyType: String, Codable, CaseIterable {
    /// Modifier key (Ctrl, Shift, Alt, Cmd, Win, Option, Super).
    /// Supports slide-to-lock in momentary-chord mode.
    case modifier
    /// Regular key (letters, numbers, symbols, Tab, Enter, Backspace, arrows, F-keys).
    /// Supports long-press repeat.
    case regular
    /// Special key with custom behavior (Caps Lock toggle).
    case special
    /// Japanese-specific key (無変換, 変換, ひらがな/カタカナ, etc.)
    case japaneseSpecial
}

/// A registered key with its identity, type, and frame in the touch container's coordinate space.
struct KeyRegistration: Equatable {
    let keyId: String
    let keyName: String
    let keyType: KeyType
    let frame: CGRect
}
