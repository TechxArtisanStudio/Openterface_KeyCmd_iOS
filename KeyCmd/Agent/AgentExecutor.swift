import Foundation

/// Executes a sequence of AgentLLMSteps via SSH (terminal), BLE HID (keyboard), and/or MacroManager.
final class AgentExecutor {
    private let keyboardManager: KeyboardManager
    private let macroManager: MacroManager
    private let bleManager: BLEManager
    private let stepDelay: TimeInterval = 0.5
    private var cancelled = false

    /// Cached SSH outputs from executed terminal steps, keyed by step index.
    private(set) var stepOutputs: [Int: String] = [:]

    init(keyboardManager: KeyboardManager, macroManager: MacroManager, bleManager: BLEManager) {
        self.keyboardManager = keyboardManager
        self.macroManager = macroManager
        self.bleManager = bleManager
    }

    /// Run all steps sequentially. Callbacks fire on the main queue.
    func run(steps: [AgentLLMStep],
             onStepStart: @escaping (Int, AgentLLMStep) -> Void,
             onStepDone: @escaping (Int, AgentLLMStep, String?) -> Void,
             onDone: @escaping () -> Void) {
        cancelled = false
        stepOutputs = [:]
        let q = DispatchQueue(label: "agent.executor")

        q.async { [weak self] in
            guard let self = self else { return }

            for (idx, step) in steps.enumerated() {
                guard !self.cancelled else { break }

                DispatchQueue.main.async { onStepStart(idx, step) }

                let output = self.execute(step: step)
                if let output = output {
                    self.stepOutputs[idx] = output
                }

                if self.stepDelay > 0 && !self.cancelled {
                    Thread.sleep(forTimeInterval: self.stepDelay)
                }

                DispatchQueue.main.async { onStepDone(idx, step, output) }
            }

            DispatchQueue.main.async {
                self.cancelled = false
                onDone()
            }
        }
    }

    func cancel() { cancelled = true }

    /// Execute a single step. Returns captured output for terminal steps, nil otherwise.
    private func execute(step: AgentLLMStep) -> String? {
        switch step.kind.lowercased() {
        case "terminal":
            return executeTerminal(step.payload)
        case "hid":
            keyboardManager.handleTextInputWithTokensSync(step.payload)
            // Safety: release all modifiers/keys so nothing carries into the next step.
            DispatchQueue.main.sync { keyboardManager.releaseAllKeys() }
            return nil
        case "macro":
            macroManager.sendMacroByLabel(step.payload)
            return nil
        default:
            return nil
        }
    }

    /// Execute a terminal command via SSH using the active credential profile.
    /// Falls back to BLE HID if no profile is configured.
    private func executeTerminal(_ command: String) -> String? {
        let credManager = CredentialManager.shared

        // Check if we have an active terminal profile
        guard let profile = credManager.getActiveProfile() else {
            LogManager.shared.log("Agent: no active terminal profile, falling back to HID", category: "Agent", level: .warning)
            // Fall back to BLE keyboard (sync to keep step ordering)
            keyboardManager.handleTextInputWithTokensSync(command + "<ENTER>")
            return nil
        }

        let password = credManager.getPassword(for: profile.id)

        LogManager.shared.log("Agent: executing terminal via SSH: \(command)", category: "Agent", level: .info)

        // Run SSH exec synchronously on this queue (we're already on a background queue)
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        var execError: Error?

        Task {
            do {
                let output = try await SSHClient.execCommand(
                    host: profile.host,
                    port: profile.port,
                    username: profile.username,
                    password: password,
                    command: command,
                    bleManager: self.bleManager
                )
                result = output
            } catch {
                LogManager.shared.log("Agent: SSH exec failed: \(error.localizedDescription)", category: "Agent", level: .error)
                execError = error
                result = "Error: \(error.localizedDescription)"
            }
            semaphore.signal()
        }

        // Wait for SSH execution to complete (timeout 60s)
        let waitResult = semaphore.wait(timeout: .now() + 60)
        if waitResult == .timedOut {
            LogManager.shared.log("Agent: SSH exec timeout", category: "Agent", level: .error)
            return "Error: Command execution timed out"
        }

        return result
    }
}
