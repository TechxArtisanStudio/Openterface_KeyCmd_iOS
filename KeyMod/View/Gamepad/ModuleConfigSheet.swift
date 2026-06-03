//
//  ModuleConfigSheet.swift
//  KeyMod
//
//  Configuration sheet for gamepad modules — matches Android's scrollable form + pinned footer.
//  Per-module settings: Stick/D-Pad mode selector, direction key mapping, button geometry, etc.
//

import SwiftUI

struct ModuleConfigSheet: View {
    @Binding var document: GamepadPresetDocument
    let module: GamepadModule
    @Binding var isPresented: Bool

    // Working state
    @State private var displayLabel: String
    @State private var derivedKey: String
    @State private var hidKey: Int
    @State private var dpadVariant: String
    @State private var stickUpKey: String
    @State private var stickLeftKey: String
    @State private var stickDownKey: String
    @State private var stickRightKey: String
    @State private var stickCenterKey: String
    @State private var stickMouseSensitivity: Double
    @State private var scrollStripSensitivity: Double
    @State private var scrollStripInvertY: Bool
    @State private var turboEnabled: Bool
    @State private var turboIntervalMs: Int
    @State private var turboInitialDelayMs: Int
    @State private var gestureLockEnabled: Bool
    @State private var gestureLockUpLeft: String
    @State private var gestureLockUpRight: String
    @State private var gestureLockDownLeft: String
    @State private var gestureLockDownRight: String
    @State private var buttonCornerRadius: Double
    @State private var buttonWidthRatio: Double
    @State private var buttonHeightRatio: Double
    @State private var buttonRotationDeg: Double
    @State private var mappedKeyLabelVisible: Bool
    @State private var accentColorHex: String
    @State private var moduleScale: Double
    @State private var touchpadMouseButtonScale: Double
    @State private var hasTouchpad: Bool
    @State private var widthNorm: Double
    @State private var heightNorm: Double
    @State private var crossArmDecoration: String
    @State private var dpadSplitGapRatio: Double
    @State private var dpadSplitOuterReachRatio: Double
    @State private var selectedMode: StickMode

    // UI state
    @State private var showRemoveConfirm = false
    @State private var showDuplicateConfirm = false
    @State private var showKeyPicker = false
    @State private var keyPickerTarget: KeyPickerTarget?

    enum KeyPickerTarget {
        case up, left, down, right, center, mappedKey
    }

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
        _stickCenterKey = State(initialValue: module.stickCenterKey ?? "")
        _stickMouseSensitivity = State(initialValue: module.stickMouseSensitivity ?? 1.0)
        _scrollStripSensitivity = State(initialValue: module.scrollStripSensitivity ?? 1.0)
        _scrollStripInvertY = State(initialValue: module.scrollStripInvertY ?? false)
        _turboEnabled = State(initialValue: module.turboEnabled)
        _turboIntervalMs = State(initialValue: module.turboIntervalMs ?? 80)
        _turboInitialDelayMs = State(initialValue: module.turboInitialDelayMs ?? 400)
        _gestureLockEnabled = State(initialValue: module.hasGestureLock)
        _gestureLockUpLeft = State(initialValue: module.gestureLock?.upLeft?.action ?? "none")
        _gestureLockUpRight = State(initialValue: module.gestureLock?.upRight?.action ?? "none")
        _gestureLockDownLeft = State(initialValue: module.gestureLock?.downLeft?.action ?? "none")
        _gestureLockDownRight = State(initialValue: module.gestureLock?.downRight?.action ?? "none")
        _buttonCornerRadius = State(initialValue: module.buttonCornerRadiusNorm)
        _buttonWidthRatio = State(initialValue: module.buttonWidthRatio)
        _buttonHeightRatio = State(initialValue: module.buttonHeightRatio)
        _buttonRotationDeg = State(initialValue: module.buttonRotationDeg)
        _mappedKeyLabelVisible = State(initialValue: module.mappedKeyLabelVisible ?? true)
        _accentColorHex = State(initialValue: module.moduleAccentArgb.map { String(format: "#%08X", $0) } ?? "")
        _moduleScale = State(initialValue: module.scale)
        _touchpadMouseButtonScale = State(initialValue: document.wrappedValue.layout.touchpadMouseButtonScale ?? 1.0)
        _hasTouchpad = State(initialValue: document.wrappedValue.modules.contains { $0.type == .touchpad })
        _widthNorm = State(initialValue: module.widthNorm ?? 0.35)
        _heightNorm = State(initialValue: module.heightNorm ?? 0.25)
        _crossArmDecoration = State(initialValue: module.dpadCrossArmDecoration ?? "none")
        _dpadSplitGapRatio = State(initialValue: module.dpadSplitGapRatio ?? 0.08)
        _dpadSplitOuterReachRatio = State(initialValue: module.dpadSplitOuterReachRatio ?? 0.5)
        // Compute initial mode from module type
        if module.type == .analogStick {
            _selectedMode = State(initialValue: module.stickMouseSensitivity != nil ? .stickMouse : .stickKeys)
        } else if module.type == .dpad {
            _selectedMode = State(initialValue: (module.dpadVariant ?? "cross") == "split" ? .dpadSplit : .dpadCross)
        } else {
            _selectedMode = State(initialValue: .stickKeys)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Module ID
                        Text("Module ID: \(module.id)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(.bottom, 12)

                        // Divider
                        Divider().padding(.bottom, 16)

                        // Module-specific settings
                        moduleSettings

                        Divider().padding(.vertical, 16)

                        // Module color section
                        colorSection

                        // Size slider (all modules)
                        sizeSection
                    }
                    .padding(.horizontal, 4)
                }

                // Pinned footer
                footerBar
            }
            .navigationTitle(module.id)
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Remove Module", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                removeModule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(module.id)? This cannot be undone.")
        }
        .alert("Duplicate Module", isPresented: $showDuplicateConfirm) {
            Button("Duplicate") {
                duplicateModule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a copy of \(module.id)?")
        }
        .sheet(isPresented: $showKeyPicker) {
            KeyPickerSheet(
                isPresented: $showKeyPicker,
                selectedKey: keyBinding(for: keyPickerTarget ?? .mappedKey),
                selectedHidKey: keyHidBinding()
            )
        }
    }

    // MARK: - Module Settings (type-specific)

    @ViewBuilder
    private var moduleSettings: some View {
        switch module.type {
        case .dpad, .analogStick:
            stickDpadSettings
        case .button, .shoulder, .trigger:
            buttonSettings
        case .touchpad:
            touchpadSettings
        case .scrollStrip:
            scrollStripSettings
        case .mouseButton:
            mouseButtonSettings
        }
    }

    // MARK: - Stick / D-Pad Settings

    private var stickDpadSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display name
            sectionHeader("Display Name")
            TextField("Custom label", text: $displayLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            // Mode selector
            sectionHeader("Mode")
            VStack(spacing: 8) {
                modeRadio(.stickMouse, label: "Relative pointer (mouse)")
                modeRadio(.stickKeys, label: "Direction keys (virtual stick)")
                modeRadio(.dpadCross, label: "D-pad (cross, digital)")
                modeRadio(.dpadSplit, label: "D-pad (split segments)")
            }

            // Pointer sensitivity (mouse mode)
            if currentMode == .stickMouse {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Pointer Sensitivity")
                    Text("Slower — Faster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $stickMouseSensitivity,
                           in: PresetConstants.stickMouseSensitivityMin...PresetConstants.stickMouseSensitivityMax)
                    Text(String(format: "%.2fx", stickMouseSensitivity))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Split spacing (split mode, stick_left only)
            if currentMode == .dpadSplit {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Split Spacing")
                    Text("Gap between segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $dpadSplitGapRatio,
                           in: PresetConstants.dpadSplitGapRatioMin...PresetConstants.dpadSplitGapRatioMax)
                    Text(String(format: "%.2f", dpadSplitGapRatio))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Distance to Keys")
                    Text("Outer reach of segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $dpadSplitOuterReachRatio,
                           in: PresetConstants.dpadSplitOuterReachRatioMin...PresetConstants.dpadSplitOuterReachRatioMax)
                    Text(String(format: "%.2f", dpadSplitOuterReachRatio))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Cross arm decoration (cross mode)
            if currentMode == .dpadCross {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Cross D-pad Arms")
                    Picker("Decoration", selection: $crossArmDecoration) {
                        Text("Nothing").tag("none")
                        Text("Mapped key labels").tag("labels")
                        Text("Direction icons").tag("icons")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }

            // Direction keys (cross layout)
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Direction Keys")
                // Cross layout: Up centered, Left/Right side by side, Down centered
                VStack(spacing: 4) {
                    // Row 1: Up
                    keyButton(stickUpKey, label: "Up", target: .up)
                        .frame(width: 90, height: 48)

                    // Row 2: Left, Right
                    HStack(spacing: 4) {
                        keyButton(stickLeftKey, label: "Left", target: .left)
                            .frame(width: 90, height: 48)
                        keyButton(stickRightKey, label: "Right", target: .right)
                            .frame(width: 90, height: 48)
                    }

                    // Row 3: Down
                    keyButton(stickDownKey, label: "Down", target: .down)
                        .frame(width: 90, height: 48)
                }

                // Center key
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Center (Hub) Key")
                    HStack {
                        keyButton(stickCenterKey.isEmpty ? "None" : stickCenterKey,
                                  label: "Center", target: .center)
                            .frame(maxWidth: .infinity, maxHeight: 48)
                        if !stickCenterKey.isEmpty {
                            Button("Clear") {
                                stickCenterKey = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var currentMode: StickMode { selectedMode }

    @ViewBuilder
    private func modeRadio(_ mode: StickMode, label: String) -> some View {
        Button {
            applyMode(mode)
        } label: {
            HStack {
                Image(systemName: currentMode == mode ? "record.circle" : "circle")
                    .foregroundColor(currentMode == mode ? .blue : .gray)
                    .font(.system(size: 18))
                Text(label)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func applyMode(_ mode: StickMode) {
        selectedMode = mode
        switch mode {
        case .stickMouse:
            dpadVariant = "cross"
        case .stickKeys:
            dpadVariant = "cross"
        case .dpadCross:
            dpadVariant = "cross"
        case .dpadSplit:
            dpadVariant = "split"
        }
    }

    // MARK: - Button / Shoulder / Trigger Settings

    private var buttonSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display name
            sectionHeader("Display Name")
            TextField("Custom label", text: $displayLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            // Mapped key label toggle
            Toggle("Show mapped key label", isOn: $mappedKeyLabelVisible)

            // Hold lock gesture
            Toggle("Hold lock gesture", isOn: $gestureLockEnabled)

            // Gesture lock diagonals
            if gestureLockEnabled {
                VStack(spacing: 8) {
                    gestureLockPicker("Up-Left", selection: $gestureLockUpLeft)
                    gestureLockPicker("Up-Right", selection: $gestureLockUpRight)
                    gestureLockPicker("Down-Left", selection: $gestureLockDownLeft)
                    gestureLockPicker("Down-Right", selection: $gestureLockDownRight)
                }
            }

            // Mapped key button
            sectionHeader("Mapped Key")
            Button(action: { keyPickerTarget = .mappedKey; showKeyPicker = true }) {
                HStack {
                    Text(derivedKey.isEmpty ? "Tap to pick key" : derivedKey)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Button geometry (button type only)
            if module.type == .button {
                Divider().padding(.vertical, 8)

                sectionHeader("Button Size")
                labeledSlider(value: $moduleScale, range: 0...2.0, format: "%.2fx",
                              leftLabel: "Small", rightLabel: "Large")

                sectionHeader("Corner Radius")
                Text("Square — Round")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $buttonCornerRadius,
                       in: PresetConstants.buttonCornerRadiusNormMin...PresetConstants.buttonCornerRadiusNormMax)
                Text(String(format: "%.0f%%", buttonCornerRadius * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider().padding(.vertical, 8)
                sectionHeader("Button Shape")
                Text("Width ratio")
                    .font(.caption)
                    .foregroundColor(.secondary)
                labeledSlider(value: $buttonWidthRatio, range: 0.25...3.5, format: "%.2fx",
                              leftLabel: "25%", rightLabel: "350%")
                labeledSlider(value: $buttonHeightRatio, range: 0.25...3.5, format: "%.2fx",
                              leftLabel: "25%", rightLabel: "350%")
                labeledSlider(value: $buttonRotationDeg, range: -180...180, format: "%.0f°",
                              leftLabel: "-180°", rightLabel: "+180°")
            }
        }
    }

    // MARK: - Touchpad Settings

    private var touchpadSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Display Name")
            TextField("Custom label", text: $displayLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            sectionHeader("Width")
            Slider(value: $widthNorm, in: 0.10...0.65)
            Text(String(format: "%.0f%%", widthNorm * 100))
                .font(.caption)
                .foregroundColor(.secondary)

            sectionHeader("Height")
            Slider(value: $heightNorm, in: 0.10...0.65)
            Text(String(format: "%.0f%%", heightNorm * 100))
                .font(.caption)
                .foregroundColor(.secondary)

            // Layout-wide touchpad mouse button scale
            if hasTouchpad {
                sectionHeader("All touchpad mouse buttons size")
                labeledSlider(value: $touchpadMouseButtonScale, range: 0.5...2.0, format: "%.2fx",
                              leftLabel: "Small", rightLabel: "Large")
            }
        }
    }

    // MARK: - Scroll Strip Settings

    private var scrollStripSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Display Name")
            TextField("Custom label", text: $displayLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            sectionHeader("Width")
            Slider(value: $widthNorm, in: 0.10...0.65)
            Text(String(format: "%.0f%%", widthNorm * 100))
                .font(.caption)
                .foregroundColor(.secondary)

            sectionHeader("Height")
            Slider(value: $heightNorm, in: 0.10...0.65)
            Text(String(format: "%.0f%%", heightNorm * 100))
                .font(.caption)
                .foregroundColor(.secondary)

            sectionHeader("Wheel Sensitivity")
            Slider(value: $scrollStripSensitivity,
                   in: PresetConstants.scrollStripSensitivityMin...PresetConstants.scrollStripSensitivityMax)
            Text(String(format: "%.2fx", scrollStripSensitivity))
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Invert vertical wheel", isOn: $scrollStripInvertY)
        }
    }

    // MARK: - Mouse Button Settings

    private var mouseButtonSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display name
            sectionHeader("Display Name")
            TextField("Custom label", text: $displayLabel)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            // Per-button size
            sectionHeader("Button Size")
            labeledSlider(value: $moduleScale, range: 0.5...2.0, format: "%.2fx",
                          leftLabel: "Small", rightLabel: "Large")

            // Layout-wide touchpad mouse button scale (only when touchpad exists)
            if hasTouchpad {
                sectionHeader("All touchpad mouse buttons size")
                labeledSlider(value: $touchpadMouseButtonScale, range: 0.5...2.0, format: "%.2fx",
                              leftLabel: "Small", rightLabel: "Large")
            }

            // Hold lock gesture
            Toggle("Hold lock gesture", isOn: $gestureLockEnabled)

            if gestureLockEnabled {
                VStack(spacing: 8) {
                    gestureLockPicker("Up-Left", selection: $gestureLockUpLeft)
                    gestureLockPicker("Up-Right", selection: $gestureLockUpRight)
                    gestureLockPicker("Down-Left", selection: $gestureLockDownLeft)
                    gestureLockPicker("Down-Right", selection: $gestureLockDownRight)
                }
            }
        }
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Module Color")
            HStack {
                // Color swatches
                ForEach(Self.commonColors, id: \.self) { argb in
                    Circle()
                        .fill(Color(argb: argb))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: accentColorHex == String(format: "#%08X", argb) ? 2 : 0)
                        )
                        .onTapGesture {
                            accentColorHex = String(format: "#%08X", argb)
                            applyAccentColorLive(argb: argb)
                        }
                }
            }

            TextField("#AABBCCDD", text: $accentColorHex)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: accentColorHex) { hex in
                    if let argb = Int(hex: hex) {
                        applyAccentColorLive(argb: argb)
                    }
                }
        }
    }

    private func applyAccentColorLive(argb: Int) {
        guard let index = document.modules.firstIndex(where: { $0.id == module.id }) else { return }
        document.modules[index].moduleAccentArgb = argb
    }

    private static let commonColors: [Int] = [
        0xFF2196F3, 0xFF4CAF50, 0xFFFF9800, 0xFFE91E63,
        0xFF9C27B0, 0xFF00BCD4, 0xFFFF5722, 0xFF607D8B,
        0xFFFFFFFF, 0xFF000000
    ]

    // MARK: - Size Section

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Module Size")
            labeledSlider(value: $moduleScale, range: 0...2.0, format: "%.2fx",
                          leftLabel: "Small", rightLabel: "Large")
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            // Remove (red outlined, only for non-essential modules)
            if !isEssentialModule {
                Button {
                    showRemoveConfirm = true
                } label: {
                    Text("Remove")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 1)
                )
            }

            Spacer()

            // Reset
            Button {
                resetToDefaults()
            } label: {
                Text("Reset")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(UIColor.systemGray5))

            // Duplicate
            Button {
                showDuplicateConfirm = true
            } label: {
                Text("Duplicate")
            }
            .buttonStyle(.bordered)

            // Done
            Button {
                applyChanges()
                isPresented = false
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .overlay(Divider(), alignment: .top)
    }

    private var isEssentialModule: Bool {
        // stick_left, stick_right, shoulder_l/r, trigger_l/r are essential
        let essentialIds = ["stick_left", "stick_right", "shoulder_l", "shoulder_r", "trigger_l", "trigger_r"]
        return essentialIds.contains(module.id)
    }

    // MARK: - Key Button

    @ViewBuilder
    private func keyButton(_ text: String, label: String, target: KeyPickerTarget) -> some View {
        Button {
            keyPickerTarget = target
            showKeyPicker = true
        } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.blue)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    /// Return a binding to the correct @State variable for the given picker target.
    func keyBinding(for target: KeyPickerTarget) -> Binding<String> {
        switch target {
        case .up: $stickUpKey
        case .left: $stickLeftKey
        case .down: $stickDownKey
        case .right: $stickRightKey
        case .center: $stickCenterKey
        case .mappedKey: $derivedKey
        }
    }

    /// Return a binding to the hidKey state (used for mapped key only).
    /// For stick keys, hidKey is fixed; for mapped key we read/write hidKey directly.
    func keyHidBinding() -> Binding<Int> {
        $hidKey
    }

    // MARK: - Gesture Lock Picker

    private func gestureLockPicker(_ label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: selection) {
                Text("None").tag(PresetConstants.gestureLockActionNone)
                Text("Hold Lock").tag(PresetConstants.gestureLockActionHoldLock)
                Text("Turbo").tag(PresetConstants.gestureLockActionTurbo)
                Text("Key Hold").tag(PresetConstants.gestureLockActionKeyHold)
                Text("Key Turbo").tag(PresetConstants.gestureLockActionKeyTurbo)
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 100)
        }
    }

    // MARK: - Helpers

    private func labeledSlider(value: Binding<Double>, range: ClosedRange<Double>, format: String, leftLabel: String, rightLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(leftLabel).font(.caption).foregroundColor(.secondary)
                Slider(value: value, in: range)
                Text(rightLabel).font(.caption).foregroundColor(.secondary)
            }
            Text(String(format: format, value.wrappedValue))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
    }

    // MARK: - Apply / Remove / Duplicate / Reset

    private func applyChanges() {
        guard let index = document.modules.firstIndex(where: { $0.id == module.id }) else { return }

        // Common fields for all module types
        // Only clear displayLabel if it was never set; preserve existing label when field is empty
        let newDisplayLabel = displayLabel.isEmpty ? nil : displayLabel
        let hadOriginalLabel = module.displayLabel != nil && !module.displayLabel!.isEmpty
        if newDisplayLabel == nil && hadOriginalLabel {
            document.modules[index].displayLabel = module.displayLabel
        } else {
            document.modules[index].displayLabel = newDisplayLabel
        }
        document.modules[index].scale = moduleScale

        // Accent color
        if let argb = Int(hex: accentColorHex) {
            document.modules[index].moduleAccentArgb = argb
        }
        switch module.type {
        case .analogStick, .dpad:
            switch selectedMode {
            case .stickMouse:
                document.modules[index].type = .analogStick
                document.modules[index].stickMouseSensitivity = stickMouseSensitivity
                document.modules[index].dpadVariant = "cross"
            case .stickKeys:
                document.modules[index].type = .analogStick
                document.modules[index].stickMouseSensitivity = nil
                document.modules[index].dpadVariant = "cross"
            case .dpadCross:
                document.modules[index].type = .dpad
                document.modules[index].dpadVariant = "cross"
                document.modules[index].stickMouseSensitivity = nil
            case .dpadSplit:
                document.modules[index].type = .dpad
                document.modules[index].dpadVariant = "split"
                document.modules[index].stickMouseSensitivity = nil
            }
            document.modules[index].stickUpKey = stickUpKey
            document.modules[index].stickLeftKey = stickLeftKey
            document.modules[index].stickDownKey = stickDownKey
            document.modules[index].stickRightKey = stickRightKey
            document.modules[index].stickCenterKey = stickCenterKey.isEmpty ? nil : stickCenterKey
            document.modules[index].dpadCrossArmDecoration = crossArmDecoration
            document.modules[index].dpadSplitGapRatio = dpadSplitGapRatio
            document.modules[index].dpadSplitOuterReachRatio = dpadSplitOuterReachRatio

        case .button, .shoulder, .trigger:
            document.modules[index].derivedKey = derivedKey.isEmpty ? nil : derivedKey
            document.modules[index].hidKey = hidKey == 0 ? nil : hidKey
            document.modules[index].mappedKeyLabelVisible = mappedKeyLabelVisible
            document.modules[index].turboEnabled = turboEnabled
            document.modules[index].turboIntervalMs = turboIntervalMs
            document.modules[index].turboInitialDelayMs = turboInitialDelayMs
            if module.type == .button {
                document.modules[index].buttonCornerRadiusNorm = buttonCornerRadius
                document.modules[index].buttonWidthRatio = buttonWidthRatio
                document.modules[index].buttonHeightRatio = buttonHeightRatio
                document.modules[index].buttonRotationDeg = buttonRotationDeg
            }
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

        case .touchpad:
            document.modules[index].widthNorm = widthNorm
            document.modules[index].heightNorm = heightNorm
            if hasTouchpad {
                document.layout.touchpadMouseButtonScale = touchpadMouseButtonScale
            }

        case .scrollStrip:
            document.modules[index].widthNorm = widthNorm
            document.modules[index].heightNorm = heightNorm
            document.modules[index].scrollStripSensitivity = scrollStripSensitivity
            document.modules[index].scrollStripInvertY = scrollStripInvertY

        case .mouseButton:
            if hasTouchpad {
                document.layout.touchpadMouseButtonScale = touchpadMouseButtonScale
            }
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
        }
    }

    private func removeModule() {
        guard let index = document.modules.firstIndex(where: { $0.id == module.id }) else { return }
        document.modules.remove(at: index)
        isPresented = false
    }

    private func duplicateModule() {
        guard let original = document.modules.first(where: { $0.id == module.id }) else { return }
        var copy = original
        copy.id = "\(module.type.rawValue)_dup_\(UUID().uuidString.prefix(6))"
        // Offset position slightly
        copy.anchorX = min(copy.anchorX + 0.05, 0.95)
        copy.anchorY = min(copy.anchorY + 0.05, 0.95)
        document.modules.append(copy)
        isPresented = false
    }

    private func resetToDefaults() {
        displayLabel = ""
        derivedKey = ""
        hidKey = 0
        dpadVariant = "cross"
        stickUpKey = "W"
        stickLeftKey = "A"
        stickDownKey = "S"
        stickRightKey = "D"
        stickCenterKey = ""
        stickMouseSensitivity = 1.0
        scrollStripSensitivity = 1.0
        scrollStripInvertY = false
        turboEnabled = false
        turboIntervalMs = 80
        turboInitialDelayMs = 400
        gestureLockEnabled = false
        gestureLockUpLeft = "none"
        gestureLockUpRight = "none"
        gestureLockDownLeft = "none"
        gestureLockDownRight = "none"
        buttonCornerRadius = 1.0
        buttonWidthRatio = 1.0
        buttonHeightRatio = 1.0
        buttonRotationDeg = 0
        mappedKeyLabelVisible = true
        accentColorHex = ""
        moduleScale = 1.0
        widthNorm = module.type == .touchpad ? 0.28 : (module.type == .scrollStrip ? 0.10 : 0.35)
        heightNorm = module.type == .touchpad ? 0.28 : (module.type == .scrollStrip ? 0.36 : 0.25)
        crossArmDecoration = "none"
        dpadSplitGapRatio = 0.08
        dpadSplitOuterReachRatio = 0.5
    }
}
