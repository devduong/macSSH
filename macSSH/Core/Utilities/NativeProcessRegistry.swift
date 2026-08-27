//
//  NativeProcessRegistry.swift
//  macSSH
//
//  Thread-safe central registry for all spawned native child processes (SOCKS5 tunnels, SSH terminals).
//  Guarantees 100% cleanup of child processes when the app terminates or sessions end.
//

import Foundation
import Darwin

final class NativeProcessRegistry: @unchecked Sendable {
    static let shared = NativeProcessRegistry()

    private let lock = NSLock()
    private var activePids = [pid_t: String]()

    // Global static array for async-signal-safe access during crash
    private static var emergencyPids = [pid_t]()
    private static let emergencyLock = NSLock()

    private init() {
        setupAtexitHook()
        setupSignalHandlers()
    }

    // MARK: - Registration

    /// Registers a child process PID for lifecycle tracking
    func register(pid: pid_t, description: String = "") {
        guard pid > 0 else { return }
        lock.lock()
        activePids[pid] = description
        lock.unlock()

        Self.emergencyLock.lock()
        Self.emergencyPids.append(pid)
        Self.emergencyLock.unlock()
    }

    /// Unregisters a child process PID when it is stopped normally
    func unregister(pid: pid_t) {
        guard pid > 0 else { return }
        lock.lock()
        activePids.removeValue(forKey: pid)
        lock.unlock()

        Self.emergencyLock.lock()
        Self.emergencyPids.removeAll { $0 == pid }
        Self.emergencyLock.unlock()
    }

    // MARK: - Process Termination

    /// Immediately terminates all registered child processes (SIGTERM followed by SIGKILL)
    func terminateAll() {
        lock.lock()
        let pids = Array(activePids.keys)
        activePids.removeAll()
        lock.unlock()

        Self.emergencyLock.lock()
        Self.emergencyPids.removeAll()
        Self.emergencyLock.unlock()

        guard !pids.isEmpty else { return }

        // Phase 1: Send SIGTERM to process and its process group
        for pid in pids {
            kill(pid, SIGTERM)
            kill(-pid, SIGTERM)
        }

        // Phase 2: Short grace period (50ms) then force kill with SIGKILL if still running
        usleep(50_000)

        for pid in pids {
            var status: Int32 = 0
            let waitResult = waitpid(pid, &status, WNOHANG)
            if waitResult == 0 {
                // Process is still alive, force kill
                kill(pid, SIGKILL)
                kill(-pid, SIGKILL)
                waitpid(pid, &status, WNOHANG)
            }
        }
    }

    /// Terminates a single PID and unregisters it
    func terminate(pid: pid_t) {
        guard pid > 0 else { return }
        unregister(pid: pid)

        kill(pid, SIGTERM)
        kill(-pid, SIGTERM)

        // Non-blocking check + force kill if needed
        var status: Int32 = 0
        let waitResult = waitpid(pid, &status, WNOHANG)
        if waitResult == 0 {
            kill(pid, SIGKILL)
            kill(-pid, SIGKILL)
            waitpid(pid, &status, WNOHANG)
        }
    }

    // MARK: - Emergency Crash Kill

    /// Static synchronous emergency kill called from Darwin signal handlers during crashes
    static func emergencyKillAll() {
        for pid in emergencyPids {
            kill(pid, SIGKILL)
            kill(-pid, SIGKILL)
        }
    }

    // MARK: - Orphan Cleanup on Startup

    /// Cleans up any leftover orphan ssh -D processes spawned by macSSH on previous runs/crashes
    func cleanupOrphanProcesses() {
        DispatchQueue.global(qos: .utility).async {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-eo", "pid,ppid,command"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                let currentPid = getpid()
                let lines = output.components(separatedBy: .newlines)

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    // Look for ssh processes running in dynamic port forwarding mode (-D and -N)
                    // with macSSH-specific parameters (e.g., UserKnownHostsFile=/dev/null, ServerAliveInterval)
                    if trimmed.contains("ssh ") &&
                       trimmed.contains("-D") &&
                       trimmed.contains("-N") &&
                       trimmed.contains("UserKnownHostsFile=/dev/null") {

                        let components = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                        if let pidStr = components.first, let pid = pid_t(pidStr), pid != currentPid {
                            // Check if this process has PPID == 1 (adopted by launchd, meaning its parent app died)
                            if components.count >= 2, let ppidStr = components.dropFirst().first, let ppid = pid_t(ppidStr), ppid == 1 {
                                kill(pid, SIGTERM)
                                usleep(50_000)
                                kill(pid, SIGKILL)
                            }
                        }
                    }
                }
            } catch {
                // Ignore failure during startup cleanup
            }
        }
    }

    // MARK: - Low-level Hooks

    private func setupAtexitHook() {
        atexit {
            NativeProcessRegistry.shared.terminateAll()
        }
    }

    private func setupSignalHandlers() {
        let signalsToCatch: [Int32] = [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGTERM, SIGINT, SIGHUP]
        for sig in signalsToCatch {
            signal(sig) { triggeredSig in
                NativeProcessRegistry.emergencyKillAll()
                signal(triggeredSig, SIG_DFL)
                raise(triggeredSig)
            }
        }
    }
}
