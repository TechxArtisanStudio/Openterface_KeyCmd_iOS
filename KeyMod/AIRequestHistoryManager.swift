//
//  AIRequestHistoryManager.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

class AIRequestHistoryManager {
    static let shared = AIRequestHistoryManager()
    
    private let defaultsKey = "AIRequestHistory"
    private let maxRecords = 100  // Keep last 100 records to avoid excessive storage
    
    private init() {}
    
    // MARK: - Request Log CRUD Operations
    
    /// Save a new request log to history
    func logRequest(
        provider: String,
        model: String,
        systemPrompt: String = "",
        input: String,
        output: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        let log = AIRequestLog(
            provider: provider,
            model: model,
            systemPrompt: systemPrompt,
            inputText: input,
            outputText: output,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            success: success,
            errorMessage: errorMessage
        )
        
        var logs = getAllRequests()
        logs.append(log)
        
        // Keep only the last maxRecords entries
        if logs.count > maxRecords {
            logs = Array(logs.suffix(maxRecords))
        }
        
        saveToDefaults(logs)
    }
    
    /// Get all request logs
    func getAllRequests() -> [AIRequestLog] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([AIRequestLog].self, from: data)
        } catch {
            LogManager.shared.log(
                "Failed to decode request history: \(error.localizedDescription)",
                category: "AIRequestHistory",
                level: .error
            )
            return []
        }
    }
    
    /// Get logs for a specific provider
    func getRequestsForProvider(_ provider: String) -> [AIRequestLog] {
        return getAllRequests().filter { $0.provider == provider }
    }
    
    /// Get logs within a date range
    func getRequestsInDateRange(from: Date, to: Date) -> [AIRequestLog] {
        return getAllRequests().filter { $0.timestamp >= from && $0.timestamp <= to }
    }
    
    /// Delete a specific request log
    func deleteRequest(_ id: UUID) {
        var logs = getAllRequests()
        logs.removeAll { $0.id == id }
        saveToDefaults(logs)
    }
    
    /// Clear all request logs
    func clearAllRequests() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
    
    // MARK: - Statistics
    
    /// Get statistics about all requests
    func getStatistics() -> AIRequestStatistics {
        let logs = getAllRequests()
        var stats = AIRequestStatistics()
        
        stats.totalRequests = logs.count
        stats.successfulRequests = logs.filter { $0.success }.count
        stats.failedRequests = logs.filter { !$0.success }.count
        
        // Sum up all tokens
        stats.totalTokensUsed = logs.compactMap { $0.totalTokens }.reduce(0, +)
        
        return stats
    }
    
    /// Get statistics for a specific provider
    func getStatisticsForProvider(_ provider: String) -> AIRequestStatistics {
        let logs = getRequestsForProvider(provider)
        var stats = AIRequestStatistics()
        
        stats.totalRequests = logs.count
        stats.successfulRequests = logs.filter { $0.success }.count
        stats.failedRequests = logs.filter { !$0.success }.count
        stats.totalTokensUsed = logs.compactMap { $0.totalTokens }.reduce(0, +)
        
        return stats
    }
    
    // MARK: - Private Helper
    
    private func saveToDefaults(_ logs: [AIRequestLog]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(logs)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            LogManager.shared.log(
                "Failed to encode request history: \(error.localizedDescription)",
                category: "AIRequestHistory",
                level: .error
            )
        }
    }
}
