import Foundation
import Combine
import SwiftUI

class MacroManager: ObservableObject {
    @Published var macros: [Macro] = [] {
        didSet { saveMacros() }
    }
    @Published var scheduledTimers: [UUID: Timer] = [:]
    
    private let macrosKey = "MacrosList"
    private var keyboardManager: KeyboardManager
    private let hapticManager = HapticFeedbackManager.shared
    private var macroInvocationDepth: Int = 0
    private let maxMacroInvocationDepth: Int = 10
    
    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
        loadMacros()
        scheduleAllMacros()
    }
    
    // Find a macro by its label (name)
    private func getMacroByLabel(_ label: String) -> Macro? {
        return macros.first { $0.label.lowercased() == label.lowercased() }
    }
    
    // Check if a token is a known special key
    private func isSpecialKey(_ token: String) -> Bool {
        let specialKeys = [
            "<ESC>", "<BACK>", "<ENTER>", "<SPACE>", 
            "<LEFT>", "<RIGHT>", "<UP>", "<DOWN>",
            "<HOME>", "<END>",
            "<DELAY1S>", "<DELAY2S>", "<DELAY5S>", "<DELAY10S>",
            "<CTRL>", "<SHIFT>", "<ALT>", "<CMD>"
        ]
        return specialKeys.contains(token)
    }
    
    func sendMacro(_ macro: Macro) {
        macroInvocationDepth = 0
        sendMacroInternal(macro)
    }

    /// Look up a macro by label and send it. Called from the voice-input path
    /// via KeyboardManager.MacroHandler.
    func sendMacroByLabel(_ label: String) {
        macroInvocationDepth = 0
        if let macro = getMacroByLabel(label) {
            sendMacroInternal(macro)
        }
    }
    
    /// Recursively resolves all <Macro>…</Macro> and inline <TAGNAME> sub-macro references,
    /// returning a flat list of (token, intervalMs) pairs in strict execution order.
    private func buildFlatTokens(from macro: Macro, depth: Int = 0) -> [(token: String, intervalMs: Int)] {
        guard depth < maxMacroInvocationDepth else {
            print("Warning: Maximum macro nesting depth reached in buildFlatTokens")
            return []
        }
        let rawData = macro.data
        let parentInterval = macro.intervalMs

        // Pre-process <Macro>...</Macro> blocks → MLABEL placeholders
        var macroLabelMap: [String: String] = [:]
        var data = rawData
        if let mlabelPattern = try? NSRegularExpression(pattern: "<Macro>([\\s\\S]*?)</Macro>", options: .caseInsensitive) {
            let nsRaw = rawData as NSString
            let mlMatches = mlabelPattern.matches(in: rawData, range: NSRange(location: 0, length: nsRaw.length))
            for (i, match) in mlMatches.reversed().enumerated() {
                let label = nsRaw.substring(with: match.range(at: 1))
                let placeholder = "<MLABEL\(i)>"
                macroLabelMap[placeholder] = label
                let fullRange = match.range
                let before = (data as NSString).substring(to: fullRange.location)
                let after  = (data as NSString).substring(from: fullRange.location + fullRange.length)
                data = before + placeholder + after
            }
        }

        // Tokenize
        print("[MacroDebug] buildFlatTokens depth=\(depth) macro='\(macro.label)' data after substitution: \(data.debugDescription)")
        var tokens: [String] = []
        if let regex = try? NSRegularExpression(pattern: "</?([A-Z0-9]+)>") {
            let nsData = data as NSString
            var lastIndex = 0
            for match in regex.matches(in: data, range: NSRange(location: 0, length: nsData.length)) {
                let range = match.range
                if range.location > lastIndex {
                    tokens.append(contentsOf: nsData
                        .substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                        .map { String($0) })
                }
                tokens.append(nsData.substring(with: range))
                lastIndex = range.location + range.length
            }
            if lastIndex < nsData.length {
                tokens.append(contentsOf: nsData.substring(from: lastIndex).map { String($0) })
            }
        } else {
            tokens = data.map { String($0) }
        }

        // DEBUG: show what was tokenized before expansion
        print("[MacroDebug] buildFlatTokens depth=\(depth) macro='\(macro.label)' raw tokens: \(tokens)")
        print("[MacroDebug] macroLabelMap: \(macroLabelMap)")

        // Expand sub-macro references inline; annotate plain tokens with intervalMs
        var result: [(token: String, intervalMs: Int)] = []
        for token in tokens {
            if let label = macroLabelMap[token] {
                // <Macro>label</Macro> reference – expand recursively
                print("[MacroDebug] Expanding MLABEL token '\(token)' → label='\(label)'")
                if let sub = getMacroByLabel(label) {
                    result.append(contentsOf: buildFlatTokens(from: sub, depth: depth + 1))
                } else {
                    print("[MacroDebug] WARNING: no macro found for label='\(label)'")
                }
            } else if token.hasPrefix("<") && token.hasSuffix(">") &&
                      !token.hasPrefix("</") &&
                      !isSpecialKey(token) &&
                      !["<CTRL>", "<SHIFT>", "<ALT>", "<CMD>"].contains(token) {
                // Possible inline <TAGNAME> macro reference
                let macroName = String(token.dropFirst().dropLast())
                if let sub = getMacroByLabel(macroName) {
                    print("[MacroDebug] Expanding inline tag '\(token)' → macro='\(macroName)'")
                    result.append(contentsOf: buildFlatTokens(from: sub, depth: depth + 1))
                } else {
                    result.append((token: token, intervalMs: parentInterval))
                }
            } else {
                result.append((token: token, intervalMs: parentInterval))
            }
        }
        return result
    }

    private func sendMacroInternal(_ macro: Macro) {
        // Prevent infinite recursion
        guard macroInvocationDepth < maxMacroInvocationDepth else {
            print("Warning: Maximum macro invocation depth reached, preventing infinite recursion")
            return
        }
        
        macroInvocationDepth += 1
        defer { macroInvocationDepth -= 1 }
        
        // Trigger strong haptic feedback for macro execution
        hapticManager.triggerStrongFeedback()
        
        // Pre-expand all sub-macro references into a flat token list so that
        // every token executes in strict order on a single background thread.
        let flatTokens = buildFlatTokens(from: macro)

        // DEBUG: dump the entire resolved flat token list
        let tokenSummary = flatTokens.enumerated()
            .map { "[\($0.offset)] \($0.element.token) (\($0.element.intervalMs)ms)" }
            .joined(separator: ", ")
        print("[MacroDebug] Flat tokens for '\(macro.label)': \(tokenSummary)")

        // Spawn a background thread and run all tokens in strict order.
        DispatchQueue.global(qos: .userInitiated).async {
            self.executeTokensOnCurrentThread(flatTokens)
        }
    }

    /// Execute a flat token list **synchronously on the calling thread**.
    /// Must be called from a background thread (never from the main thread).
    /// This is the single shared execution engine used by both:
    ///   - sendMacroInternal (via DispatchQueue.global.async)
    ///   - executeBlockingByLabel (called directly from handleTextInputWithTokens)
    func executeTokensOnCurrentThread(_ flatTokens: [(token: String, intervalMs: Int)]) {
        for item in flatTokens {
            let token = item.token
            print("[MacroDebug] Executing token: \(token)")

            switch token {
            // ── Closing composite-key tag: clear tracked state only ──────────
            // sendKeyPressSynchronous already sent the physical 0x00 key-up,
            // so we just clear activeModifiers/pressedKeys without another TX.
            case let t where t.hasPrefix("</") && t.hasSuffix(">"):
                DispatchQueue.main.sync { self.keyboardManager.clearKeyStateSilently() }

            // ── Opening modifier tags ────────────────────────────────────
            case "<CTRL>", "<SHIFT>", "<ALT>", "<CMD>":
                let modifier: String
                switch token {
                case "<CTRL>":  modifier = "Ctrl"
                case "<SHIFT>": modifier = "Shift"
                case "<ALT>":   modifier = "Alt"
                default:        modifier = "Cmd"
                }
                // Silently track the modifier — no standalone BLE press.
                // The next sendKeyPressSynchronous call will include it in
                // its modifier byte; </TAG> will call releaseAllKeys().
                DispatchQueue.main.sync { self.keyboardManager.addModifierSilently(modifier) }

            // ── Named special keys ───────────────────────────────────────
            case "<ESC>":     keyboardManager.sendKeyPressSynchronous("Escape")
            case "<BACK>":    keyboardManager.sendKeyPressSynchronous("Backspace")
            case "<ENTER>":   keyboardManager.sendKeyPressSynchronous("Enter")
            case "<SPACE>":   keyboardManager.sendKeyPressSynchronous("Space")
            case "<LEFT>":    keyboardManager.sendKeyPressSynchronous("Left")
            case "<RIGHT>":   keyboardManager.sendKeyPressSynchronous("Right")
            case "<UP>":      keyboardManager.sendKeyPressSynchronous("Up")
            case "<DOWN>":    keyboardManager.sendKeyPressSynchronous("Down")
            case "<HOME>":    keyboardManager.sendKeyPressSynchronous("Home")
            case "<END>":     keyboardManager.sendKeyPressSynchronous("End")

            // ── Explicit delay tokens ────────────────────────────────────
            case "<DELAY1S>":  usleep(1_000_000)
            case "<DELAY2S>":  usleep(2_000_000)
            case "<DELAY5S>":  usleep(5_000_000)
            case "<DELAY10S>": usleep(10_000_000)

            // ── Regular characters ───────────────────────────────────────
            default:
                let keyStr = token == " " ? "Space" : token
                if token.count == 1, let char = token.first, !char.isASCII {
                    let sem = DispatchSemaphore(value: 0)
                    let charCopy = char
                    UnicodeManager.shared.serialQueue.async {
                        UnicodeManager.shared.sendChar(charCopy, keyboardManager: self.keyboardManager)
                        sem.signal()
                    }
                    sem.wait()
                } else {
                    keyboardManager.sendKeyPressSynchronous(keyStr)
                }
            }

            switch token {
            case "<DELAY1S>", "<DELAY2S>", "<DELAY5S>", "<DELAY10S>": break
            default:
                usleep(useconds_t(item.intervalMs * 1000))
            }
        }
    }

    /// Resolve a macro by label and execute it **synchronously** on the calling
    /// background thread. Used by KeyboardManager.handleTextInputWithTokens so
    /// that <Macro>…</Macro> tokens in a text sequence block until the sub-macro
    /// finishes before the next token in the sequence is processed.
    func executeBlockingByLabel(_ label: String) {
        guard let macro = getMacroByLabel(label) else {
            print("[MacroDebug] executeBlockingByLabel: no macro found for label='\(label)'")
            return
        }
        hapticManager.triggerStrongFeedback()
        let flatTokens = buildFlatTokens(from: macro)
        let tokenSummary = flatTokens.enumerated()
            .map { "[\($0.offset)] \($0.element.token) (\($0.element.intervalMs)ms)" }
            .joined(separator: ", ")
        print("[MacroDebug] executeBlockingByLabel '\(label)': \(tokenSummary)")
        executeTokensOnCurrentThread(flatTokens)
    }
    
    /// Returns a markdown section listing all defined macros for injection into the AI system prompt.
    /// Returns nil when no macros are defined so callers can skip appending entirely.
    func macroContextSection() -> String? {
        let validMacros = macros.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validMacros.isEmpty else { return nil }

        var lines: [String] = [
            "",
            "## Available macros",
            "The following macros are defined by the user. Invoke them with `<Macro>`:",
            "",
            "| Label | Command sequence |",
            "|-------|-----------------|"
        ]
        for macro in validMacros {
            // Escape pipe characters in data to keep the table valid
            let escapedData = macro.data.replacingOccurrences(of: "|", with: "\\|")
            lines.append("| \(macro.label) | `\(escapedData)` |")
        }
        return lines.joined(separator: "\n")
    }

    func saveMacros() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: macrosKey)
        }
        scheduleAllMacros()
    }
    
    func loadMacros() {
        if let data = UserDefaults.standard.data(forKey: macrosKey),
           let saved = try? JSONDecoder().decode([Macro].self, from: data) {
            macros = saved
        }
        scheduleAllMacros()
    }
    
    func scheduleAllMacros() {
        // Cancel all existing timers
        for timer in scheduledTimers.values { timer.invalidate() }
        scheduledTimers.removeAll()
        
        for macro in macros {
            if macro.isScheduled, let scheduledDate = macro.scheduledTime {
                let interval = max(0, scheduledDate.timeIntervalSinceNow)
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                    self?.runScheduledMacro(macro)
                    // If there's a repeat interval set, schedule repeating execution
                    if let repeatInterval = macro.repeatIntervalSeconds {
                        self?.scheduleRepeatingMacro(macro, interval: repeatInterval)
                    }
                }
                scheduledTimers[macro.id] = timer
            } else if let repeatInterval = macro.repeatIntervalSeconds {
                // If only repeat interval is set (no scheduled time), start repeating immediately
                scheduleRepeatingMacro(macro, interval: repeatInterval)
            }
        }
    }
    
    // Schedule a repeating macro with a given interval in seconds
    func scheduleRepeatingMacro(_ macro: Macro, interval: TimeInterval) {
        // Cancel any existing timer for this macro
        scheduledTimers[macro.id]?.invalidate()
        
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runScheduledMacro(macro)
        }
        scheduledTimers[macro.id] = timer
    }
    
    func runScheduledMacro(_ macro: Macro) {
        let repeatCount = macro.repeatCount ?? 1
        for i in 0..<repeatCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                self.sendMacro(macro)
            }
        }
    }
    
    func addMacro(_ macro: Macro) {
        macros.append(macro)
    }
    
    func updateMacro(_ macro: Macro, at index: Int) {
        macros[index] = macro
    }
    
    func removeMacro(at index: Int) {
        let macro = macros[index]
        // Cancel any scheduled timer for this macro
        scheduledTimers[macro.id]?.invalidate()
        scheduledTimers.removeValue(forKey: macro.id)
        macros.remove(at: index)
    }
    
    // Stop repeat interval for a specific macro
    func stopRepeatInterval(for macroId: UUID) {
        scheduledTimers[macroId]?.invalidate()
        scheduledTimers.removeValue(forKey: macroId)
    }
}
