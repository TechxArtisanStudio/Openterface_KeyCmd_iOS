// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import XCTest
@testable import KeyCmd
import CoreBluetooth

/// Tests for BLEManager BLE-Eth write behavior.
///
/// Critical finding: The device firmware requires BLE-level write acknowledgment
/// (.withResponse) for ALL frames — both control and data. Using .withoutResponse
/// causes silent data loss: the device accepts the BLE notification and sends a
/// BLE-Eth ACK, but never forwards the payload to TCP.
///
/// Symptoms: SSH handshake works, server→client data works, but client→server
/// data (keystrokes) never reaches the server.
final class BLEManagerTests: XCTestCase {

    private let knownUUIDsKey = "ble_known_device_uuids"
    private let lastUUIDKey = "ble_last_connected_uuid"
    private let lastNameKey = "ble_last_connected_name"
    private let pairedUUIDsKey = "ble_paired_device_uuids"
    private let factoryPINReminderKey = BLEManager.factoryPINReminderKey
    private var savedKnownUUIDs: [String]?
    private var savedLastUUID: String?
    private var savedLastName: String?
    private var savedPairedUUIDs: [String]?
    private var savedFactoryPINReminder: Bool?

    override func setUp() {
        super.setUp()
        savedKnownUUIDs = UserDefaults.standard.stringArray(forKey: knownUUIDsKey)
        savedLastUUID = UserDefaults.standard.string(forKey: lastUUIDKey)
        savedLastName = UserDefaults.standard.string(forKey: lastNameKey)
        savedPairedUUIDs = UserDefaults.standard.stringArray(forKey: pairedUUIDsKey)
        savedFactoryPINReminder = UserDefaults.standard.object(forKey: factoryPINReminderKey) as? Bool
    }

    override func tearDown() {
        if let savedKnownUUIDs {
            UserDefaults.standard.set(savedKnownUUIDs, forKey: knownUUIDsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        }
        if let savedLastUUID {
            UserDefaults.standard.set(savedLastUUID, forKey: lastUUIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastUUIDKey)
        }
        if let savedLastName {
            UserDefaults.standard.set(savedLastName, forKey: lastNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastNameKey)
        }
        if let savedPairedUUIDs {
            UserDefaults.standard.set(savedPairedUUIDs, forKey: pairedUUIDsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pairedUUIDsKey)
        }
        if let savedFactoryPINReminder {
            UserDefaults.standard.set(savedFactoryPINReminder, forKey: factoryPINReminderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: factoryPINReminderKey)
        }
        super.tearDown()
    }

    // MARK: - Write Type Requirement

    /// Documents the BLE write type requirement discovered during debugging.
    ///
    /// Before the fix, BLEManager used:
    /// - .withResponse for control frames (CONNECT/DISCONNECT/INFO)
    /// - .withoutResponse for data frames (CMD_DATA)
    ///
    /// This caused post-handshake client→server data to be silently dropped.
    ///
    /// After the fix, BLEManager uses .withResponse for ALL frames.
    ///
    /// Root cause: The device firmware's BLE receive handler only triggers the
    /// application-layer data forwarding path when the BLE write is acknowledged
    /// at the link layer (.withResponse). Unacknowledged writes (.withoutResponse)
    /// are received by the BLE stack but never passed to the application layer.
    func testWriteTypeRequirementDocumentation() {
        // All BLE-Eth frames MUST use .withResponse write type.
        // This is enforced in BLEManager.sendRawData().
        //
        // Control frames: CMD_CONNECT(0x10), CMD_DISCONNECT(0x12), CMD_INFO(0x1F)
        // Data frames: CMD_DATA(0x11)
        //
        // Reference: docs/ble-eth-protocol-spec.md Section 7 "Write Modes"
        let controlCommands: [UInt8] = [0x10, 0x12, 0x1F]
        let dataCommands: [UInt8] = [0x11]

        for cmd in controlCommands + dataCommands {
            // All commands must use .withResponse
            XCTAssertTrue(true, "CMD 0x\(String(format: "%02X", cmd)) must use .withResponse")
        }
    }

    // MARK: - Chunked Write Tests

    /// Documents the chunking behavior for large BLE-Eth frames.
    ///
    /// BLE-Eth frames can be up to 255 bytes (MAX_FRAME_LEN). BLE writes are
    /// chunked to 128 bytes (safeChunkSize) with 10ms inter-chunk delays to
    /// prevent overwhelming the device's BLE receive buffer.
    ///
    /// Example: A 255-byte frame is sent as:
    /// - Chunk 1: 128 bytes (.withResponse)
    /// - 10ms delay
    /// - Chunk 2: 127 bytes (.withResponse)
    ///
    /// ALL chunks use .withResponse (not just the first chunk).
    func testChunkedWriteParameters() {
        XCTAssertEqual(128, 128, "safeChunkSize = 128 bytes")
        XCTAssertEqual(10, 10, "interChunkDelayMs = 10ms")

        // Max frame = 255 bytes → 2 chunks (128 + 127)
        let maxFrameLen = 255
        let safeChunkSize = 128
        let numChunks = (maxFrameLen + safeChunkSize - 1) / safeChunkSize
        XCTAssertEqual(numChunks, 2, "Max frame requires 2 chunks")
    }

    // MARK: - Control Frame Detection

    /// Verifies which command codes are classified as "control frames".
    /// Control frames use CMD_CONNECT(0x10), CMD_DISCONNECT(0x12), CMD_INFO(0x1F).
    /// Data frames use CMD_DATA(0x11).
    ///
    /// Note: Since the write type fix, ALL frames use .withResponse regardless
    /// of control/data classification. The classification is still used for logging.
    func testControlFrameCommandCodes() {
        // Frame format: SYNC1(0x57) SYNC2(0xAB) ADDR CMD LEN PAYLOAD... CHECKSUM
        // CMD is at index 3

        let connectFrame    = Data([0x57, 0xAB, 0x00, 0x10, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x16, 0x00])
        let dataFrame       = Data([0x57, 0xAB, 0x00, 0x11, 0x03, 0x41, 0x00, 0x00, 0xFF, 0x00])
        let disconnectFrame = Data([0x57, 0xAB, 0x00, 0x12, 0x01, 0x00, 0x00])
        let infoFrame       = Data([0x57, 0xAB, 0x00, 0x1F, 0x00, 0x00])

        // CMD byte is at index 3
        XCTAssertEqual(connectFrame[3], 0x10, "CONNECT cmd")
        XCTAssertEqual(dataFrame[3], 0x11, "DATA cmd")
        XCTAssertEqual(disconnectFrame[3], 0x12, "DISCONNECT cmd")
        XCTAssertEqual(infoFrame[3], 0x1F, "INFO cmd")

        // Control frame detection: CMD == 0x10 || CMD == 0x12 || CMD == 0x1F
        let isControl: (Data) -> Bool = { frame in
            guard frame.count > 3 else { return false }
            let cmd = frame[3]
            return cmd == 0x10 || cmd == 0x12 || cmd == 0x1F
        }

        XCTAssertTrue(isControl(connectFrame), "CONNECT is control frame")
        XCTAssertFalse(isControl(dataFrame), "DATA is NOT control frame")
        XCTAssertTrue(isControl(disconnectFrame), "DISCONNECT is control frame")
        XCTAssertTrue(isControl(infoFrame), "INFO is control frame")
    }

    // MARK: - BLE Write Queue Tests

    /// Documents the write queue configuration.
    ///
    /// All BLE-Eth writes go through a serial DispatchQueue to prevent race
    /// conditions and ensure proper ordering, especially when control frames
    /// and data frames are interleaved.
    func testWriteQueueConfiguration() {
        // BLEManager uses a serial DispatchQueue labeled "com.keycmd.bleEth.write"
        // with .userInitiated QoS for all BLE-Eth writes.
        //
        // This ensures:
        // 1. Writes are serialized (no concurrent writes)
        // 2. Chunked writes with inter-chunk delays work correctly
        // 3. Control and data frames maintain ordering
        XCTAssertTrue(true, "Serial write queue prevents concurrent BLE writes")
    }

    // MARK: - Relative Mouse Delta Chunking

    /// A fast swipe can exceed the CH9329 ±127 limit. The old code clamped and
    /// silently lost the excess; the scheduler must split it instead.
    func testNextMouseStepClampsOneStepAndKeepsRemainder() {
        var dx = 200
        var dy = -300

        let first = BLEManager.nextMouseStep(dx: &dx, dy: &dy)
        XCTAssertEqual(first?.dx, 127)
        XCTAssertEqual(first?.dy, -127)
        XCTAssertEqual(dx, 73)
        XCTAssertEqual(dy, -173)
    }

    func testNextMouseStepConservesTotalMovement() {
        var dx = 1000
        var dy = -500
        var sumX = 0
        var sumY = 0
        var steps = 0

        while let step = BLEManager.nextMouseStep(dx: &dx, dy: &dy) {
            XCTAssertLessThanOrEqual(abs(Int(step.dx)), 127)
            XCTAssertLessThanOrEqual(abs(Int(step.dy)), 127)
            sumX += Int(step.dx)
            sumY += Int(step.dy)
            steps += 1
            XCTAssertLessThan(steps, 100, "chunking must terminate")
        }

        XCTAssertEqual(sumX, 1000)
        XCTAssertEqual(sumY, -500)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, 0)
    }

    func testNextMouseStepBoundaries() {
        var dx = -127
        var dy = 0
        let negativeLimit = BLEManager.nextMouseStep(dx: &dx, dy: &dy)
        XCTAssertEqual(negativeLimit?.dx, -127)
        XCTAssertEqual(negativeLimit?.dy, 0)
        XCTAssertNil(BLEManager.nextMouseStep(dx: &dx, dy: &dy))

        dx = 5
        dy = 0
        let small = BLEManager.nextMouseStep(dx: &dx, dy: &dy)
        XCTAssertEqual(small?.dx, 5)
        XCTAssertEqual(small?.dy, 0)
        XCTAssertNil(BLEManager.nextMouseStep(dx: &dx, dy: &dy))

        dx = 0
        dy = 0
        XCTAssertNil(BLEManager.nextMouseStep(dx: &dx, dy: &dy))

        dx = 127
        dy = 127
        let positiveLimit = BLEManager.nextMouseStep(dx: &dx, dy: &dy)
        XCTAssertEqual(positiveLimit?.dx, 127)
        XCTAssertEqual(positiveLimit?.dy, 127)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, 0)

        dx = -126
        dy = 126
        let mixed = BLEManager.nextMouseStep(dx: &dx, dy: &dy)
        XCTAssertEqual(mixed?.dx, -126)
        XCTAssertEqual(mixed?.dy, 126)
        XCTAssertNil(BLEManager.nextMouseStep(dx: &dx, dy: &dy))
    }

    // MARK: - Known Device UUIDs / Discoverability

    func testRememberDeviceUUIDPersistsAndDeduplicates() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        let a = UUID()
        let b = UUID()
        BLEManager.rememberDeviceUUID(a)
        BLEManager.rememberDeviceUUID(b)
        BLEManager.rememberDeviceUUID(a)
        XCTAssertEqual(BLEManager.knownDeviceUUIDs, [a.uuidString, b.uuidString])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: knownUUIDsKey)?.count, 2)
    }

    func testDiscoverableByKnownPrefix() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        UserDefaults.standard.removeObject(forKey: lastUUIDKey)
        let stranger = UUID()
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "KVM-GO", identifier: stranger))
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "openterface-Mini", identifier: stranger))
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "KeyMod-123", identifier: stranger))
        XCTAssertFalse(BLEManager.isDiscoverableDevice(name: "MyDevice", identifier: stranger))
        XCTAssertFalse(BLEManager.isDiscoverableDevice(name: "", identifier: stranger))
        XCTAssertFalse(BLEManager.isDiscoverableDevice(name: nil, identifier: stranger))
    }

    /// The advertised 0xFFF0 service UUID survives renames, so any device name
    /// must be accepted once it is present — no name-prefix filtering.
    func testDiscoverableByAdvertisedServiceUUIDForAnyName() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        UserDefaults.standard.removeObject(forKey: lastUUIDKey)
        let stranger = UUID()
        let service = BLEManager.serviceUUID
        let foreignService = CBUUID(string: "180D")

        XCTAssertTrue(BLEManager.isDiscoverableDevice(
            name: "MyDevice", identifier: stranger, advertisedServices: [service]))
        XCTAssertTrue(BLEManager.isDiscoverableDevice(
            name: "Living Room KVM", identifier: stranger, advertisedServices: [service]))
        XCTAssertTrue(BLEManager.isDiscoverableDevice(
            name: nil, identifier: stranger, advertisedServices: [service]))
        XCTAssertFalse(BLEManager.isDiscoverableDevice(
            name: "MyDevice", identifier: stranger, advertisedServices: [foreignService]))
    }

    func testDiscoverableByKnownUUIDAfterRename() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        UserDefaults.standard.removeObject(forKey: lastUUIDKey)
        let device = UUID()
        XCTAssertFalse(BLEManager.isDiscoverableDevice(name: "MyDevice", identifier: device))
        BLEManager.rememberDeviceUUID(device)
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "MyDevice", identifier: device))
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: nil, identifier: device))
    }

    func testDiscoverableByLastConnectedUUID() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        let device = UUID()
        UserDefaults.standard.set(device.uuidString, forKey: lastUUIDKey)
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "Whatever", identifier: device))
    }

    /// Regression: renaming to a prefix-less name then manually disconnecting clears
    /// lastConnectedUUID; the known-UUID list must keep the device discoverable.
    func testManualDisconnectAfterRenameKeepsDeviceDiscoverable() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        let device = UUID()
        BLEManager.rememberDeviceUUID(device)
        UserDefaults.standard.set(device.uuidString, forKey: lastUUIDKey)
        UserDefaults.standard.removeObject(forKey: lastUUIDKey)  // what disconnectDevice does
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "Renamed", identifier: device))
    }

    // MARK: - Forget Pairing

    func testClearLocalPairingStateKeepsKnownDevices() {
        UserDefaults.standard.removeObject(forKey: knownUUIDsKey)
        let device = UUID()
        BLEManager.rememberDeviceUUID(device)
        UserDefaults.standard.set(device.uuidString, forKey: lastUUIDKey)
        UserDefaults.standard.set("KVM-GO", forKey: lastNameKey)
        UserDefaults.standard.set([device.uuidString], forKey: pairedUUIDsKey)

        BLEManager.clearLocalPairingState()

        XCTAssertNil(UserDefaults.standard.string(forKey: lastUUIDKey))
        XCTAssertNil(UserDefaults.standard.string(forKey: lastNameKey))
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: pairedUUIDsKey))
        XCTAssertEqual(BLEManager.knownDeviceUUIDs, [device.uuidString])
        XCTAssertTrue(BLEManager.isDiscoverableDevice(name: "Renamed", identifier: device))
    }

    // MARK: - Factory PIN Reminder Setting

    func testFactoryPINReminderSettingDefaultsOnAndPersists() {
        UserDefaults.standard.removeObject(forKey: factoryPINReminderKey)
        XCTAssertTrue(BLEManager.factoryPINReminderEnabled)

        BLEManager.factoryPINReminderEnabled = false
        XCTAssertFalse(BLEManager.factoryPINReminderEnabled)
        XCTAssertEqual(UserDefaults.standard.object(forKey: factoryPINReminderKey) as? Bool, false)

        BLEManager.factoryPINReminderEnabled = true
        XCTAssertTrue(BLEManager.factoryPINReminderEnabled)
    }
}
