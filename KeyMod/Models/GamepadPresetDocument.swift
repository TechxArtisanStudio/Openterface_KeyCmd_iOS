//
//  GamepadPresetDocument.swift
//  KeyMod
//
//  JSON Schema document models for gamepad layout presets (v10 equivalent).
//  All structs are Codable for JSON serialization/deserialization.
//

import Foundation

// MARK: - Top-Level Document

struct GamepadPresetDocument: Codable, Equatable, Identifiable {
    var format: String = PresetConstants.documentFormat
    var schemaVersion: Int = PresetConstants.currentSchemaVersion
    var meta: PresetMeta
    var layout: LayoutGlobals
    var modules: [GamepadModule]

    var id: String { meta.id }

    init(
        meta: PresetMeta = PresetMeta(),
        layout: LayoutGlobals = LayoutGlobals(),
        modules: [GamepadModule] = []
    ) {
        self.meta = meta
        self.layout = layout
        self.modules = modules
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.meta.id == rhs.meta.id
    }
}

// MARK: - Metadata

struct PresetMeta: Codable, Equatable {
    var id: String
    var displayName: String
    var description: String?
    var exportedAt: String?
    var sourceAppVersion: String?
    var creator: String?

    init(
        id: String = UUID().uuidString,
        displayName: String = "Untitled Preset",
        description: String? = nil,
        exportedAt: String? = nil,
        sourceAppVersion: String? = nil,
        creator: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.exportedAt = exportedAt
        self.sourceAppVersion = sourceAppVersion
        self.creator = creator
    }
}

// MARK: - Layout Globals

struct LayoutGlobals: Codable, Equatable {
    var mouseSensitivity: Double = 1.0
    var rightStickMouseGain: Double?
    var touchpadMouseButtonScale: Double?
    var showTwoButtons: Bool = false
    var backgroundImageFile: String?
    var backgroundScale: Double = 1.0
    var backgroundOffsetX: Double = 0
    var backgroundOffsetY: Double = 0
    var backgroundImageEncoding: String?
    var backgroundImageMediaType: String?
    var backgroundImageData: String?
    var stickLayoutTemplate: String?
    var faceButtonTemplate: String?
    var gyroEnabled: Bool?
    var gestureLockMinPressMs: Int?
    var gestureLockDiagonalRadiusScale: Double?
    var turboPulsePeriodMs: Int?
    var backgroundFillArgb: Int?
    var backgroundPattern: String?

    init() {}
}

// MARK: - Gamepad Module

struct GamepadModule: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var type: ModuleType
    var zIndex: Int = 0
    var scale: Double = 1.0
    var anchorX: Double = 0.5
    var anchorY: Double = 0.5
    var moduleAccentArgb: Int?
    var displayLabel: String?
    var displayLabelColorArgb: Int?

    // Type-specific fields
    // BUTTON
    var hidKey: Int?
    var modifierMask: Int?
    var buttonCornerRadiusNorm: Double = 1.0
    var buttonWidthRatio: Double = 1.0
    var buttonHeightRatio: Double = 1.0
    var buttonRotationDeg: Double = 0
    var mappedKeyLabelVisible: Bool?

    // STICK_KEY / STICK_MOUSE / DPAD
    var stickUpKey: String?
    var stickLeftKey: String?
    var stickDownKey: String?
    var stickRightKey: String?
    var stickCenterKey: String?
    var stickVisualVariant: String?
    var stickMouseSensitivity: Double?
    var stickPointerCenterKey: String?
    var stickPointerCenterMouseMask: Int?

    // DPAD specific
    var dpadVariant: String?
    var dpadSplitGapRatio: Double?
    var dpadSplitOuterReachRatio: Double?
    var dpadCrossArmDecoration: String?

    // TOUCHPAD / SCROLL_STRIP
    var widthNorm: Double?
    var heightNorm: Double?
    var scrollStripSensitivity: Double?
    var scrollStripInvertY: Bool?

    // MOUSE_BUTTON
    var mouseButton: Int?

    // TRIGGER
    var triggerAnalog: Bool?
    var triggerVariant: String?

    // Gesture lock
    var keyboardHoldLock: Bool?
    var gestureLock: GestureLockConfig?

    // Turbo
    var turboEnabled: Bool = false
    var turboIntervalMs: Int?
    var turboInitialDelayMs: Int?

    // Derived keyboard key (for BUTTON type, resolved from hidKey)
    var derivedKey: String?

    // Position (for position editing — not serialized in JSON)
    var positionX: Double?
    var positionY: Double?

    init(
        id: String,
        type: ModuleType,
        anchorX: Double = 0.5,
        anchorY: Double = 0.5,
        scale: Double = 1.0,
        zIndex: Int = 0,
        hidKey: Int? = nil,
        derivedKey: String? = nil,
        displayLabel: String? = nil,
        dpadVariant: String? = nil,
        stickUpKey: String? = nil,
        stickLeftKey: String? = nil,
        stickDownKey: String? = nil,
        stickRightKey: String? = nil,
        stickVisualVariant: String? = nil,
        stickMouseSensitivity: Double? = nil,
        scrollStripSensitivity: Double? = nil,
        keyboardHoldLock: Bool? = nil,
        gestureLock: GestureLockConfig? = nil,
        turboEnabled: Bool = false,
        turboIntervalMs: Int? = nil,
        turboInitialDelayMs: Int? = nil,
        mouseButton: Int? = nil,
        triggerAnalog: Bool? = nil,
        triggerVariant: String? = nil,
        widthNorm: Double? = nil,
        heightNorm: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.scale = scale
        self.zIndex = zIndex
        self.hidKey = hidKey
        self.derivedKey = derivedKey
        self.displayLabel = displayLabel
        self.dpadVariant = dpadVariant
        self.stickUpKey = stickUpKey
        self.stickLeftKey = stickLeftKey
        self.stickDownKey = stickDownKey
        self.stickRightKey = stickRightKey
        self.stickVisualVariant = stickVisualVariant
        self.stickMouseSensitivity = stickMouseSensitivity
        self.scrollStripSensitivity = scrollStripSensitivity
        self.keyboardHoldLock = keyboardHoldLock
        self.gestureLock = gestureLock
        self.turboEnabled = turboEnabled
        self.turboIntervalMs = turboIntervalMs
        self.turboInitialDelayMs = turboInitialDelayMs
        self.mouseButton = mouseButton
        self.triggerAnalog = triggerAnalog
        self.triggerVariant = triggerVariant
        self.widthNorm = widthNorm
        self.heightNorm = heightNorm
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(zIndex)
        hasher.combine(scale)
        hasher.combine(anchorX)
        hasher.combine(anchorY)
        hasher.combine(moduleAccentArgb)
        hasher.combine(displayLabel)
        hasher.combine(hidKey)
        hasher.combine(derivedKey)
        hasher.combine(buttonCornerRadiusNorm)
        hasher.combine(buttonWidthRatio)
        hasher.combine(buttonHeightRatio)
        hasher.combine(dpadVariant)
        hasher.combine(stickUpKey)
        hasher.combine(stickLeftKey)
        hasher.combine(stickDownKey)
        hasher.combine(stickRightKey)
        hasher.combine(stickMouseSensitivity)
        hasher.combine(widthNorm)
        hasher.combine(heightNorm)
        hasher.combine(mouseButton)
        hasher.combine(scrollStripSensitivity)
        hasher.combine(turboEnabled)
        hasher.combine(gestureLock)
    }

    var hasGestureLock: Bool {
        gestureLock != nil || keyboardHoldLock == true
    }
}

// MARK: - Gesture Lock Config

struct GestureLockConfig: Codable, Equatable, Hashable {
    var upLeft: GestureLockSlotDetail?
    var upRight: GestureLockSlotDetail?
    var downLeft: GestureLockSlotDetail?
    var downRight: GestureLockSlotDetail?
}

struct GestureLockSlotDetail: Codable, Equatable, Hashable {
    var action: String
    var hidKey: Int?
    var modifierMask: Int?

    init(action: String, hidKey: Int? = nil, modifierMask: Int? = nil) {
        self.action = action
        self.hidKey = hidKey
        self.modifierMask = modifierMask
    }
}

// MARK: - Position & Size (for position editing in dynamic layout)

struct ModuleAnchor: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double = 0.5, y: Double = 0.5) {
        self.x = x
        self.y = y
    }
}

struct ModuleSize: Codable, Equatable {
    var width: Double
    var height: Double

    init(width: Double = 0.15, height: Double = 0.15) {
        self.width = width
        self.height = height
    }
}

// MARK: - Color Extension for Hex

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension Int {
    init?(hex: String) {
        var int: UInt64 = 0
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        self.init(int)
    }
}
