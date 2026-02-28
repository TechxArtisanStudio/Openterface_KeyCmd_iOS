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

    private let githubTokenKeychainKey = "RemoteSettings.githubToken"

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

    // MARK: - Keychain-backed token

    /// Reading/writing this property accesses the Keychain directly.
    /// `objectWillChange` is fired manually so SwiftUI observes the change.
    var githubToken: String {
        get {
            KeychainHelper.shared.retrieve(key: githubTokenKeychainKey) ?? ""
        }
        set {
            objectWillChange.send()
            if newValue.isEmpty {
                KeychainHelper.shared.delete(key: githubTokenKeychainKey)
            } else {
                KeychainHelper.shared.save(key: githubTokenKeychainKey, value: newValue)
            }
        }
    }

    // MARK: - Init

    private init() {
        githubRepo     = UserDefaults.standard.string(forKey: "RemoteSettings.repo")     ?? ""
        githubWorkflow = UserDefaults.standard.string(forKey: "RemoteSettings.workflow") ?? "start-server.yml"
        githubRef      = UserDefaults.standard.string(forKey: "RemoteSettings.ref")      ?? "main"
        let saved = UserDefaults.standard.integer(forKey: "RemoteSettings.duration")
        sessionDurationMinutes = saved > 0 ? saved : 10
    }

    // MARK: - Derived helpers

    var isConfigured: Bool {
        !githubToken.isEmpty && !githubRepo.isEmpty
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
