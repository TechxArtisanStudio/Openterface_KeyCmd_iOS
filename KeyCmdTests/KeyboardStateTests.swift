// KeyCmdTests/KeyboardStateTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardStateTests: XCTestCase {

    var state: KeyboardState!

    override func setUp() {
        super.setUp()
        state = KeyboardState.shared
        state.reset()
    }

    func testModifierStateUpdate() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(state.isShiftPressed)

        state.updateModifierState(key: .keyboardLeftShift, pressed: false)
        XCTAssertFalse(state.isShiftPressed)
    }

    func testAltGrState() {
        state.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertTrue(state.isAltGrPressed)
    }

    func testModifierByte() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertEqual(state.modifierByte, 0x02)

        state.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertEqual(state.modifierByte, 0x03)  // 0x01 | 0x02
    }

    func testDeadKeyCombination() {
        XCTAssertEqual(DeadKey.circumflex.combine(with: "e"), "ê")
        XCTAssertEqual(DeadKey.acute.combine(with: "e"), "é")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "u"), "ü")
    }

    func testReset() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        state.setDeadKey(.acute)
        state.reset()

        XCTAssertFalse(state.isShiftPressed)
        XCTAssertNil(state.pendingDeadKey)
    }
}
