// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import Foundation

/// CH9329 BLE security commands (Openterface extension, KeyMod firmware).
/// Status: 57 AB 00 22 01 03 <sum>, reply A2 [status][count][maxBonds].
/// Set PIN: 57 AB 00 22 07 04 <6 ASCII digits> <sum>, reply A2 [status].
/// Erase:   57 AB 00 22 01 02 <sum>, reply A2 [status], then the device reboots.
/// Success responses use cmd|0x80 (0xA2), failures cmd|0xC0 (0xE2).
/// The firmware never returns the current PIN and rejects 0x05 over BLE.
enum BLESecurityCommand {
    static let cmd: UInt8 = 0x22
    static let responseCommands: Set<UInt8> = [0xA2, 0xE2]

    static let factoryPIN = "666666"
    static let pinLength = 6

    struct Status: Equatable {
        let bondCount: UInt8
        let maxBonds: UInt8

        /// Older firmware answers 0x03 with a fake [0, 0] payload.
        var isSupported: Bool { maxBonds > 0 }

        var isFull: Bool { bondCount >= maxBonds }
    }

    // MARK: - Frames

    static func statusFrame() -> Data {
        BLENameCommand.frame(cmd: cmd, payload: [0x03])
    }

    static func readMaxBondsFrame() -> Data {
        BLENameCommand.frame(cmd: cmd, payload: [0x06])
    }

    static func setPINFrame(_ pin: String) -> Data? {
        guard validatePIN(pin) else { return nil }
        return BLENameCommand.frame(cmd: cmd, payload: [0x04] + Array(pin.utf8))
    }

    static func eraseBondsFrame() -> Data {
        BLENameCommand.frame(cmd: cmd, payload: [0x02])
    }

    // MARK: - Validation

    /// Firmware accepts exactly six ASCII digits and parses them as a uint32,
    /// so leading zeros are equivalent to their numeric value on the phone side.
    static func validatePIN(_ pin: String) -> Bool {
        let scalars = pin.unicodeScalars
        guard scalars.count == pinLength else { return false }
        return scalars.allSatisfy { $0.value >= 0x30 && $0.value <= 0x39 }
    }

    // MARK: - Responses

    /// Payload after the status byte of a 0x03 reply: [count][maxBonds].
    static func parseStatus(_ payload: Data) -> Status? {
        let bytes = Array(payload)
        guard bytes.count == 2 else { return nil }
        return Status(bondCount: bytes[0], maxBonds: bytes[1])
    }

    /// Payload after the status byte of a 0x06 reply: [maxBonds].
    static func parseMaxBonds(_ payload: Data) -> UInt8? {
        let bytes = Array(payload)
        guard bytes.count == 1 else { return nil }
        return bytes[0]
    }
}
