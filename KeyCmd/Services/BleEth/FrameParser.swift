import Foundation

/// State machine parser for BLE-Eth frames.
/// Ported from Android FrameParser.java.
///
/// Frame format: [0x57][0xAB][ADDR][CMD][LEN][PAYLOAD...][CHECKSUM]
/// - SYNC bytes: 0x57 0xAB
/// - ADDR: 1 byte (target address)
/// - CMD: 1 byte (command code)
/// - LEN: 1 byte (payload length, max 249)
/// - PAYLOAD: 0-249 bytes
/// - CHECKSUM: 1 byte (sum of all preceding bytes mod 256)
final class FrameParser {

    // MARK: - Constants

    static let SYNC1 = UInt8(0x57)
    static let SYNC2 = UInt8(0xAB)
    static let HEADER_LEN = 5
    static let MAX_PAYLOAD_LEN = 249
    static let MAX_FRAME_LEN = 255

    // MARK: - Parser States

    private enum State {
        case waitHead1
        case waitHead2
        case waitAddr
        case waitCmd
        case waitLen
        case waitPayload
        case waitChecksum
    }

    // MARK: - Parsed Frame

    struct ParsedFrame {
        let addr: UInt8
        let cmd: UInt8
        let payload: Data
    }

    // MARK: - State

    private var state: State = .waitHead1
    private var buffer: [UInt8] = []
    private var currentAddr: UInt8 = 0
    private var currentCmd: UInt8 = 0
    private var currentLen: Int = 0
    private var payloadBytesRead: Int = 0

    // MARK: - Callback

    var onFrameParsed: ((ParsedFrame) -> Void)?

    // MARK: - Public Methods

    /// Feed raw bytes into the parser.
    /// Calls onFrameParsed callback for each complete frame.
    func feed(data: Data) {
        for byte in data {
            processByte(byte)
        }
    }

    /// Feed a single byte into the parser.
    func feed(byte: UInt8) {
        processByte(byte)
    }

    /// Reset parser state.
    func reset() {
        state = .waitHead1
        buffer = []
        currentAddr = 0
        currentCmd = 0
        currentLen = 0
        payloadBytesRead = 0
    }

    // MARK: - Private Methods

    private func processByte(_ byte: UInt8) {
        switch state {
        case .waitHead1:
            if byte == Self.SYNC1 {
                state = .waitHead2
            }
            // Otherwise stay in waitHead1

        case .waitHead2:
            if byte == Self.SYNC2 {
                state = .waitAddr
            } else if byte == Self.SYNC1 {
                // Another SYNC1 — stay in waitHead2 (sync recovery)
                state = .waitHead2
            } else {
                // Invalid — reset to waitHead1
                state = .waitHead1
            }

        case .waitAddr:
            currentAddr = byte
            state = .waitCmd

        case .waitCmd:
            currentCmd = byte
            state = .waitLen

        case .waitLen:
            currentLen = Int(byte)
            if currentLen > Self.MAX_PAYLOAD_LEN {
                // Invalid length — reset
                reset()
            } else if currentLen == 0 {
                // No payload — go straight to checksum
                state = .waitChecksum
            } else {
                // Prepare to read payload
                buffer = []
                buffer.reserveCapacity(currentLen)
                payloadBytesRead = 0
                state = .waitPayload
            }

        case .waitPayload:
            buffer.append(byte)
            payloadBytesRead += 1
            if payloadBytesRead >= currentLen {
                state = .waitChecksum
            }

        case .waitChecksum:
            // Calculate checksum over header + payload
            var checksum = Self.SYNC1
            checksum = (checksum &+ Self.SYNC2) & 0xFF
            checksum = (checksum &+ currentAddr) & 0xFF
            checksum = (checksum &+ currentCmd) & 0xFF
            checksum = (checksum &+ UInt8(currentLen)) & 0xFF
            for b in buffer {
                checksum = (checksum &+ b) & 0xFF
            }

            if checksum == byte {
                // Valid frame
                let frame = ParsedFrame(
                    addr: currentAddr,
                    cmd: currentCmd,
                    payload: Data(buffer)
                )
                onFrameParsed?(frame)
            }
            // Always reset after checksum (valid or invalid)
            reset()
        }
    }
}