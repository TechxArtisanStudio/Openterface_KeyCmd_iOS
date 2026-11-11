// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import Foundation
import Combine

/// BLE-Eth transport implementation.
/// Tunnels TCP traffic over BLE GATT using the custom frame protocol defined in
/// FrameParser. The Openterface KeyMod device acts as a BLE-to-TCP bridge.
///
/// Flow control mirrors the proven Opf_test reference (eth_tunnel.py): every
/// outbound DATA fragment is paced by the firmware's cumulative metadata ACK
/// ([status][conn][seq][expected_seq][rx_window]) with a sliding window and
/// retransmission. Fire-and-forget sending overruns the firmware's ~6-fragment
/// reassembly/TX queue and silently stalls the SSH handshake.
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

    // MARK: - Flow-control Constants

    /// Firmware reassembles at most 6 fragments per message.
    private static let maxFragsPerMessage = 6
    /// One reassembled message is forwarded as a single TCP segment; keep it
    /// below the MTU margin (1460) so the device's segment is not dropped.
    private static let safeMessageLen = 1440
    /// Per-fragment ACK budget; doubles on each retry (2s, 4s, 8s, 16s).
    private static let ackTimeoutSeconds = 2.0
    private static let ackRetries = 3
    /// Gap between frames so the firmware's parser/queue is not overwhelmed.
    private static let frameGapNs: UInt64 = 1_000_000  // 1ms

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

    /// Human-readable reason from the most recent connect() failure (nil on success).
    private(set) var lastConnectError: String?

    /// Pipe for SSH → BLE direction (app sends data to remote)
    private var outboundPipe: QueuePipe?

    /// Pipe for BLE → SSH direction (remote sends data to app)
    private var inboundPipe: QueuePipe?

    /// Pending connection state (used during connect handshake)
    private var pendingConnId: UInt8 = 0
    private var pendingConnStatus: UInt8 = 0
    private var connectSemaphore: DispatchSemaphore?

    /// Firmware-advertised RX headroom (1...15); sliding window is capped at 6.
    private var rxWindow: Int = 1
    /// Outstanding outbound fragments awaiting their metadata ACK.
    private var ackWaiters: [AckKey: AckFuture] = [:]

    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Background queue for output reader task
    private var outputReaderTask: Task<Void, Never>?

    // MARK: - ACK Primitives

    private struct AckKey: Hashable {
        let connId: UInt8
        let seq: UInt8
    }

    /// One-shot thread-safe result holder for a fragment ACK.
    private final class AckFuture {
        enum Result {
            case acked(UInt8)   // firmware status byte (0x00 = success)
            case timeout
            case aborted        // transport disconnected / link lost
        }

        private let lock = NSLock()
        private var result: Result?
        private var continuation: CheckedContinuation<Result, Never>?

        func resolve(_ r: Result) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = r
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: r)
        }

        func wait() async -> Result {
            await withCheckedContinuation { c in
                lock.lock()
                if let r = result {
                    lock.unlock()
                    c.resume(returning: r)
                    return
                }
                continuation = c
                lock.unlock()
            }
        }
    }

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
        lastConnectError = nil
        connectSemaphore = nil
        pendingConnId = 0
        pendingConnStatus = 0
        rxWindow = 1
        let staleWaiters = Array(ackWaiters.values)
        ackWaiters.removeAll()
        stateLock.unlock()
        for w in staleWaiters { w.resolve(.aborted) }

        // 2. Parse IPv4 address (validate before touching the device)
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

        // 3. Clear any stale connection state on the device.
        // DISCONNECT common stale connIds (255 and 0) so the device releases
        // orphaned connections — prevents 0xE7 on retry.
        logger.log("BLE-Eth: sending cleanup DISCONNECT for stale connIds", category: "BLE-Eth", level: .info)
        for staleConnId in [UInt8(255), UInt8(0)] {
            sendFrame(addr: 0x00, cmd: Self.CMD_DISCONNECT, payload: Data([staleConnId]))
            Thread.sleep(forTimeInterval: 0.05)
        }
        Thread.sleep(forTimeInterval: 0.5)

        // 4. Create pipes
        outboundPipe = QueuePipe(capacity: 256)
        inboundPipe = QueuePipe(capacity: 256)

        // 5. Start output reader — polls outbound pipe, paces fragments by ACK
        outputReaderTask = Task { [weak self] in
            await self?.runOutputReader()
        }

        // 6. Build and send CONNECT frame
        let semaphore = DispatchSemaphore(value: 0)
        stateLock.lock()
        connectSemaphore = semaphore
        stateLock.unlock()

        let payload = Data([ip0, ip1, ip2, ip3, portHi, portLo])
        logger.log("BLE-Eth: sending CONNECT frame payloadLen=\(payload.count)", category: "BLE-Eth", level: .debug)
        sendFrame(addr: 0x00, cmd: Self.CMD_CONNECT, payload: payload)

        // 7. Wait for CONNECT_RESP or timeout
        logger.log("BLE-Eth: waiting for CONNECT_RESP (semaphore)", category: "BLE-Eth", level: .debug)
        let result = semaphore.wait(timeout: .now() + .milliseconds(timeoutMs))

        stateLock.lock()
        connectSemaphore = nil
        let status = pendingConnStatus
        let cid = pendingConnId
        stateLock.unlock()

        if result == .timedOut {
            logger.log("BLE-Eth CONNECT timed out after \(timeoutMs)ms", category: "BLE-Eth", level: .error)
            lastConnectError = "CONNECT timed out after \(timeoutMs / 1000)s — device did not answer (target may be unreachable)"
            listener?.onError(message: "BLE-Eth CONNECT timed out")
            return
        }
        logger.log("BLE-Eth: got CONNECT_RESP connId=\(cid) status=\(status)", category: "BLE-Eth", level: .debug)

        // 8. Check response status
        if status != 0x00 {
            let statusHex = String(format: "0x%02X", status)
            let reason = Self.connectStatusText(status)
            logger.log("BLE-Eth CONNECT failed: status=\(statusHex) (\(reason)) connId=\(cid) — sending DISCONNECT to clear stale state", category: "BLE-Eth", level: .error)
            lastConnectError = "\(reason) (\(statusHex))"
            sendFrame(addr: 0x00, cmd: Self.CMD_DISCONNECT, payload: Data([cid]))
            listener?.onError(message: "BLE-Eth CONNECT failed: \(reason) (\(statusHex))")
            return
        }

        // running/connId were already set in handleConnectResponse so the banner
        // (pushed immediately after CONNECT_RESP) is delivered, not dropped.
        logger.log("BLE-Eth connected: connId=\(cid)", category: "BLE-Eth", level: .success)
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
        rxWindow = 1
        let waiters = Array(ackWaiters.values)
        ackWaiters.removeAll()
        closePipes()
        stateLock.unlock()

        // Wake any blocked sender so the output reader can exit.
        for w in waiters { w.resolve(.aborted) }

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
        let cid = payload[0]
        let status = payload[1]
        stateLock.lock()
        pendingConnId = cid
        pendingConnStatus = status
        if status == 0x00 {
            // Mark connected BEFORE signaling the semaphore. The device pushes
            // the SSH banner immediately after CONNECT_RESP on the same serial
            // BLE queue; deliverReassembledData must already see running/connId
            // set or the banner is dropped and libssh2 waits forever.
            connId = Int(cid)
            running = true
        }
        stateLock.unlock()
        connectSemaphore?.signal()
    }

    private func handleDataResponse(_ payload: Data) {
        // 0x91 carries both metadata ACKs (for our outbound data) and inbound
        // DATA_PUSH fragments. Discriminate by payload shape, like Opf_test.
        if looksLikeDataAck(payload) {
            handleDataAck(payload)
            return
        }
        let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
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

    /// Parse and apply a firmware metadata ACK.
    /// Format: [status] / [status,conn,seq,expected_seq] / +[rx_window].
    /// expected_seq is cumulative: it releases every waiter with seq < expected.
    private func handleDataAck(_ payload: Data) {
        let status = payload[0]
        var conn: UInt8 = 0
        var seq: UInt8 = 0
        var expected: UInt8 = 0
        var windowText = "-"
        if payload.count >= 4 {
            conn = payload[1]
            seq = payload[2]
            expected = payload[3]
            if payload.count >= 5 {
                let w = max(1, min(Int(payload[4]), 15))
                stateLock.lock()
                rxWindow = w
                stateLock.unlock()
                windowText = String(w)
            }
        }
        logger.log("BLE-Eth: DATA ACK status=0x\(String(format: "%02X", status)) conn=\(conn) seq=\(seq) expected=\(expected) window=\(windowText)", category: "BLE-Eth", level: .debug)

        var resolved: [AckFuture] = []
        var exact: AckFuture?
        stateLock.lock()
        if status == 0x00 && payload.count >= 4 {
            let matching = ackWaiters.filter { $0.key.connId == conn && $0.key.seq < expected }
            for (key, fut) in matching {
                resolved.append(fut)
                ackWaiters[key] = nil
            }
        }
        if resolved.isEmpty {
            let key = AckKey(connId: conn, seq: seq)
            exact = ackWaiters[key]
            ackWaiters[key] = nil
        }
        stateLock.unlock()

        for fut in resolved { fut.resolve(.acked(status)) }
        if let fut = exact { fut.resolve(.acked(status)) }
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
            stateLock.lock()
            pendingConnStatus = 0xE7 // Generic rejection status
            stateLock.unlock()
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

    /// Background task that reads from the outbound pipe and sends DATA
    /// fragments paced by the firmware's metadata ACK window.
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
                let ready = stateLock.withLock { running && connId >= 0 }
                if ready { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled else { break }

            let chunk = await reader.read()
            guard let data = chunk else {
                logger.log("BLE-Eth: output reader EOF", category: "BLE-Eth", level: .info)
                break
            }

            logger.log("BLE-Eth: output reader got \(data.count) bytes → sendWithAcks", category: "BLE-Eth", level: .debug)
            let payloads = buildDataPayloads(data)
            let ok = await sendWithAcks(payloads)
            if !ok {
                logger.log("BLE-Eth: send failed (ACK exhausted/aborted) — disconnecting", category: "BLE-Eth", level: .error)
                listener?.onError(message: "BLE-Eth data send failed (no ACK)")
                disconnect()
                break
            }
        }
        logger.log("BLE-Eth: output reader exited", category: "BLE-Eth", level: .info)
    }

    // MARK: - Private: Fragment Building

    /// Split a byte stream into BLE-Eth DATA payloads: messages ≤1440B, each
    /// fragmented into ≤246B pieces. Single fragments use flags 0x41
    /// (FRAG_FIRST | count=1) — the device drops count=0 payloads.
    private func buildDataPayloads(_ data: Data) -> [Data] {
        let cId: UInt8 = stateLock.withLock { connId >= 0 ? UInt8(connId) : 0 }
        let maxFrag = DataReassembler.MAX_FRAG_DATA  // 246
        var payloads: [Data] = []

        var msgStart = data.startIndex
        while msgStart < data.endIndex {
            let msgEnd = min(msgStart + Self.safeMessageLen, data.endIndex)
            let message = data[msgStart..<msgEnd]
            msgStart = msgEnd

            if message.count <= maxFrag {
                let flags = DataReassembler.FRAG_FIRST | 0x01  // 0x41
                var p = Data([flags, 0x00, cId])
                p.append(message)
                payloads.append(p)
            } else {
                let totalFrags = (message.count + maxFrag - 1) / maxFrag
                var offset = message.startIndex
                for seq in 0..<totalFrags {
                    let end = min(offset + maxFrag, message.endIndex)
                    var flags = UInt8(totalFrags & 0x0F)
                    if seq == 0 { flags |= DataReassembler.FRAG_FIRST }
                    if seq < totalFrags - 1 { flags |= DataReassembler.FRAG_MORE }
                    var p = Data([flags, UInt8(seq), cId])
                    p.append(message[offset..<end])
                    payloads.append(p)
                    offset = end
                }
            }
        }
        return payloads
    }

    private static func dataFrameKey(_ payload: Data) -> AckKey? {
        guard payload.count >= 3 else { return nil }
        return AckKey(connId: payload[2], seq: payload[1])
    }

    // MARK: - Private: ACK-paced Sending

    /// Send DATA payloads with a sliding window bounded by the firmware's RX
    /// headroom. Mirrors Opf_test _send_with_acks: register the waiter before
    /// sending, pace by window, drain outstanding ACKs at the end.
    private func sendWithAcks(_ payloads: [Data]) async -> Bool {
        var pending: [(key: AckKey, payload: Data, future: AckFuture)] = []

        for payload in payloads {
            let window = stateLock.withLock { max(1, min(rxWindow, Self.maxFragsPerMessage)) }
            while pending.count >= window {
                let item = pending.removeFirst()
                guard await awaitAck(key: item.key, payload: item.payload, future: item.future) else { return false }
            }
            guard let key = Self.dataFrameKey(payload) else {
                sendFrame(addr: 0x00, cmd: Self.CMD_DATA, payload: payload)
                continue
            }
            let future = AckFuture()
            stateLock.lock()
            ackWaiters[key] = future
            stateLock.unlock()
            pending.append((key, payload, future))
            sendFrame(addr: 0x00, cmd: Self.CMD_DATA, payload: payload)
            try? await Task.sleep(nanoseconds: Self.frameGapNs)
        }

        while !pending.isEmpty {
            let item = pending.removeFirst()
            guard await awaitAck(key: item.key, payload: item.payload, future: item.future) else { return false }
        }
        return true
    }

    /// Await one fragment's ACK with exponential-backoff retransmission.
    /// On timeout/FRAME_ERR the firmware's reassembly is invalidated, so the
    /// identical frame must be resent. Mirrors Opf_test _await_ack.
    private func awaitAck(key: AckKey, payload: Data, future initialFuture: AckFuture) async -> Bool {
        var future = initialFuture
        for attempt in 0...Self.ackRetries {
            let timeout = Self.ackTimeoutSeconds * Double(1 << attempt)
            let currentFuture = future
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                currentFuture.resolve(.timeout)
            }
            let result = await future.wait()
            timeoutTask.cancel()

            switch result {
            case .acked(0x00):
                return true
            case .aborted:
                return false
            case .acked(let status):
                logger.log("BLE-Eth: DATA ACK conn=\(key.connId) seq=\(key.seq) status=0x\(String(format: "%02X", status)) — retransmit", category: "BLE-Eth", level: .warning)
            case .timeout:
                logger.log("BLE-Eth: DATA ACK conn=\(key.connId) seq=\(key.seq) timeout (attempt \(attempt))", category: "BLE-Eth", level: .debug)
            }

            stateLock.lock()
            if ackWaiters[key] === future { ackWaiters[key] = nil }
            stateLock.unlock()

            if attempt >= Self.ackRetries {
                logger.log("BLE-Eth: DATA conn=\(key.connId) seq=\(key.seq) ACK exhausted after \(Self.ackRetries) retries", category: "BLE-Eth", level: .error)
                return false
            }

            let newFuture = AckFuture()
            stateLock.lock()
            ackWaiters[key] = newFuture
            stateLock.unlock()
            future = newFuture
            sendFrame(addr: 0x00, cmd: Self.CMD_DATA, payload: payload)
            try? await Task.sleep(nanoseconds: Self.frameGapNs)
        }
        return false
    }

    // MARK: - Private: Frame Building & Sending

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

    /// Decode a CONNECT_RESP status byte (firmware ble_eth_protocol.h).
    private static func connectStatusText(_ status: UInt8) -> String {
        switch status {
        case 0x00: return "success"
        case 0xE1: return "target unreachable — ARP/SYN timeout, check target IP is on the device ECM subnet and host is connected"
        case 0xE5: return "parameter error"
        case 0xE6: return "frame error"
        case 0xE7: return "connection slots full"
        case 0xE8: return "no route — ECM link down or target not reachable"
        default:   return "device error"
        }
    }

    private func closePipes() {
        outboundPipe?.close()
        inboundPipe?.close()
        outboundPipe = nil
        inboundPipe = nil
    }
}