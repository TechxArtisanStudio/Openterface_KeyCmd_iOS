//
//  AITextRefinementManager.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

// MARK: - Error Types
enum AIRefinementError: LocalizedError {
    case noAPIKey
    case invalidConfiguration
    case invalidResponse
    case decodingError(String)
    case networkError(String)
    case apiError(String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key not configured"
        case .invalidConfiguration:
            return "AI settings not properly configured"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .decodingError(let msg):
            return "Failed to decode response: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let msg):
            return "API error: \(msg)"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// MARK: - API Request/Response Models
struct TextRefinementRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double = 0.7
    let max_tokens: Int = 500
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

struct TextRefinementResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finish_reason: String
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }
    
    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

// MARK: - Error Response
struct APIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let param: String?
        let code: String?
    }
}

// MARK: - AITextRefinementManager
class AITextRefinementManager {
    static let shared = AITextRefinementManager()
    
    private let settings = AISettings.shared
    private let logger = LogManager.shared
    
    // MARK: - Refine Text
    func refineText(input: String, completion: @escaping (Result<String, AIRefinementError>) -> Void) {
        // Validate configuration
        guard let validationError = settings.getValidationError() else {
            // Configuration is valid
            performRefinement(input: input, completion: completion)
            return
        }
        
        logger.log("AI refinement validation failed: \(validationError)", category: "AIRefinement", level: .error)
        completion(.failure(.invalidConfiguration))
    }
    
    private func performRefinement(input: String, completion: @escaping (Result<String, AIRefinementError>) -> Void) {
        // Get selected provider
        guard let provider = settings.selectedProvider else {
            logger.log("No AI provider selected", category: "AIRefinement", level: .error)
            completion(.failure(.invalidConfiguration))
            return
        }
        
        // Fetch API key from Keychain (optional for some providers)
        let apiKey = provider.getAPIKey()
        if !provider.apiKeyOptional {
            guard let key = apiKey, !key.isEmpty else {
                logger.log("No API key found for AI refinement", category: "AIRefinement", level: .error)
                completion(.failure(.noAPIKey))
                return
            }
        }
        
        // Build request
        let endpoint = provider.apiBaseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            logger.log("Invalid API endpoint URL: \(endpoint)", category: "AIRefinement", level: .error)
            completion(.failure(.invalidConfiguration))
            return
        }
        
        let request = TextRefinementRequest(
            model: provider.modelName.trimmingCharacters(in: .whitespaces),
            messages: [
                .init(role: "system", content: settings.systemPrompt),
                .init(role: "user", content: input)
            ]
        )
        
        // Build URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only set Authorization header if a key is available
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            logger.log("Failed to encode request: \(error.localizedDescription)", category: "AIRefinement", level: .error)
            completion(.failure(.decodingError(error.localizedDescription)))
            return
        }
        
        logger.log("🤖 Sending text refinement request to \(endpoint)", category: "AIRefinement", level: .info)
        
        // Execute request
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleRefinementResponse(data: data, response: response, error: error, originalText: input, providerName: provider.name, completion: completion)
            }
        }.resume()
    }
    
    private func handleRefinementResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        originalText: String,
        providerName: String,
        completion: @escaping (Result<String, AIRefinementError>) -> Void
    ) {
        // Check for network error
        if let error = error {
            logger.log("Network error during AI refinement: \(error.localizedDescription)", category: "AIRefinement", level: .error)
            // Log failed request
            AIRequestHistoryManager.shared.logRequest(
                provider: providerName,
                model: settings.selectedProvider?.modelName ?? "Unknown",
                input: originalText,
                output: "",
                success: false,
                errorMessage: error.localizedDescription
            )
            completion(.failure(.networkError(error.localizedDescription)))
            return
        }
        
        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            logger.log("AI API response status: \(httpResponse.statusCode)", category: "AIRefinement", level: .info)
            
            if httpResponse.statusCode != 200 {
                // Try to parse error response
                if let data = data {
                    do {
                        let errorResponse = try JSONDecoder().decode(APIErrorResponse.self, from: data)
                        let errorMsg = errorResponse.error.message
                        logger.log("API error (status \(httpResponse.statusCode)): \(errorMsg)", category: "AIRefinement", level: .error)
                        // Log failed request
                        AIRequestHistoryManager.shared.logRequest(
                            provider: providerName,
                            model: settings.selectedProvider?.modelName ?? "Unknown",
                            input: originalText,
                            output: "",
                            success: false,
                            errorMessage: errorMsg
                        )
                        completion(.failure(.apiError(errorMsg)))
                    } catch {
                        logger.log("Failed to parse error response (status \(httpResponse.statusCode))", category: "AIRefinement", level: .error)
                        // Log failed request
                        AIRequestHistoryManager.shared.logRequest(
                            provider: providerName,
                            model: settings.selectedProvider?.modelName ?? "Unknown",
                            input: originalText,
                            output: "",
                            success: false,
                            errorMessage: "HTTP \(httpResponse.statusCode)"
                        )
                        completion(.failure(.apiError("HTTP \(httpResponse.statusCode)")))
                    }
                } else {
                    // Log failed request
                    AIRequestHistoryManager.shared.logRequest(
                        provider: providerName,
                        model: settings.selectedProvider?.modelName ?? "Unknown",
                        input: originalText,
                        output: "",
                        success: false,
                        errorMessage: "HTTP \(httpResponse.statusCode)"
                    )
                    completion(.failure(.apiError("HTTP \(httpResponse.statusCode)")))
                }
                return
            }
        }
        
        // Decode response
        guard let data = data else {
            logger.log("No data returned from AI API", category: "AIRefinement", level: .error)
            // Log failed request
            AIRequestHistoryManager.shared.logRequest(
                provider: providerName,
                model: settings.selectedProvider?.modelName ?? "Unknown",
                input: originalText,
                output: "",
                success: false,
                errorMessage: "No data returned from API"
            )
            completion(.failure(.invalidResponse))
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(TextRefinementResponse.self, from: data)
            logger.log("✅ AI refinement succeeded (tokens used: \(decodedResponse.usage.total_tokens))", category: "AIRefinement", level: .info)
            
            guard let refinedText = decodedResponse.choices.first?.message.content else {
                logger.log("No content in AI response choices", category: "AIRefinement", level: .error)
                // Log failed request
                AIRequestHistoryManager.shared.logRequest(
                    provider: providerName,
                    model: settings.selectedProvider?.modelName ?? "Unknown",
                    input: originalText,
                    output: "",
                    success: false,
                    errorMessage: "No content in response"
                )
                completion(.failure(.invalidResponse))
                return
            }
            
            let cleanedText = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Log successful request
            AIRequestHistoryManager.shared.logRequest(
                provider: providerName,
                model: settings.selectedProvider?.modelName ?? "Unknown",
                input: originalText,
                output: cleanedText,
                inputTokens: decodedResponse.usage.prompt_tokens,
                outputTokens: decodedResponse.usage.completion_tokens,
                totalTokens: decodedResponse.usage.total_tokens,
                success: true
            )
            
            completion(.success(cleanedText))
        } catch {
            logger.log("Failed to decode AI response: \(error.localizedDescription)", category: "AIRefinement", level: .error)
            // Log failed request
            AIRequestHistoryManager.shared.logRequest(
                provider: providerName,
                model: settings.selectedProvider?.modelName ?? "Unknown",
                input: originalText,
                output: "",
                success: false,
                errorMessage: error.localizedDescription
            )
            completion(.failure(.decodingError(error.localizedDescription)))
        }
    }
}
