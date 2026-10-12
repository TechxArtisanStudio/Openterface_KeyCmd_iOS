// KeyCmd/KeyboardState.swift
import Foundation

/// 死键类型
enum DeadKey: String, Codable {
    case acute       // ´
    case grave       // `
    case circumflex  // ^
    case diaeresis   // ¨
    case tilde       // ~

    /// 将死键与基础字符组合
    func combine(with baseChar: Character) -> Character? {
        switch self {
        case .acute:
            let map: [Character: Character] = ["a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú", "y": "ý"]
            return map[baseChar]
        case .grave:
            let map: [Character: Character] = ["a": "à", "e": "è", "i": "ì", "o": "ò", "u": "ù"]
            return map[baseChar]
        case .circumflex:
            let map: [Character: Character] = ["a": "â", "e": "ê", "i": "î", "o": "ô", "u": "û"]
            return map[baseChar]
        case .diaeresis:
            let map: [Character: Character] = ["a": "ä", "e": "ë", "i": "ï", "o": "ö", "u": "ü", "y": "ÿ"]
            return map[baseChar]
        case .tilde:
            let map: [Character: Character] = ["a": "ã", "n": "ñ", "o": "õ"]
            return map[baseChar]
        }
    }
}

/// 键盘状态管理器
class KeyboardState {
    static let shared = KeyboardState()

    // 修饰键状态
    private(set) var isShiftPressed = false
    private(set) var isAltGrPressed = false
    private(set) var isCtrlPressed = false
    private(set) var isAltPressed = false

    // 死键状态
    private(set) var pendingDeadKey: DeadKey?

    private init() {}

    func updateModifierState(key: HIDUsageID, pressed: Bool) {
        switch key {
        case .keyboardLeftShift, .keyboardRightShift:
            isShiftPressed = pressed
        case .keyboardRightAlt:  // AltGr
            isAltGrPressed = pressed
        case .keyboardLeftCtrl, .keyboardRightCtrl:
            isCtrlPressed = pressed
        case .keyboardLeftAlt:
            isAltPressed = pressed
        default:
            break
        }
    }

    func setDeadKey(_ deadKey: DeadKey?) {
        pendingDeadKey = deadKey
    }

    /// 获取当前修饰键字节（用于HID报告）
    var modifierByte: UInt8 {
        var byte: UInt8 = 0
        if isCtrlPressed { byte |= 0x01 }
        if isShiftPressed { byte |= 0x02 }
        if isAltPressed { byte |= 0x04 }
        if isAltGrPressed { byte |= 0x40 }  // Right Alt
        return byte
    }

    /// 重置所有状态
    func reset() {
        isShiftPressed = false
        isAltGrPressed = false
        isCtrlPressed = false
        isAltPressed = false
        pendingDeadKey = nil
    }

    /// 清除所有修饰键状态（保留死键状态）
    func clearAllModifiers() {
        isShiftPressed = false
        isAltGrPressed = false
        isCtrlPressed = false
        isAltPressed = false
    }
}
