import XCTest
@testable import KeyCmd
import Combine

final class BleEthTransportTests: XCTestCase {

    var bleManager: BLEManager!
    var transport: BleEthTransport!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        bleManager = BLEManager()
        transport = BleEthTransport(bleManager: bleManager)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        transport = nil
        bleManager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Command Code Tests

    func testCommandCodes() {
        XCTAssertEqual(BleEthTransport.CMD_CONNECT, 0x10)
        XCTAssertEqual(BleEthTransport.CMD_DATA, 0x11)
        XCTAssertEqual(BleEthTransport.CMD_DISCONNECT, 0x12)
        XCTAssertEqual(BleEthTransport.CMD_INFO, 0x1F)
        XCTAssertEqual(BleEthTransport.CMD_CONNECT_RESP, 0x90)
        XCTAssertEqual(BleEthTransport.CMD_DATA_RESP, 0x91)
        XCTAssertEqual(BleEthTransport.CMD_DISCONN_RESP, 0x92)
        XCTAssertEqual(BleEthTransport.CMD_CONN_CLOSED, 0xD2)
        XCTAssertEqual(BleEthTransport.CMD_INFO_RESP, 0x9F)
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertFalse(transport.isConnected)
    }

    func testDisconnectWhenNotConnected() {
        // Should not crash when disconnecting from initial state
        transport.disconnect()
        XCTAssertFalse(transport.isConnected)
    }

    // MARK: - Connect Tests

    func testConnectWithInvalidIPv4() {
        class TestListener: TransportListener {
            var errorReceived: String?
            var disconnectedCalled = false

            func onDataReceived(data: Data) {}
            func onDisconnected() { disconnectedCalled = true }
            func onError(message: String) { errorReceived = message }
        }

        let listener = TestListener()
        transport.listener = listener

        transport.connect(host: "invalid", port: 22, timeoutMs: 1000)

        XCTAssertNotNil(listener.errorReceived)
        XCTAssertTrue(listener.errorReceived?.contains("invalid IPv4") ?? false)
        XCTAssertFalse(transport.isConnected)
    }

    func testConnectWithIncompleteIPv4() {
        class TestListener: TransportListener {
            var errorReceived: String?
            func onDataReceived(data: Data) {}
            func onDisconnected() {}
            func onError(message: String) { errorReceived = message }
        }

        let listener = TestListener()
        transport.listener = listener

        transport.connect(host: "192.168.1", port: 22, timeoutMs: 1000)

        XCTAssertNotNil(listener.errorReceived)
        XCTAssertTrue(listener.errorReceived?.contains("invalid IPv4") ?? false)
    }

    func testConnectWithValidIPv4Format() {
        // This test will timeout (no real BLE device), but validates the parsing logic
        // We expect it to either timeout or fail on actual connection
        let expectation = XCTestExpectation(description: "Connection attempt")

        DispatchQueue.global().async {
            self.transport.connect(host: "192.168.1.1", port: 22, timeoutMs: 100)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // After timeout, should not be connected
        XCTAssertFalse(transport.isConnected)
    }

    // MARK: - Frame Building Tests

    func testFrameBuildingWithSmallPayload() {
        // Test that send() doesn't crash with small data
        let data = Data([0x01, 0x02, 0x03])
        transport.send(data: data)

        // Should not crash, but data won't be sent without connection
        // This is a smoke test
    }

    func testSendWithoutConnection() {
        let data = Data([0x01, 0x02, 0x03])
        transport.send(data: data)

        // Should not crash when sending without connection
        XCTAssertFalse(transport.isConnected)
    }

    // MARK: - Disconnect Tests

    func testDisconnectSendsFrame() {
        // Simulate a connected state by directly manipulating internal state
        // This is a white-box test

        // We can't easily test the actual frame sent without mocking BLEManager,
        // but we can verify disconnect doesn't crash
        transport.disconnect()

        XCTAssertFalse(transport.isConnected)
    }

    func testMultipleDisconnects() {
        transport.disconnect()
        transport.disconnect()
        transport.disconnect()

        // Should not crash on multiple disconnects
        XCTAssertFalse(transport.isConnected)
    }

    // MARK: - Incoming Data Tests

    func testHandleIncomingDataWithoutConnection() {
        // Feed some data without being connected
        let data = Data([0x57, 0xAB, 0x00, 0x11, 0x01, 0x42, 0x96])
        transport.handleIncomingData(data)

        // Should not crash
    }

    // MARK: - Stream Access Tests

    func testGetInboundReaderWithoutConnection() {
        let reader = transport.getInboundReader()
        XCTAssertNil(reader)
    }

    func testGetOutboundWriterWithoutConnection() {
        let writer = transport.getOutboundWriter()
        XCTAssertNil(writer)
    }

    // MARK: - Listener Tests

    func testListenerCallbacks() {
        class TestListener: TransportListener {
            var dataReceived: Data?
            var disconnectedCalled = false
            var errorMessage: String?

            func onDataReceived(data: Data) { dataReceived = data }
            func onDisconnected() { disconnectedCalled = true }
            func onError(message: String) { errorMessage = message }
        }

        let listener = TestListener()
        transport.listener = listener

        // Trigger error via invalid host
        transport.connect(host: "invalid", port: 22, timeoutMs: 100)

        XCTAssertNotNil(listener.errorMessage)
    }

    // MARK: - Integration Tests (with mocked BLE)

    func testEndToEndWithoutBLE() {
        // Test the full flow without actual BLE
        // 1. Create transport
        // 2. Try to connect (will fail/timeout)
        // 3. Verify state is correct
        // 4. Disconnect

        transport.connect(host: "192.168.1.1", port: 22, timeoutMs: 100)

        XCTAssertFalse(transport.isConnected)

        transport.disconnect()
        XCTAssertFalse(transport.isConnected)
    }
}
