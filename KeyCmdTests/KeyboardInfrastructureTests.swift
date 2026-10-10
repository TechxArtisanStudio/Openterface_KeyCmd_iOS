import XCTest
@testable import KeyCmd

final class KeyboardInfrastructureTests: XCTestCase {

    func testHIDUsageIDCompleteness() {
        // 验证所有必要的键都已定义
        let requiredKeys: [HIDUsageID] = [
            .keyboardA, .keyboardZ, .keyboard1, .keyboard0,
            .keyboardEnter, .keyboardEscape, .keyboardSpace,
            .keyboardLeftShift, .keyboardRightAlt
        ]

        for key in requiredKeys {
            XCTAssertNotNil(HIDUsageID(rawValue: key.rawValue))
        }
    }

    func testKeyDefinitionIntegration() {
        let keyDef = KeyDefinition.key("a", "A", shift: "A", hid: .keyboardA)
        XCTAssertEqual(keyDef.hidUsageID, .keyboardA)
        XCTAssertEqual(keyDef.label, "A")
    }

    func testKeyboardStateIntegration() {
        let state = KeyboardState.shared
        state.reset()

        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(state.isShiftPressed)
        XCTAssertEqual(state.modifierByte & 0x02, 0x02)
    }

    func testTranslationTableIntegration() {
        // Create a simple test layout
        let rows: [KeyRow] = [
            [
                KeyDefinition.key("a", "A", shift: "A", hid: .keyboardA),
                KeyDefinition.key("b", "B", shift: "B", hid: .keyboardB)
            ]
        ]
        let metadata = LayoutMetadata(name: "Test Layout", description: "Minimal test layout")
        let layout = KeyboardLayoutDefinition(locale: .us, targetOS: .windows, rows: rows, metadata: metadata)
        let table = KeyboardTranslationTable(layout: layout)

        // 验证查找性能
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 {
            _ = table.hidUsageID(forCharacter: "a")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(elapsed, 0.1)  // 1000次查找应<0.1秒
    }
}
