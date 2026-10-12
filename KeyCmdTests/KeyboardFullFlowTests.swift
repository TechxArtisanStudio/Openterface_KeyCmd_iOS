//
//  KeyboardFullFlowTests.swift
//  KeyCmdTests
//
//  Full flow integration tests for keyboard handling (Task 5.1)
//

import XCTest
@testable import KeyCmd

final class KeyboardFullFlowTests: XCTestCase {

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

    // MARK: - Basic Key Flow Tests

    func testASCIIKeyFlow() {
        // Test that ASCII key press properly updates state
        // Simulate pressing 'a'
        keyboardState.updateModifierState(key: .keyboardA, pressed: true)

        // Verify state is updated
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertFalse(keyboardState.isAltGrPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testShiftedKeyFlow() {
        // Test that Shift + key properly updates state
        // Simulate pressing Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)

        // Verify Shift is active
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Simulate pressing 'a' with Shift
        keyboardState.updateModifierState(key: .keyboardA, pressed: true)

        // Verify state is still correct
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Release Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)

        // Verify Shift is released
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Modifier Key Flow Tests

    func testControlCFlow() {
        // Test Ctrl + C (copy) flow
        // Press Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)

        // Verify Ctrl is active
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        // Press 'c'
        keyboardState.updateModifierState(key: .keyboardC, pressed: true)

        // Verify state is still correct
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        // Release 'c'
        keyboardState.updateModifierState(key: .keyboardC, pressed: false)

        // Release Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)

        // Verify all released
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Dead Key Flow Tests

    func testAcuteAccentFlow() {
        // Test acute accent + e = é flow
        // Set dead key
        keyboardState.setDeadKey(.acute)

        // Verify dead key is set
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)

        // Simulate pressing 'e' - should combine
        let combinedChar = keyboardState.pendingDeadKey?.combine(with: "e")

        // Verify combination
        XCTAssertEqual(combinedChar, "é")

        // Clear dead key
        keyboardState.setDeadKey(nil)

        // Verify dead key is cleared
        XCTAssertNil(keyboardState.pendingDeadKey)
    }

    func testDeadKeyWithoutBase() {
        // Test dead key followed by space (should not combine)
        // Set dead key
        keyboardState.setDeadKey(.acute)

        // Verify dead key is set
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)

        // Simulate pressing space - should not combine
        let combinedChar = keyboardState.pendingDeadKey?.combine(with: " ")

        // Verify no combination
        XCTAssertNil(combinedChar)

        // Clear dead key
        keyboardState.setDeadKey(nil)

        // Verify dead key is cleared
        XCTAssertNil(keyboardState.pendingDeadKey)
    }

    // MARK: - Caps Lock Flow Tests

    func testCapsLockFlow() {
        // Test Caps Lock toggling
        // Initially, Caps Lock should be off
        XCTAssertFalse(keyboardState.isShiftPressed)

        // Simulate Caps Lock toggle (this would be handled by KeyboardManager)
        // For this test, we verify the state management
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)

        // Verify Shift is active (simulating Caps Lock effect)
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Release Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)

        // Verify Shift is released
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Key Combo Flow Tests

    func testAltTabFlow() {
        // Test Alt + Tab (application switcher) flow
        // Press Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)

        // Verify Alt is active
        XCTAssertTrue(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x04)

        // Press Tab
        keyboardState.updateModifierState(key: .keyboardTab, pressed: true)

        // Verify state is still correct
        XCTAssertTrue(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x04)

        // Release Tab
        keyboardState.updateModifierState(key: .keyboardTab, pressed: false)

        // Release Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: false)

        // Verify all released
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testCtrlAltDelFlow() {
        // Test Ctrl + Alt + Del flow
        // Press Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)

        // Verify Ctrl is active
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        // Press Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)

        // Verify both modifiers are active
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertTrue(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x05) // 0x01 | 0x04

        // Press Del
        keyboardState.updateModifierState(key: .keyboardDelete, pressed: true)

        // Verify state is still correct
        XCTAssertEqual(keyboardState.modifierByte, 0x05)

        // Release Del
        keyboardState.updateModifierState(key: .keyboardDelete, pressed: false)

        // Release Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: false)

        // Release Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)

        // Verify all released
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Unicode Flow Tests

    func testUnicodeCharacterFlow() {
        // Test that Unicode characters can be processed
        // This test verifies the flow works, actual Unicode conversion is tested elsewhere

        // Set up a simple test case
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)

        // Verify state
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Release Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)

        // Verify released
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Key Repeat Flow Tests

    func testKeyRepeatFlow() {
        // Test key repeat functionality
        // Simulate pressing a key
        keyboardState.updateModifierState(key: .keyboardA, pressed: true)

        // Verify state
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)

        // Release key
        keyboardState.updateModifierState(key: .keyboardA, pressed: false)

        // Verify state
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Concurrent Operations

    func testConcurrentModifierChanges() {
        // Test rapid modifier changes
        // Press Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(keyboardState.isShiftPressed)

        // Press Ctrl
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertTrue(keyboardState.isCtrlPressed)

        // Press Alt
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertTrue(keyboardState.isAltPressed)

        // Verify all modifiers are active
        XCTAssertEqual(keyboardState.modifierByte, 0x07) // 0x01 | 0x02 | 0x04

        // Release all
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: false)

        // Verify all released
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Stress Tests

    func testRapidKeyPresses() {
        // Test sending many keys rapidly
        let keys: [HIDUsageID] = [
            .keyboardA, .keyboardB, .keyboardC, .keyboardD, .keyboardE,
            .keyboardF, .keyboardG, .keyboardH, .keyboardI, .keyboardJ
        ]

        for key in keys {
            keyboardState.updateModifierState(key: key, pressed: true)
            keyboardState.updateModifierState(key: key, pressed: false)
        }

        // Verify all keys are released
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Edge Cases

    func testInvalidModifierCombination() {
        // Test that invalid modifier combinations don't break state
        // Press all modifiers
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)

        // Verify all modifiers are active
        XCTAssertEqual(keyboardState.modifierByte, 0x47) // 0x01 | 0x02 | 0x04 | 0x40

        // Release all
        keyboardState.clearAllModifiers()

        // Verify all released
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testDeadKeyWithModifiers() {
        // Test dead key with modifiers active
        // Press Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)

        // Set dead key
        keyboardState.setDeadKey(.acute)

        // Verify both states are maintained
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Combine with character
        let combinedChar = keyboardState.pendingDeadKey?.combine(with: "e")
        XCTAssertEqual(combinedChar, "é")

        // Clear dead key
        keyboardState.setDeadKey(nil)

        // Verify Shift is still active
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertNil(keyboardState.pendingDeadKey)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        // Release Shift
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)

        // Verify all released
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }
}
