// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import XCTest
@testable import KeyCmd

final class BLESecurityCommandTests: XCTestCase {

    // MARK: - Frames

    func testEraseBondsFrame() {
        XCTAssertEqual(BLESecurityCommand.eraseBondsFrame(),
                       Data([0x57, 0xAB, 0x00, 0x22, 0x01, 0x02, 0x27]))
    }

    func testStatusFrame() {
        XCTAssertEqual(BLESecurityCommand.statusFrame(),
                       Data([0x57, 0xAB, 0x00, 0x22, 0x01, 0x03, 0x28]))
    }

    func testReadMaxBondsFrame() {
        XCTAssertEqual(BLESecurityCommand.readMaxBondsFrame(),
                       Data([0x57, 0xAB, 0x00, 0x22, 0x01, 0x06, 0x2B]))
    }

    func testSetPINFrame() {
        XCTAssertEqual(BLESecurityCommand.setPINFrame("123456"),
                       Data([0x57, 0xAB, 0x00, 0x22, 0x07, 0x04,
                             0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x64]))
    }

    func testSetPINFrameRejectsInvalid() {
        for pin in ["", "12345", "1234567", "12345a", "123 45", "１２３４５６"] {
            XCTAssertNil(BLESecurityCommand.setPINFrame(pin), "should reject: \(pin)")
        }
    }

    // MARK: - PIN Validation

    func testValidatePIN() {
        XCTAssertTrue(BLESecurityCommand.validatePIN("666666"))
        XCTAssertTrue(BLESecurityCommand.validatePIN("000123"))
        XCTAssertTrue(BLESecurityCommand.validatePIN("000000"))
    }

    func testValidatePINRejectsNonASCIIAndWrongLength() {
        for pin in ["", "1", "12345", "1234567", "12345a", "12345 ", " 12345",
                    "１２３４５６", "12345６", "abcdef"] {
            XCTAssertFalse(BLESecurityCommand.validatePIN(pin), "should reject: \(pin)")
        }
    }

    // MARK: - Response Parsing

    func testParseStatus() {
        let status = BLESecurityCommand.parseStatus(Data([0x01, 0x01]))
        XCTAssertEqual(status, BLESecurityCommand.Status(bondCount: 1, maxBonds: 1))
        XCTAssertTrue(status?.isFull == true)
        XCTAssertTrue(status?.isSupported == true)
    }

    func testParseStatusEmptySlot() {
        let status = BLESecurityCommand.parseStatus(Data([0x00, 0x01]))
        XCTAssertEqual(status, BLESecurityCommand.Status(bondCount: 0, maxBonds: 1))
        XCTAssertFalse(status?.isFull == true)
    }

    func testParseStatusRejectsWrongLength() {
        XCTAssertNil(BLESecurityCommand.parseStatus(Data()))
        XCTAssertNil(BLESecurityCommand.parseStatus(Data([0x01])))
        XCTAssertNil(BLESecurityCommand.parseStatus(Data([0x01, 0x01, 0x00])))
    }

    func testUnsupportedFirmwareStatus() {
        // Old firmware: 0x03 answered [status, 0, 0] (bond count + stale window seconds).
        let status = BLESecurityCommand.parseStatus(Data([0x00, 0x00]))
        XCTAssertEqual(status, BLESecurityCommand.Status(bondCount: 0, maxBonds: 0))
        XCTAssertFalse(status?.isSupported == true)
    }

    func testParseMaxBonds() {
        XCTAssertEqual(BLESecurityCommand.parseMaxBonds(Data([0x04])), 4)
        XCTAssertNil(BLESecurityCommand.parseMaxBonds(Data()))
        XCTAssertNil(BLESecurityCommand.parseMaxBonds(Data([0x01, 0x02])))
    }

    // MARK: - Response Scanner

    private let statusResponse = Data([0x57, 0xAB, 0x00, 0xA2, 0x03, 0x00, 0x01, 0x01, 0xA9])
    private let maxResponse = Data([0x57, 0xAB, 0x00, 0xA2, 0x02, 0x00, 0x01, 0xA7])
    private let eraseResponse = Data([0x57, 0xAB, 0x00, 0xA2, 0x01, 0x00, 0xA5])
    private let errorResponse = Data([0x57, 0xAB, 0x00, 0xE2, 0x01, 0xE5, 0xCA])
    private let tunnelFrame = Data([0x57, 0xAB, 0x00, 0x91, 0x01, 0x00, 0x94])

    private func scanner() -> BLENameCommand.ResponseScanner {
        BLENameCommand.ResponseScanner(targetCommands: BLESecurityCommand.responseCommands)
    }

    func testScannerStatusResponse() {
        var scanner = scanner()
        let result = scanner.feed(statusResponse)
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertEqual(result.responses[0].cmd, 0xA2)
        XCTAssertEqual(result.responses[0].status, 0x00)
        XCTAssertEqual(BLESecurityCommand.parseStatus(result.responses[0].payload),
                       BLESecurityCommand.Status(bondCount: 1, maxBonds: 1))
        XCTAssertTrue(result.passthrough.isEmpty)
    }

    func testScannerMaxAndEraseResponses() {
        var scanner = scanner()
        let max = scanner.feed(maxResponse)
        XCTAssertEqual(BLESecurityCommand.parseMaxBonds(max.responses[0].payload), 1)

        var second = self.scanner()
        let erase = second.feed(eraseResponse)
        XCTAssertEqual(erase.responses, [BLENameCommand.Response(cmd: 0xA2, status: 0x00, payload: Data())])
    }

    func testScannerErrorResponse() {
        var scanner = scanner()
        let result = scanner.feed(errorResponse)
        XCTAssertEqual(result.responses, [BLENameCommand.Response(cmd: 0xE2, status: 0xE5, payload: Data())])
    }

    func testScannerPassesTunnelFramesThrough() {
        var scanner = scanner()
        let result = scanner.feed(tunnelFrame)
        XCTAssertTrue(result.responses.isEmpty)
        XCTAssertEqual(result.passthrough, tunnelFrame)
    }

    func testScannerHandlesFragmentedResponse() {
        var scanner = scanner()
        let first = scanner.feed(Data(statusResponse.prefix(4)))
        XCTAssertTrue(first.responses.isEmpty)
        XCTAssertTrue(first.passthrough.isEmpty)

        let result = scanner.feed(Data(statusResponse.suffix(from: 4)))
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertEqual(result.responses[0].cmd, 0xA2)
    }

    func testScannerRejectsBadChecksum() {
        var scanner = scanner()
        var corrupted = statusResponse
        corrupted[corrupted.count - 1] = corrupted[corrupted.count - 1] ^ 0xFF
        let result = scanner.feed(corrupted)
        XCTAssertTrue(result.responses.isEmpty)
        XCTAssertEqual(result.passthrough, corrupted)
    }
}
