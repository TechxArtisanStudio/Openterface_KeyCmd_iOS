import Foundation
import Combine
import SwiftUI

/// ViewModel for terminal screen. Manages connection state and coordinates:
///   - SSHClient (libssh2 via CSSH module)
///   - BleEthTransport (BLE-Eth frame protocol)
///   - TerminalEmulator (SwiftTerm rendering)
class TerminalViewModel: ObservableObject {

    // MARK: - Published State

    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var terminalTitle: String = "Terminal"
    @Published var statusMessage: String = ""

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected), (.connecting, .connecting), (.connected, .connected):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Components

    let emulator = TerminalEmulator()
    private let bleManager: BLEManager
    private var transport: BleEthTransport?
    private var bridge: POSIXSocketBridge?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(bleManager: BLEManager) {
        self.bleManager = bleManager

        // Observe emulator status changes
        emulator.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .disconnected:
                    self?.connectionStatus = .disconnected
                    self?.statusMessage = "Disconnected"
                case .connecting:
                    self?.connectionStatus = .connecting
                    self?.statusMessage = "Connecting..."
                case .connected:
                    self?.connectionStatus = .connected
                    self?.statusMessage = "Connected"
                case .error(let msg):
                    self?.connectionStatus = .error(msg)
                    self?.statusMessage = "Error: \(msg)"
                }
            }
        }
    }

    // MARK: - Public API

    /// Connect to remote host via BLE-Eth transport
    func connect(host: String, port: Int = 22, username: String, password: String) async {
        LogManager.shared.log("ViewModel: connect(\(host):\(port), user=\(username))", category: "Terminal", level: .info)
        guard !bleManager.connectedDevices.isEmpty else {
            await MainActor.run {
                statusMessage = "BLE not connected"
                connectionStatus = .error("BLE not connected")
            }
            LogManager.shared.log("ViewModel: BLE not connected — aborting", category: "Terminal", level: .error)
            return
        }

        await MainActor.run {
            connectionStatus = .connecting
            statusMessage = "Connecting to \(host):\(port)..."
        }

        // Create BLE-Eth transport
        let transport = BleEthTransport(bleManager: bleManager)
        self.transport = transport
        LogManager.shared.log("ViewModel: BleEthTransport created", category: "Terminal", level: .debug)

        // Create POSIX bridge and attach BEFORE transport.connect() so it receives the server banner
        do {
            let bridge = POSIXSocketBridge()
            try bridge.start(transport: transport)
            self.bridge = bridge
            LogManager.shared.log("ViewModel: POSIXSocketBridge created, libssh2Fd=\(bridge.libssh2Fd)", category: "Terminal", level: .info)
        } catch {
            LogManager.shared.log("ViewModel: bridge creation failed: \(error.localizedDescription)", category: "Terminal", level: .error)
            await MainActor.run {
                connectionStatus = .error("Bridge creation failed")
                statusMessage = "Bridge creation failed: \(error.localizedDescription)"
            }
            return
        }

        // Connect transport to remote host
        LogManager.shared.log("ViewModel: calling transport.connect()", category: "Terminal", level: .info)
        transport.connect(host: host, port: port, timeoutMs: 30000)
        LogManager.shared.log("ViewModel: transport.connect() returned, isConnected=\(transport.isConnected)", category: "Terminal", level: .info)

        // Wait for transport connection
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Check if transport connected
        guard transport.isConnected else {
            LogManager.shared.log("ViewModel: transport not connected after 1s wait — aborting", category: "Terminal", level: .error)
            await MainActor.run {
                connectionStatus = .error("BLE-Eth transport connection failed")
                statusMessage = "Transport connection failed"
            }
            return
        }

        // Connect SSH via emulator
        let profile = TerminalEmulator.ConnectionProfile(
            host: host,
            port: port,
            username: username,
            password: password
        )

        LogManager.shared.log("ViewModel: calling emulator.connect()", category: "Terminal", level: .info)
        do {
            try await emulator.connect(profile: profile, transport: transport, bridge: bridge!)
            LogManager.shared.log("ViewModel: emulator connected", category: "Terminal", level: .success)
        } catch {
            LogManager.shared.log("ViewModel: emulator.connect failed: \(error.localizedDescription)", category: "Terminal", level: .error)
            await MainActor.run {
                connectionStatus = .error(error.localizedDescription)
                statusMessage = "SSH error: \(error.localizedDescription)"
            }
        }
    }

    /// Disconnect from remote host
    func disconnect() {
        emulator.disconnect()
        transport?.disconnect()
        bridge?.stop()
        transport = nil
        bridge = nil

        DispatchQueue.main.async {
            self.connectionStatus = .disconnected
            self.statusMessage = "Disconnected"
        }
    }

    /// Send raw bytes to SSH
    func send(data: Data) {
        emulator.sshClient.write(data)
    }

    /// Send string to SSH
    func send(text: String) {
        emulator.sshClient.write(text)
    }

    /// Send special key sequences
    func sendSpecialKey(_ key: SpecialKey) {
        let data: Data
        switch key {
        case .enter:
            data = Data([0x0D]) // \r
        case .tab:
            data = Data([0x09]) // \t
        case .escape:
            data = Data([0x1B]) // \e
        case .backspace:
            data = Data([0x7F]) // backspace
        case .delete:
            data = Data([0x08]) // \b
        case .upArrow:
            data = Data([0x1B, 0x5B, 0x41]) // \e[A
        case .downArrow:
            data = Data([0x1B, 0x5B, 0x42]) // \e[B
        case .rightArrow:
            data = Data([0x1B, 0x5B, 0x43]) // \e[C
        case .leftArrow:
            data = Data([0x1B, 0x5B, 0x44]) // \e[D
        case .home:
            data = Data([0x1B, 0x5B, 0x48]) // \e[H
        case .end:
            data = Data([0x1B, 0x5B, 0x46]) // \e[F
        case .pageUp:
            data = Data([0x1B, 0x5B, 0x35, 0x7E]) // \e[5~
        case .pageDown:
            data = Data([0x1B, 0x5B, 0x36, 0x7E]) // \e[6~
        case .ctrlC:
            data = Data([0x03]) // Ctrl+C
        case .ctrlD:
            data = Data([0x04]) // Ctrl+D
        case .ctrlZ:
            data = Data([0x1A]) // Ctrl+Z
        }
        send(data: data)
    }

    enum SpecialKey {
        case enter, tab, escape, backspace, delete
        case upArrow, downArrow, rightArrow, leftArrow
        case home, end, pageUp, pageDown
        case ctrlC, ctrlD, ctrlZ
    }
}
