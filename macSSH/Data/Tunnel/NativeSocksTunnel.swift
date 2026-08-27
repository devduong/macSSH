//
//  NativeSocksTunnel.swift
//  macSSH
//
//  Headless Native OpenSSH SOCKS5 Proxy Tunnel
//  Spawns `/usr/bin/ssh -D [bind_address:]port -N` as an invisible background process.
//  Zero SwiftNIO dependency, impervious to macOS App Nap and Sleep/Wake issues.
//

import Foundation
import Darwin

actor NativeSocksTunnel {
    private var childPid: pid_t = -1
    private var masterFd: Int32 = -1
    private var readTask: Task<Void, Never>?
    private(set) var isRunning: Bool = false

    let socksPort: Int
    let allowLAN: Bool

    init(socksPort: Int, allowLAN: Bool = false) {
        self.socksPort = socksPort
        self.allowLAN = allowLAN
    }

    deinit {
        if childPid > 0 {
            kill(childPid, SIGTERM)
        }
        if masterFd >= 0 {
            close(masterFd)
        }
    }

    // MARK: - Start Tunnel

    /// Starts the headless OpenSSH SOCKS5 tunnel
    func start(
        host: String,
        port: Int,
        username: String,
        password: String? = nil,
        privateKeyPath: String? = nil,
        passphrase: String? = nil
    ) async throws {
        guard !isRunning else { return }

        let normalizedHost = (host.lowercased() == "localhost") ? "127.0.0.1" : host
        let bindAddress = allowLAN ? "0.0.0.0" : "127.0.0.1"
        let dynamicForwardSpec = "\(bindAddress):\(socksPort)"

        var winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, &winSize)

        if pid < 0 {
            throw AppError.terminalPTYFailed
        }

        if pid == 0 {
            // Child process: exec /usr/bin/ssh
            setenv("TERM", "dumb", 1)

            var args: [String] = ["ssh"]
            args += ["-D", dynamicForwardSpec]
            args += ["-N"] // Do not execute a remote command (port forwarding only)
            args += ["-p", "\(port)"]
            args += ["-o", "StrictHostKeyChecking=no"]
            args += ["-o", "UserKnownHostsFile=/dev/null"]
            args += ["-o", "ServerAliveInterval=30"]
            args += ["-o", "ServerAliveCountMax=3"]
            args += ["-o", "ExitOnForwardFailure=yes"]
            args += ["-o", "LogLevel=ERROR"]

            if let keyPath = privateKeyPath, !keyPath.isEmpty {
                args += ["-i", keyPath]
            }

            args += ["\(username)@\(normalizedHost)"]

            let cArgs = args.map { strdup($0) } + [nil]
            execvp("/usr/bin/ssh", cArgs)
            _exit(1)
        }

        // Parent process
        self.masterFd = master
        self.childPid = pid
        self.isRunning = true

        // Set non-blocking on master FD so reads don't hang
        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }

        // Handle interactive authentication / prompt detection in background
        startOutputMonitoring(
            password: password,
            passphrase: passphrase
        )

        // Give the process a brief moment (500ms) to check if it immediately exits (e.g. port already bound)
        try await Task.sleep(nanoseconds: 500_000_000)

        var status: Int32 = 0
        let waitResult = waitpid(pid, &status, WNOHANG)
        if waitResult == pid {
            // Process exited prematurely
            isRunning = false
            cleanup()
            let exitCode = (status >> 8) & 0xff
            logError("Native SOCKS5 tunnel process exited immediately with code \(exitCode)", category: .network)
            throw AppError.connectionFailed("SOCKS5 proxy failed to bind port \(socksPort) (Exit code: \(exitCode))")
        }

        logInfo("Native OpenSSH SOCKS5 Proxy started on \(dynamicForwardSpec) for \(username)@\(host) (PID: \(pid))", category: .network)
    }

    // MARK: - Monitor Output & Feed Credentials

    private func startOutputMonitoring(password: String?, passphrase: String?) {
        let fd = masterFd
        let pid = childPid

        readTask = Task.detached { [weak self] in
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            var passwordSent = false
            var passphraseSent = false

            while !Task.isCancelled {
                let bytesRead = read(fd, buffer, bufferSize)
                if bytesRead > 0 {
                    let output = String(decoding: Data(bytes: buffer, count: bytesRead), as: UTF8.self)

                    // Check for password prompt
                    if !passwordSent, let pwd = password, !pwd.isEmpty {
                        let lower = output.lowercased()
                        if lower.contains("password:") || lower.contains("password for") {
                            passwordSent = true
                            let data = (pwd + "\n").data(using: .utf8)!
                            data.withUnsafeBytes { raw in
                                if let ptr = raw.baseAddress {
                                    _ = write(fd, ptr, raw.count)
                                }
                            }
                        }
                    }

                    // Check for passphrase prompt
                    if !passphraseSent, let pass = passphrase, !pass.isEmpty {
                        let lower = output.lowercased()
                        if lower.contains("passphrase") {
                            passphraseSent = true
                            let data = (pass + "\n").data(using: .utf8)!
                            data.withUnsafeBytes { raw in
                                if let ptr = raw.baseAddress {
                                    _ = write(fd, ptr, raw.count)
                                }
                            }
                        }
                    }

                    // Check for host key verification prompt (yes/no)
                    if output.contains("yes/no") {
                        let data = "yes\n".data(using: .utf8)!
                        data.withUnsafeBytes { raw in
                            if let ptr = raw.baseAddress {
                                _ = write(fd, ptr, raw.count)
                            }
                        }
                    }
                } else if bytesRead == 0 {
                    // EOF - process exited
                    break
                } else {
                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK {
                        // No data available right now, sleep briefly
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    } else {
                        // Unrecoverable read error
                        break
                    }
                }

                // Check if process has died
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == pid {
                    break
                }
            }

            await self?.handleProcessExit()
        }
    }

    private func handleProcessExit() {
        isRunning = false
        cleanup()
    }

    // MARK: - Stop Tunnel

    /// Gracefully stops the native OpenSSH SOCKS5 tunnel
    func stop() {
        guard isRunning || childPid > 0 else { return }
        isRunning = false

        readTask?.cancel()
        readTask = nil

        if childPid > 0 {
            // Send SIGTERM first for graceful exit
            kill(childPid, SIGTERM)

            // Wait briefly then force kill if needed
            let pid = childPid
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                var status: Int32 = 0
                if waitpid(pid, &status, WNOHANG) == 0 {
                    kill(pid, SIGKILL)
                    waitpid(pid, &status, 0)
                }
            }
            childPid = -1
        }

        cleanup()
        logInfo("Native OpenSSH SOCKS5 Proxy stopped on port \(socksPort)", category: .network)
    }

    private func cleanup() {
        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
    }
}
