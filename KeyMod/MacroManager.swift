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
    
    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
        loadMacros()
        scheduleAllMacros()
    }
    
    func sendMacro(_ macro: Macro) {
        // Trigger strong haptic feedback for macro execution
        hapticManager.triggerStrongFeedback()
        
        let data = macro.data
        let interval = macro.intervalMs
        let pattern = "<([A-Z0-9]+S?)>"
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
        DispatchQueue.global(qos: .userInitiated).async {
            for token in tokens {
                DispatchQueue.main.async {
                    switch token {
                    case "<ALT>":
                        self.keyboardManager.handleModifierToggle("Alt")
                    case "<CTRL>":
                        self.keyboardManager.handleModifierToggle("Ctrl")
                    case "<ESC>":
                        self.keyboardManager.handleKeyPress("Escape")
                    case "<BACK>":
                        self.keyboardManager.handleKeyPress("Backspace")
                    case "<ENTER>":
                        self.keyboardManager.handleKeyPress("Enter")
                    case "<LEFT>":
                        self.keyboardManager.handleKeyPress("Left")
                    case "<RIGHT>":
                        self.keyboardManager.handleKeyPress("Right")
                    case "<UP>":
                        self.keyboardManager.handleKeyPress("Up")
                    case "<DOWN>":
                        self.keyboardManager.handleKeyPress("Down")
                    case "<HOME>":
                        self.keyboardManager.handleKeyPress("Home")
                    case "<END>":
                        self.keyboardManager.handleKeyPress("End")
                    case "<DELAY1S>": break
                    case "<DELAY2S>": break
                    case "<DELAY5S>": break
                    case "<DELAY10S>": break
                    default:
                        if token == " " {
                            self.keyboardManager.handleKeyPress("Space")
                        } else if token.count == 1, let char = token.first, char.isUppercase, char.isLetter {
                            self.keyboardManager.handleKeyCombo(modifiers: ["Shift"], key: String(char).uppercased())
                        } else {
                            self.keyboardManager.handleKeyPress(token)
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
