import Foundation
import Network
import CSSH

/// SSH client implementation using libssh2 C library
/// Handles SSH connection, authentication, and channel management over BLE-Eth transport
class SSHClient {
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var transport: BleEthTransport?

    private let host: String
    private let port: Int
    private let username: String
    private let password: String

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

    deinit {
        disconnect()
    }

    /// Connect to SSH server through BLE-Eth transport
    func connect(transport: BleEthTransport) {
        self.transport = transport

        sshQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.performConnect()
            } catch {
                self.onError?("Connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func performConnect() throws {
        // Initialize libssh2
        guard libssh2_init(0) == 0 else {
            throw SSHError.initializationFailed
        }

        // Create session
        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            throw SSHError.sessionInitFailed
        }
        self.session = session

        // Configure session preferences
        configureSessionPreferences(session)

        // Set non-blocking mode
        libssh2_session_set_blocking(session, 0)

        // Perform handshake
        // Note: libssh2 will use the socket from BleEthTransport
        // For BLE-Eth, we need to set up a socket-like interface
        // This is a simplified version - in practice, you'd need to bridge
        // BleEthTransport to a POSIX socket that libssh2 can use

        let handshakeResult = libssh2_session_handshake(session, 0)
        if handshakeResult != 0 {
            let lastError = libssh2_session_last_errno(session)
            throw SSHError.handshakeFailed(code: lastError)
        }

        // Get server banner
        if let banner = libssh2_session_banner_get(session) {
            print("SSH Banner: \(String(cString: banner))")
        }

        // Authenticate
        let authResult = libssh2_userauth_password_ex(session, username, UInt32(strlen(username)), password, UInt32(strlen(password)), nil)
        if authResult != 0 {
            let lastError = libssh2_session_last_errno(session)
            throw SSHError.authenticationFailed(code: lastError)
        }

        // Open channel (libssh2_channel_open_ex: session, type, type_len, window_size, packet_size, message, message_len)
        guard let channel = libssh2_channel_open_ex(session, "session", 7, 2*1024*1024, 32768, nil, 0) else {
            let lastError = libssh2_session_last_errno(session)
            throw SSHError.channelOpenFailed(code: lastError)
        }
        self.channel = channel

        // Request PTY with xterm-256color
        let termType = "xterm-256color"
        let ptyResult = libssh2_channel_request_pty_ex(
            channel,
            termType,
            UInt32(strlen(termType)),
            nil, 0,
            80, 24,  // width, height in characters
            0, 0     // width, height in pixels
        )
        if ptyResult != 0 {
            throw SSHError.ptyRequestFailed
        }

        // Request shell
        let shellResult = libssh2_channel_process_startup(channel, "shell", 5, nil, 0)
        if shellResult != 0 {
            throw SSHError.shellRequestFailed
        }

        isConnected = true

        // Start reading output
        startReadingOutput()
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
        sshQueue.async { [weak self] in
            guard let self = self, let channel = self.channel else { return }

            var buffer = [UInt8](repeating: 0, count: 4096)

            while self.isConnected {
                let bytesRead = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)

                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    self.onOutput?(data)
                } else if bytesRead == 0 {
                    // Channel closed
                    break
                } else if bytesRead < 0 {
                    let errorCode = libssh2_session_last_errno(self.session)
                    if errorCode == LIBSSH2_ERROR_EAGAIN {
                        // Non-blocking mode, no data available yet
                        Thread.sleep(forTimeInterval: 0.01)
                        continue
                    } else {
                        // Error
                        self.onError?("Read error: \(errorCode)")
                        break
                    }
                }
            }
        }
    }

    /// Write data to SSH channel
    func write(_ data: Data) {
        guard let channel = self.channel, isConnected else { return }

        sshQueue.async { [weak self] in
            guard let self = self else { return }

            data.withUnsafeBytes { bufferPointer in
                guard let baseAddress = bufferPointer.baseAddress else { return }
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
                            Thread.sleep(forTimeInterval: 0.01)
                            continue
                        } else {
                            self.onError?("Write error: \(errorCode)")
                            break
                        }
                    } else {
                        totalWritten += bytesWritten
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

            libssh2_exit()
        }
    }

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
    case handshakeFailed(code: Int32)
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
        case .handshakeFailed(let code):
            return "SSH handshake failed (error code: \(code))"
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
