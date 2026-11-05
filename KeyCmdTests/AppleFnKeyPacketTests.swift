import XCTest
@testable import KeyCmd

final class AppleFnKeyPacketTests: XCTestCase {

    /// Verify Apple function row packet structure: 57 AB 00 03 02 + report_id + bitmap + checksum
    func testAppleFnPacketFormat() {
        // F1 = Display Brightness Down: bitmap = 0x01
        let packet = Keymod.buildAppleFn(bitmap: 0x01)

        XCTAssertEqual(packet.count, 8, "Apple fn packet should be 8 bytes")
        XCTAssertEqual(packet[0], 0x57, "Magic byte 1")
        XCTAssertEqual(packet[1], 0xAB, "Magic byte 2")
        XCTAssertEqual(packet[2], 0x00, "Reserved")
        XCTAssertEqual(packet[3], 0x03, "CMD = KB_MEDIA")
        XCTAssertEqual(packet[4], 0x02, "Length = 2 (report_id + 1 bitmap byte)")
        XCTAssertEqual(packet[5], 0x03, "Report ID = Apple function row")
        XCTAssertEqual(packet[6], 0x01, "Bitmap: F1 brightness down (bit 0)")

        // Verify checksum
        let checksum = packet[7]
        var sum: UInt8 = 0
        for i in 0..<7 {
            sum &+= packet[i]
        }
        XCTAssertEqual(checksum, sum, "Checksum should match")
    }

    /// Verify F2 (brightness up) packet
    func testF2BrightnessUpPacket() {
        let packet = Keymod.buildAppleFn(bitmap: 0x02)
        XCTAssertEqual(packet[6], 0x02, "Bitmap: F2 brightness up (bit 1)")
    }

    /// Verify F3 (Mission Control) packet
    func testF3MissionControlPacket() {
        let packet = Keymod.buildAppleFn(bitmap: 0x04)
        XCTAssertEqual(packet[6], 0x04, "Bitmap: F3 Mission Control (bit 2)")
    }

    /// Verify F4 (Launchpad) packet
    func testF4LaunchpadPacket() {
        let packet = Keymod.buildAppleFn(bitmap: 0x08)
        XCTAssertEqual(packet[6], 0x08, "Bitmap: F4 Launchpad (bit 3)")
    }

    /// Verify release packet (bitmap = 0)
    func testAppleFnReleasePacket() {
        let packet = Keymod.buildAppleFn(bitmap: 0x00)
        XCTAssertEqual(packet[6], 0x00, "Release: bitmap = 0")
    }
}
