//
//  GeneralSettingsView.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var touchpadSettings = TouchpadSettings.shared
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    @AppStorage("clipboardMonitoringEnabled") private var clipboardMonitoringEnabled = true
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        // MARK: - Theme (matches Android ThemeManager)
        Section(header: Text("Appearance")) {
            Picker("Color Family", selection: $themeManager.colorFamily) {
                ForEach(ThemeManager.ColorFamily.allCases) { family in
                    HStack {
                        Circle()
                            .fill(family.accentColor)
                            .frame(width: 12, height: 12)
                        Text(family.displayName)
                    }
                    .tag(family)
                }
            }
            Toggle("Follow System Appearance", isOn: $themeManager.followSystem)
                .onChange(of: themeManager.followSystem) { _ in
                    themeManager.updateAppearance()
                }
            if !themeManager.followSystem {
                Picker("Theme Mode", selection: $themeManager.modeOverride) {
                    ForEach(ThemeManager.ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: themeManager.modeOverride) { _ in
                    themeManager.updateAppearance()
                }
            }
            // Preview swatches
            HStack(spacing: 8) {
                ForEach(ThemeManager.ColorFamily.allCases) { family in
                    Circle()
                        .fill(family.accentColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.2), lineWidth: family == themeManager.colorFamily ? 2 : 0)
                        )
                        .onTapGesture {
                            withAnimation { themeManager.colorFamily = family }
                        }
                }
            }
            .padding(.vertical, 4)
        }

        Section(header: Text("Target System")) {
            HStack {
                Label("Target OS", systemImage: aiSettings.targetOS.systemImage)
                Spacer()
            }
            Picker("Target OS", selection: $aiSettings.targetOS) {
                ForEach(TargetOS.allCases, id: \.self) { os in
                    Text(os.displayName).tag(os)
                }
            }
            .pickerStyle(.segmented)
            Text("Sets the operating system of the target machine. The AI Command Assistant will use OS-specific shortcuts and key tokens.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Section(header: Text("Touchpad Settings")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tap Duration Threshold")
                    Spacer()
                    Text("\(touchpadSettings.tapDurationThreshold, specifier: "%.2f")s")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $touchpadSettings.tapDurationThreshold,
                    in: 0.1...1.0,
                    step: 0.05
                )
                Text("Maximum time allowed for a tap (shorter = more responsive, longer = more forgiving)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Movement Threshold")
                    Spacer()
                    Text("\(touchpadSettings.tapMovementThreshold, specifier: "%.0f") pts")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $touchpadSettings.tapMovementThreshold,
                    in: 5...30,
                    step: 1
                )
                Text("Maximum finger movement allowed during a tap")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Delay Before Click")
                    Spacer()
                    Text("\(touchpadSettings.tapDelayThreshold, specifier: "%.2f")s")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $touchpadSettings.tapDelayThreshold,
                    in: 0.05...0.3,
                    step: 0.01
                )
                Text("Delay to distinguish between tap and drag (shorter = faster response)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            // Scroll Sensitivity (synced from Android)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scroll Sensitivity")
                    Spacer()
                    Text("\(touchpadSettings.scrollSensitivity, specifier: "%.1f")x")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: $touchpadSettings.scrollSensitivity,
                    in: 0.2...2.0,
                    step: 0.1
                )
                Text("Adjusts scroll sensitivity for two-finger scrolling (lower = slower, higher = faster)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }

        Section(header: Text("Clipboard Monitoring")) {
            HStack {
                Text("Enable Clipboard Monitoring")
                Spacer()
                Toggle("", isOn: $clipboardMonitoringEnabled)
            }
            Text("Detects new clipboard content and asks if you want to send it to the target device")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        Section(header: Text("BLE Key Delay")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inter-key Delay")
                    Spacer()
                    Text("\(aiSettings.bleKeyDelayMs) ms")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(aiSettings.bleKeyDelayMs) },
                        set: { aiSettings.bleKeyDelayMs = Int($0) }
                    ),
                    in: 5...50,
                    step: 1
                )
                Text("Delay between each BLE HID key report. Lower values = faster typing but may miss keys on slow targets. Default: 10 ms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }

        Section(header: Text("Haptic Feedback")) {
            HStack {
                Text("Enable Haptic Feedback")
                Spacer()
                Toggle("", isOn: $hapticManager.isHapticEnabled)
            }
            Text("Provides vibration feedback for all interactions including button presses, key presses, mouse clicks, and touch gestures")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if hapticManager.isHapticEnabled {
                Button("Test Light Feedback") {
                    hapticManager.triggerButtonPress()
                }
                .foregroundColor(.blue)
                
                Button("Test Medium Feedback") {
                    hapticManager.triggerMediumFeedback()
                }
                .foregroundColor(.blue)
                
                Button("Test Strong Feedback") {
                    hapticManager.triggerStrongFeedback()
                }
                .foregroundColor(.blue)
            }
        }
        
        Section {
            Button("Reset to Defaults") {
                touchpadSettings.resetToDefaults()
            }
            .foregroundColor(.red)
        }
        
        Section(header: Text("Current Values")) {
            HStack {
                Text("Tap Duration:")
                Spacer()
                Text("\(touchpadSettings.tapDurationThreshold, specifier: "%.2f")s")
            }
            HStack {
                Text("Movement Threshold:")
                Spacer()
                Text("\(touchpadSettings.tapMovementThreshold, specifier: "%.0f") points")
            }
            HStack {
                Text("Click Delay:")
                Spacer()
                Text("\(touchpadSettings.tapDelayThreshold, specifier: "%.2f")s")
            }
            HStack {
                Text("Scroll Sensitivity:")
                Spacer()
                Text("\(touchpadSettings.scrollSensitivity, specifier: "%.1f")x")
            }
        }
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            GeneralSettingsView()
        }
    }
}
