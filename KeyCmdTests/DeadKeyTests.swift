// KeyCmdTests/DeadKeyTests.swift
import XCTest
@testable import KeyCmd

final class DeadKeyTests: XCTestCase {

    func testDeadKeyCombine() {
        // Test acute accent
        XCTAssertEqual(DeadKey.acute.combine(with: "a"), "á")
        XCTAssertEqual(DeadKey.acute.combine(with: "e"), "é")
        XCTAssertEqual(DeadKey.acute.combine(with: "i"), "í")
        XCTAssertEqual(DeadKey.acute.combine(with: "o"), "ó")
        XCTAssertEqual(DeadKey.acute.combine(with: "u"), "ú")

        // Test grave accent
        XCTAssertEqual(DeadKey.grave.combine(with: "a"), "à")
        XCTAssertEqual(DeadKey.grave.combine(with: "e"), "è")
        XCTAssertEqual(DeadKey.grave.combine(with: "i"), "ì")
        XCTAssertEqual(DeadKey.grave.combine(with: "o"), "ò")
        XCTAssertEqual(DeadKey.grave.combine(with: "u"), "ù")

        // Test circumflex
        XCTAssertEqual(DeadKey.circumflex.combine(with: "a"), "â")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "e"), "ê")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "i"), "î")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "o"), "ô")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "u"), "û")

        // Test diaeresis (umlaut)
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "a"), "ä")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "e"), "ë")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "i"), "ï")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "o"), "ö")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "u"), "ü")

        // Test tilde
        XCTAssertEqual(DeadKey.tilde.combine(with: "a"), "ã")
        XCTAssertEqual(DeadKey.tilde.combine(with: "n"), "ñ")
        XCTAssertEqual(DeadKey.tilde.combine(with: "o"), "õ")

        // Test ring
        XCTAssertEqual(DeadKey.ring.combine(with: "a"), "å")

        // Test cedilla
        XCTAssertEqual(DeadKey.cedilla.combine(with: "c"), "ç")
    }

    func testDeadKeySymbol() {
        XCTAssertEqual(DeadKey.acute.symbol, "´")
        XCTAssertEqual(DeadKey.grave.symbol, "`")
        XCTAssertEqual(DeadKey.circumflex.symbol, "^")
        XCTAssertEqual(DeadKey.diaeresis.symbol, "¨")
        XCTAssertEqual(DeadKey.tilde.symbol, "~")
        XCTAssertEqual(DeadKey.ring.symbol, "°")
        XCTAssertEqual(DeadKey.cedilla.symbol, "¸")
    }

    func testDeadKeyCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test encoding
        let acute = DeadKey.acute
        let data = try encoder.encode(acute)
        // Codable 编码为 JSON 字符串（带引号）
        let jsonString = String(data: data, encoding: .utf8)!
        XCTAssertEqual(jsonString, "\"acute\"")

        // Test decoding
        let decoded = try decoder.decode(DeadKey.self, from: data)
        XCTAssertEqual(decoded, acute)
    }

    func testLayoutWithDeadKeys() throws {
        // Set up layouts directory for testing
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let layoutsPath = "\(projectRoot)/Resources/KeyboardLayouts"
        KeyboardLayoutLoader.layoutsDirectoryOverride = layoutsPath
        defer { KeyboardLayoutLoader.layoutsDirectoryOverride = nil }

        // Load German layout which has dead keys
        let layout = try KeyboardLayoutLoader.load(locale: .de, targetOS: .macOS)

        // Find circumflex key (should be on ^ key)
        let circumflexKey = layout.allKeys.first { $0.deadKey == .circumflex }
        XCTAssertNotNil(circumflexKey, "German layout should have a circumflex dead key")

        // Verify the key has correct properties
        if let key = circumflexKey {
            XCTAssertEqual(key.deadKey, .circumflex)
            XCTAssertTrue(key.label.contains("^") || key.label.contains("°"),
                         "Dead key label should contain ^ or °")
        }
    }

    func testKeyboardStateDeadKey() {
        let state = KeyboardState.shared
        state.reset()

        // Test setting dead key
        state.setDeadKey(.acute)
        XCTAssertEqual(state.pendingDeadKey, .acute)

        // Test clearing dead key
        state.clearDeadKey()
        XCTAssertNil(state.pendingDeadKey)
    }

    func testKeyboardStateProcessCharacterWithDeadKey() throws {
        // Set up layouts directory for testing
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let layoutsPath = "\(projectRoot)/Resources/KeyboardLayouts"
        KeyboardLayoutLoader.layoutsDirectoryOverride = layoutsPath
        defer { KeyboardLayoutLoader.layoutsDirectoryOverride = nil }

        let state = KeyboardState.shared
        state.reset()

        // Load US layout
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .macOS)
        let table = KeyboardTranslationTable(layout: layout)

        // Set dead key
        state.setDeadKey(.acute)

        // Process character 'e' - should combine to 'é'
        let result = state.processCharacter("e", layout: layout, translationTable: table)

        // Should return combined character
        XCTAssertNotNil(result)
        if let (char, _, _) = result {
            XCTAssertEqual(char, "é")
        }

        // Dead key should be cleared
        XCTAssertNil(state.pendingDeadKey)
    }
}
