//
//  KeyCmdTests.swift
//  KeyCmdTests
//
//  Created by 彭志坚 on 2025/6/19.
//

import Testing
@testable import KeyCmd

struct KeyCmdTests {

    @Test func buildsKeyboardPacket() {
        let packet = Keymod.buildKeyboard(modifiers: KMod.ctrl.union(.shift).rawValue, keys: [0x04, 0x05])

        #expect(Array(packet) == [
            0x57, 0xAB, 0x00, 0x02, 0x08,
            0x03, 0x00, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00,
            0x18,
        ])
    }

    @Test func parsesNestedModifierToken() {
        let token = Keymod.parseToken("<CTRL><SHIFT>A</SHIFT></CTRL>")

        #expect(token.hidCode == 0x04)
        #expect(token.modifiers == KMod.ctrl.union(.shift).rawValue)
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
