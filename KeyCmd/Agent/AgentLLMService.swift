import Foundation

// MARK: - Agent LLM models

struct AgentLLMStep: Codable {
    let kind: String
    let title: String
    let subtitle: String?
    let payload: String
}

struct AgentLLMPlan: Codable {
    let intro: String
    let steps: [AgentLLMStep]
}

/// Result of summarizing agent execution — includes whether the user's task was fully completed.
struct AgentLLMSummary {
    let summary: String
    let taskComplete: Bool
}

enum AgentLLMError: LocalizedError {
    case noProvider
    case noAPIKey
    case networkError(String)
    case apiError(String)
    case invalidJSON(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .noProvider: return "No AI provider selected"
        case .noAPIKey: return "API key not configured"
        case .networkError(let m): return "Network error: \(m)"
        case .apiError(let m): return "API error: \(m)"
        case .invalidJSON(let m): return "Agent returned invalid plan: \(m)"
        case .noContent: return "Agent returned no content"
        }
    }
}

// MARK: - Service

/// Calls the configured LLM with SSE streaming, parsing token deltas and reporting
/// progress via an `onToken` callback.
class AgentLLMService {
    static let shared = AgentLLMService()

    private let settings = AISettings.shared
    private let logger = LogManager.shared

    /// Fetch a plan from the LLM using SSE streaming. `onToken` fires on the main
    /// actor with the running token count as deltas arrive.
    func plan(prompt: String, macroContext: String?, terminalModeContext: String, onToken: ((Int) -> Void)? = nil, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        guard let provider = settings.selectedProvider else {
            completion(.failure(.noProvider)); return
        }

        // Route to local model if provider is local
        if provider.apiBaseURL.hasPrefix("local://") {
            LocalModelManager.shared.selectModel(for: provider.apiBaseURL)
            // Select prompt based on execution mode (terminal vs HID)
            let promptId = terminalModeContext.contains("Terminal (SSH)") ? "agent_planner_terminal" : "agent_planner_hid"
            let basePrompt = settings.effectivePrompt(for: promptId)
            var effectivePrompt = basePrompt
                .replacingOccurrences(of: "{{TERMINAL_MODE_CONTEXT}}", with: terminalModeContext)
            if let ctx = macroContext, !ctx.isEmpty {
                effectivePrompt = effectivePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: ctx)
            } else {
                effectivePrompt = effectivePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: "_No macros are currently defined._")
            }
            handleLocalPlan(prompt: prompt, effectivePrompt: effectivePrompt, onToken: onToken, completion: completion)
            return
        }

        let apiKey = provider.getAPIKey()
        if !provider.apiKeyOptional {
            guard let key = apiKey, !key.isEmpty else {
                completion(.failure(.noAPIKey)); return
            }
        }

        // Select prompt based on execution mode (terminal vs HID)
        let promptId = terminalModeContext.contains("Terminal (SSH)") ? "agent_planner_terminal" : "agent_planner_hid"
        let basePrompt = settings.effectivePrompt(for: promptId)
        guard !basePrompt.isEmpty else {
            completion(.failure(.noProvider)); return
        }
        var effectivePrompt = basePrompt
            .replacingOccurrences(of: "{{TERMINAL_MODE_CONTEXT}}", with: terminalModeContext)

        if let ctx = macroContext, !ctx.isEmpty {
            effectivePrompt = effectivePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: ctx)
        } else {
            effectivePrompt = effectivePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: "_No macros are currently defined._")
        }

        logger.log("Plan prompt sent to LLM:\n\(effectivePrompt.prefix(1000))", category: "Agent", level: .debug)

        let endpoint = provider.apiBaseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.networkError("Invalid endpoint"))); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": provider.modelName.trimmingCharacters(in: .whitespaces),
            "messages": [
                ["role": "system", "content": effectivePrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 2000,
            "stream": true
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error.localizedDescription))); return
        }

        logger.log("🤖 Sending agent plan stream request to \(endpoint)", category: "Agent", level: .info)

        streamRequest(req, providerName: provider.name, onToken: onToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let plan = self?.parsePlan(from: trimmed) else {
                        self?.logger.log("Agent LLM returned non-JSON content: \(String(trimmed.prefix(200)))", category: "Agent", level: .error)
                        completion(.failure(.invalidJSON("Could not parse plan JSON"))); return
                    }
                    self?.logger.log("✅ Agent plan received: \(plan.steps.count) steps", category: "Agent", level: .info)
                    // Log the parsed plan steps for debugging
                    for (i, step) in plan.steps.enumerated() {
                        self?.logger.log("  step[\(i)] kind=\(step.kind) title=\"\(step.title)\" payload=\"\(step.payload)\"", category: "Agent", level: .debug)
                    }
                    completion(.success(plan))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Summarize command outputs using SSE streaming. `onToken` fires on the main
    /// actor with the running token count.
    func summarize(prompt: String, stepOutputs: [(command: String, output: String)], terminalModeContext: String, onToken: ((Int) -> Void)? = nil, completion: @escaping (Result<AgentLLMSummary, AgentLLMError>) -> Void) {
        guard let provider = settings.selectedProvider else {
            completion(.failure(.noProvider)); return
        }

        // Route to local model if provider is local
        if provider.apiBaseURL.hasPrefix("local://") {
            LocalModelManager.shared.selectModel(for: provider.apiBaseURL)
            handleLocalSummarize(prompt: prompt, stepOutputs: stepOutputs, terminalModeContext: terminalModeContext, onToken: onToken, completion: completion)
            return
        }

        let apiKey = provider.getAPIKey()
        if !provider.apiKeyOptional {
            guard let key = apiKey, !key.isEmpty else {
                completion(.failure(.noAPIKey)); return
            }
        }

        let endpoint = provider.apiBaseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.networkError("Invalid endpoint"))); return
        }

        var contextLines: [String] = []
        for (idx, entry) in stepOutputs.enumerated() {
            let truncated = entry.output.count > 2000 ? String(entry.output.prefix(2000)) + "... (truncated)" : entry.output
            contextLines.append("Command \(idx + 1): `\(entry.command)`\nOutput:\n\(truncated)")
        }
        let context = contextLines.joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You are a helpful assistant that summarizes the results of commands executed on a remote device.
        The user asked a question or requested a task. Commands were executed and produced output.
        Based on the command outputs, provide a clear, concise answer to the user's original request.
        If the output contains the answer, state it directly. If there was an error, explain what went wrong.

        IMPORTANT: After summarizing, you MUST also assess whether the user's original task has been fully completed.
        Respond with a JSON object (no prose outside the JSON):
        {
          "summary": "your summary text here",
          "taskComplete": true or false
        }
        Set taskComplete to false if the user's task requires further steps that were not executed (e.g., the agent only read a file but did not act on its contents, or intermediate results suggest more commands are needed).
        """

        let systemPromptWithContext = terminalModeContext + "\n\n" + systemPrompt

        let userMessage = """
        User's request: \(prompt)

        Execution results:
        \(context)

        Please summarize the results, answer the user's request, and assess whether the task is fully completed.
        """

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": provider.modelName.trimmingCharacters(in: .whitespaces),
            "messages": [
                ["role": "system", "content": systemPromptWithContext],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.3,
            "max_tokens": 1000,
            "stream": true
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error.localizedDescription))); return
        }

        logger.log("🤖 Sending agent summarize stream request", category: "Agent", level: .info)

        streamRequest(req, providerName: provider.name, onToken: onToken) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let content):
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let summary = self?.parseSummary(from: trimmed) ?? AgentLLMSummary(summary: trimmed, taskComplete: true)
                    self?.logger.log("✅ Agent summarize received: \(summary.summary.count) chars, taskComplete=\(summary.taskComplete)", category: "Agent", level: .info)
                    completion(.success(summary))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Ask the LLM to produce alternative commands for failed terminal steps.
    /// Used by the retry loop when commands fail due to wrong OS, missing tools, etc.
    func retryPlan(originalPrompt: String, failedSteps: [(command: String, error: String)], targetOS: TargetOS, terminalModeContext: String, onToken: ((Int) -> Void)? = nil, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        logger.log("🔄 retryPlan: starting with \(failedSteps.count) failed steps, targetOS=\(targetOS.displayName)", category: "Agent", level: .info)

        guard let provider = settings.selectedProvider else {
            logger.log("❌ retryPlan: no provider selected", category: "Agent", level: .error)
            completion(.failure(.noProvider)); return
        }

        logger.log("🔄 retryPlan: provider=\(provider.name), model=\(provider.modelName)", category: "Agent", level: .info)

        if provider.apiBaseURL.hasPrefix("local://") {
            logger.log("🔄 retryPlan: routing to local model", category: "Agent", level: .info)
            LocalModelManager.shared.selectModel(for: provider.apiBaseURL)
            handleLocalRetryPlan(originalPrompt: originalPrompt, failedSteps: failedSteps, targetOS: targetOS, terminalModeContext: terminalModeContext, onToken: onToken, completion: completion)
            return
        }

        let apiKey = provider.getAPIKey()
        if !provider.apiKeyOptional {
            guard let key = apiKey, !key.isEmpty else {
                completion(.failure(.noAPIKey)); return
            }
        }

        let endpoint = provider.apiBaseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.networkError("Invalid endpoint"))); return
        }

        var errorLines: [String] = []
        for (idx, entry) in failedSteps.enumerated() {
            errorLines.append("Failed command \(idx + 1): `\(entry.command)`\nError: \(entry.error)")
        }
        let errorContext = errorLines.joined(separator: "\n\n")

        let systemPrompt = """
        You are an autonomous agent that executes commands on a \(targetOS.displayName) device.
        The user asked a question, but some commands failed. Your job is to provide **alternative** commands that work on \(targetOS.displayName).
        Use only commands that are correct for \(targetOS.displayName). Do NOT reuse the failed commands.
        Return a JSON plan with the corrected steps.
        """

        let systemPromptWithContext = terminalModeContext + "\n\n" + systemPrompt

        let userMessage = """
        User's original request: \(originalPrompt)

        The following commands failed on \(targetOS.displayName):

        \(errorContext)

        Please provide alternative commands that will work on \(targetOS.displayName). Respond with a single JSON object inside a ```json code fence. No prose before or after.

        ```json
        {
          "intro": "One-sentence description of the retry plan.",
          "steps": [
            {
              "kind": "terminal",
              "title": "Step title",
              "payload": "correct command for \(targetOS.displayName)"
            }
          ]
        }
        ```
        """

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": provider.modelName.trimmingCharacters(in: .whitespaces),
            "messages": [
                ["role": "system", "content": systemPromptWithContext],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.3,
            "max_tokens": 2000,
            "stream": true
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error.localizedDescription))); return
        }

        logger.log("🤖 Sending agent retry plan stream request (\(failedSteps.count) failed steps)", category: "Agent", level: .info)
        logger.log("🤖 Retry prompt: \(userMessage.prefix(300))", category: "Agent", level: .debug)

        // Capture logger + completion strongly to avoid explicit self in closure
        let log = logger

        streamRequest(req, providerName: provider.name, onToken: onToken) { [weak self] result in
            DispatchQueue.main.async {
                log.log("🤖 retryPlan stream completed", category: "Agent", level: .info)
                switch result {
                case .success(let content):
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    log.log("🤖 retryPlan raw response length=\(trimmed.count), preview=\(String(trimmed.prefix(300)))", category: "Agent", level: .debug)
                    guard let plan = self?.parsePlan(from: trimmed) else {
                        log.log("❌ retryPlan: non-JSON response: \(String(trimmed.prefix(500)))", category: "Agent", level: .error)
                        completion(.failure(.invalidJSON("Could not parse retry plan JSON"))); return
                    }
                    log.log("✅ retryPlan parsed: \(plan.steps.count) steps, intro=\(plan.intro)", category: "Agent", level: .info)
                    completion(.success(plan))
                case .failure(let error):
                    log.log("❌ retryPlan stream error: \(error.localizedDescription)", category: "Agent", level: .error)
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Local model routing

    /// Route plan() to LocalModelManager for on-device inference.
    private func handleLocalPlan(prompt: String, effectivePrompt: String, onToken: ((Int) -> Void)?, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        logger.log("🏠 Routing plan to local model", category: "Agent", level: .info)

        Task {
            do {
                logger.log("🏠 handleLocalPlan: about to await generate()", category: "Agent", level: .info)
                let response = try await LocalModelManager.shared.generate(system: effectivePrompt, user: prompt)
                logger.log("🏠 handleLocalPlan: generate() returned \(response.count) chars", category: "Agent", level: .info)
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

                guard let plan = parsePlan(from: trimmed) else {
                    logger.log("Local model returned non-JSON content: \(String(trimmed.prefix(200)))", category: "Agent", level: .error)
                    completion(.failure(.invalidJSON("Could not parse plan JSON from local model")))
                    return
                }

                logger.log("✅ Local agent plan received: \(plan.steps.count) steps", category: "Agent", level: .info)
                for (i, step) in plan.steps.enumerated() {
                    logger.log("  step[\(i)] kind=\(step.kind) title=\"\(step.title)\" payload=\"\(step.payload)\"", category: "Agent", level: .debug)
                }

                // Simulate streaming by breaking response into chunks and calling onToken? incrementally
                let chunks = response.split { $0.isWhitespace || $0 == "\n" || $0 == "\r" }.map { String($0) }
                var tokenCount = 0

                for chunk in chunks {
                    if !chunk.isEmpty {
                        tokenCount += 1
                        await MainActor.run {
                            onToken?(tokenCount)
                        }
                        // Small delay to simulate streaming effect
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }

                await MainActor.run {
                    completion(.success(plan))
                }
            } catch {
                logger.log("❌ Local model error: \(error.localizedDescription)", category: "Agent", level: .error)
                await MainActor.run {
                    completion(.failure(.networkError(error.localizedDescription)))
                }
            }
        }
    }

    /// Route summarize() to LocalModelManager for on-device inference.
    private func handleLocalSummarize(prompt: String, stepOutputs: [(command: String, output: String)], terminalModeContext: String, onToken: ((Int) -> Void)?, completion: @escaping (Result<AgentLLMSummary, AgentLLMError>) -> Void) {
        logger.log("🏠 Routing summarize to local model", category: "Agent", level: .info)

        var contextLines: [String] = []
        for (idx, entry) in stepOutputs.enumerated() {
            let truncated = entry.output.count > 2000 ? String(entry.output.prefix(2000)) + "... (truncated)" : entry.output
            contextLines.append("Command \(idx + 1): `\(entry.command)`\nOutput:\n\(truncated)")
        }
        let context = contextLines.joined(separator: "\n\n---\n\n")

        let systemPrompt = """
        You are a helpful assistant that summarizes the results of commands executed on a remote device.
        The user asked a question or requested a task. Commands were executed and produced output.
        Based on the command outputs, provide a clear, concise answer to the user's original request.
        If the output contains the answer, state it directly. If there was an error, explain what went wrong.

        IMPORTANT: After summarizing, you MUST also assess whether the user's original task has been fully completed.
        Respond with a JSON object (no prose outside the JSON):
        {
          "summary": "your summary text here",
          "taskComplete": true or false
        }
        Set taskComplete to false if the user's task requires further steps that were not executed.
        """

        let systemPromptWithContext = terminalModeContext + "\n\n" + systemPrompt

        let userMessage = """
        User's request: \(prompt)

        Execution results:
        \(context)

        Please summarize the results, answer the user's request, and assess whether the task is fully completed.
        """

        Task {
            do {
                logger.log("🏠 handleLocalSummarize: about to await generate()", category: "Agent", level: .info)
                let response = try await LocalModelManager.shared.generate(system: systemPromptWithContext, user: userMessage)
                logger.log("🏠 handleLocalSummarize: generate() returned \(response.count) chars", category: "Agent", level: .info)
                let summary = parseSummary(from: response)
                logger.log("✅ Local summarize received: \(summary.summary.count) chars, taskComplete=\(summary.taskComplete)", category: "Agent", level: .info)

                // Simulate streaming by breaking response into chunks and calling onToken? incrementally
                let chunks = summary.summary.split { $0.isWhitespace || $0 == "\n" || $0 == "\r" }.map { String($0) }
                var tokenCount = 0

                for chunk in chunks {
                    if !chunk.isEmpty {
                        tokenCount += 1
                        await MainActor.run {
                            onToken?(tokenCount)
                        }
                        // Small delay to simulate streaming effect
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }

                await MainActor.run {
                    completion(.success(summary))
                }
            } catch {
                logger.log("❌ Local summarize error: \(error.localizedDescription)", category: "Agent", level: .error)
                await MainActor.run {
                    completion(.failure(.networkError(error.localizedDescription)))
                }
            }
        }
    }

    /// Route retryPlan() to LocalModelManager for on-device inference.
    private func handleLocalRetryPlan(originalPrompt: String, failedSteps: [(command: String, error: String)], targetOS: TargetOS, terminalModeContext: String, onToken: ((Int) -> Void)?, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        logger.log("🏠 handleLocalRetryPlan: starting", category: "Agent", level: .info)

        var errorLines: [String] = []
        for (idx, entry) in failedSteps.enumerated() {
            errorLines.append("Failed command \(idx + 1): `\(entry.command)`\nError: \(entry.error)")
        }
        let errorContext = errorLines.joined(separator: "\n\n")

        let systemPrompt = """
        You are an autonomous agent that executes commands on a \(targetOS.displayName) device.
        The user asked a question, but some commands failed. Your job is to provide **alternative** commands that work on \(targetOS.displayName).
        Use only commands that are correct for \(targetOS.displayName). Do NOT reuse the failed commands.
        Return a JSON plan with the corrected steps.
        """

        let systemPromptWithContext = terminalModeContext + "\n\n" + systemPrompt

        let userMessage = """
        User's original request: \(originalPrompt)

        The following commands failed on \(targetOS.displayName):

        \(errorContext)

        Please provide alternative commands that will work on \(targetOS.displayName). Respond with a single JSON object inside a ```json code fence. No prose before or after.
        """

        logger.log("🏠 handleLocalRetryPlan: calling local model generate", category: "Agent", level: .info)

        Task {
            // Give BLE/SSH time to fully clean up before running inference
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            do {
                logger.log("🏠 handleLocalRetryPlan: about to await generate()", category: "Agent", level: .info)
                let response = try await LocalModelManager.shared.generate(system: systemPromptWithContext, user: userMessage)
                logger.log("🏠 handleLocalRetryPlan: generate() returned", category: "Agent", level: .info)
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                logger.log("🏠 handleLocalRetryPlan: got response, length=\(trimmed.count)", category: "Agent", level: .info)
                logger.log("🏠 handleLocalRetryPlan: response preview=\(String(trimmed.prefix(500)))", category: "Agent", level: .debug)

                guard let plan = parsePlan(from: trimmed) ?? parseRetryPlan(from: trimmed) else {
                    logger.log("❌ handleLocalRetryPlan: could not parse JSON from: \(String(trimmed.prefix(500)))", category: "Agent", level: .error)
                    completion(.failure(.invalidJSON("Could not parse retry plan JSON from local model")))
                    return
                }

                logger.log("✅ handleLocalRetryPlan: parsed \(plan.steps.count) steps", category: "Agent", level: .info)
                for (idx, step) in plan.steps.enumerated() {
                    logger.log("  localRetryStep[\(idx)] kind=\(step.kind) title=\(step.title) payload=\(step.payload)", category: "Agent", level: .debug)
                }

                let chunks = response.split { $0.isWhitespace || $0 == "\n" || $0 == "\r" }.map { String($0) }
                var tokenCount = 0

                for chunk in chunks {
                    if !chunk.isEmpty {
                        tokenCount += 1
                        await MainActor.run {
                            onToken?(tokenCount)
                        }
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                }

                await MainActor.run {
                    completion(.success(plan))
                }
            } catch {
                logger.log("❌ Local retry model error: \(error.localizedDescription)", category: "Agent", level: .error)
                await MainActor.run {
                    completion(.failure(.networkError(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: - Streaming helper

    /// Perform a streaming HTTP request, parse SSE deltas, accumulate content, and
    /// invoke `onToken` with the running token count on each delta (main actor).
    private func streamRequest(
        _ request: URLRequest,
        providerName: String,
        onToken: ((Int) -> Void)?,
        completion: @escaping (Result<String, AgentLLMError>) -> Void
    ) {
        Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(.apiError("HTTP \(http.statusCode)")))
                    return
                }

                var content = ""
                var tokenCount = 0

                for try await line in bytes.lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data: ") else { continue }

                    let payload = String(trimmed.dropFirst(6))
                    if payload == "[DONE]" { break }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first else { continue }

                    // Check finish_reason
                    if let reason = first["finish_reason"] as? String, !reason.isEmpty {
                        break
                    }

                    if let delta = first["delta"] as? [String: Any],
                       let chunk = delta["content"] as? String {
                        content += chunk
                        tokenCount += 1
                        let count = tokenCount
                        await MainActor.run { onToken?(count) }
                    }
                }

                completion(.success(content))
            } catch {
                completion(.failure(.networkError(error.localizedDescription)))
            }
        }
    }

    // MARK: - Summary parsing

    /// Parse the summarize response — expects JSON `{summary, taskComplete}`.
    /// Falls back to the raw text as summary with taskComplete=true if parsing fails.
    /// Also strips `<think>...</think>` blocks from reasoning models.
    private func parseSummary(from text: String) -> AgentLLMSummary {
        var cleaned = text

        // Strip <think>...</think> blocks
        while let thinkStart = cleaned.range(of: "<think>", options: .caseInsensitive) {
            if let thinkEnd = cleaned.range(of: "</think>", options: .caseInsensitive) {
                let before = cleaned[cleaned.startIndex..<thinkStart.lowerBound]
                let after = cleaned[thinkEnd.upperBound...]
                cleaned = String(before) + String(after)
            } else {
                let before = cleaned[cleaned.startIndex..<thinkStart.lowerBound]
                cleaned = String(before)
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON block
        var jsonCandidate = cleaned
        if let fenceRange = cleaned.range(of: "```json", options: .caseInsensitive) {
            let afterFence = cleaned[fenceRange.upperBound...]
            if let endFence = afterFence.range(of: "```") {
                jsonCandidate = String(afterFence[afterFence.startIndex..<endFence.lowerBound])
            } else {
                jsonCandidate = String(afterFence)
            }
        }

        // Try to find a JSON object
        if let openIdx = jsonCandidate.firstIndex(of: "{"), let closeIdx = jsonCandidate.lastIndex(of: "}") {
            let slice = String(jsonCandidate[openIdx...closeIdx])
            if let data = slice.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let summary = (dict["summary"] as? String) ?? cleaned
                let taskComplete = (dict["taskComplete"] as? Bool) ?? true
                return AgentLLMSummary(summary: summary, taskComplete: taskComplete)
            }
        }

        // Fallback: raw text, assume task complete
        return AgentLLMSummary(summary: cleaned, taskComplete: true)
    }

    // MARK: - Plan parsing

    /// Extracts the first JSON object from the response — either from a ` ```json ... ``` ` fence
    /// or from the entire string if it parses directly.
    /// Also strips `<think>...</think>` blocks emitted by Qwen3 and other "thinking" models.
    private func parsePlan(from text: String) -> AgentLLMPlan? {
        let decoder = JSONDecoder()

        // Strip ALL <think>…</think> blocks — thinking models emit reasoning before any output
        var cleaned = text
        var strippedCount = 0
        // Remove all <think>...</think> pairs (handles multiple blocks)
        while let thinkStart = cleaned.range(of: "<think>", options: .caseInsensitive) {
            if let thinkEnd = cleaned.range(of: "</think>", options: .caseInsensitive) {
                // Strip from <think> to after </think>
                let before = cleaned[cleaned.startIndex..<thinkStart.lowerBound]
                let after = cleaned[thinkEnd.upperBound...]
                cleaned = String(before) + String(after)
                strippedCount += 1
            } else {
                // No closing tag — strip from <think> to end of string
                let before = cleaned[cleaned.startIndex..<thinkStart.lowerBound]
                cleaned = String(before)
                strippedCount += 1
            }
        }
        if strippedCount > 0 {
            logger.log("🧠 Stripped \(strippedCount) <think> block(s) from plan response", category: "Agent", level: .info)
            logger.log("🧠 Cleaned response preview: \(String(cleaned.prefix(300)))", category: "Agent", level: .info)
        }
        if let fenceRange = cleaned.range(of: "```json", options: .caseInsensitive) {
            let afterFence = cleaned[fenceRange.upperBound...]
            if let endFence = afterFence.range(of: "```") {
                let jsonText = String(afterFence[afterFence.startIndex..<endFence.lowerBound])
                if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(jsonText.utf8)) {
                    return plan
                }
            }
        }
        if let fenceRange = cleaned.range(of: "```") {
            let afterFence = cleaned[fenceRange.upperBound...]
            if let endFence = afterFence.range(of: "```") {
                let jsonText = String(afterFence[afterFence.startIndex..<endFence.lowerBound])
                if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(jsonText.utf8)) {
                    return plan
                }
            }
        }

        if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(cleaned.utf8)) {
            return plan
        }

        if let openIdx = cleaned.firstIndex(of: "{"), let closeIdx = cleaned.lastIndex(of: "}") {
            let slice = String(cleaned[openIdx...closeIdx])
            if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(slice.utf8)) {
                return plan
            }
        }
        return nil
    }

    /// Parse retry plan JSON (simple object with command1, command2, etc.) into AgentLLMPlan
    private func parseRetryPlan(from text: String) -> AgentLLMPlan? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip <think> blocks first (same logic as parsePlan)
        var cleanedText = cleaned
        while let thinkStart = cleanedText.range(of: "<think>", options: .caseInsensitive),
              let thinkEnd = cleanedText.range(of: "</think>", options: .caseInsensitive) {
            let before = cleanedText[cleanedText.startIndex..<thinkStart.lowerBound]
            let after = cleanedText[thinkEnd.upperBound...]
            cleanedText = String(before) + String(after)
        }

        if let openIdx = cleanedText.firstIndex(of: "{"), let closeIdx = cleanedText.lastIndex(of: "}") {
            let slice = String(cleanedText[openIdx...closeIdx])

            if let dict = try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String: String] {
                var steps: [AgentLLMStep] = []

                for (key, value) in dict {
                    if key.hasPrefix("command") {
                        let step = AgentLLMStep(
                            kind: "terminal",
                            title: "Retry \(key.replacingOccurrences(of: "command", with: ""))",
                            subtitle: nil,
                            payload: value
                        )
                        steps.append(step)
                    }
                }

                steps.sort { a, b in
                    let aNum = Int(a.title.components(separatedBy: " ").last ?? "0") ?? 0
                    let bNum = Int(b.title.components(separatedBy: " ").last ?? "0") ?? 0
                    return aNum < bNum
                }

                return AgentLLMPlan(intro: "Retrying with alternative commands", steps: steps)
            }
        }

        return nil
    }
}
