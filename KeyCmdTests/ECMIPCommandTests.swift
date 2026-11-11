// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import XCTest
@testable import KeyCmd

final class ECMIPCommandTests: XCTestCase {

    // MARK: - Frames

    func testGetFrame() {
        XCTAssertEqual(ECMIPCommand.getFrame(), Data([0x57, 0xAB, 0x00, 0x23, 0x01, 0x00, 0x26]))
    }

    func testResetFrame() {
        XCTAssertEqual(ECMIPCommand.resetFrame(), Data([0x57, 0xAB, 0x00, 0x22, 0x01, 0x04, 0x29]))
    }

    func testSetAllFrameDefaults() {
        let frame = ECMIPCommand.setAllFrame(ECMIPCommand.defaultConfig)
        XCTAssertNotNil(frame)
        guard let frame else { return }
        XCTAssertEqual(frame.count, 27)
        XCTAssertEqual(Array(frame.prefix(6)), [0x57, 0xAB, 0x00, 0x22, 0x15, 0x00])
        let expectedIPs: [UInt8] = [
            192, 168, 11, 1,
            192, 168, 11, 3,
            255, 255, 255, 0,
            192, 168, 11, 2,
            192, 168, 11, 5
        ]
        XCTAssertEqual(Array(frame.dropFirst(6).dropLast()), expectedIPs)
        let checksum = frame.dropLast().reduce(UInt8(0)) { $0 &+ $1 }
        XCTAssertEqual(frame.last, checksum)
    }

    func testSetAllFrameRejectsInvalidConfig() {
        var config = ECMIPCommand.defaultConfig
        config.targetHostIP = [10, 0, 0, 2]
        config.targetDevIP = [10, 0, 0, 5]
        XCTAssertNil(ECMIPCommand.setAllFrame(config))
    }

    // MARK: - IPv4 Text

    func testParseIPv4Valid() {
        XCTAssertEqual(ECMIPCommand.parseIPv4("192.168.11.1"), [192, 168, 11, 1])
        XCTAssertEqual(ECMIPCommand.parseIPv4("0.0.0.1"), [0, 0, 0, 1])
        XCTAssertEqual(ECMIPCommand.parseIPv4("255.255.255.255"), [255, 255, 255, 255])
    }

    func testParseIPv4Invalid() {
        for text in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "1..2.3", "a.b.c.d", "1.2.3.-4", "1.2.3.4 ", "１.2.3.4"] {
            XCTAssertNil(ECMIPCommand.parseIPv4(text), "should reject: \(text)")
        }
    }

    func testFormatIPv4() {
        XCTAssertEqual(ECMIPCommand.formatIPv4([10, 0, 0, 1]), "10.0.0.1")
    }

    // MARK: - Validation

    func testDefaultConfigValid() {
        XCTAssertTrue(ECMIPCommand.validate(ECMIPCommand.defaultConfig))
    }

    func testCrossSubnetRejected() {
        var config = ECMIPCommand.defaultConfig
        config.targetHostIP = [10, 0, 0, 2]
        config.targetDevIP = [10, 0, 0, 5]
        XCTAssertFalse(ECMIPCommand.validate(config))
    }

    func testDuplicateIPRejected() {
        var config = ECMIPCommand.defaultConfig
        config.devIP = config.hostIP
        XCTAssertFalse(ECMIPCommand.validate(config))
    }

    func testNonContiguousMaskRejected() {
        var config = ECMIPCommand.defaultConfig
        config.subnetMask = [255, 0, 255, 0]
        XCTAssertFalse(ECMIPCommand.validate(config))
    }

    func testZeroAndFullMaskRejected() {
        var config = ECMIPCommand.defaultConfig
        config.subnetMask = [0, 0, 0, 0]
        XCTAssertFalse(ECMIPCommand.validate(config))
        config.subnetMask = [255, 255, 255, 255]
        XCTAssertFalse(ECMIPCommand.validate(config))
    }

    func testZeroAndBroadcastIPRejected() {
        var config = ECMIPCommand.defaultConfig
        config.hostIP = [0, 0, 0, 0]
        XCTAssertFalse(ECMIPCommand.validate(config))
        config = ECMIPCommand.defaultConfig
        config.targetDevIP = [255, 255, 255, 255]
        XCTAssertFalse(ECMIPCommand.validate(config))
    }

    func testWideMaskValid() {
        var config = ECMIPCommand.defaultConfig
        config.subnetMask = [255, 255, 0, 0]
        config.hostIP = [172, 16, 1, 1]
        config.devIP = [172, 16, 2, 1]
        config.targetHostIP = [172, 16, 3, 1]
        config.targetDevIP = [172, 16, 4, 1]
        XCTAssertTrue(ECMIPCommand.validate(config))
    }

    // MARK: - Config Parsing

    func testParseConfigRoundTrip() {
        guard let frame = ECMIPCommand.setAllFrame(ECMIPCommand.defaultConfig) else {
            XCTFail("setAllFrame returned nil")
            return
        }
        let payload = frame.dropFirst(6).dropLast()  // strip header (incl. sub_cmd) and checksum
        XCTAssertEqual(ECMIPCommand.parseConfig(Data(payload)), ECMIPCommand.defaultConfig)
    }

    func testParseConfigWrongLength() {
        XCTAssertNil(ECMIPCommand.parseConfig(Data(repeating: 0, count: 19)))
        XCTAssertNil(ECMIPCommand.parseConfig(Data(repeating: 0, count: 21)))
        XCTAssertNil(ECMIPCommand.parseConfig(Data()))
    }

    // MARK: - Response Scanner (shared with rename)

    private func getResponseFrame() -> Data {
        var payload = Data([0x00])
        guard let frame = ECMIPCommand.setAllFrame(ECMIPCommand.defaultConfig) else { return Data() }
        payload.append(frame.dropFirst(6).dropLast())
        return BLENameCommand.frame(cmd: 0xA3, payload: Array(payload))
    }

    func testScannerGetResponse() {
        var scanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
        let result = scanner.feed(getResponseFrame())
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertEqual(result.responses[0].cmd, 0xA3)
        XCTAssertEqual(result.responses[0].status, 0x00)
        XCTAssertEqual(ECMIPCommand.parseConfig(result.responses[0].payload), ECMIPCommand.defaultConfig)
        XCTAssertTrue(result.passthrough.isEmpty)
    }

    func testScannerSetResponse() {
        var scanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
        let result = scanner.feed(BLENameCommand.frame(cmd: 0xA2, payload: [0x00]))
        XCTAssertEqual(result.responses, [BLENameCommand.Response(cmd: 0xA2, status: 0x00, payload: Data())])
    }

    func testScannerRejectedResponse() {
        var scanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
        let result = scanner.feed(BLENameCommand.frame(cmd: 0xA2, payload: [0xE5]))
        XCTAssertEqual(result.responses[0].status, 0xE5)
    }

    func testScannerSplitAcrossFeeds() {
        let frame = getResponseFrame()
        var scanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
        let first = scanner.feed(frame.prefix(7))
        XCTAssertTrue(first.responses.isEmpty)
        let second = scanner.feed(frame.suffix(from: 7))
        XCTAssertEqual(second.responses.count, 1)
        XCTAssertEqual(ECMIPCommand.parseConfig(second.responses[0].payload), ECMIPCommand.defaultConfig)
    }

    func testScannerPassesThroughTunnelFrames() {
        var scanner = BLENameCommand.ResponseScanner(targetCommands: ECMIPCommand.responseCommands)
        let tunnelFrame = BLENameCommand.frame(cmd: 0x91, payload: [0x41, 0x00, 0x00, 0xDE, 0xAD])
        let mixed = tunnelFrame + getResponseFrame() + tunnelFrame
        let result = scanner.feed(mixed)
        XCTAssertEqual(result.responses.count, 1)
        XCTAssertEqual(result.passthrough, tunnelFrame + tunnelFrame)
    }
}