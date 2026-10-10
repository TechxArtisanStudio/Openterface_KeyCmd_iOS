//
//  ModifierFlowTest.swift
//  KeyCmdTests
//
//  测试修饰键和字符键的完整流程
//

import XCTest
@testable import KeyCmd

class ModifierFlowTest: XCTestCase {

    /// 测试法语布局下 Shift + 数字键的完整流程
    func testFrenchShiftNumberFlow() {
        print("\n========== French Shift+Number Flow Test ==========")

        // 设置法语布局
        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        print("Layout: \(frLayout.metadata.name)")

        // 模拟用户流程：
        // 1. 按下 Shift
        // 2. 按下 & 键（应该产生 1）
        // 3. 释放 & 键
        // 4. 释放 Shift

        print("\n--- Step 1: Press Shift ---")
        let shiftKeyName = "Shift"
        print("User presses: \(shiftKeyName)")
        print("Expected: Shift added to activeModifiers")

        print("\n--- Step 2: Press & key ---")
        let charKeyName = "&"
        print("User presses: \(charKeyName)")

        // 检查 hidKeyName 解析
        let resolvedKeyCode = frLayout.keyDefinition(for: charKeyName)?.keyCode ?? charKeyName
        print("hidKeyName(for: '\(charKeyName)') → '\(resolvedKeyCode)'")

        // 检查 HID code
        let hidCodeValue = Keymod.hidCode(forKey: resolvedKeyCode)
        print("Keymod.hidCode(forKey: '\(resolvedKeyCode)') → \(hidCodeValue)")

        // 检查 Shift 修饰键的 mask
        let shiftMask: UInt8 = 0x02
        print("Shift modifier mask: 0x\(String(format: "%02X", shiftMask))")

        // 检查最终的 HID 报告
        print("\nExpected HID report when & key is pressed with Shift:")
        print("  Modifier byte: 0x\(String(format: "%02X", shiftMask)) (Shift)")
        print("  Key codes: [\(hidCodeValue), 0, 0, 0, 0, 0]")
        print("  Target with French AZERTY layout will interpret as: '1'")

        print("\n========== Test Complete ==========")
    }

    /// 测试所有法语布局的修饰键
    func testFrenchLayoutModifiers() {
        print("\n========== French Layout Modifiers Test ==========")

        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        let allKeys = frLayout.allKeys

        // 查找所有修饰键
        let modifiers = allKeys.filter { $0.keyType == .modifier }
        print("Modifier keys in French layout:")
        for mod in modifiers {
            print("  keyName='\(mod.keyName)', label='\(mod.label)', keyCode='\(mod.keyCode)'")
        }

        // 检查 AltGr 键（法语布局应该有 AltGr）
        let altGrKey = allKeys.first { $0.keyName == "AltGr" || $0.label == "AltGr" }
        if let altGr = altGrKey {
            print("\n✅ AltGr key found: keyName='\(altGr.keyName)', label='\(altGr.label)'")
        } else {
            print("\n❌ AltGr key NOT FOUND in French layout!")
        }

        // 检查布局元数据
        print("\nLayout metadata:")
        print("  hasAltGr: \(frLayout.metadata.hasAltGr)")
        print("  physicalStandard: \(frLayout.metadata.physicalStandard)")

        print("\n========== Test Complete ==========")
    }

    /// 测试 hidKeyName 解析的完整性
    func testHidKeyNameResolution() {
        print("\n========== hidKeyName Resolution Test ==========")

        let layoutManager = KeyboardLayoutManager.shared

        // 测试法语布局的 hidKeyName 解析
        let frLayout = layoutManager.layout(for: .windows, locale: .fr)
        print("Using layout: \(frLayout.metadata.name)")

        // 测试所有法语特殊字符
        let frenchChars = ["&", "é", "\"", "'", "(", "-", "è", "_", "ç", "à", "ù", "§", "?", ".", "/"]

        print("\nFrench special character → keyCode → HID code:")
        for char in frenchChars {
            let keyDef = frLayout.keyDefinition(for: char)
            if let keyDef = keyDef {
                let hidCode = Keymod.hidCode(forKey: keyDef.keyCode)
                print("  '\(char)' → '\(keyDef.keyCode)' → \(hidCode)")
            } else {
                print("  '\(char)' → NOT FOUND IN LAYOUT")
            }
        }

        print("\n========== Test Complete ==========")
    }

    /// 测试 US 布局作为对比
    func testUSLayoutComparison() {
        print("\n========== US Layout Comparison Test ==========")

        let usLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .us)
        print("Using layout: \(usLayout.metadata.name)")

        // 测试 US 布局的数字行
        if usLayout.rows.count > 1 {
            let numberRow = usLayout.rows[1]
            print("\nUS Number row:")
            for (idx, key) in numberRow.enumerated() {
                let hidCode = Keymod.hidCode(forKey: key.keyCode)
                let shiftLabel = key.shiftLabel ?? "nil"
                print("  [\(idx)] keyName='\(key.keyName)', label='\(key.label)', shift='\(shiftLabel)', keyCode='\(key.keyCode)' → HID: \(hidCode)")
            }
        }

        // 对比法语和 US 布局的数字行
        print("\n--- Comparison: French vs US ---")
        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)

        if usLayout.rows.count > 1 && frLayout.rows.count > 1 {
            let usNumberRow = usLayout.rows[1]
            let frNumberRow = frLayout.rows[1]

            print("Position | US (keyName → keyCode) | FR (keyName → keyCode)")
            print("-" + String(repeating: "-", count: 70))
            for i in 0..<min(usNumberRow.count, frNumberRow.count) {
                let usKey = usNumberRow[i]
                let frKey = frNumberRow[i]
                print("[\(i)] | '\(usKey.keyName)' → '\(usKey.keyCode)' | '\(frKey.keyName)' → '\(frKey.keyCode)'")
            }
        }

        print("\n========== Test Complete ==========")
    }
}
