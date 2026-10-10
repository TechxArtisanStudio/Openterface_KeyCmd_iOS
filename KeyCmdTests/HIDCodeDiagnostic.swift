//
//  HIDCodeDiagnostic.swift
//  KeyCmdTests
//
//  诊断实际的 HID code 返回值
//

import XCTest
@testable import KeyCmd

class HIDCodeDiagnostic: XCTestCase {

    /// 测试各种按键的 HID code 返回值
    func testHidCodeValues() {
        print("\n========== HID Code Diagnostic ==========")

        // 测试常见按键
        // (keyName, expectedHidCodeName, description)
        let testKeys: [(String, String, String?)] = [
            ("a", "a", "Letter A"),
            ("1", "1", "Number 1"),
            ("&", "1", "French & (on 1 key)"),
            ("é", "2", "French é (on 2 key)"),
            ("\"", "3", "French quote (on 3 key)"),
            ("'", "4", "French apostrophe (on 4 key)"),
            ("(", "5", "French parenth (on 5 key)"),
            ("-", "6", "French dash (on 6 key)"),
            ("è", "7", "French è (on 7 key)"),
            ("_", "8", "French underscore (on 8 key)"),
            ("ç", "9", "French ç (on 9 key)"),
            ("à", "0", "French à (on 0 key)"),
            (")", "Minus", "French ) (on Minus key)"),
            ("=", "Equal", "French = (on Equal key)"),
            ("q", "q", "Letter Q"),
            ("w", "w", "Letter W"),
            ("z", "z", "Letter Z"),
            ("m", "m", "Letter M"),
            ("Enter", "Enter", "Enter key"),
            ("Space", "Space", "Space key"),
            ("Tab", "Tab", "Tab key"),
            ("Esc", "Escape", "Escape key"),
            ("F1", "F1", "F1 key"),
            ("F12", "F12", "F12 key"),
            ("Shift", "Shift", "Left Shift"),
            ("Ctrl", "Ctrl", "Left Ctrl"),
            ("Alt", "Alt", "Left Alt"),
            ("Win", "GUI", "Left GUI/Win"),
        ]

        print("Key Name → HID Code (Decimal) [Expected Description]")
        print("-" + String(repeating: "-", count: 60))

        var allPassed = true

        for (keyName, expectedHidName, description) in testKeys {
            let hidCodeValue = Keymod.hidCode(forKey: keyName)
            let status = hidCodeValue >= 0 ? "✅" : "❌"
            if hidCodeValue < 0 {
                allPassed = false
            }

            // 对于特殊字符，显示预期信息
            let detail = description != nil ? " [\(description!)]" : ""
            print("\(status) \(keyName.padding(toLength: 8, withPad: " ", startingAt: 0)) → \(hidCodeValue) \(detail)")

            // 查找预期名称对应的值
            let expectedValue = lookupExpectedHidCode(expectedHidName)
            if let expVal = expectedValue, hidCodeValue != expVal {
                print("    ⚠️  Expected \(expectedHidName) (\(expVal)), got \(hidCodeValue)")
                allPassed = false
            }
        }

        print("-" + String(repeating: "-", count: 60))
        print(allPassed ? "✅ All HID code lookups passed" : "❌ Some HID code lookups failed")
        print("========== Diagnostic Complete ==========")
    }

    /// 根据名称查找预期的 HID code 值（简化版）
    private func lookupExpectedHidCode(_ name: String) -> Int32? {
        // 常见 HID 用法码（页面 0x07，键盘）
        let hidMap: [String: Int32] = [
            "a": 0x04,
            "b": 0x05,
            "c": 0x06,
            "d": 0x07,
            "e": 0x08,
            "f": 0x09,
            "g": 0x0A,
            "h": 0x0B,
            "i": 0x0C,
            "j": 0x0D,
            "k": 0x0E,
            "l": 0x0F,
            "m": 0x10,
            "n": 0x11,
            "o": 0x12,
            "p": 0x13,
            "q": 0x14,
            "r": 0x15,
            "s": 0x16,
            "t": 0x17,
            "u": 0x18,
            "v": 0x19,
            "w": 0x1A,
            "x": 0x1B,
            "y": 0x1C,
            "z": 0x1D,
            "1": 0x1E,
            "2": 0x1F,
            "3": 0x20,
            "4": 0x21,
            "5": 0x22,
            "6": 0x23,
            "7": 0x24,
            "8": 0x25,
            "9": 0x26,
            "0": 0x27,
            "Enter": 0x28,
            "Esc": 0x29,
            "Backspace": 0x2A,
            "Tab": 0x2B,
            "Space": 0x2C,
            "Minus": 0x2D,
            "Equal": 0x2E,
            "LeftBracket": 0x2F,
            "RightBracket": 0x30,
            "Backslash": 0x31,
            "Semicolon": 0x33,
            "Quote": 0x34,
            "Grave": 0x35,
            "Comma": 0x36,
            "Period": 0x37,
            "Slash": 0x38,
            "CapsLock": 0x39,
            "F1": 0x3A,
            "F2": 0x3B,
            "F3": 0x3C,
            "F4": 0x3D,
            "F5": 0x3E,
            "F6": 0x3F,
            "F7": 0x40,
            "F8": 0x41,
            "F9": 0x42,
            "F10": 0x43,
            "F11": 0x44,
            "F12": 0x45,
            "PrintScreen": 0x46,
            "ScrollLock": 0x47,
            "Pause": 0x48,
            "Insert": 0x49,
            "Home": 0x4A,
            "PageUp": 0x4B,
            "Delete": 0x4C,
            "End": 0x4D,
            "PageDown": 0x4E,
            "RightArrow": 0x4F,
            "LeftArrow": 0x50,
            "DownArrow": 0x51,
            "UpArrow": 0x52,
            "NumLock": 0x53,
            "KP_Slash": 0x54,
            "KP_Asterisk": 0x55,
            "KP_Minus": 0x56,
            "KP_Plus": 0x57,
            "KP_Enter": 0x58,
            "KP_1": 0x59,
            "KP_2": 0x5A,
            "KP_3": 0x5B,
            "KP_4": 0x5C,
            "KP_5": 0x5D,
            "KP_6": 0x5E,
            "KP_7": 0x5F,
            "KP_8": 0x60,
            "KP_9": 0x61,
            "KP_0": 0x62,
            "KP_Period": 0x63,
            "Shift": 0xE1,  // Left Shift
            "RightShift": 0xE2,
            "Ctrl": 0xE0,   // Left Ctrl
            "RightCtrl": 0xE4,
            "Alt": 0xE2,    // Left Alt
            "RightAlt": 0xE6,
            "GUI": 0xE3,    // Left GUI
            "RightGUI": 0xE7,
        ]

        return hidMap[name]
    }

    /// 测试修饰键组合
    func testModifierCombination() {
        print("\n========== Modifier Combination Test ==========")

        // 模拟按下 Shift + 1 （应该产生 ! 在 US 布局，或 & 在 FR 布局）
        let keyName = "1"

        let hidCodeValue = Keymod.hidCode(forKey: keyName)
        print("Key: \(keyName) → HID code: \(hidCodeValue)")

        // 测试常见的修饰键值（简化版）
        let shiftModifier: UInt8 = 0x02  // KMod.shift
        let ctrlModifier: UInt8 = 0x01   // KMod.ctrl
        let altModifier: UInt8 = 0x04    // KMod.alt

        print("Shift modifier: 0x\(String(format: "%02X", shiftModifier))")
        print("Ctrl modifier: 0x\(String(format: "%02X", ctrlModifier))")
        print("Alt modifier: 0x\(String(format: "%02X", altModifier))")

        // 在 US 布局：Shift + 1 = !
        // 在 FR 布局：Shift + 1 = & (因为 1 键无 shift，& 需要 shift)
        print("Expected for US layout: Shift+1 → !")
        print("Expected for FR layout: Shift+1 → &")
        print("========== Test Complete ==========")
    }
}
