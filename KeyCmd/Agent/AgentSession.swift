import Foundation

/// Orchestrates the real Agent flow: user prompt → LLM plan → approve → execute → summarize.
final class AgentSession: ObservableObject {
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var isThinking: Bool = false
    @Published private(set) var isExecuting: Bool = false
    @Published private(set) var isWaitingForApprove: Bool = false
    @Published private(set) var hasContent: Bool = false
    @Published private(set) var receivedTokens: Int = 0

    private let keyboardManager: KeyboardManager
    private var macroManager: MacroManager
    private let bleManager: BLEManager
    private var executor: AgentExecutor?
    private var currentSteps: [AgentLLMStep]?
    private var currentPrompt: String?

    /// Collected outputs from terminal steps: (command, output)
    private var collectedOutputs: [(command: String, output: String)] = []

    /// How many retry rounds have been attempted for the current execution.
    private var retryCount: Int = 0

    /// True when no terminal profile is active — terminal steps will be typed via BLE HID.
    var isHIDMode: Bool { CredentialManager.shared.getActiveProfile() == nil }

    init(keyboardManager: KeyboardManager, macroManager: MacroManager, bleManager: BLEManager) {
        self.keyboardManager = keyboardManager
        self.macroManager = macroManager
        self.bleManager = bleManager
    }

    // MARK: - Submit

    func submit(prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Reset state for a fresh submission
        isThinking = true
        isWaitingForApprove = false
        isExecuting = false
        hasContent = true
        currentPrompt = prompt
        receivedTokens = 0

        messages.append(.user(prompt))

        let macroCtx = macroManager.macroContextSection()
        let terminalModeCtx = buildTerminalModeContext()
        AgentLLMService.shared.plan(prompt: prompt, macroContext: macroCtx, terminalModeContext: terminalModeCtx, onToken: { [weak self] count in
            self?.receivedTokens = count
        }) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePlanResult(result)
            }
        }
    }

    /// Build the terminal mode context string injected into the planner prompt.
    private func buildTerminalModeContext() -> String {
        let targetOS = AISettings.shared.targetOS
        let credManager = CredentialManager.shared
        let maxSteps = AISettings.shared.agentMaxSteps

        if let profile = credManager.getActiveProfile() {
            return """
            **Execution mode: Terminal (SSH)**
            Target: \(profile.username)@\(profile.host):\(profile.port)
            OS: \(targetOS.displayName)
            Max steps: \(maxSteps) (do NOT exceed this; use the fewest steps possible)

            Terminal commands are executed via SSH on the remote device. Output (stdout + stderr) is captured and will be summarized for the user. Use `terminal` steps freely — they run directly.
            IMPORTANT: Use only the correct commands for \(targetOS.displayName). If a command fails, you will get a chance to retry with an alternative — do NOT pre-plan fallback commands.
            """
        } else {
            return """
            **Execution mode: HID (BLE keyboard)**
            Target OS: \(targetOS.displayName)
            Max steps: \(maxSteps) (do NOT exceed this; use the fewest steps possible)

            No terminal profile is configured. Terminal commands will be **typed into the active window** on the target device via BLE keyboard — nothing is captured.
            You MUST include an `hid` step first to open a terminal app, with a delay to let it launch:
            - macOS: `<CMD><SPACE></CMD><DELAY1S><CMD>a</CMD><BACK><DELAY1S>terminal<ENTER><DELAY3S>` (open Spotlight, release Cmd, clear old text, type "terminal", Enter)
            - Linux: `<CTRL><ALT>t<DELAY3S>` (typical shortcut)
            - Windows: `<WIN>r<DELAY1S>cmd<ENTER><DELAY4S>` (Run dialog, delay, type "cmd", Enter)
            IMPORTANT: always include the closing modifier tag (e.g. `</CMD>`) after a combo before typing plain text, otherwise text is sent as keyboard shortcuts.
            Then use `terminal` steps for the commands (each is auto-suffixed with `<ENTER>`). Since no output is captured, avoid commands that depend on reading previous output.
            """
        }
    }

    private func handlePlanResult(_ result: Result<AgentLLMPlan, AgentLLMError>) {
        switch result {
        case .success(let plan):
            let maxSteps = AISettings.shared.agentMaxSteps
            let truncated = plan.steps.count > maxSteps
            let clampedSteps = Array(plan.steps.prefix(maxSteps))
            let clampedPlan = AgentLLMPlan(intro: plan.intro, steps: clampedSteps)

            let effective = isHIDMode ? sanitizeHIDPlan(clampedPlan) : clampedPlan
            messages.append(.assistant(effective.intro))
            if truncated {
                messages.append(.assistant("⚠️ Plan had \(plan.steps.count) steps, capped to \(maxSteps)."))
            }
            let planSteps = effective.steps.enumerated().map { idx, step in
                AgentPlanStep(index: idx + 1, title: step.title, subtitle: step.subtitle, kind: planStepKind(from: step.kind))
            }
            messages.append(.plan(planSteps))
            messages.append(.actBar())
            currentSteps = effective.steps
            isWaitingForApprove = true
        case .failure(let error):
            messages.append(.assistantError("⚠️ \(error.localizedDescription)"))
        }
        isThinking = false
    }

    /// Ponytail safety net: if HID mode and the plan has `terminal` steps but no
    /// preceding `hid` step to open a terminal app, inject one. LLMs sometimes
    /// skip this even with explicit instructions — this makes it a code guarantee.
    private func sanitizeHIDPlan(_ plan: AgentLLMPlan) -> AgentLLMPlan {
        let hasTerminalStep = plan.steps.contains { $0.kind.lowercased() == "terminal" }
        let hasHIDBeforeTerminal: Bool = {
            for step in plan.steps {
                let k = step.kind.lowercased()
                if k == "hid" { return true }
                if k == "terminal" { return false }
            }
            return false
        }()
        guard hasTerminalStep && !hasHIDBeforeTerminal else { return plan }

        let targetOS = AISettings.shared.targetOS
        let (payload, label): (String, String)
        switch targetOS {
        case .macOS:
            // <CMD><SPACE> opens Spotlight, </CMD> releases Cmd before typing,
            // <CMD>a</CMD> selects all leftover search text, <BACK> deletes it,
            // then type "terminal" and <ENTER> to launch.
            payload = "<CMD><SPACE></CMD><DELAY1S><CMD>a</CMD><BACK><DELAY1S>terminal<ENTER><DELAY3S>"
            label = "Open Terminal via Spotlight"
        case .linux:
            payload = "<CTRL><ALT>t<DELAY3S>"
            label = "Open Terminal"
        case .windows:
            payload = "<WIN>r<DELAY1S>cmd<ENTER><DELAY4S>"
            label = "Open Command Prompt"
        }
        let openStep = AgentLLMStep(kind: "hid", title: label, subtitle: "Wait for terminal to launch", payload: payload)
        let patched = [openStep] + plan.steps
        return AgentLLMPlan(intro: plan.intro + " (auto-injected terminal launch for HID mode)", steps: patched)
    }

    // MARK: - Approve & Run

    func approveAndRun() {
        guard let steps = currentSteps, !isExecuting else { return }

        isWaitingForApprove = false
        isExecuting = true
        collectedOutputs = []
        retryCount = 0

        removeActBar()

        executor = AgentExecutor(keyboardManager: keyboardManager, macroManager: macroManager, bleManager: bleManager)
        executor?.run(
            steps: steps,
            onStepStart: { [weak self] idx, step in
                self?.upsertExecutionForStep(idx, step)
            },
            onStepDone: { [weak self] idx, step, output in
                self?.markStepDone(idx, step, total: steps.count, output: output)
            },
            onDone: { [weak self] in
                self?.checkForRetriesAndFinish()
            }
        )
    }

    // MARK: - Cancel / Reset

    func cancel() {
        executor?.cancel()
        if isExecuting {
            removeExecutionMessages()
            messages.append(.assistant("Execution cancelled."))
            isExecuting = false
            isWaitingForApprove = false
        }
    }

    func reset() {
        executor?.cancel()
        executor = nil
        messages = []
        currentSteps = nil
        currentPrompt = nil
        collectedOutputs = []
        retryCount = 0
        isThinking = false
        isExecuting = false
        isWaitingForApprove = false
        hasContent = false
        receivedTokens = 0
    }

    // MARK: - Execution display helpers

    private func upsertExecutionForStep(_ idx: Int, _ step: AgentLLMStep) {
        // Only drop transient macro cards — previous CLI results stay on screen
        messages.removeAll { $0.type == .executionMacro }
        switch step.kind.lowercased() {
        case "terminal":
            messages.append(.executionCli(command: "$ " + step.payload, outputLines: [], status: "running"))
        case "hid":
            messages.append(.executionMacro(steps: [step.title], progress: Int(Double(idx + 1) / Double(max(1, (currentSteps?.count ?? 1))) * 100), currentStep: idx, statusChip: "typing"))
        case "macro":
            messages.append(.executionMacro(steps: [step.title], progress: Int(Double(idx + 1) / Double(max(1, (currentSteps?.count ?? 1))) * 100), currentStep: idx, statusChip: "running"))
        default:
            break
        }
    }

    private func markStepDone(_ idx: Int, _ step: AgentLLMStep, total: Int, output: String?) {
        let progress = Int(Double(idx + 1) / Double(max(1, total)) * 100)
        switch step.kind.lowercased() {
        case "terminal":
            LogManager.shared.log("📝 markStepDone[terminal]: step[\(idx)] cmd=\(step.payload), output length=\(output?.count ?? 0)", category: "Agent", level: .info)
            if let output = output {
                LogManager.shared.log("  output preview=\(String(output.prefix(200)))", category: "Agent", level: .debug)
            }
            // Collect output for summarization
            if let output = output, !output.isEmpty {
                collectedOutputs.append((command: step.payload, output: output))
            }
            // Parse output into lines for display
            let outputLines = output?.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) ?? []
            let truncatedLines = Array(outputLines.prefix(20))
            let status = output?.hasPrefix("Error:") == true ? "error" : "done"
            LogManager.shared.log("  status=\(status), collectedOutputs.count=\(collectedOutputs.count)", category: "Agent", level: .info)
            let cmd = "$ " + step.payload
            // Swap only THIS step's running card for the done card; other CLI cards stay
            if let runIdx = messages.lastIndex(where: { $0.type == .executionCli && $0.terminalCommand == cmd && $0.terminalStatus == "running" }) {
                messages.remove(at: runIdx)
            }
            messages.append(.executionCli(command: cmd, outputLines: truncatedLines, status: status))
        case "hid", "macro":
            // Macro/HID cards are transient — replace with the "done" aggregate view
            messages.removeAll { $0.type == .executionMacro }
            messages.append(.executionMacro(
                steps: (currentSteps ?? []).map { $0.title },
                progress: progress,
                currentStep: idx,
                statusChip: "done"
            ))
        default:
            break
        }
    }

    // MARK: - Retry loop

    /// After execution completes, check for failed terminal steps. If any and under
    /// retry budget, ask the LLM for alternative commands and execute them.
    private func checkForRetriesAndFinish() {
        LogManager.shared.log("🔍 checkForRetriesAndFinish: retryCount=\(retryCount), collectedOutputs=\(collectedOutputs.count)", category: "Agent", level: .info)

        // Log all collected outputs to see what we have
        for (idx, output) in collectedOutputs.enumerated() {
            let startsWithError = output.output.hasPrefix("Error:")
            LogManager.shared.log("  output[\(idx)] cmd=\(output.command), startsWithError=\(startsWithError), preview=\(String(output.output.prefix(100)))", category: "Agent", level: .debug)
        }

        let maxRetries = AISettings.shared.agentMaxRetries
        LogManager.shared.log("🔍 maxRetries=\(maxRetries)", category: "Agent", level: .info)

        // Collect failed terminal commands
        let failures = collectedOutputs.filter { $0.output.hasPrefix("Error:") }
        LogManager.shared.log("🔍 failures.count=\(failures.count)", category: "Agent", level: .info)

        guard !failures.isEmpty, retryCount < maxRetries, let prompt = currentPrompt else {
            LogManager.shared.log("🔍 No retry needed: failures.isEmpty=\(failures.isEmpty), retryCount<max=\(retryCount < maxRetries), hasPrompt=\(currentPrompt != nil)", category: "Agent", level: .info)
            // No failures or out of retries — finish
            summarizeAndFinish()
            return
        }

        retryCount += 1
        let targetOS = AISettings.shared.targetOS
        LogManager.shared.log("🔄 Retry \(retryCount)/\(maxRetries): \(failures.count) command(s) failed", category: "Agent", level: .info)

        // Show a retry message in the transcript
        let retryMsg = "🔄 Retry \(retryCount)/\(maxRetries): \(failures.count) command(s) failed. Asking for alternatives…"
        messages.append(.assistant(retryMsg))

        isThinking = true
        receivedTokens = 0
        // Capture managers strongly — we're inside AgentSession, they'll stay valid
        let kbMgr = keyboardManager
        let macroMgr = macroManager
        let bleMgr = bleManager

        LogManager.shared.log("🔄 Calling retryPlan with prompt=\(prompt), targetOS=\(targetOS.displayName)", category: "Agent", level: .info)
        for (idx, failure) in failures.enumerated() {
            LogManager.shared.log("  failure[\(idx)] cmd=\(failure.command), error=\(String(failure.output.prefix(200)))", category: "Agent", level: .info)
        }

        let terminalModeCtx = buildTerminalModeContext()
        AgentLLMService.shared.retryPlan(
            originalPrompt: prompt,
            failedSteps: failures.map { (command: $0.command, error: $0.output) },
            targetOS: targetOS,
            terminalModeContext: terminalModeCtx,
            onToken: { [weak self] count in
                self?.receivedTokens = count
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isThinking = false
                switch result {
                case .success(let plan):
                    LogManager.shared.log("✅ retryPlan succeeded: \(plan.steps.count) steps", category: "Agent", level: .info)
                    guard !plan.steps.isEmpty else {
                        LogManager.shared.log("⚠️ retryPlan returned empty plan", category: "Agent", level: .warning)
                        self.summarizeAndFinish()
                        return
                    }
                    let retrySteps = plan.steps
                    self.currentSteps = retrySteps

                    // Log the retry steps
                    for (idx, step) in retrySteps.enumerated() {
                        LogManager.shared.log("  retryStep[\(idx)] kind=\(step.kind) title=\(step.title) payload=\(step.payload)", category: "Agent", level: .info)
                    }

                    let planSteps = retrySteps.enumerated().map { idx, step in
                        AgentPlanStep(index: idx + 1, title: step.title, subtitle: step.subtitle, kind: .terminal)
                    }
                    self.messages.append(.plan(planSteps))

                    self.executor = AgentExecutor(keyboardManager: kbMgr, macroManager: macroMgr, bleManager: bleMgr)
                    self.executor?.run(
                        steps: retrySteps,
                        onStepStart: { idx, step in
                            self.upsertExecutionForStep(idx, step)
                        },
                        onStepDone: { idx, step, output in
                            self.markStepDone(idx, step, total: retrySteps.count, output: output)
                        },
                        onDone: {
                            self.checkForRetriesAndFinish()
                        }
                    )
                case .failure(let error):
                    LogManager.shared.log("❌ retryPlan failed: \(error.localizedDescription)", category: "Agent", level: .error)
                    self.messages.append(.assistantError("⚠️ Retry planning failed: \(error.localizedDescription)"))
                    self.summarizeAndFinish()
                }
            }
        }
    }

    private func summarizeAndFinish() {
        // Keep terminal (CLI) cards visible — only drop transient macro/HID progress indicators
        messages.removeAll { $0.type == .executionMacro }

        // If we have terminal outputs and a prompt, call LLM to summarize
        if !collectedOutputs.isEmpty, let prompt = currentPrompt {
            isThinking = true
            receivedTokens = 0
            let terminalModeCtx = buildTerminalModeContext()
            AgentLLMService.shared.summarize(prompt: prompt, stepOutputs: collectedOutputs, terminalModeContext: terminalModeCtx, onToken: { [weak self] count in
                self?.receivedTokens = count
            }) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isThinking = false
                    switch result {
                    case .success(let summary):
                        self?.messages.append(.assistant(summary))
                    case .failure(let error):
                        self?.messages.append(.assistantError("⚠️ Summarize failed: \(error.localizedDescription)"))
                    }
                    self?.isExecuting = false
                    self?.currentSteps = nil
                    self?.executor = nil
                    self?.currentPrompt = nil
                    self?.collectedOutputs = []
                }
            }
        } else {
            // No terminal outputs or no prompt — just show step count
            let count = currentSteps?.count ?? 0
            messages.append(.assistant("✅ Completed \(count) step\(count == 1 ? "" : "s")."))
            isExecuting = false
            currentSteps = nil
            executor = nil
            currentPrompt = nil
            collectedOutputs = []
        }
    }

    // MARK: - Helpers

    private func planStepKind(from raw: String) -> AgentPlanStep.Kind {
        switch raw.lowercased() {
        case "terminal": return .terminal
        case "macro": return .macro
        default: return .hid
        }
    }

    private func removeActBar() {
        if let i = messages.lastIndex(where: { $0.type == .actBar }) {
            messages.remove(at: i)
        }
    }

    private func removeExecutionMessages() {
        // CLI cards persist (terminal history); only macro/HID progress cards are transient
        messages.removeAll { $0.type == .executionMacro }
    }

    func regeneratePlan() {
        guard let prompt = currentPrompt else { return }
        submit(prompt: prompt)
    }

    func reexecutePlan() {
        approveAndRun()
    }
}
