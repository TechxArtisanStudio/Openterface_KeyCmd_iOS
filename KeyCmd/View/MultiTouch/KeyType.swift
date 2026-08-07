import CoreGraphics

/// Classification of a keyboard key for touch dispatch.
enum KeyType {
    /// Modifier key (Ctrl, Shift, Alt, Cmd, Win, Option, Super).
    /// Supports slide-to-lock in momentary-chord mode.
    case modifier
    /// Regular key (letters, numbers, symbols, Tab, Enter, Backspace, arrows, F-keys).
    /// Supports long-press repeat.
    case regular
    /// Special key with custom behavior (Caps Lock toggle).
    case special
}

/// A registered key with its identity, type, and frame in the touch container's coordinate space.
struct KeyRegistration {
    let keyId: String
    let keyName: String
    let keyType: KeyType
    let frame: CGRect
}
