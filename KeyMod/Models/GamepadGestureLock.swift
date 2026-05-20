//
//  GamepadGestureLock.swift
//  KeyMod
//
//  Diagonal gesture classification — pure math, platform-independent.
//  Classifies a completed drag gesture into one of four diagonal quadrants.
//

import CoreGraphics

// MARK: - Diagonal Direction

enum DiagonalDirection: String, CaseIterable {
    case upLeft
    case upRight
    case downLeft
    case downRight

    var displayName: String {
        switch self {
        case .upLeft: return "Up-Left"
        case .upRight: return "Up-Right"
        case .downLeft: return "Down-Left"
        case .downRight: return "Down-Right"
        }
    }
}

/// Sentinel value meaning the gesture overshot the cancel radius.
let gestureLockResultCancel = "__cancel__"

// MARK: - Gesture Lock Analyzer

enum GestureLockAnalyzer {

    /// Classify a completed drag gesture as a diagonal swipe direction.
    ///
    /// - Parameters:
    ///   - dx: Horizontal displacement in points (positive = right).
    ///   - dy: Vertical displacement in points (positive = down).
    ///   - density: Screen scale factor (points per dp).
    ///   - rMinDp: Minimum distance in dp before a direction is committed.
    ///   - rCancelDp: Distance in dp beyond which the gesture is cancelled.
    /// - Returns: `nil` = still in dead zone, `gestureLockResultCancel` = overshoot, otherwise the diagonal direction.
    static func classifyDiagonalSlot(
        dx: CGFloat,
        dy: CGFloat,
        density: CGFloat = 1.0,
        rMinDp: CGFloat = PresetConstants.diagonalRMinDp,
        rCancelDp: CGFloat = PresetConstants.diagonalRCancelDp
    ) -> String? {
        let r = hypot(dx, dy)
        let rMin = rMinDp * density
        let rCancel = rCancelDp * density

        if r <= rMin {
            return nil // Inside dead zone, no commit
        }
        if r > rCancel {
            return gestureLockResultCancel // Overshoot, cancel
        }

        let adx = abs(dx)
        let ady = abs(dy)

        if adx < 1e-3 && ady < 1e-3 {
            return nil
        }

        // Primary classification: vertical-dominant
        if dy < 0 && ady >= adx {
            return dx < 0 ? "upLeft" : "upRight"
        }
        if dy > 0 && ady >= adx {
            return dx < 0 ? "downLeft" : "downRight"
        }

        // Horizontal-dominant: tie-break to nearest diagonal
        if dx < 0 {
            return dy <= 0 ? "upLeft" : "downLeft"
        }
        return dy <= 0 ? "upRight" : "downRight"
    }

    /// Resolve the action for a classified diagonal slot.
    ///
    /// - Parameters:
    ///   - module: The gamepad module with gesture lock configuration.
    ///   - slotKey: The classified slot key (e.g. "upLeft", "upRight", etc.).
    /// - Returns: The resolved gesture lock action string.
    static func resolvedActionForSlot(
        module: GamepadModule,
        slotKey: String
    ) -> String {
        if slotKey == gestureLockResultCancel {
            return PresetConstants.gestureLockActionNone
        }

        var explicitAction: String? = nil
        var slotObjectPresent = false

        if let gestureLock = module.gestureLock {
            let slot = slotForKey(gestureLock, key: slotKey)
            if let slot = slot {
                slotObjectPresent = true
                explicitAction = slotAction(slot)
            }
        }

        // Explicit non-none action wins
        if let action = explicitAction, isNonNone(action) {
            return action
        }

        // Default actions from keyboardHoldLock
        guard module.keyboardHoldLock == true else {
            return PresetConstants.gestureLockActionNone
        }

        // If slot object is explicitly present (even with "none"), don't apply defaults
        if slotObjectPresent {
            return PresetConstants.gestureLockActionNone
        }

        // Default hold_lock on up-right, turbo on up-left
        if slotKey == PresetConstants.gestureLockSlotUpRight {
            return PresetConstants.gestureLockActionHoldLock
        }
        if slotKey == PresetConstants.gestureLockSlotUpLeft {
            return PresetConstants.gestureLockActionTurbo
        }

        return PresetConstants.gestureLockActionNone
    }

    /// Check if the module has any gesture lock enabled.
    static func moduleGesturesEnabled(_ module: GamepadModule) -> Bool {
        if module.keyboardHoldLock == true {
            return true
        }
        return hasAnyNonNoneAction(module.gestureLock)
    }

    /// Check if the module has any non-none gesture action.
    static func moduleUsesDiagonalGestures(_ module: GamepadModule) -> Bool {
        return moduleGesturesEnabled(module)
    }

    /// Check if the module type supports gesture lock.
    static func gesturesAllowedModuleType(_ type: ModuleType) -> Bool {
        return PresetConstants.gestureLockAllowedTypes.contains(type)
    }

    // MARK: - Private Helpers

    private static func slotForKey(_ config: GestureLockConfig, key: String) -> GestureLockSlotDetail? {
        switch key {
        case PresetConstants.gestureLockSlotUpLeft: return config.upLeft
        case PresetConstants.gestureLockSlotUpRight: return config.upRight
        case PresetConstants.gestureLockSlotDownLeft: return config.downLeft
        case PresetConstants.gestureLockSlotDownRight: return config.downRight
        default: return nil
        }
    }

    private static func slotAction(_ slot: GestureLockSlotDetail) -> String {
        let trimmed = slot.action.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PresetConstants.gestureLockActionNone : trimmed
    }

    private static func isNonNone(_ action: String) -> Bool {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != PresetConstants.gestureLockActionNone
    }

    private static func hasAnyNonNoneAction(_ config: GestureLockConfig?) -> Bool {
        guard let config = config else { return false }
        let slots = [config.upLeft, config.upRight, config.downLeft, config.downRight]
            .compactMap { $0 }
        return slots.contains { isNonNone(slotAction($0)) }
    }
}
