//
//  JISKeyboardLayoutTests.swift
//  KeyCmdTests
//
//  Japanese (JIS) special keys: HID usage IDs and touch-frame hit testing.
//

import XCTest
@testable import KeyCmd

final class JISKeyboardLayoutTests: XCTestCase {

    private var originalLocale: KeyboardLocale!
    private var originalPhysicalStandard: KeyboardLocale.PhysicalStandard!
    private var keyboardManager: KeyboardManager!

    override func setUp() {
        super.setUp()

        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        KeyboardLayoutLoader.layoutsDirectoryOverride = "\(projectRoot)/Resources/KeyboardLayouts"
        KeyboardLayoutManager.shared.clearCache()

        originalLocale = KeyboardLayoutManager.shared.currentKeyboardLocale
        originalPhysicalStandard = KeyboardLayoutManager.shared.physicalStandard
        KeyboardLayoutManager.shared.currentKeyboardLocale = .jp
        // Pin the JIS variant regardless of what earlier tests persisted.
        KeyboardLayoutManager.shared.physicalStandard = .jis

        keyboardManager = KeyboardManager(bleManager: BLEManager())
    }

    override func tearDown() {
        keyboardManager = nil
        KeyboardLayoutManager.shared.physicalStandard = originalPhysicalStandard
        KeyboardLayoutManager.shared.currentKeyboardLocale = originalLocale
        KeyboardLayoutManager.shared.clearCache()
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        super.tearDown()
    }

    /// JIS keys must use the usages defined by the HID keyboard page:
    /// 0x87 Ro, 0x88 Kana, 0x8A Henkan (変換), 0x8B Muhenkan (無変換).
    /// Apple JIS instead uses 0x90 かな and 0x91 英数 beside Space and has no
    /// 変換/無変換 keys at all.
    func testJISSpecialKeysUseStandardHIDUsages() throws {
        let windows = try KeyboardLayoutLoader.load(locale: .jp, targetOS: .windows)
        XCTAssertEqual(windows.keyDefinition(for: "Ro")?.hidUsageID, HIDUsageID(rawValue: 0x87))
        XCTAssertEqual(windows.keyDefinition(for: "Kana")?.hidUsageID, HIDUsageID(rawValue: 0x88))
        XCTAssertEqual(windows.keyDefinition(for: "変換")?.hidUsageID, HIDUsageID(rawValue: 0x8A))
        XCTAssertEqual(windows.keyDefinition(for: "無変換")?.hidUsageID, HIDUsageID(rawValue: 0x8B))

        let linux = try KeyboardLayoutLoader.load(locale: .jp, targetOS: .linux)
        XCTAssertEqual(linux.keyDefinition(for: "Ro")?.hidUsageID, HIDUsageID(rawValue: 0x87))
        XCTAssertEqual(linux.keyDefinition(for: "Kana")?.hidUsageID, HIDUsageID(rawValue: 0x88))

        let mac = try KeyboardLayoutLoader.load(locale: .jp, targetOS: .macOS)
        XCTAssertEqual(mac.keyDefinition(for: "Ro")?.hidUsageID, HIDUsageID(rawValue: 0x87))
        XCTAssertEqual(mac.keyDefinition(for: "かな")?.hidUsageID, .keyboardLANG1)
        XCTAssertEqual(mac.keyDefinition(for: "英数")?.hidUsageID, .keyboardLANG2)
        XCTAssertNil(mac.keyDefinition(for: "Kana"))
        XCTAssertNil(mac.keyDefinition(for: "変換"))
        XCTAssertNil(mac.keyDefinition(for: "無変換"))
    }

    func testJISSpecialKeysResolveToLayoutHIDs() {
        XCTAssertEqual(keyboardManager.hidUsageID(forKey: "Ro"), HIDUsageID(rawValue: 0x87))

        switch AISettings.shared.targetOS {
        case .macOS:
            XCTAssertEqual(keyboardManager.hidUsageID(forKey: "かな"), .keyboardLANG1)
            XCTAssertEqual(keyboardManager.hidUsageID(forKey: "英数"), .keyboardLANG2)
        case .windows, .linux:
            XCTAssertEqual(keyboardManager.hidUsageID(forKey: "Kana"), HIDUsageID(rawValue: 0x88))
            XCTAssertEqual(keyboardManager.hidUsageID(forKey: "変換"), HIDUsageID(rawValue: 0x8A))
            XCTAssertEqual(keyboardManager.hidUsageID(forKey: "無変換"), HIDUsageID(rawValue: 0x8B))
        }
    }

    /// Conversion keys are not auto-repeat keys; on Apple JIS that applies to
    /// 英数/かな because 変換/無変換 do not exist on the keyboard.
    func testJISConversionKeysAreJapaneseSpecialType() throws {
        let windows = try KeyboardLayoutLoader.load(locale: .jp, targetOS: .windows)
        for name in ["Kana", "変換", "無変換"] {
            XCTAssertEqual(windows.keyDefinition(for: name)?.keyType, .japaneseSpecial,
                           "windows \(name)")
        }

        let mac = try KeyboardLayoutLoader.load(locale: .jp, targetOS: .macOS)
        for name in ["英数", "かな"] {
            XCTAssertEqual(mac.keyDefinition(for: name)?.keyType, .japaneseSpecial,
                           "macOS \(name)")
        }
    }

    /// The touch registry must hit-test the measured view frames, which differ
    /// from the layout grid (inverted-T arrows, JIS keys after the arrow cluster).
    func testRegistryHitTestsMeasuredFrames() {
        let registry = KeyFrameRegistry()
        registry.setRegistrations([
            KeyRegistration(keyId: "Up", keyName: "Up", keyType: .regular,
                            frame: CGRect(x: 100, y: 0, width: 50, height: 50)),
            KeyRegistration(keyId: "Down", keyName: "Down", keyType: .regular,
                            frame: CGRect(x: 100, y: 50, width: 50, height: 50)),
            KeyRegistration(keyId: "変換", keyName: "変換", keyType: .japaneseSpecial,
                            frame: CGRect(x: 150, y: 50, width: 50, height: 50))
        ])

        XCTAssertEqual(registry.hitTest(CGPoint(x: 120, y: 25))?.keyName, "Up")
        XCTAssertEqual(registry.hitTest(CGPoint(x: 120, y: 75))?.keyName, "Down")
        XCTAssertEqual(registry.hitTest(CGPoint(x: 170, y: 75))?.keyName, "変換")
        XCTAssertNil(registry.hitTest(CGPoint(x: 10, y: 10)))
    }
}
