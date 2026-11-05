//
//  JapaneseMacLayoutTests.swift
//  KeyCmdTests
//
//  jp_macos_jis.json must describe the Apple JIS keyboard, not the Windows JIS
//  virtual keyboard: 英数/かな flank Space, ろ sits on the ZXCV row, the yen key
//  is on the number row, and the number/home-row legends follow JIS.
//  jp_macos_ansi.json covers the same Japanese input source on an ANSI (US)
//  physical keyboard.
//

import XCTest
@testable import KeyCmd

final class JapaneseMacLayoutTests: XCTestCase {

    private var macLayout: KeyboardLayoutDefinition!
    private var ansiLayout: KeyboardLayoutDefinition!
    private var windowsLayout: KeyboardLayoutDefinition!

    override func setUp() {
        super.setUp()
        KeyboardLayoutLoader.layoutsDirectoryOverride = Self.layoutsDirectory
        KeyboardLayoutManager.shared.clearCache()
        macLayout = MacLayoutBuilder.build(for: .jp)
        ansiLayout = MacLayoutBuilder.build(for: .jp, physicalStandard: .ansi)
        windowsLayout = WindowsLayoutBuilder.build(for: .jp)
    }

    override func tearDown() {
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        KeyboardLayoutManager.shared.clearCache()
        macLayout = nil
        ansiLayout = nil
        windowsLayout = nil
        super.tearDown()
    }

    private static var layoutsDirectory: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/KeyboardLayouts")
            .path
    }

    private var bottomRow: [String] {
        macLayout.rows[5].map(\.keyName)
    }

    // MARK: - Layout source

    func testMacJapaneseLayoutLoadsAsAppleJIS() {
        XCTAssertEqual(macLayout.targetOS, .macOS,
                       "Loader failure silently falls back to the Windows layout")
        XCTAssertEqual(macLayout.locale, .jp)
        XCTAssertTrue(macLayout.metadata.name.contains("Apple"))
    }

    func testWindowsOnlyJISKeysAreGone() {
        for name in ["変換", "無変換", "Kana"] {
            XCTAssertNil(macLayout.keyDefinition(for: name),
                         "\(name) belongs to the Windows JIS keyboard, not Apple's")
        }
    }

    // MARK: - Bottom row

    func testBottomRowFollowsAppleOrder() {
        XCTAssertEqual(Array(bottomRow.prefix(9)),
                       ["Menu", "LeftCtrl", "LeftAlt", "LeftWin",
                        "英数", "Space", "かな", "RightWin", "RightAlt"])
    }

    func testBottomRowStartsWithAppleFnKey() {
        let fnKey = macLayout.rows[5].first
        XCTAssertEqual(fnKey?.label, "fn",
                       "The leftmost bottom key is Apple's Fn key")
        XCTAssertEqual(fnKey?.keyName, "Menu",
                       "Fn reuses the PC Menu slot but is handled as a local layer")
    }

    func testAppleJISSpecialKeysUseAppleHIDUsages() {
        XCTAssertEqual(macLayout.keyDefinition(for: "かな")?.hidUsageID, .keyboardLANG1)
        XCTAssertEqual(macLayout.keyDefinition(for: "英数")?.hidUsageID, .keyboardLANG2)
        XCTAssertEqual(macLayout.keyDefinition(for: "Ro")?.hidUsageID, .keyboardInternational1)
        XCTAssertEqual(macLayout.keyDefinition(for: "¥")?.hidUsageID, .keyboardInternational3)
    }

    // MARK: - Key positions

    func testRoKeySitsOnZXCVRowBeforeRightShift() {
        let row = macLayout.rows[4].map(\.keyName)
        XCTAssertEqual(Array(row.suffix(3)), ["/", "Ro", "RightShift"])
    }

    func testYenKeySitsOnNumberRowBeforeBackspace() {
        let row = macLayout.rows[1].map(\.keyName)
        XCTAssertEqual(Array(row.suffix(3)), ["^", "¥", "Backspace"])
    }

    // MARK: - JIS legends

    func testNumberRowShiftLabelsMatchAppleJIS() {
        let expected: [String: String] = [
            "1": "!", "2": "\"", "3": "#", "4": "$", "5": "%",
            "6": "&", "7": "'", "8": "(", "9": ")", "0": "を",
            "-": "=", "^": "~", "¥": "|"
        ]
        for (name, shiftLabel) in expected {
            XCTAssertEqual(macLayout.keyDefinition(for: name)?.shiftLabel, shiftLabel,
                           "Wrong shifted legend for \(name)")
        }
    }

    func testHomeRowPunctuationMatchesAppleJIS() {
        XCTAssertEqual(macLayout.keyDefinition(for: ";")?.shiftLabel, "+")
        XCTAssertEqual(macLayout.keyDefinition(for: ":")?.shiftLabel, "*")
        XCTAssertEqual(macLayout.keyDefinition(for: "]")?.shiftLabel, "}")
        XCTAssertEqual(macLayout.keyDefinition(for: "@")?.shiftLabel, "`")
        XCTAssertEqual(macLayout.keyDefinition(for: "[")?.shiftLabel, "{")
    }

    // MARK: - Key types

    func testKeyTypes() {
        let modifiers = Set(macLayout.allKeys.filter { $0.keyType == .modifier }.map(\.keyName))
        XCTAssertEqual(modifiers, ["LeftCtrl", "LeftAlt", "LeftWin", "RightAlt", "RightWin",
                                   "LeftShift", "RightShift"])

        XCTAssertEqual(macLayout.keyDefinition(for: "英数")?.keyType, .japaneseSpecial)
        XCTAssertEqual(macLayout.keyDefinition(for: "かな")?.keyType, .japaneseSpecial)
        XCTAssertEqual(macLayout.keyDefinition(for: "Caps")?.keyType, .special)
        XCTAssertEqual(macLayout.keyDefinition(for: "Ro")?.keyType, .regular)
        XCTAssertEqual(macLayout.keyDefinition(for: "1")?.keyType, .regular)
        XCTAssertEqual(macLayout.keyDefinition(for: "Space")?.keyType, .regular)
    }

    // MARK: - ANSI variant

    func testDefaultMacJapaneseLayoutStaysJIS() {
        XCTAssertEqual(macLayout.metadata.physicalStandard, .jis)
    }

    func testANSIVariantUsesUSKeycaps() {
        XCTAssertEqual(ansiLayout.locale, .jp)
        XCTAssertEqual(ansiLayout.targetOS, .macOS)
        XCTAssertEqual(ansiLayout.metadata.physicalStandard, .ansi)
        XCTAssertEqual(ansiLayout.metadata.name, "Japanese (ANSI)")

        for name in ["Ro", "英数", "かな", "¥", "半角/全角"] {
            XCTAssertNil(ansiLayout.keyDefinition(for: name),
                         "\(name) is JIS-only and must not appear on an ANSI keyboard")
        }
        XCTAssertNotNil(ansiLayout.keyDefinition(for: "\\"))
        XCTAssertEqual(ansiLayout.keyDefinition(for: "\\")?.shiftLabel, "|")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "\\")?.hidUsageID, .keyboardBackslash)
    }

    func testANSIVariantUsesUSLegends() {
        XCTAssertEqual(ansiLayout.keyDefinition(for: "2")?.shiftLabel, "@")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "6")?.shiftLabel, "^")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "-")?.shiftLabel, "_")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "=")?.shiftLabel, "+")
        XCTAssertEqual(ansiLayout.keyDefinition(for: ";")?.shiftLabel, ":")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "'")?.shiftLabel, "\"")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "[")?.shiftLabel, "{")
        XCTAssertEqual(ansiLayout.keyDefinition(for: "]")?.shiftLabel, "}")
    }

    func testANSIVariantBottomRowFollowsAppleOrder() {
        let names = ansiLayout.rows[5].map(\.keyName)
        XCTAssertEqual(Array(names.prefix(7)),
                       ["Menu", "LeftCtrl", "LeftAlt", "LeftWin", "Space", "RightWin", "RightAlt"])
        XCTAssertEqual(ansiLayout.rows[5].first?.label, "fn")
    }

    // MARK: - Windows layout must stay Windows-style

    func testWindowsJapaneseLayoutKeepsItsOwnJISKeys() {
        XCTAssertNotNil(windowsLayout.keyDefinition(for: "変換"))
        XCTAssertNotNil(windowsLayout.keyDefinition(for: "無変換"))
        XCTAssertNotNil(windowsLayout.keyDefinition(for: "Kana"))
    }
}
