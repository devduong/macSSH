//
//  NativeTerminalSession.swift
//  macSSH
//
//  Terminal session using native ssh command via forkpty for full PTY compatibility.
//  This bypasses Citadel's PTY implementation to get proper character echo,
//  tab completion, and all interactive shell features working identically to Terminal.app.
//

import Foundation

actor NativeTerminalSession: TerminalSessionProtocol {
    private var childPid: pid_t = -1
    private var masterFd: Int32 = -1
    private(set) var isConnected = false
    private(set) var sessionEndedGracefully = false

    private var readTask: Task<Void, Never>?
    private var outputContinuation: AsyncStream<Data>.Continuation?
    private var _outputStream: AsyncStream<Data>?
    private var currentSize: TerminalSize = .default

    // SOCKS5 proxy support (via Native OpenSSH headless tunnel)
    private var socksTunnel: NativeSocksTunnel?

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

        let tunnel = socksTunnel
        socksTunnel = nil
        Task {
            await tunnel?.stop()
        }

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
        await socksTunnel?.stop()
        socksTunnel = nil


        outputContinuation?.finish()
        outputContinuation = nil
        _outputStream = nil
        isConnected = false
    }

    // MARK: - SOCKS5 Proxy (via Native OpenSSH headless tunnel)

    private func startSocksProxy(
        host: String, port: Int,
        username: String, password: String?,
        privateKeyPath: String?, passphrase: String?,
        socksPort: Int, allowLAN: Bool
    ) async throws {
        let isAlreadyRunning = await MainActor.run { ConnectionSessionManager.shared.isSocksProxyPortInUse(socksPort) }
        if !isAlreadyRunning {
            let tunnel = NativeSocksTunnel(socksPort: socksPort, allowLAN: allowLAN)
            try await tunnel.start(
                host: host,
                port: port,
                username: username,
                password: password,
                privateKeyPath: privateKeyPath,
                passphrase: passphrase
            )
            socksTunnel = tunnel
            logInfo("Native OpenSSH SOCKS5 Proxy started on port \(socksPort) for native terminal (allowLAN: \(allowLAN))", category: .network)
        }
    }
}



