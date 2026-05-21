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
    let isEditMode: Bool
    let isPositionEditMode: Bool
    let isKeyMappingMode: Bool
    let layoutScale: CGFloat
    let canvasSize: CGSize

    var onModulePress: (String, String?) -> Void
    var onModuleRelease: (String, String?) -> Void
    var onModuleConfig: (String) -> Void

    @State private var isPressed = false
    @State private var gestureTracker = GestureLockTracker()
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
            if isEditMode {
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
        let cornerRadius = module.buttonCornerRadiusNorm * min(w, h) / 2

        Button(action: {}) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: w, height: h)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isPressed ? accentColor.opacity(0.7) : accentColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .simultaneousGesture(moduleDragGesture(componentId: module.id, key: key))
    }

    // MARK: - D-Pad Module

    @ViewBuilder
    private var moduleDpadView: some View {
        let variant = DPadVariant(rawValue: module.dpadVariant ?? "cross") ?? .cross
        let baseRadius = 180.0 * layoutScale * CGFloat(module.scale)
        DPadVariantView(
            variant: variant,
            baseRadius: baseRadius,
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
        if abs(pos.x) < deadZone && abs(pos.y) < deadZone {
            return
        }
        var keysToPress: [String] = []
        if -pos.y > activationThreshold { keysToPress.append(module.stickUpKey ?? "W") }
        else if -pos.y < -activationThreshold { keysToPress.append(module.stickDownKey ?? "S") }
        if pos.x > activationThreshold { keysToPress.append(module.stickRightKey ?? "D") }
        else if pos.x < -activationThreshold { keysToPress.append(module.stickLeftKey ?? "A") }
        if !keysToPress.isEmpty {
            keyboardManager.handleKeysDown(keysToPress)
        }
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
            isEditMode: isEditMode,
            onDelta: { dx, dy in
                let basePosition = CGPoint(x: 100, y: 100)
                let currentPosition = CGPoint(x: basePosition.x + dx, y: basePosition.y + dy)
                mouseManager.previousPosition = basePosition
                mouseManager.handleDragChanged(currentPosition: currentPosition)
            },
            onDragEnd: {
                mouseManager.handleDragEnded()
            }
        )
        .frame(width: ww, height: hh)
    }

    // MARK: - Mouse Button Module

    @ViewBuilder
    private var moduleMouseButtonView: some View {
        let label = mouseButtonLabel
        let baseRadius = 52.0 * layoutScale * CGFloat(module.scale)
        Button(action: {}) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: baseRadius * 2, height: baseRadius * 2)
                .background(
                    Circle()
                        .fill(isPressed ? Color.gray : Color(red: 0.35, green: 0.35, blue: 0.38))
                )
        }
        .simultaneousGesture(moduleDragGesture(componentId: module.id, key: ""))
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

        Button(action: {}) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: sw, height: sh)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPressed ? accentColor.opacity(0.7) : Color(red: 0.35, green: 0.37, blue: 0.4))
                )
        }
        .simultaneousGesture(moduleDragGesture(componentId: module.id, key: key))
    }

    // MARK: - Trigger Module

    @ViewBuilder
    private var moduleTriggerView: some View {
        let label = module.displayLabel ?? "TR"
        let key = hidKeyToKeyName(module.hidKey)
        let sw = 108.0 * layoutScale * CGFloat(module.scale)
        let sh = 34.0 * layoutScale * CGFloat(module.scale)

        Button(action: {}) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: sw, height: sh)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isPressed ? accentColor.opacity(0.7) : Color(red: 0.29, green: 0.31, blue: 0.34))
                )
        }
        .simultaneousGesture(moduleDragGesture(componentId: module.id, key: key))
    }

    // MARK: - Shared Gesture Handler

    private func moduleDragGesture(componentId: String, key: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressed {
                    isPressed = true
                    hapticManager.triggerButtonPress()
                    if !key.isEmpty {
                        // Check turbo first
                        if module.turboEnabled && !key.isEmpty {
                            turboEngine.start(key: key, config: TurboConfig(
                                enabled: true,
                                intervalMs: module.turboIntervalMs ?? 80,
                                initialDelayMs: module.turboInitialDelayMs ?? 400
                            ))
                        } else if module.hasGestureLock {
                            // Gesture lock: send keyDown for hold behavior
                            keyboardManager.handleKeyDown(key)
                        } else {
                            onModulePress(componentId, nil)
                        }
                    }
                }
                // Track for gesture lock
                gestureTracker.recordOffset(dx: value.translation.width, dy: value.translation.height)
            }
            .onEnded { value in
                let wasPressed = isPressed
                isPressed = false
                gestureTracker.recordOffset(dx: value.translation.width, dy: value.translation.height)

                if wasPressed && !key.isEmpty {
                    // If turbo is running, stop it
                    if turboEngine.isActive {
                        turboEngine.stop()
                    } else if module.hasGestureLock {
                        // For gesture lock, check the resolved action
                        let action = gestureTracker.committedAction(for: module)
                        gestureTracker.highlightedQuadrant = nil
                        switch action {
                        case PresetConstants.gestureLockActionHoldLock,
                             PresetConstants.gestureLockActionKeyHold:
                            keyboardManager.handleKeyUp(key)
                        default:
                            keyboardManager.handleKeyUp(key)
                        }
                    } else {
                        onModuleRelease(componentId, nil)
                    }
                }

                // Check gesture lock
                let action = gestureTracker.committedAction(for: module)
                gestureTracker.highlightedQuadrant = nil
                handleGestureLockAction(action, key: key)
            }
    }

    private func handleGestureLockAction(_ action: String, key: String) {
        switch action {
        case PresetConstants.gestureLockActionHoldLock:
            if !key.isEmpty {
                keyboardManager.handleKeyDown(key)
                // Key stays pressed until explicit release
            }
        case PresetConstants.gestureLockActionTurbo:
            // Turbo would be started here if we had a TurboEngine reference
            // For now, just send the key
            if !key.isEmpty {
                keyboardManager.handleKeyDown(key)
            }
        case PresetConstants.gestureLockActionKeyHold:
            if !key.isEmpty {
                keyboardManager.handleKeyDown(key)
            }
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
