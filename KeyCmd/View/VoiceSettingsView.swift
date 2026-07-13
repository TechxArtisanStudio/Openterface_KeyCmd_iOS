import SwiftUI

/// Voice input settings: engine/model config and AI prompt.
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "voice"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Settings", selection: $selectedTab) {
                    Text("Voice").tag("voice")
                    Text("AI Prompt").tag("ai_prompt")
                }
                .pickerStyle(.segmented)
                .padding()

                Form {
                    if selectedTab == "voice" {
                        WhisperSettingsView()
                    } else {
                        RoleManagementSection()
                        PromptManagementSection()
                    }
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
