//
//  AISettings.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

// MARK: - AI Provider
struct AIProvider: Identifiable, Codable {
    var id: UUID
    var name: String
    var apiBaseURL: String
    var modelName: String
    /// When true, the API key is optional (e.g. local providers like Ollama)
    var apiKeyOptional: Bool
    
    init(id: UUID = UUID(), name: String = "OpenAI", apiBaseURL: String = "https://api.openai.com/v1", modelName: String = "gpt-3.5-turbo", apiKeyOptional: Bool = false) {
        self.id = id
        self.name = name
        self.apiBaseURL = apiBaseURL
        self.modelName = modelName
        self.apiKeyOptional = apiKeyOptional
    }
    
    private func getAPIKeyKeychainKey() -> String {
        return "AISettings.apiKey.\(id.uuidString)"
    }
    
    // MARK: - API Key Management (Bundled with Provider)
    
    /// Save API key for this provider
    func saveAPIKey(_ key: String) {
        KeychainHelper.shared.save(key: getAPIKeyKeychainKey(), value: key)
    }
    
    /// Get API key for this provider
    func getAPIKey() -> String? {
        return KeychainHelper.shared.retrieve(key: getAPIKeyKeychainKey())
    }
    
    /// Check if API key is configured for this provider
    func hasAPIKey() -> Bool {
        if apiKeyOptional { return true }
        guard let apiKey = getAPIKey() else { return false }
        return !apiKey.isEmpty
    }
    
    /// Delete API key for this provider
    func deleteAPIKey() {
        KeychainHelper.shared.delete(key: getAPIKeyKeychainKey())
    }
}

// MARK: - System Prompt Role
struct SystemPromptRole {
    let id: String
    let name: String
    let description: String
    let prompt: String
}

class AISettings: ObservableObject {
    // MARK: - Published Properties
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "AISettings.isEnabled") }
    }
    
    @Published var providers: [AIProvider] {
        didSet { 
            if let encoded = try? JSONEncoder().encode(providers) {
                UserDefaults.standard.set(encoded, forKey: "AISettings.providers")
            }
        }
    }
    
    @Published var selectedProviderId: String {
        didSet { UserDefaults.standard.set(selectedProviderId, forKey: "AISettings.selectedProviderId") }
    }
    
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "AISettings.systemPrompt") }
    }
    
    @Published var selectedSystemPromptRole: String {
        didSet { UserDefaults.standard.set(selectedSystemPromptRole, forKey: "AISettings.selectedSystemPromptRole") }
    }
    
    @Published var apiKeyStatus: String = "Not Configured" // Display-only, not persisted
    
    // MARK: - Constants
    private let defaultBaseURL = "https://api.openai.com/v1"
    private let defaultModel = "gpt-3.5-turbo"
    
    // MARK: - System Prompt Roles
    let systemPromptRoles: [SystemPromptRole] = [
        SystemPromptRole(
            id: "text_refinement",
            name: "Text Refinement",
            description: "Refine voice transcription for clarity",
            prompt: "You are a helpful assistant. The user will provide voice-transcribed text. Your task is to:\n1. Check the user's intention\n2. Correct any speech recognition errors\n3. Refine the text for clarity and completeness\n\nIMPORTANT: Output ONLY printable ASCII characters (ASCII 32-126). Use only standard keyboard-inputtable characters. No special Unicode, emojis, or non-keyboard symbols. No explanations, only the refined text."
        ),
        SystemPromptRole(
            id: "command_assistant",
            name: "Command Assistant",
            description: "Convert voice commands to keyboard/mouse actions",
            prompt: "You are a command interpreter for keyboard and mouse control. The user will provide voice-transcribed commands. Your task is to:\n1. Interpret the voice command\n2. Convert to specific keyboard keys or mouse actions\n3. Output in format: KEY:key_name or MOUSE:action\n4. For key combinations use + (e.g., CTRL+S, ALT+TAB)\n5. For mouse: MOUSE:click, MOUSE:double_click, MOUSE:move_up, MOUSE:move_down, MOUSE:left, MOUSE:right\n6. Use ONLY ASCII keyboard-inputtable characters (ASCII 32-126) in all output\n\nExamples:\n- 'save file' -> KEY:CTRL+S\n- 'open file' -> KEY:CTRL+O\n- 'undo' -> KEY:CTRL+Z\n- 'click' -> MOUSE:click\n- 'double click' -> MOUSE:double_click\n- 'move mouse up' -> MOUSE:move_up\n\nRespond with ONLY the command output (using ASCII 32-126 characters), no explanations."
        ),
        SystemPromptRole(
            id: "custom",
            name: "Custom",
            description: "Use your own system prompt",
            prompt: ""
        )
    ]
    
    // MARK: - Singleton
    static let shared = AISettings()
    
    // MARK: - Initialization
    private init() {
        // Initialize isEnabled first
        self.isEnabled = UserDefaults.standard.object(forKey: "AISettings.isEnabled") as? Bool ?? false
        
        // Initialize providers
        let loadedProviders: [AIProvider]
        if let encodedProviders = UserDefaults.standard.data(forKey: "AISettings.providers"),
           let decodedProviders = try? JSONDecoder().decode([AIProvider].self, from: encodedProviders) {
            loadedProviders = decodedProviders
        } else {
            // Migration: create default provider from old settings
            let oldBaseURL = UserDefaults.standard.string(forKey: "AISettings.apiBaseURL") ?? defaultBaseURL
            let oldModel = UserDefaults.standard.string(forKey: "AISettings.modelName") ?? defaultModel
            loadedProviders = [AIProvider(name: "OpenAI", apiBaseURL: oldBaseURL, modelName: oldModel)]
        }
        self.providers = loadedProviders
        
        // Initialize selectedProviderId
        let providerId: String
        if let savedId = UserDefaults.standard.string(forKey: "AISettings.selectedProviderId") {
            providerId = savedId
        } else {
            providerId = loadedProviders.first?.id.uuidString ?? UUID().uuidString
        }
        self.selectedProviderId = providerId
        
        // Initialize selectedSystemPromptRole
        let roleId = UserDefaults.standard.string(forKey: "AISettings.selectedSystemPromptRole") ?? "text_refinement"
        self.selectedSystemPromptRole = roleId
        
        // Initialize systemPrompt
        let prompt: String
        if let savedPrompt = UserDefaults.standard.string(forKey: "AISettings.systemPrompt"), !savedPrompt.isEmpty {
            prompt = savedPrompt
        } else {
            prompt = systemPromptRoles.first(where: { $0.id == roleId })?.prompt ?? systemPromptRoles[0].prompt
        }
        self.systemPrompt = prompt
        
        updateAPIKeyStatus()
    }
    
    // MARK: - Provider Management
    var selectedProvider: AIProvider? {
        providers.first(where: { $0.id.uuidString == selectedProviderId })
    }
    
    func addProvider(name: String = "New Provider", apiBaseURL: String = "", modelName: String = "") -> AIProvider {
        let newProvider = AIProvider(name: name, apiBaseURL: apiBaseURL, modelName: modelName)
        providers.append(newProvider)
        return newProvider
    }
    
    func updateProvider(_ provider: AIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        }
    }
    
    func deleteProvider(_ providerId: UUID) {
        providers.removeAll(where: { $0.id == providerId })
        // If deleted provider was selected, select the first one
        if selectedProviderId == providerId.uuidString && !providers.isEmpty {
            selectedProviderId = providers[0].id.uuidString
        }
    }
    
    func selectProvider(_ providerId: UUID) {
        selectedProviderId = providerId.uuidString
        updateAPIKeyStatus()
    }
    
    // MARK: - Get System Prompt Role by ID
    func getSystemPromptRole(id: String) -> SystemPromptRole? {
        return systemPromptRoles.first(where: { $0.id == id })
    }
    
    // MARK: - Update System Prompt from Role
    func setSystemPromptRole(_ roleId: String) {
        selectedSystemPromptRole = roleId
        if let role = getSystemPromptRole(id: roleId), roleId != "custom" {
            systemPrompt = role.prompt
        }
    }
    
    // MARK: - API Key Management (Delegates to Provider)
    func saveAPIKey(_ key: String, for provider: AIProvider? = nil) {
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return }
        targetProvider.saveAPIKey(key)
        updateAPIKeyStatus()
    }
    
    func getAPIKey(for provider: AIProvider? = nil) -> String? {
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return nil }
        return targetProvider.getAPIKey()
    }
    
    func clearAPIKey(for provider: AIProvider? = nil) {
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return }
        targetProvider.deleteAPIKey()
        updateAPIKeyStatus()
    }
    
    func hasAPIKey(for provider: AIProvider? = nil) -> Bool {
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return false }
        return targetProvider.hasAPIKey()
    }
    
    func updateAPIKeyStatus() {
        if let provider = selectedProvider, provider.apiKeyOptional {
            let hasKey = provider.getAPIKey().map { !$0.isEmpty } ?? false
            apiKeyStatus = hasKey ? "✓ Configured" : "✓ Not Required"
        } else if hasAPIKey() {
            apiKeyStatus = "✓ Configured"
        } else {
            apiKeyStatus = "✗ Not Configured"
        }
    }
    
    // MARK: - Validation
    func isConfigured(provider: AIProvider? = nil) -> Bool {
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return false }
        return isEnabled && hasAPIKey(for: targetProvider) && !targetProvider.apiBaseURL.isEmpty && !targetProvider.modelName.isEmpty
    }
    
    func getValidationError(provider: AIProvider? = nil) -> String? {
        guard isEnabled else { return nil }
        
        let targetProvider = provider ?? selectedProvider
        guard let targetProvider = targetProvider else { return "No provider selected" }
        
        if !targetProvider.apiKeyOptional && !hasAPIKey(for: targetProvider) {
            return "API key not configured"
        }
        if targetProvider.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API base URL is empty"
        }
        if targetProvider.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Model name is empty"
        }
        return nil
    }
    
    // MARK: - Reset to Defaults
    func resetToDefaults() {
        isEnabled = false
        selectedProviderId = providers.first?.id.uuidString ?? ""
        selectedSystemPromptRole = "text_refinement"
        systemPrompt = systemPromptRoles[0].prompt
        clearAPIKey()
    }
}
