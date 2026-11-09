//
//  KeyboardLayoutSymbolTests.swift
//  KeyCmdTests
//
//  Regression tests for layout symbols against macOS Keyboard Viewer /
//  xkeyboard-config ground truth (see scripts/audit_layout_symbols.py).
//

import XCTest
@testable import KeyCmd

final class KeyboardLayoutSymbolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let layoutsPath = (dir as NSString).appendingPathComponent("Resources/KeyboardLayouts")
            if FileManager.default.fileExists(atPath: layoutsPath) {
                KeyboardLayoutLoader.layoutsDirectoryOverride = layoutsPath
                return
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        KeyboardLayoutLoader.layoutsDirectoryOverride = "/Users/txa/project/Openterface_KeyCmd_iOS/Resources/KeyboardLayouts"
    }

    override func tearDown() {
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        super.tearDown()
    }

    private func key(_ layout: KeyboardLayoutDefinition, hid: UInt16) -> KeyDefinition? {
        layout.allKeys.first { $0.hidUsageID.rawValue == hid }
    }

    /// 法语 AZERTY：M 在分号位（HID 0x33），ù 在 HID 0x34，ISO 键是 @#。
    func testFrenchMacOSSymbols() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .fr, targetOS: .macOS)

        XCTAssertEqual(key(layout, hid: 0x33)?.keyName, "m", "French M must sit at the semicolon position")
        XCTAssertEqual(key(layout, hid: 0x10)?.label, ",", "HID 0x10 must be comma on AZERTY")
        XCTAssertEqual(key(layout, hid: 0x34)?.label, "ù")
        XCTAssertEqual(key(layout, hid: 0x64)?.label, "@", "Apple French ISO key is @#")
        XCTAssertEqual(key(layout, hid: 0x64)?.shiftLabel, "#")

        // Number row: & é " ' ( § è ! ç à ) -
        let expected: [(UInt16, String, String)] = [
            (0x1E, "&", "1"), (0x1F, "é", "2"), (0x20, "\"", "3"), (0x21, "'", "4"),
            (0x22, "(", "5"), (0x23, "§", "6"), (0x24, "è", "7"), (0x25, "!", "8"),
            (0x26, "ç", "9"), (0x27, "à", "0"), (0x2D, ")", "°"), (0x2E, "-", "_"),
        ]
        for (hid, label, shift) in expected {
            XCTAssertEqual(key(layout, hid: hid)?.label, label, "HID \(String(hid, radix: 16))")
            XCTAssertEqual(key(layout, hid: hid)?.shiftLabel, shift, "HID \(String(hid, radix: 16))")
        }
    }

    /// 德语：数字行 Shift 层 § & / ( ) =，´ 死键在 0x2E，ISO 键是 ^° 死键。
    func testGermanMacOSSymbols() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .de, targetOS: .macOS)

        let expected: [(UInt16, String)] = [
            (0x20, "§"), (0x23, "&"), (0x24, "/"), (0x25, "("), (0x26, ")"), (0x27, "="),
        ]
        for (hid, shift) in expected {
            XCTAssertEqual(key(layout, hid: hid)?.shiftLabel, shift, "HID \(String(hid, radix: 16))")
        }
        XCTAssertEqual(key(layout, hid: 0x2E)?.label, "´")
        XCTAssertEqual(key(layout, hid: 0x2E)?.deadKey, .acute)
        XCTAssertEqual(key(layout, hid: 0x64)?.label, "^", "Apple German ISO key is ^°")
        XCTAssertEqual(key(layout, hid: 0x64)?.deadKey, .circumflex)
        XCTAssertEqual(key(layout, hid: 0x2F)?.label, "ü")
        XCTAssertEqual(key(layout, hid: 0x33)?.label, "ö")
        XCTAssertEqual(key(layout, hid: 0x34)?.label, "ä")
    }

    /// PC 法语 AZERTY：M 位置、ISO 键 <>、数字行 Shift 才是数字。
    func testFrenchWindowsSymbols() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .fr, targetOS: .windows)

        XCTAssertEqual(key(layout, hid: 0x33)?.keyName, "m")
        XCTAssertEqual(key(layout, hid: 0x34)?.label, "ù")
        XCTAssertEqual(key(layout, hid: 0x64)?.label, "<")
        XCTAssertEqual(key(layout, hid: 0x64)?.shiftLabel, ">")
        XCTAssertEqual(key(layout, hid: 0x1E)?.label, "&")
        XCTAssertEqual(key(layout, hid: 0x1E)?.shiftLabel, "1")
        XCTAssertEqual(key(layout, hid: 0x27)?.altGrLabel, "@", "PC French @ is AltGr+à(0)")
    }

    /// 9 个 ISO 地区在所有 OS 变体中都有 HID 0x64（LeftShift 旁）。
    func testISOKeyPresentInISOLocales() throws {
        let isoLocales: [KeyboardLocale] = [.uk, .de, .fr, .es, .it, .pt, .be, .ch, .nordic]
        for locale in isoLocales {
            for os in [TargetOS.macOS, .windows, .linux] {
                let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                let isoKey = key(layout, hid: 0x64)
                XCTAssertNotNil(isoKey, "\(locale.rawValue)_\(os.rawValue) missing ISO key (HID 0x64)")
                XCTAssertTrue(layout.rows[4].contains { $0.hidUsageID.rawValue == 0x64 },
                              "\(locale.rawValue)_\(os.rawValue) ISO key must be in row 4")
            }
        }
    }

    /// ANSI 地区（us/au/ca/cn）不应有 ISO 键。
    func testANSILocalesHaveNoISOKey() throws {
        for locale in [KeyboardLocale.us, .au, .ca, .cn] {
            for os in [TargetOS.macOS, .windows, .linux] {
                let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                XCTAssertNil(key(layout, hid: 0x64), "\(locale.rawValue)_\(os.rawValue) must not have ISO key")
            }
        }
    }

    /// macOS 变体使用 Apple 修饰键符号与 ⌫/⇥/↩；PC 变体使用文字标签。
    func testModifierLabelsMatchTargetOS() throws {
        for locale in [KeyboardLocale.us, .fr, .de] {
            let mac = try KeyboardLayoutLoader.load(locale: locale, targetOS: .macOS)
            XCTAssertEqual(mac.keyDefinition(for: "LeftCtrl")?.label, "⌃")
            XCTAssertEqual(mac.keyDefinition(for: "LeftAlt")?.label, "⌥")
            XCTAssertEqual(mac.keyDefinition(for: "LeftWin")?.label, "⌘")
            XCTAssertEqual(mac.keyDefinition(for: "Backspace")?.label, "⌫")
            XCTAssertEqual(mac.keyDefinition(for: "Enter")?.label, "↩")
            XCTAssertNotNil(mac.keyDefinition(for: "Fn"), "macOS layout needs the local Fn layer key")

            let pc = try KeyboardLayoutLoader.load(locale: locale, targetOS: .windows)
            XCTAssertEqual(pc.keyDefinition(for: "LeftCtrl")?.label, "Ctrl")
            XCTAssertEqual(pc.keyDefinition(for: "LeftWin")?.label, "Win")
            XCTAssertEqual(pc.keyDefinition(for: "Backspace")?.label, "Backspace")
        }
    }
}