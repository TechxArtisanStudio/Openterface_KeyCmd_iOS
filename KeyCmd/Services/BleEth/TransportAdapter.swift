import Foundation

/// Abstract interface for raw TCP byte streaming over BLE-Eth or USB ECM.
/// Ported from Android TransportAdapter.java.
protocol TransportAdapter: AnyObject {

    /// Listener for transport events.
    var listener: TransportListener? { get set }

    /// Connect to the remote host:port over the transport.
    /// - Parameters:
    ///   - host: IPv4 address string (e.g. "192.168.1.5")
    ///   - port: TCP port number
    ///   - timeoutMs: connection timeout in milliseconds
    func connect(host: String, port: Int, timeoutMs: Int)

    /// Send raw bytes over the transport.
    func send(data: Data)

    /// Disconnect and tear down.
    func disconnect()

    /// Whether the transport is currently connected and operational.
    var isConnected: Bool { get }
}

/// Callbacks for transport state changes.
protocol TransportListener: AnyObject {
    /// Called when data arrives from the remote side.
    func onDataReceived(data: Data)

    /// Called when the transport disconnects (intentional or unexpected).
    func onDisconnected()

    /// Called when an error occurs.
    func onError(message: String)
}