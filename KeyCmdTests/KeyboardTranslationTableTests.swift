// KeyCmdTests/KeyboardTranslationTableTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardTranslationTableTests: XCTestCase {

    // MARK: - Helper to create test layout

    private func createTestLayout() -> KeyboardLayoutDefinition {
        let rows: [KeyRow] = [
            // Function row
            [
                KeyDefinition.key("Esc", "Esc", hid: .keyboardEscape),
                KeyDefinition.key("F1", "F1", hid: .keyboardF1),
                KeyDefinition.key("F2", "F2", hid: .keyboardF2)
            ],
            // Number row
            [
                KeyDefinition.key("1", "1", shift: "!", hid: .keyboard1),
                KeyDefinition.key("2", "2", shift: "@", hid: .keyboard2),
                KeyDefinition.key("3", "3", shift: "#", hid: .keyboard3)
            ],
            // QWERTY row
            [
                KeyDefinition.key("Tab", "Tab", hid: .keyboardTab),
                KeyDefinition.key("q", "Q", hid: .keyboardQ),
                KeyDefinition.key("w", "W", hid: .keyboardW),
                KeyDefinition.key("e", "E", shift: "€", altGr: "é", hid: .keyboardE)
            ],
            // ASDF row
            [
                KeyDefinition.key("Caps", "Caps", hid: .keyboardCapsLock),
                KeyDefinition.key("a", "A", hid: .keyboardA),
                KeyDefinition.key("s", "S", hid: .keyboardS),
                KeyDefinition.key("d", "D", hid: .keyboardD)
            ],
            // ZXCV row
            [
                KeyDefinition.mod("Shift", hid: .keyboardLeftShift),
                KeyDefinition.key("z", "Z", hid: .keyboardZ),
                KeyDefinition.key("x", "X", hid: .keyboardX),
                KeyDefinition.key("c", "C", hid: .keyboardC)
            ],
            // Bottom row
            [
                KeyDefinition.mod("Ctrl", hid: .keyboardLeftCtrl),
                KeyDefinition.key("Space", " ", hid: .keyboardSpace),
                KeyDefinition.mod("Alt", hid: .keyboardLeftAlt)
            ]
        ]

        let metadata = LayoutMetadata(
            name: "Test Layout",
            description: "Minimal test layout"
        )

        return KeyboardLayoutDefinition(
            locale: .us,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - HID to Position tests

    func testHIDToPosition() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        if let pos = table.position(forHID: .keyboardQ) {
            XCTAssertEqual(pos.row, 2, "Q should be in row 2 (QWERTY row)")
            XCTAssertEqual(pos.column, 1, "Q should be at column 1")
        } else {
            XCTFail("Position not found for keyboardQ")
        }
    }

    func testHIDToPositionForNumberRow() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        if let pos = table.position(forHID: .keyboard1) {
            XCTAssertEqual(pos.row, 1, "1 should be in row 1 (number row)")
            XCTAssertEqual(pos.column, 0, "1 should be at column 0")
        } else {
            XCTFail("Position not found for keyboard1")
        }
    }

    func testHIDToPositionForUnknownHID() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        // keyboardF13 is not in our test layout
        let unknownHID = HIDUsageID.keyboardLANG1
        XCTAssertNil(table.position(forHID: unknownHID), "Unknown HID should return nil")
    }

    // MARK: - Character to HID tests

    func testCharacterToHID() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        // Lowercase 'q' maps from label "Q"
        XCTAssertEqual(table.hidUsageID(forCharacter: "Q"), .keyboardQ, "Q should map to keyboardQ")

        // Uppercase 'Q' also maps from label "Q"
        XCTAssertEqual(table.hidUsageID(forCharacter: "Q"), .keyboardQ, "Q should map to keyboardQ")
    }

    func testCharacterToHIDForNumbers() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        XCTAssertEqual(table.hidUsageID(forCharacter: "1"), .keyboard1, "1 should map to keyboard1")
        XCTAssertEqual(table.hidUsageID(forCharacter: "2"), .keyboard2, "2 should map to keyboard2")
    }

    func testCharacterToHIDForShiftSymbols() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        // Shift+1 = !
        XCTAssertEqual(table.hidUsageID(forCharacter: "!"), .keyboard1, "! should map to keyboard1")

        // Shift+2 = @
        XCTAssertEqual(table.hidUsageID(forCharacter: "@"), .keyboard2, "@ should map to keyboard2")
    }

    func testCharacterToHIDForAltGrSymbols() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        // AltGr+E = é
        XCTAssertEqual(table.hidUsageID(forCharacter: "é"), .keyboardE, "é should map to keyboardE")
    }

    func testCharacterToHIDForUnknownChar() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        XCTAssertNil(table.hidUsageID(forCharacter: "§"), "Unknown character should return nil")
    }

    // MARK: - Position to HID tests

    func testPositionToHID() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        // Row 2, column 1 should be Q
        if let hid = table.hidUsageID(forPosition: 2, column: 1) {
            XCTAssertEqual(hid, .keyboardQ, "Position (2,1) should be Q")
        } else {
            XCTFail("HID not found for position (2,1)")
        }
    }

    func testPositionToHIDForInvalidPosition() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        XCTAssertNil(table.hidUsageID(forPosition: 99, column: 99), "Invalid position should return nil")
        XCTAssertNil(table.hidUsageID(forPosition: -1, column: 0), "Negative row should return nil")
        XCTAssertNil(table.hidUsageID(forPosition: 0, column: -1), "Negative column should return nil")
    }

    // MARK: - Round-trip tests

    func testRoundTripHIDToPositionToHID() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        let originalHID = HIDUsageID.keyboardA
        if let pos = table.position(forHID: originalHID) {
            let recoveredHID = table.hidUsageID(forPosition: pos.row, column: pos.column)
            XCTAssertEqual(recoveredHID, originalHID, "Round-trip HID->Position->HID should preserve value")
        } else {
            XCTFail("Position not found for keyboardA")
        }
    }

    func testRoundTripPositionToHIDToPosition() {
        let layout = createTestLayout()
        let table = KeyboardTranslationTable(layout: layout)

        let originalRow = 2
        let originalCol = 1

        if let hid = table.hidUsageID(forPosition: originalRow, column: originalCol) {
            if let pos = table.position(forHID: hid) {
                XCTAssertEqual(pos.row, originalRow, "Round-trip should preserve row")
                XCTAssertEqual(pos.column, originalCol, "Round-trip should preserve column")
            } else {
                XCTFail("Position not found for recovered HID")
            }
        } else {
            XCTFail("HID not found for position (\(originalRow), \(originalCol))")
        }
    }

    // MARK: - Different layout tests

    func testDifferentLayouts() {
        let layout1 = createTestLayout()
        let layout2 = createTestLayout()

        let table1 = KeyboardTranslationTable(layout: layout1)
        let table2 = KeyboardTranslationTable(layout: layout2)

        // Both should have keyboardQ
        XCTAssertNotNil(table1.position(forHID: .keyboardQ), "First layout should have Q")
        XCTAssertNotNil(table2.position(forHID: .keyboardQ), "Second layout should have Q")

        // Both should map to same position
        XCTAssertEqual(table1.position(forHID: .keyboardQ)?.row,
                      table2.position(forHID: .keyboardQ)?.row,
                      "Same key should be at same row in identical layouts")
    }
}
