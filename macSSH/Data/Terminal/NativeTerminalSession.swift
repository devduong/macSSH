//
//  NativeTerminalSession.swift
//  macSSH
//
//  Terminal session using native ssh command via forkpty for full PTY compatibility.
//  This bypasses Citadel's PTY implementation to get proper character echo,
//  tab completion, and all interactive shell features working identically to Terminal.app.
//

import Foundation
import Citadel
import NIO
import NIOCore
import NIOFoundationCompat
import NIOSSH

actor NativeTerminalSession: TerminalSessionProtocol {
    private var childPid: pid_t = -1
    private var masterFd: Int32 = -1
    private(set) var isConnected = false
    private(set) var sessionEndedGracefully = false

    private var readTask: Task<Void, Never>?
    private var outputContinuation: AsyncStream<Data>.Continuation?
    private var _outputStream: AsyncStream<Data>?
    private var currentSize: TerminalSize = .default

    // SOCKS5 proxy support (via Citadel, independent of the native ssh process)
    private var socksServer: Socks5ProxyServer?
    private var sshClient: SSHClient?
    private var eventLoopGroup: (any EventLoopGroup)?
    private var socksMonitorTask: Task<Void, Never>?

    // Credentials cached for SOCKS5 reconnect
    private var socksHost: String?
    private var socksPort: Int = 22
    private var socksUsername: String?
    private var socksPassword: String?
    private var socksPrivateKeyPath: String?
    private var socksPassphrase: String?
    private var socksProxyPort: Int = 0
    private var socksAllowLAN: Bool = false

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

    // MARK: - Connect with Password

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        terminalSize: TerminalSize,
        socksProxyPort: Int? = nil,
        socksProxyAllowLAN: Bool = false
    ) async throws {
        logInfo("Connecting native terminal to \(username)@\(host):\(port)", category: .network)
        currentSize = terminalSize
        sessionEndedGracefully = false

        // Start SOCKS5 proxy if needed (non-fatal — terminal works even if proxy port is already in use)
        if let socksPort = socksProxyPort, socksPort > 0 {
            do {
                try await startSocksProxy(
                    host: host, port: port,
                    username: username, password: password,
                    privateKeyPath: nil, passphrase: nil,
                    socksPort: socksPort, allowLAN: socksProxyAllowLAN
                )
            } catch {
                logWarning("SOCKS5 proxy could not be started in Terminal (may already be running): \(error)", category: .network)
            }
        }

        // Initialize output stream
        _ = await outputStream

        // Build SSH command with sshpass for password auth
        try launchSSHProcess(
            host: host, port: port, username: username,
            password: password, privateKeyPath: nil,
            terminalSize: terminalSize
        )

        isConnected = true
        startReading()

        logInfo("Native terminal connected to \(host)", category: .network)
    }

    // MARK: - Connect with Private Key

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
        logInfo("Connecting native terminal to \(username)@\(host):\(port) with key", category: .network)
        currentSize = terminalSize
        sessionEndedGracefully = false

        // Start SOCKS5 proxy if needed (non-fatal)
        if let socksPort = socksProxyPort, socksPort > 0 {
            do {
                try await startSocksProxy(
                    host: host, port: port,
                    username: username, password: nil,
                    privateKeyPath: privateKeyPath, passphrase: passphrase,
                    socksPort: socksPort, allowLAN: socksProxyAllowLAN
                )
            } catch {
                logWarning("SOCKS5 proxy could not be started in Terminal (may already be running): \(error)", category: .network)
            }
        }

        _ = await outputStream

        try launchSSHProcess(
            host: host, port: port, username: username,
            password: nil, privateKeyPath: privateKeyPath,
            terminalSize: terminalSize
        )

        isConnected = true
        startReading()

        logInfo("Native terminal connected to \(host)", category: .network)
    }

    // MARK: - Launch SSH Process with forkpty

    private func launchSSHProcess(
        host: String, port: Int, username: String,
        password: String?, privateKeyPath: String?,
        terminalSize: TerminalSize
    ) throws {
        let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host

        // Set up terminal size
        var winSize = winsize(
            ws_row: UInt16(terminalSize.rows > 0 ? terminalSize.rows : 24),
            ws_col: UInt16(terminalSize.columns > 0 ? terminalSize.columns : 80),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, &winSize)

        if pid < 0 {
            throw AppError.terminalPTYFailed
        }

        if pid == 0 {
            // Child process — exec ssh
            // Set TERM environment variable
            setenv("TERM", "xterm-256color", 1)

            var args: [String] = ["ssh"]
            args += ["-p", "\(port)"]
            args += ["-o", "StrictHostKeyChecking=no"]
            args += ["-o", "ServerAliveInterval=30"]
            args += ["-o", "ServerAliveCountMax=3"]

            if let keyPath = privateKeyPath, !keyPath.isEmpty {
                args += ["-i", keyPath]
            }

            args += ["\(username)@\(normalizedHost)"]

            // Convert to C strings and exec
            let cArgs = args.map { strdup($0) } + [nil]
            execvp("/usr/bin/ssh", cArgs)

            // If exec fails
            _exit(1)
        }

        // Parent process
        self.masterFd = master
        self.childPid = pid

        // If password auth, wait briefly for password prompt then send password
        if let password = password, !password.isEmpty {
            // Send password after a short delay to let ssh show the prompt
            let passwordData = (password + "\n").data(using: .utf8)!
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) {
                passwordData.withUnsafeBytes { rawBuffer in
                    if let ptr = rawBuffer.baseAddress {
                        write(master, ptr, rawBuffer.count)
                    }
                }
            }
        }
    }

    // MARK: - Read Output

    private func startReading() {
        let fd = masterFd
        readTask = Task.detached { [weak self] in
            let bufferSize = 8192
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            while !Task.isCancelled {
                let bytesRead = read(fd, buffer, bufferSize)
                if bytesRead <= 0 {
                    break
                }
                let data = Data(bytes: buffer, count: bytesRead)
                await self?.sendOutput(data)
            }

            // Reading ended — child process exited
            await self?.handleProcessExit()
        }
    }

    private func sendOutput(_ data: Data) {
        outputContinuation?.yield(data)
    }

    private func handleProcessExit() {
        // Check child exit status
        var status: Int32 = 0
        if childPid > 0 {
            waitpid(childPid, &status, WNOHANG)
        }
        isConnected = false
        sessionEndedGracefully = (status == 0)
        outputContinuation?.finish()
    }

    // MARK: - Send Data

    func send(_ data: Data) async throws {
        guard isConnected, masterFd >= 0 else {
            throw AppError.notConnected
        }

        let fd = masterFd
        data.withUnsafeBytes { rawBuffer in
            if let ptr = rawBuffer.baseAddress {
                write(fd, ptr, rawBuffer.count)
            }
        }
    }

    // MARK: - Resize

    func resize(columns: Int, rows: Int) async throws {
        guard isConnected, masterFd >= 0 else { return }

        currentSize = TerminalSize(columns: columns, rows: rows)

        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let fd = masterFd
        ioctl(fd, TIOCSWINSZ, &winSize)
    }

    // MARK: - Disconnect

    func disconnect() async {
        logInfo("Disconnecting native terminal", category: .network)

        readTask?.cancel()
        readTask = nil

        // Stop SOCKS5 monitor first to prevent reconnect attempts during teardown
        socksMonitorTask?.cancel()
        socksMonitorTask = nil

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }

        if childPid > 0 {
            kill(childPid, SIGHUP)
            var status: Int32 = 0
            waitpid(childPid, &status, 0)
            childPid = -1
        }

        // Stop SOCKS5 proxy
        await socksServer?.stop()
        socksServer = nil

        try? await sshClient?.close()
        try? await eventLoopGroup?.shutdownGracefully()
        sshClient = nil
        eventLoopGroup = nil

        outputContinuation?.finish()
        outputContinuation = nil
        _outputStream = nil
        isConnected = false
    }

    // MARK: - SOCKS5 Proxy (via Citadel, independent of terminal PTY)

    private func startSocksProxy(
        host: String, port: Int,
        username: String, password: String?,
        privateKeyPath: String?, passphrase: String?,
        socksPort: Int, allowLAN: Bool
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host

        let authMethod: SSHAuthenticationMethod
        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            let privateKeyURL = URL(fileURLWithPath: keyPath)
            let privateKeyData = try Data(contentsOf: privateKeyURL)
            guard let privateKeyString = String(data: privateKeyData, encoding: .utf8) else {
                throw AppError.authenticationFailed
            }
            authMethod = try .rsa(username: username, privateKey: .init(sshRsa: privateKeyString))
        } else {
            authMethod = .passwordBased(username: username, password: password ?? "")
        }

        let client = try await SSHClient.connect(
            host: normalizedHost,
            port: port,
            authenticationMethod: authMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never,
            group: group
        )
        sshClient = client

        let isAlreadyRunning = await MainActor.run { ConnectionSessionManager.shared.isSocksProxyPortInUse(socksPort) }
        if !isAlreadyRunning {
            let server = Socks5ProxyServer(port: socksPort, sshClient: client, allowLAN: allowLAN)
            try await server.start()
            socksServer = server
            logInfo("SOCKS5 Proxy started on port \(socksPort) for native terminal (allowLAN: \(allowLAN))", category: .network)

            // Cache credentials for auto-reconnect
            self.socksHost = host
            self.socksPort = port
            self.socksUsername = username
            self.socksPassword = password
            self.socksPrivateKeyPath = privateKeyPath
            self.socksPassphrase = passphrase
            self.socksProxyPort = socksPort
            self.socksAllowLAN = allowLAN

            // Start background health monitor
            startSocksMonitor()
        }
    }

    // MARK: - SOCKS5 Health Monitor & Auto-Reconnect

    /// Periodically checks if the SSH connection backing the SOCKS5 proxy is alive.
    /// If the connection dies (e.g. network drop while app is in background),
    /// automatically reconnects and restarts the proxy.
    private func startSocksMonitor() {
        socksMonitorTask?.cancel()
        socksMonitorTask = Task { [weak self] in
            var consecutiveFailures = 0
            let maxRetries = 3

            while !Task.isCancelled {
                // Check every 60 seconds
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self = self else { break }

                // Only monitor if SOCKS5 is active
                guard await self.socksServer != nil, await self.sshClient != nil else { break }

                // Ping SSH connection
                let isAlive = await self.checkSSHAlive()
                if isAlive {
                    consecutiveFailures = 0
                    continue
                }

                // SSH is dead — attempt reconnect
                consecutiveFailures += 1
                logWarning("SOCKS5 SSH connection lost (attempt \(consecutiveFailures)/\(maxRetries)), reconnecting...", category: .network)

                if consecutiveFailures > maxRetries {
                    logError("SOCKS5 auto-reconnect failed after \(maxRetries) attempts. Giving up.", category: .network)
                    break
                }

                let success = await self.reconnectSocksProxy()
                if success {
                    consecutiveFailures = 0
                    logInfo("SOCKS5 proxy reconnected successfully", category: .network)
                } else {
                    // Wait a bit longer before next retry on failure
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    /// Check if the SSH client connection is still alive by attempting a simple channel operation
    private func checkSSHAlive() -> Bool {
        guard let client = sshClient else { return false }
        // Check if the underlying NIO channel is still active
        return client.isConnected
    }

    /// Tear down old SOCKS5 + SSH and create fresh ones using cached credentials
    private func reconnectSocksProxy() async -> Bool {
        // Clean up old resources safely
        let oldServer = socksServer
        let oldClient = sshClient
        let oldGroup = eventLoopGroup
        socksServer = nil
        sshClient = nil
        eventLoopGroup = nil

        await oldServer?.stop()
        try? await oldClient?.close()
        try? await oldGroup?.shutdownGracefully()

        // Reconnect using cached credentials
        guard let host = socksHost, let username = socksUsername, socksProxyPort > 0 else {
            return false
        }

        do {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.eventLoopGroup = group

            let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host

            let authMethod: SSHAuthenticationMethod
            if let keyPath = socksPrivateKeyPath, !keyPath.isEmpty {
                let privateKeyURL = URL(fileURLWithPath: keyPath)
                let privateKeyData = try Data(contentsOf: privateKeyURL)
                guard let privateKeyString = String(data: privateKeyData, encoding: .utf8) else {
                    return false
                }
                authMethod = try .rsa(username: username, privateKey: .init(sshRsa: privateKeyString))
            } else {
                authMethod = .passwordBased(username: username, password: socksPassword ?? "")
            }

            let client = try await SSHClient.connect(
                host: normalizedHost,
                port: socksPort,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group
            )
            self.sshClient = client

            let server = Socks5ProxyServer(port: socksProxyPort, sshClient: client, allowLAN: socksAllowLAN)
            try await server.start()
            self.socksServer = server

            return true
        } catch {
            logError("SOCKS5 reconnect failed: \(error)", category: .network)
            return false
        }
    }
}

