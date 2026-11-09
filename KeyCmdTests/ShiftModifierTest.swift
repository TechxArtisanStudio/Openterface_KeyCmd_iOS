//
//  ShiftModifierTest.swift
//  KeyCmdTests
//
//  测试 Shift 修饰键是否正确发送到目标设备
//

import XCTest
@testable import KeyCmd

class ShiftModifierTest: XCTestCase {

    var keyboardManager: KeyboardManager!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []
    private var originalLocale: KeyboardLocale!

    override func setUp() {
        super.setUp()
        // 本测试假设 US QWERTY（'a' = HID 0x04）；共享 locale 可能被其他测试改过。
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

    // MARK: - Shift 修饰键测试

    /// 测试 1：模拟真实按键流程 - Shift + A（大写 A）
    func testShiftPlusA_RealFlow() {
        print("\n========== Shift + A (Real Flow) ==========")

        // 确保初始状态干净
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()
        clearCapturedReports()

        // Step 1: 按下 Shift 键（模拟 UI 层调用 handleKeyDown）
        print("\n--- Step 1: Press Shift ---")
        keyboardManager.handleKeyDown("Shift")

        print("activeModifiers: \(keyboardManager.activeModifiers)")
        XCTAssertTrue(keyboardManager.activeModifiers.contains("Shift"),
                      "Shift should be in activeModifiers")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")
            XCTAssertEqual(last.modifier, 0x02, "Modifier byte should include Shift (0x02)")
            print("✅ Shift modifier correctly sent")
        } else {
            XCTFail("No HID report sent when pressing Shift")
        }

        // Step 2: 按下 A 键（模拟 UI 层调用 handleKeyDown）
        print("\n--- Step 2: Press A ---")
        clearCapturedReports()
        keyboardManager.handleKeyDown("a")

        print("activeModifiers: \(keyboardManager.activeModifiers)")
        print("pressedKeys: \(keyboardManager.pressedKeys)")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 关键验证：modifier byte 必须包含 Shift (0x02)
            XCTAssertTrue(last.modifier & 0x02 != 0,
                         "Modifier byte must include Shift (0x02)")

            // 关键验证：key code 必须是 4 (0x04) - 'a' 键的 HID 码
            XCTAssertEqual(last.keyCodes[0], 4,
                         "Key code should be 4 (0x04) for 'a' key")

            print("✅ HID report correctly includes Shift modifier (0x02) and key code 4")
            print("  Target will interpret as: 'A' (uppercase)")
        } else {
            XCTFail("No HID report sent when pressing A")
        }

        // Step 3: 释放 A 键
        print("\n--- Step 3: Release A ---")
        clearCapturedReports()
        keyboardManager.handleKeyUp("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 释放 A 后，Shift 应该仍然保持
            XCTAssertTrue(last.modifier & 0x02 != 0,
                         "Shift should still be active after releasing A")
            // 但 key code 应该为 0（没有按键）
            XCTAssertEqual(last.keyCodes[0], 0,
                         "Key code should be 0 after releasing A")
        }

        // Step 4: 释放 Shift 键
        print("\n--- Step 4: Release Shift ---")
        clearCapturedReports()
        keyboardManager.handleKeyUp("Shift")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 释放 Shift 后，modifier byte 应该为 0
            XCTAssertEqual(last.modifier, 0x00,
                         "Modifier byte should be 0 after releasing Shift")
        }

        print("\n✅ Test passed: Shift modifier correctly sent with A key")
        print("========== Test Complete ==========\n")
    }

    /// 测试 2：验证 handleKeysDown 是否正确应用 activeModifiers
    func testHandleKeysDown_AppliesActiveModifiers() {
        print("\n========== handleKeysDown Applies Active Modifiers ==========")

        // 确保初始状态干净
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()
        clearCapturedReports()

        // 手动添加 Shift 到 activeModifiers（模拟按下 Shift）
        keyboardManager.activeModifiers.insert("Shift")
        // Also update KeyboardState to match (since handleKeyDown now reads from keyboardState)
        keyboardManager.keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        print("Manually added Shift to activeModifiers and keyboardState")

        // 按下 A 键
        print("\n--- Press A (with Shift in activeModifiers) ---")
        keyboardManager.handleKeyDown("a")

        if let last = lastReport {
            print("Sent HID report: modifier=0x\(String(format: "%02X", last.modifier)), keyCodes=\(last.keyCodes.map { String(format: "0x%02X", $0) }.joined(separator: ", "))")

            // 关键验证：modifier byte 必须包含 Shift (0x02)
            XCTAssertTrue(last.modifier & 0x02 != 0,
                         "Modifier byte must include Shift (0x02)")

            print("✅ handleKeysDown correctly applies activeModifiers")
        } else {
            XCTFail("No HID report sent")
        }

        // 清理
        keyboardManager.handleKeyUp("a")
        keyboardManager.activeModifiers.remove("Shift")
        keyboardManager.keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)

        print("========== Test Complete ==========\n")
    }

    /// 测试 3：验证 modifierMask 函数
    func testModifierMaskFunction() {
        print("\n========== modifierMask Function Test ==========")

        // 通过反射或间接方式测试 modifierMask
        // 由于 modifierMask 是 private，我们通过实际使用来验证

        keyboardManager.activeModifiers.removeAll()
        clearCapturedReports()

        // 测试 Shift
        keyboardManager.handleKeyDown("Shift")
        if let last = lastReport {
            print("Shift modifier byte: 0x\(String(format: "%02X", last.modifier))")
            XCTAssertEqual(last.modifier, 0x02, "Shift should be 0x02")
        }
        keyboardManager.handleKeyUp("Shift")

        // 测试 Ctrl
        clearCapturedReports()
        keyboardManager.handleKeyDown("Ctrl")
        if let last = lastReport {
            print("Ctrl modifier byte: 0x\(String(format: "%02X", last.modifier))")
            XCTAssertEqual(last.modifier, 0x01, "Ctrl should be 0x01")
        }
        keyboardManager.handleKeyUp("Ctrl")

        // 测试 Alt
        clearCapturedReports()
        keyboardManager.handleKeyDown("Alt")
        if let last = lastReport {
            print("Alt modifier byte: 0x\(String(format: "%02X", last.modifier))")
            XCTAssertEqual(last.modifier, 0x04, "Alt should be 0x04")
        }
        keyboardManager.handleKeyUp("Alt")

        print("\n✅ All modifier masks correct")
        print("========== Test Complete ==========\n")
    }
}
