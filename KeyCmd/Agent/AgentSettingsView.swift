import SwiftUI

/// Agent-specific settings: AI provider selection and agent planner prompt.
struct AgentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aiSettings = AISettings.shared

    @State private var terminalPromptDraft: String = ""
    @State private var hidPromptDraft: String = ""
    @State private var selectedPromptMode: PromptMode = .terminal
    @State private var hasUnsavedChanges = false

    enum PromptMode: String, CaseIterable, Identifiable {
        case terminal = "Terminal (SSH)"
        case hid = "HID (BLE Keyboard)"
        var id: String { rawValue }
    }

    private let terminalPromptKey = "AgentSettings.agent_planner_terminalPrompt"
    private let hidPromptKey = "AgentSettings.agent_planner_hidPrompt"
    private let terminalPromptId = "agent_planner_terminal"
    private let hidPromptId = "agent_planner_hid"

    var body: some View {
        NavigationView {
            Form {
                providerSection
                limitsSection
                promptSection
            }
            .navigationTitle("Agent Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePrompts()
                        dismiss()
                    }
                    .disabled(!hasUnsavedChanges)
                }
            }
            .onAppear {
                terminalPromptDraft = loadPrompt(key: terminalPromptKey, roleId: terminalPromptId)
                hidPromptDraft = loadPrompt(key: hidPromptKey, roleId: hidPromptId)
            }
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        Section(header: Text("AI Provider")) {
            if aiSettings.providers.isEmpty {
                Text("No providers configured")
                    .foregroundColor(.secondary)
            } else {
                ForEach(aiSettings.providers) { provider in
                    Button {
                        aiSettings.selectedProviderId = provider.id.uuidString
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(provider.modelName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if provider.id.uuidString == aiSettings.selectedProviderId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Limits Section

    private var limitsSection: some View {
        Section {
            Stepper(value: $aiSettings.agentMaxSteps, in: 3...30) {
                HStack {
                    Text("Max steps per plan")
                    Spacer()
                    Text("\(aiSettings.agentMaxSteps)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            Stepper(value: $aiSettings.agentMaxRetries, in: 0...5) {
                HStack {
                    Text("Max retries on failure")
                    Spacer()
                    Text("\(aiSettings.agentMaxRetries)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Execution Limits")
        } footer: {
            Text("Max steps caps how many commands the planner can include in one plan. Max retries sets how many times the agent will re-plan with alternative commands if the first attempt fails.")
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        Section {
            Picker("Mode", selection: $selectedPromptMode) {
                ForEach(PromptMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: bindingForSelectedMode())
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .onChange(of: terminalPromptDraft) { _ in
                    hasUnsavedChanges = true
                }
                .onChange(of: hidPromptDraft) { _ in
                    hasUnsavedChanges = true
                }
        } header: {
            Text("System Prompts")
        } footer: {
            Text("Terminal prompt is used when SSH is connected. HID prompt is used when controlling via BLE keyboard.")
        }
    }

    // MARK: - Helpers

    private func bindingForSelectedMode() -> Binding<String> {
        switch selectedPromptMode {
        case .terminal:
            return $terminalPromptDraft
        case .hid:
            return $hidPromptDraft
        }
    }

    private func loadPrompt(key: String, roleId: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        return aiSettings.getSystemPromptRole(id: roleId)?.prompt ?? ""
    }

    private func savePrompts() {
        UserDefaults.standard.set(terminalPromptDraft, forKey: terminalPromptKey)
        UserDefaults.standard.set(hidPromptDraft, forKey: hidPromptKey)
        hasUnsavedChanges = false
    }
}
