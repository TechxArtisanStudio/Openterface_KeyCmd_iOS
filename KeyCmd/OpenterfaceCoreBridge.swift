//
//  OpenterfaceCoreBridge.swift
//  KeyMod
//
//  Swift wrapper for the OpenterfaceCore C library.
//

import Foundation

// ── Modifier flags (mirrors OP_INPUT_MOD_* defines) ─────────────────────

private enum OpInputMod {
    static let none:   UInt8 = 0x00
    static let lCtrl:  UInt8 = 0x01
    static let lShift: UInt8 = 0x02
    static let lAlt:   UInt8 = 0x04
    static let lGui:   UInt8 = 0x08
    static let rCtrl:  UInt8 = 0x10
    static let rShift: UInt8 = 0x20
    static let rAlt:   UInt8 = 0x40
    static let rGui:   UInt8 = 0x80
}

struct KMod: OptionSet {
    let rawValue: UInt8
    static let ctrl  = KMod(rawValue: OpInputMod.lCtrl)
    static let shift = KMod(rawValue: OpInputMod.lShift)
    static let alt   = KMod(rawValue: OpInputMod.lAlt)
    static let gui   = KMod(rawValue: OpInputMod.lGui)
    static let none  = KMod(rawValue: OpInputMod.none)
}

// ── Packet size constants (mirrors OP_INPUT_PKT_* defines) ──────────────

enum KMPacketSize {
    static let keyboard:     Int = 14  // 5 header + 8 data + 1 checksum
    static let mouseRel:     Int = 11  // 5 header + 5 data + 1 checksum
    static let pressRelease: Int = 2 * 14
}

// ── Parsed token result ────────────────────────────────────────────────

struct KMParsedToken {
    let hidCode: Int32
    let modifiers: UInt8
}

struct KMScriptTokenSpan {
    let startUTF8: Int32
    let lengthUTF8: Int32
}

// ── Bridged functions ──────────────────────────────────────────────────

enum Keymod {

    // MARK: - HID Lookup

    /// Look up HID usage code by key name string (e.g. "Enter", "A", "F1").
    /// Returns -1 if unknown.
    static func hidCode(forKey name: String) -> Int32 {
        name.withCString { op_input_hid_code_from_name($0) }
    }

    /// Map a printable ASCII character to its HID code.
    /// Returns (code, needsShift). code is -1 if unmappable.
    static func hidCode(for char: Character) -> (code: Int32, needsShift: Bool) {
        var shift: Int32 = 0
        let scalar = char.unicodeScalars.first?.value ?? 0
        guard scalar >= 0x20 && scalar <= 0x7E else { return (-1, false) }
        let code = op_input_hid_code_from_char(CChar(scalar), &shift)
        return (code, shift != 0)
    }

    /// Convert a HID usage code to a human-readable label.
    static func label(for hidCode: Int32) -> String {
        String(cString: op_input_hid_code_label(hidCode))
    }

    // MARK: - Packet Builders

    /// Build a CH9329 keyboard packet (14 bytes).
    static func buildKeyboard(modifiers: UInt8, keys: [UInt8]) -> Data {
        var out = Data(count: KMPacketSize.keyboard)
        _ = out.withUnsafeMutableBytes { buf in
            op_input_build_keyboard(
                buf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                modifiers, keys, Int32(keys.count)
            )
        }
        return out
    }

    /// Build a CH9329 relative-mouse packet (11 bytes).
    static func buildMouseRel(buttons: UInt8, dx: Int8, dy: Int8, wheel: Int8) -> Data {
        var out = Data(count: KMPacketSize.mouseRel)
        _ = out.withUnsafeMutableBytes { buf in
            op_input_build_mouse_rel(
                buf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                buttons, dx, dy, wheel
            )
        }
        return out
    }

    /// Build a press+release keyboard sequence (28 bytes = 2 × 14).
    static func buildPressRelease(modifiers: UInt8, hidCode: UInt8) -> Data {
        var out = Data(count: KMPacketSize.pressRelease)
        _ = out.withUnsafeMutableBytes { buf in
            op_input_build_press_release(
                buf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                modifiers, hidCode
            )
        }
        return out
    }

    // MARK: - Token / Macro Parsing

    /// Parse a single token string into (hidCode, modifiers).
    static func parseToken(_ token: String) -> KMParsedToken {
        let result = token.withCString { op_input_parse_token($0) }
        return KMParsedToken(hidCode: result.hid_code, modifiers: UInt8(result.modifiers))
    }

    /// Parse a full macro string into an array of parsed tokens.
    static func parseMacro(_ input: String, max: Int = 128) -> [KMParsedToken] {
        var out = [op_input_parsed_token_t](
            repeating: op_input_parsed_token_t(hid_code: 0, modifiers: 0),
            count: max
        )
        let count = input.withCString { op_input_macro_parse($0, &out, Int32(max)) }
        return (0..<Int(count)).map {
            KMParsedToken(hidCode: out[$0].hid_code, modifiers: UInt8(out[$0].modifiers))
        }
    }

    /// Tokenize a macro script into raw tags or single-character strings.
    static func tokenizeScript(_ input: String) -> [String] {
        let utf8Bytes = Array(input.utf8)
        guard !utf8Bytes.isEmpty else { return [] }

        var spans = [op_input_script_token_span_t](
            repeating: op_input_script_token_span_t(start_utf8: 0, length_utf8: 0),
            count: utf8Bytes.count
        )
        let count = input.withCString { op_input_script_tokenize($0, &spans, Int32(spans.count)) }

        return (0..<Int(count)).compactMap { index in
            let span = spans[index]
            let start = Int(span.start_utf8)
            let end = start + Int(span.length_utf8)
            guard start >= 0, end <= utf8Bytes.count, start < end else { return nil }
            return String(decoding: utf8Bytes[start..<end], as: UTF8.self)
        }
    }

    // MARK: - Utility

    /// Compute the CH9329 checksum for a packet.
    static func checksum(_ data: Data) -> UInt8 {
        data.withUnsafeBytes { buf in
            op_input_checksum(
                buf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                Int32(data.count)
            )
        }
    }

    /// Format a packet as an uppercase hex string (for debugging).
    static func hexDump(_ data: Data) -> String {
        var bytes = [UInt8](repeating: 0, count: 2 * data.count + 1)
        data.withUnsafeBytes { buf in
            op_input_hex_dump(
                buf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                Int32(data.count), &bytes
            )
        }
        return String(cString: bytes)
    }
}
