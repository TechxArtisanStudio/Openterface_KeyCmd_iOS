import SwiftUI

/// Agent mode — real LLM-backed planner + executor.
struct AgentView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @StateObject private var macroManager: MacroManager
    @StateObject private var session: AgentSession

    @State private var promptDraft: String = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var inputFocused: Bool

    @ObservedObject private var aiSettings = AISettings.shared
    private let credentialManager = CredentialManager.shared

    init(keyboardManager: KeyboardManager) {
        self.keyboardManager = keyboardManager
        let macroManager = MacroManager(keyboardManager: keyboardManager)
        _macroManager = StateObject(wrappedValue: macroManager)
        _session = StateObject(wrappedValue: AgentSession(keyboardManager: keyboardManager, macroManager: macroManager))
    }

    private var isConfigured: Bool { aiSettings.isConfigured() }

    var body: some View {
        VStack(spacing: 0) {
            sessionBar
            if !isConfigured {
                gateOverlay
            } else if session.messages.isEmpty {
                emptyState
            } else {
                transcript
            }
            inputBar
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .padding(.bottom, keyboardHeight)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { onKeyboardFrameChange($0) }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in keyboardHeight = 0 }
        .onTapGesture {
            inputFocused = false
        }
    }

    private func onKeyboardFrameChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // Use screen height minus keyboard origin to get the full keyboard height
        // including any accessory views (predictive text bar, etc.)
        let screenHeight = UIScreen.main.bounds.height
        keyboardHeight = screenHeight - frame.origin.y
    }

    // MARK: - Session Bar

    private var sessionBar: some View {
        HStack(spacing: 8) {
            let activeProfile = credentialManager.getActiveProfile()

            if let profile = activeProfile {
                // Profile selected: show terminal icon and profile name
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("Target: \(profile.displayLabel)")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            } else {
                // No profile: show OS name
                Image(aiSettings.targetOS.imageName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.gray)

                Text("Target: \(aiSettings.targetOS.displayName)")
                    .font(.caption)
                    .foregroundColor(.primary)
            }

            Spacer()

            Text(isConfigured ? "AGENT READY" : "NOT CONFIGURED")
                .font(.caption2.weight(.bold))
                .foregroundColor(isConfigured ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isConfigured ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)
            Text("Describe a workflow")
                .font(.headline)
            Text("Type what you want done. The agent plans it, asks for approval, then runs it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(session.messages) { msg in
                        messageRow(msg).id(msg.id)
                    }
                    if session.isThinking {
                        thinkingRow.id("thinking")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: session.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: AgentMessage) -> some View {
        switch msg.type {
        case .user:
            userBubble(msg.text ?? "")
        case .assistant:
            assistantBubble(msg.text ?? "")
        case .plan:
            planCard(msg.planSteps)
        case .actBar:
            actBar
        case .executionCli:
            cliCard(msg.terminalLines)
        case .executionMacro:
            macroCard(
                steps: msg.macroSteps,
                progress: msg.macroProgress,
                currentStep: msg.macroCurrentStep,
                chip: msg.macroStatusChip
            )
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Thinking\u{2026}")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Bubbles

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.18))
                .foregroundColor(.primary)
                .cornerRadius(14)
        }
        .padding(.horizontal, 12)
    }

    private func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(.accentColor)
                .padding(.top, 4)
            Text(text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemFill))
                .foregroundColor(.primary)
                .cornerRadius(14)
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Plan Card

    private func planCard(_ steps: [AgentPlanStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLAN")
                .font(.caption.weight(.bold))
                .foregroundColor(.accentColor)
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(step.index)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.accentColor))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: step.kind))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(step.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                        }
                        if let sub = step.subtitle {
                            Text(sub)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func icon(for kind: AgentPlanStep.Kind) -> String {
        switch kind {
        case .terminal: return "terminal"
        case .macro: return "list.bullet.rectangle"
        case .hid: return "keyboard"
        }
    }

    // MARK: - Act Bar

    private var actBar: some View {
        HStack(spacing: 8) {
            Button {
                session.approveAndRun()
            } label: {
                Text("Approve & Run")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            Button(role: .destructive) {
                session.cancel()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - CLI Card

    private func cliCard(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.caption)
                Text(NSLocalizedString("terminal_title", comment: "Terminal view title")).font(.caption.weight(.semibold))
            }
            .foregroundColor(.secondary)
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }

    // MARK: - Macro Card

    private func macroCard(steps: [String], progress: Int, currentStep: Int, chip: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle").font(.caption)
                    Text("Macro").font(.caption.weight(.semibold))
                }
                .foregroundColor(.secondary)
                Spacer()
                if let chip = chip {
                    Text(chip)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                }
            }
            ProgressView(value: Double(progress), total: 100)
                .tint(.accentColor)
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, label in
                HStack(spacing: 8) {
                    Image(systemName: idx <= currentStep ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(idx <= currentStep ? .green : .secondary)
                        .font(.caption)
                    Text(label)
                        .font(.caption)
                        .foregroundColor(idx <= currentStep ? .primary : .secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Describe a workflow\u{2026}", text: $promptDraft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor.tertiarySystemFill))
                )
                .disabled(!isConfigured || session.isThinking || session.isExecuting)
                .onSubmit(submitDraft)

            Button(action: submitDraft) {
                Image(systemName: session.isThinking ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSubmit ? .accentColor : .secondary)
            }
            .disabled(!canSubmit)
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var canSubmit: Bool {
        isConfigured && !session.isThinking && !session.isExecuting && !promptDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitDraft() {
        guard canSubmit else { return }
        let text = promptDraft
        promptDraft = ""
        inputFocused = false
        session.submit(prompt: text)
    }

    // MARK: - Gate Overlay

    private var gateOverlay: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                        .padding(.top, 40)
                    Text(NSLocalizedString("agent_title", comment: "Agent view title"))
                        .font(.title2.weight(.bold))
                    Text("Agent plans multi-step desktop workflows and runs them on the connected device. Configure an AI provider to unlock it.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    } label: {
                        Text("Configure AI provider")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Target Settings Sheet

struct TargetSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedProfileId: String?
    @ObservedObject private var aiSettings = AISettings.shared
    @State private var profiles: [CredentialProfile] = []

    private let credentialManager = CredentialManager.shared

    var body: some View {
        NavigationView {
            List {
                // Section 1: Target OS
                Section("Target OS") {
                    ForEach(TargetOS.allCases, id: \.self) { os in
                        Button(action: {
                            // Selecting OS directly clears profile selection
                            aiSettings.targetOS = os
                            selectedProfileId = nil
                            credentialManager.clearActiveProfile()
                        }) {
                            HStack {
                                Image(os.imageName)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)
                                    .foregroundColor(aiSettings.targetOS == os && selectedProfileId == nil ? .accentColor : .secondary)

                                Text(os.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 8)

                                Spacer()
                                if aiSettings.targetOS == os && selectedProfileId == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }

                // Section 2: Terminal Profile
                Section("Terminal Profile") {
                    if profiles.isEmpty {
                        Text("No profiles saved yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(profiles) { profile in
                            Button(action: {
                                // Selecting profile sets OS from profile
                                selectedProfileId = profile.id
                                credentialManager.setActiveProfileId(profile.id)
                                if let profileOS = TargetOS(rawValue: profile.targetOs) {
                                    aiSettings.targetOS = profileOS
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayLabel)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)
                                        Text(profile.shortDescription)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedProfileId == profile.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Target Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                profiles = credentialManager.getAllProfiles()
            }
        }
    }
}
