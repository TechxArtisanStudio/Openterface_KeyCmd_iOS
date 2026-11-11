// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import Foundation

/// CH9329 BLE name commands (Openterface extension, KVM-GO firmware).
/// Set name: 57 AB 00 23 <len> <raw UTF-8 bytes> <sum>, reply A3 (ok) / E3 (error).
/// Factory reset: 57 AB 00 31 01 00 <sum>, reply B1 (ok) / F1 (error).
/// The firmware reboots 500ms after a successful reply.
enum BLENameCommand {
    static let maxNameBytes = 20
    static let cmdSetName: UInt8 = 0x23
    static let cmdSystemReset: UInt8 = 0x31
    static let responseCommands: Set<UInt8> = [0xA3, 0xE3, 0xB1, 0xF1]

    /// Trims whitespace, then enforces the firmware constraints: 1...20 UTF-8
    /// bytes, every byte >= 0x20. The lower bound also avoids the firmware's
    /// 0x23 payload-shape collision with BLE-Eth GET_ECM_IP (len==1, byte<=0x06).
    static func validatedNameBytes(_ name: String) -> [UInt8]? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard (1...maxNameBytes).contains(bytes.count) else { return nil }
        guard bytes.allSatisfy({ $0 >= 0x20 }) else { return nil }
        return bytes
    }

    static func setNameFrame(_ name: String) -> Data? {
        guard let bytes = validatedNameBytes(name) else { return nil }
        return frame(cmd: cmdSetName, payload: bytes)
    }

    static func resetNameFrame() -> Data {
        frame(cmd: cmdSystemReset, payload: [0x00])
    }

    static func frame(cmd: UInt8, payload: [UInt8]) -> Data {
        var bytes: [UInt8] = [0x57, 0xAB, 0x00, cmd, UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        bytes.append(bytes.reduce(UInt8(0)) { $0 &+ $1 })
        return Data(bytes)
    }

    struct Response: Equatable {
        let cmd: UInt8
        let status: UInt8
        /// Payload bytes after the status byte (ECM GET data; empty for rename replies).
        let payload: Data

        var isSuccess: Bool {
            (cmd == 0xA3 || cmd == 0xB1) && status == 0x00
        }
    }

    /// Incrementally scans FFF1 notification bytes for command responses
    /// (rename or ECM IP) while passing everything else through untouched, so
    /// an active BLE-Eth tunnel keeps working during the response window.
    struct ResponseScanner {
        private var buffer = Data()
        private let targetCommands: Set<UInt8>

        init(targetCommands: Set<UInt8> = BLENameCommand.responseCommands) {
            self.targetCommands = targetCommands
        }

        mutating func feed(_ data: Data) -> (responses: [Response], passthrough: Data) {
            buffer.append(data)
            var responses: [Response] = []
            var passthrough = Data()

            while !buffer.isEmpty {
                guard let syncIndex = buffer.firstIndex(of: 0x57) else {
                    passthrough.append(buffer)
                    buffer.removeAll()
                    break
                }
                if syncIndex > buffer.startIndex {
                    passthrough.append(buffer[buffer.startIndex..<syncIndex])
                    buffer.removeSubrange(buffer.startIndex..<syncIndex)
                }
                guard buffer.count >= 2 else { break }
                guard buffer[buffer.startIndex + 1] == 0xAB else {
                    passthrough.append(buffer[buffer.startIndex])
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= 5 else { break }
                let frameLength = 6 + Int(buffer[buffer.startIndex + 4])
                guard buffer.count >= frameLength else { break }

                let frame = buffer.prefix(frameLength)
                let checksum = frame.dropLast().reduce(UInt8(0)) { $0 &+ $1 }
                if checksum == frame[frame.startIndex + frameLength - 1] {
                    let cmd = frame[frame.startIndex + 3]
                    if targetCommands.contains(cmd) {
                        let status = frameLength > 6 ? frame[frame.startIndex + 5] : 0
                        let payload = frameLength > 7 ? Data(frame[(frame.startIndex + 6)..<(frame.startIndex + frameLength - 1)]) : Data()
                        responses.append(Response(cmd: cmd, status: status, payload: payload))
                    } else {
                        passthrough.append(frame)
                    }
                    buffer.removeFirst(frameLength)
                } else {
                    // Bad checksum: this 57 AB was payload data, not a header.
                    passthrough.append(buffer[buffer.startIndex])
                    buffer.removeFirst()
                }
            }
            return (responses, passthrough)
        }

        /// Releases any buffered partial frame when the rename window closes.
        mutating func flush() -> Data {
            let remaining = buffer
            buffer.removeAll()
            return remaining
        }
    }
}