//
//  ModifierIntegrationTest.swift
//  KeyCmdTests
//
//  综合测试：验证修饰键和字符键的完整 HID 报告流程
//

import XCTest
@testable import KeyCmd

class ModifierIntegrationTest: XCTestCase {

    // MARK: - Modifier Mask Tests

    /// 测试所有修饰键的 mask 值是否正确
    func testModifierMaskValues() {
        print("\n========== Modifier Mask Values Test ==========")

        // 创建一个测试用的 KeyboardManager
        // 注意：KeyboardManager 依赖 BLEManager，这里我们只测试 modifierMask 的逻辑

        // 验证 HID modifier byte 的标准值
        let expectedMasks: [(String, UInt8, String)] = [
            ("Ctrl", 0x01, "Left Ctrl"),
            ("Shift", 0x02, "Left Shift"),
            ("Alt", 0x04, "Left Alt"),
            ("Win", 0x08, "Left GUI/Win"),
            ("AltGr", 0x40, "Right Alt (AltGr)"),  // 修复后的值
        ]

        var allPassed = true
        for (key, expectedMask, description) in expectedMasks {
            let actualMask = computeModifierMask(for: key)
            let status = actualMask == expectedMask ? "✅" : "❌"
            if actualMask != expectedMask {
                allPassed = false
            }
            print("\(status) \(key.padding(toLength: 8, withPad: " ", startingAt: 0)) → 0x\(String(format: "%02X", actualMask)) (期望: 0x\(String(format: "%02X", expectedMask))) [\(description)]")
        }

        print("-" + String(repeating: "-", count: 70))
        print(allPassed ? "✅ All modifier masks correct" : "❌ Some modifier masks wrong")
        print("========== Test Complete ==========\n")

        XCTAssertTrue(allPassed, "Some modifier masks are incorrect")
    }

    /// 计算修饰键 mask（复制 KeyboardManager 的逻辑用于测试）
    private func computeModifierMask(for key: String) -> UInt8 {
        switch key {
        case "Ctrl":  return KMod.ctrl.rawValue
        case "Shift": return KMod.shift.rawValue
        case "Alt", "Option": return KMod.alt.rawValue
        case "AltGr": return KMod.rAlt.rawValue // 修复后：Right Alt (0x40)
        case "Cmd", "Win", "Super": return KMod.gui.rawValue
        default:      return 0x00
        }
    }

    // MARK: - Full Flow Tests

    /// 测试法语布局下 Shift + 字符键的完整流程
    func testFrenchLayoutShiftFlow() {
        print("\n========== French Layout Shift Flow Test ==========")

        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        print("Layout: \(frLayout.metadata.name)")

        // 模拟 Shift + & 的流程
        print("\n--- Scenario: Press Shift, then press & key ---")

        // Step 1: Press Shift → modifier byte should include 0x02
        let shiftMask: UInt8 = 0x02
        print("Step 1: Press Shift")
        print("  Active modifiers: {Shift}")
        print("  Modifier byte: 0x\(String(format: "%02X", shiftMask))")

        // Step 2: Press & key → resolve to keyCode "1" → HID 30
        let charKeyName = "&"
        let resolvedKeyCode = frLayout.keyDefinition(for: charKeyName)?.keyCode ?? charKeyName
        let hidCode = Keymod.hidCode(forKey: resolvedKeyCode)
        print("\nStep 2: Press '\(charKeyName)' key")
        print("  hidKeyName(for: '\(charKeyName)') → '\(resolvedKeyCode)'")
        print("  HID code for '\(resolvedKeyCode)': \(hidCode) (0x\(String(format: "%02X", hidCode)))")

        // Step 3: Build HID report
        let modifierByte = shiftMask
        let keyCodes: [UInt8] = [UInt8(hidCode), 0, 0, 0, 0, 0]
        print("\nStep 3: Send HID report")
        print("  Modifier byte: 0x\(String(format: "%02X", modifierByte))")
        print("  Key codes: \(keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")
        print("  Target with French AZERTY → interprets as: '1' (Shift+& on French = 1)")

        // Verify
        XCTAssertEqual(hidCode, 30, "& should resolve to HID code 30 (key '1')")
        XCTAssertEqual(modifierByte, 0x02, "Shift modifier should be 0x02")

        print("\n========== Test Complete ==========\n")
    }

    /// 测试 AltGr + 字符键的流程（法语 @ = AltGr + 0）
    func testFrenchLayoutAltGrFlow() {
        print("\n========== French Layout AltGr Flow Test ==========")

        let frLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)
        print("Layout: \(frLayout.metadata.name)")

        // 验证 AltGr mask 是否正确
        let altGrMask: UInt8 = KMod.rAlt.rawValue
        print("\nAltGr modifier mask: 0x\(String(format: "%02X", altGrMask))")
        XCTAssertEqual(altGrMask, 0x40, "AltGr should be 0x40 (Right Alt), not 0x0C (Left Alt + Left GUI)")

        // 模拟 AltGr + 0 → @ 的流程
        print("\n--- Scenario: Press AltGr, then press à key (to get @) ---")

        // Step 1: Press AltGr → modifier byte should include 0x40
        print("Step 1: Press AltGr")
        print("  Active modifiers: {AltGr}")
        print("  Modifier byte: 0x\(String(format: "%02X", altGrMask))")

        // Step 2: Press à key → resolve to keyCode "0" → HID 39
        let charKeyName = "à"
        let resolvedKeyCode = frLayout.keyDefinition(for: charKeyName)?.keyCode ?? charKeyName
        let hidCode = Keymod.hidCode(forKey: resolvedKeyCode)
        print("\nStep 2: Press '\(charKeyName)' key")
        print("  hidKeyName(for: '\(charKeyName)') → '\(resolvedKeyCode)'")
        print("  HID code for '\(resolvedKeyCode)': \(hidCode) (0x\(String(format: "%02X", hidCode)))")

        // Step 3: Build HID report
        let modifierByte = altGrMask
        let keyCodes: [UInt8] = [UInt8(hidCode), 0, 0, 0, 0, 0]
        print("\nStep 3: Send HID report")
        print("  Modifier byte: 0x\(String(format: "%02X", modifierByte))")
        print("  Key codes: \(keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")
        print("  Target with French AZERTY → interprets as: '@' (AltGr+à on French = @)")

        // Verify
        XCTAssertEqual(hidCode, 39, "à should resolve to HID code 39 (key '0')")
        XCTAssertEqual(altGrMask, 0x40, "AltGr should be 0x40 (Right Alt)")

        print("\n========== Test Complete ==========\n")
    }

    /// 测试多个修饰键组合
    func testMultipleModifierCombination() {
        print("\n========== Multiple Modifier Combination Test ==========")

        // 测试 Ctrl + Shift + A 的流程
        print("\n--- Scenario: Ctrl + Shift + A ---")

        var modifierByte: UInt8 = 0x00
        let activeModifiers: Set<String> = ["Ctrl", "Shift"]

        for modifier in activeModifiers {
            modifierByte |= computeModifierMask(for: modifier)
        }

        print("Active modifiers: \(activeModifiers)")
        print("Combined modifier byte: 0x\(String(format: "%02X", modifierByte))")
        print("Expected: 0x03 (Ctrl=0x01 | Shift=0x02)")

        XCTAssertEqual(modifierByte, 0x03, "Ctrl + Shift should be 0x03")

        // 测试 Ctrl + Alt + Delete 的流程
        print("\n--- Scenario: Ctrl + Alt + Delete ---")

        modifierByte = 0x00
        let activeModifiers2: Set<String> = ["Ctrl", "Alt"]

        for modifier in activeModifiers2 {
            modifierByte |= computeModifierMask(for: modifier)
        }

        print("Active modifiers: \(activeModifiers2)")
        print("Combined modifier byte: 0x\(String(format: "%02X", modifierByte))")
        print("Expected: 0x05 (Ctrl=0x01 | Alt=0x04)")

        XCTAssertEqual(modifierByte, 0x05, "Ctrl + Alt should be 0x05")

        // 测试 Ctrl + Shift + AltGr + A 的流程
        print("\n--- Scenario: Ctrl + Shift + AltGr + A ---")

        modifierByte = 0x00
        let activeModifiers3: Set<String> = ["Ctrl", "Shift", "AltGr"]

        for modifier in activeModifiers3 {
            modifierByte |= computeModifierMask(for: modifier)
        }

        print("Active modifiers: \(activeModifiers3)")
        print("Combined modifier byte: 0x\(String(format: "%02X", modifierByte))")
        print("Expected: 0x43 (Ctrl=0x01 | Shift=0x02 | AltGr=0x40)")

        XCTAssertEqual(modifierByte, 0x43, "Ctrl + Shift + AltGr should be 0x43")

        print("\n========== Test Complete ==========\n")
    }

    /// 测试 US 布局的 Shift + 数字键
    func testUSLayoutShiftNumberFlow() {
        print("\n========== US Layout Shift+Number Flow Test ==========")

        let usLayout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .us)
        print("Layout: \(usLayout.metadata.name)")

        // 测试 Shift + 1 = !
        let testCases: [(String, Int32, String)] = [
            ("1", 30, "!"),   // Shift + 1 = !
            ("2", 31, "@"),   // Shift + 2 = @
            ("3", 32, "#"),   // Shift + 3 = #
            ("4", 33, "$"),   // Shift + 4 = $
            ("5", 34, "%"),   // Shift + 5 = %
            ("6", 35, "^"),   // Shift + 6 = ^
            ("7", 36, "&"),   // Shift + 7 = &
            ("8", 37, "*"),   // Shift + 8 = *
            ("9", 38, "("),   // Shift + 9 = (
            ("0", 39, ")"),   // Shift + 0 = )
        ]

        let shiftMask: UInt8 = 0x02

        for (keyName, expectedHid, expectedChar) in testCases {
            let resolvedKeyCode = usLayout.keyDefinition(for: keyName)?.keyCode ?? keyName
            let hidCode = Keymod.hidCode(forKey: resolvedKeyCode)

            let status = hidCode == expectedHid ? "✅" : "❌"
            print("\(status) Shift + \(keyName) → HID \(hidCode) (期望 \(expectedHid)) → '\(expectedChar)'")

            XCTAssertEqual(hidCode, expectedHid, "\(keyName) should resolve to HID code \(expectedHid)")
        }

        print("\n========== Test Complete ==========\n")
    }

    /// 测试 KMod 的左右侧修饰键定义
    func testKModDefinitions() {
        print("\n========== KMod Definitions Test ==========")

        // 验证左侧修饰键
        XCTAssertEqual(KMod.ctrl.rawValue, 0x01, "KMod.ctrl should be 0x01")
        XCTAssertEqual(KMod.shift.rawValue, 0x02, "KMod.shift should be 0x02")
        XCTAssertEqual(KMod.alt.rawValue, 0x04, "KMod.alt should be 0x04")
        XCTAssertEqual(KMod.gui.rawValue, 0x08, "KMod.gui should be 0x08")
        print("✅ Left modifiers: Ctrl=0x01, Shift=0x02, Alt=0x04, GUI=0x08")

        // 验证右侧修饰键
        XCTAssertEqual(KMod.rCtrl.rawValue, 0x10, "KMod.rCtrl should be 0x10")
        XCTAssertEqual(KMod.rShift.rawValue, 0x20, "KMod.rShift should be 0x20")
        XCTAssertEqual(KMod.rAlt.rawValue, 0x40, "KMod.rAlt should be 0x40")
        XCTAssertEqual(KMod.rGui.rawValue, 0x80, "KMod.rGui should be 0x80")
        print("✅ Right modifiers: rCtrl=0x10, rShift=0x20, rAlt=0x40, rGUI=0x80")

        // 验证 AltGr 应该使用 rAlt
        let altGrMask = KMod.rAlt.rawValue
        XCTAssertEqual(altGrMask, 0x40, "AltGr should use KMod.rAlt (0x40)")
        print("✅ AltGr = KMod.rAlt = 0x40")

        print("\n========== Test Complete ==========\n")
    }
}
