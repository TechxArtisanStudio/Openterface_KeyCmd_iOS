import Foundation

/// Reassembles fragmented BLE-Eth DATA frames into complete messages.
/// Ported from Android DataReassembler.java.
///
/// Fragment header (3 bytes):
/// - byte 0: FLAGS — bit 7 = FRAG_MORE, bit 6 = FRAG_FIRST, bits 0-3 = total fragment count
/// - byte 1: SEQ — fragment sequence number, 0-based
/// - byte 2: CONNID — connection ID
final class DataReassembler {

    // MARK: - Constants

    static let FRAG_HEADER_LEN = 3
    static let FRAG_MORE = UInt8(0x80)
    static let FRAG_FIRST = UInt8(0x40)
    static let FRAG_COUNT_MASK = UInt8(0x0F)
    static let MAX_FRAG_DATA = FrameParser.MAX_PAYLOAD_LEN - FRAG_HEADER_LEN  // 246

    // MARK: - Reassembled Data

    struct ReassembledData {
        let connId: UInt8
        let data: Data
    }

    // MARK: - State

    private var active: Bool = false
    private var totalFrags: Int = 0
    private var nextSeq: Int = 0
    private var buffer: Data = Data()
    private var reassemblyConnId: UInt8 = 0

    // MARK: - Callback

    var onReassembled: ((ReassembledData) -> Void)?

    // MARK: - Public Methods

    /// Feed a DATA frame payload (after removing frame header) into the reassembler.
    /// The payload should include the 3-byte fragment header.
    func feed(payload: Data) {
        guard payload.count >= Self.FRAG_HEADER_LEN else {
            // Too short to contain fragment header
            return
        }

        let flags = payload[0]
        let seq = Int(payload[1])
        let connId = payload[2]
        let isFirst = (flags & Self.FRAG_FIRST) != 0
        let hasMore = (flags & Self.FRAG_MORE) != 0
        let dataLen = payload.count - Self.FRAG_HEADER_LEN
        print("[DataReassembler] feed: flags=0x\(String(format: "%02X", flags)) seq=\(seq) connId=\(connId) first=\(isFirst) more=\(hasMore) dataLen=\(dataLen) active=\(active) nextSeq=\(nextSeq)")

        // Extract fragment data (skip 3-byte header)
        let fragData = payload.dropFirst(DataReassembler.FRAG_HEADER_LEN)

        var count = Int(flags & Self.FRAG_COUNT_MASK)
        if count == 0 {
            count = 1  // Normalize 0 to 1
        }

        if isFirst {
            // Start new reassembly
            active = true
            totalFrags = count
            nextSeq = 0
            buffer = Data()
            reassemblyConnId = connId
        }

        if !active {
            // Not in reassembly mode — drop fragment
            print("[DataReassembler] dropped: not active")
            return
        }

        // Check sequence number
        if seq != nextSeq {
            // Out of order — discard entire reassembly
            print("[DataReassembler] out of order: expected=\(nextSeq) got=\(seq) — discarding")
            active = false
            return
        }

        // Append fragment data
        buffer.append(fragData)
        nextSeq += 1

        // Check if this is the last fragment
        if !hasMore {
            // Reassembly complete
            print("[DataReassembler] complete: totalLen=\(buffer.count) connId=\(reassemblyConnId)")
            let reassembled = ReassembledData(
                connId: reassemblyConnId,
                data: buffer
            )
            active = false
            onReassembled?(reassembled)
        }
    }

    /// Reset reassembler state.
    func reset() {
        active = false
        totalFrags = 0
        nextSeq = 0
        buffer = Data()
        reassemblyConnId = 0
    }
}