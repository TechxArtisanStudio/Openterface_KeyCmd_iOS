//
//  FnLayerTests.swift
//  KeyCmdTests
//
//  The Apple Fn key has no USB HID usage, so jp_macos_jis labels the PC Menu key
//  as "fn" and translates Fn combos locally. These tests pin the mappings that
//  the Mac keyboard normally performs itself: Fn+arrows → Home/End/PgUp/PgDn,
//  Fn+Backspace → forward delete, and Fn alone → no report at all.
//

import XCTest
@testable import KeyCmd

final class FnLayerTests: XCTestCase {

    var keyboardManager: KeyboardManager!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []

    override func setUp() {
        super.setUp()
        KeyboardState.shared.reset()
        keyboardManager = KeyboardManager(bleManager: BLEManager())
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.lockedModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()
        keyboardManager.setFnPressed(false)

        capturedReports.removeAll()
        keyboardManager.hidReportCapture = { [weak self] modifier, keyCodes in
            self?.capturedReports.append((modifier: modifier, keyCodes: keyCodes))
        }
    }

    override func tearDown() {
        keyboardManager.hidReportCapture = nil
        keyboardManager.releaseAllKeys()
        KeyboardState.shared.reset()
        keyboardManager = nil
        capturedReports.removeAll()
        super.tearDown()
    }

    private var lastKeyCode: UInt8? {
        capturedReports.last?.keyCodes.first
    }

    func testFnAloneSendsNoReport() {
        let countBefore = capturedReports.count
        keyboardManager.setFnPressed(true)
        keyboardManager.setFnPressed(false)

        XCTAssertEqual(capturedReports.count, countBefore,
                       "Fn must not be sent as a HID key by itself")
    }

    func testFnArrowsMapToNavigationKeys() {
        let mappings: [(HIDUsageID, HIDUsageID)] = [
            (.keyboardLeftArrow, .keyboardHome),
            (.keyboardRightArrow, .keyboardEnd),
            (.keyboardUpArrow, .keyboardPageUp),
            (.keyboardDownArrow, .keyboardPageDown)
        ]

        keyboardManager.setFnPressed(true)
        for (arrow, expected) in mappings {
            keyboardManager.handleKeyDown(hid: arrow)
            XCTAssertEqual(lastKeyCode, expected.rawValue,
                           "Fn + \(arrow) should send \(expected)")

            keyboardManager.handleKeyUp(hid: arrow)
            XCTAssertEqual(lastKeyCode, 0x00,
                           "Releasing Fn + \(arrow) should release \(expected)")
        }
    }

    func testFnBackspaceSendsForwardDelete() {
        keyboardManager.setFnPressed(true)

        keyboardManager.handleKeyDown(hid: .keyboardBackspace)
        XCTAssertEqual(lastKeyCode, HIDUsageID.keyboardDelete.rawValue)

        keyboardManager.handleKeyUp(hid: .keyboardBackspace)
        XCTAssertEqual(lastKeyCode, 0x00)
    }

    func testArrowWithoutFnIsUnchanged() {
        keyboardManager.handleKeyDown(hid: .keyboardLeftArrow)
        XCTAssertEqual(lastKeyCode, HIDUsageID.keyboardLeftArrow.rawValue)
        keyboardManager.handleKeyUp(hid: .keyboardLeftArrow)
    }

    func testReleasingFnBeforeMappedKeyStillReleasesIt() {
        keyboardManager.setFnPressed(true)
        keyboardManager.handleKeyDown(hid: .keyboardLeftArrow)
        XCTAssertTrue(keyboardManager.isKeyPressed(hid: .keyboardLeftArrow),
                      "The original arrow key should still show pressed")
        XCTAssertTrue(keyboardManager.pressedKeys.contains(.keyboardHome))

        keyboardManager.setFnPressed(false)
        keyboardManager.handleKeyUp(hid: .keyboardLeftArrow)

        XCTAssertFalse(keyboardManager.pressedKeys.contains(.keyboardHome),
                       "Forward Delete/Home must not stay stuck on the host")
        XCTAssertEqual(lastKeyCode, 0x00)
    }
}
