//
 //  KeyboardLayoutBuilders.swift
 //  KeyMod
 //

import Foundation
import SwiftUI

/// Windows/Linux keyboard layout builder
struct WindowsLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        switch locale {
        case .us:
            return buildUsLayout()
        case .uk:
            return buildUkLayout()
        case .de:
            return buildDeLayout()
        case .fr:
            return buildFrLayout()
        case .es:
            return buildEsLayout()
        case .it:
            return buildItLayout()
        case .pt:
            return buildPtLayout()
        case .jp:
            return buildJpLayout()
        case .cn:
            return buildUsLayout() // Chinese usually uses US layout
        case .ca:
            return buildCaLayout() // Canada has English and French variants, defaulting to English here
        case .au:
            return buildUkLayout() // Australia is same as UK
        case .be:
            return buildBeLayout() // Belgium AZERTY variant
        case .ch:
            return buildChLayout() // Switzerland QWERTZ variant
        case .nordic:
            return buildNordicLayout() // Nordic layout
        }
    }

    // MARK: - US Layout (QWERTY)
    private static func buildUsLayout() -> KeyboardLayoutDefinition {
        let rows: [KeyRow] = [
            // Function row
            [
                KeyDefinition.key("Esc", "Esc"),
                KeyDefinition.key("F1", "F1"),
                KeyDefinition.key("F2", "F2"),
                KeyDefinition.key("F3", "F3"),
                KeyDefinition.key("F4", "F4"),
                KeyDefinition.key("F5", "F5"),
                KeyDefinition.key("F6", "F6"),
                KeyDefinition.key("F7", "F7"),
                KeyDefinition.key("F8", "F8"),
                KeyDefinition.key("F9", "F9"),
                KeyDefinition.key("F10", "F10"),
                KeyDefinition.key("F11", "F11"),
                KeyDefinition.key("F12", "F12")
            ],
            // Number row
            [
                KeyDefinition.key("`", "`", shift: "~"),
                KeyDefinition.key("1", "1", shift: "!"),
                KeyDefinition.key("2", "2", shift: "@"),
                KeyDefinition.key("3", "3", shift: "#"),
                KeyDefinition.key("4", "4", shift: "$"),
                KeyDefinition.key("5", "5", shift: "%"),
                KeyDefinition.key("6", "6", shift: "^"),
                KeyDefinition.key("7", "7", shift: "&"),
                KeyDefinition.key("8", "8", shift: "*"),
                KeyDefinition.key("9", "9", shift: "("),
                KeyDefinition.key("0", "0", shift: ")"),
                KeyDefinition.key("-", "-", shift: "_"),
                KeyDefinition.key("=", "=", shift: "+"),
                KeyDefinition.key("Backspace", "Backspace")
            ],
            // QWERTY first row
            [
                KeyDefinition.key("Tab", "Tab"),
                KeyDefinition.key("q", "Q"),
                KeyDefinition.key("w", "W"),
                KeyDefinition.key("e", "E"),
                KeyDefinition.key("r", "R"),
                KeyDefinition.key("t", "T"),
                KeyDefinition.key("y", "Y"),
                KeyDefinition.key("u", "U"),
                KeyDefinition.key("i", "I"),
                KeyDefinition.key("o", "O"),
                KeyDefinition.key("p", "P"),
                KeyDefinition.key("[", "[", shift: "{"),
                KeyDefinition.key("]", "]", shift: "}"),
                KeyDefinition.key("\\", "\\", shift: "|")
            ],
            // ASDF second row
            [
                KeyDefinition.key("Caps", "Caps"),
                KeyDefinition.key("a", "a"),
                KeyDefinition.key("s", "s"),
                KeyDefinition.key("d", "d"),
                KeyDefinition.key("f", "f"),
                KeyDefinition.key("g", "g"),
                KeyDefinition.key("h", "h"),
                KeyDefinition.key("j", "j"),
                KeyDefinition.key("k", "k"),
                KeyDefinition.key("l", "l"),
                KeyDefinition.key(";", ";", shift: ":"),
                KeyDefinition.key("'", "'", shift: "\""),
                KeyDefinition.key("Enter", "Enter")
            ],
            // ZXCV third row
            [
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("z", "z"),
                KeyDefinition.key("x", "x"),
                KeyDefinition.key("c", "c"),
                KeyDefinition.key("v", "v"),
                KeyDefinition.key("b", "b"),
                KeyDefinition.key("n", "n"),
                KeyDefinition.key("m", "m"),
                KeyDefinition.key(",", ",", shift: "<"),
                KeyDefinition.key(".", ".", shift: ">"),
                KeyDefinition.key("/", "/", shift: "?"),
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("Up", "↑")
            ],
            // Bottom modifier row
            [
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.mod("Win"),
                KeyDefinition.mod("Alt"),
                KeyDefinition.key("Space", " ", width: 6.0),
                KeyDefinition.mod("Alt"),
                KeyDefinition.mod("Win"),
                KeyDefinition.key("Menu", "Menu", keyCode: "App"),
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.key("Left", "←"),
                KeyDefinition.key("Down", "↓"),
                KeyDefinition.key("Right", "→")
            ]
        ]

        let metadata = LayoutMetadata(
            name: "US QWERTY Windows",
            description: "Standard US QWERTY layout for Windows",
            rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
            keySpacing: 3,
            rowSpacing: 6,
            padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
            fixedKeyWidths: ["Space": 200],
            physicalStandard: .ansi
        )

        return KeyboardLayoutDefinition(
            locale: .us,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - UK Layout (QWERTY with UK-specific symbols)
    private static func buildUkLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // UK-specific modifications:
        // - 2: " instead of @
        // - 3: £ instead of #
        // - \ (near enter) shows # instead of \
        // - \ (between left shift and Z) shows ¬ instead

        // Modify number row
        if rows.count > 1 {
            var numberRow = rows[1]
            if numberRow.count > 3 {
                numberRow[2] = KeyDefinition.key("2", "2", shift: "\"", keyCode: "2") // " instead of @
                numberRow[3] = KeyDefinition.key("3", "3", shift: "£", keyCode: "3") // £ instead of #
                rows[1] = numberRow
            }
        }

        // Modify the backslash key (between [ and Enter) to show # instead
        if rows.count > 2 {
            var topRow = rows[2]
            if let backslashIndex = topRow.firstIndex(where: { $0.keyName == "\\" }) {
                topRow[backslashIndex] = KeyDefinition.key("#", "#", shift: "~", keyCode: "Backslash") // # instead of \
                rows[2] = topRow
            }
        }

        // Modify the key between left shift and Z to show \ instead of `
        if rows.count > 4 {
            var bottomRow = rows[4]
            // Find the key after left shift (which should be ` in US layout)
            if let backquoteIndex = bottomRow.firstIndex(where: { $0.keyName == "`" }) {
                bottomRow[backquoteIndex] = KeyDefinition.key("\\", "\\", shift: "|", keyCode: "IntlBackslash") // \ instead of `
                rows[4] = bottomRow
            }
        }

        let metadata = LayoutMetadata(
            name: "UK QWERTY Windows",
            description: "UK QWERTY layout with pound and euro symbols",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso
        )

        return KeyboardLayoutDefinition(
            locale: .uk,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - German Layout (QWERTZ)
    private static func buildDeLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // German-specific modifications:
        // - Z and Y swapped
        // - Special characters in different positions

        // Swap Z and Y in the top letter row (index 2)
        if rows.count > 2 {
            var topRow = rows[2]
            if topRow.count > 6 {
                let temp = topRow[5] // Y position
                topRow[5] = topRow[6] // Z position
                topRow[6] = temp
                rows[2] = topRow
            }
        }

        let metadata = LayoutMetadata(
            name: "German QWERTZ Windows",
            description: "German QWERTZ layout with Z/Y swapped",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso
        )

        return KeyboardLayoutDefinition(
            locale: .de,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - French Layout (AZERTY)
    private static func buildFrLayout() -> KeyboardLayoutDefinition {
        // French AZERTY layout is significantly different
        let rows: [KeyRow] = [
            // Function row (same as US)
            [
                KeyDefinition.key("Esc", "Esc"),
                KeyDefinition.key("F1", "F1"),
                KeyDefinition.key("F2", "F2"),
                KeyDefinition.key("F3", "F3"),
                KeyDefinition.key("F4", "F4"),
                KeyDefinition.key("F5", "F5"),
                KeyDefinition.key("F6", "F6"),
                KeyDefinition.key("F7", "F7"),
                KeyDefinition.key("F8", "F8"),
                KeyDefinition.key("F9", "F9"),
                KeyDefinition.key("F10", "F10"),
                KeyDefinition.key("F11", "F11"),
                KeyDefinition.key("F12", "F12")
            ],
            // Number row (AZERTY: &é"'(-è_çà)=
            [
                KeyDefinition.key("&", "&", shift: "1", keyCode: "1"),
                KeyDefinition.key("é", "é", shift: "2", keyCode: "2"),
                KeyDefinition.key("\"", "\"", shift: "3", keyCode: "3"),
                KeyDefinition.key("'", "'", shift: "4", keyCode: "4"),
                KeyDefinition.key("(", "(", shift: "5", keyCode: "5"),
                KeyDefinition.key("-", "-", shift: "6", keyCode: "6"),
                KeyDefinition.key("è", "è", shift: "7", keyCode: "7"),
                KeyDefinition.key("_", "_", shift: "8", keyCode: "8"),
                KeyDefinition.key("ç", "ç", shift: "9", keyCode: "9"),
                KeyDefinition.key("à", "à", shift: "0", keyCode: "0"),
                KeyDefinition.key(")", ")", shift: "-", keyCode: "Minus"),
                KeyDefinition.key("=", "=", shift: "+", keyCode: "Equal"),
                KeyDefinition.key("Backspace", "Backspace")
            ],
            // Top letter row (AZERTY: A Z E R T Y U I O P ^ $
            [
                KeyDefinition.key("Tab", "Tab"),
                KeyDefinition.key("a", "a"),
                KeyDefinition.key("z", "z"),
                KeyDefinition.key("e", "e"),
                KeyDefinition.key("r", "r"),
                KeyDefinition.key("t", "t"),
                KeyDefinition.key("y", "y"),
                KeyDefinition.key("u", "u"),
                KeyDefinition.key("i", "i"),
                KeyDefinition.key("o", "o"),
                KeyDefinition.key("p", "p"),
                KeyDefinition.key("^", "^", shift: "$", keyCode: "BracketLeft"), // ^ on [ key
                KeyDefinition.key("$", "$", shift: "", keyCode: "BracketRight"), // $ on ] key
                KeyDefinition.key("*", "*", shift: "µ", keyCode: "Backslash") // * on \ key
            ],
            // Home row (Q S D F G H J K L M M ù
            [
                KeyDefinition.key("Caps", "Caps"),
                KeyDefinition.key("q", "q"),
                KeyDefinition.key("s", "s"),
                KeyDefinition.key("d", "d"),
                KeyDefinition.key("f", "f"),
                KeyDefinition.key("g", "g"),
                KeyDefinition.key("h", "h"),
                KeyDefinition.key("j", "j"),
                KeyDefinition.key("k", "k"),
                KeyDefinition.key("l", "l"),
                KeyDefinition.key("m", "m"),
                KeyDefinition.key("%", "%", shift: "µ", keyCode: "Digit5"), // % on 5 key
                KeyDefinition.key("£", "£", shift: "", keyCode: "Quote"), // £ on ' key
                KeyDefinition.key("Enter", "Enter")
            ],
            // Bottom letter row (W X C V B N N ? . / §
            [
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("w", "w"),
                KeyDefinition.key("x", "x"),
                KeyDefinition.key("c", "c"),
                KeyDefinition.key("v", "v"),
                KeyDefinition.key("b", "b"),
                KeyDefinition.key("n", "n"),
                KeyDefinition.key("?", "?", shift: ".", keyCode: "Slash"), // ? on / key
                KeyDefinition.key(".", ".", shift: ";", keyCode: "Period"), // . on . key
                KeyDefinition.key("/", "/", shift: ":", keyCode: "Semicolon"), // / on ; key
                KeyDefinition.key("§", "§", shift: "!", keyCode: "Backquote"), // § on ` key
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("Up", "↑")
            ],
            // Bottom modifier row
            [
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.mod("Win"),
                KeyDefinition.mod("Alt"),
                KeyDefinition.key("Space", " ", width: 6.0),
                KeyDefinition.mod("AltGr"), // French uses AltGr
                KeyDefinition.mod("Win"),
                KeyDefinition.key("Menu", "Menu", keyCode: "App"),
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.key("Left", "←"),
                KeyDefinition.key("Down", "↓"),
                KeyDefinition.key("Right", "→")
            ]
        ]

        let metadata = LayoutMetadata(
            name: "French AZERTY Windows",
            description: "French AZERTY layout",
            rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
            keySpacing: 3,
            rowSpacing: 6,
            padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
            fixedKeyWidths: ["Space": 200],
            physicalStandard: .iso
        )

        return KeyboardLayoutDefinition(
            locale: .fr,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Spanish Layout (QWERTY with Ñ)
    private static func buildEsLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // Spanish-specific modifications:
        // - Add Ñ key next to L
        // - Some special character differences

        // Insert Ñ after L in the home row
        if rows.count > 3 {
            var homeRow = rows[3]
            if let lIndex = homeRow.firstIndex(where: { $0.keyName == "l" }) {
                let nKey = KeyDefinition.key("ñ", "ñ", shift: "Ñ", keyCode: "Semicolon") // ñ on ; key
                homeRow.insert(nKey, at: lIndex + 1)
                rows[3] = homeRow
            }
        }

        let metadata = LayoutMetadata(
            name: "Spanish QWERTY Windows",
            description: "Spanish QWERTY layout with Ñ",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso
        )

        return KeyboardLayoutDefinition(
            locale: .es,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Italian Layout (QWERTY with accented characters)
    private static func buildItLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // Italian-specific modifications:
        // - Add special characters via AltGr
        // - Modify some keys for Italian layout

        // Number row: some characters differ
        if rows.count > 1 {
            let numberRow = rows[1]
            // In Italian layout, some shift characters differ
            // For example, ' and " are more accessible
            rows[1] = numberRow
        }

        // Add ò, à, è, ì, ù keys in the top rows (accessible via special keys)
        // These are typically on the right side in Italian keyboards

        let metadata = LayoutMetadata(
            name: "Italian QWERTY Windows",
            description: "Italian QWERTY layout with accented characters",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso,
            hasAltGr: true // Italian layout uses AltGr for special characters
        )

        return KeyboardLayoutDefinition(
            locale: .it,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Portuguese Layout (QWERTY with ç and accented characters)
    private static func buildPtLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // Portuguese-specific modifications:
        // - Ç character (cedilla)
        // - Accented characters (á, é, í, ó, ú, â, ê, ô)
        // - Special characters via AltGr

        // Add dedicated Ç key in the home row (after L)
        if rows.count > 3 {
            var homeRow = rows[3]
            // Find the L key and insert Ç after it
            if let lIndex = homeRow.firstIndex(where: { $0.keyName == "l" }) {
                let cCedilhaKey = KeyDefinition.key("ç", "ç", shift: "Ç", keyCode: "Semicolon") // Ç on ; key
                homeRow.insert(cCedilhaKey, at: lIndex + 1)
                rows[3] = homeRow
            }
        }

        let metadata = LayoutMetadata(
            name: "Portuguese QWERTY Windows",
            description: "Portuguese QWERTY layout with ç",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso,
            hasAltGr: true // Portuguese layout uses AltGr
        )

        return KeyboardLayoutDefinition(
            locale: .pt,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Japanese Layout (JIS)
    private static func buildJpLayout() -> KeyboardLayoutDefinition {
        // Japanese JIS layout has additional keys
        let rows: [KeyRow] = [
            // Function row
            [
                KeyDefinition.key("Esc", "Esc"),
                KeyDefinition.key("F1", "F1"),
                KeyDefinition.key("F2", "F2"),
                KeyDefinition.key("F3", "F3"),
                KeyDefinition.key("F4", "F4"),
                KeyDefinition.key("F5", "F5"),
                KeyDefinition.key("F6", "F6"),
                KeyDefinition.key("F7", "F7"),
                KeyDefinition.key("F8", "F8"),
                KeyDefinition.key("F9", "F9"),
                KeyDefinition.key("F10", "F10"),
                KeyDefinition.key("F11", "F11"),
                KeyDefinition.key("F12", "F12")
            ],
            // Number row (similar to US but with backtick replaced by backslash)
            [
                KeyDefinition.key("\\", "\\", shift: "_", keyCode: "Backslash"), // Japanese JIS has \ instead of `
                KeyDefinition.key("1", "1", shift: "!"),
                KeyDefinition.key("2", "2", shift: "@"),
                KeyDefinition.key("3", "3", shift: "#"),
                KeyDefinition.key("4", "4", shift: "$"),
                KeyDefinition.key("5", "5", shift: "%"),
                KeyDefinition.key("6", "6", shift: "^"),
                KeyDefinition.key("7", "7", shift: "&"),
                KeyDefinition.key("8", "8", shift: "*"),
                KeyDefinition.key("9", "9", shift: "("),
                KeyDefinition.key("0", "0", shift: ")"),
                KeyDefinition.key("-", "-", shift: "="),
                KeyDefinition.key("^", "^", shift: "~", keyCode: "Minus"), // ^ instead of -
                KeyDefinition.key("Backspace", "Backspace")
            ],
            // Top letter row (includes ¥ key)
            [
                KeyDefinition.key("Tab", "Tab"),
                KeyDefinition.key("q", "q"),
                KeyDefinition.key("w", "w"),
                KeyDefinition.key("e", "e"),
                KeyDefinition.key("r", "r"),
                KeyDefinition.key("t", "t"),
                KeyDefinition.key("y", "y"),
                KeyDefinition.key("u", "u"),
                KeyDefinition.key("i", "i"),
                KeyDefinition.key("o", "o"),
                KeyDefinition.key("p", "p"),
                KeyDefinition.key("@", "@", shift: "`", keyCode: "BracketLeft"), // @ instead of [
                KeyDefinition.key("[", "[", shift: "{"),
                KeyDefinition.key("]", "]", shift: "}"),
                KeyDefinition.key("¥", "¥", shift: "|", keyCode: "IntlBackslash"), // ¥ instead of \ (keyCode is IntlBackslash)
            ],
            // Home row
            [
                KeyDefinition.key("Caps", "Caps"),
                KeyDefinition.key("a", "a"),
                KeyDefinition.key("s", "s"),
                KeyDefinition.key("d", "d"),
                KeyDefinition.key("f", "f"),
                KeyDefinition.key("g", "g"),
                KeyDefinition.key("h", "h"),
                KeyDefinition.key("j", "j"),
                KeyDefinition.key("k", "k"),
                KeyDefinition.key("l", "l"),
                KeyDefinition.key(";", ";", shift: "+", keyCode: ";"), // ; instead of :
                KeyDefinition.key(":", ":", shift: "*", keyCode: "'"), // : instead of "
                KeyDefinition.key("Enter", "Enter")
            ],
            // Bottom letter row
            [
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("z", "z"),
                KeyDefinition.key("x", "x"),
                KeyDefinition.key("c", "c"),
                KeyDefinition.key("v", "v"),
                KeyDefinition.key("b", "b"),
                KeyDefinition.key("n", "n"),
                KeyDefinition.key("m", "m"),
                KeyDefinition.key(",", ",", shift: "<"),
                KeyDefinition.key(".", ".", shift: ">"),
                KeyDefinition.key("/", "/", shift: "?"),
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.special("Ro", label: "Ro", keyCode: "Ro"), // Romaji key
                KeyDefinition.key("Up", "↑")
            ],
            // Bottom modifier row (with additional keys for Japanese)
            [
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.jpSpecial("半角/全角", label: "半角/全角"), // Hankaku/Zenkaku key
                KeyDefinition.mod("Alt"),
                KeyDefinition.key("Space", " ", width: 6.0),
                KeyDefinition.mod("Alt"),
                KeyDefinition.jpSpecial("変換", label: "変換"), // Conversion key
                KeyDefinition.jpSpecial("無変換", label: "無変換"), // Non-conversion key
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.key("Left", "←"),
                KeyDefinition.key("Down", "↓"),
                KeyDefinition.key("Right", "→")
            ]
        ]

        let metadata = LayoutMetadata(
            name: "Japanese JIS Windows",
            description: "Japanese JIS layout with additional keys",
            rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
            keySpacing: 3,
            rowSpacing: 6,
            padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
            fixedKeyWidths: ["Space": 200],
            physicalStandard: .jis
        )

        return KeyboardLayoutDefinition(
            locale: .jp,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Canadian Layout (English variant)
    private static func buildCaLayout() -> KeyboardLayoutDefinition {
        // Canadian English is essentially the same as US layout
        return buildUsLayout()
    }

    // MARK: - Belgian Layout (AZERTY variant)
    private static func buildBeLayout() -> KeyboardLayoutDefinition {
        // Belgian AZERTY is similar to French but with some differences
        // Key differences from French AZERTY:
        // - Some special characters are in different positions
        // - AltGr is used for additional characters
        let frLayout = buildFrLayout()

        // Belgian layout has some character differences
        // For now, using French AZERTY as base with minor adjustments
        let metadata = LayoutMetadata(
            name: "Belgian AZERTY Windows",
            description: "Belgian AZERTY layout (similar to French)",
            rowHeights: frLayout.metadata.rowHeights,
            keySpacing: frLayout.metadata.keySpacing,
            rowSpacing: frLayout.metadata.rowSpacing,
            padding: frLayout.metadata.padding,
            fixedKeyWidths: frLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso,
            hasAltGr: true
        )

        return KeyboardLayoutDefinition(
            locale: .be,
            targetOS: .windows,
            rows: frLayout.rows,
            metadata: metadata
        )
    }

    // MARK: - Swiss Layout (QWERTZ variant)
    private static func buildChLayout() -> KeyboardLayoutDefinition {
        // Swiss German keyboard (QWERTZ) - similar to German but with differences
        let rows: [KeyRow] = [
            // Function row (same as US)
            [
                KeyDefinition.key("Esc", "Esc"),
                KeyDefinition.key("F1", "F1"),
                KeyDefinition.key("F2", "F2"),
                KeyDefinition.key("F3", "F3"),
                KeyDefinition.key("F4", "F4"),
                KeyDefinition.key("F5", "F5"),
                KeyDefinition.key("F6", "F6"),
                KeyDefinition.key("F7", "F7"),
                KeyDefinition.key("F8", "F8"),
                KeyDefinition.key("F9", "F9"),
                KeyDefinition.key("F10", "F10"),
                KeyDefinition.key("F11", "F11"),
                KeyDefinition.key("F12", "F12")
            ],
            // Number row (Swiss: numbers have different shift characters)
            [
                KeyDefinition.key("§", "§", shift: "°", keyCode: "IntlBackslash"), // § on \ key
                KeyDefinition.key("1", "1", shift: "+", keyCode: "1"),
                KeyDefinition.key("2", "2", shift: "\"", keyCode: "2"),
                KeyDefinition.key("3", "3", shift: "*", keyCode: "3"),
                KeyDefinition.key("4", "4", shift: "ç", keyCode: "4"),
                KeyDefinition.key("5", "5", shift: "%", keyCode: "5"),
                KeyDefinition.key("6", "6", shift: "&", keyCode: "6"),
                KeyDefinition.key("7", "7", shift: "/", keyCode: "7"),
                KeyDefinition.key("8", "8", shift: "(", keyCode: "8"),
                KeyDefinition.key("9", "9", shift: ")", keyCode: "9"),
                KeyDefinition.key("0", "0", shift: "=", keyCode: "0"),
                KeyDefinition.key("'", "'", shift: "?", keyCode: "Quote"),
                KeyDefinition.key("^", "^", shift: "`", keyCode: "Backquote"),
                KeyDefinition.key("Backspace", "Backspace")
            ],
            // Top letter row (Swiss QWERTZ with Z/Y swap and special chars)
            [
                KeyDefinition.key("Tab", "Tab"),
                KeyDefinition.key("q", "q"),
                KeyDefinition.key("w", "w"),
                KeyDefinition.key("e", "e"),
                KeyDefinition.key("r", "r"),
                KeyDefinition.key("t", "t"),
                KeyDefinition.key("z", "z"), // Z before Y in Swiss
                KeyDefinition.key("u", "u"),
                KeyDefinition.key("i", "i"),
                KeyDefinition.key("o", "o"),
                KeyDefinition.key("p", "p"),
                KeyDefinition.key("ü", "ü", shift: "è", keyCode: "BracketLeft"), // ü on [ key
                KeyDefinition.key("¨", "¨", shift: "!", keyCode: "BracketRight") // ¨ on ] key (dead key for umlaut)
            ],
            // Home row (Swiss with ä and special characters)
            [
                KeyDefinition.key("Caps", "Caps"),
                KeyDefinition.key("a", "a"),
                KeyDefinition.key("s", "s"),
                KeyDefinition.key("d", "d"),
                KeyDefinition.key("f", "f"),
                KeyDefinition.key("g", "g"),
                KeyDefinition.key("h", "h"),
                KeyDefinition.key("j", "j"),
                KeyDefinition.key("k", "k"),
                KeyDefinition.key("l", "l"),
                KeyDefinition.key("ö", "ö", shift: "é", keyCode: "Semicolon"), // ö on ; key
                KeyDefinition.key("ä", "ä", shift: "à", keyCode: "Quote"), // ä on ' key
                KeyDefinition.key("$", "$", shift: "£", keyCode: "Backslash"), // $ on \ key
                KeyDefinition.key("Enter", "Enter")
            ],
            // Bottom letter row
            [
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("y", "y"), // Y after Z in Swiss
                KeyDefinition.key("x", "x"),
                KeyDefinition.key("c", "c"),
                KeyDefinition.key("v", "v"),
                KeyDefinition.key("b", "b"),
                KeyDefinition.key("n", "n"),
                KeyDefinition.key("m", "m"),
                KeyDefinition.key(",", ",", shift: ";"),
                KeyDefinition.key(".", ".", shift: ":"),
                KeyDefinition.key("-", "-", shift: "_"),
                KeyDefinition.key("Shift", "Shift", width: 1.5),
                KeyDefinition.key("Up", "↑")
            ],
            // Bottom modifier row
            [
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.mod("Win"),
                KeyDefinition.mod("Alt"),
                KeyDefinition.key("Space", " ", width: 6.0),
                KeyDefinition.mod("AltGr"), // Swiss uses AltGr
                KeyDefinition.mod("Win"),
                KeyDefinition.key("Menu", "Menu", keyCode: "App"),
                KeyDefinition.mod("Ctrl"),
                KeyDefinition.key("Left", "←"),
                KeyDefinition.key("Down", "↓"),
                KeyDefinition.key("Right", "→")
            ]
        ]

        let metadata = LayoutMetadata(
            name: "Swiss QWERTZ Windows",
            description: "Swiss German QWERTZ layout with Z/Y swap and special characters",
            rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
            keySpacing: 3,
            rowSpacing: 6,
            padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
            fixedKeyWidths: ["Space": 200],
            physicalStandard: .iso,
            hasAltGr: true
        )

        return KeyboardLayoutDefinition(
            locale: .ch,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }

    // MARK: - Nordic Layout
    private static func buildNordicLayout() -> KeyboardLayoutDefinition {
        let usLayout = buildUsLayout()
        var rows = usLayout.rows

        // Nordic layout (Swedish/Finnish) - QWERTY with additional keys for Å, Ä, Ö
        // The Nordic layout has three additional keys to the right of P and L

        // Top letter row: add Å and ¨ (dead key for umlaut) after P
        if rows.count > 2 {
            var topRow = rows[2]
            // Add Å key after ]
            if let bracketIndex = topRow.firstIndex(where: { $0.keyName == "]" }) {
                let aringKey = KeyDefinition.key("å", "å", shift: "Å", keyCode: "Backslash") // å on \ key
                let diaeresisKey = KeyDefinition.key("¨", "¨", shift: "^", keyCode: "IntlBackslash") // dead key for umlaut
                topRow.insert(contentsOf: [aringKey, diaeresisKey], at: bracketIndex + 1)
                rows[2] = topRow
            }
        }

        // Home row: add Ä and Ö after L
        if rows.count > 3 {
            var homeRow = rows[3]
            if let lIndex = homeRow.firstIndex(where: { $0.keyName == "l" }) {
                let aumlKey = KeyDefinition.key("ä", "ä", shift: "Ä", keyCode: "Semicolon") // ä on ; key
                let oumlKey = KeyDefinition.key("ö", "ö", shift: "Ö", keyCode: "Quote") // ö on ' key
                homeRow.insert(contentsOf: [aumlKey, oumlKey], at: lIndex + 1)
                rows[3] = homeRow
            }
        }

        let metadata = LayoutMetadata(
            name: "Nordic QWERTY Windows",
            description: "Nordic layout with Å, Ä, Ö",
            rowHeights: usLayout.metadata.rowHeights,
            keySpacing: usLayout.metadata.keySpacing,
            rowSpacing: usLayout.metadata.rowSpacing,
            padding: usLayout.metadata.padding,
            fixedKeyWidths: usLayout.metadata.fixedKeyWidths,
            physicalStandard: .iso,
            hasAltGr: true // Nordic layout uses AltGr for additional characters
        )

        return KeyboardLayoutDefinition(
            locale: .nordic,
            targetOS: .windows,
            rows: rows,
            metadata: metadata
        )
    }
}

/// macOS keyboard layout builder
struct MacLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        // Get the base Windows/Linux layout
        let baseLayout = WindowsLayoutBuilder.build(for: locale)

        // Modify for macOS: change modifier labels and potentially bottom row
        var modifiedRows = baseLayout.rows

        // Update the bottom modifier row for macOS
        // The Windows layout uses keyNames: "Ctrl", "Win", "Alt", "Menu"
        // macOS needs: "Ctrl" → "Control", "Win" → "⌘", "Alt" → "⌥"
        if modifiedRows.count > 0 {
            let bottomRowIndex = modifiedRows.count - 1
            if bottomRowIndex >= 0 && bottomRowIndex < modifiedRows.count {
                var bottomRow = modifiedRows[bottomRowIndex]
                for i in 0..<bottomRow.count {
                    let keyName = bottomRow[i].keyName
                    switch keyName {
                    case "Ctrl":
                        bottomRow[i] = KeyDefinition.mod(keyName, label: "⌃")
                    case "Win":
                        bottomRow[i] = KeyDefinition.mod(keyName, label: "⌘")
                    case "Alt":
                        bottomRow[i] = KeyDefinition.mod(keyName, label: "⌥")
                    case "Menu":
                        // macOS doesn't have a Menu key, hide it or relabel
                        bottomRow[i] = KeyDefinition.mod(keyName, label: "fn")
                    default:
                        break
                    }
                }
                modifiedRows[bottomRowIndex] = bottomRow
            }
        }

        let metadata = LayoutMetadata(
            name: baseLayout.metadata.name.replacingOccurrences(of: "Windows", with: "macOS"),
            description: baseLayout.metadata.description,
            rowHeights: baseLayout.metadata.rowHeights,
            keySpacing: baseLayout.metadata.keySpacing,
            rowSpacing: baseLayout.metadata.rowSpacing,
            padding: baseLayout.metadata.padding,
            fixedKeyWidths: baseLayout.metadata.fixedKeyWidths,
            physicalStandard: baseLayout.metadata.physicalStandard,
            hasAltGr: baseLayout.metadata.hasAltGr
        )

        return KeyboardLayoutDefinition(
            locale: locale,
            targetOS: .macOS,
            rows: modifiedRows,
            metadata: metadata
        )
    }
}

/// Linux keyboard layout builder
struct LinuxLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        // Linux typically uses the same layout as Windows
        return WindowsLayoutBuilder.build(for: locale)
    }
}