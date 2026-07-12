import UIKit
import SwiftTerm

/// Bridge between SwiftTerm (UIKit) and SSHClient.
/// Handles terminal emulation and bidirectional data flow between:
///   - SSH output → terminal.feed() → rendered on screen
///   - User keystrokes → terminalViewDelegate.send() → SSHClient.write()
class TerminalEmulator: NSObject, TerminalViewDelegate {

    // MARK: - Properties

    private weak var terminalView: TerminalView?
    let sshClient: SSHClient

    /// Callback for connection status changes
    var onStatusChanged: ((ConnectionStatus) -> Void)?

    /// Current connection status
    private(set) var status: ConnectionStatus = .disconnected {
        didSet {
            onStatusChanged?(status)
        }
    }

    // MARK: - Connection Profile

    struct ConnectionProfile {
        let host: String
        let port: Int
        let username: String
        let password: String
    }

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Init

    override init() {
        // SSHClient host/port are unused now — bridge creates its own TCP socket.
        self.sshClient = SSHClient(host: "127.0.0.1", port: 0, username: "", password: "")
        super.init()

        // Wire SSHClient output → terminal.feed()
        sshClient.onOutput = { [weak self] data in
            self?.feedTerminal(data: data)
        }

        sshClient.onError = { [weak self] error in
            self?.status = .error(error)
        }
    }

    /// Attach to a SwiftTerm TerminalView
    func attach(to terminalView: TerminalView) {
        LogManager.shared.log("attach() to TerminalView — setting delegate", category: "Terminal", level: .info)
        self.terminalView = terminalView
        terminalView.terminalDelegate = self

        // Set up terminal appearance — use system colors that adapt to light/dark mode
        let bgColor = UIColor.systemBackground
        let fgColor = UIColor.label
        terminalView.backgroundColor = bgColor
        terminalView.nativeBackgroundColor = bgColor
        terminalView.nativeForegroundColor = fgColor
        let fontSize = TerminalPrefs.shared.fontSize
        terminalView.font = UIFont(name: "Menlo", size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Set initial terminal size
        let frameSize = terminalView.getOptimalFrameSize()
        let cols = max(Int(frameSize.width / 8.4), 80)
        let rows = max(Int(frameSize.height / 18), 24)
        LogManager.shared.log("attach() initial size: \(cols)x\(rows)", category: "Terminal", level: .info)
        sshClient.resizeTerminal(width: cols, height: rows)
    }

    /// Connect to remote host via BLE-Eth transport
    func connect(profile: ConnectionProfile, transport: BleEthTransport, bridge: POSIXSocketBridge) async throws {
        status = .connecting
        print("[TerminalEmulator] connect() starting — host=\(profile.host) port=\(profile.port) user=\(profile.username)")

        // Update SSHClient with real credentials from the profile
        sshClient.setCredentials(username: profile.username, password: profile.password)

        // Pass the pre-created bridge to SSHClient
        print("[TerminalEmulator] calling sshClient.connect(transport:bridge:)")
        sshClient.connect(transport: transport, bridge: bridge)

        // Wait for connection (with timeout)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                // Check every 100ms for up to 30 seconds
                for i in 0..<300 {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    if self.sshClient.isConnected {
                        print("[TerminalEmulator] SSH connected after ~\((i+1)*100)ms")
                        self.status = .connected
                        continuation.resume()
                        return
                    }

                    if case .error(let msg) = self.status {
                        print("[TerminalEmulator] SSH error detected at ~\((i+1)*100)ms: \(msg)")
                        continuation.resume(throwing: NSError(domain: "SSH", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
                        return
                    }
                }
                print("[TerminalEmulator] SSH connect timeout after 30s")
                continuation.resume(throwing: NSError(domain: "SSH", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
            }
        }
    }

    /// Disconnect SSH session
    func disconnect() {
        sshClient.disconnect()
        status = .disconnected
    }

    /// Clear the terminal screen and scrollback (called before a new connection).
    func clearScreen() {
        DispatchQueue.main.async { [weak self] in
            self?.terminalView?.getTerminal().resetToInitialState()
        }
    }

    /// Feed data from SSH to terminal
    private func feedTerminal(data: Data) {
        LogManager.shared.log("feedTerminal() \(data.count) bytes, terminalView is \(terminalView != nil ? "attached" : "NIL")", category: "Terminal", level: .debug)
        LogManager.shared.log("feedTerminal() raw bytes: \(data.hexString)", category: "Terminal", level: .debug)
        DispatchQueue.main.async { [weak self] in
            let bytes = ArraySlice<UInt8>(data)
            guard let tv = self?.terminalView else {
                LogManager.shared.log("feedTerminal() terminalView is NIL — data DROPPED", category: "Terminal", level: .error)
                return
            }
            tv.feed(byteArray: bytes)
            LogManager.shared.log("feedTerminal() fed \(bytes.count) bytes to TerminalView — rendering OK", category: "Terminal", level: .debug)
        }
    }

    // MARK: - TerminalViewDelegate

    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Terminal size changed - inform SSH
        sshClient.resizeTerminal(width: newCols, height: newRows)
    }

    public func setTerminalTitle(source: TerminalView, title: String) {
        // Could update UI title bar
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Handle cwd change
    }

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // User typed something → forward to SSH
        let data = Data(data)
        LogManager.shared.log("send() \(data.count) bytes from terminal: \(data.hexString)", category: "Terminal", level: .debug)
        sshClient.write(data)
    }

    public func scrolled(source: TerminalView, position: Double) {
        // Handle scroll
    }

    public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
        // Open URL if tapped
    }

    public func bell(source: TerminalView) {
        // Play bell sound / haptic
    }

    public func clipboardCopy(source: TerminalView, content: Data) {
        // Copy to clipboard
    }

    public func clipboardRead(source: TerminalView) -> Data? {
        // Read from clipboard
        return nil
    }

    public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        // Handle iTerm2 specific features
    }

    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // Visual update range
    }
}
