// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import Testing
@testable import KeyCmd

struct KeyModTests {

    @Test func buildsKeyboardPacket() {
        let packet = Keymod.buildKeyboard(modifiers: KMod.ctrl.union(.shift).rawValue, keys: [0x04, 0x05])

        #expect(Array(packet) == [
            0x57, 0xAB, 0x00, 0x02, 0x08,
            0x03, 0x00, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00,
            0x18,
        ])
    }

    @Test func parsesNestedModifierToken() {
        // km_parse_token resolves one token in isolation; nested modifier tags are a
        // compound expression, which is km_parse_macro's job (open ORs the modifier in,
        // close ANDs it out).
        let tokens = Keymod.parseMacro("<CTRL><SHIFT>A</SHIFT></CTRL>")

        #expect(tokens.count == 1)
        #expect(tokens.first?.hidCode == 0x04)
        #expect(tokens.first?.modifiers == KMod.ctrl.union(.shift).rawValue)
    }

    @Test func parsesMacroAndSkipsDelayTokens() {
        let tokens = Keymod.parseMacro("<CTRL>a</CTRL><DELAY1S><ALT>b</ALT>")

        #expect(tokens.count == 2)
        #expect(tokens[0].hidCode == 0x04)
        #expect(tokens[0].modifiers == KMod.ctrl.rawValue)
        #expect(tokens[1].hidCode == 0x05)
        #expect(tokens[1].modifiers == KMod.alt.rawValue)
    }

    @Test func tokenizesUtf8AndTagsAsSeparateScriptTokens() {
        let tokens = Keymod.tokenizeScript("é<CTRL>中</CTRL>A")

        #expect(tokens == ["é", "<CTRL>", "中", "</CTRL>", "A"])
    }
}
