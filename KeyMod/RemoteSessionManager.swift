//
//  RemoteSessionManager.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import Foundation
import UIKit

// MARK: - Session State

enum RemoteSessionState: Equatable {
    case idle
    case starting             // workflow dispatch sent, awaiting 204
    case waitingForURL        // polling .tunnel-url in the repo
    case connected            // WebSocket open, relaying input
    case error(String)

    var displayText: String {
        switch self {
        case .idle:              return "Not started"
        case .starting:          return "Starting GitHub workflow…"
        case .waitingForURL:     return "Waiting for tunnel URL…"
        case .connected:         return "Session active"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .waitingForURL, .connected: return true
        default: return false
        }
    }

    static func == (lhs: RemoteSessionState, rhs: RemoteSessionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.starting, .starting),
             (.waitingForURL, .waitingForURL), (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Manager

class RemoteSessionManager: ObservableObject {

    // MARK: Published state
    @Published var state: RemoteSessionState = .idle
    @Published var tunnelURL: URL?

    // MARK: Injected (set from ContentView after init)
    weak var keyboardManager: KeyboardManager?
    weak var mouseManager: MouseManager?

    // MARK: Private
    private let logger = LogManager.shared
    private var pollTimer: Timer?
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession = .shared
    private var dispatchTimestamp: Date?
    
    /// Maximum age (in seconds) for a tunnel URL. URLs older than this are considered stale.
    private let maxTunnelURLAge: TimeInterval = 60.0
    
    /// Tracks the previous URL to detect when server generates a new one
    private var previousTunnelURL: URL?
    
    /// Timeout for waiting for URL change (1 minute)
    private let urlChangeTimeout: TimeInterval = 60.0
    private var urlChangePollingStartTime: Date?
    private var urlChangePollingTimer: Timer?

    // MARK: - ANSI escape-sequence → KeyboardManager key name map
    private let escapeKeyMap: [String: String] = [
        "\u{1b}[A"  : "Up",      "\u{1b}[B"   : "Down",
        "\u{1b}[C"  : "Right",   "\u{1b}[D"   : "Left",
        "\u{1b}[H"  : "Home",    "\u{1b}[F"   : "End",
        "\u{1b}[5~" : "PageUp",  "\u{1b}[6~"  : "PgDn",
        "\u{1b}[2~" : "Insert",  "\u{1b}[3~"  : "Delete",
        "\u{1b}OP"  : "F1",  "\u{1b}OQ"  : "F2",
        "\u{1b}OR"  : "F3",  "\u{1b}OS"  : "F4",
        "\u{1b}[15~": "F5",  "\u{1b}[17~": "F6",
        "\u{1b}[18~": "F7",  "\u{1b}[19~": "F8",
        "\u{1b}[20~": "F9",  "\u{1b}[21~": "F10",
        "\u{1b}[23~": "F11", "\u{1b}[24~": "F12",
        "\u{0d}"    : "Enter",
        "\u{0a}"    : "Enter",
        "\u{7f}"    : "Backspace",
        "\u{1b}"    : "Escape",
        "\u{09}"    : "Tab",
        " "         : "Space"
    ]

    // MARK: - Public Interface

    func startSession() {
        guard !state.isActive else {
            logger.log("startSession() called but session is already active (state=\(state.displayText)) — ignoring", category: "Remote", level: .warning)
            return
        }
        let settings = RemoteSettings.shared
        guard settings.isConfigured else {
            setError("GitHub token and repository must be configured.")
            return
        }
        
        // Clear old tunnel URL and timestamp
        DispatchQueue.main.async {
            self.tunnelURL = nil
            settings.tunnelURLTimestamp = nil
        }
        
        logger.log("Starting session — repo: \(settings.githubRepo)  workflow: \(settings.githubWorkflow)  ref: \(settings.githubRef)  duration: \(settings.sessionDurationMinutes) min", category: "Remote")
        logger.log("Token present: \(!settings.githubToken.isEmpty)  length: \(settings.githubToken.count)", category: "Remote")
        setState(.starting)
        
        // Fetch the current URL from the repo to establish baseline (even on first start)
        fetchCurrentURLAsBaseline(settings: settings)
    }

    private func fetchCurrentURLAsBaseline(settings: RemoteSettings) {
        let pollURLString = "https://api.github.com/repos/\(settings.githubRepo)/contents/.tunnel-url"
        logger.log("Fetching current URL as baseline to avoid reusing stale URLs: GET \(pollURLString)", category: "Remote")

        guard let url = URL(string: pollURLString) else {
            logger.log("Could not build poll URL from: \(pollURLString)", category: "Remote", level: .error)
            dispatchWorkflow(settings: settings)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.githubToken)",   forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json",      forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28",                       forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let base64Content = json["content"] as? String else {
                self.logger.log("Baseline fetch: URL file not found or not readable; proceeding without baseline", category: "Remote")
                self.dispatchWorkflow(settings: settings)
                return
            }

            let stripped = base64Content.replacingOccurrences(of: "\n", with: "")
            guard let decoded = Data(base64Encoded: stripped),
                  let rawURL = String(data: decoded, encoding: .utf8)
                                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                  !rawURL.isEmpty,
                  let baselineURL = URL(string: rawURL) else {
                self.logger.log("Baseline fetch: Failed to decode URL; proceeding without baseline", category: "Remote")
                self.dispatchWorkflow(settings: settings)
                return
            }

            self.previousTunnelURL = baselineURL
            self.logger.log("✅ Baseline URL established: \(rawURL) — will only accept URLs different from this", category: "Remote")
            self.dispatchWorkflow(settings: settings)
        }.resume()
    }

    func stopSession() {
        logger.log("stopSession() called — state was: \(state.displayText)", category: "Remote")
        pollTimer?.invalidate()
        pollTimer = nil
        urlChangePollingTimer?.invalidate()
        urlChangePollingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.state = .idle
            self.tunnelURL = nil
        }
        logger.log("Session stopped.", category: "Remote")
    }

    // MARK: - Step 1: Trigger GitHub Actions workflow

    private func dispatchWorkflow(settings: RemoteSettings) {
        let dispatchURLString = "https://api.github.com/repos/\(settings.githubRepo)/actions/workflows/\(settings.githubWorkflow)/dispatches"
        logger.log("Dispatch URL: \(dispatchURLString)", category: "Remote")

        guard let url = URL(string: dispatchURLString) else {
            setError("Invalid repository or workflow name — could not build URL from: \(dispatchURLString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.githubToken)",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json",
                         forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28",
                         forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any] = [
            "ref": settings.githubRef,
            "inputs": ["duration_minutes": String(settings.sessionDurationMinutes)]
        ]
        if let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict),
           let bodyStr = String(data: bodyData, encoding: .utf8) {
            logger.log("Dispatch request body: \(bodyStr)", category: "Remote")
            request.httpBody = bodyData
        }

        dispatchTimestamp = Date()
        logger.log("Dispatch timestamp: \(dispatchTimestamp!)", category: "Remote")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.logger.log("Dispatch network error: \(error) (domain=\((error as NSError).domain) code=\((error as NSError).code))", category: "Remote", level: .error)
                self.setError("Network error: \(error.localizedDescription)")
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let headers = http?.allHeaderFields as? [String: String] ?? [:]
            self.logger.log("Dispatch response HTTP \(status)", category: "Remote")
            self.logger.log("Dispatch response headers: \(headers.filter { ["x-github-request-id", "x-ratelimit-remaining", "content-type"].contains($0.key.lowercased()) })", category: "Remote")
            if let data, let body = String(data: data, encoding: .utf8), !body.isEmpty {
                self.logger.log("Dispatch response body: \(body)", category: "Remote")
            }
            if status == 204 {
                self.logger.log("Workflow dispatched successfully — waiting for tunnel URL", category: "Remote")
                self.setState(.waitingForURL)
                DispatchQueue.main.async { self.startPollingForTunnelURL() }
            } else {
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(no body)"
                self.setError("GitHub API responded \(status): \(bodyStr)")
            }
        }.resume()
    }

    // MARK: - Step 2: Poll .tunnel-url from repo contents

    private var pollCount = 0

    private func startPollingForTunnelURL() {
        pollCount = 0
        
        // Always check for URL change (we now always have a baseline from fetchCurrentURLAsBaseline)
        if let previousURL = previousTunnelURL {
            logger.log("Starting URL change detection — will poll until URL changes from: \(previousURL.absoluteString)", category: "Remote")
            urlChangePollingStartTime = Date()
            startURLChangePolling()
        } else {
            // Fallback: no baseline was found, proceed with normal polling
            logger.log("No baseline URL found; starting normal poll loop for .tunnel-url (every 6 s)", category: "Remote")
            fetchTunnelURL()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
                self?.fetchTunnelURL()
            }
        }
    }

    private func startURLChangePolling() {
        urlChangePollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForURLChange()
        }
        // Check immediately
        checkForURLChange()
    }

    private func checkForURLChange() {
        let settings = RemoteSettings.shared
        
        guard let previousURL = previousTunnelURL else {
            logger.log("Previous URL was cleared; starting normal polling", category: "Remote")
            stopURLChangePolling()
            startNormalPolling()
            return
        }

        // Check timeout (1 minute)
        if let startTime = urlChangePollingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > urlChangeTimeout {
                logger.log("URL change detection timeout after \(String(format: "%.1f", elapsed))s — URL did not change from: \(previousURL.absoluteString)", category: "Remote", level: .error)
                stopURLChangePolling()
                setError("Timeout waiting for server to generate new tunnel URL. The server may not have restarted properly.")
                return
            }
        }

        let pollURLString = "https://api.github.com/repos/\(settings.githubRepo)/contents/.tunnel-url"

        guard let url = URL(string: pollURLString) else {
            logger.log("Could not build poll URL from: \(pollURLString)", category: "Remote", level: .error)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.githubToken)",   forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json",      forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28",                       forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let base64Content = json["content"] as? String else {
                return
            }

            let stripped = base64Content.replacingOccurrences(of: "\n", with: "")
            guard let decoded = Data(base64Encoded: stripped),
                  let rawURL = String(data: decoded, encoding: .utf8)
                                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                  !rawURL.isEmpty,
                  let currentURL = URL(string: rawURL) else {
                return
            }

            // Check if URL has changed
            if currentURL.absoluteString != previousURL.absoluteString {
                let elapsed = Date().timeIntervalSince(self.urlChangePollingStartTime ?? Date())
                self.logger.log("✅ URL changed to new value after \(String(format: "%.1f", elapsed))s — proceeding with new URL: \(rawURL)", category: "Remote")
                self.stopURLChangePolling()
                
                // Now proceed with normal polling using the new URL
                DispatchQueue.main.async {
                    self.previousTunnelURL = nil
                }
                self.startNormalPolling()
            }
        }.resume()
    }

    private func stopURLChangePolling() {
        urlChangePollingTimer?.invalidate()
        urlChangePollingTimer = nil
        urlChangePollingStartTime = nil
    }

    private func startNormalPolling() {
        logger.log("Starting poll loop for .tunnel-url (every 6 s)", category: "Remote")
        pollCount = 0
        fetchTunnelURL()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.fetchTunnelURL()
        }
    }

    private func fetchTunnelURL() {
        let settings = RemoteSettings.shared
        pollCount += 1
        let pollURLString = "https://api.github.com/repos/\(settings.githubRepo)/contents/.tunnel-url"
        logger.log("Poll #\(pollCount) → GET \(pollURLString)", category: "Remote")

        guard let url = URL(string: pollURLString) else {
            logger.log("Could not build poll URL from: \(pollURLString)", category: "Remote", level: .error)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.githubToken)",   forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json",      forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28",                       forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.logger.log("Poll #\(self.pollCount) network error: \(error.localizedDescription)", category: "Remote", level: .warning)
                return
            }

            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            self.logger.log("Poll #\(self.pollCount) HTTP \(status)", category: "Remote")

            guard let data else {
                self.logger.log("Poll #\(self.pollCount) — no data in response", category: "Remote", level: .warning)
                return
            }

            // Log raw response for debugging
            if let rawStr = String(data: data, encoding: .utf8) {
                let preview = String(rawStr.prefix(300)).replacingOccurrences(of: "\n", with: " ")
                self.logger.log("Poll #\(self.pollCount) raw body (first 300 chars): \(preview)", category: "Remote")
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.logger.log("Poll #\(self.pollCount) — response is not valid JSON; not ready yet", category: "Remote")
                return
            }

            guard let base64Content = json["content"] as? String else {
                // GitHub returns 404 with {message: "Not Found"} until file exists
                let msg = json["message"] as? String ?? "(no message field)"
                self.logger.log("Poll #\(self.pollCount) — no 'content' field; message=\(msg) — not ready yet", category: "Remote")
                return
            }

            self.logger.log("Poll #\(self.pollCount) — content field present (\(base64Content.count) chars b64)", category: "Remote")

            // Check commit timestamp vs our dispatch time
            let fileIsStale = self.isFileStale(json: json)
            
            if fileIsStale {
                self.logger.log("Poll #\(self.pollCount) — file failed freshness check; skipping stale file", category: "Remote", level: .warning)
                return
            }

            // Decode Base64 (GitHub pads with newlines)
            let stripped = base64Content.replacingOccurrences(of: "\n", with: "")
            self.logger.log("Poll #\(self.pollCount) — stripped b64 (\(stripped.count) chars): \(String(stripped.prefix(60)))", category: "Remote")

            guard let decoded = Data(base64Encoded: stripped) else {
                self.logger.log("Poll #\(self.pollCount) — Base64 decode failed on stripped content", category: "Remote", level: .error)
                return
            }

            guard let rawURL = String(data: decoded, encoding: .utf8)
                                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                  !rawURL.isEmpty else {
                self.logger.log("Poll #\(self.pollCount) — decoded bytes could not be read as UTF-8 string", category: "Remote", level: .error)
                return
            }

            self.logger.log("Poll #\(self.pollCount) — decoded URL string: '\(rawURL)'", category: "Remote")

            guard let tunnelURL = URL(string: rawURL) else {
                self.logger.log("Poll #\(self.pollCount) — URL(string:) rejected '\(rawURL)'", category: "Remote", level: .error)
                return
            }

            self.logger.log("Tunnel URL ready: \(rawURL)  scheme=\(tunnelURL.scheme ?? "nil")  host=\(tunnelURL.host ?? "nil")", category: "Remote")
            self.pollTimer?.invalidate()
            self.pollTimer = nil

            DispatchQueue.main.async {
                self.tunnelURL = tunnelURL
                // Record when this URL was generated
                settings.tunnelURLTimestamp = Date()
            }
            self.connectAsAgent(tunnelURL: tunnelURL)
        }.resume()
    }

    /// Validates if a fetched file is stale by checking:
    /// 1. Commit timestamp against dispatch time (if available)
    /// 2. Maximum age since dispatch (strict fallback validation)
    private func isFileStale(json: [String: Any]) -> Bool {
        guard let dispatchTime = dispatchTimestamp else { return false }

        // Try to get precise commit timestamp
        if let committerRaw = (json["commit"] as? [String: Any])?["committer"] as? [String: Any],
           let dateStr = committerRaw["date"] as? String {
            self.logger.log("Poll #\(self.pollCount) — commit date: \(dateStr)", category: "Remote")
            let formatter = ISO8601DateFormatter()
            if let commitDate = formatter.date(from: dateStr) {
                if commitDate < dispatchTime {
                    self.logger.log("Poll #\(self.pollCount) — commit (\(dateStr)) predates dispatch (\(dispatchTime)) — file is stale", category: "Remote")
                    return true
                } else {
                    self.logger.log("Poll #\(self.pollCount) — commit is fresh (commit \(dateStr) >= dispatch \(dispatchTime))", category: "Remote")
                    return false
                }
            }
        }

        // Fallback: if we can't verify commit timestamp, use strict age limit
        let now = Date()
        let ageSeconds = now.timeIntervalSince(dispatchTime)
        self.logger.log("Poll #\(self.pollCount) — no commit.committer.date field; applying strict age limit (max \(Int(self.maxTunnelURLAge))s)", category: "Remote")

        if ageSeconds > self.maxTunnelURLAge {
            self.logger.log("Poll #\(self.pollCount) — file is too old (\(String(format: "%.1f", ageSeconds))s > \(Int(self.maxTunnelURLAge))s limit) — rejecting", category: "Remote")
            return true
        }

        self.logger.log("Poll #\(self.pollCount) — file age is acceptable (\(String(format: "%.1f", ageSeconds))s)", category: "Remote")
        return false
    }

    // MARK: - Step 3: Connect WebSocket as /agent

    private func connectAsAgent(tunnelURL: URL) {
        logger.log("connectAsAgent — input URL: \(tunnelURL)  scheme=\(tunnelURL.scheme ?? "nil")  host=\(tunnelURL.host ?? "nil")  port=\(tunnelURL.port.map(String.init) ?? "default")", category: "Remote")

        guard var components = URLComponents(url: tunnelURL, resolvingAgainstBaseURL: false) else {
            setError("URLComponents could not parse tunnel URL: \(tunnelURL)")
            return
        }

        let originalScheme = components.scheme ?? "https"
        components.scheme = originalScheme == "https" ? "wss" : "ws"
        components.path   = "/agent"

        logger.log("WebSocket components — scheme: \(components.scheme ?? "nil")  host: \(components.host ?? "nil")  path: \(components.path ?? "nil")", category: "Remote")

        guard let wsURL = components.url else {
            setError("Could not build WebSocket URL from components: \(components)")
            return
        }

        logger.log("Opening WebSocket → \(wsURL.absoluteString)", category: "Remote")
        var wsRequest = URLRequest(url: wsURL)
        wsRequest.timeoutInterval = 30
        webSocketTask = urlSession.webSocketTask(with: wsRequest)
        webSocketTask?.resume()
        logger.log("WebSocket task resumed — state: \(webSocketTask?.state.rawValue ?? -1)", category: "Remote")
        setState(.connected)
        receiveNext()
    }

    // MARK: - Receive loop

    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s):  self.logger.log("WS ← text (\(s.count) chars)", category: "Remote")
                case .data(let d):    self.logger.log("WS ← binary (\(d.count) bytes)", category: "Remote")
                @unknown default:     break
                }
                self.dispatch(message)
                if self.state == .connected { self.receiveNext() }
            case .failure(let error):
                let nsErr = error as NSError
                self.logger.log("WS receive failed — domain=\(nsErr.domain)  code=\(nsErr.code)  desc=\(nsErr.localizedDescription)  task-state=\(self.webSocketTask?.state.rawValue ?? -1)", category: "Remote", level: .error)
                if self.state == .connected {
                    self.setError("Connection lost: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Message dispatch

    private func dispatch(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleBinaryFrame(data)
        case .string(let text):
            handleTextFrame(text)
        @unknown default:
            break
        }
    }

    /// Binary CH9329 frame — forward verbatim to BLE; no decode needed.
    private func handleBinaryFrame(_ data: Data) {
        guard data.count >= 4, data[0] == 0x57, data[1] == 0xAB else {
            logger.log("Non-CH9329 binary frame ignored (len=\(data.count))", category: "Remote", level: .warning)
            return
        }
        keyboardManager?.bleManager.sendTouchData(data: data)
    }

    /// Text frame: JSON with `type` field, or raw ANSI escape sequence.
    private func handleTextFrame(_ text: String) {
        if let jsonData = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let type = json["type"] as? String {
            // Structured JSON message
            switch type {
            case "key":
                if let key = json["key"] as? String { handleRemoteKey(key) }
            case "mouse_move":
                let dx = json["dx"] as? Int ?? 0
                let dy = json["dy"] as? Int ?? 0
                if dx != 0 || dy != 0 {
                    DispatchQueue.main.async {
                        self.mouseManager?.sendRelativeMove(dx: dx, dy: dy, buttons: 0x00)
                    }
                }
            case "mouse_click":
                let button = json["button"] as? Int ?? 1
                let action = json["action"] as? String ?? "press"
                DispatchQueue.main.async {
                    self.mouseManager?.sendButtonEvent(button: button, pressed: action == "press")
                }
            case "mouse_scroll":
                let dx = json["dx"] as? Int ?? 0
                let dy = json["dy"] as? Int ?? json["delta"] as? Int ?? 0
                DispatchQueue.main.async {
                    self.mouseManager?.handleScroll(deltaX: dx, deltaY: dy)
                }
            default:
                logger.log("Unknown message type: \(type)", category: "Remote", level: .warning)
            }
        } else {
            // Raw character / ANSI escape sequence from xterm.js
            handleRemoteKey(text)
        }
    }

    // MARK: - Key event translation

    private func handleRemoteKey(_ raw: String) {
        // 1. Named escape sequence (Up, Down, F1…)
        if let name = escapeKeyMap[raw] {
            DispatchQueue.main.async { self.keyboardManager?.handleKeyPress(name) }
            return
        }

        // 2. Ctrl+letter (\x01–\x1a)
        if raw.count == 1, let scalar = raw.unicodeScalars.first {
            let v = scalar.value
            if v >= 0x01 && v <= 0x1a, let letter = UnicodeScalar(v + 0x60) {
                let letterStr = String(letter).uppercased()
                DispatchQueue.main.async {
                    self.keyboardManager?.activeModifiers.insert("Ctrl")
                    self.keyboardManager?.handleKeyPress(letterStr)
                    self.keyboardManager?.activeModifiers.remove("Ctrl")
                }
                return
            }
        }

        // 3. Single printable character or multi-char text — delegate to
        //    handleTextInput which does its own BLE-paced loop internally.
        DispatchQueue.global(qos: .userInitiated).async {
            self.keyboardManager?.handleTextInput(raw)
        }
    }

    // MARK: - Helpers

    private func setState(_ newState: RemoteSessionState) {
        DispatchQueue.main.async { self.state = newState }
    }

    private func setError(_ message: String) {
        logger.log(message, category: "Remote", level: .error)
        setState(.error(message))
    }
}
