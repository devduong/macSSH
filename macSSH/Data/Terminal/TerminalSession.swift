//
//  TerminalSession.swift
//  macSSH
//
//  Actor-based terminal session using Citadel SSH with PTY
//

import Foundation
import Citadel
import NIO
import NIOCore
import NIOFoundationCompat
import NIOSSH

actor TerminalSession: TerminalSessionProtocol {
    private var client: SSHClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var socksServer: Socks5ProxyServer?
    private(set) var isConnected = false
    private(set) var sessionEndedGracefully = false

    // PTY state
    private var ptyTask: Task<Void, Error>?
    private var ttyWriter: TTYStdinWriter?
    private var ptyReadyContinuation: CheckedContinuation<Void, Error>?
    private var outputContinuation: AsyncStream<Data>.Continuation?
    private var currentSize: TerminalSize = .default

    // Output stream for terminal data
    private var _outputStream: AsyncStream<Data>?
    var outputStream: AsyncStream<Data> {
        get async {
            if let stream = _outputStream {
                return stream
            }
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            outputContinuation = continuation
            _outputStream = stream
            return stream
        }
    }

    init() {}

    // MARK: - Connection with Password

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        terminalSize: TerminalSize,
        socksProxyPort: Int? = nil,
        socksProxyAllowLAN: Bool = false
    ) async throws {
        logInfo("Connecting terminal to \(username)@\(host):\(port) with password", category: .network)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        currentSize = terminalSize
        sessionEndedGracefully = false

        do {
            let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host

            let authMethod: SSHAuthenticationMethod = .passwordBased(
                username: username,
                password: password
            )

            let sshClient = try await SSHClient.connect(
                host: normalizedHost,
                port: port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group
            )
            client = sshClient
            isConnected = true

            // Start SOCKS5 proxy server if requested and not already managed globally
            if let socksPort = socksProxyPort, socksPort > 0 {
                let isAlreadyRunning = await MainActor.run { ConnectionSessionManager.shared.isSocksProxyPortInUse(socksPort) }
                if !isAlreadyRunning {
                    let server = Socks5ProxyServer(port: socksPort, sshClient: sshClient, allowLAN: socksProxyAllowLAN)
                    do {
                        try await server.start()
                        self.socksServer = server
                        logInfo("SOCKS5 Proxy started on port \(socksPort) for Terminal connection to \(host) (allowLAN: \(socksProxyAllowLAN))", category: .network)
                    } catch {
                        logError("Failed to start SOCKS5 proxy on port \(socksPort): \(error)", category: .network)
                    }
                }
            }

            // Initialize output stream if not already
            _ = await outputStream

            // Start PTY session and await readiness
            try await startPTYSession()

            logInfo("Terminal connected successfully to \(host)", category: .network)
        } catch {
            await socksServer?.stop()
            socksServer = nil
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw parseConnectionError(error)
        }
    }

    // MARK: - Connection with Private Key

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        passphrase: String?,
        terminalSize: TerminalSize,
        socksProxyPort: Int? = nil,
        socksProxyAllowLAN: Bool = false
    ) async throws {
        logInfo("Connecting terminal to \(username)@\(host):\(port) with private key", category: .network)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        currentSize = terminalSize
        sessionEndedGracefully = false

        do {
            let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host

            let privateKeyURL = URL(fileURLWithPath: privateKeyPath)
            let privateKeyData = try Data(contentsOf: privateKeyURL)
            guard let privateKeyString = String(data: privateKeyData, encoding: .utf8) else {
                throw AppError.authenticationFailed
            }

            let authMethod: SSHAuthenticationMethod = try .rsa(
                username: username,
                privateKey: .init(sshRsa: privateKeyString)
            )

            let sshClient = try await SSHClient.connect(
                host: normalizedHost,
                port: port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group
            )
            client = sshClient
            isConnected = true

            // Start SOCKS5 proxy server if requested and not already managed globally
            if let socksPort = socksProxyPort, socksPort > 0 {
                let isAlreadyRunning = await MainActor.run { ConnectionSessionManager.shared.isSocksProxyPortInUse(socksPort) }
                if !isAlreadyRunning {
                    let server = Socks5ProxyServer(port: socksPort, sshClient: sshClient, allowLAN: socksProxyAllowLAN)
                    do {
                        try await server.start()
                        self.socksServer = server
                        logInfo("SOCKS5 Proxy started on port \(socksPort) for Terminal connection to \(host) (allowLAN: \(socksProxyAllowLAN))", category: .network)
                    } catch {
                        logError("Failed to start SOCKS5 proxy on port \(socksPort): \(error)", category: .network)
                    }
                }
            }

            // Initialize output stream if not already
            _ = await outputStream

            // Start PTY session and await readiness
            try await startPTYSession()

            logInfo("Terminal connected successfully to \(host)", category: .network)
        } catch {
            await socksServer?.stop()
            socksServer = nil
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw parseConnectionError(error)
        }
    }

    // MARK: - PTY Session

    private func startPTYSession() async throws {
        guard let client = client else {
            throw AppError.notConnected
        }

        // Capture current size before entering task
        let cols = currentSize.columns > 0 ? currentSize.columns : 80
        let rows = currentSize.rows > 0 ? currentSize.rows : 24

        try await withCheckedThrowingContinuation { continuation in
            self.ptyReadyContinuation = continuation

            // Create a task to run the PTY session
            ptyTask = Task { [weak self] in
                guard let self = self else { return }

                do {
                    // Full OpenSSH-compatible PTY modes for proper character echo
                    let terminalModes = SSHTerminalModes([
                        // Baud rate
                        .TTY_OP_ISPEED: 38400,
                        .TTY_OP_OSPEED: 38400,
                        // POSIX control characters
                        .VINTR: 3,        // Ctrl-C
                        .VQUIT: 28,       // Ctrl-backslash
                        .VERASE: 127,     // DEL (backspace)
                        .VKILL: 21,       // Ctrl-U
                        .VEOF: 4,         // Ctrl-D
                        .VEOL: 0,         // disabled
                        .VEOL2: 0,        // disabled
                        .VSTART: 17,      // Ctrl-Q (XON)
                        .VSTOP: 19,       // Ctrl-S (XOFF)
                        .VSUSP: 26,       // Ctrl-Z
                        .VREPRINT: 18,    // Ctrl-R
                        .VWERASE: 23,     // Ctrl-W
                        .VLNEXT: 22,      // Ctrl-V
                        .VFLUSH: 15,      // Ctrl-O
                        // Input modes
                        .ICRNL: 1,        // Map CR to NL on input
                        .IXON: 1,         // Enable output flow control
                        .IXANY: 0,        // Disable any-char restart
                        .IMAXBEL: 1,      // Ring bell on input queue full
                        // Local modes — CRITICAL for character echo
                        .ISIG: 1,         // Enable signals (INTR, QUIT, SUSP)
                        .ICANON: 1,       // Canonical mode (let shell handle line editing)
                        .ECHO: 1,         // Enable echoing
                        .ECHOE: 1,        // Visually erase characters
                        .ECHOK: 1,        // Echo NL after kill character
                        .ECHONL: 0,       // Don't echo NL when ECHO is off
                        .ECHOCTL: 1,      // Echo control characters as ^X
                        .ECHOKE: 1,       // Visual erase for line kill
                        .IEXTEN: 1,       // Enable extensions
                        .NOFLSH: 0,       // Flush after interrupt
                        .TOSTOP: 0,       // Don't stop background jobs from output
                        .PENDIN: 0,       // Don't reprint pending input
                        // Output modes
                        .OPOST: 1,        // Enable output processing
                        .ONLCR: 1,        // Map NL to CR-NL
                        // Character size
                        .CS8: 1,          // 8-bit characters
                        .PARENB: 0,       // No parity
                    ])
                    let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: cols,
                        terminalRowHeight: rows,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: terminalModes
                    )

                    // Open a shell channel with PTY using Citadel's withPTY
                    try await client.withPTY(ptyRequest) { ttyOutput, ttyWriter in
                        // Store the writer for sending input and resize
                        await self.setTTYWriter(ttyWriter)
                        await self.resumePTYReady(with: .success(()))

                        // Read output from the TTY and forward to the stream
                        for try await output in ttyOutput {
                            if Task.isCancelled { break }

                            switch output {
                            case .stdout(let buffer):
                                let data = Data(buffer: buffer)
                                await self.sendOutput(data)
                            case .stderr(let buffer):
                                let data = Data(buffer: buffer)
                                await self.sendOutput(data)
                            }
                        }
                    }

                    // PTY stream ended normally (e.g. user exited shell with CTRL-D/exit)
                    if !Task.isCancelled {
                        logInfo("Terminal session ended gracefully", category: .network)
                        await self.handleGracefulSessionEnd()
                    }
                } catch {
                    await self.resumePTYReady(with: .failure(error))
                    if !Task.isCancelled {
                        logError("PTY session error: \(error)", category: .network)
                        await self.handlePTYError(error)
                    }
                }
            }
        }
    }

    private func resumePTYReady(with result: Result<Void, Error>) {
        if let cont = ptyReadyContinuation {
            ptyReadyContinuation = nil
            cont.resume(with: result)
        }
    }

    private func setTTYWriter(_ writer: TTYStdinWriter) {
        ttyWriter = writer
    }

    private func sendOutput(_ data: Data) {
        outputContinuation?.yield(data)
    }

    private func handleGracefulSessionEnd() {
        isConnected = false
        sessionEndedGracefully = true
        outputContinuation?.finish()
    }

    private func handlePTYError(_ error: Error) {
        isConnected = false
        outputContinuation?.finish()
    }

    // MARK: - Send Data

    func send(_ data: Data) async throws {
        guard isConnected else {
            throw AppError.notConnected
        }

        guard let writer = ttyWriter else {
            throw AppError.terminalPTYFailed
        }

        try await writer.write(ByteBuffer(data: data))
    }

    // MARK: - Resize

    func resize(columns: Int, rows: Int) async throws {
        guard isConnected else { return }

        currentSize = TerminalSize(columns: columns, rows: rows)

        guard let writer = ttyWriter else { return }

        do {
            try await writer.changeSize(cols: columns, rows: rows, pixelWidth: 0, pixelHeight: 0)
        } catch {
            logError("Failed to resize terminal: \(error)", category: .network)
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        logInfo("Disconnecting terminal", category: .network)

        await socksServer?.stop()
        socksServer = nil

        ptyTask?.cancel()
        ptyTask = nil
        ttyWriter = nil

        outputContinuation?.finish()
        outputContinuation = nil
        _outputStream = nil

        try? await client?.close()
        try? await eventLoopGroup?.shutdownGracefully()

        client = nil
        eventLoopGroup = nil
        isConnected = false
    }

    private func parseConnectionError(_ error: Error) -> AppError {
        let description = error.localizedDescription.lowercased()

        if error is AuthenticationFailed ||
           (error as? CitadelError) == .unauthorized ||
           (error as? SSHClientError) == .allAuthenticationOptionsFailed ||
           description.contains("authentication") ||
           description.contains("password") ||
           description.contains("permission denied") ||
           description.contains("auth") {
            return .authenticationFailed
        } else if description.contains("connection refused") {
            return .connectionFailed("Connection refused. Make sure the SSH server is running.")
        } else if description.contains("host unreachable") || description.contains("no route to host") {
            return .hostUnreachable
        } else if description.contains("timeout") {
            return .connectionTimeout
        } else if description.contains("operation not permitted") {
            return .connectionFailed("Operation not permitted. Check firewall settings.")
        }

        return .terminalConnectionFailed(error.localizedDescription)
    }
}
