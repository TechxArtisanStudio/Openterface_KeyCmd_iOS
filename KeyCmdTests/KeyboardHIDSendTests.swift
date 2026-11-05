//
//  KeyboardHIDSendTests.swift
//  KeyCmdTests
//
//  Verifies that on-screen keys and text input send the layout's HID usage
//  IDs directly, so QWERTZ/AZERTY/JIS positions are not remapped through a
//  US-centric name table.
//

import XCTest
@testable import KeyCmd

final class KeyboardHIDSendTests: XCTestCase {

    var keyboardManager: KeyboardManager!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []
    private var originalLocale: KeyboardLocale!

    override func setUp() {
        super.setUp()

        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        KeyboardLayoutLoader.layoutsDirectoryOverride = "\(projectRoot)/Resources/KeyboardLayouts"
        KeyboardLayoutManager.shared.clearCache()
        originalLocale = KeyboardLayoutManager.shared.currentKeyboardLocale

        keyboardManager = KeyboardManager(bleManager: BLEManager())
        keyboardManager.hidReportCapture = { [weak self] modifier, keyCodes in
            self?.capturedReports.append((modifier: modifier, keyCodes: keyCodes))
        }
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()
        keyboardManager.keyboardState.reset()
    }

    override func tearDown() {
        keyboardManager.releaseAllKeys()
        keyboardManager.hidReportCapture = nil
        keyboardManager = nil
        capturedReports.removeAll()
        KeyboardLayoutManager.shared.currentKeyboardLocale = originalLocale
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        KeyboardLayoutManager.shared.clearCache()
        super.tearDown()
    }

    private var lastReport: (modifier: UInt8, keyCodes: [UInt8])? {
        capturedReports.last
    }

    private var lastPressReport: (modifier: UInt8, keyCodes: [UInt8])? {
        capturedReports.last { $0.keyCodes.contains { $0 != 0 } }
    }

    // MARK: - On-screen physical keys

    func testGermanLayoutSendsQWERTZPositions() {
        KeyboardLayoutManager.shared.currentKeyboardLocale = .de

        keyboardManager.handleKeyDown("z")
        XCTAssertEqual(lastReport?.keyCodes[0], 0x1C, "DE 'z' must use the physical Y position (0x1C)")
        keyboardManager.handleKeyUp("z")

        keyboardManager.handleKeyDown("y")
        XCTAssertEqual(lastReport?.keyCodes[0], 0x1D, "DE 'y' must use the physical Z position (0x1D)")
        keyboardManager.handleKeyUp("y")
    }

    func testFrenchLayoutSendsAZERTYPositions() {
        KeyboardLayoutManager.shared.currentKeyboardLocale = .fr

        keyboardManager.handleKeyDown("a")
        XCTAssertEqual(lastReport?.keyCodes[0], 0x14, "FR 'a' must use the physical Q position (0x14)")
        keyboardManager.handleKeyUp("a")

        keyboardManager.handleKeyDown("q")
        XCTAssertEqual(lastReport?.keyCodes[0], 0x04, "FR 'q' must use the physical A position (0x04)")
        keyboardManager.handleKeyUp("q")
    }

    func testRightAltSendsAltGrBit() {
        keyboardManager.handleKeyDown("RightAlt")
        XCTAssertEqual(lastReport?.modifier, 0x40, "Right Alt must set the AltGr bit")
        XCTAssertTrue(keyboardManager.isAltGrActive)

        keyboardManager.handleKeyUp("RightAlt")
        XCTAssertEqual(lastReport?.modifier, 0x00)
        XCTAssertFalse(keyboardManager.isAltGrActive)
    }

    // MARK: - Translation table layers

    func testGermanStrokesResolveShiftAndAltGr() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .de, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)

        XCTAssertEqual(table.stroke(forCharacter: "z")?.hidUsageID.rawValue, 0x1C)
        XCTAssertEqual(table.stroke(forCharacter: "z")?.modifiers, 0)

        XCTAssertEqual(table.stroke(forCharacter: "A")?.hidUsageID.rawValue, 0x04)
        XCTAssertEqual(table.stroke(forCharacter: "A")?.modifiers, KMod.shift.rawValue)

        XCTAssertEqual(table.stroke(forCharacter: "@")?.hidUsageID.rawValue, 0x14)
        XCTAssertEqual(table.stroke(forCharacter: "@")?.modifiers, KMod.rAlt.rawValue)

        XCTAssertEqual(table.stroke(forCharacter: "€")?.hidUsageID.rawValue, 0x08)
        XCTAssertEqual(table.stroke(forCharacter: "€")?.modifiers, KMod.rAlt.rawValue)
    }

    func testFrenchStrokesResolveNumberRowLayers() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .fr, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)

        XCTAssertEqual(table.stroke(forCharacter: "a")?.hidUsageID.rawValue, 0x14)
        XCTAssertEqual(table.stroke(forCharacter: "a")?.modifiers, 0)

        XCTAssertEqual(table.stroke(forCharacter: "&")?.hidUsageID.rawValue, 0x1E)
        XCTAssertEqual(table.stroke(forCharacter: "&")?.modifiers, 0)

        XCTAssertEqual(table.stroke(forCharacter: "1")?.hidUsageID.rawValue, 0x1E)
        XCTAssertEqual(table.stroke(forCharacter: "1")?.modifiers, KMod.shift.rawValue)

        XCTAssertEqual(table.stroke(forCharacter: "@")?.hidUsageID.rawValue, 0x27)
        XCTAssertEqual(table.stroke(forCharacter: "@")?.modifiers, KMod.rAlt.rawValue)
    }

    func testDeadKeyStrokeIsMarked() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .de, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)

        let stroke = table.stroke(forCharacter: "^")
        XCTAssertEqual(stroke?.isDeadKey, true)
        XCTAssertEqual(stroke?.hidUsageID.rawValue, 0x35)
    }

    // MARK: - Text input path

    func testInlineTextUsesLayoutStrokes() {
        KeyboardLayoutManager.shared.currentKeyboardLocale = .de

        keyboardManager.sendASCIICharInline("z")
        XCTAssertEqual(lastPressReport?.keyCodes[0], 0x1C)
        XCTAssertEqual(lastPressReport?.modifier, 0)

        capturedReports.removeAll()
        keyboardManager.sendASCIICharInline("@")
        XCTAssertEqual(lastPressReport?.keyCodes[0], 0x14)
        XCTAssertEqual(lastPressReport?.modifier, KMod.rAlt.rawValue)
    }

    // MARK: - Layout data

    func testLayoutsLoadFromAppBundleWithoutTestOverride() throws {
        // The JSON files must ship inside the app; otherwise every locale
        // silently falls back to the built-in US layout on device.
        let savedOverride = KeyboardLayoutLoader.layoutsDirectoryOverride
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        defer { KeyboardLayoutLoader.layoutsDirectoryOverride = savedOverride }

        let layout = try KeyboardLayoutLoader.load(locale: .de, targetOS: .windows)
        XCTAssertEqual(layout.keyDefinition(for: "z")?.hidUsageID, .keyboardY)
    }

    func testAllLayoutFilesLoadWithoutDuplicatePositions() {
        for locale in KeyboardLocale.allCases {
            for os in [TargetOS.windows, .macOS, .linux] {
                XCTAssertNoThrow(
                    try KeyboardLayoutLoader.load(locale: locale, targetOS: os),
                    "\(locale.rawValue) \(os.rawValue) failed to load"
                )
            }
        }
    }

    func testMacOSRelabellingPreservesModifierHIDs() {
        let layout = KeyboardLayoutManager.createLayout(for: .macOS, locale: .us)

        XCTAssertEqual(layout.keyDefinition(for: "LeftCtrl")?.hidUsageID, .keyboardLeftCtrl)
        XCTAssertEqual(layout.keyDefinition(for: "LeftWin")?.hidUsageID, .keyboardLeftGUI)
        XCTAssertEqual(layout.keyDefinition(for: "LeftAlt")?.hidUsageID, .keyboardLeftAlt)
        XCTAssertEqual(layout.keyDefinition(for: "RightAlt")?.hidUsageID, .keyboardRightAlt)
    }

    func testMacOSBottomRowUsesAppleModifierOrder() {
        let layout = KeyboardLayoutManager.createLayout(for: .macOS, locale: .us)
        let bottomRow = try! XCTUnwrap(layout.rows.last)

        XCTAssertEqual(
            Array(bottomRow.prefix(7).map(\.keyName)),
            ["Fn", "LeftCtrl", "LeftAlt", "LeftWin", "Space", "RightWin", "RightAlt"]
        )
        XCTAssertEqual(layout.keyDefinition(for: "Fn")?.label, "fn")
        XCTAssertEqual(layout.keyDefinition(for: "LeftCtrl")?.label, "⌃")
        XCTAssertEqual(layout.keyDefinition(for: "LeftAlt")?.label, "⌥")
        XCTAssertEqual(layout.keyDefinition(for: "LeftWin")?.label, "⌘")

        // Relabelling must not disturb the usage ID the key actually sends.
        XCTAssertEqual(layout.keyDefinition(for: "Fn")?.hidUsageID, .keyboardFn)
        XCTAssertEqual(layout.keyDefinition(for: "LeftWin")?.hidUsageID, .keyboardLeftGUI)
        // The bundled ANSI row keeps a right Control — full-size Apple keyboards have one.
        XCTAssertEqual(layout.keyDefinition(for: "RightCtrl")?.hidUsageID, .keyboardRightCtrl)
    }
}
