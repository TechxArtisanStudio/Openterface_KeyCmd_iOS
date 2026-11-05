//
//  CapitalizationTest.swift
//  KeyCmdTests
//
//  测试大小写转换是否正确交给操作系统处理
//

import XCTest
@testable import KeyCmd

class CapitalizationTest: XCTestCase {

    var keyboardManager: KeyboardManager!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []
    private var originalLocale: KeyboardLocale!

    override func setUp() {
        super.setUp()

        // These assertions describe the US physical key positions, so pin the
        // active layout instead of inheriting whichever locale a prior test used.
        originalLocale = KeyboardLayoutManager.shared.currentKeyboardLocale
        KeyboardLayoutManager.shared.currentKeyboardLocale = .us

        // 创建 KeyboardManager（需要 BLEManager）
        let bleManager = BLEManager()
        keyboardManager = KeyboardManager(bleManager: bleManager)

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

    // MARK: - 大小写转换测试

    /// 测试大写锁定关闭时的字母输入
    func testCapsLockOffLowercase() {
        print("\n========== Caps Lock Off - Lowercase Input ==========")

        // 确保大写锁定关闭
        keyboardManager.capsLockActive = false
        keyboardManager.activeModifiers.removeAll()

        clearCapturedReports()
        // 按下 'a' 键（应该输出小写 'a'）
        keyboardManager.handleKeyDown("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 应该没有修饰键，key code 应该是 'a' 键的 HID 码 (4)
            XCTAssertEqual(last.modifier, 0x00, "No modifiers should be active")
            XCTAssertEqual(last.keyCodes[0], 4, "'a' key should send HID code 4")
            print("✅ Correctly sent 'a' key code with no modifiers")
        }

        // 释放键
        clearCapturedReports()
        keyboardManager.handleKeyUp("a")

        if let last = lastReport {
            print("Key up report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")
            XCTAssertEqual(last.modifier, 0x00, "No modifiers should be active on key up")
            XCTAssertEqual(last.keyCodes[0], 0, "Key code should be 0 on key up")
        }

        print("========== Test Complete ==========\n")
    }

    /// 测试大写锁定关闭时的Shift+字母输入（大写）
    func testCapsLockOffShiftUppercase() {
        print("\n========== Caps Lock Off + Shift - Uppercase Input ==========")

        // 确保大写锁定关闭
        keyboardManager.capsLockActive = false
        keyboardManager.activeModifiers.removeAll()

        // 按下 Shift 键
        keyboardManager.handleKeyDown("Shift")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier))")
            XCTAssertEqual(last.modifier, 0x02, "Shift modifier should be active")
            print("✅ Shift modifier correctly set")
        }

        clearCapturedReports()
        // 按下 'a' 键（应该输出大写 'A'）
        keyboardManager.handleKeyDown("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 应该有 Shift 修饰键，key code 应该是 'a' 键的 HID 码 (4)
            XCTAssertEqual(last.modifier, 0x02, "Shift modifier should be active")
            XCTAssertEqual(last.keyCodes[0], 4, "'a' key should send HID code 4")
            print("✅ Correctly sent 'a' key code with Shift modifier")
        }

        // 释放 'a' 键
        clearCapturedReports()
        keyboardManager.handleKeyUp("a")

        // 释放 Shift 键
        clearCapturedReports()
        keyboardManager.handleKeyUp("Shift")

        print("========== Test Complete ==========\n")
    }

    /// 测试大写锁定打开时的字母输入（大写）
    func testCapsLockOnUppercase() {
        print("\n========== Caps Lock On - Uppercase Input ==========")

        // 打开大写锁定
        keyboardManager.capsLockActive = true
        keyboardManager.activeModifiers.removeAll()

        clearCapturedReports()
        // 按下 'a' 键（应该输出大写 'A'）
        keyboardManager.handleKeyDown("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 应该没有修饰键（我们不再尝试自己处理大小写），key code 应该是 'a' 键的 HID 码 (4)
            XCTAssertEqual(last.modifier, 0x00, "No modifiers should be active (letting OS handle caps lock)")
            XCTAssertEqual(last.keyCodes[0], 4, "'a' key should send HID code 4")
            print("✅ Correctly sent 'a' key code with no modifiers (OS will handle caps lock)")
        }

        // 释放键
        clearCapturedReports()
        keyboardManager.handleKeyUp("a")

        print("========== Test Complete ==========\n")
    }

    /// 测试大写锁定打开时的Shift+字母输入（小写，因为Shift反转）
    func testCapsLockOnShiftLowercase() {
        print("\n========== Caps Lock On + Shift - Lowercase Input ==========")

        // 打开大写锁定
        keyboardManager.capsLockActive = true
        keyboardManager.activeModifiers.removeAll()

        // 按下 Shift 键
        keyboardManager.handleKeyDown("Shift")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier))")
            XCTAssertEqual(last.modifier, 0x02, "Shift modifier should be active")
            print("✅ Shift modifier correctly set")
        }

        clearCapturedReports()
        // 按下 'a' 键（应该输出小写 'a'，因为Shift在大写锁定状态下会反转）
        keyboardManager.handleKeyDown("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 应该有 Shift 修饰键，key code 应该是 'a' 键的 HID 码 (4)
            XCTAssertEqual(last.modifier, 0x02, "Shift modifier should be active")
            XCTAssertEqual(last.keyCodes[0], 4, "'a' key should send HID code 4")
            print("✅ Correctly sent 'a' key code with Shift modifier (OS will handle shift + caps lock)")
        }

        // 释放 'a' 键
        clearCapturedReports()
        keyboardManager.handleKeyUp("a")

        // 释放 Shift 键
        clearCapturedReports()
        keyboardManager.handleKeyUp("Shift")

        print("========== Test Complete ==========\n")
    }
}
