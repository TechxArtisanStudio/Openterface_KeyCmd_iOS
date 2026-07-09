import Foundation
import Network
import CSSH

/// SSH client implementation using libssh2 C library
/// Handles SSH connection, authentication, and channel management over BLE-Eth transport
class SSHClient {
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var transport: BleEthTransport?
    private var bridge: POSIXSocketBridge?

    private let host: String
    private let port: Int
    private var username: String
    private var password: String

    private let sshQueue = DispatchQueue(label: "ssh.client.queue", qos: .userInitiated)

    // Connection state
    private(set) var isConnected = false
    var onOutput: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    init(host: String, port: Int = 22, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// Update credentials before connecting
    func setCredentials(username: String, password: String) {
        self.username = username
        self.password = password
    }

    deinit {
        disconnect()
    }

    /// Connect to SSH server through BLE-Eth transport using a pre-created bridge
    func connect(transport: BleEthTransport, bridge: POSIXSocketBridge) {
        self.transport = transport
        self.bridge = bridge
        LogManager.shared.log("SSH: connect() called, transport isConnected=\(transport.isConnected), bridge libssh2Fd=\(bridge.libssh2Fd)", category: "SSH", level: .info)

        sshQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                LogManager.shared.log("SSH: using pre-created bridge, libssh2Fd=\(bridge.libssh2Fd)", category: "SSH", level: .info)
                try self.performConnect(socketFd: bridge.libssh2Fd)
            } catch {
                LogManager.shared.log("SSH: connect failed: \(error.localizedDescription)", category: "SSH", level: .error)
                self.onError?("Connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func performConnect(socketFd: Int32) throws {
        let log = LogManager.shared
        log.log("SSH: performConnect starting (socketFd=\(socketFd))", category: "SSH", level: .info)

        // Initialize libssh2
        guard libssh2_init(0) == 0 else {
            log.log("SSH: libssh2_init failed", category: "SSH", level: .error)
            throw SSHError.initializationFailed
        }
        log.log("SSH: libssh2_init ok", category: "SSH", level: .debug)

        // Create session
        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            log.log("SSH: session_init_ex returned nil", category: "SSH", level: .error)
            throw SSHError.sessionInitFailed
        }
        self.session = session
        log.log("SSH: session created", category: "SSH", level: .debug)

        // Configure session preferences
        configureSessionPreferences(session)
        log.log("SSH: session preferences configured", category: "SSH", level: .debug)

        // Set non-blocking mode
        libssh2_session_set_blocking(session, 0)

        // Perform handshake over the bridge socket (non-blocking with retry loop)
        log.log("SSH: starting handshake (socketFd=\(socketFd))", category: "SSH", level: .info)
        var handshakeResult = libssh2_session_handshake(session, socketFd)
        var attempts = 0
        while handshakeResult == LIBSSH2_ERROR_EAGAIN && attempts < 300 {
            waitForSocket(socketFd, session: session)
            attempts += 1
            handshakeResult = libssh2_session_handshake(session, socketFd)
        }
        let handshakeErrno = libssh2_session_last_errno(session)
        log.log("SSH: handshake returned \(handshakeResult) after \(attempts) retries, errno=\(handshakeErrno)",
                category: "SSH", level: handshakeResult == 0 ? .debug : .error)
        if handshakeResult != 0 {
            var detail = "SSH handshake failed (error code: \(handshakeErrno))"
            if let msg = lastSessionErrorString(session) {
                detail += " — \(msg)"
            }
            throw SSHError.handshakeFailed(code: handshakeErrno, detail: detail)
        }

        // Get server banner
        if let banner = libssh2_session_banner_get(session) {
            let bannerStr = String(cString: banner)
            log.log("SSH: server banner: \(bannerStr)", category: "SSH", level: .info)
        }

        // Authenticate (with EAGAIN retry)
        log.log("SSH: authenticating as user=\(username)", category: "SSH", level: .info)
        let authResult = retryEAGAIN(session: session, socketFd: socketFd) {
            libssh2_userauth_password_ex(session, username, UInt32(strlen(username)),
                                         password, UInt32(strlen(password)), nil)
        }
        let authErrno = libssh2_session_last_errno(session)
        log.log("SSH: auth returned \(authResult), errno=\(authErrno)", category: "SSH", level: authResult == 0 ? .debug : .error)
        if authResult != 0 {
            if let msg = lastSessionErrorString(session) {
                log.log("SSH: auth last_error: \(msg)", category: "SSH", level: .error)
            }
            throw SSHError.authenticationFailed(code: authErrno)
        }
        log.log("SSH: auth ok", category: "SSH", level: .debug)

        // Open channel (with EAGAIN retry)
        log.log("SSH: opening channel", category: "SSH", level: .info)
        var channel: OpaquePointer?
        var channelAttempts = 0
        while channelAttempts < 300 {
            channel = libssh2_channel_open_ex(session, "session", 7, 2*1024*1024, 32768, nil, 0)
            if channel != nil { break }
            let err = libssh2_session_last_errno(session)
            guard err == LIBSSH2_ERROR_EAGAIN else { break }
            waitForSocket(socketFd, session: session)
            channelAttempts += 1
        }
        guard let channel = channel else {
            let lastError = libssh2_session_last_errno(session)
            if let msg = lastSessionErrorString(session) {
                log.log("SSH: channel open last_error: \(msg)", category: "SSH", level: .error)
            }
            log.log("SSH: channel open failed, errno=\(lastError)", category: "SSH", level: .error)
            throw SSHError.channelOpenFailed(code: lastError)
        }
        self.channel = channel
        log.log("SSH: channel open ok", category: "SSH", level: .debug)

        // Request PTY with xterm-256color (with EAGAIN retry)
        let termType = "xterm-256color"
        log.log("SSH: requesting PTY \(termType) 80x24", category: "SSH", level: .info)
        let ptyResult = retryEAGAIN(session: session, socketFd: socketFd) {
            libssh2_channel_request_pty_ex(channel, termType, UInt32(strlen(termType)),
                                           nil, 0, 80, 24, 0, 0)
        }
        log.log("SSH: PTY request returned \(ptyResult)", category: "SSH", level: ptyResult == 0 ? .debug : .error)
        if ptyResult != 0 { throw SSHError.ptyRequestFailed }

        // Request shell (with EAGAIN retry)
        log.log("SSH: requesting shell", category: "SSH", level: .info)
        let shellResult = retryEAGAIN(session: session, socketFd: socketFd) {
            libssh2_channel_process_startup(channel, "shell", 5, nil, 0)
        }
        log.log("SSH: shell request returned \(shellResult)", category: "SSH", level: shellResult == 0 ? .debug : .error)
        if shellResult != 0 { throw SSHError.shellRequestFailed }

        isConnected = true
        log.log("SSH: fully connected, starting output reader", category: "SSH", level: .success)

        // Start reading output
        startReadingOutput()

        // After shell is up, send a small "probe" by reading once to confirm channel is alive
        log.log("SSH: connection complete — auth OK, PTY requested, shell started. Awaiting remote data.", category: "SSH", level: .info)
    }

    private func configureSessionPreferences(_ session: OpaquePointer) {
        // Set timeout
        libssh2_session_set_timeout(session, 30000) // 30 seconds

        // Configure key exchange
        let kexAlgorithms = "curve25519-sha256,diffie-hellman-group14-sha256,diffie-hellman-group14-sha1"
        libssh2_session_method_pref(session, LIBSSH2_METHOD_KEX, kexAlgorithms)

        // Configure host key
        let hostKeyAlgorithms = "ssh-ed25519,ecdsa-sha2-nistp256,ssh-rsa"
        libssh2_session_method_pref(session, LIBSSH2_METHOD_HOSTKEY, hostKeyAlgorithms)

        // Configure encryption (client to server)
        let cryptCS = "aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
        libssh2_session_method_pref(session, LIBSSH2_METHOD_CRYPT_CS, cryptCS)

        // Configure encryption (server to client)
        libssh2_session_method_pref(session, LIBSSH2_METHOD_CRYPT_SC, cryptCS)

        // Configure MAC (client to server)
        let macCS = "hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256"
        libssh2_session_method_pref(session, LIBSSH2_METHOD_MAC_CS, macCS)

        // Configure MAC (server to client)
        libssh2_session_method_pref(session, LIBSSH2_METHOD_MAC_SC, macCS)

        // Configure compression
        let compression = "none,zlib@openssh.com"
        libssh2_session_method_pref(session, LIBSSH2_METHOD_COMP_CS, compression)
        libssh2_session_method_pref(session, LIBSSH2_METHOD_COMP_SC, compression)
    }

    private func startReadingOutput() {
        // Use a global concurrent queue — the serial sshQueue can't host an infinite loop
        LogManager.shared.log("SSH: output reader starting", category: "SSH", level: .info)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let channel = self.channel else {
                LogManager.shared.log("SSH: output reader — channel nil, exiting", category: "SSH", level: .error)
                return
            }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var eagainCount = 0

            while self.isConnected {
                let bytesRead = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)

                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    LogManager.shared.log("SSH: channel read \(bytesRead) bytes (total eagain=\(eagainCount)) hex=\(data.hexString)", category: "SSH", level: .debug)
                    eagainCount = 0
                    self.onOutput?(data)
                } else if bytesRead == 0 {
                    // Channel closed
                    LogManager.shared.log("SSH: channel closed (read returned 0)", category: "SSH", level: .info)
                    break
                } else if bytesRead < 0 {
                    let errorCode = libssh2_session_last_errno(self.session)
                    if errorCode == LIBSSH2_ERROR_EAGAIN {
                        eagainCount += 1
                        if eagainCount == 1 || eagainCount % 500 == 0 {
                            LogManager.shared.log("SSH: channel read EAGAIN (no data yet, poll #\(eagainCount))", category: "SSH", level: .debug)
                        }
                        // Non-blocking mode, no data available yet
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    } else {
                        // Error
                        LogManager.shared.log("SSH: channel read error \(errorCode)", category: "SSH", level: .error)
                        self.onError?("Read error: \(errorCode)")
                        break
                    }
                }
            }
            LogManager.shared.log("SSH: output reader exited", category: "SSH", level: .info)
        }
    }

    /// Write data to SSH channel
    func write(_ data: Data) {
        guard let channel = self.channel, isConnected else {
            LogManager.shared.log("SSH: write() dropped — channel=\(channel != nil) connected=\(isConnected)", category: "SSH", level: .warning)
            return
        }
        LogManager.shared.log("SSH: write() \(data.count) bytes — queueing to sshQueue", category: "SSH", level: .debug)

        sshQueue.async { [weak self] in
            guard let self = self else {
                LogManager.shared.log("SSH: write async — self is nil", category: "SSH", level: .error)
                return
            }
            LogManager.shared.log("SSH: write async block executing", category: "SSH", level: .info)

            data.withUnsafeBytes { bufferPointer in
                guard let baseAddress = bufferPointer.baseAddress else {
                    LogManager.shared.log("SSH: write baseAddress is nil", category: "SSH", level: .error)
                    return
                }
                let bytesToWrite = baseAddress.assumingMemoryBound(to: Int8.self)

                var totalWritten = 0
                while totalWritten < data.count {
                    let bytesWritten = libssh2_channel_write_ex(
                        channel,
                        0,
                        bytesToWrite.advanced(by: totalWritten),
                        data.count - totalWritten
                    )

                    if bytesWritten < 0 {
                        let errorCode = libssh2_session_last_errno(self.session)
                        if errorCode == LIBSSH2_ERROR_EAGAIN {
                            // Non-blocking mode, retry
                            LogManager.shared.log("SSH: write EAGAIN — retrying", category: "SSH", level: .info)
                            Thread.sleep(forTimeInterval: 0.01)
                            continue
                        } else {
                            LogManager.shared.log("SSH: write error \(errorCode)", category: "SSH", level: .error)
                            self.onError?("Write error: \(errorCode)")
                            break
                        }
                    } else {
                        totalWritten += bytesWritten
                        LogManager.shared.log("SSH: wrote \(bytesWritten) bytes (total \(totalWritten)/\(data.count))", category: "SSH", level: .debug)
                    }
                }
            }
        }
    }

    /// Write string to SSH channel
    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }

    /// Disconnect SSH session
    func disconnect() {
        sshQueue.async { [weak self] in
            guard let self = self else { return }

            self.isConnected = false

            if let channel = self.channel {
                libssh2_channel_free(channel)
                self.channel = nil
            }

            if let session = self.session {
                libssh2_session_disconnect_ex(session, 11, "Client disconnecting", "")
                libssh2_session_free(session)
                self.session = nil
            }

            self.bridge?.stop()
            self.bridge = nil

            // NOTE: Do NOT call libssh2_exit() here — it tears down global state
            // and causes issues on reconnect. libssh2_init() is ref-counted, so
            // repeated calls are safe. libssh2_exit() should only be called on
            // app termination.
        }
    }

    /// Wait for socket to be ready for reading and/or writing based on libssh2's block directions.
    private func waitForSocket(_ socketFd: Int32, session: OpaquePointer) {
        let dirs = libssh2_session_block_directions(session)
        var events: Int16 = 0
        if (dirs & LIBSSH2_SESSION_BLOCK_INBOUND)  != 0 { events |= Int16(POLLIN) }
        if (dirs & LIBSSH2_SESSION_BLOCK_OUTBOUND) != 0 { events |= Int16(POLLOUT) }
        if events == 0 { events = Int16(POLLIN) }  // default: wait for readable

        var pfd = pollfd(fd: socketFd, events: events, revents: 0)
        let rc = poll(&pfd, 1, 1000)  // 1s timeout
        if rc < 0 && errno != EINTR {
            LogManager.shared.log("SSH: poll() failed errno=\(errno)", category: "SSH", level: .error)
        }
    }

    /// Retry a libssh2 call while it returns LIBSSH2_ERROR_EAGAIN.
    private func retryEAGAIN(session: OpaquePointer, socketFd: Int32, maxAttempts: Int = 300,
                             _ body: () -> Int32) -> Int32 {
        var result = body()
        var attempts = 0
        while result == LIBSSH2_ERROR_EAGAIN && attempts < maxAttempts {
            waitForSocket(socketFd, session: session)
            result = body()
            attempts += 1
        }
        return result
    }

    /// Extract the last error string from a libssh2 session (output param pattern).
    private func lastSessionErrorString(_ session: OpaquePointer) -> String? {
        var errPtr: UnsafeMutablePointer<CChar>? = nil
        let rc = libssh2_session_last_error(session, &errPtr, nil, 0)
        guard rc != 0, let ptr = errPtr else { return nil }
        return String(cString: ptr)
    }
}

// MARK: - POSIXSocketBridge

/// socketpair bridge: libssh2 ↔ socket fd ↔ BleEthTransport.
/// libssh2 gets one fd, bridge pumps the other: socket→BLE and BLE→socket.
final class POSIXSocketBridge: TransportListener {

    private let logger = LogManager.shared
    private(set) var libssh2Fd: Int32 = -1
    private var bridgeFd: Int32 = -1
    private weak var transport: BleEthTransport?
    private var readerTask: Task<Void, Never>?
    private var stopped = false

    init() {}
    deinit { stop() }

    func start(transport: BleEthTransport) throws {
        var fds = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            logger.log("Bridge: socketpair() failed errno=\(errno)", category: "Bridge", level: .error)
            throw NSError(domain: "POSIXSocketBridge", code: Int(errno))
        }
        libssh2Fd = fds[0]
        bridgeFd = fds[1]
        self.transport = transport
        transport.listener = self
        logger.log("Bridge: socketpair (libssh2Fd=\(libssh2Fd), bridgeFd=\(bridgeFd))",
                   category: "Bridge", level: .info)
        startSocketReader()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        readerTask?.cancel(); readerTask = nil
        if bridgeFd >= 0 { shutdown(bridgeFd, Int32(SHUT_RDWR)); close(bridgeFd); bridgeFd = -1 }
        if libssh2Fd >= 0 { close(libssh2Fd); libssh2Fd = -1 }
    }

    private func startSocketReader() {
        logger.log("Bridge: starting socket reader task", category: "Bridge", level: .info)
        readerTask = Task.detached { [weak self] in
            guard let self, self.bridgeFd >= 0 else { return }
            // ponytail: 246-byte cap = MAX_FRAG_DATA, single fragment per send
            var buf = [UInt8](repeating: 0, count: DataReassembler.MAX_FRAG_DATA)
            while !Task.isCancelled {
                let n = Darwin.read(self.bridgeFd, &buf, buf.count)
                if n > 0 {
                    self.logger.log("Bridge: socket reader got \(n) bytes → transport.send()", category: "Bridge", level: .debug)
                    self.transport?.send(data: Data(bytes: buf, count: n))
                } else if n == 0 {
                    self.logger.log("Bridge: socket EOF", category: "Bridge", level: .info); break
                } else {
                    if errno != EINTR {
                        self.logger.log("Bridge: socket read error errno=\(errno)", category: "Bridge", level: .error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - TransportListener

    func onDataReceived(data: Data) {
        guard bridgeFd >= 0 else {
            logger.log("Bridge: onDataReceived but bridgeFd<0 — dropping \(data.count) bytes", category: "Bridge", level: .warning)
            return
        }
        logger.log("Bridge: onDataReceived \(data.count) bytes → writing to bridgeFd=\(bridgeFd)", category: "Bridge", level: .debug)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let written = Darwin.write(bridgeFd, base, data.count)
            if written < 0 {
                logger.log("Bridge: socket write error errno=\(errno), attempted=\(data.count) bytes", category: "Bridge", level: .error)
            } else if written != data.count {
                logger.log("Bridge: socket write partial — expected=\(data.count), wrote=\(written) bytes", category: "Bridge", level: .warning)
            } else {
                logger.log("Bridge: socket write OK \(data.count) bytes: \(data.hexString)", category: "Bridge", level: .debug)
            }
        }
    }
    func onDisconnected() { logger.log("Bridge: transport disconnected", category: "Bridge", level: .info); stop() }
    func onError(message: String) { logger.log("Bridge: transport error: \(message)", category: "Bridge", level: .error) }
}

extension SSHClient {
    /// Resize terminal window
    func resizeTerminal(width: Int, height: Int) {
        guard let channel = self.channel, isConnected else { return }
        sshQueue.async { [weak self] in
            guard self != nil else { return }
            libssh2_channel_request_pty_size_ex(channel, Int32(width), Int32(height), 0, 0)
        }
    }
}

// MARK: - SSH Errors
enum SSHError: Error, LocalizedError {
    case initializationFailed
    case sessionInitFailed
    case handshakeFailed(code: Int32, detail: String? = nil)
    case authenticationFailed(code: Int32)
    case channelOpenFailed(code: Int32)
    case ptyRequestFailed
    case shellRequestFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize libssh2"
        case .sessionInitFailed:
            return "Failed to create SSH session"
        case .handshakeFailed(let code, let detail):
            return detail ?? "SSH handshake failed (error code: \(code))"
        case .authenticationFailed(let code):
            return "Authentication failed (error code: \(code))"
        case .channelOpenFailed(let code):
            return "Failed to open channel (error code: \(code))"
        case .ptyRequestFailed:
            return "Failed to request PTY"
        case .shellRequestFailed:
            return "Failed to start shell"
        }
    }
}
