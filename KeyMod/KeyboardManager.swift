//
//  KeyboardManager.swift
//  KeyMod
//
//  Created on 2025/6/21.
//

import Foundation

class KeyboardManager: ObservableObject {
    var bleManager: BLEManager
    @Published var activeModifiers: Set<String> = []
    @Published var capsLockActive: Bool = false
    @Published var pressedKeys: Set<String> = [] // Track currently pressed keys
    @Published var isGameMode: Bool = false // Track current mode
    let compositeKeyManager: CompositeKeyManager
    private let hapticManager = HapticFeedbackManager.shared
    private let logger = LogManager.shared

    /// Optional handler invoked (on the background thread) when a
    /// `<Macro>label</Macro>` token is encountered in
    /// `handleTextInputWithTokens`. Set by VoiceInputView to resolve
    /// macro-label invocations without introducing a circular dependency.
    var MacroHandler: ((String) -> Void)?

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
        self.compositeKeyManager = CompositeKeyManager()
        self.compositeKeyManager.setKeyboardManager(self)
    }

    // ── BLE key timing helpers ───────────────────────────────────────────────
    /// Inter-key delay in microseconds (reads live from AISettings).
    private var keyDelayUs:    UInt32 { UInt32(AISettings.shared.bleKeyDelayMs) * 1_000 }
    /// Slightly longer delay used after modifier release / character commit.
    private var commitDelayUs: UInt32 { UInt32(AISettings.shared.bleKeyDelayMs + 20) * 1_000 }
    
    // HID keyboard usage codes for common keys
    private let keyboardCodes: [String: UInt8] = [
        // Letters (uppercase)
        "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09,
        "G": 0x0A, "H": 0x0B, "I": 0x0C, "J": 0x0D, "K": 0x0E, "L": 0x0F,
        "M": 0x10, "N": 0x11, "O": 0x12, "P": 0x13, "Q": 0x14, "R": 0x15,
        "S": 0x16, "T": 0x17, "U": 0x18, "V": 0x19, "W": 0x1A, "X": 0x1B,
        "Y": 0x1C, "Z": 0x1D,
        
        // Letters (lowercase) - same codes as uppercase
        "a": 0x04, "b": 0x05, "c": 0x06, "d": 0x07, "e": 0x08, "f": 0x09,
        "g": 0x0A, "h": 0x0B, "i": 0x0C, "j": 0x0D, "k": 0x0E, "l": 0x0F,
        "m": 0x10, "n": 0x11, "o": 0x12, "p": 0x13, "q": 0x14, "r": 0x15,
        "s": 0x16, "t": 0x17, "u": 0x18, "v": 0x19, "w": 0x1A, "x": 0x1B,
        "y": 0x1C, "z": 0x1D,
        
        // Numbers
        "1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21, "5": 0x22,
        "6": 0x23, "7": 0x24, "8": 0x25, "9": 0x26, "0": 0x27,
        
        // Special characters
        "Enter": 0x28, "Escape": 0x29, "Backspace": 0x2A, "Tab": 0x2B,
        "Space": 0x2C, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30,
        "\\": 0x31, ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36,
        ".": 0x37, "/": 0x38, "Caps": 0x39,
        
        // Function keys
        "F1": 0x3A, "F2": 0x3B, "F3": 0x3C, "F4": 0x3D, "F5": 0x3E, "F6": 0x3F,
        "F7": 0x40, "F8": 0x41, "F9": 0x42, "F10": 0x43, "F11": 0x44, "F12": 0x45,
        
        // Additional keys
        "Delete": 0x4C, "Insert": 0x49, "Home": 0x4A, "End": 0x4D,
        "PageUp": 0x4B, "PageDown": 0x4E,
        "PgUp": 0x4B, "PgDn": 0x4E, // Add these aliases
        
        // Arrow keys
        "Right": 0x4F, "Left": 0x50, "Down": 0x51, "Up": 0x52,
        
        // Numpad keys
        "Numpad0": 0x62, "Numpad1": 0x59, "Numpad2": 0x5A, "Numpad3": 0x5B,
        "Numpad4": 0x5C, "Numpad5": 0x5D, "Numpad6": 0x5E, "Numpad7": 0x5F,
        "Numpad8": 0x60, "Numpad9": 0x61, "NumpadDot": 0x63, "NumpadSlash": 0x54,
        "NumpadAsterisk": 0x55, "NumpadMinus": 0x56, "NumpadPlus": 0x57,
        "NumpadEnter": 0x58, "NumpadEquals": 0x67, "NumLock": 0x53,
        
        // Modifier keys (special handling)
        "Ctrl": 0xE0, "Shift": 0xE1, "Alt": 0xE2, "Cmd": 0xE3, "Win": 0xE3
    ]
    
    // Modifier key bitmasks
    private let modifierMasks: [String: UInt8] = [
        "Ctrl": 0x01,   // Left Control
        "Shift": 0x02,  // Left Shift
        "Alt": 0x04,    // Left Alt
        "Cmd": 0x08,    // Left GUI (Command / macOS)
        "Win": 0x08     // Left GUI (Windows / Linux Super key — same HID bit as Cmd)
    ]
    
    // Handle key press events
    func handleKeyPress(_ key: String) {
        logger.log("Key pressed: \(key)", category: "Keyboard")
        
        // Trigger haptic feedback for key press
        hapticManager.triggerButtonPress()
        
        // Handle modifier keys with toggle behavior
        if modifierMasks.keys.contains(key) {
            handleModifierToggle(key)
            return
        }
        
        // Handle Caps Lock
        if key == "Caps" {
            capsLockActive.toggle()
            logger.log("Caps Lock: \(capsLockActive ? "ON" : "OFF")", category: "Keyboard")
            sendCapsLockState()
            return
        }
        
        // Map common aliases to standard names
        let keyAlias = mapKeyAlias(key)
        
        guard let keyCode = keyboardCodes[keyAlias] else {
            logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
            return
        }
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Apply caps lock effect for letters
        if keyAlias.count == 1 && keyAlias.first!.isLetter {
            let shouldBeUppercase = capsLockActive != activeModifiers.contains("Shift")
            if shouldBeUppercase {
                modifierByte |= modifierMasks["Shift"] ?? 0x00
            }
        }
        
        // Send key press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
        
        // Send key release after a short delay (but keep modifiers active)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var releaseModifierByte: UInt8 = 0x00
            for modifier in self.activeModifiers {
                if let modifierMask = self.modifierMasks[modifier] {
                    releaseModifierByte |= modifierMask
                }
            }
            self.sendKeyboardData(modifier: releaseModifierByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    // MARK: - Synchronous macro key sending (called from background thread)

    /// Sends a key press and synchronously waits for its release before returning.
    /// Must be called from a **background** thread. Uses no asyncAfter so the
    /// caller can safely sequence the next key immediately after this returns.
    func sendKeyPressSynchronous(_ key: String) {
        // Press — run on main thread
        DispatchQueue.main.sync {
            logger.log("Key pressed: \(key)", category: "Keyboard")
            hapticManager.triggerButtonPress()
            if modifierMasks.keys.contains(key) { handleModifierToggle(key); return }
            if key == "Caps" { capsLockActive.toggle(); sendCapsLockState(); return }
            let keyAlias = mapKeyAlias(key)
            guard let keyCode = keyboardCodes[keyAlias] else { return }
            var modByte: UInt8 = 0x00
            for m in activeModifiers { modByte |= modifierMasks[m] ?? 0 }
            if keyAlias.count == 1, let ch = keyAlias.first, ch.isLetter {
                if capsLockActive != activeModifiers.contains("Shift") { modByte |= modifierMasks["Shift"] ?? 0 }
            }
            sendKeyboardData(modifier: modByte, keyCodes: [keyCode, 0, 0, 0, 0, 0])
        }
        // Hold for 50 ms on background thread — no main-queue involvement
        usleep(50_000)
        // Release — always send all-zeros. The modifier state in activeModifiers
        // remains for the next key in a sequence; releaseAllKeys() (fired by the
        // closing tag) will send the final all-zeros cleanup report.
        DispatchQueue.main.sync {
            sendKeyboardData(modifier: 0x00, keyCodes: [0, 0, 0, 0, 0, 0])
        }
    }

    /// Add a modifier to activeModifiers **without** sending a BLE report.
    /// Used by token-loop handlers so that modifier tags like <CMD> only
    /// affect the next key press — no standalone modifier-press TX is sent.
    /// Must be called on the main thread.
    func addModifierSilently(_ modifier: String) {
        activeModifiers.insert(modifier)
        logger.log("\(modifier) queued (silent)", category: "Keyboard")
    }

    /// Remove a modifier from activeModifiers without sending a BLE report.
    /// Must be called on the main thread.
    func removeModifierSilently(_ modifier: String) {
        activeModifiers.remove(modifier)
    }

    /// Clear all modifier and key tracking state without sending a BLE report.
    /// Use this in closing-tag handlers (</CMD> etc.) when the physical key-up
    /// was already sent by sendKeyPressSynchronous, so no duplicate TX is needed.
    /// Must be called on the main thread.
    func clearKeyStateSilently() {
        activeModifiers.removeAll()
        pressedKeys.removeAll()
        logger.log("Key state cleared (silent)", category: "Keyboard")
    }

    /// Sends a key combo (modifier + key) synchronously from a background thread.
    /// After releasing the key, restores the BLE modifier state to whatever
    /// activeModifiers currently holds — so that an outer <CMD>…</CMD> block
    /// keeps its modifier active until the closing tag fires releaseAllKeys().
    func sendKeyComboSynchronous(modifiers: [String], key: String) {
        DispatchQueue.main.sync {
            logger.log("Key combo: \(modifiers.joined(separator: "+"))+\(key)", category: "Keyboard")
            guard let keyCode = keyboardCodes[key] else { return }
            var modByte: UInt8 = 0x00
            for m in modifiers { modByte |= modifierMasks[m] ?? 0 }
            sendKeyboardData(modifier: modByte, keyCodes: [keyCode, 0, 0, 0, 0, 0])
        }
        usleep(50_000)
        DispatchQueue.main.sync {
            // Always release to all-zeros. activeModifiers retains the modifier
            // state for subsequent keys; releaseAllKeys() on </TAG> cleans up.
            sendKeyboardData(modifier: 0x00, keyCodes: [0, 0, 0, 0, 0, 0])
        }
    }

    // Handle modifier key toggling
    public func handleModifierToggle(_ modifier: String) {
        if activeModifiers.contains(modifier) {
            activeModifiers.remove(modifier)
            logger.log("\(modifier) released", category: "Keyboard")
        } else {
            activeModifiers.insert(modifier)
            logger.log("\(modifier) pressed", category: "Keyboard")
        }
        
        // Send current modifier state
        var modifierByte: UInt8 = 0x00
        for activeModifier in activeModifiers {
            if let modifierMask = modifierMasks[activeModifier] {
                modifierByte |= modifierMask
            }
        }
        
        sendKeyboardData(modifier: modifierByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
    
    // Send caps lock state
    private func sendCapsLockState() {
        let capsKeyCode = keyboardCodes["Caps"] ?? 0x39
        let keyCodes: [UInt8] = [capsKeyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        sendKeyboardData(modifier: 0x00, keyCodes: keyCodes)
        
        // Release caps lock key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    // Handle key combinations (e.g., Ctrl+C)
    func handleKeyCombo(modifiers: [String], key: String) {
        logger.log("Key combo: \(modifiers.joined(separator: "+"))+\(key)", category: "Keyboard")
        
        guard let keyCode = keyboardCodes[key] else {
            logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
            return
        }
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply modifiers
        for modifier in modifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Send key combo press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
        
        // Send key release after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }
    
    /// Send a raw HID keyboard report directly.
    /// Must be called from the main thread. Used by UnicodeManager for multi-step
    /// sequences (e.g., Windows Alt+NumPad hex input, Linux Ctrl+Shift+U).
    func sendRawHIDReport(modifierByte: UInt8, keyCodes: [UInt8]) {
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
    }

    // Send keyboard data via BLE
    private func sendKeyboardData(modifier: UInt8, keyCodes: [UInt8]) {
        // HID keyboard report format:
        // [Report ID, Modifier, Reserved, Key1, Key2, Key3, Key4, Key5, Key6]
        var dataPacket: [UInt8] = getDataPacketHeader() // Use dynamic header based on mode
        dataPacket.append(modifier)
        dataPacket.append(0x00) // Reserved byte
        dataPacket.append(contentsOf: keyCodes)
        
        // Calculate checksum
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        
        bleManager.sendTouchData(data: Data(dataPacket))
    }
    
    // Handle special keys that might need different behavior
    func handleSpecialKey(_ key: String) {
        switch key {
        case "Esc":
            handleKeyPress("Escape")
        case "Caps":
            handleKeyPress("Caps")
        default:
            handleKeyPress(key)
        }
    }
    
    // Handle text input (for typing strings)
    func handleTextInput(_ text: String) {
        logger.log("Starting text input: \(text)", category: "Keyboard")
        logger.logCheckpoint("Text input started", category: "Keyboard")
        
        DispatchQueue.global(qos: .userInitiated).async {
            for char in text {
                let scalar = char.unicodeScalars.first?.value ?? 0
                // Non-ASCII Unicode — delegate to UnicodeManager (already on bg thread)
                if scalar > 0x7E {
                    UnicodeManager.shared.sendChar(char, keyboardManager: self)
                    usleep(self.keyDelayUs)
                    continue
                }
                // Press and release key synchronously
                DispatchQueue.main.sync {
                    if char.isLetter {
                        let key = String(char).uppercased()
                        if char.isUppercase {
                            self.sendKeyPressAndRelease(modifiers: ["Shift"], key: key)
                        } else {
                            self.sendKeyPressAndRelease(key: key)
                        }
                    } else if char == " " {
                        self.sendKeyPressAndRelease(key: "Space")
                    } else if char == "\n" || char == "\r" {
                        self.sendKeyPressAndRelease(key: "Enter")
                    } else if char == "\t" {
                        self.sendKeyPressAndRelease(key: "Tab")
                    } else {
                        let needsShift = "!@#$%^&*()_+{}|:\"<>?~".contains(char)
                        
                        if needsShift {
                            let shiftedChar = self.getShiftedCharacter(char)
                            self.sendKeyPressAndRelease(modifiers: ["Shift"], key: shiftedChar)
                        } else {
                            let key = String(char).uppercased()
                            self.sendKeyPressAndRelease(key: key)
                        }
                    }
                }
                // Wait between characters for proper timing
                usleep(self.keyDelayUs)
            }
            
            DispatchQueue.main.async {
                self.logger.logCheckpoint("Text input completed", category: "Keyboard")
            }
        }
    }
    
    /// Send a complete key press and release cycle synchronously.
    /// Internal so that UnicodeManager can use it from a background thread.
    func sendKeyPressAndRelease(modifiers: [String] = [], key: String) {
        guard let keyCode = keyboardCodes[key] else {
            logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
            return
        }
        
        logger.log("Key pressed: \(key)", category: "Keyboard")
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply modifiers
        for modifier in modifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Send key press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)
        
        // Wait 100ms for key to be held
        usleep(commitDelayUs)
        
        // Send key release
        sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
    
    /// Send a single printable ASCII character, handling case, space, enter, tab,
    /// and shift-symbols correctly. Must be called on the **main thread**.
    func sendASCIICharInline(_ char: Character) {
        if char.isLetter {
            let key = String(char).uppercased()
            if char.isUppercase {
                sendKeyPressAndRelease(modifiers: ["Shift"], key: key)
            } else {
                sendKeyPressAndRelease(key: key)
            }
        } else if char == " " {
            sendKeyPressAndRelease(key: "Space")
        } else if char == "\n" || char == "\r" {
            sendKeyPressAndRelease(key: "Enter")
        } else if char == "\t" {
            sendKeyPressAndRelease(key: "Tab")
        } else {
            let shiftSymbols = "!@#$%^&*()_+{}|:\"<>?~"
            if shiftSymbols.contains(char) {
                let baseKey = getShiftedCharacter(char)
                sendKeyPressAndRelease(modifiers: ["Shift"], key: baseKey)
            } else {
                sendKeyPressAndRelease(key: String(char).uppercased())
            }
        }
    }

    // Convenience methods for common actions
    func sendCopy() {
        handleKeyCombo(modifiers: ["Cmd"], key: "C")
    }
    
    func sendPaste() {
        handleKeyCombo(modifiers: ["Cmd"], key: "V")
    }
    
    func sendCut() {
        handleKeyCombo(modifiers: ["Cmd"], key: "X")
    }
    
    func sendUndo() {
        handleKeyCombo(modifiers: ["Cmd"], key: "Z")
    }
    
    func sendSelectAll() {
        handleKeyCombo(modifiers: ["Cmd"], key: "A")
    }
    
    // Additional common shortcuts
    func sendRedo() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "Y")
    }
    
    func sendFind() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "F")
    }
    
    func sendSave() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "S")
    }
    
    func sendNew() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "N")
    }
    
    func sendOpen() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "O")
    }
    
    func sendNewTab() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "T")
    }
    
    func sendCloseTab() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "W")
    }
    
    func sendNextTab() {
        handleKeyCombo(modifiers: ["Ctrl"], key: "Tab")
    }
    
    // System shortcuts
    func sendAltF4() {
        handleKeyCombo(modifiers: ["Alt"], key: "F4")
    }
    
    func sendCtrlAltDel() {
        handleKeyCombo(modifiers: ["Ctrl", "Alt"], key: "Delete")
    }
    
    func sendWinL() {
        handleKeyCombo(modifiers: ["Cmd"], key: "L")
    }
    
    func sendWinD() {
        handleKeyCombo(modifiers: ["Cmd"], key: "D")
    }
    
    func clearAllModifiers() {
        activeModifiers.removeAll()
        sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        print("All modifiers cleared")
    }
    
    // Map shifted characters to their base keys
    private func getShiftedCharacter(_ char: Character) -> String {
        let shiftMap: [Character: String] = [
            "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
            "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
            "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\",
            ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
            "~": "`"
        ]
        
        return shiftMap[char] ?? String(char).uppercased()
    }
    
    // MARK: - Gamepad Key Control Methods
    
    // Handle key press down (without auto-release) - supports single key
    func handleKeyDown(_ key: String) {
        handleKeysDown([key])
    }
    
    // Handle multiple keys press down simultaneously (for composite directions)
    func handleKeysDown(_ keys: [String]) {
        logger.log("Keys down: \(keys.joined(separator: ", "))", category: "Keyboard")
        
        var modifierByte: UInt8 = 0x00
        
        // Process each key
        for key in keys {
            // Handle modifier keys with toggle behavior
            if modifierMasks.keys.contains(key) {
                if !activeModifiers.contains(key) {
                    activeModifiers.insert(key)
                    logger.log("\(key) pressed", category: "Keyboard")
                }
                continue
            }
            
            // Handle Caps Lock
            if key == "Caps" {
                capsLockActive.toggle()
                logger.log("Caps Lock: \(capsLockActive ? "ON" : "OFF")", category: "Keyboard")
                sendCapsLockState()
                continue
            }
            
            // Map common aliases to standard names
            let keyAlias = mapKeyAlias(key)
            
            guard keyboardCodes[keyAlias] != nil else {
                logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
                continue
            }
            
            // Add to pressed keys set
            pressedKeys.insert(keyAlias)
        }
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Apply caps lock effect for letters in the key list
        for key in keys {
            let keyAlias = mapKeyAlias(key)
            if keyAlias.count == 1 && keyAlias.first!.isLetter {
                let shouldBeUppercase = capsLockActive != activeModifiers.contains("Shift")
                if shouldBeUppercase {
                    modifierByte |= modifierMasks["Shift"] ?? 0x00
                }
                break // Only need to apply once
            }
        }
        
        // Build key codes array with ALL currently pressed keys (up to 6 keys can be pressed simultaneously in HID)
        var keyCodesToSend: [UInt8] = []
        for pressedKey in pressedKeys {
            if let keyCode = keyboardCodes[pressedKey], keyCodesToSend.count < 6 {
                keyCodesToSend.append(keyCode)
            }
        }
        
        // Pad key codes array to 6 elements
        while keyCodesToSend.count < 6 {
            keyCodesToSend.append(0x00)
        }
        
        // Send key press (stay pressed until explicitly released)
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodesToSend)
    }
    
    // Handle key release - supports single key
    func handleKeyUp(_ key: String) {
        handleKeysUp([key])
    }
    
    // Handle multiple keys release simultaneously
    func handleKeysUp(_ keys: [String]) {
        logger.log("Keys up: \(keys.joined(separator: ", "))", category: "Keyboard")
        
        // Process each key
        for key in keys {
            // Handle modifier keys
            if modifierMasks.keys.contains(key) {
                if activeModifiers.contains(key) {
                    activeModifiers.remove(key)
                    logger.log("\(key) released", category: "Keyboard")
                }
                continue
            }
            
            // Map common aliases to standard names
            let keyAlias = mapKeyAlias(key)
            
            // Remove from pressed keys set
            pressedKeys.remove(keyAlias)
        }
        
        // Send key release with current state of all remaining pressed keys
        var keyCodesToSend: [UInt8] = []
        var modifierByte: UInt8 = 0x00
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMasks[modifier] {
                modifierByte |= modifierMask
            }
        }
        
        // Add remaining pressed keys (excluding the ones we're releasing)
        for pressedKey in pressedKeys {
            if let keyCode = keyboardCodes[pressedKey], keyCodesToSend.count < 6 {
                keyCodesToSend.append(keyCode)
            }
        }
        
        // Pad key codes array to 6 elements
        while keyCodesToSend.count < 6 {
            keyCodesToSend.append(0x00)
        }
        
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodesToSend)
    }
    
    // Helper method to map key aliases
    private func mapKeyAlias(_ key: String) -> String {
        switch key {
        case "↑": return "Up"
        case "↓": return "Down"
        case "←": return "Left"
        case "→": return "Right"
        case "PgUp": return "PageUp"
        case "PgDn": return "PageDown"
        case "Home", "home": return "Home"
        case "End", "end": return "End"
        default: return key
        }
    }
    
    // Release all currently pressed keys
    func releaseAllKeys() {
        pressedKeys.removeAll()
        activeModifiers.removeAll()
        sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        logger.log("All keys released", category: "Keyboard")
    }
    
    // Check if a key is currently pressed
    func isKeyPressed(_ key: String) -> Bool {
        let keyAlias = mapKeyAlias(key)
        return pressedKeys.contains(keyAlias) || activeModifiers.contains(keyAlias)
    }
    
    // MARK: - Text Input with Special Token Support
    
    /// Parse and handle text input with special tokens (e.g., <CTRL>, <SHIFT>, <ALT>, <CMD>, <F1>-<F12>)
    /// Supports composite keys: <CTRL>A</CTRL> means press Ctrl, press A, release all
    func handleTextInputWithTokens(_ text: String) {
        // ── Pre-process <Macro>label</Macro> blocks ────────────────
        // Replace each block with a deterministic uppercase placeholder so the
        // main tokenizer (which only accepts uppercase tags) can handle them.
        var MacroMap: [String: String] = [:] // placeholder → label
        var processedText = text
        let mlPattern = try? NSRegularExpression(pattern: "<Macro>([\\s\\S]*?)</Macro>", options: .caseInsensitive)
        var mlIndex = 0
        if let mlPattern = mlPattern {
            let nsRaw = text as NSString
            let mlMatches = mlPattern.matches(in: text, range: NSRange(location: 0, length: nsRaw.length))
            for match in mlMatches.reversed() {
                let label = nsRaw.substring(with: match.range(at: 1))
                let placeholder = "<MLABEL\(mlIndex)>"
                MacroMap[placeholder] = label
                mlIndex += 1
                let before = (processedText as NSString).substring(to: match.range.location)
                let after  = (processedText as NSString).substring(from: match.range.location + match.range.length)
                processedText = before + placeholder + after
            }
        }

        let tokens = tokenizeInput(processedText)

        // Run on a background thread so that non-ASCII characters (sent via
        // UnicodeManager, which blocks with usleep()) and ASCII characters are
        // processed in strict sequence — preventing reordering like "你K好EV" → "KEV你好".
        DispatchQueue.global(qos: .userInitiated).async {
            var activeModifiers: [String] = []

            for token in tokens {
                // Handle <Macro>...</Macro> placeholders — blocks until sub-macro finishes
                if let label = MacroMap[token] {
                    self.MacroHandler?(label)
                }
                // Handle closing tags - clear tracked state only.
                // Physical key-up (0x00) was already sent by sendKeyPressSynchronous.
                else if token.hasPrefix("</") && token.hasSuffix(">") {
                    DispatchQueue.main.sync { self.clearKeyStateSilently() }
                    activeModifiers.removeAll()
                }
                // Handle opening modifier tags
                else if token == "<CTRL>" || token == "<SHIFT>" || token == "<ALT>" || token == "<CMD>" || token == "<WIN>" {
                    let modifier: String
                    switch token {
                    case "<CTRL>":  modifier = "Ctrl"
                    case "<SHIFT>": modifier = "Shift"
                    case "<ALT>":   modifier = "Alt"
                    case "<CMD>":   modifier = "Cmd"
                    case "<WIN>":   modifier = "Win"
                    default:        modifier = ""
                    }
                    if !modifier.isEmpty {
                        // Silently track — no standalone BLE modifier press.
                        DispatchQueue.main.sync { self.addModifierSilently(modifier) }
                        activeModifiers.append(modifier)
                    }
                }
                // Handle delay tokens
                else if token == "<DELAY1S>" || token == "<DELAY2S>" || token == "<DELAY5S>" || token == "<DELAY10S>" {
                    switch token {
                    case "<DELAY1S>":  usleep(1_000_000)
                    case "<DELAY2S>":  usleep(2_000_000)
                    case "<DELAY5S>":  usleep(5_000_000)
                    default:           usleep(10_000_000)
                    }
                }
                // Handle special tokens (arrow keys, Enter, Esc, etc.)
                // Use synchronous send so the release is guaranteed before the next token.
                else if self.isSpecialToken(token) {
                    let key = self.specialTokenToKeyName(token)
                    if !key.isEmpty {
                        if activeModifiers.isEmpty {
                            self.sendKeyPressSynchronous(key)
                        } else {
                            self.sendKeyComboSynchronous(modifiers: activeModifiers, key: key)
                        }
                    }
                }
                // Regular text
                else if token.count == 1 {
                    if let char = token.first, char.unicodeScalars.first.map({ $0.value }) ?? 0 > 0x7E {
                        UnicodeManager.shared.sendChar(char, keyboardManager: self)
                    } else if activeModifiers.isEmpty {
                        DispatchQueue.main.sync {
                            if let char = token.first {
                                self.sendASCIICharInline(char)
                            }
                        }
                    } else {
                        // sendKeyPressSynchronous already reads activeModifiers for both
                        // press and restore-release, so no need to pass them explicitly.
                        // Uppercase letters still need Shift in the modifier byte; the
                        // synchronous helper handles that via the existing modifierByte logic.
                        self.sendKeyPressSynchronous(token.uppercased())
                    }
                } else {
                    // Multiple characters - send each
                    for char in token {
                        let charStr = String(char)
                        if char.unicodeScalars.first.map({ $0.value }) ?? 0 > 0x7E {
                            UnicodeManager.shared.sendChar(char, keyboardManager: self)
                        } else if activeModifiers.isEmpty {
                            DispatchQueue.main.sync {
                                self.sendASCIICharInline(char)
                            }
                        } else {
                            self.sendKeyPressSynchronous(charStr.uppercased())
                        }
                        usleep(self.keyDelayUs)
                    }
                }
                // Inter-token gap. Skip for delay tokens (already slept) and
                // multi-char tokens (per-char gap applied above).
                let isDelayToken = token == "<DELAY1S>" || token == "<DELAY2S>" || token == "<DELAY5S>" || token == "<DELAY10S>"
                if !isDelayToken && (token.count <= 1 || self.isSpecialToken(token)) {
                    usleep(self.keyDelayUs)
                }
            }

            // Safety-net release: only send if something is still held.
            // Normal sequences clear state via closing tags (</CMD> etc.);
            // this only fires for malformed input with unclosed modifier tags.
            DispatchQueue.main.sync {
                if !self.activeModifiers.isEmpty || !self.pressedKeys.isEmpty {
                    self.releaseAllKeys()
                }
            }
        }
    }
    
    /// Tokenize input string to separate special tokens from regular text
    private func tokenizeInput(_ text: String) -> [String] {
        // [A-Z0-9]+ covers mixed tokens like DELAY1S, DELAY10S, MLABEL0, F12 etc.
        let pattern = "</?[A-Z0-9]+>|."
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        var result: [String] = []
        
        if let regex = regex {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let token = nsText.substring(with: match.range)
                result.append(token)
            }
        } else {
            result = text.map { String($0) }
        }
        
        return result
    }
    
    /// Map a special token like "<LEFT>" to a key name like "Left" for use with
    /// sendKeyPressSynchronous / sendKeyComboSynchronous.
    /// Returns an empty string for tokens that are not recognised.
    func specialTokenToKeyName(_ token: String) -> String {
        let content = String(token.dropFirst().dropLast()).uppercased()
        switch content {
        case "ENTER":     return "Enter"
        case "ESC":       return "Escape"
        case "BACK":      return "Backspace"
        case "TAB":       return "Tab"
        case "SPACE":     return "Space"
        case "LEFT":      return "Left"
        case "RIGHT":     return "Right"
        case "UP":        return "Up"
        case "DOWN":      return "Down"
        case "HOME":      return "Home"
        case "END":       return "End"
        case "PAGEUP", "PGUP":  return "PageUp"
        case "PAGEDOWN", "PGDN": return "PageDown"
        case "INSERT":    return "Insert"
        case "DELETE":    return "Delete"
        case "F1":  return "F1";  case "F2":  return "F2";  case "F3":  return "F3"
        case "F4":  return "F4";  case "F5":  return "F5";  case "F6":  return "F6"
        case "F7":  return "F7";  case "F8":  return "F8";  case "F9":  return "F9"
        case "F10": return "F10"; case "F11": return "F11"; case "F12": return "F12"
        default:          return ""
        }
    }

    /// Check if a token is a special token (e.g., <CTRL>, <SHIFT>, etc.)
    private func isSpecialToken(_ token: String) -> Bool {
        return token.hasPrefix("<") && token.hasSuffix(">") && !token.hasPrefix("</")
    }
    
    /// Handle special tokens with optional active modifiers
    private func handleSpecialTokenWithModifiers(_ token: String, modifiers: [String]) {
        let content = String(token.dropFirst().dropLast()).uppercased()  // Remove < > and uppercase
        
        switch content {
        case "ENTER":
            if modifiers.isEmpty {
                handleKeyPress("Enter")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Enter")
            }
        case "ESC":
            if modifiers.isEmpty {
                handleKeyPress("Escape")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Escape")
            }
        case "BACK":
            if modifiers.isEmpty {
                handleKeyPress("Backspace")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Backspace")
            }
        case "TAB":
            if modifiers.isEmpty {
                handleKeyPress("Tab")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Tab")
            }
        case "SPACE":
            if modifiers.isEmpty {
                handleKeyPress("Space")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Space")
            }
        case "LEFT":
            if modifiers.isEmpty {
                handleKeyPress("Left")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Left")
            }
        case "RIGHT":
            if modifiers.isEmpty {
                handleKeyPress("Right")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Right")
            }
        case "UP":
            if modifiers.isEmpty {
                handleKeyPress("Up")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Up")
            }
        case "DOWN":
            if modifiers.isEmpty {
                handleKeyPress("Down")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Down")
            }
        case "HOME":
            if modifiers.isEmpty {
                handleKeyPress("Home")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Home")
            }
        case "END":
            if modifiers.isEmpty {
                handleKeyPress("End")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "End")
            }
        case "DELETE", "DEL":
            if modifiers.isEmpty {
                handleKeyPress("Delete")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "Delete")
            }
        case "PAGEUP", "PGUP":
            if modifiers.isEmpty {
                handleKeyPress("PageUp")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "PageUp")
            }
        case "PAGEDOWN", "PGDN":
            if modifiers.isEmpty {
                handleKeyPress("PageDown")
            } else {
                handleKeyCombo(modifiers: modifiers, key: "PageDown")
            }
        default:
            // Handle function keys F1-F12
            if content.hasPrefix("F") && content.dropFirst().allSatisfy({ $0.isNumber }) {
                if modifiers.isEmpty {
                    handleKeyPress(content)
                } else {
                    handleKeyCombo(modifiers: modifiers, key: content)
                }
            } else {
                logger.log("⚠️ Unknown special token: \(token)", category: "Keyboard", level: .warning)
            }
        }
    }
    
    /// Handle special tokens like <CTRL>, <SHIFT>, <ALT>, <CMD>, <F1>-<F12>, <ENTER>, etc.
    private func handleSpecialToken(_ token: String) {
        handleSpecialTokenWithModifiers(token, modifiers: [])
    }
    
    // MARK: - Mode Management
    
    // Switch to game mode (for gamepad view)
    func switchToGameMode() {
        isGameMode = true
        logger.log("Switched to Game Mode", category: "Keyboard")
    }
    
    // Switch to normal keyboard mode
    func switchToNormalMode() {
        isGameMode = false
        logger.log("Switched to Normal Mode", category: "Keyboard")
    }
    
    // Get the appropriate data packet header based on current mode
    private func getDataPacketHeader() -> [UInt8] {
        if isGameMode {
            return [0x57, 0xAB, 0x00, 0x12, 0x08] // Game mode header
        } else {
            return [0x57, 0xAB, 0x00, 0x02, 0x08] // Normal mode header
        }
    }
    
    // Get current mode description
    func getCurrentModeDescription() -> String {
        return isGameMode ? "Game Mode" : "Normal Mode"
    }
    
    // Get current data packet header for debugging
    func getCurrentDataPacketHeader() -> [UInt8] {
        return getDataPacketHeader()
    }
}
