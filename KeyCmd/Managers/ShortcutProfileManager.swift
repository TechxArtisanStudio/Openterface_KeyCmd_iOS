//
//  ShortcutProfileManager.swift
//  KeyMod
//
//  Singleton ObservableObject that owns all shortcut profiles.
//  - Built-in profiles are loaded from bundled JSON files in the app bundle (Profiles/).
//  - User-created profiles are stored as JSON files in the app's Documents directory.
//  - "My Shortcuts" is persisted per profile using UserDefaults with the key
//    "MyShortcuts_<profileId>".
//

import Foundation
import Combine

class ShortcutProfileManager: ObservableObject {
    static let shared = ShortcutProfileManager()

    // MARK: - Published state

    @Published var builtInProfiles: [ShortcutProfileData] = []
    @Published var userProfiles: [ShortcutProfileData] = []

    /// Combined list: built-in first, then user-created.
    var allProfiles: [ShortcutProfileData] { builtInProfiles + userProfiles }

    /// The currently active profile ID. Changes trigger @Published updates.
    @Published var activeProfileId = "" {
        didSet {
            userDefaults.set(activeProfileId, forKey: activeProfileKey)
        }
    }

    /// The active profile data object (nil if ID is invalid).
    var activeProfile: ShortcutProfileData? {
        allProfiles.first { $0.id == activeProfileId }
    }

    /// All profiles available for picking in the profile switcher.
    var profilesForPicking: [ShortcutProfileData] { allProfiles }

    // MARK: - Private

    private let userDefaults = UserDefaults.standard
    private let activeProfileKey = "ShortcutProfiles_activeProfileId"
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Names of JSON files to load as built-in profiles, in display order.
    private let builtInFileNames = ["standard", "blender", "kicad", "nomad", "fusion360", "photoshop", "vscode"]

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Init

    private init() {
        loadBuiltInProfiles()
        loadUserProfiles()
        // Restore last active profile, default to first built-in
        let lastId = userDefaults.string(forKey: activeProfileKey)
            ?? builtInFileNames.first
        self.activeProfileId = lastId ?? ""
    }

    // MARK: - Built-in profiles

    private func loadBuiltInProfiles() {
        builtInProfiles = builtInFileNames.compactMap { name in
            // Try subdirectory first (folder reference), then bundle root (file-system-synced group)
            let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Profiles")
                   ?? Bundle.main.url(forResource: name, withExtension: "json")
            guard let url else {
                LogManager.shared.log("ShortcutProfileManager: Could not find \(name).json in bundle", category: "Profile", level: .warning)
                return nil
            }
            return loadProfile(from: url)
        }
    }

    // MARK: - User profiles

    private var userProfilesURL: URL {
        documentsURL.appendingPathComponent("ShortcutProfiles", isDirectory: true)
    }

    private func loadUserProfiles() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: userProfilesURL.path) else { return }

        do {
            let files = try fm.contentsOfDirectory(at: userProfilesURL,
                                                   includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            userProfiles = files.compactMap { loadProfile(from: $0) }
        } catch {
            LogManager.shared.log("ShortcutProfileManager: Failed to list user profiles – \(error)", category: "Profile", level: .warning)
        }
    }

    private func loadProfile(from url: URL) -> ShortcutProfileData? {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ShortcutProfileData.self, from: data)
        } catch {
            LogManager.shared.log("ShortcutProfileManager: Failed to decode \(url.lastPathComponent) – \(error)", category: "Profile", level: .warning)
            return nil
        }
    }

    /// Imports a JSON file as a new user profile.
    /// - Parameter data: Raw JSON data conforming to `ShortcutProfileData`.
    /// - Throws: `DecodingError` if JSON is malformed, or a file-system error on save failure.
    func addCustomProfile(from data: Data) throws {
        var profile = try decoder.decode(ShortcutProfileData.self, from: data)

        // Ensure the id is unique — append a suffix if it conflicts.
        if allProfiles.contains(where: { $0.id == profile.id }) {
            let newId = profile.id + "_" + UUID().uuidString.prefix(8)
            profile = ShortcutProfileData(
                id: String(newId),
                name: profile.name,
                icon: profile.icon,
                themeColorHex: profile.themeColorHex,
                hasNumpad: profile.hasNumpad,
                categories: profile.categories,
                numpad: profile.numpad
            )
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: userProfilesURL.path) {
            try fm.createDirectory(at: userProfilesURL, withIntermediateDirectories: true)
        }

        let fileURL = userProfilesURL.appendingPathComponent("\(profile.id).json")
        let encoded = try encoder.encode(profile)
        try encoded.write(to: fileURL, options: .atomic)

        DispatchQueue.main.async { [weak self] in
            self?.userProfiles.append(profile)
        }
    }

    /// Deletes a user-created profile and its persisted My Shortcuts data.
    func deleteUserProfile(id: String) {
        let fileURL = userProfilesURL.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: fileURL)
        userDefaults.removeObject(forKey: myShortcutsKey(for: id))
        userProfiles.removeAll { $0.id == id }
    }

    // MARK: - My Shortcuts persistence

    private func myShortcutsKey(for profileId: String) -> String {
        "MyShortcuts_\(profileId)"
    }

    /// Returns the user's saved "My Shortcuts" list for the given profile.
    func myShortcuts(for profileId: String) -> [ShortcutItem] {
        guard let data = userDefaults.data(forKey: myShortcutsKey(for: profileId)),
              let items = try? decoder.decode([ShortcutItem].self, from: data)
        else { return [] }
        return items
    }

    /// Persists the user's "My Shortcuts" list for the given profile.
    func updateMyShortcuts(for profileId: String, items: [ShortcutItem]) {
        guard let data = try? encoder.encode(items) else { return }
        userDefaults.set(data, forKey: myShortcutsKey(for: profileId))
    }

    // MARK: - Shortcut mutation (user profiles only)

    func isUserProfile(id: String) -> Bool {
        userProfiles.contains { $0.id == id }
    }

    /// Adds a shortcut to a specific category in a user profile.
    /// If `categoryId` is nil, adds to the first available category.
    func addShortcut(_ item: ShortcutItem, toCategoryId categoryId: String?, inProfileId profileId: String) {
        guard let profIdx = userProfiles.firstIndex(where: { $0.id == profileId }) else { return }
        let profile = userProfiles[profIdx]
        let targetId = categoryId ?? profile.categories.first?.id
        let cats: [ShortcutCategoryData] = profile.categories.map { cat in
            guard cat.id == targetId else { return cat }
            return ShortcutCategoryData(id: cat.id, name: cat.name, icon: cat.icon,
                                        colorHex: cat.colorHex,
                                        shortcuts: cat.shortcuts + [item])
        }
        saveUserProfile(ShortcutProfileData(id: profile.id, name: profile.name,
                                            icon: profile.icon, themeColorHex: profile.themeColorHex,
                                            hasNumpad: profile.hasNumpad, categories: cats,
                                            numpad: profile.numpad))
    }

    /// Updates an existing shortcut (by id) in all categories of a user profile.
    func updateShortcutInProfile(_ item: ShortcutItem, inProfileId profileId: String) {
        guard let profIdx = userProfiles.firstIndex(where: { $0.id == profileId }) else { return }
        let profile = userProfiles[profIdx]
        let cats: [ShortcutCategoryData] = profile.categories.map { cat in
            ShortcutCategoryData(id: cat.id, name: cat.name, icon: cat.icon,
                                 colorHex: cat.colorHex,
                                 shortcuts: cat.shortcuts.map { $0.id == item.id ? item : $0 })
        }
        saveUserProfile(ShortcutProfileData(id: profile.id, name: profile.name,
                                            icon: profile.icon, themeColorHex: profile.themeColorHex,
                                            hasNumpad: profile.hasNumpad, categories: cats,
                                            numpad: profile.numpad))
        // Keep My Shortcuts in sync
        var mine = myShortcuts(for: profileId)
        mine = mine.map { $0.id == item.id ? item : $0 }
        updateMyShortcuts(for: profileId, items: mine)
    }

    /// Removes a shortcut (by id) from all categories and My Shortcuts of a user profile.
    func deleteShortcutFromProfile(shortcutId: String, inProfileId profileId: String) {
        guard let profIdx = userProfiles.firstIndex(where: { $0.id == profileId }) else { return }
        let profile = userProfiles[profIdx]
        let cats: [ShortcutCategoryData] = profile.categories.map { cat in
            ShortcutCategoryData(id: cat.id, name: cat.name, icon: cat.icon,
                                 colorHex: cat.colorHex,
                                 shortcuts: cat.shortcuts.filter { $0.id != shortcutId })
        }
        saveUserProfile(ShortcutProfileData(id: profile.id, name: profile.name,
                                            icon: profile.icon, themeColorHex: profile.themeColorHex,
                                            hasNumpad: profile.hasNumpad, categories: cats,
                                            numpad: profile.numpad))
        var mine = myShortcuts(for: profileId)
        mine.removeAll { $0.id == shortcutId }
        updateMyShortcuts(for: profileId, items: mine)
    }

    private func saveUserProfile(_ profile: ShortcutProfileData) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: userProfilesURL.path) {
            try? fm.createDirectory(at: userProfilesURL, withIntermediateDirectories: true)
        }
        let fileURL = userProfilesURL.appendingPathComponent("\(profile.id).json")
        if let data = try? encoder.encode(profile) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let idx = userProfiles.firstIndex(where: { $0.id == profile.id }) {
            userProfiles[idx] = profile
        }
    }

    // MARK: - Create blank user profile

    /// Creates a new empty user profile with the given display name and saves it to disk.
    func createUserProfile(name: String) {
        let profile = ShortcutProfileData(
            id: UUID().uuidString,
            name: name,
            icon: "keyboard",
            themeColorHex: "#29B6F6",
            hasNumpad: false,
            categories: [
                ShortcutCategoryData(
                    id: "general",
                    name: "General",
                    icon: nil,
                    colorHex: "#29B6F6",
                    shortcuts: []
                )
            ],
            numpad: nil
        )
        guard let data = try? encoder.encode(profile) else { return }
        try? addCustomProfile(from: data)
    }
}
