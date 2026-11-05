// KeyCmd/KeyboardTranslationTable.swift

import Foundation

/// KeyboardTranslationTable provides O(1) lookups between
/// HID usage IDs, physical key positions, and printable characters.
///
/// It is built from a KeyboardLayoutDefinition.
/// `stroke(forCharacter:)` returns the exact key and modifier layer needed to
/// type a character on the layout: Shift and AltGr are resolved from the JSON
/// labels instead of being guessed from the character's case.
///
/// `hidUsageID(forCharacter:)` is kept as a case-folding convenience lookup for
/// callers that only need the physical key.

struct KeyboardTranslationTable {

    /// Everything needed to type one character on the target host.
    struct KeyStroke: Equatable {
        let hidUsageID: HIDUsageID
        /// HID modifier byte bits (0x02 Shift, 0x40 AltGr/Right Alt).
        let modifiers: UInt8
        /// True when the character lives on a dead key.
        let isDeadKey: Bool
    }

    // MARK: Public API

    /// HID Usage ID → (row, column)
    private let hidToPosition: [HIDUsageID: (row: Int, column: Int)]

    /// (row, column) -> HID Usage ID
    private let positionToHid: [String: HIDUsageID]

    /// Character → HID Usage ID
    private let charToHid: [Character: HIDUsageID]

    /// Character → exact key + layer
    private let charToStroke: [Character: KeyStroke]

    // MARK: Initialise from layout

    init(layout: KeyboardLayoutDefinition) {
        var hidToPos = [HIDUsageID: (Int, Int)]()
        var posToHid = [String: HIDUsageID]()
        var charToH = [Character: HIDUsageID]()
        var charToS = [Character: KeyStroke]()

        for (rowIndex, row) in layout.rows.enumerated() {
            for (colIndex, keyDef) in row.enumerated() {
                let hid = keyDef.hidUsageID

                // HID → Position
                hidToPos[hid] = (rowIndex, colIndex)

                // Position → HID
                let posKey = "\(rowIndex)_\(colIndex)"
                posToHid[posKey] = hid

                // Modifier and special keys don't produce characters. Labels
                // such as "Menu" or "変換" are not typable characters either.
                guard keyDef.keyType == .regular || keyDef.keyType == .japaneseSpecial else { continue }

                let isDead = keyDef.deadKey != nil

                func record(_ char: Character, modifiers: UInt8) {
                    if let existing = charToS[char] {
                        // A dead-key mapping is the more faithful description of
                        // the same character, so it may replace a plain one.
                        guard isDead && !existing.isDeadKey else { return }
                    }
                    charToH[char] = hid
                    charToS[char] = KeyStroke(hidUsageID: hid, modifiers: modifiers, isDeadKey: isDead)
                }

                if keyDef.label.count == 1, let base = keyDef.label.first {
                    if base.isLetter {
                        // JSON letter labels are uppercase caps, but the
                        // unshifted layer types the lowercase character.
                        // Guard against letters whose case expansion is not
                        // one character (e.g. ß → "SS").
                        let lowerString = String(base).lowercased()
                        let upperString = String(base).uppercased()
                        if lowerString.count == 1, let lower = lowerString.first {
                            record(lower, modifiers: 0)
                        }
                        if upperString.count == 1, let upper = upperString.first,
                           upperString != lowerString {
                            record(upper, modifiers: KMod.shift.rawValue)
                        }
                    } else {
                        record(base, modifiers: 0)
                    }
                }

                if let shiftLabel = keyDef.shiftLabel, shiftLabel.count == 1, let shift = shiftLabel.first {
                    record(shift, modifiers: KMod.shift.rawValue)
                }

                if let altGrLabel = keyDef.altGrLabel, altGrLabel.count == 1, let altGr = altGrLabel.first {
                    record(altGr, modifiers: KMod.rAlt.rawValue)
                }
            }
        }

        self.hidToPosition = hidToPos
        self.positionToHid = posToHid
        self.charToHid = charToH
        self.charToStroke = charToS
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

    /// Returns the exact key + modifier layer for a character on this layout.
    func stroke(forCharacter char: Character) -> KeyStroke? {
        return charToStroke[char]
    }
}
