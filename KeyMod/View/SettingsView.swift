//
//  SettingsView.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var touchpadSettings = TouchpadSettings.shared
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    @ObservedObject private var aiSettings = AISettings.shared
    @AppStorage("clipboardMonitoringEnabled") private var clipboardMonitoringEnabled = true
    @Environment(\.presentationMode) var presentationMode
    
    @State private var tempAPIKey = ""
    @State private var showAPIKeyField = false
    @State private var isTestingAPI = false
    @State private var testResult: String?
    @State private var testError: String?
    
    var body: some View {
        NavigationView {
            Form {
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
                
                Section(header: Text("AI Text Refinement")) {
                    HStack {
                        Text("Enable AI Refinement")
                        Spacer()
                        Toggle("", isOn: $aiSettings.isEnabled)
                    }
                    Text("After voice input, AI will check intention and refine text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if aiSettings.isEnabled {
                        // API Key
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("API Key")
                                Spacer()
                                Text(aiSettings.apiKeyStatus)
                                    .font(.caption)
                                    .foregroundColor(aiSettings.apiKeyStatus.contains("✓") ? .green : .red)
                            }
                            
                            if showAPIKeyField {
                                SecureField("Enter OpenAI API Key", text: $tempAPIKey)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .padding(8)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                                
                                HStack(spacing: 8) {
                                    Button("Save") {
                                        if !tempAPIKey.isEmpty {
                                            aiSettings.saveAPIKey(tempAPIKey)
                                            tempAPIKey = ""
                                            showAPIKeyField = false
                                        }
                                    }
                                    .foregroundColor(.blue)
                                    
                                    Button("Cancel") {
                                        tempAPIKey = ""
                                        showAPIKeyField = false
                                    }
                                    .foregroundColor(.gray)
                                }
                            } else {
                                Button("Update API Key") {
                                    showAPIKeyField = true
                                    tempAPIKey = ""
                                }
                                .foregroundColor(.blue)
                            }
                        }
                        
                        // API Base URL
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Base URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("https://api.openai.com/v1", text: $aiSettings.apiBaseURL)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(8)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                        }
                        
                        // Model Name
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("gpt-3.5-turbo", text: $aiSettings.modelName)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(8)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                        }
                        
                        // System Prompt
                        VStack(alignment: .leading, spacing: 4) {
                            Text("System Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $aiSettings.systemPrompt)
                                .frame(height: 100)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        // Test API Button
                        Button(action: testAPIConfiguration) {
                            if isTestingAPI {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8, anchor: .center)
                                    Text("Testing…")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            } else {
                                Label("Test API Connection", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .disabled(isTestingAPI)
                        
                        // Test Result Messages
                        if let result = testResult {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("✓ Connection Successful")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if let error = testError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("✗ Connection Failed")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
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
            .navigationTitle("Settings")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    // MARK: - Test API Configuration
    
    private func testAPIConfiguration() {
        isTestingAPI = true
        testResult = nil
        testError = nil
        
        let testText = "Test message from iOS app"
        
        AITextRefinementManager.shared.refineText(input: testText) { result in
            DispatchQueue.main.async {
                isTestingAPI = false
                switch result {
                case .success(let refined):
                    testResult = "Model: \(aiSettings.modelName)\nRefined: \(refined.prefix(100))..."
                    testError = nil
                    LogManager.shared.log("✅ API test successful", category: "SettingsView", level: .info)
                case .failure(let error):
                    testResult = nil
                    testError = error.localizedDescription
                    LogManager.shared.log("❌ API test failed: \(error.localizedDescription)", category: "SettingsView", level: .error)
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
