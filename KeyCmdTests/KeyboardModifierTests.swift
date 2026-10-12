//
//  KeyboardModifierTests.swift
//  KeyCmdTests
//
//  Integration tests for modifier and dead key handling (Task 4.6)
//

import XCTest
@testable import KeyCmd

final class KeyboardModifierTests: XCTestCase {

    var keyboardState: KeyboardState!

    override func setUp() {
        super.setUp()
        keyboardState = KeyboardState.shared
        keyboardState.reset()
    }

    override func tearDown() {
        keyboardState.reset()
        super.tearDown()
    }

    // MARK: - Modifier State Tests

    func testShiftModifierState() {
        // Test left shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x02, 0x02)

        // Test right shift (KeyboardState treats left/right shift as single state)
        keyboardState.updateModifierState(key: .keyboardRightShift, pressed: true)
        XCTAssertTrue(keyboardState.isShiftPressed)

        // Release right shift
        keyboardState.updateModifierState(key: .keyboardRightShift, pressed: false)
        XCTAssertFalse(keyboardState.isShiftPressed) // Left and right share same state
        XCTAssertEqual(keyboardState.modifierByte & 0x02, 0x00)

        // Press left shift again
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x02, 0x02)

        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x02, 0x00)
    }

    func testCtrlModifierState() {
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x01, 0x01)

        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x01, 0x00)
    }

    func testAltModifierState() {
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertTrue(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x04, 0x04)

        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: false)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x04, 0x00)
    }

    func testAltGrModifierState() {
        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertTrue(keyboardState.isAltGrPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x40, 0x40)

        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: false)
        XCTAssertFalse(keyboardState.isAltGrPressed)
        XCTAssertEqual(keyboardState.modifierByte & 0x40, 0x00)
    }

    func testMultipleModifiers() {
        // Test Ctrl + Shift
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x03) // 0x01 | 0x02

        // Add Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x07) // 0x01 | 0x02 | 0x04

        // Release Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)
        XCTAssertEqual(keyboardState.modifierByte, 0x06) // 0x02 | 0x04
    }

    // MARK: - Dead Key Tests

    func testDeadKeyAcute() {
        keyboardState.setDeadKey(.acute)
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)

        // Test combinations
        XCTAssertEqual(DeadKey.acute.combine(with: "a"), "á")
        XCTAssertEqual(DeadKey.acute.combine(with: "e"), "é")
        XCTAssertEqual(DeadKey.acute.combine(with: "i"), "í")
        XCTAssertEqual(DeadKey.acute.combine(with: "o"), "ó")
        XCTAssertEqual(DeadKey.acute.combine(with: "u"), "ú")
        XCTAssertEqual(DeadKey.acute.combine(with: "y"), "ý")
    }

    func testDeadKeyGrave() {
        keyboardState.setDeadKey(.grave)
        XCTAssertEqual(keyboardState.pendingDeadKey, .grave)

        // Test combinations
        XCTAssertEqual(DeadKey.grave.combine(with: "a"), "à")
        XCTAssertEqual(DeadKey.grave.combine(with: "e"), "è")
        XCTAssertEqual(DeadKey.grave.combine(with: "i"), "ì")
        XCTAssertEqual(DeadKey.grave.combine(with: "o"), "ò")
        XCTAssertEqual(DeadKey.grave.combine(with: "u"), "ù")
    }

    func testDeadKeyCircumflex() {
        keyboardState.setDeadKey(.circumflex)
        XCTAssertEqual(keyboardState.pendingDeadKey, .circumflex)

        // Test combinations
        XCTAssertEqual(DeadKey.circumflex.combine(with: "a"), "â")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "e"), "ê")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "i"), "î")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "o"), "ô")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "u"), "û")
    }

    func testDeadKeyDiaeresis() {
        keyboardState.setDeadKey(.diaeresis)
        XCTAssertEqual(keyboardState.pendingDeadKey, .diaeresis)

        // Test combinations
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "a"), "ä")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "e"), "ë")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "i"), "ï")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "o"), "ö")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "u"), "ü")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "y"), "ÿ")
    }

    func testDeadKeyTilde() {
        keyboardState.setDeadKey(.tilde)
        XCTAssertEqual(keyboardState.pendingDeadKey, .tilde)

        // Test combinations
        XCTAssertEqual(DeadKey.tilde.combine(with: "a"), "ã")
        XCTAssertEqual(DeadKey.tilde.combine(with: "n"), "ñ")
        XCTAssertEqual(DeadKey.tilde.combine(with: "o"), "õ")
    }

    func testDeadKeyClear() {
        keyboardState.setDeadKey(.acute)
        XCTAssertNotNil(keyboardState.pendingDeadKey)

        keyboardState.setDeadKey(nil)
        XCTAssertNil(keyboardState.pendingDeadKey)
    }

    // MARK: - Integration Tests

    func testModifierAndDeadKeyInteraction() {
        // Set up modifier state
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)

        // Set dead key
        keyboardState.setDeadKey(.circumflex)

        // Verify both states are maintained
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.pendingDeadKey, .circumflex)
        XCTAssertEqual(keyboardState.modifierByte, 0x03) // Ctrl + Shift
    }

    func testClearAllModifiersPreservesDeadKey() {
        // Set up modifier state
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)

        // Set dead key
        keyboardState.setDeadKey(.acute)

        // Clear modifiers
        keyboardState.clearAllModifiers()

        // Modifiers should be cleared
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)

        // Dead key should be preserved
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)
    }

    func testResetClearsAllState() {
        // Set up modifier state
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)

        // Set dead key
        keyboardState.setDeadKey(.grave)

        // Reset all state
        keyboardState.reset()

        // All state should be cleared
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertFalse(keyboardState.isAltGrPressed)
        XCTAssertNil(keyboardState.pendingDeadKey)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Edge Cases

    func testInvalidDeadKeyCombination() {
        // Test that invalid combinations return nil
        XCTAssertNil(DeadKey.acute.combine(with: "b"))
        XCTAssertNil(DeadKey.grave.combine(with: "c"))
        XCTAssertNil(DeadKey.circumflex.combine(with: "d"))
        XCTAssertNil(DeadKey.diaeresis.combine(with: "f"))
        XCTAssertNil(DeadKey.tilde.combine(with: "g"))
    }

    func testModifierByteCalculation() {
        // Test all modifier combinations
        keyboardState.reset()
        XCTAssertEqual(keyboardState.modifierByte, 0x00)

        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x03)

        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x07)

        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x47) // 0x07 | 0x40
    }
}
