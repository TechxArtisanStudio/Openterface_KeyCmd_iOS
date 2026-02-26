//
//  AISettings.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

class AISettings: ObservableObject {
    // MARK: - Published Properties
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "AISettings.isEnabled") }
    }
    
    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: "AISettings.apiBaseURL") }
    }
    
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "AISettings.modelName") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "AISettings.systemPrompt") }
    }
    
    @Published var apiKeyStatus: String = "Not Configured" // Display-only, not persisted
    
    // MARK: - Constants
    private let apiKeyKeychainKey = "AISettings.apiKey"
    private let defaultBaseURL = "https://api.openai.com/v1"
    private let defaultModel = "gpt-3.5-turbo"
    private let defaultSystemPrompt = "You are a helpful assistant. The user will provide voice-transcribed text. Your task is to:\n1. Check the user's intention\n2. Correct any speech recognition errors\n3. Refine the text for clarity and completeness\n\nRespond with ONLY the refined text, no explanations."
    
    // MARK: - Singleton
    static let shared = AISettings()
    
    // MARK: - Initialization
    private init() {
        // Load from UserDefaults with defaults
        self.isEnabled = UserDefaults.standard.object(forKey: "AISettings.isEnabled") as? Bool ?? false
        self.apiBaseURL = UserDefaults.standard.string(forKey: "AISettings.apiBaseURL") ?? defaultBaseURL
        self.modelName = UserDefaults.standard.string(forKey: "AISettings.modelName") ?? defaultModel
        self.systemPrompt = UserDefaults.standard.string(forKey: "AISettings.systemPrompt") ?? defaultSystemPrompt
        
        updateAPIKeyStatus()
    }
    
    // MARK: - API Key Management (Keychain)
    func saveAPIKey(_ key: String) {
        KeychainHelper.shared.save(key: apiKeyKeychainKey, value: key)
        updateAPIKeyStatus()
    }
    
    func getAPIKey() -> String? {
        return KeychainHelper.shared.retrieve(key: apiKeyKeychainKey)
    }
    
    func clearAPIKey() {
        KeychainHelper.shared.delete(key: apiKeyKeychainKey)
        updateAPIKeyStatus()
    }
    
    func hasAPIKey() -> Bool {
        return getAPIKey() != nil && !(getAPIKey()?.isEmpty ?? true)
    }
    
    private func updateAPIKeyStatus() {
        if hasAPIKey() {
            apiKeyStatus = "✓ Configured"
        } else {
            apiKeyStatus = "✗ Not Configured"
        }
    }
    
    // MARK: - Validation
    func isConfigured() -> Bool {
        return isEnabled && hasAPIKey() && !apiBaseURL.isEmpty && !modelName.isEmpty
    }
    
    func getValidationError() -> String? {
        guard isEnabled else { return nil }
        
        if !hasAPIKey() {
            return "API key not configured"
        }
        if apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API base URL is empty"
        }
        if modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Model name is empty"
        }
        return nil
    }
    
    // MARK: - Reset to Defaults
    func resetToDefaults() {
        isEnabled = false
        apiBaseURL = defaultBaseURL
        modelName = defaultModel
        systemPrompt = defaultSystemPrompt
        clearAPIKey()
    }
}
