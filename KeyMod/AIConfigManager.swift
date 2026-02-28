//
//  AIConfigManager.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import Foundation
import Combine

// MARK: - Data Models

struct SystemPromptRole: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    /// Inline prompt text. Populated either directly from JSON or resolved from `promptFile`.
    var prompt: String
    /// Path to a bundle `.md` file relative to the bundle root (e.g. `"Prompts/text_refinement.md"`).
    /// When present, `prompt` is resolved from this file at load time.
    let promptFile: String?

    // Allow JSON with only one of the two fields
    private enum CodingKeys: String, CodingKey {
        case id, name, description, prompt, promptFile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id          = try container.decode(String.self, forKey: .id)
        name        = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        prompt      = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        promptFile  = try container.decodeIfPresent(String.self, forKey: .promptFile)
    }
}

/// A provider template defined in the config (no API key, no UUID – those are user-specific).
struct AIProviderPreset: Codable {
    let name: String
    let apiBaseURL: String
    let modelName: String
    let apiKeyOptional: Bool
}

/// Default selections shipped/served with the config.
struct AIConfigDefaults: Codable {
    /// Name of the preset provider to select on first launch.
    let providerName: String
    /// ID of the prompt role to select on first launch.
    let role: String
    /// Raw value of `SpeechEngineType` to use on first launch.
    let sttEngine: String
}

struct AIConfig: Codable {
    let version: String
    let defaults: AIConfigDefaults
    let providerPresets: [AIProviderPreset]
    let roles: [SystemPromptRole]
}

// MARK: - AIConfigManager

/// Loads and vends the full AI configuration (provider presets, default selections,
/// prompt roles) from a local JSON bundle or a remote server URL.
/// The bundle acts as the default / offline fallback.
///
/// Future server integration:
///   1. Call `loadFromServer(urlString:)` on app launch (or from Settings).
///   2. On success the downloaded config is cached in UserDefaults and immediately
///      replaces the in-memory config.
///   3. Call `clearServerCache()` to revert to the bundle defaults.
class AIConfigManager: ObservableObject {

    static let shared = AIConfigManager()

    // MARK: Published

    /// The active configuration (bundle or server-loaded).
    @Published private(set) var config: AIConfig?

    /// True while a server request is in flight.
    @Published private(set) var isLoadingFromServer: Bool = false

    /// Populated when the last server request failed.
    @Published private(set) var serverLoadError: String?

    // MARK: Computed helpers

    var roles: [SystemPromptRole]       { config?.roles ?? [] }
    var providerPresets: [AIProviderPreset] { config?.providerPresets ?? [] }
    var defaults: AIConfigDefaults? { config?.defaults }
    var configVersion: String        { config?.version ?? "–" }

    // MARK: Persistence keys

    private enum Keys {
        static let cachedConfig = "AIConfigManager.cachedConfig"
        static let serverURL    = "AIConfigManager.serverURL"
    }

    private let bundleResourceName = "AIConfig"

    // MARK: Init

    private init() {
        if let cached = loadCachedServerConfig() {
            config = cached
        } else {
            config = loadBundleConfig()
        }
    }

    // MARK: - Bundle Loading

    func loadFromBundle() {
        if let bundleConfig = loadBundleConfig() {
            config = bundleConfig
        }
    }

    private func loadBundleConfig() -> AIConfig? {
        guard let url = Bundle.main.url(forResource: bundleResourceName, withExtension: "json") else {
            print("[AIConfigManager] Bundle resource '\(bundleResourceName).json' not found.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            var config = try JSONDecoder().decode(AIConfig.self, from: data)
            config = resolvePromptFiles(in: config, source: .bundle)
            return config
        } catch {
            print("[AIConfigManager] Failed to decode bundle config: \(error)")
            return nil
        }
    }

    // MARK: - Prompt File Resolution

    private enum PromptSource { case bundle }

    /// For any role that has a `promptFile`, load the file contents into `prompt`.
    private func resolvePromptFiles(in config: AIConfig, source: PromptSource) -> AIConfig {
        let resolvedRoles = config.roles.map { role -> SystemPromptRole in
            guard let filePath = role.promptFile, !filePath.isEmpty else { return role }
            var resolved = role

            // Strip extension to get resource name + subdirectory
            let url = URL(fileURLWithPath: filePath)
            let resourceName = url.deletingPathExtension().path  // e.g. "Prompts/text_refinement"
            let ext = url.pathExtension                           // e.g. "md"

            if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: ext),
               let content = try? String(contentsOf: bundleURL, encoding: .utf8) {
                resolved.prompt = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("[AIConfigManager] Could not load prompt file: \(filePath)")
            }
            return resolved
        }
        return AIConfig(version: config.version,
                        defaults: config.defaults,
                        providerPresets: config.providerPresets,
                        roles: resolvedRoles)
    }

    // MARK: - Server Loading

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Keys.serverURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.serverURL) }
    }

    func loadFromServer(url: URL, completion: ((Result<AIConfig, Error>) -> Void)? = nil) {
        isLoadingFromServer = true
        serverLoadError = nil

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingFromServer = false

                if let error {
                    self.serverLoadError = error.localizedDescription
                    completion?(.failure(error))
                    return
                }

                guard let data else {
                    let err = NSError(domain: "AIConfigManager", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Empty server response"])
                    self.serverLoadError = err.localizedDescription
                    completion?(.failure(err))
                    return
                }

                do {
                    var decoded = try JSONDecoder().decode(AIConfig.self, from: data)
                    decoded = self.resolvePromptFiles(in: decoded, source: .bundle)
                    self.config = decoded
                    self.persistServerCache(data)
                    completion?(.success(decoded))
                } catch {
                    self.serverLoadError = "Failed to decode server config: \(error.localizedDescription)"
                    completion?(.failure(error))
                }
            }
        }.resume()
    }

    func loadFromServer(urlString: String, completion: ((Result<AIConfig, Error>) -> Void)? = nil) {
        guard let url = URL(string: urlString) else {
            let err = NSError(domain: "AIConfigManager", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid server URL: \(urlString)"])
            serverLoadError = err.localizedDescription
            completion?(.failure(err))
            return
        }
        serverURL = urlString
        loadFromServer(url: url, completion: completion)
    }

    // MARK: - Cache Management

    func clearServerCache() {
        UserDefaults.standard.removeObject(forKey: Keys.cachedConfig)
        loadFromBundle()
    }

    private func persistServerCache(_ data: Data) {
        UserDefaults.standard.set(data, forKey: Keys.cachedConfig)
    }

    private func loadCachedServerConfig() -> AIConfig? {
        guard let data = UserDefaults.standard.data(forKey: Keys.cachedConfig) else { return nil }
        guard var config = try? JSONDecoder().decode(AIConfig.self, from: data) else { return nil }
        config = resolvePromptFiles(in: config, source: .bundle)
        return config
    }

    // MARK: - Role Helpers

    func role(id: String) -> SystemPromptRole? {
        roles.first { $0.id == id }
    }

    // MARK: - Provider Preset Helpers

    func providerPreset(named name: String) -> AIProviderPreset? {
        providerPresets.first { $0.name == name }
    }
}
