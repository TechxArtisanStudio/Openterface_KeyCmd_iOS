// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import XCTest
@testable import KeyCmd

final class BLENameCommandTests: XCTestCase {

    // MARK: - Name Validation

    func testValidASCIIName() {
        XCTAssertEqual(BLENameCommand.validatedNameBytes("KVM-GO"), Array("KVM-GO".utf8))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(BLENameCommand.validatedNameBytes("  KVM-GO \n"), Array("KVM-GO".utf8))
    }

    func testRejectsEmptyAndWhitespaceOnly() {
        XCTAssertNil(BLENameCommand.validatedNameBytes(""))
        XCTAssertNil(BLENameCommand.validatedNameBytes("   \n"))
    }

    func testLengthBoundary() {
        let twenty = String(repeating: "A", count: 20)
        let twentyOne = String(repeating: "A", count: 21)
        XCTAssertNotNil(BLENameCommand.validatedNameBytes(twenty))
        XCTAssertNil(BLENameCommand.validatedNameBytes(twentyOne))
    }

    func testUTF8ByteLengthNotCharacterCount() {
        // 6 Chinese characters = 18 bytes (valid); 7 = 21 bytes (invalid)
        XCTAssertNotNil(BLENameCommand.validatedNameBytes("我的设备名称"))
        XCTAssertNil(BLENameCommand.validatedNameBytes("我的设备名称哈"))
    }

    func testRejectsControlCharacters() {
        XCTAssertNil(BLENameCommand.validatedNameBytes("A\u{01}B"))
        XCTAssertNil(BLENameCommand.validatedNameBytes("\u{00}"))
        XCTAssertNil(BLENameCommand.validatedNameBytes("A\nB"))
        // Single byte <= 0x06 would collide with BLE-Eth GET_ECM_IP on the firmware
        XCTAssertNil(BLENameCommand.validatedNameBytes("\u{03}"))
    }

    // MARK: - Frame Building

    func testSetNameFrameKnownVector() {
        let frame = BLENameCommand.setNameFrame("KVM-GO-TEST")
        let expected = Data([0x57, 0xAB, 0x00, 0x23, 0x0B,
                             0x4B, 0x56, 0x4D, 0x2D, 0x47, 0x4F, 0x2D, 0x54, 0x45, 0x53, 0x54,
                             0x4E])
        XCTAssertEqual(frame, expected)
    }

    func testSetNameFrameTrimsBeforeBuilding() {
        XCTAssertEqual(BLENameCommand.setNameFrame(" KVM-GO-TEST "),
                       BLENameCommand.setNameFrame("KVM-GO-TEST"))
    }

    func testSetNameFrameRejectsInvalidName() {
        XCTAssertNil(BLENameCommand.setNameFrame(""))
        XCTAssertNil(BLENameCommand.setNameFrame(String(repeating: "A", count: 21)))
    }

    func testResetNameFrameKnownVector() {
        XCTAssertEqual(BLENameCommand.resetNameFrame(),
                       Data([0x57, 0xAB, 0x00, 0x31, 0x01, 0x00, 0x34]))
    }

    // MARK: - Response Scanner

    private let okResponse = Data([0x57, 0xAB, 0x00, 0xA3, 0x01, 0x00, 0xA6])
    private let errResponse = Data([0x57, 0xAB, 0x00, 0xE3, 0x01, 0xE5, 0xCB])
    private let dataFrame = Data([0x57, 0xAB, 0x00, 0x91, 0x01, 0x00, 0x94])

    func testScannerSingleResponse() {
        var scanner = BLENameCommand.ResponseScanner()
        let result = scanner.feed(okResponse)
        XCTAssertEqual(result.responses, [BLENameCommand.Response(cmd: 0xA3, status: 0x00, payload: Data())])
        XCTAssertTrue(result.responses[0].isSuccess)
        XCTAssertTrue(result.passthrough.isEmpty)
    }

    func testScannerErrorResponse() {
        var scanner = BLENameCommand.ResponseScanner()
        let result = scanner.feed(errResponse)
        XCTAssertEqual(result.responses, [BLENameCommand.Response(cmd: 0xE3, status: 0xE5, payload: Data())])
        XCTAssertFalse(result.responses[0].isSuccess)
    }

    func testScannerSplitAcrossFeeds() {
        var scanner = BLENameCommand.ResponseScanner()
        let first = scanner.feed(okResponse.prefix(3))
        XCTAssertTrue(first.responses.isEmpty)
        XCTAssertTrue(first.passthrough.isEmpty)
        let second = scanner.feed(okResponse.suffix(from: 3))
        XCTAssertEqual(second.responses.count, 1)
        XCTAssertTrue(second.passthrough.isEmpty)
    }

    func testScannerPassesThroughNonTargetFrames() {
        var scanner = BLENameCommand.ResponseScanner()
        let result = scanner.feed(dataFrame)
        XCTAssertTrue(result.responses.isEmpty)
        XCTAssertEqual(result.passthrough, dataFrame)
    }

    func testScannerPassesThroughGarbage() {
        var scanner = BLENameCommand.ResponseScanner()
        let garbage = Data([0x01, 0x02, 0x57, 0x00, 0x99])
        let result = scanner.feed(garbage)
        XCTAssertTrue(result.responses.isEmpty)
        XCTAssertEqual(result.passthrough, garbage)
    }

    func testScannerInterleavedTerminalDataAndResponse() {
        var scanner = BLENameCommand.ResponseScanner()
        var mixed = Data([0xAA, 0xBB])
        mixed.append(dataFrame)
        mixed.append(okResponse)
        let result = scanner.feed(mixed)
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertEqual(result.passthrough, Data([0xAA, 0xBB]) + dataFrame)
    }

    func testScannerBadChecksumSlidesAndRecovers() {
        var bad = okResponse
        bad[bad.count - 1] = 0x00  // corrupt checksum
        var scanner = BLENameCommand.ResponseScanner()
        let first = scanner.feed(bad)
        XCTAssertTrue(first.responses.isEmpty)
        XCTAssertEqual(first.passthrough, bad)
        let second = scanner.feed(okResponse)
        XCTAssertEqual(second.responses.count, 1)
    }

    func testScannerFlushReleasesPartialFrame() {
        var scanner = BLENameCommand.ResponseScanner()
        _ = scanner.feed(okResponse.prefix(4))
        let remainder = scanner.flush()
        XCTAssertEqual(remainder, okResponse.prefix(4))
        XCTAssertTrue(scanner.flush().isEmpty)
    }
}