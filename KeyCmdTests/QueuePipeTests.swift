import XCTest
@testable import KeyMod

final class QueuePipeTests: XCTestCase {

    func testWriteAndRead() async {
        let pipe = QueuePipe(capacity: 16)

        // Write some data
        let testData = Data([0x01, 0x02, 0x03])
        pipe.output.write(testData)
        pipe.output.close()  // EOF

        // Read it back
        let chunk = await pipe.input.read()
        XCTAssertEqual(chunk, testData)

        // Next read should return nil (EOF)
        let eof = await pipe.input.read()
        XCTAssertNil(eof)
    }

    func testClose() async {
        let pipe = QueuePipe()
        pipe.close()

        let result = await pipe.input.read()
        XCTAssertNil(result)
    }
}
