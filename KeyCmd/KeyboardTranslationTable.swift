// KeyCmd/KeyboardTranslationTable.swift

import Foundation

/// KeyboardTranslationTable provides O(1) lookups between
/// HID usage IDs, physical key positions, and printable characters.
///
/// It is built from a KeyboardLayoutDefinition.
/// All lookups are case-sensitive for characters.
/// The character mapping uses the first character of
/// `label`, `shiftLabel`, and `altGrLabel` for each key.
/// For example:
///   * key("q", "Q") -> label first = "Q"'
///   * key("1", "1", shift: "!") -> shiftLabel first = "!"
///
/// The table does not store any type information beyond
/// these three maps; additional lookup (e.g., key type)
/// can be derived from KeyboardLayoutDefinition if needed.

struct KeyboardTranslationTable {
    // MARK: Public API

    /// HID Usage ID → (row, column)
    private let hidToPosition: [HIDUsageID: (row: Int, column: Int)]

    /// (row, column) -> HID Usage ID
    private let positionToHid: [String: HIDUsageID]

    /// Character → HID Usage ID
    private let charToHid: [Character: HIDUsageID]

    // MARK: Initialise from layout

    init(layout: KeyboardLayoutDefinition) {
        var hidToPos = [HIDUsageID: (Int, Int)]()
        var posToHid = [String: HIDUsageID]()
        var charToH = [Character: HIDUsageID]()

        for (rowIndex, row) in layout.rows.enumerated() {
            for (colIndex, keyDef) in row.enumerated() {
                let hid = keyDef.hidUsageID

                // HID → Position
                hidToPos[hid] = (rowIndex, colIndex)

                // Position → HID
                let posKey = "\(rowIndex)_\(colIndex)"
                posToHid[posKey] = hid

                // Character → HID
                if let first = keyDef.label.first {
                    charToH[first] = hid
                }
                if let shift = keyDef.shiftLabel?.first {
                    charToH[shift] = hid
                }
                if let altGr = keyDef.altGrLabel?.first {
                    charToH[altGr] = hid
                }
            }
        }

        self.hidToPosition = hidToPos
        self.positionToHid = posToHid
        self.charToHid = charToH
    }

    // MARK: Public lookup helpers

    /// Returns the key position for a given HID Usage ID, if known.
    func position(forHID hid: HIDUsageID) -> (row: Int, column: Int)? {
        return hidToPosition[hid]
    }

    /// Returns the HID Usage ID for a given position.  The position is
    /// specified as (row, column).  Returns nil if out of bounds.
    func hidUsageID(forPosition row: Int, column: Int) -> HIDUsageID? {
        guard row >= 0, column >= 0 else { return nil }
        let key = "\(row)_\(column)"
        return positionToHid[key]
    }

    /// Returns the HID Usage ID for a given printable character.
    func hidUsageID(forCharacter char: Character) -> HIDUsageID? {
        return charToHid[char]
    }
}
