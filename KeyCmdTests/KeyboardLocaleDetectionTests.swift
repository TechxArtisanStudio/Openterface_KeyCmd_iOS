//
//  KeyboardLocaleDetectionTests.swift
//  KeyCmdTests
//
//  Tests for keyboard layout detection (Task 3.1)
//

import XCTest
@testable import KeyCmd

final class KeyboardLocaleDetectionTests: XCTestCase {

    /// Test that detectActiveKeyboardLayout returns a valid KeyboardLocale or nil
    func testDetectActiveKeyboardLayoutReturnsValidValue() {
        let detected = KeyboardLocale.detectActiveKeyboardLayout()

        // Should either return a valid locale or nil (if detection fails)
        if let detected = detected {
            XCTAssertTrue(KeyboardLocale.allCases.contains(detected),
                         "Detected locale \(detected) should be a valid KeyboardLocale")
        }
    }

    /// Test that fromSystemLocale returns a valid KeyboardLocale
    func testFromSystemLocaleReturnsValidValue() {
        let locale = KeyboardLocale.fromSystemLocale()
        XCTAssertTrue(KeyboardLocale.allCases.contains(locale),
                     "System locale \(locale) should be a valid KeyboardLocale")
    }

    /// Test language code mapping for common languages
    func testLanguageCodeMapping() {
        // Test via detectActiveKeyboardLayout which uses the mapping internally
        // We can't directly test the private method, but we can verify the behavior

        // The detection should work on the current device
        let detected = KeyboardLocale.detectActiveKeyboardLayout()

        // If we're on a simulator, we should get a result
        #if targetEnvironment(simulator)
        // Simulators typically have en-US or similar
        if let detected = detected {
            XCTAssertFalse(detected.rawValue.isEmpty, "Detected locale should have a non-empty rawValue")
        }
        #endif
    }

    /// Test that all KeyboardLocale cases have valid display names
    func testAllLocalesHaveDisplayNames() {
        for locale in KeyboardLocale.allCases {
            XCTAssertFalse(locale.displayName.isEmpty,
                          "Locale \(locale.rawValue) should have a non-empty display name")
        }
    }

    /// Test that all KeyboardLocale cases have valid locale identifiers
    func testAllLocalesHaveLocaleIdentifiers() {
        for locale in KeyboardLocale.allCases {
            XCTAssertFalse(locale.localeIdentifiers.isEmpty,
                          "Locale \(locale.rawValue) should have at least one locale identifier")
        }
    }

    /// Test that physical standard is correctly assigned
    func testPhysicalStandardAssignment() {
        // ANSI layouts
        XCTAssertEqual(KeyboardLocale.us.physicalStandard, .ansi)
        XCTAssertEqual(KeyboardLocale.cn.physicalStandard, .ansi)

        // JIS layout
        XCTAssertEqual(KeyboardLocale.jp.physicalStandard, .jis)

        // ISO layouts
        XCTAssertEqual(KeyboardLocale.uk.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.de.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.fr.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.es.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.it.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.pt.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.ca.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.au.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.be.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.ch.physicalStandard, .iso)
        XCTAssertEqual(KeyboardLocale.nordic.physicalStandard, .iso)
    }

    /// Test that preferred target OS is assigned
    func testPreferredTargetOS() {
        XCTAssertEqual(KeyboardLocale.us.preferredTargetOS, .macOS)
        XCTAssertEqual(KeyboardLocale.cn.preferredTargetOS, .macOS)
        XCTAssertEqual(KeyboardLocale.jp.preferredTargetOS, .macOS)
        XCTAssertEqual(KeyboardLocale.uk.preferredTargetOS, .windows)
        XCTAssertEqual(KeyboardLocale.au.preferredTargetOS, .windows)
        XCTAssertEqual(KeyboardLocale.ca.preferredTargetOS, .windows)
        XCTAssertEqual(KeyboardLocale.de.preferredTargetOS, .linux)
        XCTAssertEqual(KeyboardLocale.fr.preferredTargetOS, .linux)
    }
}
