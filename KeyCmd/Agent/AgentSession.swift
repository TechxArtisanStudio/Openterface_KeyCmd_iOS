import Foundation

/// Orchestrates the real Agent flow: user prompt → LLM plan → approve → execute.
final class AgentSession: ObservableObject {
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var isThinking: Bool = false
    @Published private(set) var isExecuting: Bool = false
    @Published private(set) var isWaitingForApprove: Bool = false
    @Published private(set) var hasContent: Bool = false

    private let keyboardManager: KeyboardManager
    private var macroManager: MacroManager
    private var executor: AgentExecutor?
    private var currentSteps: [AgentLLMStep]?

    init(keyboardManager: KeyboardManager, macroManager: MacroManager) {
        self.keyboardManager = keyboardManager
        self.macroManager = macroManager
    }

    // MARK: - Submit

    func submit(prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Reset state for a fresh submission
        isThinking = true
        isWaitingForApprove = false
        isExecuting = false
        hasContent = true

        messages.append(.user(prompt))

        let macroCtx = macroManager.macroContextSection()
        AgentLLMService.shared.plan(prompt: prompt, macroContext: macroCtx) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePlanResult(result)
            }
        }
    }

    private func handlePlanResult(_ result: Result<AgentLLMPlan, AgentLLMError>) {
        switch result {
        case .success(let plan):
            messages.append(.assistant(plan.intro))
            let planSteps = plan.steps.enumerated().map { idx, step in
                AgentPlanStep(index: idx + 1, title: step.title, subtitle: step.subtitle, kind: planStepKind(from: step.kind))
            }
            messages.append(.plan(planSteps))
            messages.append(.actBar())
            currentSteps = plan.steps
            isWaitingForApprove = true
        case .failure(let error):
            messages.append(.assistant("⚠️ \(error.localizedDescription)"))
        }
        isThinking = false
    }

    // MARK: - Approve & Run

    func approveAndRun() {
        guard let steps = currentSteps, !isExecuting else { return }

        isWaitingForApprove = false
        isExecuting = true

        removeActBar()

        executor = AgentExecutor(keyboardManager: keyboardManager, macroManager: macroManager)
        executor?.run(
            steps: steps,
            onStepStart: { [weak self] idx, step in
                self?.upsertExecutionForStep(idx, step)
            },
            onStepDone: { [weak self] idx, step in
                self?.markStepDone(idx, step, total: steps.count)
            },
            onDone: { [weak self] in
                self?.finishWithSummary()
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
        isThinking = false
        isExecuting = false
        isWaitingForApprove = false
        hasContent = false
    }

    // MARK: - Execution display helpers

    private func upsertExecutionForStep(_ idx: Int, _ step: AgentLLMStep) {
        removeExecutionMessages()
        switch step.kind.lowercased() {
        case "terminal":
            messages.append(.executionCli(["$ " + step.payload]))
        case "hid":
            messages.append(.executionMacro(steps: [step.title], progress: Int(Double(idx + 1) / Double(max(1, (currentSteps?.count ?? 1))) * 100), currentStep: idx, statusChip: "typing"))
        case "macro":
            messages.append(.executionMacro(steps: [step.title], progress: Int(Double(idx + 1) / Double(max(1, (currentSteps?.count ?? 1))) * 100), currentStep: idx, statusChip: "running"))
        default:
            break
        }
    }

    private func markStepDone(_ idx: Int, _ step: AgentLLMStep, total: Int) {
        removeExecutionMessages()
        let progress = Int(Double(idx + 1) / Double(max(1, total)) * 100)
        switch step.kind.lowercased() {
        case "terminal":
            messages.append(.executionCli(["$ " + step.payload, "✓ done"]))
        case "hid", "macro":
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

    private func finishWithSummary() {
        removeExecutionMessages()
        let count = currentSteps?.count ?? 0
        messages.append(.assistant("✅ Completed \(count) step\(count == 1 ? "" : "s")."))
        isExecuting = false
        currentSteps = nil
        executor = nil
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
        messages.removeAll { $0.type == .executionCli || $0.type == .executionMacro }
    }
}
