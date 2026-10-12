//
//  KeyboardLayoutDetectionIntegrationTests.swift
//  KeyCmdTests
//
//  Tests for keyboard layout detection integration with KeyboardLayoutManager (Task 3.3)
//

import XCTest
@testable import KeyCmd

final class KeyboardLayoutDetectionIntegrationTests: XCTestCase {

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

    /// Test that KeyboardLayoutManager initializes with detected layout when available
    func testKeyboardLayoutManagerInitializesWithDetectedLayout() {
        // This test verifies that the manager can be initialized
        // The actual detection depends on the current system locale
        let manager = KeyboardLayoutManager.shared

        // Should have a valid layout
        XCTAssertFalse(manager.activeLayout.metadata.name.isEmpty)
        XCTAssertTrue(KeyboardLocale.allCases.contains(manager.currentKeyboardLocale))
    }

    /// Test that clearCache still works with detection enabled
    func testClearCacheWorksWithDetection() {
        let manager = KeyboardLayoutManager.shared

        // Get a layout to cache
        let layout1 = manager.layout(for: .windows, locale: .us)

        // Clear cache
        manager.clearCache()

        // Getting layout again should work (may recalculate)
        let layout2 = manager.layout(for: .windows, locale: .us)

        // Should be able to get layout after cache clear
        XCTAssertFalse(layout2.allKeys.isEmpty)
    }

    /// Test that supportedLocales still returns all locales
    func testSupportedLocalesUnchanged() {
        let manager = KeyboardLayoutManager.shared
        XCTAssertEqual(manager.supportedLocales.count, 14)
    }

    /// Test that layout(for:locale:) still works correctly
    func testLayoutForLocaleStillWorks() {
        let manager = KeyboardLayoutManager.shared

        // Test a few combinations
        let usWindows = manager.layout(for: .windows, locale: .us)
        let deMacOS = manager.layout(for: .macOS, locale: .de)
        let frLinux = manager.layout(for: .linux, locale: .fr)

        XCTAssertFalse(usWindows.allKeys.isEmpty)
        XCTAssertFalse(deMacOS.allKeys.isEmpty)
        XCTAssertFalse(frLinux.allKeys.isEmpty)

        // Verify they have correct metadata
        XCTAssertEqual(usWindows.locale, .us)
        XCTAssertEqual(usWindows.targetOS, .windows)
        XCTAssertEqual(deMacOS.locale, .de)
        XCTAssertEqual(deMacOS.targetOS, .macOS)
        XCTAssertEqual(frLinux.locale, .fr)
        XCTAssertEqual(frLinux.targetOS, .linux)
    }

    /// Test that manual locale setting still works
    func testManualLocaleSettingStillWorks() {
        let manager = KeyboardLayoutManager.shared
        let originalLocale = manager.currentKeyboardLocale

        // Change to a different locale
        manager.currentKeyboardLocale = .de
        XCTAssertEqual(manager.currentKeyboardLocale, .de)

        // Change back
        manager.currentKeyboardLocale = originalLocale
        XCTAssertEqual(manager.currentKeyboardLocale, originalLocale)
    }

    /// Test that autoDetectLocale setting still works
    func testAutoDetectLocaleSettingStillWorks() {
        let manager = KeyboardLayoutManager.shared
        let originalSetting = manager.autoDetectLocale

        // Toggle the setting
        manager.autoDetectLocale = !originalSetting
        XCTAssertEqual(manager.autoDetectLocale, !originalSetting)

        // Toggle back
        manager.autoDetectLocale = originalSetting
        XCTAssertEqual(manager.autoDetectLocale, originalSetting)
    }
}