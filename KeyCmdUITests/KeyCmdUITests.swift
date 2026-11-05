// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

//
//  KeyCmdUITests.swift
//  KeyCmdUITests
//
//  UI coverage for the Keyboard & Mouse Basic surface: submode tab switching and the
//  setup sheet.
//

import XCTest

/// The app lands on Keyboard & Mouse Basic with the Touchpad submode selected, and
/// `ViewManager.loadLastView` pins that landing view, so the surface itself is stable.
/// The first-run launch panel, however, is a ZStack overlay that covers everything and
/// swallows taps. Setting `HasSeenLaunchPanel` through the argument domain starts every
/// test from the same screen without adding test-only branches to the app.
final class KeyCmdUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // The remembered launch-panel mode is persisted by the app itself, so pin it here too:
        // without it a previous run that picked Pro starts there and no test lands on Basic.
        app.launchArguments = ["-HasSeenLaunchPanel", "YES",
                               "-LaunchPanelSelectedMode", "Keyboard & Mouse"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // The keyboard submode locks the interface to landscape; hand the device back
        // upright so a run does not leave the simulator rotated.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Helpers

    /// Submode containers carry an `accessibilityIdentifier` but no distinct element
    /// type, so they resolve from the full descendant set. Typed queries such as
    /// `otherElements[...]` miss them, and every lookup costs a whole-tree snapshot.
    private func surface(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Portrait and landscape each render their own tab bar, so query defensively.
    private func tab(_ submode: String) -> XCUIElement {
        app.buttons["km-tab-\(submode)"].firstMatch
    }

    /// Orientation is not observable through a predicate, so poll the app's geometry:
    /// the keyboard submode locks the interface to landscape, which shows up as the
    /// application frame rotating rather than as a device-orientation flag.
    private var isLandscape: Bool {
        app.frame.width > app.frame.height
    }

    private func pollUntil(_ timeout: TimeInterval = 10, _ check: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return check()
    }

    /// Sidebar rows label themselves with the nav icon plus the title, so match the title
    /// as a substring rather than by exact label.
    private func sidebarRow(containing title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func openSidebar() {
        app.buttons["line.3.horizontal"].firstMatch.tap()
        XCTAssertTrue(sidebarRow(containing: "Gamepad").waitForExistence(timeout: 5),
                      "the sidebar did not open")
    }

    // MARK: - Tests

    @MainActor
    func testLaunchesIntoTouchpadSubmodeWithAllTabs() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15),
                      "expected the Touchpad submode on launch")

        for submode in ["touchpad", "keyboard", "numpad"] {
            XCTAssertTrue(tab(submode).exists, "missing tab button for \(submode)")
        }
    }

    @MainActor
    func testKeyboardTabShowsKeyboardAndLocksLandscape() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15))

        tab("keyboard").tap()

        XCTAssertTrue(surface("km-submode-keyboard").waitForExistence(timeout: 15),
                      "the keyboard submode never appeared")
        // Only one submode renders at a time, so its arrival is the switch; asserting
        // the old one is gone would mean waiting out a full snapshot timeout per query.
        XCTAssertTrue(pollUntil { self.isLandscape },
                      "the keyboard submode locks to landscape; the frame stayed portrait")
    }

    @MainActor
    func testTouchpadTabReturnsToPortrait() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15))

        tab("keyboard").tap()
        XCTAssertTrue(surface("km-submode-keyboard").waitForExistence(timeout: 15))
        XCTAssertTrue(pollUntil { self.isLandscape })

        tab("touchpad").tap()

        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15),
                      "returning to the Touchpad tab did not restore that submode")
        XCTAssertTrue(pollUntil { !self.isLandscape },
                      "the touchpad submode should unlock orientation back to portrait")
    }

    @MainActor
    func testNumpadTabShowsNumpadSurface() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15))

        tab("numpad").tap()

        XCTAssertTrue(surface("km-submode-numpad").waitForExistence(timeout: 15),
                      "the numpad submode never appeared")
    }

    @MainActor
    func testSetupSheetOpensFromGearAndClosesWithDone() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15))

        app.buttons["km-setup-button"].tap()

        let setupBar = app.navigationBars["Setup"]
        XCTAssertTrue(setupBar.waitForExistence(timeout: 10),
                      "the Keyboard & Mouse setup sheet did not open")

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.exists, "the setup sheet has no Done control")
        done.tap()

        XCTAssertFalse(setupBar.waitForExistence(timeout: 3),
                       "the setup sheet stayed on screen after tapping Done")
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 10),
                      "the touchpad surface should still be there once setup dismisses")
    }

    /// Pro picks its layout from `orientationManager.isLandscape`, which used to stay pinned to
    /// the landscape lock the Basic keyboard submode had applied — so the first switch drew the
    /// landscape layout inside the portrait window.
    @MainActor
    func testProLaysOutForPortraitAfterLeavingLandscape() throws {
        XCTAssertTrue(surface("km-submode-touchpad").waitForExistence(timeout: 15))

        tab("keyboard").tap()
        XCTAssertTrue(pollUntil { self.isLandscape },
                      "expected the keyboard submode in landscape before switching")

        openSidebar()
        sidebarRow(containing: "Keyboard & Mouse Pro").tap()

        XCTAssertTrue(pollUntil { !self.isLandscape },
                      "Pro unlocks the landscape lock, so the window should return to portrait")
        XCTAssertTrue(app.staticTexts["TouchPad"].waitForExistence(timeout: 10),
                      "the Pro surface should render its portrait layout in a portrait window")
    }
}
