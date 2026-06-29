import XCTest
@testable import KeyCmd
import Combine

final class TerminalViewModelTests: XCTestCase {

    var bleManager: BLEManager!
    var viewModel: TerminalViewModel!

    override func setUp() {
        super.setUp()
        bleManager = BLEManager()
        viewModel = TerminalViewModel(bleManager: bleManager)
    }

    override func tearDown() {
        viewModel = nil
        bleManager = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
        XCTAssertEqual(viewModel.terminalTitle, "Terminal")
        XCTAssertEqual(viewModel.statusMessage, "")
    }

    // MARK: - Connection Status Tests

    func testConnectionStatusEquality() {
        XCTAssertEqual(TerminalViewModel.ConnectionStatus.disconnected, .disconnected)
        XCTAssertEqual(TerminalViewModel.ConnectionStatus.connecting, .connecting)
        XCTAssertEqual(TerminalViewModel.ConnectionStatus.connected, .connected)
        XCTAssertEqual(TerminalViewModel.ConnectionStatus.error("test"), .error("test"))
        XCTAssertNotEqual(TerminalViewModel.ConnectionStatus.error("test1"), .error("test2"))
        XCTAssertNotEqual(TerminalViewModel.ConnectionStatus.disconnected, .connected)
    }

    // MARK: - Special Key Tests

    func testSpecialKeyEnter() {
        viewModel.sendSpecialKey(.enter)
    }

    func testSpecialKeyTab() {
        viewModel.sendSpecialKey(.tab)
    }

    func testSpecialKeyEscape() {
        viewModel.sendSpecialKey(.escape)
    }

    func testSpecialKeyBackspace() {
        viewModel.sendSpecialKey(.backspace)
    }

    func testSpecialKeyDelete() {
        viewModel.sendSpecialKey(.delete)
    }

    func testSpecialKeyArrowKeys() {
        viewModel.sendSpecialKey(.upArrow)
        viewModel.sendSpecialKey(.downArrow)
        viewModel.sendSpecialKey(.leftArrow)
        viewModel.sendSpecialKey(.rightArrow)
    }

    func testSpecialKeyNavigationKeys() {
        viewModel.sendSpecialKey(.home)
        viewModel.sendSpecialKey(.end)
        viewModel.sendSpecialKey(.pageUp)
        viewModel.sendSpecialKey(.pageDown)
    }

    func testSpecialKeyControlKeys() {
        viewModel.sendSpecialKey(.ctrlC)
        viewModel.sendSpecialKey(.ctrlD)
        viewModel.sendSpecialKey(.ctrlZ)
    }

    // MARK: - Send Data Tests

    func testSendRawData() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        viewModel.send(data: data)
    }

    func testSendText() {
        viewModel.send(text: "Hello, World!")
    }

    func testSendEmptyData() {
        viewModel.send(data: Data())
    }

    func testSendEmptyText() {
        viewModel.send(text: "")
    }

    // MARK: - Connection Tests

    func testConnectWithoutBLE() {
        let expectation = XCTestExpectation(description: "Connect without BLE")

        Task {
            await viewModel.connect(host: "192.168.1.1", port: 22, username: "user", password: "pass")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Should fail because BLE is not connected
        if case .error(let msg) = viewModel.connectionStatus {
            XCTAssertTrue(msg.contains("BLE not connected"))
        } else {
            XCTFail("Expected .error state, got \(viewModel.connectionStatus)")
        }
    }

    // MARK: - Disconnect Tests

    func testDisconnectWhenNotConnected() {
        let expectation = XCTestExpectation(description: "Disconnect updates state")

        // Subscribe to connectionStatus changes
        let cancellable = viewModel.$connectionStatus
            .dropFirst() // skip initial value
            .sink { status in
                if status == .disconnected {
                    expectation.fulfill()
                }
            }

        viewModel.disconnect()

        wait(for: [expectation], timeout: 0.5)
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
        XCTAssertEqual(viewModel.statusMessage, "Disconnected")
        XCTAssertNotNil(cancellable)
    }

    func testDisconnectWhenConnected() {
        // Simulate connected state
        viewModel.connectionStatus = .connected
        viewModel.statusMessage = "Connected"

        let expectation = XCTestExpectation(description: "Disconnect updates state")

        // Subscribe to connectionStatus changes
        let cancellable = viewModel.$connectionStatus
            .sink { status in
                if status == .disconnected {
                    expectation.fulfill()
                }
            }

        viewModel.disconnect()

        wait(for: [expectation], timeout: 0.5)
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
        XCTAssertEqual(viewModel.statusMessage, "Disconnected")
        XCTAssertNotNil(cancellable)
    }

    func testMultipleDisconnects() {
        viewModel.disconnect()
        viewModel.disconnect()
        viewModel.disconnect()

        // Should not crash
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
    }

    // MARK: - Emulator Access Tests

    func testEmulatorAccess() {
        XCTAssertNotNil(viewModel.emulator)
    }

    func testEmulatorInitialState() {
        let status = viewModel.emulator.status
        if case .disconnected = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .disconnected, got \(status)")
        }
    }

    // MARK: - Status Callback Tests

    func testStatusChangeCallback() {
        // Simulate onStatusChanged via emulator
        // Use the ViewModel's emulator reference to trigger status changes
        let expectation = XCTestExpectation(description: "Connection status changed to disconnected")

        // Create a publisher for connectionStatus changes
        let cancellable = viewModel.$connectionStatus
            .dropFirst() // skip initial value
            .sink { status in
                if status == .disconnected {
                    expectation.fulfill()
                }
            }

        // Trigger via disconnect
        viewModel.disconnect()

        wait(for: [expectation], timeout: 0.5)
        XCTAssertNotNil(cancellable)
    }

    // MARK: - Thread Safety Tests

    func testConcurrentDisconnects() {
        let expectation = XCTestExpectation(description: "Concurrent disconnects")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                self.viewModel.disconnect()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
    }

    func testConcurrentStatusReads() {
        let expectation = XCTestExpectation(description: "Concurrent status reads")
        expectation.expectedFulfillmentCount = 100

        for _ in 0..<100 {
            DispatchQueue.global().async {
                _ = self.viewModel.connectionStatus
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }
}