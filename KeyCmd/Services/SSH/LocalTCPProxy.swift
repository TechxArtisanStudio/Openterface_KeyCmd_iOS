import Foundation
import Network

/// Local TCP proxy that bridges TCP connections to BLE-Eth transport.
/// This allows libssh2 to connect via standard POSIX sockets while traffic flows through BLE.
///
/// Pattern:
///   libssh2 → NWConnection (localhost TCP) → LocalTCPProxy → BleEthTransport → BLE
class LocalTCPProxy {

    let port: UInt16
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var transport: BleEthTransport?

    /// Async task that pumps BLE → TCP direction
    private var inboundTask: Task<Void, Never>?

    init(port: UInt16 = 12345) {
        self.port = port
    }

    func start(transport: BleEthTransport) throws {
        self.transport = transport
        print("[LocalTCPProxy] start() called, transport isConnected=\(transport.isConnected)")

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[LocalTCPProxy] listening on port \(self.port)")
            case .failed(let error):
                print("[LocalTCPProxy] listener failed: \(error)")
            case .setup:
                print("[LocalTCPProxy] setup")
            case .cancelled:
                print("[LocalTCPProxy] cancelled")
            case .waiting(let error):
                print("[LocalTCPProxy] waiting: \(error)")
            @unknown default:
                print("[LocalTCPProxy] unknown state")
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            print("[LocalTCPProxy] new incoming connection")
            self?.handleNewConnection(connection)
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        print("[LocalTCPProxy] stop()")
        inboundTask?.cancel()
        inboundTask = nil

        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        print("[LocalTCPProxy] handleNewConnection, total=\(connections.count)")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[LocalTCPProxy] TCP connection ready — bridging")
                self?.bridgeConnection(connection)
            case .failed(let error):
                print("[LocalTCPProxy] TCP connection failed: \(error)")
            case .setup:
                print("[LocalTCPProxy] TCP setup")
            case .preparing:
                print("[LocalTCPProxy] TCP preparing")
            case .cancelled:
                print("[LocalTCPProxy] TCP cancelled")
            case .waiting(let error):
                print("[LocalTCPProxy] TCP waiting: \(error)")
            @unknown default:
                print("[LocalTCPProxy] TCP unknown state")
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func bridgeConnection(_ connection: NWConnection) {
        guard let transport = transport else {
            print("[LocalTCPProxy] bridgeConnection: transport is nil")
            return
        }
        print("[LocalTCPProxy] bridgeConnection starting (TCP↔BLE bidirectional)")

        // === TCP → BLE direction ===
        // libssh2 writes to NWConnection; we read and forward to transport.send(...)
        func receiveFromTCP() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    transport.send(data: data)
                }
                if !isComplete && error == nil {
                    receiveFromTCP()
                }
            }
        }
        receiveFromTCP()

        // === BLE → TCP direction ===
        // BleEthTransport delivers incoming data via getInboundReader() (async stream).
        // We pump the stream and send each chunk through the TCP connection.
        guard let reader = transport.getInboundReader() else { return }

        // Cancel any previous inbound pump (new connection replaces old)
        inboundTask?.cancel()
        inboundTask = Task { [weak connection] in
            while !Task.isCancelled {
                if let chunk = await reader.read() {
                    connection?.send(content: chunk, completion: .contentProcessed { error in
                        if let error = error {
                            print("Failed to send to TCP: \(error)")
                        }
                    })
                } else {
                    // EOF: remote closed the BLE-Eth tunnel
                    connection?.cancel()
                    break
                }
            }
        }
    }
}
