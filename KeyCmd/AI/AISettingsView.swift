//
//  AISettingsView.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

// MARK: - Main AI Settings View
struct AISettingsView: View {
    @ObservedObject private var aiSettings = AISettings.shared
    
    @Binding var tempAPIKey: String
    @Binding var showAPIKeyField: Bool
    @Binding var isTestingAPI: Bool
    @Binding var testResult: String?
    @Binding var testError: String?
    
    var body: some View {
        Group {
            APIConfigurationSection()
            
            if aiSettings.isEnabled {
                AIProviderSettingSection()
                APIKeyManagementSection(tempAPIKey: $tempAPIKey, showAPIKeyField: $showAPIKeyField)
            }
        }
    }
}

// MARK: - API Configuration Section
struct APIConfigurationSection: View {
    @ObservedObject private var aiSettings = AISettings.shared

    var body: some View {
        Section(header: Text("API Configuration")) {
            HStack {
                Text("Enable AI Refinement")
                Spacer()
                Toggle("", isOn: $aiSettings.isEnabled)
            }
            Text("After voice input, AI will check intention and refine text")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
// MARK: - AI Provider Setting Section
struct AIProviderSettingSection: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var localModel = LocalModelManager.shared
    @State private var showAddAlert = false
    @State private var showDeleteAlert = false
    @State private var isTestingAPI = false
    @State private var testResult: String?
    @State private var testError: String?

    private func confirmAddProvider() {
        let newProvider = aiSettings.addProvider()
        aiSettings.selectProvider(newProvider.id)
        showAddAlert = false
    }

    private func confirmDeleteProvider() {
        if let selectedProvider = aiSettings.selectedProvider {
            aiSettings.deleteProvider(selectedProvider.id)
        }
        showDeleteAlert = false
    }

    var body: some View {
        Section(header: Text("AI Provider Setting")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select or manage AI providers")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !aiSettings.providers.isEmpty {
                    Picker("Active Provider", selection: Binding(
                        get: { aiSettings.selectedProviderId },
                        set: { newId in
                            if let provider = aiSettings.providers.first(where: { $0.id.uuidString == newId }) {
                                aiSettings.selectProvider(provider.id)
                                LocalModelManager.shared.selectModel(for: provider.apiBaseURL)
                            }
                        }
                    )) {
                        ForEach(aiSettings.providers, id: \.id) { provider in
                            HStack {
                                Text(provider.name)
                                Text(aiSettings.hasAPIKey(for: provider) ? "✓" : "")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            .tag(provider.id.uuidString)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                    .disabled(localModel.isDownloading)

                    // Show validation warning if selected provider is invalid
                    if let validationError = aiSettings.getValidationError() {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(validationError)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                Label("Add New Provider", systemImage: "plus.circle")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                    .onTapGesture {
                        showAddAlert = true
                    }
                    .disabled(localModel.isDownloading)
                    .alert("Add New Provider?", isPresented: $showAddAlert) {
                        Button("Add Provider") {
                            confirmAddProvider()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will create a new AI provider configuration.")
                    }

                if let selectedProvider = aiSettings.selectedProvider {
                    // Show download UI for local providers
                    if selectedProvider.apiBaseURL.hasPrefix("local://") {
                        LocalModelDownloadView()
                    }

                    // Always show editable provider fields
                    ProviderEditFields(provider: selectedProvider)

                    if aiSettings.providers.count > 1 {
                        Label("Delete This Provider", systemImage: "trash")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                            .onTapGesture {
                                showDeleteAlert = true
                            }
                            .disabled(localModel.isDownloading)
                            .alert("Delete This Provider?", isPresented: $showDeleteAlert) {
                                Button("Delete Provider", role: .destructive) {
                                    confirmDeleteProvider()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This will permanently remove the selected provider.")
                            }
                    }

                    TestingSection(
                        isTestingAPI: $isTestingAPI,
                        testResult: $testResult,
                        testError: $testError
                    )
                }
            }
        }
        .onAppear {
            if let selectedProvider = aiSettings.selectedProvider {
                LocalModelManager.shared.selectModel(for: selectedProvider.apiBaseURL)
            }
        }
    }
}

// MARK: - Local Model Download UI
struct LocalModelDownloadView: View {
    @ObservedObject private var localModel = LocalModelManager.shared
    @State private var showDownloadConfirmation = false
    @State private var showDeleteLocalModelConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local \(localModel.activeModel.displayName) Model")
                .font(.headline)

            Text("On-device AI model for simple offline requests. No API key needed.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Model source picker (only when not downloading)
            if case .notDownloaded = localModel.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Source")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Source", selection: Binding(
                        get: { localModel.modelSource },
                        set: { localModel.modelSource = $0 }
                    )) {
                        ForEach(LocalModelManager.ModelSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            switch localModel.state {
            case .notDownloaded:
                Button(action: { showDownloadConfirmation = true }) {
                    Label("Download from \(localModel.modelSource.displayName)", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .confirmationDialog(
                    "Download \(localModel.activeModel.displayName) Model?",
                    isPresented: $showDownloadConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Download (~\(localModel.activeModel.approxSizeMB)MB) from \(localModel.modelSource.displayName)") {
                        localModel.startDownload()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will download approximately \(localModel.activeModel.approxSizeMB)MB of model data from \(localModel.modelSource.displayName). Make sure you have enough storage and a stable internet connection.")
                }

            case .downloading(let progress):
                VStack(spacing: 8) {
                    HStack {
                        Text("Source: \(localModel.modelSource.displayName)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    ProgressView(value: progress) {
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)

                    HStack {
                        Text("Downloading model files (~\(localModel.activeModel.approxSizeMB)MB). This may take several minutes.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Cancel", role: .destructive) {
                            localModel.cancelDownload()
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)

            case .downloaded:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Model Ready")
                        .foregroundColor(.green)
                    Spacer()
                    Button(action: { showDeleteLocalModelConfirmation = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading model into memory…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .ready:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Model Loaded & Ready")
                        .foregroundColor(.green)
                    Spacer()
                    Button(action: { showDeleteLocalModelConfirmation = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Download Failed")
                            .foregroundColor(.red)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { localModel.startDownload() }) {
                        Label("Retry Download", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .confirmationDialog("Delete Local Model?",
            isPresented: $showDeleteLocalModelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                localModel.deleteModel()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the downloaded model file and free up approximately \(localModel.activeModel.approxSizeMB)MB of storage.")
        }
    }
}

// MARK: - Provider Edit Fields
struct ProviderEditFields: View {
    @ObservedObject private var aiSettings = AISettings.shared
    let provider: AIProvider

    private var isURLValid: Bool {
        !provider.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isModelValid: Bool {
        !provider.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if let selectedProvider = aiSettings.selectedProvider {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit Provider: \(selectedProvider.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Provider Name", text: Binding(
                    get: { selectedProvider.name },
                    set: { newName in
                        var updated = selectedProvider
                        updated.name = newName
                        aiSettings.updateProvider(updated)
                    }
                ))
                .textInputAutocapitalization(.words)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))

                TextField("API Base URL", text: Binding(
                    get: { selectedProvider.apiBaseURL },
                    set: { newURL in
                        var updated = selectedProvider
                        updated.apiBaseURL = newURL
                        aiSettings.updateProvider(updated)
                    }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isURLValid ? Color.gray : Color.red, lineWidth: isURLValid ? 0.5 : 1.5)
                )
                if !isURLValid {
                    Text("API Base URL is required")
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                TextField("Model Name", text: Binding(
                    get: { selectedProvider.modelName },
                    set: { newModel in
                        var updated = selectedProvider
                        updated.modelName = newModel
                        aiSettings.updateProvider(updated)
                    }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isModelValid ? Color.gray : Color.red, lineWidth: isModelValid ? 0.5 : 1.5)
                )
                if !isModelValid {
                    Text("Model Name is required")
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                HStack {
                    Text("API Key Optional")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { selectedProvider.apiKeyOptional },
                        set: { newValue in
                            var updated = selectedProvider
                            updated.apiKeyOptional = newValue
                            aiSettings.updateProvider(updated)
                        }
                    ))
                }
                Text("Enable for local providers (Ollama, LM Studio, etc.)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - API Key Management Section
struct APIKeyManagementSection: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @Binding var tempAPIKey: String
    @Binding var showAPIKeyField: Bool
    
    var body: some View {
        Section(header: Text("API Key Management")) {
            if let selectedProvider = aiSettings.selectedProvider {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key for \(selectedProvider.name)")
                        Spacer()
                        Text(selectedProvider.hasAPIKey() ? "✓ Configured" : "✗ Not Configured")
                            .font(.caption)
                            .foregroundColor(selectedProvider.hasAPIKey() ? .green : .red)
                    }
                    
                    if showAPIKeyField {
                        SecureField("Enter API Key", text: $tempAPIKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                        
                        HStack(spacing: 8) {
                            Button("Save") {
                                if !tempAPIKey.isEmpty {
                                    selectedProvider.saveAPIKey(tempAPIKey)
                                    aiSettings.updateAPIKeyStatus()
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
            }
        }
    }
}

// MARK: - Role Management Section
struct RoleManagementSection: View {
    @ObservedObject private var aiSettings = AISettings.shared
    
    var body: some View {
        Section(header: Text("Role Management")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("System Prompt Role")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Role", selection: $aiSettings.selectedSystemPromptRole) {
                    ForEach(aiSettings.systemPromptRoles, id: \.id) { role in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.name)
                            Text(role.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .tag(role.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                .onChange(of: aiSettings.selectedSystemPromptRole) { roleId in
                    aiSettings.setSystemPromptRole(roleId)
                }
            }
            Text("Select a predefined role or create a custom prompt")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Full-Screen Prompt Viewer/Editor
struct PromptFullScreenView: View {
    let title: String
    let isEditable: Bool
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isEditable {
                    TextEditor(text: $prompt)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                } else {
                    ScrollView {
                        Text(prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isEditable {
                        Label("Read-only", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Prompt Management Section
struct PromptManagementSection: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @State private var showFullScreen = false

    private var isCustomRole: Bool {
        aiSettings.selectedSystemPromptRole == "custom"
    }

    private var promptTitle: String {
        aiSettings.systemPromptRoles
            .first(where: { $0.id == aiSettings.selectedSystemPromptRole })?.name
            ?? "System Prompt"
    }

    var body: some View {
        Section(header: Text("Prompt Management")) {
            if isCustomRole {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Custom System Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showFullScreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    TextEditor(text: $aiSettings.systemPrompt)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 0.5))
                        .font(.system(.body, design: .monospaced))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Current System Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showFullScreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        Text(aiSettings.systemPrompt)
                            .font(.caption)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(height: 150)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(4)
                }
            }
        }
        .sheet(isPresented: $showFullScreen) {
            PromptFullScreenView(
                title: promptTitle,
                isEditable: isCustomRole,
                prompt: $aiSettings.systemPrompt
            )
        }
    }
}

// MARK: - Testing Section
struct TestingSection: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @Binding var isTestingAPI: Bool
    @Binding var testResult: String?
    @Binding var testError: String?
    
    var body: some View {
        Section(header: Text("Testing")) {
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
    
    private func testAPIConfiguration() {
        isTestingAPI = true
        testResult = nil
        testError = nil

        // Check if this is a local provider
        if let provider = aiSettings.selectedProvider, provider.apiBaseURL.hasPrefix("local://") {
            // Guard: ensure model is downloaded; generate() will load it if needed
            guard LocalModelManager.shared.isModelDownloaded() else {
                isTestingAPI = false
                testResult = nil
                testError = "Local model not downloaded. Please download the model first."
                LogManager.shared.log("❌ Local model not downloaded for testing", category: "SettingsView", level: .error)
                return
            }

            // Test local model instead of HTTP API
            Task {
                do {
                    let testText = "Test message from iOS app"
                    let response = try await LocalModelManager.shared.generate(
                        system: "You are a helpful assistant.",
                        user: testText
                    )
                    await MainActor.run {
                        isTestingAPI = false
                        let modelInfo = provider.modelName
                        testResult = "Provider: \(provider.name)\nModel: \(modelInfo)\nResponse: \(response.prefix(100))..."
                        testError = nil
                        LogManager.shared.log("✅ Local model test successful", category: "SettingsView", level: .info)
                    }
                } catch {
                    await MainActor.run {
                        isTestingAPI = false
                        testResult = nil
                        testError = error.localizedDescription
                        LogManager.shared.log("❌ Local model test failed: \(error.localizedDescription)", category: "SettingsView", level: .error)
                    }
                }
            }
            return
        }

        // HTTP API test for remote providers
        let testText = "Test message from iOS app"

        AITextRefinementManager.shared.refineText(input: testText) { result in
            DispatchQueue.main.async {
                isTestingAPI = false
                switch result {
                case .success(let refined):
                    let modelInfo = aiSettings.selectedProvider?.modelName ?? "Unknown"
                    testResult = "Provider: \(aiSettings.selectedProvider?.name ?? "N/A")\nModel: \(modelInfo)\nRefined: \(refined.prefix(100))..."
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

struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            AISettingsView(
                tempAPIKey: .constant(""),
                showAPIKeyField: .constant(false),
                isTestingAPI: .constant(false),
                testResult: .constant(nil),
                testError: .constant(nil)
            )
        }
    }
}
