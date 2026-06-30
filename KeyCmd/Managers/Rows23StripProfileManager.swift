//
//  Rows23StripProfileManager.swift
//  KeyMod
//
//  Manages Rows 2–3 keyboard strip profiles (slot overrides + custom shortcuts).
//  Mirrors Android's Rows23StripProfileManager.
//

import Foundation
import Combine

final class Rows23StripProfileManager: ObservableObject {

    static let shared = Rows23StripProfileManager()

    // MARK: - Published state

    @Published private(set) var profiles: [Rows23StripProfile] = []

    @Published var activeProfileId: String = Rows23StripProfileConstants.defaultProfileId {
        didSet {
            UserDefaults.standard.set(activeProfileId, forKey: Keys.activeId)
        }
    }

    var activeProfile: Rows23StripProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    // MARK: - Private

    private enum Keys {
        static let profilesJson = "StripProfiles_v1_profiles_json"
        static let activeId     = "StripProfiles_v1_active_id"
    }

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Load / Save

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.profilesJson),
           let loaded = try? decoder.decode([Rows23StripProfile].self, from: data) {
            profiles = loaded
        }
        let savedActive = UserDefaults.standard.string(forKey: Keys.activeId)
        activeProfileId = savedActive ?? Rows23StripProfileConstants.defaultProfileId
        ensureBuiltIns()
    }

    func reloadFromStorage() {
        load()
    }

    private func save() {
        guard let data = try? encoder.encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Keys.profilesJson)
    }

    // MARK: - Built-in profiles

    private func ensureBuiltIns() {
        var changed = false

        if !profiles.contains(where: { $0.id == Rows23StripProfileConstants.defaultProfileId }) {
            profiles.insert(Rows23StripProfile(
                id: Rows23StripProfileConstants.defaultProfileId,
                name: "Default"
            ), at: 0)
            changed = true
        }

        let mineIdx = profiles.firstIndex(where: { $0.id == Rows23StripProfileConstants.personalProfileId })
        if mineIdx == nil {
            let insertAt = min(1, profiles.count)
            profiles.insert(Rows23StripProfile(
                id: Rows23StripProfileConstants.personalProfileId,
                name: "Mine"
            ), at: insertAt)
            changed = true
        } else if let idx = mineIdx, profiles[idx].name != "Mine" {
            profiles[idx].name = "Mine"
            changed = true
        }

        if changed { save() }
    }

    // MARK: - CRUD

    func createProfile(name: String) {
        let p = Rows23StripProfile(id: UUID().uuidString, name: name)
        profiles.append(p)
        save()
    }

    func deleteProfile(id: String) {
        guard !Rows23StripProfileConstants.isBuiltIn(id: id) else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = Rows23StripProfileConstants.defaultProfileId
        }
        save()
    }

    func resetProfileToFactory(id: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].slotMap = [:]
        profiles[idx].shortcuts = []
        save()
    }

    func getProfileById(_ id: String) -> Rows23StripProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Import / Export

    /// Import a profile from raw JSON. Assigns a new UUID if the id conflicts.
    func importProfileFromJSON(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }
        do {
            var p = try decoder.decode(Rows23StripProfile.self, from: data)
            if profiles.contains(where: { $0.id == p.id }) {
                p.id = UUID().uuidString
            }
            profiles.append(p)
            save()
        } catch {
            LogManager.shared.log("Rows23StripProfileManager: import failed – \(error)", category: "Profile", level: .warning)
        }
    }

    /// Exports the given profile as a JSON string, or nil on failure.
    func exportProfileAsJSON(_ profile: Rows23StripProfile) -> String? {
        guard let data = try? encoder.encode(profile) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
