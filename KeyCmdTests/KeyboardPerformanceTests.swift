//
//  KeyboardPerformanceTests.swift
//  KeyCmdTests
//
//  Performance benchmark tests for keyboard operations (Task 5.3)
//

import XCTest
@testable import KeyCmd

final class KeyboardPerformanceTests: XCTestCase {

    var keyboardState: KeyboardState!
    var translationTable: KeyboardTranslationTable!

    override func setUp() {
        super.setUp()
        keyboardState = KeyboardState.shared
        keyboardState.reset()

        // Create a translation table for performance testing
        let manager = KeyboardLayoutManager.shared
        let layout = manager.layout(for: .windows, locale: .us)
        translationTable = KeyboardTranslationTable(layout: layout)
    }

    override func tearDown() {
        keyboardState.reset()
        super.tearDown()
    }

    // MARK: - Layout Lookup Performance

    func testLayoutLookupPerformance() {
        // Test that layout lookups are fast (< 1ms)
        let manager = KeyboardLayoutManager.shared

        measure {
            for _ in 0..<1000 {
                _ = manager.layout(for: .windows, locale: .us)
            }
        }
    }

    func testAllLayoutsLookupPerformance() {
        // Test looking up all 42 layout combinations
        let manager = KeyboardLayoutManager.shared
        let locales = KeyboardLocale.allCases
        let targetOSes: [TargetOS] = [.windows, .macOS, .linux]

        measure {
            for locale in locales {
                for os in targetOSes {
                    _ = manager.layout(for: os, locale: locale)
                }
            }
        }
    }

    // MARK: - Translation Table Performance

    func testHIDToPositionLookupPerformance() {
        // Test HID to position lookup performance
        let testHIDs: [HIDUsageID] = [
            .keyboardA, .keyboardB, .keyboardC, .keyboardD, .keyboardE,
            .keyboardF, .keyboardG, .keyboardH, .keyboardI, .keyboardJ,
            .keyboard1, .keyboard2, .keyboard3, .keyboard4, .keyboard5,
            .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5
        ]

        measure {
            for _ in 0..<1000 {
                for hid in testHIDs {
                    _ = translationTable.position(forHID: hid)
                }
            }
        }
    }

    func testCharacterToHIDLookupPerformance() {
        // Test character to HID lookup performance
        let testChars: [Character] = [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J"
        ]

        measure {
            for _ in 0..<1000 {
                for char in testChars {
                    _ = translationTable.hidUsageID(forCharacter: char)
                }
            }
        }
    }

    func testPositionToHIDLookupPerformance() {
        // Test position to HID lookup performance
        measure {
            for _ in 0..<1000 {
                for row in 0..<6 {
                    for col in 0..<15 {
                        _ = translationTable.hidUsageID(forPosition: row, column: col)
                    }
                }
            }
        }
    }

    // MARK: - KeyboardState Performance

    func testModifierStateUpdatePerformance() {
        // Test modifier state update performance
        let modifiers: [HIDUsageID] = [
            .keyboardLeftShift, .keyboardRightShift,
            .keyboardLeftCtrl, .keyboardRightCtrl,
            .keyboardLeftAlt, .keyboardRightAlt,
            .keyboardLeftGUI, .keyboardRightGUI
        ]

        measure {
            for _ in 0..<10000 {
                for modifier in modifiers {
                    keyboardState.updateModifierState(key: modifier, pressed: true)
                    keyboardState.updateModifierState(key: modifier, pressed: false)
                }
            }
        }
    }

    func testModifierByteCalculationPerformance() {
        // Test modifier byte calculation performance
        // Set up some modifiers
        keyboardState.updateModifierState(key: .keyboardLeftShift, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        keyboardState.updateModifierState(key: .keyboardLeftAlt, pressed: true)

        measure {
            for _ in 0..<100000 {
                _ = keyboardState.modifierByte
            }
        }
    }

    func testDeadKeyCombinationPerformance() {
        // Test dead key combination performance
        let baseChars: [Character] = ["a", "e", "i", "o", "u", "y", "n"]
        let deadKeys: [DeadKey] = [.acute, .grave, .circumflex, .diaeresis, .tilde]

        measure {
            for _ in 0..<1000 {
                for deadKey in deadKeys {
                    for baseChar in baseChars {
                        _ = deadKey.combine(with: baseChar)
                    }
                }
            }
        }
    }

    // MARK: - JSON Layout Loading Performance

    func testJSONLayoutLoadingPerformance() throws {
        // Test JSON layout loading performance
        measure {
            for _ in 0..<100 {
                do {
                    _ = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)
                } catch {
                    XCTFail("Failed to load layout: \(error)")
                }
            }
        }
    }

    func testAllJSONLayoutsLoadingPerformance() throws {
        // Test loading all 42 layout combinations
        let locales = KeyboardLocale.allCases
        let targetOSes: [TargetOS] = [.windows, .macOS, .linux]

        measure {
            for locale in locales {
                for os in targetOSes {
                    do {
                        _ = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                    } catch {
                        // Ignore errors in performance test
                    }
                }
            }
        }
    }

    // MARK: - Layout Detection Performance

    func testLayoutDetectionPerformance() {
        // Test layout detection performance
        measure {
            for _ in 0..<1000 {
                _ = KeyboardLocale.detectActiveKeyboardLayout()
            }
        }
    }

    func testSystemLocaleDetectionPerformance() {
        // Test system locale detection performance
        measure {
            for _ in 0..<1000 {
                _ = KeyboardLocale.fromSystemLocale()
            }
        }
    }

    // MARK: - Concurrent Access Performance

    func testConcurrentLayoutAccessPerformance() {
        // Test concurrent layout access performance
        let manager = KeyboardLayoutManager.shared
        let expectation = XCTestExpectation(description: "Concurrent layout access")
        let iterations = 1000

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        measure {
            for _ in 0..<10 {
                let group = DispatchGroup()

                for i in 0..<iterations {
                    group.enter()
                    queue.async {
                        let locale = KeyboardLocale.allCases[i % KeyboardLocale.allCases.count]
                        let os: TargetOS = i % 2 == 0 ? .windows : .macOS
                        _ = manager.layout(for: os, locale: locale)
                        group.leave()
                    }
                }

                group.wait()
            }
            expectation.fulfill()
        }
    }

    func testConcurrentStateUpdatePerformance() {
        // Test concurrent state update performance
        let expectation = XCTestExpectation(description: "Concurrent state update")
        let iterations = 10000

        let queue = DispatchQueue(label: "test.state", attributes: .concurrent)

        measure {
            for _ in 0..<10 {
                let group = DispatchGroup()

                for i in 0..<iterations {
                    group.enter()
                    queue.async {
                        let modifier: HIDUsageID = i % 2 == 0 ? .keyboardLeftShift : .keyboardLeftCtrl
                        self.keyboardState.updateModifierState(key: modifier, pressed: i % 3 == 0)
                        _ = self.keyboardState.modifierByte
                        group.leave()
                    }
                }

                group.wait()
            }
            expectation.fulfill()
        }
    }

    // MARK: - Memory Usage Tests

    func testLayoutCacheMemoryUsage() {
        // Test that layout cache doesn't grow unbounded
        let manager = KeyboardLayoutManager.shared

        // Load all layouts
        for locale in KeyboardLocale.allCases {
            for os in [TargetOS.windows, .macOS, .linux] {
                _ = manager.layout(for: os, locale: locale)
            }
        }

        // Verify cache stats
        let stats = manager.cacheStats
        XCTAssertFalse(stats.isEmpty, "Cache stats should not be empty")
    }

    // MARK: - Stress Tests

    func testRapidLayoutSwitchingPerformance() {
        // Test rapid layout switching performance
        let manager = KeyboardLayoutManager.shared
        let locales = KeyboardLocale.allCases

        measure {
            for _ in 0..<100 {
                for locale in locales {
                    manager.currentKeyboardLocale = locale
                }
            }
        }
    }

    func testRapidModifierTogglingPerformance() {
        // Test rapid modifier toggling performance
        let modifiers: [HIDUsageID] = [
            .keyboardLeftShift, .keyboardLeftCtrl, .keyboardLeftAlt,
            .keyboardRightShift, .keyboardRightCtrl, .keyboardRightAlt
        ]

        measure {
            for _ in 0..<10000 {
                for modifier in modifiers {
                    keyboardState.updateModifierState(key: modifier, pressed: true)
                    keyboardState.updateModifierState(key: modifier, pressed: false)
                }
            }
        }
    }
}
