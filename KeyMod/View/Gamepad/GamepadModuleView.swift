//
//  GamepadModuleView.swift
//  KeyMod
//
//  Unified module renderer — dispatches to the correct sub-view based on ModuleType.
//  Used by GamepadDynamicCanvas for schema-driven layout rendering.
//

import SwiftUI

struct GamepadModuleView: View {
    let module: GamepadModule
    let globalSettings: LayoutGlobals
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var mouseManager: MouseManager
    @ObservedObject var turboEngine: TurboEngine
    @ObservedObject var gestureLockEngine: GestureLockEngine
    let isEditMode: Bool
    let isPositionEditMode: Bool
    let isKeyMappingMode: Bool
    var showSettingsButton: Bool = true
    let layoutScale: CGFloat
    let canvasSize: CGSize

    var onModulePress: (String, String?) -> Void
    var onModuleRelease: (String, String?) -> Void
    var onModuleConfig: (String) -> Void

    @State private var isPressed = false
    @State private var gestureTracker = GestureLockTracker()
    @State private var stickActiveKeys: Set<String> = []
    @StateObject private var hapticManager = HapticFeedbackManager.shared

    var effectiveScale: Double {
        module.scale
    }

    var accentColor: Color {
        if let argb = module.moduleAccentArgb {
            return Color(argb: argb)
        }
        return .blue
    }

    var accentUIColor: UIColor {
        UIColor(accentColor)
    }

    var accentPressedUIColor: UIColor {
        if let argb = module.moduleAccentArgb {
            let color = Color(argb: argb)
            return UIColor(color).withAlphaComponent(0.7)
        }
        return UIColor.blue.withAlphaComponent(0.7)
    }

    var body: some View {
        Group {
            switch module.type {
            case .button:
                moduleButtonView
            case .dpad:
                moduleDpadView
            case .analogStick:
                moduleStickView
            case .scrollStrip:
                moduleScrollStripView
            case .touchpad:
                moduleTouchpadView
            case .mouseButton:
                moduleMouseButtonView
            case .shoulder:
                moduleShoulderView
            case .trigger:
                moduleTriggerView
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditMode && showSettingsButton {
                settingsButton
            }
        }
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            onModuleConfig(module.id)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
                .padding(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Button Module

    @ViewBuilder
    private var moduleButtonView: some View {
        let label = module.displayLabel ?? "Btn"
        let key = module.derivedKey ?? ""
        let baseRadius = 100.0 * layoutScale * CGFloat(module.scale)
        let w = baseRadius * 2 * CGFloat(module.buttonWidthRatio)
        let h = baseRadius * 2 * CGFloat(module.buttonHeightRatio)

        MultiTouchDragButton(
            label: label,
            normalColor: accentUIColor,
            pressedColor: accentPressedUIColor,
            cornerRadiusNorm: module.buttonCornerRadiusNorm,
            borderColor: .clear,
            isEnabled: !isEditMode,
            onPress: {
                if !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    handleButtonPress(key: key)
                }
            },
            onDrag: { translation in
                gestureTracker.recordOffset(dx: translation.width, dy: translation.height)
            },
            onRelease: {
                let wasPressed = isPressed
                isPressed = false
                handleButtonRelease(wasPressed: wasPressed, key: key)
            }
        )
        .frame(width: w, height: h)
    }

    // MARK: - D-Pad Module

    @ViewBuilder
    private var moduleDpadView: some View {
        let variant = DPadVariant(rawValue: module.dpadVariant ?? "cross") ?? .cross
        let baseRadius = 180.0 * layoutScale * CGFloat(module.scale)
        let labels: [String: String] = [
            "Up":    module.stickUpKey    ?? "▲",
            "Down":  module.stickDownKey  ?? "▼",
            "Left":  module.stickLeftKey  ?? "◀",
            "Right": module.stickRightKey ?? "▶"
        ]
        DPadVariantView(
            variant: variant,
            baseRadius: baseRadius,
            directionLabels: labels,
            onDirection: { dir in onModulePress(module.id, dir) },
            onDirectionUp: { dir in onModuleRelease(module.id, dir) },
            onLongPress: { dir in onModuleConfig(module.id) },
            isEditMode: isEditMode,
            isKeyMappingMode: isKeyMappingMode
        )
    }

    // MARK: - Analog Stick Module

    @ViewBuilder
    private var moduleStickView: some View {
        let baseRadius = 180.0 * layoutScale * CGFloat(module.scale)
        let isMouseStick = module.stickMouseSensitivity != nil
        if isMouseStick {
            AnalogStickView(
                position: Binding(
                    get: { .zero },
                    set: { pos in
                        handleStickMouseMove(pos: pos)
                    }
                ),
                onTap: { onModuleConfig(module.id) },
                stickName: module.id,
                isEditMode: isEditMode,
                baseRadius: baseRadius
            )
        } else {
            AnalogStickView(
                position: Binding(
                    get: { .zero },
                    set: { pos in
                        handleStickKeyboardMove(pos: pos)
                    }
                ),
                onTap: { onModuleConfig(module.id) },
                stickName: module.id,
                isEditMode: isEditMode,
                baseRadius: baseRadius
            )
        }
    }

    private func handleStickMouseMove(pos: CGPoint) {
        if abs(pos.x) < 0.1 && abs(pos.y) < 0.1 {
            mouseManager.handleDragEnded()
            return
        }
        let sensitivity = module.stickMouseSensitivity ?? 1.0
        let magnitude = sqrt(pos.x * pos.x + pos.y * pos.y)
        let baseSensitivity: CGFloat = 2.0 * CGFloat(sensitivity)
        let maxSensitivity: CGFloat = 8.0 * CGFloat(sensitivity)
        let accelerationFactor = pow(magnitude, 1.8)
        let dynamicSensitivity = baseSensitivity + (maxSensitivity - baseSensitivity) * accelerationFactor
        var deltaX = pos.x * dynamicSensitivity
        var deltaY = pos.y * dynamicSensitivity
        deltaX = max(-25, min(25, deltaX))
        deltaY = max(-25, min(25, deltaY))
        let basePosition = CGPoint(x: 100, y: 100)
        let currentPosition = CGPoint(x: basePosition.x + deltaX, y: basePosition.y + deltaY)
        mouseManager.previousPosition = basePosition
        mouseManager.handleDragChanged(currentPosition: currentPosition)
    }

    private func handleStickKeyboardMove(pos: CGPoint) {
        let activationThreshold: CGFloat = 0.6
        let deadZone: CGFloat = 0.1

        var keysToPress: [String] = []
        if abs(pos.x) < deadZone && abs(pos.y) < deadZone {
            // Stick returned to center — release all active keys
            for key in stickActiveKeys {
                keyboardManager.handleKeyUp(key)
            }
            stickActiveKeys.removeAll()
            return
        }

        if -pos.y > activationThreshold { keysToPress.append(module.stickUpKey ?? "W") }
        else if -pos.y < -activationThreshold { keysToPress.append(module.stickDownKey ?? "S") }
        if pos.x > activationThreshold { keysToPress.append(module.stickRightKey ?? "D") }
        else if pos.x < -activationThreshold { keysToPress.append(module.stickLeftKey ?? "A") }

        // Release keys that are no longer in the new direction
        let newKeySet = Set(keysToPress)
        for key in stickActiveKeys where !newKeySet.contains(key) {
            keyboardManager.handleKeyUp(key)
        }

        // Press new keys that weren't previously active
        for key in keysToPress where !stickActiveKeys.contains(key) {
            keyboardManager.handleKeyDown(key)
            if stickActiveKeys.isEmpty {
                hapticManager.triggerButtonPress()
            }
        }

        stickActiveKeys = newKeySet
    }

    // MARK: - Scroll Strip Module

    @ViewBuilder
    private var moduleScrollStripView: some View {
        let ww = CGFloat(module.widthNorm ?? 0.10) * canvasSize.width
        let hh = CGFloat(module.heightNorm ?? 0.36) * canvasSize.height
        ScrollStripView(
            mouseManager: mouseManager,
            isEditMode: isEditMode,
            sensitivity: module.scrollStripSensitivity ?? 1.0
        )
        .frame(width: ww, height: hh)
    }

    // MARK: - Touchpad Module

    @ViewBuilder
    private var moduleTouchpadView: some View {
        let ww = CGFloat(module.widthNorm ?? 0.35) * canvasSize.width
        let hh = CGFloat(module.heightNorm ?? 0.25) * canvasSize.height
        TouchpadModuleView(
            mouseManager: mouseManager,
            isEditMode: isEditMode
        )
        .frame(width: ww, height: hh)
    }

    // MARK: - Mouse Button Module

    @ViewBuilder
    private var moduleMouseButtonView: some View {
        let label = mouseButtonLabel
        let touchpadMouseButtonScale = globalSettings.touchpadMouseButtonScale ?? 1.0
        let screenScale = UIScreen.main.scale
        let baseRadius = 52.0 * screenScale * layoutScale * CGFloat(module.scale) * touchpadMouseButtonScale
        MultiTouchDragButton(
            label: label,
            normalColor: UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0),
            pressedColor: .systemGray,
            cornerRadiusNorm: 1.0,  // Perfect circle
            isEnabled: !isEditMode,
            onPress: {
                if !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    gestureTracker.recordStart()
                    onModulePress(module.id, nil)
                }
            },
            onDrag: { translation in
                gestureTracker.recordOffset(dx: translation.width, dy: translation.height)
            },
            onRelease: {
                let wasPressed = isPressed
                isPressed = false
                handleMouseButtonRelease(wasPressed: wasPressed)
            }
        )
        .frame(width: baseRadius * 2, height: baseRadius * 2)
    }

    private func handleMouseButtonRelease(wasPressed: Bool) {
        if module.hasGestureLock {
            let action = gestureTracker.committedAction(for: module)
            gestureTracker.highlightedQuadrant = nil
            let key = mouseButtonActionKey
            if !key.isEmpty {
                // Release first
                keyboardManager.handleKeyUp(key)
                // Execute gesture action
                switch action {
                case PresetConstants.gestureLockActionHoldLock:
                    gestureLockEngine.handleHoldLock(moduleId: module.id, key: key)
                case PresetConstants.gestureLockActionTurbo:
                    let period = module.turboPulsePeriodMs
                        ?? globalSettings.turboPulsePeriodMs ?? 70
                    gestureLockEngine.handleTurbo(moduleId: module.id, key: key,
                        config: TurboConfig(enabled: true, intervalMs: period, initialDelayMs: 0))
                default:
                    break
                }
            }
        } else {
            onModuleRelease(module.id, nil)
        }
    }

    /// Returns the mouse action key for this button (used for gesture lock).
    private var mouseButtonActionKey: String {
        switch module.mouseButton {
        case 1: return "Left Click"
        case 3: return "Right Click"
        default: return "Left Click"
        }
    }

    private var mouseButtonLabel: String {
        switch module.mouseButton {
        case 1: return "L"
        case 2: return "M"
        case 3: return "R"
        default: return "Btn"
        }
    }

    // MARK: - Shoulder Module

    @ViewBuilder
    private var moduleShoulderView: some View {
        let label = module.displayLabel ?? "SH"
        let key = hidKeyToKeyName(module.hidKey)
        let sw = 108.0 * layoutScale * CGFloat(module.scale)
        let sh = 34.0 * layoutScale * CGFloat(module.scale)

        MultiTouchDragButton(
            label: label,
            normalColor: UIColor(red: 0.35, green: 0.37, blue: 0.4, alpha: 1.0),
            pressedColor: accentPressedUIColor,
            cornerRadiusNorm: 0.47,  // ~8px on 34pt height, matching Android shoulder
            isEnabled: !isEditMode,
            onPress: {
                if !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    handleButtonPress(key: key)
                }
            },
            onDrag: { translation in
                gestureTracker.recordOffset(dx: translation.width, dy: translation.height)
            },
            onRelease: {
                let wasPressed = isPressed
                isPressed = false
                handleButtonRelease(wasPressed: wasPressed, key: key)
            }
        )
        .frame(width: sw, height: sh)
    }

    // MARK: - Trigger Module

    @ViewBuilder
    private var moduleTriggerView: some View {
        let label = module.displayLabel ?? "TR"
        let key = hidKeyToKeyName(module.hidKey)
        let sw = 108.0 * layoutScale * CGFloat(module.scale)
        let sh = 34.0 * layoutScale * CGFloat(module.scale)

        MultiTouchDragButton(
            label: label,
            normalColor: UIColor(red: 0.29, green: 0.31, blue: 0.34, alpha: 1.0),
            pressedColor: accentPressedUIColor,
            cornerRadiusNorm: 0.35,  // ~6px on 34pt height, matching Android trigger
            isEnabled: !isEditMode,
            onPress: {
                if !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    handleButtonPress(key: key)
                }
            },
            onDrag: { translation in
                gestureTracker.recordOffset(dx: translation.width, dy: translation.height)
            },
            onRelease: {
                let wasPressed = isPressed
                isPressed = false
                handleButtonRelease(wasPressed: wasPressed, key: key)
            }
        )
        .frame(width: sw, height: sh)
    }

    // MARK: - Button Press/Release Handlers

    private func handleButtonPress(key: String) {
        if !key.isEmpty {
            if module.turboEnabled {
                turboEngine.start(key: key, config: TurboConfig(
                    enabled: true,
                    intervalMs: module.turboIntervalMs ?? 80,
                    initialDelayMs: module.turboInitialDelayMs ?? 400
                ))
            } else if module.hasGestureLock {
                keyboardManager.handleKeyDown(key)
            } else {
                onModulePress(module.id, nil)
            }
        }
    }

    private func handleButtonRelease(wasPressed: Bool, key: String) {
        if key.isEmpty {
            if !module.hasGestureLock {
                onModuleRelease(module.id, nil)
            }
            return
        }

        // If turbo engine is active (non-gesture turbo), stop it
        if turboEngine.isActive {
            turboEngine.stop()
            onModuleRelease(module.id, nil)
            return
        }

        // If module has gesture lock, classify the gesture and act
        if module.hasGestureLock {
            let action = gestureTracker.committedAction(for: module)
            gestureTracker.highlightedQuadrant = nil

            // Release the key first (it was held during press)
            keyboardManager.handleKeyUp(key)

            // Execute the gesture action
            switch action {
            case PresetConstants.gestureLockActionHoldLock:
                gestureLockEngine.handleHoldLock(moduleId: module.id, key: key)
            case PresetConstants.gestureLockActionTurbo:
                let period = module.turboPulsePeriodMs
                    ?? globalSettings.turboPulsePeriodMs ?? 70
                gestureLockEngine.handleTurbo(moduleId: module.id, key: key,
                    config: TurboConfig(enabled: true, intervalMs: period, initialDelayMs: 0))
            case PresetConstants.gestureLockActionKeyHold:
                gestureLockEngine.handleHoldLock(moduleId: module.id, key: key)
            default:
                break
            }
        } else {
            onModuleRelease(module.id, nil)
        }
    }

    private func handleGestureLockAction(_ action: String, key: String) {
        switch action {
        case PresetConstants.gestureLockActionHoldLock:
            gestureLockEngine.handleHoldLock(moduleId: module.id, key: key)
        case PresetConstants.gestureLockActionTurbo:
            let period = module.turboPulsePeriodMs
                ?? globalSettings.turboPulsePeriodMs ?? 70
            gestureLockEngine.handleTurbo(moduleId: module.id, key: key,
                config: TurboConfig(enabled: true, intervalMs: period, initialDelayMs: 0))
        default:
            break
        }
    }

    private func hidKeyToKeyName(_ hidKey: Int?) -> String {
        guard let hidKey = hidKey else { return "" }
        // Basic HID keycode to key name mapping
        switch hidKey {
        case 4: return "A"
        case 5: return "B"
        case 6: return "C"
        case 7: return "D"
        case 8: return "E"
        case 9: return "F"
        case 10: return "G"
        case 11: return "H"
        case 12: return "I"
        case 13: return "J"
        case 14: return "K"
        case 15: return "L"
        case 16: return "M"
        case 17: return "N"
        case 18: return "O"
        case 19: return "P"
        case 20: return "Q"
        case 21: return "R"
        case 22: return "S"
        case 23: return "T"
        case 24: return "U"
        case 25: return "V"
        case 26: return "W"
        case 27: return "X"
        case 28: return "Y"
        case 29: return "Z"
        case 40: return "Enter"
        case 41: return "Escape"
        case 42: return "Backspace"
        case 43: return "Tab"
        case 44: return "Space"
        case 80: return "Right"
        case 81: return "Left"
        case 82: return "Down"
        case 83: return "Up"
        case 224: return "Ctrl"
        case 225: return "Shift"
        case 226: return "Alt"
        case 227: return "Cmd"
        default: return ""
        }
    }
}
