//
//  KeyboardRegressionTests.swift
//  KeyCmdTests
//
//  Regression tests to ensure existing functionality still works (Task 5.4)
//

import XCTest
@testable import KeyCmd

final class KeyboardRegressionTests: XCTestCase {

    var keyboardState: KeyboardState!

    override func setUp() {
        super.setUp()
        keyboardState = KeyboardState.shared
        keyboardState.reset()

        // Set up layout directory override for testing
        // Find the Resources/KeyboardLayouts directory
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        print("Test working directory: \(cwd)")

        var currentDir = cwd
        var foundPath: String?
        while currentDir != "/" {
            let layoutsPath = (currentDir as NSString).appendingPathComponent("Resources/KeyboardLayouts")
            print("Checking: \(layoutsPath)")
            if fileManager.fileExists(atPath: layoutsPath) {
                foundPath = layoutsPath
                break
            }
            currentDir = (currentDir as NSString).deletingLastPathComponent
        }

        if let path = foundPath {
            KeyboardLayoutLoader.layoutsDirectoryOverride = path
            KeyboardLayoutManager.shared.clearCache()
            print("Found layouts directory: \(path)")
        } else {
            // Fallback: use the known project path
            let projectPath = "/Users/txa/project/Openterface_KeyCmd_iOS/Resources/KeyboardLayouts"
            if fileManager.fileExists(atPath: projectPath) {
                KeyboardLayoutLoader.layoutsDirectoryOverride = projectPath
                KeyboardLayoutManager.shared.clearCache()
                print("Using fallback layouts directory: \(projectPath)")
            } else {
                print("WARNING: Could not find Resources/KeyboardLayouts directory")
            }
        }
    }

    override func tearDown() {
        keyboardState.reset()
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        KeyboardLayoutManager.shared.clearCache()
        super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testBasicKeyPressStillWorks() {
        // Test that basic key press still works after refactoring
        keyboardState.updateModifierState(key: .keyboardA, pressed: true)
        keyboardState.updateModifierState(key: .keyboardA, pressed: false)

        // Should not crash and state should be clean
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testShiftModifierStillWorks() {
        // Test that Shift modifier still works
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)
        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testCtrlModifierStillWorks() {
        // Test that Ctrl modifier still works
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertTrue(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: false)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testAltModifierStillWorks() {
        // Test that Alt modifier still works
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertTrue(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x04)

        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: false)
        XCTAssertFalse(keyboardState.isAltPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testAltGrModifierStillWorks() {
        // Test that AltGr modifier still works
        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertTrue(keyboardState.isAltGrPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x40)

        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: false)
        XCTAssertFalse(keyboardState.isAltGrPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Layout Loading Tests

    func testLayoutLoadingStillWorks() {
        // Test that layout loading still works
        let manager = KeyboardLayoutManager.shared

        // Debug: print the override directory
        if let override = KeyboardLayoutLoader.layoutsDirectoryOverride {
            print("Layout directory override: \(override)")
        } else {
            print("No layout directory override set!")
        }

        // Test US Windows layout
        let usWindows = manager.layout(for: .windows, locale: .us)
        XCTAssertFalse(usWindows.allKeys.isEmpty)
        XCTAssertEqual(usWindows.locale, .us)
        XCTAssertEqual(usWindows.targetOS, .windows)

        // Test German macOS layout
        let deMacOS = manager.layout(for: .macOS, locale: .de)
        XCTAssertFalse(deMacOS.allKeys.isEmpty)
        XCTAssertEqual(deMacOS.locale, .de, "Expected locale .de but got \(deMacOS.locale)")
        XCTAssertEqual(deMacOS.targetOS, .macOS, "Expected targetOS .macOS but got \(deMacOS.targetOS)")
    }

    func testAllLayoutsStillLoad() {
        // Test that all 42 layouts still load
        let manager = KeyboardLayoutManager.shared
        let locales = KeyboardLocale.allCases
        let targetOSes: [TargetOS] = [.windows, .macOS, .linux]

        for locale in locales {
            for os in targetOSes {
                let layout = manager.layout(for: os, locale: locale)
                XCTAssertFalse(layout.allKeys.isEmpty, "Layout \(locale) \(os) should not be empty")
                XCTAssertEqual(layout.locale, locale)
                XCTAssertEqual(layout.targetOS, os)
            }
        }
    }

    // MARK: - Layout Detection Tests

    func testLayoutDetectionStillWorks() {
        // Test that layout detection still works
        let detected = KeyboardLocale.detectActiveKeyboardLayout()

        // Should either return a valid locale or nil
        if let detected = detected {
            XCTAssertTrue(KeyboardLocale.allCases.contains(detected))
        }
    }

    func testSystemLocaleDetectionStillWorks() {
        // Test that system locale detection still works
        let locale = KeyboardLocale.fromSystemLocale()
        XCTAssertTrue(KeyboardLocale.allCases.contains(locale))
    }

    // MARK: - Dead Key Tests

    func testDeadKeyCombinationsStillWork() {
        // Test that dead key combinations still work
        XCTAssertEqual(DeadKey.acute.combine(with: "e"), "é")
        XCTAssertEqual(DeadKey.grave.combine(with: "a"), "à")
        XCTAssertEqual(DeadKey.circumflex.combine(with: "o"), "ô")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "u"), "ü")
        XCTAssertEqual(DeadKey.tilde.combine(with: "n"), "ñ")
    }

    func testDeadKeyStateStillWorks() {
        // Test that dead key state management still works
        keyboardState.setDeadKey(.acute)
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)

        keyboardState.setDeadKey(nil)
        XCTAssertNil(keyboardState.pendingDeadKey)
    }

    // MARK: - Translation Table Tests

    func testTranslationTableStillWorks() {
        // Test that translation table still works
        let manager = KeyboardLayoutManager.shared
        let layout = manager.layout(for: .windows, locale: .us)
        let table = KeyboardTranslationTable(layout: layout)

        // Test character to HID lookup
        let hid = table.hidUsageID(forCharacter: "a")
        XCTAssertEqual(hid, .keyboardA)

        // Test HID to position lookup
        if let pos = table.position(forHID: .keyboardA) {
            XCTAssertGreaterThanOrEqual(pos.row, 0)
            XCTAssertGreaterThanOrEqual(pos.column, 0)
        }
    }

    // MARK: - Integration Tests

    func testModifierAndDeadKeyInteractionStillWorks() {
        // Test that modifier and dead key interaction still works
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.setDeadKey(.acute)

        XCTAssertTrue(keyboardState.isShiftPressed)
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)
        XCTAssertEqual(keyboardState.modifierByte, 0x02)

        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: false)
        keyboardState.setDeadKey(nil)

        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertNil(keyboardState.pendingDeadKey)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testClearAllModifiersStillWorks() {
        // Test that clearAllModifiers still works
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.setDeadKey(.acute)

        keyboardState.clearAllModifiers()

        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)

        // Dead key should be preserved
        XCTAssertEqual(keyboardState.pendingDeadKey, .acute)
    }

    func testResetStillWorks() {
        // Test that reset still works
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.setDeadKey(.acute)

        keyboardState.reset()

        XCTAssertFalse(keyboardState.isShiftPressed)
        XCTAssertFalse(keyboardState.isCtrlPressed)
        XCTAssertNil(keyboardState.pendingDeadKey)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Edge Cases

    func testMultipleModifierCombinationsStillWork() {
        // Test that multiple modifier combinations still work
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)

        XCTAssertEqual(keyboardState.modifierByte, 0x07) // 0x01 | 0x02 | 0x04

        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x47) // 0x07 | 0x40

        keyboardState.clearAllModifiers()
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testInvalidDeadKeyCombinationsStillReturnNil() {
        // Test that invalid dead key combinations still return nil
        XCTAssertNil(DeadKey.acute.combine(with: "b"))
        XCTAssertNil(DeadKey.grave.combine(with: "c"))
        XCTAssertNil(DeadKey.circumflex.combine(with: "d"))
        XCTAssertNil(DeadKey.diaeresis.combine(with: "f"))
        XCTAssertNil(DeadKey.tilde.combine(with: "g"))
    }

    // MARK: - Backward Compatibility Tests

    func testOldModifierByteCalculationStillWorks() {
        // Test that old modifier byte calculation still works
        // This ensures backward compatibility
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x01)

        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x03) // 0x01 | 0x02

        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x07) // 0x01 | 0x02 | 0x04

        keyboardState.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertEqual(keyboardState.modifierByte, 0x47) // 0x07 | 0x40
    }

    func testLayoutCacheStillWorks() {
        // Test that layout cache still works
        let manager = KeyboardLayoutManager.shared

        // Get a layout to cache it
        let layout1 = manager.layout(for: .windows, locale: .us)

        // Get the same layout again (should be cached)
        let layout2 = manager.layout(for: .windows, locale: .us)

        // Both layouts should be valid and have the same properties
        XCTAssertEqual(layout1.locale, layout2.locale)
        XCTAssertEqual(layout1.targetOS, layout2.targetOS)
    }

    func testClearCacheStillWorks() {
        // Test that clearCache still works
        let manager = KeyboardLayoutManager.shared

        // Cache a layout
        _ = manager.layout(for: .windows, locale: .us)

        // Clear cache
        manager.clearCache()

        // Should be able to get layout again
        let layout = manager.layout(for: .windows, locale: .us)
        XCTAssertFalse(layout.allKeys.isEmpty)
    }
}
