//
//  FullFlowDiagnostic.swift
//  KeyCmdTests
//
//  测试完整的按键流程：布局查找 → hidKeyName → hidCode
//

import XCTest
@testable import KeyCmd

class FullFlowDiagnostic: XCTestCase {

    /// 测试完整流程：从 keyName 到最终 HID code
    func testFullKeyFlow() {
        print("\n========== Full Key Flow Diagnostic ==========")

        // 设置法语布局
        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        print("Using layout: \(frLayout.metadata.name)")

        // 测试法语布局的特殊按键
        let testCases: [(String, String, Int32?)] = [
            // (keyName from layout, expected keyCode from layout, expected HID code)
            ("&", "1", 30),   // French & on 1 key
            ("é", "2", 31),   // French é on 2 key
            ("\"", "3", 32),  // French " on 3 key
            ("'", "4", 33),   // French ' on 4 key
            ("(", "5", 34),   // French ( on 5 key
            ("-", "6", 35),   // French - on 6 key
            ("è", "7", 36),   // French è on 7 key
            ("_", "8", 37),   // French _ on 8 key
            ("ç", "9", 38),   // French ç on 9 key
            ("à", "0", 39),   // French à on 0 key
        ]

        for (keyName, expectedKeyCode, expectedHidCode) in testCases {
            print("\n--- Testing key: '\(keyName)' ---")

            // Step 1: Look up key in layout
            let keyDef = frLayout.keyDefinition(for: keyName)
            if let keyDef = keyDef {
                print("  ✅ Found in layout: keyName='\(keyDef.keyName)', keyCode='\(keyDef.keyCode)'")

                // Step 2: Verify keyCode matches expected
                if keyDef.keyCode != expectedKeyCode {
                    print("  ⚠️  Expected keyCode '\(expectedKeyCode)', got '\(keyDef.keyCode)'")
                } else {
                    print("  ✅ keyCode matches expected: '\(expectedKeyCode)'")
                }

                // Step 3: Get HID code for the keyCode
                let hidCodeValue = Keymod.hidCode(forKey: keyDef.keyCode)
                print("  HID code for '\(keyDef.keyCode)': \(hidCodeValue)")

                // Step 4: Verify HID code
                if let expected = expectedHidCode {
                    if hidCodeValue == expected {
                        print("  ✅ HID code matches expected: \(expected)")
                    } else {
                        print("  ❌ Expected HID code \(expected), got \(hidCodeValue)")
                    }
                }
            } else {
                print("  ❌ Key '\(keyName)' NOT FOUND in layout!")
            }
        }

        print("\n========== Test Complete ==========")
    }

    /// 测试修饰键是否正确应用
    func testModifierApplication() {
        print("\n========== Modifier Application Test ==========")

        // 模拟按下 Shift 然后按下 & 键
        let keyName = "&"
        print("Key to press: \(keyName)")

        // 获取 HID 键名（通过布局查找）
        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        let resolvedKeyCode = frLayout.keyDefinition(for: keyName)?.keyCode ?? keyName
        print("Resolved keyCode: \(resolvedKeyCode)")

        // 获取 HID code
        let hidCodeValue = Keymod.hidCode(forKey: resolvedKeyCode)
        print("HID code: \(hidCodeValue)")

        // 模拟 Shift 修饰键
        let shiftMask: UInt8 = 0x02
        print("Shift modifier mask: 0x\(String(format: "%02X", shiftMask))")

        // 验证 Shift + & 应该产生 1
        print("With Shift active, HID report should be: [0x\(String(format: "%02X", shiftMask)), \(hidCodeValue), 0, 0, 0, 0, 0]")
        print("Target with French AZERTY layout will interpret this as: '1'")

        print("\n========== Test Complete ==========")
    }

    /// 测试所有法语数字行的按键
    func testFrenchNumberRow() {
        print("\n========== French Number Row Test ==========")

        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)

        // 数字行应该是第二行 (index 1)
        if frLayout.rows.count > 1 {
            let numberRow = frLayout.rows[1]
            print("Number row has \(numberRow.count) keys")

            for (idx, key) in numberRow.enumerated() {
                let hidCode = Keymod.hidCode(forKey: key.keyCode)
                let shiftLabel = key.shiftLabel ?? "nil"
                print("[\(idx)] keyName='\(key.keyName)', label='\(key.label)', shift='\(shiftLabel)', keyCode='\(key.keyCode)' → HID: \(hidCode)")
            }
        }

        print("\n========== Test Complete ==========")
    }
}
