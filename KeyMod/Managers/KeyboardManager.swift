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
    @Published var lockedModifiers: Set<String> = []
    @Published var capsLockActive: Bool = false
    @Published var pressedKeys: Set<String> = [] // Track currently pressed keys
    @Published var isGameMode: Bool = false // Track current mode
    @Published var isFnLocked: Bool = false // Fn lock for F1-F12 mapping
    @Published var isSymbolMode: Bool = false // Symbol mode keyboard layout
    @Published var isSending: Bool = false    // True while handleTextInput is in-flight
    private var sendCancelFlag = false
    private let sendLock = NSLock()
    let compositeKeyManager: CompositeKeyManager
    private let hapticManager = HapticFeedbackManager.shared
    private let logger = LogManager.shared

    /// Fn lock mapping: letter key → F-key (matches Android CustomKeyboardView.resolveFnMapping)
    let fnMapping: [String: String] = [
        "q": "F1", "w": "F2", "e": "F3", "r": "F4", "t": "F5",
        "y": "F6", "u": "F7", "i": "F8", "o": "F9", "p": "F10",
        "a": "F11", "s": "F12"
    ]

    /// Key alternates definition matching Android XML keyAlternates attributes.
    /// Each entry: (label, symbolLabel, alternates, cornerHint)
    struct KeyDef {
        let label: String
        let symbolLabel: String
        let alternates: [String]  // ordered list of alternate chars
        let cornerHint: String
        let keyCode: String      // base key name for HID lookup
        let requiresShift: Bool  // true if this key needs shift modifier

        init(_ label: String, _ symbolLabel: String = "", _ alternates: [String] = [], _ cornerHint: String = "", _ keyCode: String? = nil, _ requiresShift: Bool = false) {
            self.label = label
            self.symbolLabel = symbolLabel
            self.alternates = alternates
            self.cornerHint = cornerHint
            self.keyCode = keyCode ?? label
            self.requiresShift = requiresShift
        }
    }

    /// Portrait letter key definitions with alternates
    /// Matches Android keyboard_lower_portrait_no_gui.xml (4 rows)
    let portraitLetterKeys: [[KeyDef]] = [
        [ // Row 1: q-p (10 letter keys, equal width)
            KeyDef("q", "Q", ["!", "1"], "!", "q"),
            KeyDef("w", "W", ["@", "2"], "@", "w"),
            KeyDef("e", "E", ["#", "3"], "#", "e"),
            KeyDef("r", "R", ["$", "4"], "$", "r"),
            KeyDef("t", "T", ["%", "5"], "%", "t"),
            KeyDef("y", "Y", ["^", "6"], "^", "y"),
            KeyDef("u", "U", ["&", "7"], "&", "u"),
            KeyDef("i", "I", ["*", "8"], "*", "i"),
            KeyDef("o", "O", [",", "9"], ",", "o"),
            KeyDef("p", "P", [".", "0"], ".", "p")
        ],
        [ // Row 2: Tab + a-l + Forward Delete
            KeyDef("Tab", "", [], "", "Tab"),
            KeyDef("a", "A", ["¥", "", "£", "€"], "¥", "a"),
            KeyDef("s", "S", ["", "", "`", "~"], "`", "s"),
            KeyDef("d", "D", ["", "-", "_"], "-", "d"),
            KeyDef("f", "F", ["", "+", "="], "+", "f"),
            KeyDef("g", "G", ["", "/", "?"], "/", "g"),
            KeyDef("h", "H", ["", "<", ">"], "<", "h"),
            KeyDef("j", "J", ["", "[", "]"], "[", "j"),
            KeyDef("k", "K", ["", "{", "}"], "{", "k"),
            KeyDef("l", "L", ["", "(", ")"], "(", "l"),
            KeyDef("Backspace", "", [], "", "Backspace")
        ],
        [ // Row 3: Shift + z-m + / + Enter
            KeyDef("Shift", "", [], "", "Shift"),
            KeyDef("z", "Z", ["'", "", ","], "'", "z"),
            KeyDef("x", "X", ["\""], "\"", "x"),
            KeyDef("c", "C", [";"], ";", "c"),
            KeyDef("v", "V", [":"], ":", "v"),
            KeyDef("b", "B", ["/"], "/", "b"),
            KeyDef("n", "N", ["|"], "|", "n"),
            KeyDef("m", "M", ["\\"], "\\", "m"),
            KeyDef("/", "?", ["?"], "?", "/"),
            KeyDef("Enter", "", [], "", "Enter")
        ],
        [ // Row 4: Fn + Ctrl + Space + Alt + Win
            KeyDef("Fn", "", [], "", "Fn"),
            KeyDef("Ctrl", "", [], "", "Ctrl"),
            KeyDef("Space", "", [], "", "Space"),
            KeyDef("Alt", "", [], "", "Alt"),
            KeyDef("Win", "", [], "", "Win")
        ]
    ]

    /// Windows-style portrait layout (target_os == "windows")
    /// Row 1: Esc F1-F12 (short height)
    let portraitWindowsFRow: [KeyDef] = [
        KeyDef("Esc", "", [], "", "Esc"),
        KeyDef("F1", "", [], "", "F1"),
        KeyDef("F2", "", [], "", "F2"),
        KeyDef("F3", "", [], "", "F3"),
        KeyDef("F4", "", [], "", "F4"),
        KeyDef("F5", "", [], "", "F5"),
        KeyDef("F6", "", [], "", "F6"),
        KeyDef("F7", "", [], "", "F7"),
        KeyDef("F8", "", [], "", "F8"),
        KeyDef("F9", "", [], "", "F9"),
        KeyDef("F10", "", [], "", "F10"),
        KeyDef("F11", "", [], "", "F11"),
        KeyDef("F12", "", [], "", "F12")
    ]

    /// Row 2: ` 1 2 3 4 5 6 7 8 9 0 - = Backspace (short height)
    let portraitWindowsNumberRow: [KeyDef] = [
        KeyDef("`", "~", [], "`", "`"),
        KeyDef("1", "!", [], "1", "1"),
        KeyDef("2", "@", [], "2", "2"),
        KeyDef("3", "#", [], "3", "3"),
        KeyDef("4", "$", [], "4", "4"),
        KeyDef("5", "%", [], "5", "5"),
        KeyDef("6", "^", [], "6", "6"),
        KeyDef("7", "&", [], "7", "7"),
        KeyDef("8", "*", [], "8", "8"),
        KeyDef("9", "(", [], "9", "9"),
        KeyDef("0", ")", [], "0", "0"),
        KeyDef("-", "_", [], "-", "-"),
        KeyDef("=", "+", [], "=", "="),
        KeyDef("Backspace", "", [], "", "Backspace")
    ]

    /// Row 3: Tab q w e r t y u i o p [ ] \ (normal height)
    let portraitWindowsRow3: [KeyDef] = [
        KeyDef("Tab", "", [], "", "Tab"),
        KeyDef("q", "Q", [], "q", "q"),
        KeyDef("w", "W", [], "w", "w"),
        KeyDef("e", "E", [], "e", "e"),
        KeyDef("r", "R", [], "r", "r"),
        KeyDef("t", "T", [], "t", "t"),
        KeyDef("y", "Y", [], "y", "y"),
        KeyDef("u", "U", [], "u", "u"),
        KeyDef("i", "I", [], "i", "i"),
        KeyDef("o", "O", [], "o", "o"),
        KeyDef("p", "P", [], "p", "p"),
        KeyDef("[", "{", [], "[", "["),
        KeyDef("]", "}", [], "]", "]"),
        KeyDef("\\", "|", [], "\\", "\\")
    ]

    /// Row 4: Caps a s d f g h j k l ; ' Enter (normal height)
    let portraitWindowsRow4: [KeyDef] = [
        KeyDef("Caps", "", [], "", "Caps"),
        KeyDef("a", "A", [], "a", "a"),
        KeyDef("s", "S", [], "s", "s"),
        KeyDef("d", "D", [], "d", "d"),
        KeyDef("f", "F", [], "f", "f"),
        KeyDef("g", "G", [], "g", "g"),
        KeyDef("h", "H", [], "h", "h"),
        KeyDef("j", "J", [], "j", "j"),
        KeyDef("k", "K", [], "k", "k"),
        KeyDef("l", "L", [], "l", "l"),
        KeyDef(";", ":", [], ";", ";"),
        KeyDef("'", "\"", [], "'", "'"),
        KeyDef("Enter", "", [], "", "Enter")
    ]

    /// Row 5: Shift z x c v b n m , . / Shift Up (normal height, Up arrow occupies rightmost slot)
    let portraitWindowsRow5: [KeyDef] = [
        KeyDef("Shift", "", [], "", "Shift"),
        KeyDef("z", "Z", [], "z", "z"),
        KeyDef("x", "X", [], "x", "x"),
        KeyDef("c", "C", [], "c", "c"),
        KeyDef("v", "V", [], "v", "v"),
        KeyDef("b", "B", [], "b", "b"),
        KeyDef("n", "N", [], "n", "n"),
        KeyDef("m", "M", [], "m", "m"),
        KeyDef(",", "<", [], ",", ","),
        KeyDef(".", ">", [], ".", "."),
        KeyDef("/", "?", [], "/", "/"),
        KeyDef("Shift", "", [], "", "Shift"),
        KeyDef("Up", "", [], "↑", "Up")
    ]

    /// Row 6: Ctrl Win Alt Space Alt Ctrl Left Down Right (normal height)
    let portraitWindowsRow6: [KeyDef] = [
        KeyDef("Ctrl", "", [], "", "Ctrl"),
        KeyDef("Win", "", [], "", "Win"),
        KeyDef("Alt", "", [], "", "Alt"),
        KeyDef("Space", "", [], "", "Space"),
        KeyDef("Alt", "", [], "", "Alt"),
        KeyDef("Ctrl", "", [], "", "Ctrl"),
        KeyDef("Left", "", [], "←", "Left"),
        KeyDef("Down", "", [], "↓", "Down"),
        KeyDef("Right", "", [], "→", "Right")
    ]

    // MARK: - Landscape Key Definitions (matches Android keyboard_lower_landscape_no_gui_*.xml)

    /// macOS landscape layout — symmetrical bottom row: Ctrl + Opt + Cmd + Space + Cmd + Opt + Ctrl
    /// Matches Android keyboard_lower_landscape_no_gui.xml
    let landscapeMacKeys: [[KeyDef]] = [
        [ // Row 1: Tab + q-p + Backspace
            KeyDef("Tab", "", [], "", "Tab"),
            KeyDef("q", "Q", ["!", "1"], "!", "q"),
            KeyDef("w", "W", ["@", "2"], "@", "w"),
            KeyDef("e", "E", ["#", "3"], "#", "e"),
            KeyDef("r", "R", ["$", "4"], "$", "r"),
            KeyDef("t", "T", ["%", "5"], "%", "t"),
            KeyDef("y", "Y", ["^", "6"], "^", "y"),
            KeyDef("u", "U", ["&", "7"], "&", "u"),
            KeyDef("i", "I", ["*", "8"], "*", "i"),
            KeyDef("o", "O", [",", "9"], ",", "o"),
            KeyDef("p", "P", [".", "0"], ".", "p"),
            KeyDef("Backspace", "", [], "", "Backspace")
        ],
        [ // Row 2: Fn + a-l + Delete
            KeyDef("Fn", "", [], "", "Fn"),
            KeyDef("a", "A", ["¥", "", "£", "€"], "¥", "a"),
            KeyDef("s", "S", ["", "", "`", "~"], "`", "s"),
            KeyDef("d", "D", ["", "-", "_"], "-", "d"),
            KeyDef("f", "F", ["", "+", "="], "+", "f"),
            KeyDef("g", "G", ["", "/", "?"], "/", "g"),
            KeyDef("h", "H", ["", "<", ">"], "<", "h"),
            KeyDef("j", "J", ["", "[", "]"], "[", "j"),
            KeyDef("k", "K", ["", "{", "}"], "{", "k"),
            KeyDef("l", "L", ["", "(", ")"], "(", "l"),
            KeyDef("Delete", "", [], "", "Delete")
        ],
        [ // Row 3: Shift + z-m + / + Enter
            KeyDef("Shift", "", [], "", "Shift"),
            KeyDef("z", "Z", ["'", "", ","], "'", "z"),
            KeyDef("x", "X", ["\""], "\"", "x"),
            KeyDef("c", "C", [";"], ";", "c"),
            KeyDef("v", "V", [":"], ":", "v"),
            KeyDef("b", "B", ["/"], "/", "b"),
            KeyDef("n", "N", ["|"], "|", "n"),
            KeyDef("m", "M", ["\\"], "\\", "m"),
            KeyDef("/", "?", ["?"], "?", "/"),
            KeyDef("Enter", "", [], "", "Enter")
        ],
        [ // Row 4: Ctrl + Opt + Cmd + Space + Cmd + Opt + Ctrl
            KeyDef("Ctrl", "", [], "", "Ctrl"),
            KeyDef("Option", "", [], "", "Alt"),
            KeyDef("Cmd", "", [], "", "Cmd"),
            KeyDef("Space", "", [], "", "Space"),
            KeyDef("Cmd", "", [], "", "Cmd"),
            KeyDef("Option", "", [], "", "Alt"),
            KeyDef("Ctrl", "", [], "", "Ctrl")
        ]
    ]

    /// Windows/Linux landscape layout — bottom row: Ctrl + Win + Alt + Space + Alt + App + Right Ctrl
    /// Matches Android keyboard_lower_landscape_no_gui.xml
    let landscapePcKeys: [[KeyDef]] = [
        [ // Row 1: Tab + q-p + Backspace
            KeyDef("Tab", "", [], "", "Tab"),
            KeyDef("q", "Q", ["!", "1"], "!", "q"),
            KeyDef("w", "W", ["@", "2"], "@", "w"),
            KeyDef("e", "E", ["#", "3"], "#", "e"),
            KeyDef("r", "R", ["$", "4"], "$", "r"),
            KeyDef("t", "T", ["%", "5"], "%", "t"),
            KeyDef("y", "Y", ["^", "6"], "^", "y"),
            KeyDef("u", "U", ["&", "7"], "&", "u"),
            KeyDef("i", "I", ["*", "8"], "*", "i"),
            KeyDef("o", "O", [",", "9"], ",", "o"),
            KeyDef("p", "P", [".", "0"], ".", "p"),
            KeyDef("Backspace", "", [], "", "Backspace")
        ],
        [ // Row 2: Fn + a-l + Forward Delete
            KeyDef("Fn", "", [], "", "Fn"),
            KeyDef("a", "A", ["¥", "", "£", "€"], "¥", "a"),
            KeyDef("s", "S", ["", "", "`", "~"], "`", "s"),
            KeyDef("d", "D", ["", "-", "_"], "-", "d"),
            KeyDef("f", "F", ["", "+", "="], "+", "f"),
            KeyDef("g", "G", ["", "/", "?"], "/", "g"),
            KeyDef("h", "H", ["", "<", ">"], "<", "h"),
            KeyDef("j", "J", ["", "[", "]"], "[", "j"),
            KeyDef("k", "K", ["", "{", "}"], "{", "k"),
            KeyDef("l", "L", ["", "(", ")"], "(", "l"),
            KeyDef("FwdDel", "", [], "", "Delete")
        ],
        [ // Row 3: Shift + z-m + / + Enter
            KeyDef("Shift", "", [], "", "Shift"),
            KeyDef("z", "Z", ["'", "", ","], "'", "z"),
            KeyDef("x", "X", ["\""], "\"", "x"),
            KeyDef("c", "C", [";"], ";", "c"),
            KeyDef("v", "V", [":"], ":", "v"),
            KeyDef("b", "B", ["/"], "/", "b"),
            KeyDef("n", "N", ["|"], "|", "n"),
            KeyDef("m", "M", ["\\"], "\\", "m"),
            KeyDef("/", "?", ["?"], "?", "/"),
            KeyDef("Enter", "", [], "", "Enter")
        ],
        [ // Row 4: Ctrl + Win + Alt + Space + Alt + App + Right Ctrl
            KeyDef("Ctrl", "", [], "", "Ctrl"),
            KeyDef("Win", "", [], "", "Win"),
            KeyDef("Alt", "", [], "", "Alt"),
            KeyDef("Space", "", [], "", "Space"),
            KeyDef("Alt", "", [], "", "Alt"),
            KeyDef("App", "", [], "", "App"),
            KeyDef("Ctrl", "", [], "", "Ctrl")
        ]
    ]

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
    
    // HID keyboard usage code lookup via OpenterfaceCore
    private func hidCode(forKey key: String) -> UInt8? {
        let code = Keymod.hidCode(forKey: key)
        guard code >= 0 else { return nil }
        return UInt8(code)
    }

    // Modifier key bitmasks via KMod
    private func modifierMask(for key: String) -> UInt8? {
        switch key {
        case "Ctrl":  return KMod.ctrl.rawValue
        case "Shift": return KMod.shift.rawValue
        case "Alt", "Option": return KMod.alt.rawValue
        case "Cmd", "Win", "Super": return KMod.gui.rawValue
        default:      return nil
        }
    }
    
    // Handle key press events
    func handleKeyPress(_ key: String) {
        logger.log("Key pressed: \(key)", category: "Keyboard")
        
        // Trigger haptic feedback for key press
        hapticManager.triggerButtonPress()
        
        // Handle modifier keys with toggle behavior
        if modifierMask(for: key) != nil {
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

        // Apply Fn lock mapping: if Fn is locked and this key maps to an F-key,
        // send the F-key instead of the letter.
        let effectiveKey = resolveFnKey(keyAlias) ?? keyAlias

        guard let keyCode = hidCode(forKey: effectiveKey) else {
            logger.log("Unknown key: \(key) (resolved: \(effectiveKey))", category: "Keyboard", level: .warning)
            return
        }
        
        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]
        
        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMask(for: modifier) {
                modifierByte |= modifierMask
            }
        }

        // Apply caps lock effect for letters
        if effectiveKey.count == 1 && effectiveKey.first!.isLetter {
            let shouldBeUppercase = capsLockActive != activeModifiers.contains("Shift")
            if shouldBeUppercase {
                modifierByte |= KMod.shift.rawValue
            }
        }

        // Send key press
        sendKeyboardData(modifier: modifierByte, keyCodes: keyCodes)

        // Send key release after a short delay (but keep modifiers active)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var releaseModifierByte: UInt8 = 0x00
            for modifier in self.activeModifiers {
                if let modifierMask = self.modifierMask(for: modifier) {
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
            if modifierMask(for: key) != nil { handleModifierToggle(key); return }
            if key == "Caps" { capsLockActive.toggle(); sendCapsLockState(); return }
            let keyAlias = mapKeyAlias(key)
            // For single letter keys, use the uppercased form for HID lookup so that
            // both "a" and "A" resolve to the same key code. Original case is preserved
            // in keyAlias to determine whether Shift is required.
            let lookupAlias = (keyAlias.count == 1 && keyAlias.first?.isLetter == true)
                ? keyAlias.uppercased() : keyAlias
            guard let keyCode = hidCode(forKey: lookupAlias) else { return }
            var modByte: UInt8 = 0x00
            for m in activeModifiers { modByte |= modifierMask(for: m) ?? 0 }
            if keyAlias.count == 1, let ch = keyAlias.first, ch.isLetter {
                // Add Shift when the intended case differs from the CapsLock state.
                let wantUppercase = ch.isUppercase
                if wantUppercase != capsLockActive { modByte |= KMod.shift.rawValue }
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

    /// Track a modifier locally without sending a HID modifier-down report.
    /// Used in momentary-chord mode when chord-sustain HID is disabled — the modifier
    /// is included in the next regular-key HID report but no standalone modifier-down
    /// is sent to the host until a key is chorded.
    /// Must be called on the main thread.
    func addModifierTrackedOnly(_ modifier: String) {
        if modifierMask(for: modifier) != nil {
            activeModifiers.insert(modifier)
            logger.log("\(modifier) tracked (no HID report)", category: "Keyboard")
        }
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
            guard let keyCode = hidCode(forKey: key) else { return }
            var modByte: UInt8 = 0x00
            for m in modifiers { modByte |= modifierMask(for: m) ?? 0 }
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
            if let modifierMask = modifierMask(for: activeModifier) {
                modifierByte |= modifierMask
            }
        }
        
        sendKeyboardData(modifier: modifierByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
    
    // Send caps lock state
    private func sendCapsLockState() {
        guard let capsKeyCode = hidCode(forKey: "Caps") else { return }
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

        guard let keyCode = hidCode(forKey: key) else {
            logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
            return
        }

        var modifierByte: UInt8 = 0x00
        let keyCodes: [UInt8] = [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00]

        // Apply modifiers
        for modifier in modifiers {
            if let modifierMask = modifierMask(for: modifier) {
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
        var packet = Keymod.buildKeyboard(modifiers: modifier, keys: keyCodes)
        // Override header byte 3 for game mode (Core uses 0x02, game mode uses 0x12)
        if isGameMode {
            packet[3] = 0x12
        }
        bleManager.sendTouchData(data: packet)
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

    // MARK: - Fn Lock & Key Resolution

    /// Resolve the effective key name when Fn lock is active.
    /// Matches Android CustomKeyboardView.resolveFnMapping(): q→F1, w→F2, ..., a→F11, s→F12.
    func resolveFnKey(_ key: String) -> String? {
        guard isFnLocked else { return nil }
        // Fn lock only applies to letter keys that map to F-keys
        return fnMapping[key.lowercased()]
    }

    /// Find the KeyDef for a given label in the portrait letter keys.
    func findKeyDef(for label: String) -> KeyDef? {
        for row in portraitLetterKeys {
            for kd in row {
                if kd.label == label { return kd }
            }
        }
        return nil
    }

    /// Select the appropriate landscape keyboard layout based on target OS.
    func landscapeKeys(for targetOS: TargetOS) -> [[KeyDef]] {
        switch targetOS {
        case .macOS: return landscapeMacKeys
        case .windows, .linux: return landscapePcKeys
        }
    }

    /// Check if a key is a modifier or special key that should not show alternates.
    func isModifierOrSpecialKey(_ label: String) -> Bool {
        let skipSet = ["Shift", "Ctrl", "Alt", "Cmd", "Win", "Fn", "Space", "Enter", "Backspace", "Caps", "Tab", "Esc", "Escape", "Delete", "Forward Delete", "FwdDel", "Del", "App", "Option"]
        return skipSet.contains(label)
    }

    /// Check if a key should have a long-press alternates popup.
    /// Matches Android CustomKeyboardView.shouldEnableAlternates().
    func shouldShowAlternates(for label: String) -> Bool {
        guard !isModifierOrSpecialKey(label) else { return false }
        guard !isFnLocked else { return false }
        guard label.count == 1 else { return false }
        // Only single-char letter/number/symbol keys
        return true
    }
    
    // Handle text input (for typing strings)
    func handleTextInput(_ text: String) {
        logger.log("Starting text input: \(text)", category: "Keyboard")
        logger.logCheckpoint("Text input started", category: "Keyboard")
        sendLock.lock()
        sendCancelFlag = false
        sendLock.unlock()
        isSending = true

        DispatchQueue.global(qos: .userInitiated).async {
            for char in text {
                self.sendLock.lock()
                let cancelled = self.sendCancelFlag
                self.sendLock.unlock()
                if cancelled { break }

                let scalar = char.unicodeScalars.first?.value ?? 0
                // Non-ASCII Unicode — delegate to UnicodeManager (already on bg thread)
                if scalar > 0x7E {
                    UnicodeManager.shared.sendChar(char, keyboardManager: self)
                    usleep(self.keyDelayUs)
                    continue
                }
                // ASCII characters — send directly from background thread.
                // sendKeyPressAndRelease is thread-safe (builds HID packets, no UI access).
                // Using main.sync here would deadlock when the main thread is blocked
                // (gesture gate timeout, haptic engine, etc.).
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
                    let (code, needsShift) = Keymod.hidCode(for: char)
                    if code >= 0 {
                        if needsShift {
                            self.sendKeyPressAndRelease(modifiers: ["Shift"], key: String(char), rawHidCode: UInt8(code))
                        } else {
                            self.sendKeyPressAndRelease(key: String(char), rawHidCode: UInt8(code))
                        }
                    } else {
                        // Fallback for unmappable chars
                        self.sendKeyPressAndRelease(key: String(char).uppercased())
                    }
                }
                // Wait between characters for proper timing
                usleep(self.keyDelayUs)
            }
            
            DispatchQueue.main.async {
                self.sendLock.lock()
                self.sendCancelFlag = false
                self.sendLock.unlock()
                self.isSending = false
                self.logger.logCheckpoint("Text input completed", category: "Keyboard")
            }
        }
    }

    /// Cancel an in-flight text send operation.
    func cancelSend() {
        sendLock.lock()
        sendCancelFlag = true
        sendLock.unlock()
    }
    
    /// Send a complete key press and release cycle synchronously.
    /// Internal so that UnicodeManager can use it from a background thread.
    /// If `hidCode` is provided, it is used directly instead of looking up `key`.
    func sendKeyPressAndRelease(modifiers: [String] = [], key: String, rawHidCode: UInt8? = nil) {
        let keyCode: UInt8
        if let code = rawHidCode {
            keyCode = code
        } else {
            guard let code = hidCode(forKey: key) else {
                logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
                return
            }
            keyCode = code
        }

        logger.log("Key pressed: \(key)", category: "Keyboard")

        var modifierByte: UInt8 = 0x00

        // Apply modifiers
        for modifier in modifiers {
            if let modifierMask = modifierMask(for: modifier) {
                modifierByte |= modifierMask
            }
        }

        // Send key press
        sendKeyboardData(modifier: modifierByte, keyCodes: [keyCode, 0x00, 0x00, 0x00, 0x00, 0x00])

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
            let (code, needsShift) = Keymod.hidCode(for: char)
            if code >= 0 {
                if needsShift {
                    sendKeyPressAndRelease(modifiers: ["Shift"], key: String(char), rawHidCode: UInt8(code))
                } else {
                    sendKeyPressAndRelease(key: String(char), rawHidCode: UInt8(code))
                }
            } else {
                sendKeyPressAndRelease(key: String(char))
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
            if modifierMask(for: key) != nil {
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

            guard hidCode(forKey: keyAlias) != nil else {
                logger.log("Unknown key: \(key)", category: "Keyboard", level: .warning)
                continue
            }

            // Add to pressed keys set
            pressedKeys.insert(keyAlias)
        }

        // Apply active modifiers
        for modifier in activeModifiers {
            if let modifierMask = modifierMask(for: modifier) {
                modifierByte |= modifierMask
            }
        }

        // Apply caps lock effect for letters in the key list
        for key in keys {
            let keyAlias = mapKeyAlias(key)
            if keyAlias.count == 1 && keyAlias.first!.isLetter {
                let shouldBeUppercase = capsLockActive != activeModifiers.contains("Shift")
                if shouldBeUppercase {
                    modifierByte |= KMod.shift.rawValue
                }
                break // Only need to apply once
            }
        }

        // Build key codes array with ALL currently pressed keys (up to 6 keys can be pressed simultaneously in HID)
        var keyCodesToSend: [UInt8] = []
        for pressedKey in pressedKeys {
            if let keyCode = hidCode(forKey: pressedKey), keyCodesToSend.count < 6 {
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
            if modifierMask(for: key) != nil {
                // Don't release if locked
                if lockedModifiers.contains(key) { continue }
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
            if let modifierMask = modifierMask(for: modifier) {
                modifierByte |= modifierMask
            }
        }

        // Add remaining pressed keys (excluding the ones we're releasing)
        for pressedKey in pressedKeys {
            if let keyCode = hidCode(forKey: pressedKey), keyCodesToSend.count < 6 {
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
        lockedModifiers.removeAll()
        sendKeyboardData(modifier: 0x00, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        logger.log("All keys released", category: "Keyboard")
    }

    /// Lock a modifier (sticky key). Modifier stays in activeModifiers until unlocked.
    func lockModifier(_ key: String) {
        lockedModifiers.insert(key)
        if !activeModifiers.contains(key) {
            activeModifiers.insert(key)
            var modByte: UInt8 = 0x00
            for m in activeModifiers { modByte |= modifierMask(for: m) ?? 0 }
            sendKeyboardData(modifier: modByte, keyCodes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
    }

    /// Unlock a locked modifier and release it.
    func unlockModifier(_ key: String) {
        lockedModifiers.remove(key)
        activeModifiers.remove(key)
        var modByte: UInt8 = 0x00
        for m in activeModifiers { modByte |= modifierMask(for: m) ?? 0 }
        // Maintain any currently pressed regular keys in the HID report
        var keyCodes: [UInt8] = []
        for pressedKey in pressedKeys {
            if let code = hidCode(forKey: pressedKey), keyCodes.count < 6 {
                keyCodes.append(code)
            }
        }
        while keyCodes.count < 6 { keyCodes.append(0x00) }
        sendKeyboardData(modifier: modByte, keyCodes: keyCodes)
    }

    // MARK: - Long-press key repeat (KM Basic)

    /// Initial delay before auto-repeat starts (matches typical physical keyboard).
    private let repeatInitialDelay: TimeInterval = 0.4
    /// Interval between repeated key reports.
    private let repeatInterval: TimeInterval = 0.08

    private var repeatTimer: Timer?
    private var repeatKey: String?

    /// Start sending a key-down HID report and schedule auto-repeat.
    /// Call on the main thread. Sends the first key-down immediately, then
    /// after `repeatInitialDelay` fires repeated press-release cycles.
    func startKeyRepeat(_ key: String) {
        stopKeyRepeat()
        repeatKey = key
        handleKeyDown(key)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatInitialDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                guard let self = self, let k = self.repeatKey else { return }
                // Bounce the key: up then down — generates a new key event on the host
                // without asyncAfter so there is no overlap between repeat ticks.
                self.handleKeyUp(k)
                self.handleKeyDown(k)
            }
        }
    }

    /// Stop auto-repeat and send key-up for the currently repeating key.
    /// Call on the main thread.
    func stopKeyRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        if let k = repeatKey {
            handleKeyUp(k)
            repeatKey = nil
        }
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

        let tokens = Keymod.tokenizeScript(processedText)

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
                else if let hidCode = self.specialTokenHidCode(token) {
                    if activeModifiers.isEmpty {
                        self.sendKeyPressAndRelease(key: Keymod.label(for: Int32(hidCode)))
                    } else {
                        let keyName = Keymod.label(for: Int32(hidCode))
                        self.sendKeyComboSynchronous(modifiers: activeModifiers, key: keyName)
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
                        // Pass the token as-is (do NOT uppercase) so that sendKeyPressSynchronous
                        // can detect the original case and add Shift for uppercase letters.
                        self.sendKeyPressSynchronous(token)
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
                            // Pass charStr as-is so sendKeyPressSynchronous can detect case.
                            self.sendKeyPressSynchronous(charStr)
                        }
                        usleep(self.keyDelayUs)
                    }
                }
                // Inter-token gap. Skip for delay tokens (already slept) and
                // multi-char tokens (per-char gap applied above).
                let isDelayToken = token == "<DELAY1S>" || token == "<DELAY2S>" || token == "<DELAY5S>" || token == "<DELAY10S>"
                let isSpecial = token.hasPrefix("<") && token.hasSuffix(">") && !token.hasPrefix("</")
                if !isDelayToken && (token.count <= 1 || isSpecial) {
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
    
    /// Check if a token is a special token (e.g., <CTRL>, <SHIFT>, etc.)
    /// and get its HID code via Core. Returns nil if not a special token or unmappable.
    private func specialTokenHidCode(_ token: String) -> UInt8? {
        // Only handle angle-bracket tokens like <ENTER>, <F1>, <UP> etc.
        // Plain single characters like "H" or "a" must NOT match here — they
        // need to go through sendASCIICharInline so that case is preserved.
        guard token.hasPrefix("<") && token.hasSuffix(">") else { return nil }
        let result = Keymod.parseToken(token)
        guard result.hidCode >= 0 else { return nil }
        return UInt8(result.hidCode)
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
