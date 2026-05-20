//
//  GamepadPresetConstants.swift
//  KeyMod
//
//  Gamepad layout preset constants — enums, ranges, and identifier patterns.
//

import Foundation

// MARK: - Module Types

enum ModuleType: String, Codable, CaseIterable {
    case button
    case dpad
    case analogStick
    case scrollStrip
    case touchpad
    case mouseButton
    case shoulder
    case trigger
}

// MARK: - D-Pad Visual Variants

enum DPadVariant: String, Codable, CaseIterable {
    case cross
    case disc
    case split
    case floating
    case clicky
    case pivot
}

// MARK: - D-Pad Cross-Arm Decoration

enum DPadCrossDecoration: String, Codable, CaseIterable {
    case none
    case labels
    case icons
}

// MARK: - Gesture Lock Actions

enum GestureLockAction: String, Codable, CaseIterable {
    case none
    case holdLock
    case turbo
    case keyHold
    case keyTurbo
}

enum GestureLockSlot: String, Codable, CaseIterable {
    case upLeft
    case upRight
    case downLeft
    case downRight
}

// MARK: - Stick Visual Variants

enum StickVisualVariant: String, Codable, CaseIterable {
    case standard
    case concave
    case convex
    case lowProfile
    case cStick
    case hallEffect
}

// MARK: - Trigger Variants

enum TriggerVariant: String, Codable, CaseIterable {
    case digital
    case analog
    case hair
    case adaptive
}

// MARK: - Face Button Templates

enum FaceButtonTemplate: String, Codable, CaseIterable {
    case nintendoDiamond
    case xboxABXY
    case playstationSymbols
}

// MARK: - Stick Layout Templates

enum StickLayoutTemplate: String, Codable, CaseIterable {
    case symmetrical
    case offset
    case parallel
}

// MARK: - Background Patterns

enum BackgroundPattern: String, Codable, CaseIterable {
    case none
    case dots
    case microGrid
    case diagonalHatch
    case noise

    var displayName: String {
        switch self {
        case .none: return "None"
        case .dots: return "Dots"
        case .microGrid: return "Grid"
        case .diagonalHatch: return "Hatch"
        case .noise: return "Noise"
        }
    }
}

// MARK: - Background Image Types

enum BackgroundMediaType: String, Codable, CaseIterable {
    case png = "image/png"
    case jpeg = "image/jpeg"
    case webp = "image/webp"
}

// MARK: - Preset Schema Constants

enum PresetConstants {
    // Schema versioning
    static let documentFormat = "openterface.gamepad.layout.v1"
    static let currentSchemaVersion = 10
    static let minSchemaVersion = 1

    // Dynamic layout scaling
    static let dynamicLayoutReferenceMinEdge: CGFloat = 800
    static let dynamicLayoutScaleMin: CGFloat = 0.35
    static let dynamicLayoutScaleMax: CGFloat = 1.35

    // HID usage keycode range
    static let hidUsageKeycodeMin = 1
    static let hidUsageKeycodeMax = 255

    // Gesture lock radii (dp)
    static let diagonalRMinDp: CGFloat = 9
    static let diagonalRCancelDp: CGFloat = 200

    // Button geometry
    static let buttonCornerRadiusNormMin: CGFloat = 0
    static let buttonCornerRadiusNormMax: CGFloat = 1
    static let buttonWidthRatioMin: CGFloat = 0.25
    static let buttonWidthRatioMax: CGFloat = 3.5
    static let buttonHeightRatioMin: CGFloat = 0.25
    static let buttonHeightRatioMax: CGFloat = 3.5
    static let buttonRotationDegMax: CGFloat = 180

    // Scale range
    static let moduleScaleMin: CGFloat = 0.01
    static let moduleScaleMax: CGFloat = 4.0

    // Anchor range
    static let anchorMin: CGFloat = 0
    static let anchorMax: CGFloat = 1.0

    // Module count limits
    static let maxMouseButtons = 24
    static let maxScrollStrips = 8
    static let maxShoulders = 2
    static let maxTriggers = 2
    static let maxTouchpads = 8

    // Background embed limits
    static let maxBackgroundEmbedDecodedBytes = 6 * 1024 * 1024 // 6MB

    // Meta creator max length
    static let metaCreatorMaxChars = 64

    // Display label max code points
    static let displayLabelMaxCodePoints = 6

    // Gesture lock min press (ms)
    static let gestureLockMinPressMsMin = 0
    static let gestureLockMinPressMsMax = 1000

    // Gesture lock diagonal radius scale
    static let gestureLockDiagonalRadiusScaleMin: CGFloat = 0.5
    static let gestureLockDiagonalRadiusScaleMax: CGFloat = 3.0

    // Turbo pulse period (ms)
    static let turboPulsePeriodMsMin = 25
    static let turboPulsePeriodMsMax = 300

    // Mouse button scale
    static let touchpadMouseButtonScaleMin: CGFloat = 0.5
    static let touchpadMouseButtonScaleMax: CGFloat = 2.0

    // D-pad split geometry
    static let dpadSplitGapRatioMin: CGFloat = 0.05
    static let dpadSplitGapRatioMax: CGFloat = 0.38
    static let dpadSplitOuterReachRatioMin: CGFloat = 0.28
    static let dpadSplitOuterReachRatioMax: CGFloat = 1.0
    static let dpadSplitSegmentDepthNorm: CGFloat = 0.52
    static let dpadSplitSegmentBreadthNorm: CGFloat = 0.44

    // Stick mouse sensitivity
    static let stickMouseSensitivityMin: CGFloat = 0.25
    static let stickMouseSensitivityMax: CGFloat = 4.0

    // Scroll strip sensitivity
    static let scrollStripSensitivityMin: CGFloat = 0.25
    static let scrollStripSensitivityMax: CGFloat = 4.0

    // ID naming patterns (regex)
    static let stickIdPattern = "^stick_[a-z0-9_]+$"
    static let touchpadIdPattern = "^touchpad_[0-9]+$"
    static let scrollStripIdPattern = "^scroll_strip_[0-9]+$"
    static let buttonIdPattern = "^button_[a-z0-9]+$"
    static let mouseButtonCopyIdPattern = "^mouse_btn_copy_[0-9]+$"

    // Known module IDs
    static let shoulderLId = "shoulder_l"
    static let shoulderRId = "shoulder_r"
    static let triggerLId = "trigger_l"
    static let triggerRId = "trigger_r"
    static let stickLeftId = "stick_left"
    static let stickRightId = "stick_right"
    static let dpadId = "dpad"

    // Gesture lock slot keys
    static let gestureLockSlotUpLeft = "upLeft"
    static let gestureLockSlotUpRight = "upRight"
    static let gestureLockSlotDownLeft = "downLeft"
    static let gestureLockSlotDownRight = "downRight"

    // Gesture lock actions
    static let gestureLockActionNone = "none"
    static let gestureLockActionHoldLock = "hold_lock"
    static let gestureLockActionTurbo = "turbo"
    static let gestureLockActionKeyHold = "key_hold"
    static let gestureLockActionKeyTurbo = "key_turbo"

    // Background patterns
    static let backgroundPatternNone = "none"
    static let backgroundPatternDots = "dots"
    static let backgroundPatternMicroGrid = "micro_grid"
    static let backgroundPatternDiagonalHatch = "diagonal_hatch"
    static let backgroundPatternNoise = "noise"

    static let allowedBackgroundPatterns: Set<String> = [
        backgroundPatternNone, backgroundPatternDots,
        backgroundPatternMicroGrid, backgroundPatternDiagonalHatch,
        backgroundPatternNoise
    ]

    // Allowed gesture lock actions
    static let allowedGestureLockActions: Set<String> = [
        gestureLockActionNone, gestureLockActionHoldLock,
        gestureLockActionTurbo, gestureLockActionKeyHold,
        gestureLockActionKeyTurbo
    ]

    // Allowed D-pad cross-arm decoration
    static let allowedDpadCrossArmDecorations: Set<String> = ["none", "labels", "icons"]

    // Module types that support gesture lock
    static let gestureLockAllowedTypes: Set<ModuleType> = [.button, .shoulder, .trigger, .mouseButton]

    /// Compute dynamic layout scale factor from content size.
    static func contentMinEdgeScaleFactor(width: CGFloat, height: CGFloat) -> CGFloat {
        let minEdge = min(max(1, width), max(1, height))
        let raw = minEdge / dynamicLayoutReferenceMinEdge
        return max(dynamicLayoutScaleMin, min(dynamicLayoutScaleMax, raw))
    }
}
