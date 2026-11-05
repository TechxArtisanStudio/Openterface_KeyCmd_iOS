import XCTest
@testable import KeyCmd

final class MediaKeyPacketTests: XCTestCase {

    /// Verify media packet structure: 57 AB 00 03 04 + report_id + 3 bitmap bytes + checksum
    func testMediaPacketFormat() {
        // F10 = Mute: bitmap = (0x04, 0x00, 0x00)
        let packet = Keymod.buildMedia(reportId: 0x02, bitmap: (0x04, 0x00, 0x00))

        XCTAssertEqual(packet.count, 10, "Media packet should be 10 bytes")
        XCTAssertEqual(packet[0], 0x57, "Magic byte 1")
        XCTAssertEqual(packet[1], 0xAB, "Magic byte 2")
        XCTAssertEqual(packet[2], 0x00, "Reserved")
        XCTAssertEqual(packet[3], 0x03, "CMD = KB_MEDIA")
        XCTAssertEqual(packet[4], 0x04, "Length = 4 (report_id + 3 bitmap bytes)")
        XCTAssertEqual(packet[5], 0x02, "Report ID = Consumer Control")
        XCTAssertEqual(packet[6], 0x04, "Bitmap byte 1: Mute (bit 2)")
        XCTAssertEqual(packet[7], 0x00, "Bitmap byte 2")
        XCTAssertEqual(packet[8], 0x00, "Bitmap byte 3")

        // Verify checksum
        let checksum = packet[9]
        var sum: UInt8 = 0
        for i in 0..<9 {
            sum &+= packet[i]
        }
        XCTAssertEqual(checksum, sum, "Checksum should match")
    }

    /// Verify volume up packet
    func testVolumeUpPacket() {
        // F12 = Volume Increment: bitmap = (0x01, 0x00, 0x00)
        let packet = Keymod.buildMedia(reportId: 0x02, bitmap: (0x01, 0x00, 0x00))

        XCTAssertEqual(packet[6], 0x01, "Bitmap byte 1: Volume+ (bit 0)")
    }

    /// Verify play/pause packet
    func testPlayPausePacket() {
        // F8 = Play/Pause: bitmap = (0x08, 0x00, 0x00)
        let packet = Keymod.buildMedia(reportId: 0x02, bitmap: (0x08, 0x00, 0x00))

        XCTAssertEqual(packet[6], 0x08, "Bitmap byte 1: Play/Pause (bit 3)")
    }

    /// Verify release packet (all zeros)
    func testMediaReleasePacket() {
        let packet = Keymod.buildMedia(reportId: 0x02, bitmap: (0x00, 0x00, 0x00))

        XCTAssertEqual(packet[6], 0x00, "Release: bitmap byte 1 = 0")
        XCTAssertEqual(packet[7], 0x00, "Release: bitmap byte 2 = 0")
        XCTAssertEqual(packet[8], 0x00, "Release: bitmap byte 3 = 0")
    }
}
