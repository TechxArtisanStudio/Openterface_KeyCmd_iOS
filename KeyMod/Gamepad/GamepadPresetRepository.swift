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
    /// Loaded active preset document — mutated by UI, persisted on save.
    @Published var activeDocument: GamepadPresetDocument?

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
        if let id = activePresetId {
            activeDocument = loadDocument(id: id)
        }
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
        // Deduplicate module IDs — keep first occurrence, reassign duplicates
        var seenIds: Set<String> = []
        for i in document.modules.indices {
            let origId = document.modules[i].id
            if seenIds.contains(origId) {
                document.modules[i].id = "\(document.modules[i].type.rawValue)_dup_\(UUID().uuidString.prefix(6))"
            }
            seenIds.insert(origId)
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
        activeDocument = loadDocument(id: id)
    }

    /// Get the active preset document, or nil.
    var activePresetDocument: GamepadPresetDocument? {
        activeDocument
    }

    /// Update the active document in memory (doesn't persist to disk — call saveDocument for that).
    func updateDocument(_ document: GamepadPresetDocument) {
        activeDocument = document
    }

    /// Persist the active document to disk.
    func saveActiveDocument() {
        if let doc = activeDocument {
            saveDocument(doc)
        }
    }

    // MARK: - Bundled Presets

    private func loadBundledPresetsIfNeeded() {
        let installed = userDefaults.stringArray(forKey: bundledInstalledKey) ?? []

        // Bundled preset IDs matching Android's gamepad/*.json files
        let bundledIds = [
            "preset_default",           // default.json
            "preset_pack_xyab",         // xyab.json
            "preset_pack_xyab_touchpad", // xyab_touchpad.json
            "preset_pack_minecraft_java", // minecraft_java.json
            "emulator_6"                // emu-6.json
        ]
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
            let id = id
            setActivePresetId(id)
            activeDocument = loadDocument(id: id)
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
        case "preset_default":
            layout.backgroundFillArgb = -1515563
            layout.backgroundPattern = "dots"
            modules = defaultPresetModules()
        case "preset_pack_xyab":
            layout.backgroundFillArgb = -14997448
            layout.backgroundPattern = "micro_grid"
            layout.faceButtonTemplate = "xbox_abxy"
            modules = xyabModules()
        case "preset_pack_xyab_touchpad":
            layout.backgroundFillArgb = -14997448
            layout.backgroundPattern = "micro_grid"
            layout.faceButtonTemplate = "xbox_abxy"
            modules = xyabTouchpadModules()
        case "preset_pack_minecraft_java":
            layout.backgroundFillArgb = -14796241
            layout.backgroundPattern = "micro_grid"
            layout.faceButtonTemplate = "xbox_abxy"
            layout.mouseSensitivity = 1.12
            layout.rightStickMouseGain = 1.18
            modules = minecraftJavaModules()
        case "emulator_6":
            layout.backgroundFillArgb = -14997448
            layout.backgroundPattern = "micro_grid"
            modules = emulator6Modules()
        default:
            break
        }

        return GamepadPresetDocument(meta: meta, layout: layout, modules: modules)
    }

    private func defaultPresetName(for id: String) -> String {
        switch id {
        case "preset_default": return "Default"
        case "preset_pack_xyab": return "XYAB"
        case "preset_pack_xyab_touchpad": return "XYAB Trackpad"
        case "preset_pack_minecraft_java": return "Minecraft Java"
        case "emulator_6": return "Emu 6"
        default: return "Default"
        }
    }

    // MARK: - Default Module Definitions (matching Android gamepad/*.json)

    private func defaultPresetModules() -> [GamepadModule] {
        var dpad = GamepadModule(id: "stick_left", type: .dpad, anchorX: 0.2, anchorY: 0.5, zIndex: 0,
                                 dpadVariant: "cross",
                                 stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right")
        dpad.moduleAccentArgb = -13154481
        var btnA = GamepadModule(id: "button_a", type: .button, anchorX: 0.716, anchorY: 0.514, scale: 1.01, zIndex: 1,
                                 hidKey: 40, derivedKey: "Enter", displayLabel: "B")
        btnA.buttonCornerRadiusNorm = 1.0; btnA.moduleAccentArgb = -43230
        var btnSelect = GamepadModule(id: "button_select", type: .button, anchorX: 0.43, anchorY: 0.833, scale: 0.53, zIndex: 2,
                                      hidKey: 20, derivedKey: "Q", displayLabel: "Select")
        btnSelect.buttonCornerRadiusNorm = 0.51
        var btnStart = GamepadModule(id: "button_start", type: .button, anchorX: 0.573, anchorY: 0.827, scale: 0.53, zIndex: 3,
                                     hidKey: 8, derivedKey: "E", displayLabel: "Start")
        btnStart.buttonCornerRadiusNorm = 0.51
        var btnB = GamepadModule(id: "button_b", type: .button, anchorX: 0.854, anchorY: 0.512, scale: 1.01, zIndex: 4,
                                 hidKey: 44, derivedKey: "Space", displayLabel: "A")
        btnB.buttonCornerRadiusNorm = 1.0; btnB.moduleAccentArgb = -1499549
        return [dpad, btnA, btnSelect, btnStart, btnB]
    }

    private func xyabModules() -> [GamepadModule] {
        var dpad = GamepadModule(id: "stick_left", type: .dpad, anchorX: 0.2, anchorY: 0.5, zIndex: 0,
                                 dpadVariant: "cross",
                                 stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right")
        dpad.moduleAccentArgb = -13154481
        var btnY = GamepadModule(id: "button_y", type: .button, anchorX: 0.795, anchorY: 0.388, scale: 0.91, zIndex: 1,
                                 hidKey: 24, derivedKey: "U", displayLabel: "Y")
        btnY.buttonCornerRadiusNorm = 1.0; btnY.moduleAccentArgb = -20443
        var btnX = GamepadModule(id: "button_x", type: .button, anchorX: 0.688, anchorY: 0.515, scale: 0.91, zIndex: 2,
                                 hidKey: 11, derivedKey: "H", displayLabel: "X")
        btnX.buttonCornerRadiusNorm = 1.0; btnX.moduleAccentArgb = -14575807
        var btnB = GamepadModule(id: "button_b", type: .button, anchorX: 0.902, anchorY: 0.515, scale: 0.91, zIndex: 3,
                                 hidKey: 12, derivedKey: "I", displayLabel: "B")
        btnB.buttonCornerRadiusNorm = 1.0; btnB.moduleAccentArgb = -43230
        var btnA = GamepadModule(id: "button_a", type: .button, anchorX: 0.795, anchorY: 0.642, scale: 0.91, zIndex: 4,
                                 hidKey: 13, derivedKey: "J", displayLabel: "A")
        btnA.buttonCornerRadiusNorm = 1.0; btnA.moduleAccentArgb = -11684126
        let btnSelect = GamepadModule(id: "button_select", type: .button, anchorX: 0.43, anchorY: 0.833, scale: 0.53, zIndex: 5,
                                      hidKey: 20, derivedKey: "Q", displayLabel: "Select")
        let btnStart = GamepadModule(id: "button_start", type: .button, anchorX: 0.573, anchorY: 0.827, scale: 0.53, zIndex: 6,
                                     hidKey: 8, derivedKey: "E", displayLabel: "Start")
        return [dpad, btnY, btnX, btnB, btnA, btnSelect, btnStart]
    }

    private func xyabTouchpadModules() -> [GamepadModule] {
        var dpad = GamepadModule(id: "stick_left", type: .dpad, anchorX: 0.205, anchorY: 0.5, scale: 0.82, zIndex: 0,
                                 displayLabel: "D",
                                 dpadVariant: "cross",
                                 stickUpKey: "Down", stickLeftKey: "Right", stickDownKey: "Left", stickRightKey: "Up")
        dpad.moduleAccentArgb = -13154481
        var btnY = GamepadModule(id: "button_y", type: .button, anchorX: 0.795, anchorY: 0.388, scale: 0.91, zIndex: 1,
                                 hidKey: 24, derivedKey: "U", displayLabel: "Y")
        btnY.buttonCornerRadiusNorm = 1.0; btnY.moduleAccentArgb = -20443
        var btnX = GamepadModule(id: "button_x", type: .button, anchorX: 0.688, anchorY: 0.515, scale: 0.91, zIndex: 2,
                                 hidKey: 11, derivedKey: "H", displayLabel: "X")
        btnX.buttonCornerRadiusNorm = 1.0; btnX.moduleAccentArgb = -14575807
        var btnB = GamepadModule(id: "button_b", type: .button, anchorX: 0.902, anchorY: 0.515, scale: 0.91, zIndex: 3,
                                 hidKey: 12, derivedKey: "I", displayLabel: "B")
        btnB.buttonCornerRadiusNorm = 1.0; btnB.moduleAccentArgb = -43230
        var btnA = GamepadModule(id: "button_a", type: .button, anchorX: 0.795, anchorY: 0.642, scale: 0.91, zIndex: 4,
                                 hidKey: 13, derivedKey: "J", displayLabel: "A")
        btnA.buttonCornerRadiusNorm = 1.0; btnA.moduleAccentArgb = -11684126
        var touchpad = GamepadModule(id: "touchpad_1", type: .touchpad, anchorX: 0.5, anchorY: 0.268, scale: 0.71, zIndex: 5,
                                     displayLabel: "Touchpad")
        touchpad.moduleAccentArgb = -13154481
        let mouseL = GamepadModule(id: "mouse_btn_l", type: .mouseButton, anchorX: 0.435, anchorY: 0.498, scale: 0.5, zIndex: 6,
                                   displayLabel: "L", mouseButton: 1)
        let mouseR = GamepadModule(id: "mouse_btn_r", type: .mouseButton, anchorX: 0.565, anchorY: 0.498, scale: 0.5, zIndex: 7,
                                   displayLabel: "R", mouseButton: 3)
        let btnSelect = GamepadModule(id: "button_select", type: .button, anchorX: 0.418, anchorY: 0.108, scale: 0.53, zIndex: 8,
                                      hidKey: 20, derivedKey: "Q", displayLabel: "Select")
        var btnStart = GamepadModule(id: "button_start", type: .button, anchorX: 0.582, anchorY: 0.108, scale: 0.53, zIndex: 9,
                                     hidKey: 8, derivedKey: "E", displayLabel: "Start")
        btnStart.buttonCornerRadiusNorm = 1.0
        var dpad2 = GamepadModule(id: "stick_left_2", type: .dpad, anchorX: 0.41, anchorY: 0.792, scale: 0.82, zIndex: 10,
                                  dpadVariant: "cross",
                                  stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right")
        dpad2.moduleAccentArgb = -13154481
        var stick = GamepadModule(id: "stick_left_3", type: .analogStick, anchorX: 0.59, anchorY: 0.792, scale: 0.82, zIndex: 11,
                                  displayLabel: "M",
                                  stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right",
                                  stickMouseSensitivity: 1.0)
        stick.moduleAccentArgb = -13154481
        return [dpad, btnY, btnX, btnB, btnA, touchpad, mouseL, mouseR, btnSelect, btnStart, dpad2, stick]
    }

    private func minecraftJavaModules() -> [GamepadModule] {
        let jumpGestureLock = GestureLockConfig(
            upLeft: GestureLockSlotDetail(action: "hold_lock"),
            upRight: GestureLockSlotDetail(action: "none"),
            downLeft: GestureLockSlotDetail(action: "turbo"),
            downRight: GestureLockSlotDetail(action: "none")
        )
        let mouseBtnGestureLock = GestureLockConfig(
            upLeft: GestureLockSlotDetail(action: "turbo"),
            upRight: GestureLockSlotDetail(action: "hold_lock"),
            downLeft: GestureLockSlotDetail(action: "turbo"),
            downRight: GestureLockSlotDetail(action: "hold_lock")
        )
        let btn14GestureLock = GestureLockConfig(
            upLeft: GestureLockSlotDetail(action: "turbo"),
            upRight: GestureLockSlotDetail(action: "hold_lock"),
            downLeft: GestureLockSlotDetail(action: "none"),
            downRight: GestureLockSlotDetail(action: "none")
        )
        var stick = GamepadModule(id: "stick_left", type: .dpad, anchorX: 0.116, anchorY: 0.739, scale: 1.13, zIndex: 0,
                                  stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right")
        stick.moduleAccentArgb = -13154481
        var btnY = GamepadModule(id: "button_y", type: .button, anchorX: 0.748, anchorY: 0.384, scale: 0.9, zIndex: 1,
                                 hidKey: 224, derivedKey: "Ctrl", displayLabel: "Run")
        btnY.buttonCornerRadiusNorm = 1.0; btnY.moduleAccentArgb = -20443
        var btnX = GamepadModule(id: "button_x", type: .button, anchorX: 0.162, anchorY: 0.435, scale: 1.06, zIndex: 2,
                                 hidKey: 225, derivedKey: "Shift", displayLabel: "Sneak")
        btnX.buttonCornerRadiusNorm = 1.0; btnX.keyboardHoldLock = true; btnX.moduleAccentArgb = -14575807
        var btnB = GamepadModule(id: "button_b", type: .button, anchorX: 0.5, anchorY: 0.387, scale: 0.9, zIndex: 3,
                                 hidKey: 8, derivedKey: "E", displayLabel: "Inv")
        btnB.buttonCornerRadiusNorm = 0.57; btnB.moduleAccentArgb = -43230
        var btnA = GamepadModule(id: "button_a", type: .button, anchorX: 0.928, anchorY: 0.497, scale: 1.08, zIndex: 4,
                                 hidKey: 44, derivedKey: "Space", displayLabel: "Jump",
                                 gestureLock: jumpGestureLock)
        btnA.buttonCornerRadiusNorm = 1.0; btnA.moduleAccentArgb = -11684126
        var touchpad = GamepadModule(id: "touchpad_1", type: .touchpad, anchorX: 0.85, anchorY: 0.788, scale: 0.71, zIndex: 5,
                                     displayLabel: "Look", widthNorm: 0.27, heightNorm: 0.38)
        touchpad.moduleAccentArgb = -13154481
        var mouseL = GamepadModule(id: "mouse_btn_l", type: .mouseButton, anchorX: 0.699, anchorY: 0.855, scale: 0.77, zIndex: 6,
                                   displayLabel: "L", gestureLock: mouseBtnGestureLock, mouseButton: 1)
        mouseL.keyboardHoldLock = true
        var mouseR = GamepadModule(id: "mouse_btn_r", type: .mouseButton, anchorX: 0.734, anchorY: 0.624, scale: 0.67, zIndex: 7,
                                   displayLabel: "R", mouseButton: 3)
        mouseR.keyboardHoldLock = true
        var btnSelect = GamepadModule(id: "button_select", type: .button, anchorX: 0.644, anchorY: 0.218, scale: 0.72, zIndex: 8,
                                      hidKey: 43, derivedKey: "Tab", displayLabel: "Tab")
        btnSelect.buttonCornerRadiusNorm = 1.0
        var btn17 = GamepadModule(id: "button_17", type: .button, anchorX: 0.356, anchorY: 0.218, scale: 0.72, zIndex: 10,
                                  hidKey: 58, derivedKey: "F1", displayLabel: "UI")
        btn17.buttonCornerRadiusNorm = 1.0; btn17.moduleAccentArgb = -8875876
        var btn18 = GamepadModule(id: "button_18", type: .button, anchorX: 0.428, anchorY: 0.218, scale: 0.72, zIndex: 11,
                                  hidKey: 59, derivedKey: "F2", displayLabel: "Cap")
        btn18.buttonCornerRadiusNorm = 1.0; btn18.moduleAccentArgb = -14575885
        var btn19 = GamepadModule(id: "button_19", type: .button, anchorX: 0.5, anchorY: 0.218, scale: 0.72, zIndex: 12,
                                  hidKey: 60, derivedKey: "F3", displayLabel: "Dbg")
        btn19.buttonCornerRadiusNorm = 1.0; btn19.moduleAccentArgb = -10011977
        var btn16 = GamepadModule(id: "button_16", type: .button, anchorX: 0.572, anchorY: 0.218, scale: 0.72, zIndex: 13,
                                  hidKey: 62, derivedKey: "F5", displayLabel: "3rd")
        btn16.buttonCornerRadiusNorm = 1.0; btn16.moduleAccentArgb = -10177034
        var btnStart = GamepadModule(id: "button_start", type: .button, anchorX: 0.051, anchorY: 0.207, scale: 1.04, zIndex: 9,
                                     hidKey: 41, derivedKey: "Escape", displayLabel: "Esc")
        btnStart.buttonCornerRadiusNorm = 1.0
        var btn3 = GamepadModule(id: "button_3", type: .button, anchorX: 0.055, anchorY: 0.425, scale: 1.08, zIndex: 14,
                                 hidKey: 44, derivedKey: "Space", displayLabel: "Jump")
        btn3.buttonCornerRadiusNorm = 1.0; btn3.moduleAccentArgb = -11684126
        var btn4 = GamepadModule(id: "button_4", type: .button, anchorX: 0.928, anchorY: 0.212, scale: 1.08, zIndex: 15,
                                 hidKey: 9, derivedKey: "F", displayLabel: "Swap")
        btn4.buttonCornerRadiusNorm = 1.0
        var btn5 = GamepadModule(id: "button_5", type: .button, anchorX: 0.147, anchorY: 0.162, scale: 1.08, zIndex: 16,
                                 hidKey: 30, derivedKey: "1", displayLabel: "1")
        btn5.buttonCornerRadiusNorm = 0.88; btn5.moduleAccentArgb = -769226
        var btn6 = GamepadModule(id: "button_6", type: .button, anchorX: 0.839, anchorY: 0.282, scale: 1.17, zIndex: 17,
                                 hidKey: 20, derivedKey: "Q", displayLabel: "Drop")
        btn6.buttonCornerRadiusNorm = 0.88
        var btn7 = GamepadModule(id: "button_7", type: .button, anchorX: 0.213, anchorY: 0.207, scale: 1.08, zIndex: 18,
                                 hidKey: 31, derivedKey: "2", displayLabel: "2")
        btn7.buttonCornerRadiusNorm = 0.88; btn7.moduleAccentArgb = -26624
        var btn8 = GamepadModule(id: "button_8", type: .button, anchorX: 0.26, anchorY: 0.299, scale: 1.08, zIndex: 19,
                                 hidKey: 32, derivedKey: "3", displayLabel: "3")
        btn8.buttonCornerRadiusNorm = 0.88; btn8.moduleAccentArgb = -16121
        var btn9 = GamepadModule(id: "button_9", type: .button, anchorX: 0.299, anchorY: 0.397, scale: 1.08, zIndex: 20,
                                 hidKey: 33, derivedKey: "4", displayLabel: "4")
        btn9.buttonCornerRadiusNorm = 0.88; btn9.moduleAccentArgb = -11751600
        var btn10 = GamepadModule(id: "button_10", type: .button, anchorX: 0.346, anchorY: 0.492, scale: 1.08, zIndex: 21,
                                  hidKey: 34, derivedKey: "5", displayLabel: "5")
        btn10.buttonCornerRadiusNorm = 0.88; btn10.moduleAccentArgb = -16728876
        var btn11 = GamepadModule(id: "button_11", type: .button, anchorX: 0.366, anchorY: 0.596, scale: 1.08, zIndex: 22,
                                  hidKey: 35, derivedKey: "6", displayLabel: "6")
        btn11.buttonCornerRadiusNorm = 0.88; btn11.moduleAccentArgb = -14575885
        var btn12 = GamepadModule(id: "button_12", type: .button, anchorX: 0.377, anchorY: 0.698, scale: 1.08, zIndex: 23,
                                  hidKey: 36, derivedKey: "7", displayLabel: "7")
        btn12.buttonCornerRadiusNorm = 0.88; btn12.moduleAccentArgb = -10011977
        var btn13 = GamepadModule(id: "button_13", type: .button, anchorX: 0.368, anchorY: 0.805, scale: 1.08, zIndex: 24,
                                  hidKey: 37, derivedKey: "8", displayLabel: "8")
        btn13.buttonCornerRadiusNorm = 0.88; btn13.moduleAccentArgb = -1499549
        var mouseCopy1 = GamepadModule(id: "mouse_btn_copy_1", type: .mouseButton, anchorX: 0.252, anchorY: 0.848, scale: 0.77, zIndex: 25,
                                       displayLabel: "L", mouseButton: 1)
        mouseCopy1.keyboardHoldLock = true
        var mouseCopy2 = GamepadModule(id: "mouse_btn_copy_2", type: .mouseButton, anchorX: 0.241, anchorY: 0.595, scale: 0.67, zIndex: 26,
                                       displayLabel: "R", mouseButton: 3)
        mouseCopy2.keyboardHoldLock = true
        var btn14 = GamepadModule(id: "button_14", type: .button, anchorX: 0.825, anchorY: 0.521, scale: 1.06, zIndex: 27,
                                  hidKey: 225, derivedKey: "Shift", displayLabel: "Sneak",
                                  gestureLock: btn14GestureLock)
        btn14.buttonCornerRadiusNorm = 1.0; btn14.keyboardHoldLock = true; btn14.moduleAccentArgb = -14575807
        var btn15 = GamepadModule(id: "button_15", type: .button, anchorX: 0.355, anchorY: 0.926, scale: 1.08, zIndex: 28,
                                  hidKey: 38, derivedKey: "9", displayLabel: "9")
        btn15.buttonCornerRadiusNorm = 0.88; btn15.moduleAccentArgb = -8825528
        var scrollStrip = GamepadModule(id: "scroll_strip_1", type: .scrollStrip, anchorX: 0.5, anchorY: 0.711, scale: 1.0, zIndex: 29,
                                        displayLabel: "Wheel", widthNorm: 0.08, heightNorm: 0.42)
        scrollStrip.moduleAccentArgb = -13154481
        return [stick, btnY, btnX, btnB, btnA, touchpad, mouseL, mouseR, btnSelect, btn17, btn18, btn19, btn16, btnStart, btn3, btn4, btn5, btn6, btn7, btn8, btn9, btn10, btn11, btn12, btn13, mouseCopy1, mouseCopy2, btn14, btn15, scrollStrip]
    }

    private func emulator6Modules() -> [GamepadModule] {
        var dpad = GamepadModule(id: "stick_left", type: .dpad, anchorX: 0.237, anchorY: 0.512, scale: 1.43, zIndex: 0,
                                 dpadVariant: "cross",
                                 stickUpKey: "Up", stickLeftKey: "Left", stickDownKey: "Down", stickRightKey: "Right")
        dpad.moduleAccentArgb = -13154481
        var btnA = GamepadModule(id: "button_a", type: .button, anchorX: 0.547, anchorY: 0.327, scale: 1.43, zIndex: 1,
                                 hidKey: 24, derivedKey: "U", displayLabel: "K")
        btnA.buttonCornerRadiusNorm = 1.0; btnA.moduleAccentArgb = -20443
        var btnB = GamepadModule(id: "button_b", type: .button, anchorX: 0.721, anchorY: 0.334, scale: 1.43, zIndex: 2,
                                 hidKey: 12, derivedKey: "I", displayLabel: "S")
        btnB.buttonCornerRadiusNorm = 1.0; btnB.moduleAccentArgb = -43230
        var btn2 = GamepadModule(id: "button_2", type: .button, anchorX: 0.543, anchorY: 0.717, scale: 1.43, zIndex: 3,
                                 hidKey: 13, derivedKey: "J", displayLabel: "P")
        btn2.buttonCornerRadiusNorm = 1.0; btn2.moduleAccentArgb = -11684126
        var btn3 = GamepadModule(id: "button_3", type: .button, anchorX: 0.909, anchorY: 0.341, scale: 1.43, zIndex: 4,
                                 hidKey: 18, derivedKey: "O", displayLabel: "Hs")
        btn3.buttonCornerRadiusNorm = 1.0; btn3.moduleAccentArgb = -14575807
        var btn4 = GamepadModule(id: "button_4", type: .button, anchorX: 0.91, anchorY: 0.736, scale: 1.43, zIndex: 5,
                                 hidKey: 15, derivedKey: "L", displayLabel: "D")
        btn4.buttonCornerRadiusNorm = 1.0; btn4.moduleAccentArgb = -1499549
        var btn5 = GamepadModule(id: "button_5", type: .button, anchorX: 0.724, anchorY: 0.736, scale: 1.43, zIndex: 6,
                                 hidKey: 8, derivedKey: "E", displayLabel: "Rc")
        btn5.buttonCornerRadiusNorm = 1.0; btn5.moduleAccentArgb = -11751600
        return [dpad, btnA, btnB, btn2, btn3, btn4, btn5]
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
