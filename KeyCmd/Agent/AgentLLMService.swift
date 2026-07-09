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

/// Calls the configured LLM with the agent_planner role and parses a JSON plan.
class AgentLLMService {
    static let shared = AgentLLMService()

    private let settings = AISettings.shared
    private let logger = LogManager.shared

    /// Fetch a plan from the LLM. The `agent_planner` system prompt is used, with
    /// `macroContext` appended (if provided) in place of the `{{MACRO_CONTEXT}}` placeholder.
    func plan(prompt: String, macroContext: String?, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        guard let provider = settings.selectedProvider else {
            completion(.failure(.noProvider)); return
        }
        let apiKey = provider.getAPIKey()
        if !provider.apiKeyOptional {
            guard let key = apiKey, !key.isEmpty else {
                completion(.failure(.noAPIKey)); return
            }
        }

        guard let role = settings.getSystemPromptRole(id: "agent_planner") else {
            completion(.failure(.noProvider)); return
        }

        let basePrompt = role.prompt
        let effectivePrompt: String
        if let ctx = macroContext, !ctx.isEmpty {
            effectivePrompt = basePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: ctx)
        } else {
            effectivePrompt = basePrompt.replacingOccurrences(of: "{{MACRO_CONTEXT}}", with: "_No macros are currently defined._")
        }

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
            "max_tokens": 2000
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError(error.localizedDescription))); return
        }

        logger.log("🤖 Sending agent plan request to \(endpoint)", category: "Agent", level: .info)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(data: data, response: response, error: error, providerName: provider.name, completion: completion)
            }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, providerName: String, completion: @escaping (Result<AgentLLMPlan, AgentLLMError>) -> Void) {
        if let error = error {
            logger.log("Agent LLM network error: \(error.localizedDescription)", category: "Agent", level: .error)
            completion(.failure(.networkError(error.localizedDescription))); return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = data.flatMap { try? JSONDecoder().decode(APIErrorResponse.self, from: $0).error.message } ?? "HTTP \(http.statusCode)"
            logger.log("Agent LLM API error (status \(http.statusCode)): \(msg)", category: "Agent", level: .error)
            completion(.failure(.apiError(msg))); return
        }
        guard let data = data else {
            completion(.failure(.noContent)); return
        }

        // Decode the chat completion wrapper
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            completion(.failure(.invalidJSON("Unexpected response shape"))); return
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plan = parsePlan(from: trimmed) else {
            logger.log("Agent LLM returned non-JSON content: \(String(trimmed.prefix(200)))", category: "Agent", level: .error)
            completion(.failure(.invalidJSON("Could not parse plan JSON"))); return
        }
        logger.log("✅ Agent plan received: \(plan.steps.count) steps", category: "Agent", level: .info)
        completion(.success(plan))
    }

    /// Extracts the first JSON object from the response — either from a ` ```json ... ``` ` fence
    /// or from the entire string if it parses directly.
    private func parsePlan(from text: String) -> AgentLLMPlan? {
        let decoder = JSONDecoder()

        // Try fenced code block first
        if let fenceRange = text.range(of: "```json", options: .caseInsensitive) {
            let afterFence = text[fenceRange.upperBound...]
            if let endFence = afterFence.range(of: "```") {
                let jsonText = String(afterFence[afterFence.startIndex..<endFence.lowerBound])
                if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(jsonText.utf8)) {
                    return plan
                }
            }
        }
        if let fenceRange = text.range(of: "```") {
            let afterFence = text[fenceRange.upperBound...]
            if let endFence = afterFence.range(of: "```") {
                let jsonText = String(afterFence[afterFence.startIndex..<endFence.lowerBound])
                if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(jsonText.utf8)) {
                    return plan
                }
            }
        }

        // Try the whole string
        if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(text.utf8)) {
            return plan
        }

        // Try extracting the first { ... } block
        if let openIdx = text.firstIndex(of: "{"), let closeIdx = text.lastIndex(of: "}") {
            let slice = String(text[openIdx...closeIdx])
            if let plan = try? decoder.decode(AgentLLMPlan.self, from: Data(slice.utf8)) {
                return plan
            }
        }
        return nil
    }
}
