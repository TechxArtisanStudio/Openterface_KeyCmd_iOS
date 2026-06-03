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
    /// Module IDs that are currently hold-locked.
    @Published var holdLockedModuleIds: Set<String> = []

    /// Module IDs that are currently turbo-latched.
    @Published var turboLatchedModuleIds: Set<String> = []

    /// Track the key/action associated with each hold-locked module.
    private var holdLockKeys: [String: String] = [:]
    /// Track the turbo config for each latched module.
    private var turboConfigs: [String: TurboConfig] = [:]
    /// Track if a module is a mouse button hold-lock (vs keyboard key).
    private var holdLockIsMouse: [String: Bool] = [:]

    private var keyboardManager: KeyboardManager?
    private var mouseManager: MouseManager?
    private var turboEngine: TurboEngine?

    init(keyboardManager: KeyboardManager, mouseManager: MouseManager, turboEngine: TurboEngine) {
        self.keyboardManager = keyboardManager
        self.mouseManager = mouseManager
        self.turboEngine = turboEngine
    }

    // MARK: - Mouse action helpers

    private static let mouseActions: Set<String> = [
        "Left Click", "Right Click", "Middle Click", "Double Click", "Drag Toggle", "Scroll Up", "Scroll Down"
    ]

    private static func buttonMask(for key: String) -> UInt8? {
        switch key {
        case "Left Click": return 0x01
        case "Right Click": return 0x02
        case "Middle Click": return 0x04
        default: return nil
        }
    }

    private func sendMouseButtonDown(_ key: String) {
        guard let mask = Self.buttonMask(for: key) else { return }
        mouseManager?.sendButtonDown(buttons: mask)
    }

    private func sendMouseButtonUp(_ key: String) {
        guard let mask = Self.buttonMask(for: key) else { return }
        mouseManager?.sendButtonUp(buttons: mask)
    }

    // MARK: - Public API

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

    /// Toggle hold-lock for a module. Works with both keyboard keys and mouse actions.
    func handleHoldLock(moduleId: String, key: String) {
        let isMouse = Self.mouseActions.contains(key)

        if holdLockedModuleIds.contains(moduleId) {
            // Toggle off
            if isMouse {
                sendMouseButtonUp(key)
            } else {
                keyboardManager?.handleKeyUp(key)
            }
            holdLockedModuleIds.remove(moduleId)
            holdLockKeys.removeValue(forKey: moduleId)
            holdLockIsMouse.removeValue(forKey: moduleId)
        } else {
            // Toggle on
            if isMouse {
                sendMouseButtonDown(key)
            } else {
                keyboardManager?.handleKeyDown(key)
            }
            holdLockedModuleIds.insert(moduleId)
            holdLockKeys[moduleId] = key
            holdLockIsMouse[moduleId] = isMouse
        }
    }

    /// Toggle turbo for a module. Works with both keyboard keys and mouse actions.
    func handleTurbo(moduleId: String, key: String, config: TurboConfig) {
        let isMouse = Self.mouseActions.contains(key)

        if turboLatchedModuleIds.contains(moduleId) {
            // Toggle off
            turboEngine?.stop()
            turboLatchedModuleIds.remove(moduleId)
            turboConfigs.removeValue(forKey: moduleId)
        } else {
            // Toggle on
            if isMouse {
                // For mouse buttons, use a mouse-specific turbo
                startMouseTurbo(key: key, config: config)
            } else {
                turboEngine?.start(key: key, config: config)
            }
            turboLatchedModuleIds.insert(moduleId)
            turboConfigs[moduleId] = config
        }
    }

    /// Release a specific hold-locked module without toggling.
    func releaseHoldLock(moduleId: String, key: String) {
        let isMouse = holdLockIsMouse[moduleId] ?? false
        if holdLockedModuleIds.remove(moduleId) != nil {
            if isMouse {
                sendMouseButtonUp(key)
            } else {
                keyboardManager?.handleKeyUp(key)
            }
            holdLockKeys.removeValue(forKey: moduleId)
            holdLockIsMouse.removeValue(forKey: moduleId)
        }
    }

    /// Release all hold-locked keys/buttons and stop turbo.
    func releaseAll() {
        for (moduleId, key) in holdLockKeys {
            let isMouse = holdLockIsMouse[moduleId] ?? false
            if isMouse {
                sendMouseButtonUp(key)
            } else {
                keyboardManager?.handleKeyUp(key)
            }
        }
        holdLockedModuleIds.removeAll()
        holdLockKeys.removeAll()
        holdLockIsMouse.removeAll()

        turboEngine?.stop()
        turboLatchedModuleIds.removeAll()
        turboConfigs.removeAll()
    }

    /// Clear latch state without releasing keys.
    func clearState() {
        holdLockedModuleIds.removeAll()
        holdLockKeys.removeAll()
        holdLockIsMouse.removeAll()
        turboLatchedModuleIds.removeAll()
        turboConfigs.removeAll()
    }

    // MARK: - Mouse Turbo

    private var mouseTurboTimer: Timer?

    private func startMouseTurbo(key: String, config: TurboConfig) {
        mouseTurboTimer?.invalidate()

        // Send initial button down
        sendMouseButtonDown(key)

        // Schedule repeating click cycles
        let interval = TimeInterval(config.intervalMs) / 1000.0
        guard interval > 0 else { return }

        mouseTurboTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Pulse: button up then down
            self.sendMouseButtonUp(key)
            self.sendMouseButtonDown(key)
        }
    }

    func stopMouseTurbo() {
        mouseTurboTimer?.invalidate()
        mouseTurboTimer = nil
    }
}
