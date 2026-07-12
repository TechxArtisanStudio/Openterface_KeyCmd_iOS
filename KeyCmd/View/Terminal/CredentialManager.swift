import Foundation

/// Manages SSH credential profiles.
/// Profile metadata stored in UserDefaults (JSON), passwords in Keychain.
class CredentialManager {
    static let shared = CredentialManager()

    static let defaultKeyCmdHost = "192.168.12.1"

    private let prefsKey = "credential_profiles"
    private let activeIdKey = "credential_active_id"
    private let defaults = UserDefaults.standard

    // MARK: - CRUD

    /// Add a new profile. First profile becomes active automatically.
    func addProfile(_ profile: CredentialProfile, password: String = "") {
        var profiles = getAllProfiles()
        var p = profile
        if profiles.isEmpty {
            p.isActive = true
            defaults.set(p.id, forKey: activeIdKey)
        }
        profiles.append(p)
        saveProfiles(profiles)
        if !password.isEmpty {
            KeychainHelper.shared.save(key: passwordKey(for: p.id), value: password)
        }
    }

    /// Update an existing profile. If not found, adds it.
    func updateProfile(_ profile: CredentialProfile, password: String? = nil) {
        var profiles = getAllProfiles()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            var p = profile
            p.updatedAt = Date().timeIntervalSince1970
            profiles[idx] = p
            saveProfiles(profiles)
        } else {
            addProfile(profile, password: password ?? "")
            return
        }
        if let pw = password {
            KeychainHelper.shared.save(key: passwordKey(for: profile.id), value: pw)
        }
    }

    /// Delete a profile by ID.
    func deleteProfile(id: String) {
        var profiles = getAllProfiles()
        let wasActive = profiles.first(where: { $0.id == id })?.isActive ?? false
        profiles.removeAll(where: { $0.id == id })
        if wasActive {
            if let first = profiles.first {
                var f = first
                f.isActive = true
                profiles[0] = f
                defaults.set(f.id, forKey: activeIdKey)
            } else {
                defaults.removeObject(forKey: activeIdKey)
            }
        }
        saveProfiles(profiles)
        KeychainHelper.shared.delete(key: passwordKey(for: id))
    }

    /// Get a profile by ID.
    func getProfile(id: String) -> CredentialProfile? {
        getAllProfiles().first(where: { $0.id == id })
    }

    /// Get all profiles.
    func getAllProfiles() -> [CredentialProfile] {
        guard let data = defaults.data(forKey: prefsKey),
              let profiles = try? JSONDecoder().decode([CredentialProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    /// Get the active profile.
    func getActiveProfile() -> CredentialProfile? {
        if let activeId = defaults.string(forKey: activeIdKey) {
            return getProfile(id: activeId)
        }
        // Fallback: find first profile marked active
        let profiles = getAllProfiles()
        if let active = profiles.first(where: { $0.isActive }) {
            defaults.set(active.id, forKey: activeIdKey)
            return active
        }
        return nil
    }

    /// Set the active profile by ID.
    func setActiveProfileId(_ id: String) {
        var profiles = getAllProfiles()
        for i in profiles.indices {
            profiles[i].isActive = profiles[i].id == id
        }
        saveProfiles(profiles)
        defaults.set(id, forKey: activeIdKey)
    }

    /// Clear the active profile (show OS target instead).
    func clearActiveProfile() {
        defaults.removeObject(forKey: activeIdKey)
        // Also clear isActive flags so the fallback doesn't pick up a profile
        var profiles = getAllProfiles()
        for i in profiles.indices {
            profiles[i].isActive = false
        }
        saveProfiles(profiles)
    }

    /// Get the password for a profile from Keychain.
    func getPassword(for profileId: String) -> String {
        KeychainHelper.shared.retrieve(key: passwordKey(for: profileId)) ?? ""
    }

    /// Get all unique tags across all profiles, sorted.
    func getAllTags() -> [String] {
        Array(Set(getAllProfiles().flatMap(\.tags))).sorted()
    }

    /// Seed a default KeyCmd profile if no profiles exist.
    func ensureDefaultKeyCmdProfile() {
        guard getAllProfiles().isEmpty else { return }
        var profile = CredentialProfile(
            name: "KeyCmd default",
            host: Self.defaultKeyCmdHost,
            port: 22,
            username: "root"
        )
        profile.notes = "Default KeyCmd hardware SSH endpoint."
        addProfile(profile)
    }

    // MARK: - Private

    private func saveProfiles(_ profiles: [CredentialProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: prefsKey)
        }
    }

    private func passwordKey(for profileId: String) -> String {
        "credential_pw_\(profileId)"
    }
}
