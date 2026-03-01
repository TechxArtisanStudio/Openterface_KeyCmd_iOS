//
//  RemoteSettings.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import Foundation

/// Persists GitHub configuration for the remote session feature.
/// Sensitive token is stored in Keychain; all other values use UserDefaults.
class RemoteSettings: ObservableObject {

    static let shared = RemoteSettings()

    // MARK: - Persisted properties

    @Published var githubRepo: String {
        didSet { UserDefaults.standard.set(githubRepo, forKey: "RemoteSettings.repo") }
    }

    /// The workflow filename, e.g. "start-server.yml"
    @Published var githubWorkflow: String {
        didSet { UserDefaults.standard.set(githubWorkflow, forKey: "RemoteSettings.workflow") }
    }

    /// The branch / tag / SHA the workflow runs on (usually "main")
    @Published var githubRef: String {
        didSet { UserDefaults.standard.set(githubRef, forKey: "RemoteSettings.ref") }
    }

    @Published var sessionDurationMinutes: Int {
        didSet { UserDefaults.standard.set(sessionDurationMinutes, forKey: "RemoteSettings.duration") }
    }

    /// Timestamp when the current tunnel URL was generated (for staleness validation)
    @Published var tunnelURLTimestamp: Date? {
        didSet {
            if let timestamp = tunnelURLTimestamp {
                UserDefaults.standard.set(timestamp, forKey: "RemoteSettings.tunnelURLTimestamp")
            } else {
                UserDefaults.standard.removeObject(forKey: "RemoteSettings.tunnelURLTimestamp")
            }
        }
    }

    // MARK: - Keychain-backed token (OAuth token from GitHub)

    /// GitHub OAuth access token from GitHubOAuthManager
    var githubToken: String {
        get {
            GitHubOAuthManager.shared.accessToken
        }
    }
    
    /// Whether user is authenticated with GitHub via OAuth
    var isGitHubAuthenticated: Bool {
        GitHubOAuthManager.shared.isAuthenticated
    }
    
    /// GitHub username from OAuth profile
    var githubUsername: String {
        GitHubOAuthManager.shared.username
    }

    // MARK: - Init

    private init() {
        githubRepo     = UserDefaults.standard.string(forKey: "RemoteSettings.repo")     ?? ""
        githubWorkflow = UserDefaults.standard.string(forKey: "RemoteSettings.workflow") ?? "start-server.yml"
        githubRef      = UserDefaults.standard.string(forKey: "RemoteSettings.ref")      ?? "main"
        let saved = UserDefaults.standard.integer(forKey: "RemoteSettings.duration")
        sessionDurationMinutes = saved > 0 ? saved : 10
        tunnelURLTimestamp = UserDefaults.standard.object(forKey: "RemoteSettings.tunnelURLTimestamp") as? Date
    }

    // MARK: - Derived helpers

    var isConfigured: Bool {
        GitHubOAuthManager.shared.isAuthenticated && !githubRepo.isEmpty
    }

    var parsedOwner: String {
        let parts = githubRepo.split(separator: "/")
        return parts.count >= 1 ? String(parts[0]) : ""
    }

    var parsedRepoName: String {
        let parts = githubRepo.split(separator: "/")
        return parts.count >= 2 ? String(parts[1]) : ""
    }
}
