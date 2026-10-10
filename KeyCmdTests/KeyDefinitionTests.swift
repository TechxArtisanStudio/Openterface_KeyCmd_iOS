// KeyCmdTests/KeyDefinitionTests.swift
import XCTest
@testable import KeyCmd

final class KeyDefinitionTests: XCTestCase {

    // MARK: - hidUsageID field tests

    func testKeyDefinitionWithHID() {
        let keyDef = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        XCTAssertEqual(keyDef.hidUsageID, .keyboardQ)
        XCTAssertEqual(keyDef.hidUsageValue, 0x14)
    }

    func testModifierKeyDefinition() {
        let shiftKey = KeyDefinition.mod("Shift", hid: .keyboardLeftShift, width: 1.5)
        XCTAssertEqual(shiftKey.keyType, .modifier)
        XCTAssertEqual(shiftKey.hidUsageID, .keyboardLeftShift)
    }

    func testKeyWithAltGr() {
        let keyDef = KeyDefinition.key("e", "E", shift: "€", altGr: "é", hid: .keyboardE)
        XCTAssertEqual(keyDef.altGrLabel, "é")
        XCTAssertEqual(keyDef.hidUsageID, .keyboardE)
        XCTAssertEqual(keyDef.hidUsageValue, 0x08)
    }

    // MARK: - hidUsageValue computed property

    func testHidUsageValueReturnsRawValue() {
        let keyDef = KeyDefinition.key("a", "A", hid: .keyboardA)
        XCTAssertEqual(keyDef.hidUsageValue, HIDUsageID.keyboardA.rawValue)
        XCTAssertEqual(keyDef.hidUsageValue, 0x04)
    }

    func testHidUsageValueForModifiers() {
        let leftCtrl = KeyDefinition.mod("LCtrl", hid: .keyboardLeftCtrl)
        XCTAssertEqual(leftCtrl.hidUsageValue, 0xE0)

        let rightGui = KeyDefinition.mod("RGui", hid: .keyboardRightGUI)
        XCTAssertEqual(rightGui.hidUsageValue, 0xE7)
    }

    // MARK: - Direct initializer tests

    func testDirectInitializerWithHID() {
        let keyDef = KeyDefinition(
            keyName: "space",
            label: "Space",
            hidUsageID: .keyboardSpace,
            keyType: .regular
        )
        XCTAssertEqual(keyDef.hidUsageID, .keyboardSpace)
        XCTAssertEqual(keyDef.hidUsageValue, 0x2C)
        XCTAssertEqual(keyDef.keyName, "space")
        XCTAssertEqual(keyDef.keyCode, "space")
    }

    func testDirectInitializerWithAllParameters() {
        let keyDef = KeyDefinition(
            keyName: "1",
            label: "1",
            shiftLabel: "!",
            altGrLabel: "¡",
            keyCode: "1",
            hidUsageID: .keyboard1,
            keyType: .regular,
            widthMultiplier: 1.0,
            heightMultiplier: 1.0
        )
        XCTAssertEqual(keyDef.hidUsageID, .keyboard1)
        XCTAssertEqual(keyDef.shiftLabel, "!")
        XCTAssertEqual(keyDef.altGrLabel, "¡")
    }

    // MARK: - Factory method tests

    func testKeyFactoryMethodPreservesAllFields() {
        let keyDef = KeyDefinition.key(
            "tab", "Tab",
            shift: nil,
            altGr: nil,
            hid: .keyboardTab,
            type: .special,
            width: 1.5,
            height: 1.0
        )
        XCTAssertEqual(keyDef.keyName, "tab")
        XCTAssertEqual(keyDef.label, "Tab")
        XCTAssertEqual(keyDef.hidUsageID, .keyboardTab)
        XCTAssertEqual(keyDef.keyType, .special)
        XCTAssertEqual(keyDef.widthMultiplier, 1.5)
        XCTAssertEqual(keyDef.heightMultiplier, 1.0)
    }

    func testModFactoryMethodDefaults() {
        let modKey = KeyDefinition.mod("Alt", hid: .keyboardLeftAlt)
        XCTAssertEqual(modKey.keyName, "Alt")
        XCTAssertEqual(modKey.label, "Alt")  // defaults to name
        XCTAssertNil(modKey.shiftLabel)
        XCTAssertNil(modKey.altGrLabel)
        XCTAssertEqual(modKey.keyType, .modifier)
        XCTAssertEqual(modKey.hidUsageID, .keyboardLeftAlt)
    }

    func testModFactoryMethodWithCustomLabel() {
        let modKey = KeyDefinition.mod("Shift", label: "⇧", hid: .keyboardLeftShift)
        XCTAssertEqual(modKey.label, "⇧")
        XCTAssertEqual(modKey.hidUsageID, .keyboardLeftShift)
    }

    // MARK: - Codable conformance

    func testKeyDefinitionCodable() throws {
        let original = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyDefinition.self, from: encoded)
        XCTAssertEqual(decoded.hidUsageID, .keyboardQ)
        XCTAssertEqual(decoded.keyName, "q")
        XCTAssertEqual(decoded.label, "Q")
    }

    // MARK: - Equatable/Hashable conformance

    func testKeyDefinitionEquality() {
        let key1 = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        let key2 = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        XCTAssertEqual(key1, key2)
    }

    func testKeyDefinitionInequalityDifferentHID() {
        let key1 = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        let key2 = KeyDefinition.key("q", "Q", hid: .keyboardA)
        XCTAssertNotEqual(key1, key2)
    }

    func testKeyDefinitionHashable() {
        let key1 = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        let key2 = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        let set: Set<KeyDefinition> = [key1, key2]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Backward compatibility (default hid)

    func testKeyFactoryMethodDefaultHID() {
        // Existing call sites without hid should still compile and produce a valid KeyDefinition
        let keyDef = KeyDefinition.key("q", "Q")
        XCTAssertEqual(keyDef.keyName, "q")
        XCTAssertEqual(keyDef.label, "Q")
        // hidUsageID should have some default value
        XCTAssertNotNil(keyDef.hidUsageID)
    }

    func testModFactoryMethodDefaultHID() {
        let modKey = KeyDefinition.mod("Shift")
        XCTAssertEqual(modKey.keyType, .modifier)
        XCTAssertNotNil(modKey.hidUsageID)
    }
}
