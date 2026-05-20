//
//  GamepadPresetRepository.swift
//  KeyMod
//
//  Preset CRUD, import/export, bundled preset loading.
//  JSON files stored in Application Support/GamepadPresets/.
//  Active preset index stored in UserDefaults.
//

import Foundation
import Combine
import SwiftUI

/// Lightweight reference to a preset (used for list display without loading full document).
struct PresetRef: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var isBuiltin: Bool
    var createdAt: String?
}

class GamepadPresetRepository: ObservableObject {
    @Published var presets: [PresetRef] = []
    @Published var activePresetId: String?

    private let presetsDirectory: URL
    private let userDefaults = UserDefaults.standard
    private let indexKey = "GamepadPresetIndex"
    private let activeKey = "GamepadActivePresetId"
    private let bundledInstalledKey = "GamepadBundledPresetsInstalled"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let container = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.presetsDirectory = container.appendingPathComponent("GamepadPresets", conformingTo: .directory)

        do {
            try FileManager.default.createDirectory(
                at: presetsDirectory, withIntermediateDirectories: true
            )
        } catch {
            print("⚠️ Failed to create presets directory: \(error)")
        }

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        loadIndex()
        loadActivePresetId()
        loadBundledPresetsIfNeeded()
    }

    // MARK: - Index Management

    private func loadIndex() {
        guard let data = userDefaults.data(forKey: indexKey),
              let index = try? decoder.decode([PresetRef].self, from: data) else {
            presets = []
            return
        }
        // Filter out refs whose files no longer exist
        presets = index.filter { ref in
            let url = fileURL(for: ref.id)
            return FileManager.default.fileExists(atPath: url.path)
        }
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? encoder.encode(presets) {
            userDefaults.set(data, forKey: indexKey)
        }
    }

    private func loadActivePresetId() {
        activePresetId = userDefaults.string(forKey: activeKey)
    }

    private func setActivePresetId(_ id: String?) {
        activePresetId = id
        userDefaults.set(id, forKey: activeKey)
    }

    // MARK: - File Operations

    private func fileURL(for id: String) -> URL {
        presetsDirectory.appendingPathComponent("\(id).json")
    }

    /// Load a full preset document from disk.
    func loadDocument(id: String) -> GamepadPresetDocument? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              var document = try? decoder.decode(GamepadPresetDocument.self, from: data) else {
            return nil
        }
        // Upgrade schema version if needed
        if document.schemaVersion < PresetConstants.currentSchemaVersion {
            document = migrateDocument(document)
        }
        return document
    }

    /// Save a full preset document to disk and update the index.
    func saveDocument(_ document: GamepadPresetDocument) {
        let url = fileURL(for: document.meta.id)
        guard let data = try? encoder.encode(document) else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("⚠️ Failed to save preset: \(error)")
            return
        }

        // Update index
        if let idx = presets.firstIndex(where: { $0.id == document.meta.id }) {
            presets[idx].displayName = document.meta.displayName
        } else {
            presets.append(PresetRef(
                id: document.meta.id,
                displayName: document.meta.displayName,
                isBuiltin: false
            ))
        }
        saveIndex()
    }

    /// Delete a preset. Cannot delete built-in presets.
    func deletePreset(id: String) {
        let ref = presets.first(where: { $0.id == id })
        guard let ref = ref, !ref.isBuiltin else { return }

        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)

        presets.removeAll { $0.id == id }
        saveIndex()

        if activePresetId == id {
            setActivePresetId(nil)
        }
    }

    /// Duplicate a preset, returning the new ID.
    func duplicatePreset(id: String) -> String? {
        guard var doc = loadDocument(id: id) else { return nil }
        let newId = UUID().uuidString
        doc.meta.id = newId
        doc.meta.displayName = doc.meta.displayName + " (copy)"
        doc.meta.exportedAt = ISO8601DateFormatter().string(from: Date())
        saveDocument(doc)
        return newId
    }

    /// Rename a preset.
    func renamePreset(id: String, newName: String) {
        guard var doc = loadDocument(id: id) else { return }
        doc.meta.displayName = newName
        saveDocument(doc)
    }

    /// Create an empty preset and return the new ID.
    func createEmptyPreset() -> String? {
        let doc = GamepadPresetDocument(
            meta: PresetMeta(displayName: "New Layout"),
            modules: []
        )
        saveDocument(doc)
        return doc.meta.id
    }

    // MARK: - Import / Export

    /// Import a preset from a JSON file URL.
    func importPreset(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var document = try decoder.decode(GamepadPresetDocument.self, from: data)

        // Generate new ID to avoid collisions
        let newId = UUID().uuidString
        document.meta.id = newId
        document.meta.exportedAt = ISO8601DateFormatter().string(from: Date())

        saveDocument(document)
        return newId
    }

    /// Export a preset to a temporary shareable file.
    func exportPreset(id: String) -> URL? {
        guard let document = loadDocument(id: id) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(document.meta.displayName).json")

        guard let data = try? encoder.encode(document) else { return nil }

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("⚠️ Failed to export preset: \(error)")
            return nil
        }
    }

    // MARK: - Active Preset

    /// Set the active preset by ID.
    func activatePreset(id: String) {
        guard presets.contains(where: { $0.id == id }) else { return }
        setActivePresetId(id)
    }

    /// Get the active preset document, or nil.
    var activePresetDocument: GamepadPresetDocument? {
        guard let id = activePresetId else { return nil }
        return loadDocument(id: id)
    }

    // MARK: - Bundled Presets

    private func loadBundledPresetsIfNeeded() {
        let installed = userDefaults.stringArray(forKey: bundledInstalledKey) ?? []

        // Check if bundled presets exist on disk
        let bundledIds = ["preset_default_xbox", "preset_default_ps", "preset_default_nes", "preset_default_simple"]
        let needsInstall = bundledIds.filter { id in !installed.contains(id) && !presets.contains(where: { $0.id == id }) }

        guard !needsInstall.isEmpty else { return }

        for presetId in needsInstall {
            installBundledPreset(id: presetId)
        }

        userDefaults.set(installed + needsInstall, forKey: bundledInstalledKey)
    }

    private func installBundledPreset(id: String) {
        // Create default preset if file doesn't exist
        let url = fileURL(for: id)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let document = createDefaultPreset(id: id)
        saveDocument(document)

        // Mark as builtin
        if let idx = presets.firstIndex(where: { $0.id == id }) {
            presets[idx].isBuiltin = true
            saveIndex()
        }

        // Set as active if no active preset
        if activePresetId == nil {
            setActivePresetId(id)
        }
    }

    private func createDefaultPreset(id: String) -> GamepadPresetDocument {
        let meta = PresetMeta(
            id: id,
            displayName: defaultPresetName(for: id),
            sourceAppVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        var layout = LayoutGlobals()
        var modules: [GamepadModule] = []

        switch id {
        case "preset_default_xbox":
            modules = defaultXboxModules()
        case "preset_default_ps":
            modules = defaultPlayStationModules()
        case "preset_default_nes":
            modules = defaultNESModules()
        case "preset_default_simple":
            modules = defaultSimpleModules()
        default:
            break
        }

        return GamepadPresetDocument(meta: meta, layout: layout, modules: modules)
    }

    private func defaultPresetName(for id: String) -> String {
        switch id {
        case "preset_default_xbox": return "Xbox Default"
        case "preset_default_ps": return "PlayStation Default"
        case "preset_default_nes": return "NES Default"
        case "preset_default_simple": return "Simple Default"
        default: return "Default"
        }
    }

    // MARK: - Default Module Definitions

    private func defaultXboxModules() -> [GamepadModule] {
        [
            GamepadModule(id: "dpad", type: .dpad, anchorX: 0.15, anchorY: 0.5, zIndex: 0,
                          dpadVariant: "cross",
                          stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right"),
            GamepadModule(id: "stick_left", type: .analogStick, anchorX: 0.25, anchorY: 0.65, zIndex: 1,
                          stickUpKey: "W", stickLeftKey: "A", stickDownKey: "S", stickRightKey: "D",
                          stickVisualVariant: "standard"),
            GamepadModule(id: "stick_right", type: .analogStick, anchorX: 0.75, anchorY: 0.65, zIndex: 1,
                          stickMouseSensitivity: 1.0),
            GamepadModule(id: "button_a", type: .button, anchorX: 0.85, anchorY: 0.55, zIndex: 2,
                          hidKey: 44, derivedKey: "Space", displayLabel: "A"),
            GamepadModule(id: "button_b", type: .button, anchorX: 0.90, anchorY: 0.45, zIndex: 2,
                          hidKey: 42, derivedKey: "Backspace", displayLabel: "B"),
            GamepadModule(id: "button_x", type: .button, anchorX: 0.80, anchorY: 0.45, zIndex: 3,
                          hidKey: 43, derivedKey: "Tab", displayLabel: "X"),
            GamepadModule(id: "button_y", type: .button, anchorX: 0.85, anchorY: 0.35, zIndex: 3,
                          hidKey: 40, derivedKey: "Enter", displayLabel: "Y"),
            GamepadModule(id: "shoulder_l", type: .shoulder, anchorX: 0.30, anchorY: 0.15, zIndex: 4,
                          hidKey: 43, displayLabel: "LB"),
            GamepadModule(id: "shoulder_r", type: .shoulder, anchorX: 0.70, anchorY: 0.15, zIndex: 4,
                          hidKey: 40, displayLabel: "RB"),
            GamepadModule(id: "trigger_l", type: .trigger, anchorX: 0.30, anchorY: 0.08, zIndex: 5,
                          hidKey: 225, displayLabel: "LT"),
            GamepadModule(id: "trigger_r", type: .trigger, anchorX: 0.70, anchorY: 0.08, zIndex: 5,
                          hidKey: 224, displayLabel: "RT"),
            GamepadModule(id: "button_back", type: .button, anchorX: 0.40, anchorY: 0.40, zIndex: 1,
                          hidKey: 41, derivedKey: "Escape", displayLabel: "View"),
            GamepadModule(id: "button_start", type: .button, anchorX: 0.60, anchorY: 0.40, zIndex: 1,
                          hidKey: 44, derivedKey: "Space", displayLabel: "Menu"),
        ]
    }

    private func defaultPlayStationModules() -> [GamepadModule] {
        [
            GamepadModule(id: "dpad", type: .dpad, anchorX: 0.15, anchorY: 0.5, zIndex: 0,
                          dpadVariant: "cross",
                          stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right"),
            GamepadModule(id: "stick_left", type: .analogStick, anchorX: 0.25, anchorY: 0.65, zIndex: 1,
                          stickUpKey: "W", stickLeftKey: "A", stickDownKey: "S", stickRightKey: "D",
                          stickVisualVariant: "standard"),
            GamepadModule(id: "stick_right", type: .analogStick, anchorX: 0.75, anchorY: 0.65, zIndex: 1,
                          stickMouseSensitivity: 1.0),
            GamepadModule(id: "button_cross", type: .button, anchorX: 0.85, anchorY: 0.55, zIndex: 2,
                          hidKey: 44, derivedKey: "Space", displayLabel: "✕"),
            GamepadModule(id: "button_circle", type: .button, anchorX: 0.90, anchorY: 0.45, zIndex: 2,
                          hidKey: 42, derivedKey: "Backspace", displayLabel: "○"),
            GamepadModule(id: "button_square", type: .button, anchorX: 0.80, anchorY: 0.45, zIndex: 3,
                          hidKey: 43, derivedKey: "Tab", displayLabel: "☐"),
            GamepadModule(id: "button_triangle", type: .button, anchorX: 0.85, anchorY: 0.35, zIndex: 3,
                          hidKey: 40, derivedKey: "Enter", displayLabel: "△"),
            GamepadModule(id: "shoulder_l", type: .shoulder, anchorX: 0.30, anchorY: 0.15, zIndex: 4,
                          hidKey: 43, displayLabel: "L1"),
            GamepadModule(id: "shoulder_r", type: .shoulder, anchorX: 0.70, anchorY: 0.15, zIndex: 4,
                          hidKey: 40, displayLabel: "R1"),
            GamepadModule(id: "trigger_l", type: .trigger, anchorX: 0.30, anchorY: 0.08, zIndex: 5,
                          hidKey: 225, displayLabel: "L2"),
            GamepadModule(id: "trigger_r", type: .trigger, anchorX: 0.70, anchorY: 0.08, zIndex: 5,
                          hidKey: 224, displayLabel: "R2"),
            GamepadModule(id: "button_share", type: .button, anchorX: 0.40, anchorY: 0.40, zIndex: 1,
                          hidKey: 41, derivedKey: "Escape", displayLabel: "Share"),
            GamepadModule(id: "button_options", type: .button, anchorX: 0.60, anchorY: 0.40, zIndex: 1,
                          hidKey: 44, derivedKey: "Space", displayLabel: "Options"),
        ]
    }

    private func defaultNESModules() -> [GamepadModule] {
        [
            GamepadModule(id: "dpad", type: .dpad, anchorX: 0.20, anchorY: 0.5, zIndex: 0,
                          dpadVariant: "cross",
                          stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right"),
            GamepadModule(id: "button_a", type: .button, anchorX: 0.80, anchorY: 0.55, zIndex: 2,
                          hidKey: 44, derivedKey: "Space", displayLabel: "A"),
            GamepadModule(id: "button_b", type: .button, anchorX: 0.90, anchorY: 0.45, zIndex: 2,
                          hidKey: 42, derivedKey: "Backspace", displayLabel: "B"),
            GamepadModule(id: "button_select", type: .button, anchorX: 0.40, anchorY: 0.70, zIndex: 1,
                          hidKey: 41, derivedKey: "Escape", displayLabel: "Select"),
            GamepadModule(id: "button_start", type: .button, anchorX: 0.60, anchorY: 0.70, zIndex: 1,
                          hidKey: 44, derivedKey: "Space", displayLabel: "Start"),
        ]
    }

    private func defaultSimpleModules() -> [GamepadModule] {
        [
            GamepadModule(id: "dpad", type: .dpad, anchorX: 0.20, anchorY: 0.5, scale: 1.5, zIndex: 0,
                          dpadVariant: "cross",
                          stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right"),
            GamepadModule(id: "button_a", type: .button, anchorX: 0.85, anchorY: 0.5, scale: 1.5, zIndex: 2,
                          hidKey: 44, derivedKey: "Space", displayLabel: "A"),
            GamepadModule(id: "button_b", type: .button, anchorX: 0.93, anchorY: 0.4, scale: 1.5, zIndex: 2,
                          hidKey: 42, derivedKey: "Backspace", displayLabel: "B"),
        ]
    }

    // MARK: - Schema Migration

    private func migrateDocument(_ doc: GamepadPresetDocument) -> GamepadPresetDocument {
        var doc = doc
        // Currently no migrations needed since we create new documents at v10
        // If we ever support loading older formats, add migration logic here
        doc.schemaVersion = PresetConstants.currentSchemaVersion
        return doc
    }
}
