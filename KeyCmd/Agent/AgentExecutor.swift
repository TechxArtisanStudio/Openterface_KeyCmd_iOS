import Foundation

/// Executes a sequence of AgentLLMSteps via KeyboardManager and/or MacroManager.
final class AgentExecutor {
    private let keyboardManager: KeyboardManager
    private let macroManager: MacroManager
    private let stepDelay: TimeInterval = 0.5
    private var cancelled = false

    init(keyboardManager: KeyboardManager, macroManager: MacroManager) {
        self.keyboardManager = keyboardManager
        self.macroManager = macroManager
    }

    /// Run all steps sequentially. Callbacks fire on the main queue.
    func run(steps: [AgentLLMStep],
             onStepStart: @escaping (Int, AgentLLMStep) -> Void,
             onStepDone: @escaping (Int, AgentLLMStep) -> Void,
             onDone: @escaping () -> Void) {
        cancelled = false
        let group = DispatchGroup()
        let q = DispatchQueue(label: "agent.executor")

        for (idx, step) in steps.enumerated() {
            q.async { [weak self] in
                guard let self = self, !self.cancelled else { return }
                group.enter()
                DispatchQueue.main.async { onStepStart(idx, step) }
                self.execute(step: step)
                if stepDelay > 0 {
                    Thread.sleep(forTimeInterval: stepDelay)
                }
                DispatchQueue.main.async { onStepDone(idx, step) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.cancelled = false
            onDone()
        }
    }

    func cancel() { cancelled = true }

    private func execute(step: AgentLLMStep) {
        switch step.kind.lowercased() {
        case "terminal":
            keyboardManager.handleTextInputWithTokens(step.payload + "<ENTER>")
        case "hid":
            keyboardManager.handleTextInputWithTokens(step.payload)
        case "macro":
            macroManager.sendMacroByLabel(step.payload)
        default:
            break
        }
    }
}
