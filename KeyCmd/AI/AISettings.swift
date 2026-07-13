//
//  AISettings.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import Foundation

// MARK: - STT Language

struct STTLanguage: Identifiable, Equatable {
    /// BCP-47 locale identifier used by SFSpeechRecognizer (e.g. "en-US", "zh-Hans").
    let id: String
    /// Human-readable label shown in the UI.
    let displayName: String
    /// Short language code passed to whisper.cpp (e.g. "en", "zh", "ja").
    let whisperCode: String

    static let supported: [STTLanguage] = [
        STTLanguage(id: "en-US",    displayName: "English (US)",           whisperCode: "en"),
        STTLanguage(id: "en-GB",    displayName: "English (UK)",           whisperCode: "en"),
        STTLanguage(id: "zh-Hans",  displayName: "中文（简体）",              whisperCode: "zh"),
        STTLanguage(id: "zh-Hant",  displayName: "中文（繁體）",              whisperCode: "zh"),
        STTLanguage(id: "zh-HK",    displayName: "粵語（廣東話）",             whisperCode: "yue"),
        STTLanguage(id: "ja",       displayName: "日本語",                  whisperCode: "ja"),
        STTLanguage(id: "ko",       displayName: "한국어",                  whisperCode: "ko"),
        STTLanguage(id: "fr-FR",    displayName: "Français",               whisperCode: "fr"),
        STTLanguage(id: "de-DE",    displayName: "Deutsch",                whisperCode: "de"),
        STTLanguage(id: "es-ES",    displayName: "Español",                whisperCode: "es"),
        STTLanguage(id: "it-IT",    displayName: "Italiano",               whisperCode: "it"),
        STTLanguage(id: "pt-PT",    displayName: "Português",              whisperCode: "pt"),
        STTLanguage(id: "ru-RU",    displayName: "Русский",                whisperCode: "ru"),
        STTLanguage(id: "ar",       displayName: "العربية",                whisperCode: "ar"),
        STTLanguage(id: "hi-IN",    displayName: "हिन्दी",                  whisperCode: "hi"),
    ]

    static func from(localeId: String) -> STTLanguage {
        supported.first { $0.id == localeId } ?? supported[0]
    }
}

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
    
    @Published var sttEngine: SpeechEngineType {
        didSet { UserDefaults.standard.set(sttEngine.rawValue, forKey: "AISettings.sttEngine") }
    }

    @Published var sttLocale: String {
        didSet {
            UserDefaults.standard.set(sttLocale, forKey: "AISettings.sttLocale")
            NotificationCenter.default.post(name: NSNotification.Name("STTLocaleChanged"), object: nil)
        }
    }

    /// Convenience accessor returning the full `STTLanguage` for the current locale.
    var currentSTTLanguage: STTLanguage { STTLanguage.from(localeId: sttLocale) }

    /// Inter-key BLE HID delay in milliseconds. Default 10 ms. Configurable in General Settings.
    @Published var bleKeyDelayMs: Int {
        didSet { UserDefaults.standard.set(bleKeyDelayMs, forKey: "AISettings.bleKeyDelayMs") }
    }

    @Published var targetOS: TargetOS {
        didSet {
            UserDefaults.standard.set(targetOS.rawValue, forKey: "AISettings.targetOS")
            // Refresh the command assistant prompt to reflect the new OS
            if selectedSystemPromptRole == "command_assistant" {
                refreshCommandAssistantPrompt()
            }
        }
    }

    /// Max terminal steps the planner can emit in a single plan. Hard cap prevents runaway plans.
    @Published var agentMaxSteps: Int {
        didSet { UserDefaults.standard.set(agentMaxSteps, forKey: "AISettings.agentMaxSteps") }
    }

    /// Max times the agent will retry failed terminal steps with alternative commands.
    @Published var agentMaxRetries: Int {
        didSet { UserDefaults.standard.set(agentMaxRetries, forKey: "AISettings.agentMaxRetries") }
    }
    
    // MARK: - System Prompt Roles (sourced from AIConfigManager)

    /// Live list of roles loaded from AIConfig.json (or server).
    var systemPromptRoles: [SystemPromptRole] {
        AIConfigManager.shared.roles
    }
    
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
            // First launch: build provider list from config presets
            let presets = AIConfigManager.shared.providerPresets
            if !presets.isEmpty {
                loadedProviders = presets.map { preset in
                    AIProvider(name: preset.name,
                               apiBaseURL: preset.apiBaseURL,
                               modelName: preset.modelName,
                               apiKeyOptional: preset.apiKeyOptional)
                }
            } else {
                // Absolute fallback if the config bundle is missing
                loadedProviders = [AIProvider(name: "OpenAI",
                                              apiBaseURL: "https://api.openai.com/v1",
                                              modelName: "gpt-4o")]
            }
        }
        var mutableProviders = loadedProviders

        // Migration: ensure Local Qwen presets exist and have apiKeyOptional=true
        for i in mutableProviders.indices {
            if mutableProviders[i].apiBaseURL.hasPrefix("local://") && !mutableProviders[i].apiKeyOptional {
                mutableProviders[i].apiKeyOptional = true
            }
        }
        if !mutableProviders.contains(where: { $0.apiBaseURL == "local://qwen3-0.6b" }) {
            let smallPreset = AIProvider(name: "Local Qwen 0.6B",
                                         apiBaseURL: "local://qwen3-0.6b",
                                         modelName: "Qwen3-0.6B-4bit",
                                         apiKeyOptional: true)
            mutableProviders.append(smallPreset)
        }
        if !mutableProviders.contains(where: { $0.apiBaseURL == "local://qwen3-1.7b" }) {
            let largePreset = AIProvider(name: "Local Qwen 1.7B",
                                          apiBaseURL: "local://qwen3-1.7b",
                                          modelName: "Qwen3-1.7B-4bit",
                                          apiKeyOptional: true)
            mutableProviders.append(largePreset)
        }

        self.providers = mutableProviders
        
        // Initialize selectedProviderId
        let providerId: String
        if let savedId = UserDefaults.standard.string(forKey: "AISettings.selectedProviderId") {
            providerId = savedId
        } else {
            // Pick the provider whose name matches the config default, else first
            let defaultName = AIConfigManager.shared.defaults?.providerName ?? ""
            let matched = loadedProviders.first { $0.name == defaultName }
            providerId = (matched ?? loadedProviders.first)?.id.uuidString ?? UUID().uuidString
        }
        self.selectedProviderId = providerId

        // Initialize selectedSystemPromptRole
        let configDefaultRole = AIConfigManager.shared.defaults?.role ?? "text_refinement"
        let roleId = UserDefaults.standard.string(forKey: "AISettings.selectedSystemPromptRole") ?? configDefaultRole
        self.selectedSystemPromptRole = roleId
        
        // Initialize systemPrompt
        let prompt: String
        if let savedPrompt = UserDefaults.standard.string(forKey: "AISettings.systemPrompt"), !savedPrompt.isEmpty {
            prompt = savedPrompt
        } else {
            let roles = AIConfigManager.shared.roles
            prompt = roles.first(where: { $0.id == roleId })?.prompt ?? roles.first?.prompt ?? ""
        }
        self.systemPrompt = prompt

        // Initialize sttEngine
        let configDefaultEngine = AIConfigManager.shared.defaults?.sttEngine ?? SpeechEngineType.apple.rawValue
        let engineRaw = UserDefaults.standard.string(forKey: "AISettings.sttEngine") ?? configDefaultEngine
        self.sttEngine = SpeechEngineType(rawValue: engineRaw) ?? .apple

        // Initialize sttLocale
        self.sttLocale = UserDefaults.standard.string(forKey: "AISettings.sttLocale") ?? "en-US"

        // Initialize bleKeyDelayMs (default 10 ms)
        self.bleKeyDelayMs = UserDefaults.standard.object(forKey: "AISettings.bleKeyDelayMs") as? Int ?? 10

        // Initialize targetOS
        let osRaw = UserDefaults.standard.string(forKey: "AISettings.targetOS") ?? TargetOS.linux.rawValue
        self.targetOS = TargetOS(rawValue: osRaw) ?? .linux

        // Initialize agent limits (ponytail: hardcoded defaults — change via Settings UI)
        self.agentMaxSteps = UserDefaults.standard.object(forKey: "AISettings.agentMaxSteps") as? Int ?? 10
        self.agentMaxRetries = UserDefaults.standard.object(forKey: "AISettings.agentMaxRetries") as? Int ?? 3

        updateAPIKeyStatus()

        // If command_assistant role is active, ensure systemPrompt reflects the stored OS
        if self.selectedSystemPromptRole == "command_assistant" {
            if let resolved = AIConfigManager.shared.resolvedCommandPrompt(for: self.targetOS) {
                self.systemPrompt = resolved
            }
        }
    }
    
    // MARK: - Provider Management
    var selectedProvider: AIProvider? {
        // First try to match by UUID (for user-added providers)
        if let provider = providers.first(where: { $0.id.uuidString == selectedProviderId }) {
            return provider
        }
        // Fallback: match by name (for config-loaded providers with new UUIDs)
        return providers.first(where: { $0.name == selectedProviderId })
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
        guard providers.contains(where: { $0.id == providerId }) else {
            return
        }
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
        return AIConfigManager.shared.role(id: id)
    }

    /// Returns the effective prompt for a given role ID.
    /// Checks UserDefaults for a custom override first, then falls back to the config default.
    func effectivePrompt(for roleId: String) -> String {
        let key = "AgentSettings.\(roleId)Prompt"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        return getSystemPromptRole(id: roleId)?.prompt ?? ""
    }
    
    // MARK: - Update System Prompt from Role
    func setSystemPromptRole(_ roleId: String) {
        selectedSystemPromptRole = roleId
        if roleId == "command_assistant" {
            refreshCommandAssistantPrompt()
        } else if let role = getSystemPromptRole(id: roleId), roleId != "custom" {
            systemPrompt = role.prompt
        }
    }

    /// Reload the command-assistant system prompt for the current target OS.
    func refreshCommandAssistantPrompt() {
        if let resolved = AIConfigManager.shared.resolvedCommandPrompt(for: targetOS) {
            systemPrompt = resolved
        } else if let role = getSystemPromptRole(id: "command_assistant") {
            // Fallback to the generic command_assistant.md if OS-specific file is missing.
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
        return hasAPIKey(for: targetProvider) && !targetProvider.apiBaseURL.isEmpty && !targetProvider.modelName.isEmpty
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
        let defaultRoleId = AIConfigManager.shared.defaults?.role ?? "text_refinement"
        selectedSystemPromptRole = defaultRoleId
        systemPrompt = AIConfigManager.shared.role(id: defaultRoleId)?.prompt
            ?? AIConfigManager.shared.roles.first?.prompt ?? ""
        let defaultProviderName = AIConfigManager.shared.defaults?.providerName ?? ""
        selectedProviderId = providers.first { $0.name == defaultProviderName }?.id.uuidString
            ?? providers.first?.id.uuidString ?? ""
        let defaultEngineRaw = AIConfigManager.shared.defaults?.sttEngine ?? SpeechEngineType.apple.rawValue
        sttEngine = SpeechEngineType(rawValue: defaultEngineRaw) ?? .apple
        sttLocale = "en-US"
        clearAPIKey()
    }
}
