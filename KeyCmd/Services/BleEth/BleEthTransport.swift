import Foundation
import Combine

/// BLE-Eth transport implementation.
/// Ports Android's BleEthTransport.java — tunnels TCP traffic over BLE GATT
/// using the custom frame protocol defined in FrameParser.
///
/// Connects to a remote host via the Openterface device's BLE-Eth tunnel.
/// The device acts as a BLE-to-TCP bridge.
final class BleEthTransport: TransportAdapter {

    // MARK: - Command Codes

    static let CMD_CONNECT      = UInt8(0x10)
    static let CMD_DATA         = UInt8(0x11)
    static let CMD_DISCONNECT   = UInt8(0x12)
    static let CMD_INFO         = UInt8(0x1F)
    static let CMD_CONNECT_RESP   = UInt8(0x90)
    static let CMD_DATA_RESP     = UInt8(0x91)
    static let CMD_DISCONN_RESP  = UInt8(0x92)
    static let CMD_CONN_CLOSED   = UInt8(0xD2)
    static let CMD_INFO_RESP     = UInt8(0x9F)

    // MARK: - TransportAdapter

    weak var listener: TransportListener?

    var isConnected: Bool {
        stateLock.withLock { running && connId >= 0 }
    }

    // MARK: - State

    private let bleManager: BLEManager
    private let logger = LogManager.shared
    private let frameParser = FrameParser()
    private let dataReassembler = DataReassembler()

    private let stateLock = NSLock()
    private var connId: Int = -1
    private var running: Bool = false
    private var inputPipeClosed: Bool = false

    /// Pipe for SSH → BLE direction (app sends data to remote)
    private var outboundPipe: QueuePipe?

    /// Pipe for BLE → SSH direction (remote sends data to app)
    private var inboundPipe: QueuePipe?

    /// Pending connection state (used during connect handshake)
    private var pendingConnId: UInt8 = 0
    private var pendingConnStatus: UInt8 = 0
    private var connectSemaphore: DispatchSemaphore?

    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Background queue for output reader task
    private var outputReaderTask: Task<Void, Never>?

    // MARK: - Init

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
        setupFrameHandler()
    }

    deinit {
        disconnect()
    }

    // MARK: - TransportAdapter Methods

    func connect(host: String, port: Int, timeoutMs: Int) {
        logger.log("BLE-Eth: connect(\(host):\(port), timeout=\(timeoutMs)ms)", category: "BLE-Eth", level: .info)
        // 1. Reset state
        stateLock.lock()
        closePipes()
        inputPipeClosed = false
        running = false
        connId = -1
        stateLock.unlock()

        // 2. Clear any stale connection state on the device
        // Send DISCONNECT for common stale connIds (255 and 0) to ensure device releases orphaned connections
        // This prevents 0xE7 errors when device has stale state from previous sessions
        logger.log("BLE-Eth: sending cleanup DISCONNECT for stale connIds", category: "BLE-Eth", level: .info)
        for staleConnId in [UInt8(255), UInt8(0)] {
            let cleanupPayload = Data([staleConnId])
            sendFrame(addr: 0x00, cmd: Self.CMD_DISCONNECT, payload: cleanupPayload)
            // 50ms delay between DISCONNECT frames to avoid overwhelming firmware
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Wait for firmware to process DISCONNECT frames and send responses
        Thread.sleep(forTimeInterval: 0.5)

        // 2. Create pipes
        outboundPipe = QueuePipe(capacity: 256)
        inboundPipe = QueuePipe(capacity: 256)

        // 3. Start output reader — polls outbound pipe and sends fragments via BLE
        outputReaderTask = Task { [weak self] in
            await self?.runOutputReader()
        }

        // 4. Build and send CONNECT frame
        let semaphore = DispatchSemaphore(value: 0)
        self.connectSemaphore = semaphore

        guard let hostData = host.data(using: .utf8) else {
            listener?.onError(message: "BLE-Eth: invalid host")
            return
        }
        _ = hostData  // We parse the IP manually below

        // Parse IPv4 address
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let ip0 = UInt8(parts[0]),
              let ip1 = UInt8(parts[1]),
              let ip2 = UInt8(parts[2]),
              let ip3 = UInt8(parts[3]) else {
            listener?.onError(message: "BLE-Eth: invalid IPv4 address: \(host)")
            return
        }

        let portHi = UInt8((port >> 8) & 0xFF)
        let portLo = UInt8(port & 0xFF)

        var payload = Data([ip0, ip1, ip2, ip3, portHi, portLo])
        logger.log("BLE-Eth: sending CONNECT frame payloadLen=\(payload.count)", category: "BLE-Eth", level: .debug)
        sendFrame(addr: 0x00, cmd: Self.CMD_CONNECT, payload: payload)

        // 5. Wait for CONNECT_RESP or timeout
        logger.log("BLE-Eth: waiting for CONNECT_RESP (semaphore)", category: "BLE-Eth", level: .debug)
        let result = semaphore.wait(timeout: .now() + .milliseconds(timeoutMs))
        if result == .timedOut {
            logger.log("BLE-Eth CONNECT timed out after \(timeoutMs)ms", category: "BLE-Eth", level: .error)
            listener?.onError(message: "BLE-Eth CONNECT timed out")
            return
        }
        logger.log("BLE-Eth: got CONNECT_RESP pendingConnId=\(pendingConnId) pendingConnStatus=\(pendingConnStatus)", category: "BLE-Eth", level: .debug)

        // 6. Check response status
        if pendingConnStatus != 0x00 {
            let statusHex = String(format: "0x%02X", pendingConnStatus)
            logger.log("BLE-Eth CONNECT failed: status=\(statusHex) connId=\(pendingConnId) — sending DISCONNECT to clear stale state", category: "BLE-Eth", level: .error)

            // Send DISCONNECT for the rejected connId to clear device's stale state
            // This prevents 0xE7 on retry (device thinks connId is still allocated)
            let payload = Data([pendingConnId])
            sendFrame(addr: 0x00, cmd: Self.CMD_DISCONNECT, payload: payload)

            listener?.onError(message: "BLE-Eth CONNECT failed: status=\(statusHex)")
            return
        }

        // 7. Connected
        stateLock.lock()
        connId = Int(pendingConnId)
        running = true
        stateLock.unlock()

        logger.log("BLE-Eth connected: connId=\(pendingConnId)", category: "BLE-Eth", level: .success)
    }

    func send(data: Data) {
        guard let pipe = outboundPipe else {
            logger.log("BLE-Eth: send() dropped — outboundPipe is nil", category: "BLE-Eth", level: .warning)
            return
        }
        logger.log("BLE-Eth: send() enqueuing \(data.count) bytes", category: "BLE-Eth", level: .debug)
        pipe.output.write(data)
    }

    func disconnect() {
        logger.log("BLE-Eth: disconnect() called", category: "BLE-Eth", level: .info)
        // Cancel BLE subscription FIRST to stop receiving new notifications
        cancellables.removeAll()

        stateLock.lock()

        // Already fully closed?
        if !running && connId < 0 && inputPipeClosed {
            stateLock.unlock()
            logger.log("BLE-Eth: disconnect() no-op (already closed)", category: "BLE-Eth", level: .debug)
            return
        }

        running = false
        let disconnectConnId = connId
        connId = -1
        inputPipeClosed = true
        closePipes()
        stateLock.unlock()

        // Cancel output reader
        outputReaderTask?.cancel()
        outputReaderTask = nil

        // Send DISCONNECT frame if we had a valid connection
        if disconnectConnId >= 0 {
            let payload = Data([UInt8(disconnectConnId)])
            sendFrame(addr: 0x00, cmd: Self.CMD_DISCONNECT, payload: payload)
        }

        listener?.onDisconnected()
        logger.log("BLE-Eth disconnected", category: "BLE-Eth", level: .warning)
    }

    // MARK: - Public: Incoming BLE Data

    /// Entry point for raw BLE notification bytes.
    /// Call this from BLEManager's didUpdateValueFor delegate.
    func handleIncomingData(_ data: Data) {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.log("BLE-Eth: incoming raw \(data.count) bytes: \(hex)", category: "BLE-Eth", level: .debug)
        frameParser.feed(data: data)
    }

    // MARK: - Public: Stream Access

    /// Get the inbound pipe reader — SSH client reads from here.
    func getInboundReader() -> QueuePipe.Reader? {
        return inboundPipe?.input
    }

    /// Get the outbound pipe writer — SSH client writes to here.
    func getOutboundWriter() -> QueuePipe.Writer? {
        return outboundPipe?.output
    }

    // MARK: - Private: Setup

    private func setupFrameHandler() {
        // Wire up frame parser → handle parsed frames
        frameParser.onFrameParsed = { [weak self] frame in
            self?.handleParsedFrame(frame)
        }

        // Wire up data reassembler → deliver reassembled data to inbound pipe
        dataReassembler.onReassembled = { [weak self] reassembled in
            self?.deliverReassembledData(reassembled)
        }

        // Subscribe to BLEManager's raw data subject
        bleManager.rawDataSubject
            .sink { [weak self] data in
                self?.handleIncomingData(data)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private: Frame Handling

    private func handleParsedFrame(_ frame: FrameParser.ParsedFrame) {
        logger.log("BLE-Eth: frame cmd=0x\(String(format: "%02X", frame.cmd)) payloadLen=\(frame.payload.count)", category: "BLE-Eth", level: .debug)
        switch frame.cmd {
        case Self.CMD_CONNECT_RESP:
            logger.log("BLE-Eth: handling CONNECT_RESP payloadLen=\(frame.payload.count)", category: "BLE-Eth", level: .debug)
            handleConnectResponse(frame.payload)

        case Self.CMD_DATA_RESP:
            handleDataResponse(frame.payload)

        case Self.CMD_DISCONN_RESP, Self.CMD_CONN_CLOSED:
            logger.log("BLE-Eth: handling remote close cmd=0x\(String(format: "0x%02X", frame.cmd))", category: "BLE-Eth", level: .warning)
            handleRemoteClose(frame.payload)

        case Self.CMD_INFO_RESP:
            logger.log("BLE-Eth INFO response received", category: "BLE-Eth")

        default:
            logger.log("BLE-Eth unknown cmd: 0x\(String(format: "%02X", frame.cmd))", category: "BLE-Eth", level: .warning)
        }
    }

    private func handleConnectResponse(_ payload: Data) {
        guard payload.count >= 2 else { return }
        pendingConnId = payload[0]
        pendingConnStatus = payload[1]
        connectSemaphore?.signal()
    }

    private func handleDataResponse(_ payload: Data) {
        let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        // Match Android: filter ACKs before feeding to reassembler
        // ACKs are status frames (payload[0]==0x00 or 0xE0-0xEF), not data fragments
        if looksLikeDataAck(payload) {
            let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
            logger.log("BLE-Eth: DATA ACK — ignored (hex=\(hex))", category: "BLE-Eth", level: .debug)
            return
        }
        logger.log("BLE-Eth: DATA_RESP payloadLen=\(payload.count) hex=\(hex)", category: "BLE-Eth", level: .debug)
        dataReassembler.feed(payload: payload)
    }

    private func looksLikeDataAck(_ payload: Data) -> Bool {
        guard !payload.isEmpty else { return false }
        let first = payload[0]
        if first == 0x00 { return true }
        if (first & 0xF0) == 0xE0 { return true }
        return false
    }

    private func handleRemoteClose(_ payload: Data) {
        guard !payload.isEmpty else { return }
        let closedConnId = Int(payload[0])

        stateLock.lock()
        let shouldClose = (closedConnId == connId)
        // Connecting: semaphore exists but connection not yet established
        let isConnecting = (connectSemaphore != nil && !running && connId < 0)
        stateLock.unlock()

        if shouldClose {
            logger.log("BLE-Eth: remote closed connId=\(closedConnId)", category: "BLE-Eth")
            disconnect()
        } else if isConnecting {
            // Device rejected connection - signal connect semaphore with error
            logger.log("BLE-Eth: device rejected connection with CMD_DISCONN_RESP", category: "BLE-Eth", level: .error)
            pendingConnStatus = 0xE7 // Generic rejection status
            connectSemaphore?.signal()
        }
    }

    // MARK: - Private: Deliver Reassembled Data

    private func deliverReassembledData(_ reassembled: DataReassembler.ReassembledData) {
        // Verify this is for our connection
        stateLock.lock()
        let ourConnId = connId
        let isRunning = running
        stateLock.unlock()

        let shouldDeliver = isRunning && ourConnId >= 0 && Int(reassembled.connId) == ourConnId
        logger.log("BLE-Eth: deliver reassembled dataLen=\(reassembled.data.count) dataConnId=\(reassembled.connId) ourConnId=\(ourConnId) running=\(isRunning) → deliver=\(shouldDeliver)",
                   category: "BLE-Eth", level: .debug)

        guard shouldDeliver else { return }

        // Deliver directly to listener (bridge writes to libssh2's socket fd)
        listener?.onDataReceived(data: reassembled.data)
    }

    // MARK: - Private: Output Reader

    /// Background task that reads from outbound pipe and sends fragmented DATA frames.
    private func runOutputReader() async {
        logger.log("BLE-Eth: output reader started", category: "BLE-Eth", level: .info)
        guard let pipe = outboundPipe else {
            logger.log("BLE-Eth: output reader — no outboundPipe", category: "BLE-Eth", level: .error)
            return
        }
        let reader = pipe.input

        while !Task.isCancelled {
            // Wait until connected
            while !Task.isCancelled {
                stateLock.lock()
                let ready = running && connId >= 0
                stateLock.unlock()
                if ready { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            guard !Task.isCancelled else { break }

            // Read next chunk from SSH output
            let chunk = await reader.read()
            guard let data = chunk else {
                // EOF — pipe closed
                logger.log("BLE-Eth: output reader EOF", category: "BLE-Eth", level: .info)
                break
            }

            logger.log("BLE-Eth: output reader got \(data.count) bytes → sendFragmented", category: "BLE-Eth", level: .debug)
            // Fragment and send
            sendFragmented(data: data)
        }
        logger.log("BLE-Eth: output reader exited", category: "BLE-Eth", level: .info)
    }

    // MARK: - Private: Frame Building & Sending

    /// Send data as fragmented DATA frames (if needed).
    private func sendFragmented(data: Data) {
        let maxFragData = DataReassembler.MAX_FRAG_DATA  // 246

        guard connId >= 0 else { return }
        let cId = UInt8(connId)

        if data.count <= maxFragData {
            // Single fragment — match device format: FRAG_FIRST | count=1 (0x41)
            // Device doesn't normalize count=0→1 like our reassembler does
            let flags: UInt8 = DataReassembler.FRAG_FIRST | 0x01  // 0x41
            var payload = Data([flags, 0x00, cId])  // flags, seq=0, connId
            payload.append(data)
            let payloadHex = payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            logger.log("BLE-Eth: single frag flags=0x\(String(format: "%02X", flags)) seq=0 connId=\(cId) dataLen=\(data.count) payload(\(payload.count))=\(payloadHex)", category: "BLE-Eth", level: .debug)
            sendFrame(addr: 0x00, cmd: Self.CMD_DATA, payload: payload)
        } else {
            // Multiple fragments
            let totalFrags = (data.count + maxFragData - 1) / maxFragData
            var offset = 0

            for seq in 0..<totalFrags {
                let end = min(offset + maxFragData, data.count)
                let chunk = data[offset..<end]

                var flags = UInt8(totalFrags & 0x0F)
                if seq == 0 {
                    flags |= DataReassembler.FRAG_FIRST
                }
                if seq < totalFrags - 1 {
                    flags |= DataReassembler.FRAG_MORE
                }

                var payload = Data([flags, UInt8(seq), cId])
                payload.append(chunk)
                sendFrame(addr: 0x00, cmd: Self.CMD_DATA, payload: payload)

                offset = end

                // Inter-fragment delay (5ms)
                if seq < totalFrags - 1 {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
    }

    /// Build and send a single BLE-Eth frame.
    private func sendFrame(addr: UInt8, cmd: UInt8, payload: Data) {
        let payloadLen = payload.count
        guard payloadLen <= FrameParser.MAX_PAYLOAD_LEN else {
            logger.log("BLE-Eth: payload too large (\(payloadLen) bytes)", category: "BLE-Eth", level: .error)
            return
        }

        // Build frame: SYNC1 + SYNC2 + ADDR + CMD + LEN + PAYLOAD + CHECKSUM
        var frame = Data(capacity: 5 + payloadLen + 1)
        frame.append(FrameParser.SYNC1)
        frame.append(FrameParser.SYNC2)
        frame.append(addr)
        frame.append(cmd)
        frame.append(UInt8(payloadLen))
        frame.append(payload)

        // Calculate checksum
        var checksum: UInt8 = 0
        for byte in frame {
            checksum = checksum &+ byte
        }
        frame.append(checksum)

        logger.log("BLE-Eth: sendFrame addr=0x\(String(format: "%02X", addr)) cmd=0x\(String(format: "%02X", cmd)) payloadLen=\(payloadLen) frameLen=\(frame.count)", category: "BLE-Eth", level: .debug)

        // Send via BLEManager
        bleManager.sendRawData(frame)
    }

    // MARK: - Private: Helpers

    private func closePipes() {
        outboundPipe?.close()
        inboundPipe?.close()
        outboundPipe = nil
        inboundPipe = nil
    }
}