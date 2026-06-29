import XCTest
@testable import KeyMod

final class FrameParserTests: XCTestCase {

    func testParseValidFrame() {
        let parser = FrameParser()
        var frames: [FrameParser.ParsedFrame] = []
        parser.onFrameParsed = { frame in
            frames.append(frame)
        }

        // Build a valid CONNECT frame: 57 AB 00 10 06 C0 A8 01 05 00 16 <checksum>
        var frame = Data([0x57, 0xAB, 0x00, 0x10, 0x06, 0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16])
        let checksum = frame.reduce(UInt8(0)) { $0 &+ $1 }
        frame.append(checksum)

        parser.feed(data: frame)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].addr, 0x00)
        XCTAssertEqual(frames[0].cmd, 0x10)
        XCTAssertEqual(frames[0].payload, Data([0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16]))
    }

    func testInvalidChecksum() {
        let parser = FrameParser()
        var frames: [FrameParser.ParsedFrame] = []
        parser.onFrameParsed = { frame in
            frames.append(frame)
        }

        // Invalid checksum
        let frame = Data([0x57, 0xAB, 0x00, 0x10, 0x06, 0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16, 0xFF])
        parser.feed(data: frame)

        XCTAssertEqual(frames.count, 0)
    }

    func testMultipleFrames() {
        let parser = FrameParser()
        var frames: [FrameParser.ParsedFrame] = []
        parser.onFrameParsed = { frame in
            frames.append(frame)
        }

        // Frame 1
        var frame1 = Data([0x57, 0xAB, 0x00, 0x10, 0x02, 0x01, 0x02])
        frame1.append(frame1.reduce(UInt8(0)) { $0 &+ $1 })

        // Frame 2
        var frame2 = Data([0x57, 0xAB, 0x00, 0x11, 0x03, 0x0A, 0x0B, 0x0C])
        frame2.append(frame2.reduce(UInt8(0)) { $0 &+ $1 })

        parser.feed(data: frame1 + frame2)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].cmd, 0x10)
        XCTAssertEqual(frames[1].cmd, 0x11)
    }

    func testSyncRecovery() {
        let parser = FrameParser()
        var frames: [FrameParser.ParsedFrame] = []
        parser.onFrameParsed = { frame in
            frames.append(frame)
        }

        // Garbage + valid frame
        var data = Data([0xFF, 0xAA, 0x57, 0x57, 0xAB, 0x00, 0x10, 0x01, 0x42])
        data.append(data.reduce(UInt8(0)) { $0 &+ $1 })

        parser.feed(data: data)

        XCTAssertEqual(frames.count, 1)
    }
}
