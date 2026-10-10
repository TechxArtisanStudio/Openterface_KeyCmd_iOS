// KeyCmdTests/HIDUsageIDTests.swift
import XCTest
@testable import KeyCmd

final class HIDUsageIDTests: XCTestCase {

    func testLetterKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardA.rawValue, 0x04)
        XCTAssertEqual(HIDUsageID.keyboardZ.rawValue, 0x1D)
    }

    func testNumberKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboard1.rawValue, 0x1E)
        XCTAssertEqual(HIDUsageID.keyboard0.rawValue, 0x27)
    }

    func testModifierKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardLeftCtrl.rawValue, 0xE0)
        XCTAssertEqual(HIDUsageID.keyboardRightAlt.rawValue, 0xE6)
    }

    func testJapaneseKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardInternational1.rawValue, 0x87)
        XCTAssertEqual(HIDUsageID.keyboardInternational5.rawValue, 0x8B)
    }

    func testAllCasesCount() {
        // 确保所有键都被定义
        XCTAssertGreaterThan(HIDUsageID.allCases.count, 80)
    }
}