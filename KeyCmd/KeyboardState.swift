// KeyCmd/KeyboardState.swift
import Foundation

/// 键盘状态管理器
class KeyboardState {
    static let shared = KeyboardState()

    // 修饰键状态
    private(set) var isShiftPressed = false
    private(set) var isAltGrPressed = false
    private(set) var isCtrlPressed = false
    private(set) var isAltPressed = false
    private(set) var isLeftGUIPressed = false
    private(set) var isRightGUIPressed = false

    // 死键状态
    private(set) var pendingDeadKey: DeadKey?
    private(set) var pendingDeadKeyHID: HIDUsageID?

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
        case .keyboardLeftGUI:
            isLeftGUIPressed = pressed
        case .keyboardRightGUI:
            isRightGUIPressed = pressed
        default:
            break
        }
    }

    func setDeadKey(_ deadKey: DeadKey?) {
        pendingDeadKey = deadKey
    }

    /// 从布局设置死键状态（按键按下时调用）
    func setDeadKeyIfNeeded(_ layout: KeyboardLayoutDefinition, for hid: HIDUsageID) {
        if let keyDef = layout.allKeys.first(where: { $0.hidUsageID == hid }),
           let deadKey = keyDef.deadKey {
            pendingDeadKey = deadKey
            pendingDeadKeyHID = hid
        } else {
            pendingDeadKey = nil
            pendingDeadKeyHID = nil
        }
    }

    /// 清除死键状态
    func clearDeadKey() {
        pendingDeadKey = nil
        pendingDeadKeyHID = nil
    }

    /// 处理字符输入，返回最终要发送的 (字符, HID, 修饰键字节)
    /// 返回 nil 表示等待下一个字符（死键按下后）
    func processCharacter(
        _ char: Character,
        layout: KeyboardLayoutDefinition,
        translationTable: KeyboardTranslationTable
    ) -> (character: Character, hid: HIDUsageID, modifiers: UInt8)? {

        // Helper: try to find HID for a character, with case-insensitive fallback
        func findHID(for char: Character) -> HIDUsageID? {
            // Try exact match first
            if let hid = translationTable.hidUsageID(forCharacter: char) {
                return hid
            }
            // Try uppercase
            if let upper = char.uppercased().first,
               let hid = translationTable.hidUsageID(forCharacter: upper) {
                return hid
            }
            // Try lowercase
            if let lower = char.lowercased().first,
               let hid = translationTable.hidUsageID(forCharacter: lower) {
                return hid
            }
            return nil
        }

        // 1. 有待处理死键 → 尝试组合
        if let deadKey = pendingDeadKey,
           let combined = deadKey.combine(with: char) {
            clearDeadKey()
            // 返回组合字符，使用基础字符的 HID 作为回退
            // 实际发送时由 KeyboardManager 处理 Unicode 字符
            if let baseHID = findHID(for: char) {
                return (combined, baseHID, modifierByte)
            }
            // 连基础字符的 HID 都找不到
            return nil
        }

        // 2. 正常字符查找
        guard let hid = findHID(for: char) else {
            return nil
        }

        // 3. 检查该键是否是死键
        if let keyDef = layout.allKeys.first(where: { $0.hidUsageID == hid }),
           let deadKey = keyDef.deadKey {
            // 这是死键键位：设置状态，不立即发送字符
            pendingDeadKey = deadKey
            pendingDeadKeyHID = hid
            return nil  // 等待下一个字符
        }

        // 4. 普通字符
        return (char, hid, modifierByte)
    }

    /// 获取当前修饰键字节（用于HID报告）
    var modifierByte: UInt8 {
        var byte: UInt8 = 0
        if isCtrlPressed { byte |= 0x01 }
        if isShiftPressed { byte |= 0x02 }
        if isAltPressed { byte |= 0x04 }
        if isAltGrPressed { byte |= 0x40 }  // Right Alt
        if isLeftGUIPressed { byte |= 0x08 }   // Left GUI (Cmd / Win)
        if isRightGUIPressed { byte |= 0x80 }  // Right GUI
        return byte
    }

    /// 重置所有状态
    func reset() {
        clearAllModifiers()
        pendingDeadKey = nil
        pendingDeadKeyHID = nil
    }

    /// 清除所有修饰键状态（保留死键状态）
    func clearAllModifiers() {
        isShiftPressed = false
        isAltGrPressed = false
        isCtrlPressed = false
        isAltPressed = false
        isLeftGUIPressed = false
        isRightGUIPressed = false
    }
}
