//
//  LogManager.swift
//  KeyMod
//
//  Generic logging utility with timestamps for all classes
//

import Foundation

class LogManager {
    static let shared = LogManager()
    
    private let startTime = Date()
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.keymod.logging", attributes: .concurrent)
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    /// Log a message with timestamp and elapsed time
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: Optional category/tag for the message (e.g., "Keyboard", "BLE", "Clipboard")
    ///   - level: Log level (info, debug, warning, error)
    func log(
        _ message: String,
        category: String = "General",
        level: LogLevel = .info
    ) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let elapsedTime = Date().timeIntervalSince(self.startTime)
            let timeString = self.dateFormatter.string(from: Date())
            let levelIcon = level.icon
            let formattedMessage = "[\(timeString)] [\(elapsedTime.formatted)] [\(category)] \(levelIcon) \(message)"
            
            print(formattedMessage)
        }
    }
    
    /// Log with data packet hex representation
    /// - Parameters:
    ///   - message: The message to log
    ///   - data: Data packet to convert to hex string
    ///   - category: Optional category/tag
    ///   - level: Log level
    func logWithData(
        _ message: String,
        data: Data,
        category: String = "General",
        level: LogLevel = .info
    ) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("\(message): \(hexString)", category: category, level: level)
    }
    
    /// Log hex data directly
    /// - Parameters:
    ///   - hexData: Hex string representation (e.g., "57 AB 00 02 08")
    ///   - message: Optional message prefix
    ///   - category: Optional category/tag
    ///   - level: Log level
    func logHex(
        _ hexData: String,
        message: String? = nil,
        category: String = "General",
        level: LogLevel = .info
    ) {
        if let msg = message {
            log("\(msg): \(hexData)", category: category, level: level)
        } else {
            log(hexData, category: category, level: level)
        }
    }
    
    /// Log a timing checkpoint
    /// - Parameters:
    ///   - checkpoint: Name of the checkpoint
    ///   - category: Optional category/tag
    func logCheckpoint(_ checkpoint: String, category: String = "Timing") {
        log("⏱ \(checkpoint)", category: category, level: .debug)
    }
    
    /// Reset the start time (useful for profiling specific sections)
    func resetTimer() {
        DispatchQueue.main.async {
            // Note: This creates a new LogManager instance with fresh timer
            // Call this at the start of a profiling session
            print("[\(self.dateFormatter.string(from: Date()))] Timer reset")
        }
    }
}

/// Log levels with visual indicators
enum LogLevel {
    case debug
    case info
    case warning
    case error
    case success
    
    var icon: String {
        switch self {
        case .debug:
            return "🔍"
        case .info:
            return "ℹ️"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        case .success:
            return "✅"
        }
    }
}

// MARK: - Extension for TimeInterval formatting
extension TimeInterval {
    var formatted: String {
        if self < 1 {
            return String(format: "+%.3fs", self)
        } else if self < 60 {
            return String(format: "+%.2fs", self)
        } else {
            let minutes = Int(self) / 60
            let seconds = Int(self) % 60
            return String(format: "+%dm%02ds", minutes, seconds)
        }
    }
}
