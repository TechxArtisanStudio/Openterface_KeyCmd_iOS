//
//  KeyboardLayoutPersistenceTests.swift
//  KeyCmdTests
//
//  The keyboard layout selected by the user must be restored on the next launch.
//

import XCTest
@testable import KeyCmd

final class KeyboardLayoutPersistenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KeyboardLayoutPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSavedLocaleIsRestored() {
        defaults.set(KeyboardLocale.de.rawValue, forKey: KeyboardLayoutManager.keyboardLocaleKey)

        XCTAssertEqual(KeyboardLayoutManager.restoreLocale(defaults: defaults), .de)
    }

    /// Auto-detect must not override a layout the user has already chosen.
    func testSavedLocaleWinsOverAutoDetect() {
        defaults.set(KeyboardLocale.jp.rawValue, forKey: KeyboardLayoutManager.keyboardLocaleKey)
        defaults.set(true, forKey: KeyboardLayoutManager.keyboardAutoDetectKey)

        XCTAssertEqual(KeyboardLayoutManager.restoreLocale(defaults: defaults), .jp)
    }

    func testAutoDetectIsUsedOnlyWhenNothingWasSaved() {
        defaults.set(true, forKey: KeyboardLayoutManager.keyboardAutoDetectKey)

        XCTAssertEqual(
            KeyboardLayoutManager.restoreLocale(defaults: defaults),
            KeyboardLocale.fromSystemLocale()
        )
    }

    func testDefaultsToUSWithoutSavedLocaleOrAutoDetect() {
        XCTAssertEqual(KeyboardLayoutManager.restoreLocale(defaults: defaults), .us)
    }

    func testUnknownSavedLocaleFallsBackToUS() {
        defaults.set("XX", forKey: KeyboardLayoutManager.keyboardLocaleKey)

        XCTAssertEqual(KeyboardLayoutManager.restoreLocale(defaults: defaults), .us)
    }

    func testSelectingLayoutPersistsIt() {
        let manager = KeyboardLayoutManager.shared
        let originalLocale = manager.currentKeyboardLocale
        defer { manager.currentKeyboardLocale = originalLocale }

        manager.currentKeyboardLocale = .fr

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: KeyboardLayoutManager.keyboardLocaleKey),
            KeyboardLocale.fr.rawValue
        )
    }

    func testRestoredLocaleProducesLayoutForEveryTargetOS() {
        defaults.set(KeyboardLocale.de.rawValue, forKey: KeyboardLayoutManager.keyboardLocaleKey)
        let locale = KeyboardLayoutManager.restoreLocale(defaults: defaults)

        for os in TargetOS.allCases {
            let layout = KeyboardLayoutManager.createLayout(for: os, locale: locale)
            XCTAssertEqual(layout.locale, .de)
            XCTAssertEqual(layout.targetOS, os)
        }
    }

    // MARK: - Physical keyboard standard

    func testPhysicalStandardDefaultsToTheLocaleStandard() {
        XCTAssertEqual(KeyboardLayoutManager.restorePhysicalStandard(for: .jp, defaults: defaults), .jis)
        XCTAssertEqual(KeyboardLayoutManager.restorePhysicalStandard(for: .us, defaults: defaults), .ansi)
        XCTAssertEqual(KeyboardLayoutManager.restorePhysicalStandard(for: .de, defaults: defaults), .iso)
    }

    func testSavedANSIPhysicalStandardIsRestoredForJapanese() {
        defaults.set(KeyboardLocale.PhysicalStandard.ansi.rawValue,
                     forKey: KeyboardLayoutManager.physicalStandardKey)

        XCTAssertEqual(KeyboardLayoutManager.restorePhysicalStandard(for: .jp, defaults: defaults), .ansi)
    }

    func testUnsupportedSavedPhysicalStandardFallsBackToLocaleStandard() {
        defaults.set(KeyboardLocale.PhysicalStandard.iso.rawValue,
                     forKey: KeyboardLayoutManager.physicalStandardKey)

        XCTAssertEqual(KeyboardLayoutManager.restorePhysicalStandard(for: .jp, defaults: defaults), .jis)
    }

    func testJapaneseANSIStandardProducesANSILayout() {
        let ansi = KeyboardLayoutManager.createLayout(for: .macOS, locale: .jp, physicalStandard: .ansi)
        XCTAssertEqual(ansi.metadata.physicalStandard, .ansi)

        let jis = KeyboardLayoutManager.createLayout(for: .macOS, locale: .jp, physicalStandard: .jis)
        XCTAssertEqual(jis.metadata.physicalStandard, .jis)
    }

    func testSelectingPhysicalStandardPersistsIt() {
        let manager = KeyboardLayoutManager.shared
        let originalStandard = manager.physicalStandard
        defer { manager.physicalStandard = originalStandard }

        manager.physicalStandard = .ansi

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: KeyboardLayoutManager.physicalStandardKey),
            KeyboardLocale.PhysicalStandard.ansi.rawValue
        )
    }
}
