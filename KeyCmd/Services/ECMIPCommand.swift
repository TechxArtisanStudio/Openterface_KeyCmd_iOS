// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import Foundation

/// BLE-Eth ECM IP configuration commands (KeyMod firmware, Openterface_KM
/// ble_eth_protocol.c).
/// GET: 57 AB 00 23 01 00 <sum>, reply A3 [status][host 4][dev 4][mask 4][target_host 4][target_dev 4].
/// SET all: 57 AB 00 22 15 00 <20 IP bytes> <sum>, reply A2 [status].
/// Reset: 57 AB 00 22 01 04 <sum>, reply A2 [status].
/// Status: 0x00 ok, 0xE5 invalid params, 0xE9 flash error.
/// The firmware re-enumerates the affected USB side ~500ms after a successful
/// SET; the BLE link itself stays up.
enum ECMIPCommand {
    static let cmdSet: UInt8 = 0x22
    static let cmdGet: UInt8 = 0x23
    static let responseCommands: Set<UInt8> = [0xA2, 0xA3]

    struct Config: Equatable {
        var hostIP: [UInt8]
        var devIP: [UInt8]
        var subnetMask: [UInt8]
        var targetHostIP: [UInt8]
        var targetDevIP: [UInt8]
    }

    static let defaultConfig = Config(
        hostIP: [192, 168, 11, 1],
        devIP: [192, 168, 11, 3],
        subnetMask: [255, 255, 255, 0],
        targetHostIP: [192, 168, 11, 2],
        targetDevIP: [192, 168, 11, 5]
    )

    // MARK: - IPv4 Text

    static func parseIPv4(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part), value <= 255 else { return nil }
            bytes.append(UInt8(value))
        }
        return bytes
    }

    static func formatIPv4(_ bytes: [UInt8]) -> String {
        bytes.map(String.init).joined(separator: ".")
    }

    // MARK: - Validation (mirrors firmware ECM_IPConfig_Validate)

    static func validate(_ config: Config) -> Bool {
        let ips = [config.hostIP, config.devIP, config.targetHostIP, config.targetDevIP]
        for ip in ips {
            guard ip.count == 4 else { return false }
            if ip.allSatisfy({ $0 == 0 }) || ip.allSatisfy({ $0 == 255 }) { return false }
        }
        guard config.subnetMask.count == 4 else { return false }
        let mask = config.subnetMask.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        // Inverted mask must be of the form 2^n - 1 (firmware ecm_ip_config.c).
        let inv = ~mask
        guard mask != 0, mask != 0xFFFFFFFF, (inv & (inv &+ 1)) == 0 else { return false }
        let network = ips[0].enumerated().map { $0.element & config.subnetMask[$0.offset] }
        for ip in ips.dropFirst() {
            for i in 0..<4 where (ip[i] & config.subnetMask[i]) != network[i] { return false }
        }
        for i in 0..<ips.count {
            for j in (i + 1)..<ips.count where ips[i] == ips[j] { return false }
        }
        return true
    }

    // MARK: - Frames

    static func getFrame() -> Data {
        BLENameCommand.frame(cmd: cmdGet, payload: [0x00])
    }

    static func setAllFrame(_ config: Config) -> Data? {
        guard validate(config) else { return nil }
        var payload: [UInt8] = [0x00]
        for ip in [config.hostIP, config.devIP, config.subnetMask, config.targetHostIP, config.targetDevIP] {
            payload.append(contentsOf: ip)
        }
        return BLENameCommand.frame(cmd: cmdSet, payload: payload)
    }

    static func resetFrame() -> Data {
        BLENameCommand.frame(cmd: cmdSet, payload: [0x04])
    }

    /// Parses the 20 data bytes of a GET reply (payload after the status byte).
    static func parseConfig(_ data: Data) -> Config? {
        guard data.count == 20 else { return nil }
        let bytes = Array(data)
        return Config(
            hostIP: Array(bytes[0..<4]),
            devIP: Array(bytes[4..<8]),
            subnetMask: Array(bytes[8..<12]),
            targetHostIP: Array(bytes[12..<16]),
            targetDevIP: Array(bytes[16..<20])
        )
    }
}