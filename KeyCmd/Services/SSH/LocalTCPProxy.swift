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

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("TCP Proxy listening on port \(self.port)")
            case .failed(let error):
                print("TCP Proxy listener failed: \(error)")
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        inboundTask?.cancel()
        inboundTask = nil

        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("TCP connection ready")
                self?.bridgeConnection(connection)
            case .failed(let error):
                print("TCP connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func bridgeConnection(_ connection: NWConnection) {
        guard let transport = transport else { return }

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
