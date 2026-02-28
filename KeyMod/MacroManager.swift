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
        
        let data = macro.data
        let interval = macro.intervalMs
        // Updated pattern to match both opening and closing tags: <TAG> and </TAG>
        let pattern = "</?([A-Z0-9]+S?)>"
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsData = data as NSString
        var lastIndex = 0
        var tokens: [String] = []
        if let regex = regex {
            let matches = regex.matches(in: data, range: NSRange(location: 0, length: nsData.length))
            for match in matches {
                let range = match.range
                if range.location > lastIndex {
                    let text = nsData.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                    tokens.append(contentsOf: text.map { String($0) })
                }
                let keyToken = nsData.substring(with: range)
                tokens.append(keyToken)
                lastIndex = range.location + range.length
            }
            if lastIndex < nsData.length {
                let text = nsData.substring(from: lastIndex)
                tokens.append(contentsOf: text.map { String($0) })
            }
        } else {
            tokens = data.map { String($0) }
        }
        
        // Also extract non-special tags for macro invocation
        let allTagsPattern = "</?([^>]+)>"
        let allTagsRegex = try? NSRegularExpression(pattern: allTagsPattern)
        var tokenDict: [Int: String] = [:] // map original index to extracted tag name
        if let allTagsRegex = allTagsRegex {
            let matches = allTagsRegex.matches(in: data, range: NSRange(location: 0, length: nsData.length))
            for match in matches {
                let range = match.range
                let fullToken = nsData.substring(with: range)
                let tagContent = nsData.substring(with: match.range(at: 1))
                // If it's not a known special key, it might be a macro name
                if !isSpecialKey(fullToken) && !tagContent.hasPrefix("/") {
                    tokenDict[range.location] = tagContent
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Track active modifiers for composite key support
            var activeModifiers: [String] = []
            
            for token in tokens {
                DispatchQueue.main.async {
                    // Handle closing tags - release all active modifiers and keys
                    if token.hasPrefix("</") && token.hasSuffix(">") {
                        // Release all keys
                        self.keyboardManager.releaseAllKeys()
                        // Clear active modifiers
                        activeModifiers.removeAll()
                    }
                    // Handle opening modifier tags like <CTRL>, <SHIFT>, etc
                    else if token == "<CTRL>" || token == "<SHIFT>" || token == "<ALT>" || token == "<CMD>" {
                        let modifier: String
                        switch token {
                        case "<CTRL>":
                            modifier = "Ctrl"
                        case "<SHIFT>":
                            modifier = "Shift"
                        case "<ALT>":
                            modifier = "Alt"
                        case "<CMD>":
                            modifier = "Cmd"
                        default:
                            modifier = ""
                        }
                        
                        if !modifier.isEmpty {
                            // Press the modifier
                            self.keyboardManager.handleModifierToggle(modifier)
                            activeModifiers.append(modifier)
                        }
                    }
                    else if token.hasPrefix("<") && token.hasSuffix(">") && !self.isSpecialKey(token) {
                        // This might be a macro name - extract the content between < and >
                        let macroName = String(token.dropFirst().dropLast())
                        if let referencedMacro = self.getMacroByLabel(macroName) {
                            // Invoke the referenced macro
                            self.sendMacroInternal(referencedMacro)
                        }
                    }
                    else {
                        switch token {
                        case "<ESC>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Escape")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Escape")
                            }
                        case "<BACK>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Backspace")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Backspace")
                            }
                        case "<ENTER>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Enter")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Enter")
                            }
                        case "<SPACE>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Space")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Space")
                            }
                        case "<LEFT>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Left")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Left")
                            }
                        case "<RIGHT>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Right")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Right")
                            }
                        case "<UP>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Up")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Up")
                            }
                        case "<DOWN>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Down")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Down")
                            }
                        case "<HOME>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("Home")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Home")
                            }
                        case "<END>":
                            if activeModifiers.isEmpty {
                                self.keyboardManager.handleKeyPress("End")
                            } else {
                                self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "End")
                            }
                        case "<DELAY1S>": break
                        case "<DELAY2S>": break
                        case "<DELAY5S>": break
                        case "<DELAY10S>": break
                        default:
                            if token == " " {
                                if activeModifiers.isEmpty {
                                    self.keyboardManager.handleKeyPress("Space")
                                } else {
                                    self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: "Space")
                                }
                            } else if token.count == 1, let char = token.first {
                                if !char.isASCII {
                                    // Non-ASCII Unicode – must run on background thread
                                    // so UnicodeManager can use usleep between HID reports.
                                    let charCopy = char
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        UnicodeManager.shared.sendChar(charCopy, keyboardManager: self.keyboardManager)
                                    }
                                } else if activeModifiers.isEmpty {
                                    if char.isUppercase && char.isLetter {
                                        self.keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: String(char).uppercased())
                                    } else {
                                        self.keyboardManager.handleKeyPress(token)
                                    }
                                } else {
                                    // Apply active modifiers to the key
                                    var allModifiers = activeModifiers
                                    if char.isUppercase && char.isLetter {
                                        if !allModifiers.contains("Shift") {
                                            allModifiers.append("Shift")
                                        }
                                    }
                                    self.keyboardManager.handleKeyCombo(modifiers: allModifiers, key: String(char).uppercased())
                                }
                            } else {
                                if activeModifiers.isEmpty {
                                    self.keyboardManager.handleKeyPress(token)
                                } else {
                                    self.keyboardManager.handleKeyCombo(modifiers: activeModifiers, key: token)
                                }
                            }
                        }
                    }
                }
                switch token {
                case "<DELAY1S>":
                    usleep(1_000_000)
                case "<DELAY2S>":
                    usleep(2_000_000)
                case "<DELAY5S>":
                    usleep(5_000_000)
                case "<DELAY10S>":
                    usleep(10_000_000)
                default:
                    usleep(useconds_t(interval * 1000))
                }
            }
        }
    }
    
    /// Returns a markdown section listing all defined macros for injection into the AI system prompt.
    /// Returns nil when no macros are defined so callers can skip appending entirely.
    func macroContextSection() -> String? {
        let validMacros = macros.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validMacros.isEmpty else { return nil }

        var lines: [String] = [
            "",
            "## Available macros",
            "The following macros are defined by the user. Invoke them with `<MacroLabel>`:",
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
