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

    var body: some View {
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
