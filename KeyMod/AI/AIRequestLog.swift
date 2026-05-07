//
//  AIRequestLog.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

// MARK: - AI Request Log Model
struct AIRequestLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let provider: String
    let model: String
    let systemPrompt: String
    let inputText: String
    let outputText: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let success: Bool
    let errorMessage: String?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        provider: String,
        model: String,
        systemPrompt: String = "",
        inputText: String,
        outputText: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.inputText = inputText
        self.outputText = outputText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.success = success
        self.errorMessage = errorMessage
    }
    
    // Formatted timestamp string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    // Formatted tokens info
    var tokensInfo: String {
        if let total = totalTokens {
            return "Tokens: \(total)"
        } else if let input = inputTokens, let output = outputTokens {
            return "Tokens: \(input + output)"
        } else if let input = inputTokens {
            return "Input: \(input) tokens"
        } else {
            return "Token count unavailable"
        }
    }
}

// MARK: - Request Statistics
struct AIRequestStatistics {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var totalTokensUsed: Int = 0
    
    var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests) * 100
    }
}
