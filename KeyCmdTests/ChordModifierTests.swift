//
//  ChordModifierTests.swift
//  KeyCmdTests
//
//  Regression tests: a held modifier must be present in the modifier byte of the
//  next key's HID report. Previously KeyboardState tracked no GUI (Cmd/Win) state
//  and the tracked-only chord path never updated it, so Cmd+Tab reached the host
//  as a bare Tab.
//

import XCTest
@testable import KeyCmd

final class ChordModifierTests: XCTestCase {

    var keyboardManager: KeyboardManager!
    var keyboardState: KeyboardState!
    var capturedReports: [(modifier: UInt8, keyCodes: [UInt8])] = []

    override func setUp() {
        super.setUp()
        keyboardState = KeyboardState.shared
        keyboardState.reset()
        keyboardManager = KeyboardManager(bleManager: BLEManager())
        keyboardManager.activeModifiers.removeAll()
        keyboardManager.lockedModifiers.removeAll()
        keyboardManager.pressedKeys.removeAll()

        capturedReports.removeAll()
        keyboardManager.hidReportCapture = { [weak self] modifier, keyCodes in
            self?.capturedReports.append((modifier: modifier, keyCodes: keyCodes))
        }
    }

    override func tearDown() {
        keyboardManager.hidReportCapture = nil
        keyboardManager.releaseAllKeys()
        keyboardState.reset()
        keyboardManager = nil
        capturedReports.removeAll()
        super.tearDown()
    }

    // MARK: - KeyboardState

    func testGUIStateIsReflectedInModifierByte() {
        keyboardState.updateModifierState(key: .keyboardLeftGUI, pressed: true)
        XCTAssertTrue(keyboardState.isLeftGUIPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x08)

        keyboardState.updateModifierState(key: .keyboardRightGUI, pressed: true)
        XCTAssertTrue(keyboardState.isRightGUIPressed)
        XCTAssertEqual(keyboardState.modifierByte, 0x88)

        keyboardState.clearAllModifiers()
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    // MARK: - Momentary chord, standalone modifier-down enabled (default)

    func testCmdTabWithSustainedHIDKeepsCommandBit() {
        keyboardManager.handleKeyDown(hid: .keyboardLeftGUI)

        XCTAssertEqual(capturedReports.last?.modifier, 0x08,
                       "Cmd-down report should contain the left GUI bit")
        XCTAssertEqual(capturedReports.last?.keyCodes, [0, 0, 0, 0, 0, 0])

        keyboardManager.handleKeyDown(hid: .keyboardTab)

        XCTAssertEqual(capturedReports.last?.modifier, 0x08,
                       "Tab must be sent with Cmd held, not as a bare Tab")
        XCTAssertEqual(capturedReports.last?.keyCodes.first, HIDUsageID.keyboardTab.rawValue)

        keyboardManager.handleKeyUp(hid: .keyboardTab)
        XCTAssertEqual(capturedReports.last?.modifier, 0x08,
                       "Cmd stays held after Tab is released")
        XCTAssertEqual(capturedReports.last?.keyCodes.first, 0x00)

        keyboardManager.handleKeyUp(hid: .keyboardLeftGUI)
        XCTAssertEqual(capturedReports.last?.modifier, 0x00)
    }

    // MARK: - Momentary chord, tracked-only mode (chordSustainHid == false)

    func testCmdTabTrackedOnlyKeepsCommandBit() {
        keyboardManager.addModifierTrackedOnly("LeftWin")

        XCTAssertTrue(capturedReports.isEmpty,
                      "Tracked-only mode must not send a standalone modifier report")
        XCTAssertEqual(keyboardState.modifierByte, 0x08)

        keyboardManager.handleKeyDown(hid: .keyboardTab)

        XCTAssertEqual(capturedReports.last?.modifier, 0x08,
                       "Tracked Cmd must be included in the reported chord")
        XCTAssertEqual(capturedReports.last?.keyCodes.first, HIDUsageID.keyboardTab.rawValue)

        keyboardManager.handleKeyUp(hid: .keyboardTab)
        keyboardManager.handleKeyUp(hid: .keyboardLeftGUI)

        XCTAssertEqual(capturedReports.last?.modifier, 0x00)
        XCTAssertEqual(keyboardState.modifierByte, 0x00)
    }

    func testRightGUIUsesRightModifierBit() {
        keyboardManager.addModifierTrackedOnly("RightWin")
        keyboardManager.handleKeyDown(hid: .keyboardTab)

        XCTAssertEqual(capturedReports.last?.modifier, 0x80,
                       "Right Win/Cmd must set the right GUI bit (0x80)")
    }

    // MARK: - Token scripts (<CMD>t</CMD>)

    func testSilentModifierFeedsSynchronousKeyPress() {
        keyboardManager.addModifierSilently("Cmd")
        XCTAssertEqual(keyboardState.modifierByte, 0x08)

        let expectation = expectation(description: "press and release reports")
        var reportCount = 0
        keyboardManager.hidReportCapture = { [weak self] modifier, keyCodes in
            self?.capturedReports.append((modifier: modifier, keyCodes: keyCodes))
            reportCount += 1
            if reportCount >= 2 { expectation.fulfill() }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.keyboardManager.sendKeyPressSynchronous("t")
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(capturedReports.first?.modifier, 0x08,
                       "Synchronous key press must carry the silently queued Cmd")
        XCTAssertEqual(capturedReports.first?.keyCodes.first, HIDUsageID.keyboardT.rawValue)
        XCTAssertEqual(capturedReports.last?.modifier, 0x00)
        XCTAssertEqual(capturedReports.last?.keyCodes, [0, 0, 0, 0, 0, 0])
    }

    func testClearKeyStateSilentlyClearsGUIBit() {
        keyboardManager.addModifierTrackedOnly("LeftWin")
        XCTAssertEqual(keyboardState.modifierByte, 0x08)

        keyboardManager.clearKeyStateSilently()

        XCTAssertEqual(keyboardState.modifierByte, 0x00)
        XCTAssertTrue(keyboardManager.activeModifiers.isEmpty)
    }
}
