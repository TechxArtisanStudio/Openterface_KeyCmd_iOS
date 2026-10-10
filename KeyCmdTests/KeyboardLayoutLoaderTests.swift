//
//  KeyboardLayoutLoaderTests.swift
//  KeyCmdTests
//
//  Tests for JSON keyboard layout loader
//

import XCTest
@testable import KeyCmd

final class KeyboardLayoutLoaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Set the layouts directory for testing - use project root path
        // Walk up from current directory to find Resources/KeyboardLayouts
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let layoutsPath = (dir as NSString).appendingPathComponent("Resources/KeyboardLayouts")
            if FileManager.default.fileExists(atPath: layoutsPath) {
                KeyboardLayoutLoader.layoutsDirectoryOverride = layoutsPath
                return
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        // Fallback: use absolute path (for CI/test environments)
        KeyboardLayoutLoader.layoutsDirectoryOverride = "/Users/txa/project/Openterface_KeyCmd_iOS/Resources/KeyboardLayouts"
    }

    override func tearDown() {
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        super.tearDown()
    }

    func testLoadUSLayout() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        XCTAssertEqual(layout.locale, .us)
        XCTAssertEqual(layout.targetOS, .windows)
        XCTAssertGreaterThan(layout.rows.count, 0)

        // Verify all keys have HID Usage IDs
        for row in layout.rows {
            for keyDef in row {
                XCTAssertNotNil(keyDef.hidUsageID)
            }
        }
    }

    func testLoadAllLayouts() throws {
        // Test that all 42 layouts (14 locales × 3 OSes) load successfully
        let locales: [KeyboardLocale] = [.us, .uk, .de, .fr, .es, .it, .pt, .jp, .cn, .ca, .au, .be, .ch, .nordic]
        let oses: [TargetOS] = [.windows, .macOS, .linux]

        var loadedCount = 0
        for locale in locales {
            for os in oses {
                let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                XCTAssertEqual(layout.locale, locale)
                XCTAssertEqual(layout.targetOS, os)
                XCTAssertGreaterThan(layout.rows.count, 0, "Layout \(locale)_\(os) should have keys")
                loadedCount += 1
            }
        }

        XCTAssertEqual(loadedCount, 42, "Should have loaded all 42 layouts (14 locales × 3 OSes)")
    }

    func testLayoutMetadata() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        XCTAssertEqual(layout.metadata.name, "US QWERTY")
        XCTAssertFalse(layout.metadata.description.isEmpty)
        XCTAssertEqual(layout.metadata.physicalStandard, .ansi)
        XCTAssertFalse(layout.metadata.hasAltGr)
        XCTAssertNotNil(layout.metadata.rowHeights)
        XCTAssertGreaterThan(layout.metadata.keySpacing, 0)
        XCTAssertGreaterThan(layout.metadata.rowSpacing, 0)
    }

    func testKeyDefinitions() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        // Check that we have keys in multiple rows
        XCTAssertGreaterThanOrEqual(layout.rows.count, 5)

        // Check function row (row 0)
        let functionRow = layout.rows[0]
        XCTAssertGreaterThan(functionRow.count, 0)

        // Check number row (row 1)
        let numberRow = layout.rows[1]
        XCTAssertGreaterThan(numberRow.count, 0)

        // Check that keys have proper labels
        for row in layout.rows {
            for keyDef in row {
                XCTAssertFalse(keyDef.label.isEmpty)
                XCTAssertFalse(keyDef.keyName.isEmpty)
            }
        }
    }

    func testSpecificKeys() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        // Find the 'A' key
        let aKey = layout.allKeys.first { $0.keyName == "a" }
        XCTAssertNotNil(aKey)
        XCTAssertEqual(aKey?.hidUsageID, .keyboardA)
        XCTAssertEqual(aKey?.label, "A")

        // Find the Space key
        let spaceKey = layout.allKeys.first { $0.keyName == "Space" }
        XCTAssertNotNil(spaceKey)
        XCTAssertEqual(spaceKey?.hidUsageID, .keyboardSpace)
    }

    func testModifierKeys() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        // Check for modifier keys
        let leftShift = layout.allKeys.first { $0.keyName == "LeftShift" }
        XCTAssertNotNil(leftShift)
        XCTAssertEqual(leftShift?.keyType, .modifier)
        XCTAssertEqual(leftShift?.hidUsageID, .keyboardLeftShift)

        let leftCtrl = layout.allKeys.first { $0.keyName == "LeftCtrl" }
        XCTAssertNotNil(leftCtrl)
        XCTAssertEqual(leftCtrl?.keyType, .modifier)
        XCTAssertEqual(leftCtrl?.hidUsageID, .keyboardLeftCtrl)
    }

    func testLayoutCacheKey() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)

        XCTAssertEqual(layout.layoutCacheKey, "windows_US")
    }
}
