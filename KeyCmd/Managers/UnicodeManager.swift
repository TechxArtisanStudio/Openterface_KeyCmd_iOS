//
//  UnicodeManager.swift
//  KeyMod
//
//  Converts non-ASCII Unicode characters into OS-appropriate keyboard sequences
//  and sends them to the target machine via BLE HID.
//
//  Windows  – Alt  + NumPad+ + 4 hex digits + release Alt
//             (requires EnableHexNumpad = 1 in HKCU\Control Panel\Input Method)
//  Linux    – Ctrl + Shift  + U, then hex digits, then Enter  (GTK/IBus)
//  macOS    – Option held + 4 hex digits + release Option
//             (requires "Unicode Hex Input" keyboard in System Settings → Keyboard → Input Sources)
//

import Foundation

class UnicodeManager {

    static let shared = UnicodeManager()
    private init() {}

    private let logger = LogManager.shared

    /// Serial queue — ensures that back-to-back Unicode characters are sent
    /// one after the other and never interleave their HID reports.
    let serialQueue = DispatchQueue(label: "com.keymod.unicode", qos: .userInitiated)

    // ── Standard USB HID modifier bitmasks ──────────────────────────────────
    private let kAlt:   UInt8 = 0x04   // Left Alt
    private let kCtrl:  UInt8 = 0x01   // Left Ctrl
    private let kShift: UInt8 = 0x02   // Left Shift

    // ── HID key codes used in Unicode sequences ──────────────────────────────
    // Numpad 0–9 (used for digit portion of Windows hex input)
    private let numpadCodes: [Character: UInt8] = [
        "0": 0x62, "1": 0x59, "2": 0x5A, "3": 0x5B,
        "4": 0x5C, "5": 0x5D, "6": 0x5E, "7": 0x5F,
        "8": 0x60, "9": 0x61
    ]

    // Regular letter keys A–F (used for the hex-letter portion of Windows input)
    private let hexLetterCodes: [Character: UInt8] = [
        "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09
    ]

    // Regular number-row keys 0–9 and letter keys a–f (Linux digit typing)
    private let regularDigitCodes: [Character: UInt8] = [
        "0": 0x27, "1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21,
        "5": 0x22, "6": 0x23, "7": 0x24, "8": 0x25, "9": 0x26,
        "a": 0x04, "b": 0x05, "c": 0x06, "d": 0x07, "e": 0x08, "f": 0x09
    ]

    // Zero key-code array (all keys released)
    private let kRelease: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

    // ── Target OS (read from same UserDefaults key as AISettings) ────────────
    var targetOS: TargetOS {
        let raw = UserDefaults.standard.string(forKey: "AISettings.targetOS")
                  ?? TargetOS.windows.rawValue
        return TargetOS(rawValue: raw) ?? .windows
    }

    // ── BLE key timing helpers ───────────────────────────────────────────────
    /// Inter-key delay in microseconds (reads live from AISettings).
    private var keyDelayUs:    UInt32 { UInt32(AISettings.shared.bleKeyDelayMs) * 1_000 }
    /// Slightly longer delay used after modifier release / character commit.
    private var commitDelayUs: UInt32 { UInt32(AISettings.shared.bleKeyDelayMs + 20) * 1_000 }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - Public API
    // ────────────────────────────────────────────────────────────────────────

    /// Send a single non-ASCII character to the target machine using the
    /// platform-appropriate Unicode entry method.
    ///
    /// **Must be called from a background thread** – the method blocks with
    /// `usleep()` between HID reports to give the target OS time to register
    /// each keystroke.
    func sendChar(_ char: Character, keyboardManager: KeyboardManager) {
        guard let scalar = char.unicodeScalars.first?.value else { return }
        let hexStr = String(format: "%04X", scalar).uppercased()

        logger.log("Unicode send: '\(char)' U+\(hexStr) → \(targetOS.displayName)",
                   category: "Unicode")

        switch targetOS {
        case .windows:
            sendWindowsHexUnicode(hexStr: hexStr, km: keyboardManager)
        case .linux:
            sendLinuxUnicode(hexStr: hexStr, km: keyboardManager)
        case .macOS:
            sendMacOSUnicode(hexStr: hexStr, km: keyboardManager)
        }
    }

    /// Send a mixed ASCII + Unicode string to the target.
    ///
    /// ASCII printable characters are sent directly via `KeyboardManager`;
    /// non-ASCII characters are sent via `sendChar(_:keyboardManager:)`.
    ///
    /// **Must be called from a background thread.**
    func sendText(_ text: String, keyboardManager: KeyboardManager) {
        for char in text {
            let scalar = char.unicodeScalars.first?.value ?? 0
            if scalar > 0 && scalar <= 0x7E {
                DispatchQueue.main.sync {
                    self.sendASCIIChar(char, km: keyboardManager)
                }
            } else if scalar > 0x7E {
                sendChar(char, keyboardManager: keyboardManager)
            }
            usleep(keyDelayUs) // inter-character gap
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - Windows — Alt + NumPad+ + hex digits
    // ────────────────────────────────────────────────────────────────────────

    /// Windows EnableHexNumpad method:
    /// Hold Alt → press NumPad+ → type 4 hex digits (numpad for 0-9, keyboard for A-F) → release Alt.
    private func sendWindowsHexUnicode(hexStr: String, km: KeyboardManager) {
        // 1. Alt down
        mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: self.kRelease) }
        usleep(keyDelayUs)

        // 2. NumpadPlus while Alt held (triggers hex-input mode)
        mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: [0x57, 0x00, 0x00, 0x00, 0x00, 0x00]) }
        usleep(keyDelayUs)
        mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: self.kRelease) }
        usleep(keyDelayUs)

        // 3. Each hex digit with Alt held
        for hexChar in hexStr.uppercased() {
            guard let code = windowsHexKeyCode(for: hexChar) else { continue }
            mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: [code, 0x00, 0x00, 0x00, 0x00, 0x00]) }
            usleep(keyDelayUs)
            mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: self.kRelease) }
            usleep(keyDelayUs)
        }

        // 4. Release Alt → OS commits the character
        mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: self.kRelease) }
        usleep(commitDelayUs)
    }

    /// Returns the HID key code for a hex digit character in the Windows sequence.
    /// Digits 0–9 use numpad; letters A–F use regular keyboard.
    private func windowsHexKeyCode(for c: Character) -> UInt8? {
        numpadCodes[c] ?? hexLetterCodes[c]
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - macOS — Option (Alt) held + 4 hex digits
    // ────────────────────────────────────────────────────────────────────────

    /// macOS Unicode Hex Input method:
    /// Requires "Unicode Hex Input" keyboard enabled in System Settings → Keyboard → Input Sources.
    /// Hold Option → type exactly 4 hex digits using the number-row / letter keys → release Option.
    private func sendMacOSUnicode(hexStr: String, km: KeyboardManager) {
        // 1. Option (Alt) down
        mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: self.kRelease) }
        usleep(keyDelayUs)

        // 2. Each hex digit while Option is held (regular keyboard row, lowercase)
        for hexChar in hexStr.lowercased() {
            guard let code = regularDigitCodes[hexChar] else { continue }
            mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: [code, 0x00, 0x00, 0x00, 0x00, 0x00]) }
            usleep(keyDelayUs)
            mainSync { km.sendRawHIDReport(modifierByte: self.kAlt, keyCodes: self.kRelease) }
            usleep(keyDelayUs)
        }

        // 3. Release Option → macOS commits the character
        mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: self.kRelease) }
        usleep(commitDelayUs)
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - Linux — Ctrl + Shift + U, hex, Enter
    // ────────────────────────────────────────────────────────────────────────

    /// GTK/IBus Unicode input method:
    /// Press Ctrl+Shift+U → release → type hex digits → press Enter.
    private func sendLinuxUnicode(hexStr: String, km: KeyboardManager) {
        let ctrlShift = kCtrl | kShift   // 0x03

        // 1. Ctrl+Shift+U (U = 0x18)
        mainSync { km.sendRawHIDReport(modifierByte: ctrlShift, keyCodes: [0x18, 0x00, 0x00, 0x00, 0x00, 0x00]) }
        usleep(commitDelayUs)
        mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: self.kRelease) }
        usleep(commitDelayUs)

        // 2. Hex digits (lowercase, regular keys)
        for hexChar in hexStr.lowercased() {
            guard let code = regularDigitCodes[hexChar] else { continue }
            mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: [code, 0x00, 0x00, 0x00, 0x00, 0x00]) }
            usleep(keyDelayUs)
            mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: self.kRelease) }
            usleep(keyDelayUs)
        }

        // 3. Enter (0x28) to commit
        mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: [0x28, 0x00, 0x00, 0x00, 0x00, 0x00]) }
        usleep(commitDelayUs)
        mainSync { km.sendRawHIDReport(modifierByte: 0x00, keyCodes: self.kRelease) }
        usleep(keyDelayUs)
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - ASCII helper (mirrors KeyboardManager.handleTextInput logic)
    // ────────────────────────────────────────────────────────────────────────

    /// Send a single printable ASCII character.  Must be called on the **main thread**.
    private func sendASCIIChar(_ char: Character, km: KeyboardManager) {
        if char.isLetter {
            let key = String(char).uppercased()
            if char.isUppercase {
                km.sendKeyPressAndRelease(modifiers: ["Shift"], key: key)
            } else {
                km.sendKeyPressAndRelease(key: key)
            }
        } else if char == " " {
            km.sendKeyPressAndRelease(key: "Space")
        } else if char == "\n" || char == "\r" {
            km.sendKeyPressAndRelease(key: "Enter")
        } else if char == "\t" {
            km.sendKeyPressAndRelease(key: "Tab")
        } else {
            let shiftSymbols = "!@#$%^&*()_+{}|:\"<>?~"
            if shiftSymbols.contains(char) {
                let shiftMap: [Character: String] = [
                    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
                    "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
                    "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\",
                    ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
                    "~": "`"
                ]
                let baseKey = shiftMap[char] ?? String(char).uppercased()
                km.sendKeyPressAndRelease(modifiers: ["Shift"], key: baseKey)
            } else {
                km.sendKeyPressAndRelease(key: String(char).uppercased())
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // MARK: - Thread helper
    // ────────────────────────────────────────────────────────────────────────

    /// Dispatch a block to the main thread synchronously.
    /// Safe to call from a background thread.
    private func mainSync(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
}
