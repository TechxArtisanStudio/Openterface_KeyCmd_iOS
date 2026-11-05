//
//  RealDeviceHIDTest.swift
//  KeyCmdTests
//
//  真机自动化测试：程序化模拟按键，验证实际发送的 HID 报告
//  无需手动点击按钮
//

import XCTest
@testable import KeyCmd

class RealDeviceHIDTest: XCTestCase {

    var keyboardManager: KeyboardManager!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []
    private var originalLocale: KeyboardLocale!

    override func setUp() {
        super.setUp()

        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        KeyboardLayoutLoader.layoutsDirectoryOverride = "\(projectRoot)/Resources/KeyboardLayouts"
        KeyboardLayoutManager.shared.clearCache()

        // Force a known starting locale so each test's locale switch refreshes
        // the active layout even when a previous test already selected it.
        originalLocale = KeyboardLayoutManager.shared.currentKeyboardLocale
        KeyboardLayoutManager.shared.currentKeyboardLocale = .us

        // 创建 KeyboardManager（需要 BLEManager）
        let bleManager = BLEManager()
        keyboardManager = KeyboardManager(bleManager: bleManager)

        // Reset the shared keyboard state to ensure clean state for each test
        keyboardManager.keyboardState.reset()
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()

        // 设置测试钩子捕获 HID 报告
        capturedReports.removeAll()
        keyboardManager.hidReportCapture = { [weak self] modifier, keyCodes in
            self?.capturedReports.append((modifier: modifier, keyCodes: keyCodes))
        }
    }

    override func tearDown() {
        keyboardManager.hidReportCapture = nil
        keyboardManager = nil
        capturedReports.removeAll()
        KeyboardLayoutManager.shared.currentKeyboardLocale = originalLocale
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        KeyboardLayoutManager.shared.clearCache()
        super.tearDown()
    }

    /// 清空捕获的报告
    func clearCapturedReports() {
        capturedReports.removeAll()
    }

    /// 获取最后发送的报告
    var lastReport: (modifier: UInt8, keyCodes: [UInt8])? {
        return capturedReports.last
    }

    // MARK: - 自动化按键测试

    /// 测试 1：程序化模拟按下 Shift + & 键（法语布局）
    func testAutomatedShiftAndCharKey() {
        print("\n========== Automated Shift + & Key Test ==========")

        // 设置法语布局
        let layoutManager = KeyboardLayoutManager.shared
        layoutManager.currentKeyboardLocale = .fr
        let frLayout = layoutManager.layout(for: .windows, locale: .fr)
        print("Layout: \(frLayout.metadata.name)")

        clearCapturedReports()

        // Step 1: 程序化按下 Shift 键
        print("\n--- Step 1: Press Shift ---")
        let shiftKeyName = "Shift"
        keyboardManager.handleKeyDown(shiftKeyName)

        // 验证 Shift 被添加到 activeModifiers
        XCTAssertTrue(keyboardManager.activeModifiers.contains("Shift"),
                      "Shift should be in activeModifiers")
        print("✅ Shift added to activeModifiers")

        // 验证发送了 Shift-only 报告
        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")
            XCTAssertEqual(last.modifier, 0x02, "Modifier byte should include Shift (0x02)")
        }

        // Step 2: 程序化按下 & 键 (which is keyName "1" on French AZERTY)
        print("\n--- Step 2: Press & key (keyName '1') ---")
        let charKeyName = "1"  // On French AZERTY, the "1" key has label "&"
        // 模拟 BasicKeyboardMouseView：屏幕按键直接使用布局中的 HID
        let charHID = try! XCTUnwrap(frLayout.keyDefinition(for: charKeyName)?.hidUsageID)
        print("HID for '\(charKeyName)' → 0x\(String(format: "%02X", charHID.rawValue))")

        clearCapturedReports()
        keyboardManager.handleKeyDown(hid: charHID)

        // 验证发送的报告包含 Shift 修饰键
        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 关键验证：modifier byte 必须包含 Shift (0x02)
            XCTAssertTrue(last.modifier & 0x02 != 0,
                         "Modifier byte must include Shift (0x02)")

            // 关键验证：key code 必须是 30 (0x1E) - 数字 1 键的位置
            XCTAssertEqual(last.keyCodes[0], 30,
                         "Key code should be 30 (0x1E) for the '1' key position")

            print("✅ HID report correctly includes Shift modifier (0x02) and key code 30")
            print("  Target with French AZERTY will interpret as: '1'")
        }

        // Step 3: 释放 & 键
        print("\n--- Step 3: Release & key ---")
        clearCapturedReports()
        keyboardManager.handleKeyUp(hid: charHID)

        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 释放字符键后，Shift 应该仍然保持
            XCTAssertTrue(last.modifier & 0x02 != 0,
                         "Shift should still be active after releasing character key")
            // 但 key code 应该为 0（没有按键）
            XCTAssertEqual(last.keyCodes[0], 0,
                         "Key code should be 0 after releasing character key")
        }

        // Step 4: 释放 Shift 键
        print("\n--- Step 4: Release Shift ---")
        clearCapturedReports()
        keyboardManager.handleKeyUp(shiftKeyName)

        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 释放 Shift 后，modifier byte 应该为 0
            XCTAssertEqual(last.modifier, 0x00,
                         "Modifier byte should be 0 after releasing Shift")
        }

        print("\n✅ Test passed: Shift modifier correctly sent with character key")
        print("========== Test Complete ==========\n")
    }

    /// 测试 2：程序化模拟 AltGr + 字符键（法语 @ 字符）
    func testAutomatedAltGrAndCharKey() {
        print("\n========== Automated AltGr + à Key Test (@ character) ==========")

        // 设置法语布局
        let layoutManager = KeyboardLayoutManager.shared
        layoutManager.currentKeyboardLocale = .fr
        let frLayout = layoutManager.layout(for: .windows, locale: .fr)
        print("Layout: \(frLayout.metadata.name)")

        clearCapturedReports()

        // Step 1: 按下 AltGr 键
        print("\n--- Step 1: Press AltGr ---")
        let altGrKeyName = "AltGr"
        keyboardManager.handleKeyDown(altGrKeyName)

        XCTAssertTrue(keyboardManager.activeModifiers.contains("AltGr"),
                     "AltGr should be in activeModifiers")
        print("✅ AltGr added to activeModifiers")

        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier))")
            // AltGr 应该是 0x40 (Right Alt)
            XCTAssertEqual(last.modifier, 0x40,
                         "Modifier byte should be 0x40 (Right Alt for AltGr)")
        }

        // Step 2: 按下 à 键（在法语布局中，AltGr+à = @）
        print("\n--- Step 2: Press à key (keyName '0') ---")
        let charKeyName = "0"  // On French AZERTY, the "0" key has label "à"
        let charHID = try! XCTUnwrap(frLayout.keyDefinition(for: charKeyName)?.hidUsageID)
        print("HID for '\(charKeyName)' → 0x\(String(format: "%02X", charHID.rawValue))")

        clearCapturedReports()
        keyboardManager.handleKeyDown(hid: charHID)

        if let last = lastReport {
            print("  Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 关键验证：modifier byte 必须包含 AltGr (0x40)
            XCTAssertTrue(last.modifier & 0x40 != 0,
                         "Modifier byte must include AltGr (0x40)")

            // 关键验证：key code 必须是 39 (0x27) - 数字 0 键的位置
            XCTAssertEqual(last.keyCodes[0], 39,
                         "Key code should be 39 (0x27) for the '0' key position")

            print("✅ HID report correctly includes AltGr modifier (0x40) and key code 39")
            print("  Target with French AZERTY will interpret as: '@'")
        }

        print("\n✅ Test passed: AltGr modifier correctly sent with character key")
        print("========== Test Complete ==========\n")
    }

    /// 测试 3：批量测试法语布局的所有特殊字符
    func testAutomatedFrenchSpecialCharacters() {
        print("\n========== Automated French Special Characters Test ==========")

        let layoutManager = KeyboardLayoutManager.shared
        layoutManager.currentKeyboardLocale = .fr
        let frLayout = layoutManager.layout(for: .windows, locale: .fr)

        // 测试所有法语数字行的特殊字符 (using keyName, not label)
        // Format: (keyName, expectedHIDCode, label, shiftLabel)
        let testChars: [(String, UInt8, String, String)] = [
            ("1", 30, "&", "1"),
            ("2", 31, "é", "2"),
            ("3", 32, "\"", "3"),
            ("4", 33, "'", "4"),
            ("5", 34, "(", "5"),
            ("6", 35, "-", "6"),
            ("7", 36, "è", "7"),
            ("8", 37, "_", "8"),
            ("9", 38, "ç", "9"),
            ("0", 39, "à", "0"),
        ]

        var allPassed = true

        for (keyName, expectedHidCode, label, shiftLabel) in testChars {
            clearCapturedReports()

            guard let charHID = frLayout.keyDefinition(for: keyName)?.hidUsageID else {
                XCTFail("French layout has no key '\(keyName)'")
                continue
            }

            // 按下字符键
            keyboardManager.handleKeyDown(hid: charHID)

            if let last = lastReport {
                let passed = last.keyCodes[0] == expectedHidCode
                let status = passed ? "✅" : "❌"
                if !passed { allPassed = false }
                print("\(status) keyName '\(keyName)' (label: '\(label)') → HID \(last.keyCodes[0]) (期望 \(expectedHidCode)) → Shift = '\(shiftLabel)'")
            }

            // 释放字符键
            keyboardManager.handleKeyUp(hid: charHID)
        }

        print("-" + String(repeating: "-", count: 70))
        print(allPassed ? "✅ All French special characters passed" : "❌ Some French special characters failed")
        print("========== Test Complete ==========\n")

        XCTAssertTrue(allPassed, "Some French special characters failed")
    }

    /// 测试 4：多修饰键组合
    func testAutomatedMultipleModifiers() {
        print("\n========== Automated Multiple Modifiers Test ==========")

        clearCapturedReports()

        // 测试 Ctrl + Shift + A
        print("\n--- Ctrl + Shift + A ---")
        keyboardManager.handleKeyDown("Ctrl")
        keyboardManager.handleKeyDown("Shift")
        clearCapturedReports()
        keyboardManager.handleKeyDown(hid: .keyboardA)

        if let last = lastReport {
            print("Modifier byte: 0x\(String(format: "%02X", last.modifier))")
            print("Key code: \(last.keyCodes[0])")

            // Ctrl (0x01) + Shift (0x02) = 0x03
            XCTAssertEqual(last.modifier, 0x03,
                         "Ctrl + Shift should be 0x03")
            XCTAssertEqual(last.keyCodes[0], 4,
                         "'a' should be HID code 4")
        }

        // 释放所有键
        keyboardManager.handleKeyUp(hid: .keyboardA)
        keyboardManager.handleKeyUp("Shift")
        keyboardManager.handleKeyUp("Ctrl")

        print("\n✅ Test passed: Multiple modifiers correctly combined")
        print("========== Test Complete ==========\n")
    }
}
