//
//  GeneralSettingsView.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct GeneralSettingsView: View {
    @ObservedObject private var touchpadSettings = TouchpadSettings.shared
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    @AppStorage("clipboardMonitoringEnabled") private var clipboardMonitoringEnabled = true
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

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
                Label("Target OS", image: aiSettings.targetOS.imageName)
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
            #if os(iOS)
            // Device diagnostics
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Device:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hapticManager.deviceModelName)
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                HStack {
                    Text("Taptic Engine:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hapticManager.hasTapticEngine ? "✅ Available" : "❌ Not Available")
                        .font(.caption)
                        .foregroundColor(hapticManager.hasTapticEngine ? .green : .red)
                }

                HStack {
                    Text("Low Power Mode:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(hapticManager.isLowPowerModeEnabled ? "⚠️ ON (reduces haptics)" : "✅ OFF")
                        .font(.caption)
                        .foregroundColor(hapticManager.isLowPowerModeEnabled ? .orange : .green)
                }
            }

            // Warning if device doesn't have Taptic Engine
            if !hapticManager.hasTapticEngine {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This device doesn't have a Taptic Engine")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text("Haptic feedback is not available on this device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Warning if haptics might not work (vibration disabled)
            if hapticManager.hasTapticEngine && hapticManager.isHapticEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can't feel haptic feedback?")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("Check that Vibration is enabled:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text("1. Open Settings app\n2. Go to Accessibility\n3. Tap Touch\n4. Enable Vibration")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: {
                            // Try to open system Settings main page (best we can do — iOS doesn't
                            // allow deep-linking to Accessibility → Touch → Vibration from third-party apps)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings App")
                                    .fontWeight(.semibold)
                            }
                            .font(.caption)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            HStack {
                Text("Enable Haptic Feedback")
                Spacer()
                Toggle("", isOn: $hapticManager.isHapticEnabled)
            }
            Text("Provides vibration feedback for all interactions including button presses, key presses, mouse clicks, and touch gestures")
                .font(.caption)
                .foregroundColor(.secondary)

            if hapticManager.isHapticEnabled && hapticManager.hasTapticEngine {
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
            #else
            // Non-iOS platforms
            HStack {
                Text("Enable Haptic Feedback")
                Spacer()
                Toggle("", isOn: $hapticManager.isHapticEnabled)
            }
            Text("Provides vibration feedback for all interactions")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
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

        // MARK: - Language
        Section(header: Text("Language")) {
            Picker("App Language", selection: $languageManager.selectedLanguageId) {
                ForEach(LanguageManager.supported) { lang in
                    Text(lang.displayName).tag(lang.id)
                }
            }
            Text("The selected language takes effect immediately.")
                .font(.caption)
                .foregroundColor(.secondary)
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
