//
//  ModuleConfigSheet.swift
//  KeyMod
//
//  Configuration sheet for gamepad modules in dynamic layout.
//  Edits HID keys, D-pad variants, stick keys, turbo, gesture lock, and visual properties.
//

import SwiftUI

struct ModuleConfigSheet: View {
    @Binding var document: GamepadPresetDocument
    let module: GamepadModule
    @Binding var isPresented: Bool

    @State private var displayLabel: String
    @State private var derivedKey: String
    @State private var hidKey: Int
    @State private var dpadVariant: String
    @State private var stickUpKey: String
    @State private var stickLeftKey: String
    @State private var stickDownKey: String
    @State private var stickRightKey: String
    @State private var stickMouseSensitivity: Double
    @State private var scrollStripSensitivity: Double
    @State private var turboEnabled: Bool
    @State private var turboIntervalMs: Int
    @State private var turboInitialDelayMs: Int
    @State private var gestureLockEnabled: Bool
    @State private var gestureLockUpLeft: String
    @State private var gestureLockUpRight: String
    @State private var gestureLockDownLeft: String
    @State private var gestureLockDownRight: String
    @State private var buttonCornerRadius: Double
    @State private var accentColorHex: String
    @State private var selectedTab = ConfigTab.basic

    enum ConfigTab { case basic, turbo, gestureLock, appearance }

    init(document: Binding<GamepadPresetDocument>, module: GamepadModule, isPresented: Binding<Bool>) {
        self._document = document
        self.module = module
        self._isPresented = isPresented
        _displayLabel = State(initialValue: module.displayLabel ?? "")
        _derivedKey = State(initialValue: module.derivedKey ?? "")
        _hidKey = State(initialValue: module.hidKey ?? 0)
        _dpadVariant = State(initialValue: module.dpadVariant ?? "cross")
        _stickUpKey = State(initialValue: module.stickUpKey ?? "W")
        _stickLeftKey = State(initialValue: module.stickLeftKey ?? "A")
        _stickDownKey = State(initialValue: module.stickDownKey ?? "S")
        _stickRightKey = State(initialValue: module.stickRightKey ?? "D")
        _stickMouseSensitivity = State(initialValue: module.stickMouseSensitivity ?? 1.0)
        _scrollStripSensitivity = State(initialValue: module.scrollStripSensitivity ?? 1.0)
        _turboEnabled = State(initialValue: module.turboEnabled)
        _turboIntervalMs = State(initialValue: module.turboIntervalMs ?? 80)
        _turboInitialDelayMs = State(initialValue: module.turboInitialDelayMs ?? 400)
        _gestureLockEnabled = State(initialValue: module.hasGestureLock)
        _gestureLockUpLeft = State(initialValue: module.gestureLock?.upLeft?.action ?? "none")
        _gestureLockUpRight = State(initialValue: module.gestureLock?.upRight?.action ?? "none")
        _gestureLockDownLeft = State(initialValue: module.gestureLock?.downLeft?.action ?? "none")
        _gestureLockDownRight = State(initialValue: module.gestureLock?.downRight?.action ?? "none")
        _buttonCornerRadius = State(initialValue: module.buttonCornerRadiusNorm)
        _accentColorHex = State(initialValue: module.moduleAccentArgb.map { String(format: "#%08X", $0) } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                // Tab picker
                Section {
                    Picker("Tab", selection: Binding(
                        get: { selectedTab },
                        set: { selectedTab = $0 }
                    )) {
                        Text("Basic").tag(ConfigTab.basic)
                        Text("Turbo").tag(ConfigTab.turbo)
                        Text("Gesture Lock").tag(ConfigTab.gestureLock)
                        Text("Appearance").tag(ConfigTab.appearance)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                switch selectedTab {
                case .basic:
                    basicSection
                case .turbo:
                    turboSection
                case .gestureLock:
                    gestureLockSection
                case .appearance:
                    appearanceSection
                }
            }
            .navigationTitle(module.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyChanges()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Basic Section

    @ViewBuilder
    private var basicSection: some View {
        if module.type == .button || module.type == .shoulder || module.type == .trigger {
            TextField("Display Label", text: $displayLabel)
            TextField("Key Name (e.g. A, Space, Enter)", text: $derivedKey)
            Section("HID Key Code") {
                Stepper("HID Key: \(hidKey)", value: $hidKey, in: 0...255)
            }
        }

        if module.type == .dpad {
            Section("D-Pad Variant") {
                Picker("Variant", selection: $dpadVariant) {
                    ForEach(DPadVariant.allCases, id: \.rawValue) { v in
                        Text(v.rawValue.capitalized).tag(v.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }

        if module.type == .analogStick {
            Section("Stick Keys") {
                TextField("Up Key", text: $stickUpKey)
                TextField("Left Key", text: $stickLeftKey)
                TextField("Down Key", text: $stickDownKey)
                TextField("Right Key", text: $stickRightKey)
            }
            Section("Mouse Sensitivity") {
                Slider(value: $stickMouseSensitivity,
                       in: PresetConstants.stickMouseSensitivityMin...PresetConstants.stickMouseSensitivityMax) {
                    Text("Sensitivity")
                }
                Text(String(format: "%.2f", stickMouseSensitivity))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        if module.type == .scrollStrip {
            Section("Scroll Sensitivity") {
                Slider(value: $scrollStripSensitivity,
                       in: PresetConstants.scrollStripSensitivityMin...PresetConstants.scrollStripSensitivityMax) {
                    Text("Sensitivity")
                }
                Text(String(format: "%.2f", scrollStripSensitivity))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // Module info (read-only)
        Section("Module Info") {
            HStack { Text("Type").foregroundColor(.secondary); Spacer(); Text(module.type.rawValue) }
            HStack { Text("ID").foregroundColor(.secondary); Spacer(); Text(module.id) }
            HStack { Text("Position").foregroundColor(.secondary); Spacer(); Text(String(format: "(%.2f, %.2f)", module.anchorX, module.anchorY)) }
            HStack { Text("Scale").foregroundColor(.secondary); Spacer(); Text(String(format: "%.2f", module.scale)) }
        }
    }

    // MARK: - Turbo Section

    @ViewBuilder
    private var turboSection: some View {
        Toggle("Turbo Enabled", isOn: $turboEnabled)

        if turboEnabled {
            Section("Turbo Timing") {
                Stepper("Interval: \(turboIntervalMs)ms", value: $turboIntervalMs,
                        in: PresetConstants.turboPulsePeriodMsMin...PresetConstants.turboPulsePeriodMsMax)
                Stepper("Initial Delay: \(turboInitialDelayMs)ms", value: $turboInitialDelayMs,
                        in: 50...1000)
            }
        }
    }

    // MARK: - Gesture Lock Section

    @ViewBuilder
    private var gestureLockSection: some View {
        Toggle("Gesture Lock Enabled", isOn: $gestureLockEnabled)

        if gestureLockEnabled {
            Section("Diagonal Slot Actions") {
                Picker("Up-Left", selection: $gestureLockUpLeft) {
                    gestureLockActionOptions
                }
                Picker("Up-Right", selection: $gestureLockUpRight) {
                    gestureLockActionOptions
                }
                Picker("Down-Left", selection: $gestureLockDownLeft) {
                    gestureLockActionOptions
                }
                Picker("Down-Right", selection: $gestureLockDownRight) {
                    gestureLockActionOptions
                }
            }
        }
    }

    @ViewBuilder
    private var gestureLockActionOptions: some View {
        Text("None").tag(PresetConstants.gestureLockActionNone)
        Text("Hold Lock").tag(PresetConstants.gestureLockActionHoldLock)
        Text("Turbo").tag(PresetConstants.gestureLockActionTurbo)
        Text("Key Hold").tag(PresetConstants.gestureLockActionKeyHold)
        Text("Key Turbo").tag(PresetConstants.gestureLockActionKeyTurbo)
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Button Shape") {
            Slider(value: $buttonCornerRadius,
                   in: PresetConstants.buttonCornerRadiusNormMin...PresetConstants.buttonCornerRadiusNormMax) {
                Text("Corner Radius")
            }
            Text(String(format: "%.2f", buttonCornerRadius))
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Section("Accent Color") {
            TextField("#AABBCCDD", text: $accentColorHex)
                .font(.system(.caption, design: .monospaced))
            if let argb = Int(hex: accentColorHex) {
                Circle()
                    .fill(Color(argb: argb))
                    .frame(width: 24, height: 24)
            }
        }
    }

    // MARK: - Apply Changes

    private func applyChanges() {
        guard let index = document.modules.firstIndex(where: { $0.id == module.id }) else { return }

        document.modules[index].displayLabel = displayLabel.isEmpty ? nil : displayLabel
        document.modules[index].derivedKey = derivedKey.isEmpty ? nil : derivedKey
        document.modules[index].hidKey = hidKey == 0 ? nil : hidKey
        document.modules[index].dpadVariant = dpadVariant
        document.modules[index].stickUpKey = stickUpKey
        document.modules[index].stickLeftKey = stickLeftKey
        document.modules[index].stickDownKey = stickDownKey
        document.modules[index].stickRightKey = stickRightKey
        document.modules[index].stickMouseSensitivity = stickMouseSensitivity
        document.modules[index].scrollStripSensitivity = scrollStripSensitivity
        document.modules[index].turboEnabled = turboEnabled
        document.modules[index].turboIntervalMs = turboIntervalMs
        document.modules[index].turboInitialDelayMs = turboInitialDelayMs
        document.modules[index].buttonCornerRadiusNorm = buttonCornerRadius

        // Gesture lock
        if gestureLockEnabled {
            document.modules[index].gestureLock = GestureLockConfig(
                upLeft: GestureLockSlotDetail(action: gestureLockUpLeft),
                upRight: GestureLockSlotDetail(action: gestureLockUpRight),
                downLeft: GestureLockSlotDetail(action: gestureLockDownLeft),
                downRight: GestureLockSlotDetail(action: gestureLockDownRight)
            )
            document.modules[index].keyboardHoldLock = true
        } else {
            document.modules[index].gestureLock = nil
            document.modules[index].keyboardHoldLock = nil
        }

        // Accent color
        if let argb = Int(hex: accentColorHex) {
            document.modules[index].moduleAccentArgb = argb
        }
    }
}

