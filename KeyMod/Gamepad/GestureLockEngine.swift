//
//  GestureLockEngine.swift
//  KeyMod
//
//  Runtime engine for gesture lock actions (hold-lock, turbo).
//  Manages per-module latch state and executes key down/up cycles.
//

import Foundation
import Combine

/// The type of latch currently active on a module.
enum LatchState {
    case hold
    case turbo

    var iconName: String {
        switch self {
        case .hold: return "lock.fill"
        case .turbo: return "repeat"
        }
    }
}

class GestureLockEngine: ObservableObject {
    /// Module IDs that are currently hold-locked (key stays pressed until toggled off).
    @Published var holdLockedModuleIds: Set<String> = []

    /// Module IDs that are currently turbo-latched (key repeating via TurboEngine).
    @Published var turboLatchedModuleIds: Set<String> = []

    /// Track the key associated with each hold-locked module.
    private var holdLockKeys: [String: String] = [:]
    /// Track the turbo config for each latched module.
    private var turboConfigs: [String: TurboConfig] = [:]
    private var keyboardManager: KeyboardManager?
    private var turboEngine: TurboEngine?

    init(keyboardManager: KeyboardManager, turboEngine: TurboEngine) {
        self.keyboardManager = keyboardManager
        self.turboEngine = turboEngine
    }

    /// Query the latch state for a module. Returns nil if not latched.
    func latchState(for moduleId: String) -> LatchState? {
        if holdLockedModuleIds.contains(moduleId) {
            return .hold
        }
        if turboLatchedModuleIds.contains(moduleId) {
            return .turbo
        }
        return nil
    }

    /// Toggle hold-lock for a module.
    /// If already locked → release key and remove from set.
    /// If not locked → press key and add to set.
    func handleHoldLock(moduleId: String, key: String) {
        if holdLockedModuleIds.contains(moduleId) {
            // Toggle off: release the key
            keyboardManager?.handleKeyUp(key)
            holdLockedModuleIds.remove(moduleId)
            holdLockKeys.removeValue(forKey: moduleId)
        } else {
            // Toggle on: press the key and lock it
            keyboardManager?.handleKeyDown(key)
            holdLockedModuleIds.insert(moduleId)
            holdLockKeys[moduleId] = key
        }
    }

    /// Toggle turbo for a module.
    /// If already latched → stop turbo.
    /// If not latched → start turbo with the given config.
    func handleTurbo(moduleId: String, key: String, config: TurboConfig) {
        if turboLatchedModuleIds.contains(moduleId) {
            // Toggle off: stop turbo
            turboEngine?.stop()
            turboLatchedModuleIds.remove(moduleId)
            turboConfigs.removeValue(forKey: moduleId)
        } else {
            // Toggle on: start turbo
            turboEngine?.start(key: key, config: config)
            turboLatchedModuleIds.insert(moduleId)
            turboConfigs[moduleId] = config
        }
    }

    /// Release a specific hold-locked module without toggling.
    /// Used when user re-presses a hold-locked button to release it.
    func releaseHoldLock(moduleId: String, key: String) {
        if holdLockedModuleIds.remove(moduleId) != nil {
            keyboardManager?.handleKeyUp(key)
            holdLockKeys.removeValue(forKey: moduleId)
        }
    }

    /// Release all hold-locked keys and stop turbo. Called on canvas disappear.
    func releaseAll() {
        for (moduleId, key) in holdLockKeys {
            keyboardManager?.handleKeyUp(key)
            _ = moduleId
        }
        holdLockedModuleIds.removeAll()
        holdLockKeys.removeAll()

        turboEngine?.stop()
        turboLatchedModuleIds.removeAll()
        turboConfigs.removeAll()
    }

    /// Clear latch state without releasing keys (for preset changes).
    func clearState() {
        holdLockedModuleIds.removeAll()
        holdLockKeys.removeAll()
        turboLatchedModuleIds.removeAll()
        turboConfigs.removeAll()
    }
}
