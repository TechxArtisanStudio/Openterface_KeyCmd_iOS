import XCTest
@testable import KeyMod

final class DataReassemblerTests: XCTestCase {

    func testSingleFragment() {
        let reassembler = DataReassembler()
        var results: [DataReassembler.ReassembledData] = []
        reassembler.onReassembled = { data in
            results.append(data)
        }

        // Single fragment: flags=0x41 (FIRST + count=1), seq=0, connId=5
        let payload = Data([0x41, 0x00, 0x05, 0xAA, 0xBB, 0xCC])
        reassembler.feed(payload: payload)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].connId, 0x05)
        XCTAssertEqual(results[0].data, Data([0xAA, 0xBB, 0xCC]))
    }

    func testMultipleFragments() {
        let reassembler = DataReassembler()
        var results: [DataReassembler.ReassembledData] = []
        reassembler.onReassembled = { data in
            results.append(data)
        }

        // Fragment 1: flags=0xC2 (FIRST+MORE+count=2), seq=0, connId=3
        let frag1 = Data([0xC2, 0x00, 0x03, 0x11, 0x22])
        reassembler.feed(payload: frag1)
        XCTAssertEqual(results.count, 0)  // Not complete yet

        // Fragment 2: flags=0x82 (MORE+count=2), seq=1, connId=3
        let frag2 = Data([0x82, 0x01, 0x03, 0x33, 0x44])
        reassembler.feed(payload: frag2)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].data, Data([0x11, 0x22, 0x33, 0x44]))
    }

    func testOutOfOrderFragments() {
        let reassembler = DataReassembler()
        var results: [DataReassembler.ReassembledData] = []
        reassembler.onReassembled = { data in
            results.append(data)
        }

        // Fragment 1: FIRST, seq=0
        let frag1 = Data([0xC2, 0x00, 0x01, 0xAA])
        reassembler.feed(payload: frag1)

        // Fragment 3: skip seq=1, go to seq=2 → out of order
        let frag3 = Data([0x02, 0x02, 0x01, 0xCC])
        reassembler.feed(payload: frag3)

        // Should discard entire reassembly
        XCTAssertEqual(results.count, 0)
    }
}
