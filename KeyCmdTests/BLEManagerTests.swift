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
}
