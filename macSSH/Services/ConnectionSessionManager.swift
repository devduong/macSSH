//
//  ConnectionSessionManager.swift
//  macSSH
//
//  Manages persistent SSH connection sessions, background tunnel lifecycle,
//  and session credentials.
//

import Foundation
import SwiftUI
import Combine
import Citadel
import NIO
import NIOCore

@MainActor
final class ConnectionSessionManager: ObservableObject {
    static let shared = ConnectionSessionManager()

    struct ActiveSession {
        let connection: Connection
        var client: SSHClient
        let eventLoopGroup: MultiThreadedEventLoopGroup
        var socksServer: Socks5ProxyServer?
        let password: String
        let connectedAt: Date
        var monitorTask: Task<Void, Never>?
    }

    @Published private(set) var activeSessions: [UUID: ActiveSession] = [:]
    @Published private(set) var connectingIds: Set<UUID> = []
    private var cachedPasswords: [UUID: String] = [:]

    private init() {}

    // MARK: - State queries

    func isConnected(_ connectionId: UUID) -> Bool {
        activeSessions[connectionId] != nil || WindowManager.shared.isConnectionActive(connectionId)
    }

    func isConnecting(_ connectionId: UUID) -> Bool {
        connectingIds.contains(connectionId)
    }

    func getCachedPassword(for connectionId: UUID) -> String? {
        cachedPasswords[connectionId] ?? activeSessions[connectionId]?.password
    }

    func cachePassword(_ password: String, for connectionId: UUID) {
        cachedPasswords[connectionId] = password
    }

    func clearPassword(for connectionId: UUID) {
        cachedPasswords.removeValue(forKey: connectionId)
    }

    func markConnected(for connectionId: UUID) {
        WindowManager.shared.markConnectionActive(connectionId)
        objectWillChange.send()
    }

    func markDisconnected(for connectionId: UUID) {
        WindowManager.shared.markConnectionInactive(connectionId)
        objectWillChange.send()
    }

    func clearSession(for connectionId: UUID) {
        cachedPasswords.removeValue(forKey: connectionId)
        activeSessions.removeValue(forKey: connectionId)
        WindowManager.shared.markConnectionInactive(connectionId)
        objectWillChange.send()
    }

    // MARK: - Connect & Retain Session

    func connect(_ connection: Connection, password: String) async throws {
        connectingIds.insert(connection.id)
        defer { connectingIds.remove(connection.id) }

        // Cache password for current app lifecycle
        if !password.isEmpty {
            cachedPasswords[connection.id] = password
        }

        // Clean up previous active session for this ID if any
        if activeSessions[connection.id] != nil {
            await disconnect(connection.id)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let normalizedHost = (connection.host.lowercased() == "localhost") ? "127.0.0.1" : connection.host

        let sshClient: SSHClient

        if connection.authMethod == .password {
            let authMethod: SSHAuthenticationMethod = .passwordBased(
                username: connection.username,
                password: password
            )
            sshClient = try await SSHClient.connect(
                host: normalizedHost,
                port: connection.port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group
            )
        } else if let keyPath = connection.privateKeyPath {
            let keyURL = URL(fileURLWithPath: keyPath)
            let keyData = try Data(contentsOf: keyURL)
            guard let keyString = String(data: keyData, encoding: .utf8) else {
                throw AppError.authenticationFailed
            }

            let authMethod: SSHAuthenticationMethod = try .rsa(
                username: connection.username,
                privateKey: .init(sshRsa: keyString)
            )

            sshClient = try await SSHClient.connect(
                host: normalizedHost,
                port: connection.port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group
            )
        } else {
            throw AppError.authenticationFailed
        }

        // Start SOCKS5 proxy if enabled and port is not in conflict with another active session
        var effectiveProxyEnabled = connection.socksProxyEnabled
        if effectiveProxyEnabled && connection.socksProxyPort > 0 {
            if let activeName = activeConnectionName(forSocksPort: connection.socksProxyPort, excludingConnectionId: connection.id) {
                logWarning("SOCKS proxy port \(connection.socksProxyPort) is already in use by another active SSH session '\(activeName)'. Proxy turned OFF for \(connection.name).", category: .network)
                effectiveProxyEnabled = false
                handleProxyPortConflict(for: connection.id, port: connection.socksProxyPort, reason: .usedBySession(name: activeName))
            }
        }

        var socksServer: Socks5ProxyServer? = nil
        if effectiveProxyEnabled && connection.socksProxyPort > 0 {
            let server = Socks5ProxyServer(
                port: connection.socksProxyPort,
                sshClient: sshClient,
                allowLAN: connection.socksProxyAllowLAN
            )
            do {
                try await server.start()
                socksServer = server
                logInfo("SOCKS5 Proxy started on port \(connection.socksProxyPort) for \(connection.name) (allowLAN: \(connection.socksProxyAllowLAN))", category: .network)
            } catch {
                logError("Failed to start SOCKS5 proxy on port \(connection.socksProxyPort): \(error). Turning proxy OFF.", category: .network)
                effectiveProxyEnabled = false
                handleProxyPortConflict(for: connection.id, port: connection.socksProxyPort, reason: .alreadyBoundOrFailed)
            }
        }

        var sessionConnection = connection
        sessionConnection.socksProxyEnabled = effectiveProxyEnabled

        let session = ActiveSession(
            connection: sessionConnection,
            client: sshClient,
            eventLoopGroup: group,
            socksServer: socksServer,
            password: password,
            connectedAt: Date()
        )

        activeSessions[connection.id] = session
        WindowManager.shared.markConnectionActive(connection.id)
        logInfo("Session established and retained for \(connection.name) (proxy: \(effectiveProxyEnabled ? "ON:\(connection.socksProxyPort)" : "OFF"))", category: .network)

        // Start background health monitor if SOCKS5 is active
        if effectiveProxyEnabled && socksServer != nil {
            startSessionMonitor(for: connection.id)
        }
    }

    /// Checks if a SOCKS proxy port is currently active on another session
    func isSocksProxyPortInUse(_ port: Int, excludingConnectionId: UUID? = nil) -> Bool {
        return activeSessions.values.contains { session in
            session.connection.id != excludingConnectionId &&
            session.socksServer != nil &&
            session.connection.socksProxyPort == port
        }
    }

    /// Returns the name of the active connection currently using the specified SOCKS proxy port
    func activeConnectionName(forSocksPort port: Int, excludingConnectionId: UUID? = nil) -> String? {
        return activeSessions.values.first { session in
            session.connection.id != excludingConnectionId &&
            session.socksServer != nil &&
            session.connection.socksProxyPort == port
        }?.connection.name
    }

    // MARK: - Disconnect

    func disconnect(_ connectionId: UUID) async {
        guard var session = activeSessions.removeValue(forKey: connectionId) else {
            WindowManager.shared.markConnectionInactive(connectionId)
            return
        }

        session.monitorTask?.cancel()
        session.monitorTask = nil

        await session.socksServer?.stop()
        try? await session.client.close()
        try? await session.eventLoopGroup.shutdownGracefully()
        WindowManager.shared.markConnectionInactive(connectionId)
        logInfo("Session closed for connection: \(connectionId)", category: .network)
    }

    func disconnectAll() async {
        let keys = Array(activeSessions.keys)
        for key in keys {
            await disconnect(key)
        }
    }

    func getActiveSession(for connectionId: UUID) -> ActiveSession? {
        activeSessions[connectionId]
    }

    /// Dynamically starts or stops the SOCKS5 proxy on an active session
    func updateProxyState(for connectionId: UUID, enabled: Bool) async throws {
        guard var session = activeSessions[connectionId] else { return }

        if enabled {
            if session.socksServer == nil && session.connection.socksProxyPort > 0 {
                if let activeName = activeConnectionName(forSocksPort: session.connection.socksProxyPort, excludingConnectionId: connectionId) {
                    handleProxyPortConflict(for: connectionId, port: session.connection.socksProxyPort, reason: .usedBySession(name: activeName))
                    return
                }

                let server = Socks5ProxyServer(
                    port: session.connection.socksProxyPort,
                    sshClient: session.client,
                    allowLAN: session.connection.socksProxyAllowLAN
                )
                do {
                    try await server.start()
                    session.socksServer = server
                    var updatedConn = session.connection
                    updatedConn.socksProxyEnabled = true
                    let newSession = ActiveSession(
                        connection: updatedConn,
                        client: session.client,
                        eventLoopGroup: session.eventLoopGroup,
                        socksServer: server,
                        password: session.password,
                        connectedAt: session.connectedAt
                    )
                    activeSessions[connectionId] = newSession
                    logInfo("SOCKS5 Proxy started dynamically on port \(session.connection.socksProxyPort) for \(session.connection.name)", category: .network)
                } catch {
                    logError("Failed to start SOCKS5 proxy dynamically on port \(session.connection.socksProxyPort): \(error)", category: .network)
                    handleProxyPortConflict(for: connectionId, port: session.connection.socksProxyPort, reason: .alreadyBoundOrFailed)
                }
            }
        } else {
            if let server = session.socksServer {
                await server.stop()
                var updatedConn = session.connection
                updatedConn.socksProxyEnabled = false
                let newSession = ActiveSession(
                    connection: updatedConn,
                    client: session.client,
                    eventLoopGroup: session.eventLoopGroup,
                    socksServer: nil,
                    password: session.password,
                    connectedAt: session.connectedAt
                )
                activeSessions[connectionId] = newSession
                logInfo("SOCKS5 Proxy stopped dynamically for \(session.connection.name)", category: .network)
            }
        }
        objectWillChange.send()
    }

    public enum ProxyConflictReason: Sendable {
        case usedBySession(name: String)
        case alreadyBoundOrFailed
    }

    /// Handles a port conflict or start failure for SOCKS5 proxy:
    /// Disables proxy in database, marks config changed, posts refresh notification, and shows 5s toast.
    public func handleProxyPortConflict(for connectionId: UUID, port: Int, reason: ProxyConflictReason) {
        Task { @MainActor in
            if var conn = try? await DependencyContainer.shared.connectionRepository.fetch(id: connectionId) {
                conn.socksProxyEnabled = false
                try? await DependencyContainer.shared.connectionRepository.update(conn)
                ConfigurationService.shared.markUnsavedChanges()
            }

            // Immediately broadcast data change to refresh all views (ConnectionList, MenuBar, etc.)
            NotificationCenter.default.post(name: .configurationDataDidChange, object: nil)
            self.objectWillChange.send()

            switch reason {
            case .usedBySession(let sessionName):
                ToastManager.shared.show(
                    title: L10n.tr("socks_port_in_use_title"),
                    message: L10n.tr("socks_port_in_use_desc", String(port), sessionName),
                    type: .warning,
                    duration: 5.0
                )
            case .alreadyBoundOrFailed:
                ToastManager.shared.show(
                    title: L10n.tr("socks_port_in_use_title"),
                    message: L10n.tr("socks_port_already_bound_desc", String(port)),
                    type: .warning,
                    duration: 5.0
                )
            }
        }
    }

    // MARK: - Session Health Monitor & Auto-Reconnect

    /// Starts a background monitor that checks SSH connection health every 60 seconds.
    /// If the SSH connection dies, automatically reconnects and restarts SOCKS5.
    private func startSessionMonitor(for connectionId: UUID) {
        // Cancel any existing monitor
        activeSessions[connectionId]?.monitorTask?.cancel()

        let task = Task { [weak self] in
            var consecutiveFailures = 0
            let maxRetries = 3

            while !Task.isCancelled {
                // Check every 60 seconds
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self = self else { break }

                guard let session = await MainActor.run(body: { self.activeSessions[connectionId] }),
                      session.socksServer != nil else {
                    break
                }

                // Check if SSH is still alive
                let isAlive = session.client.isConnected
                if isAlive {
                    consecutiveFailures = 0
                    continue
                }

                // SSH connection died — attempt reconnect
                consecutiveFailures += 1
                logWarning("SSH connection lost for \(session.connection.name) (attempt \(consecutiveFailures)/\(maxRetries)), reconnecting SOCKS5...", category: .network)

                if consecutiveFailures > maxRetries {
                    logError("Auto-reconnect failed after \(maxRetries) attempts for \(session.connection.name). Giving up.", category: .network)
                    await MainActor.run {
                        ToastManager.shared.show(
                            title: "SOCKS5 Proxy Disconnected",
                            message: "SSH connection to \(session.connection.name) was lost. Proxy stopped.",
                            type: .warning,
                            duration: 5.0
                        )
                    }
                    break
                }

                let success = await self.reconnectSession(connectionId: connectionId, session: session)
                if success {
                    consecutiveFailures = 0
                    logInfo("SOCKS5 proxy reconnected for \(session.connection.name)", category: .network)
                } else {
                    // Wait longer before retry on failure
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }

        activeSessions[connectionId]?.monitorTask = task
    }

    /// Reconnects SSH + SOCKS5 for an active session
    private func reconnectSession(connectionId: UUID, session: ActiveSession) async -> Bool {
        // Stop old SOCKS5 server
        await session.socksServer?.stop()
        try? await session.client.close()

        let connection = session.connection
        let normalizedHost = (connection.host.lowercased() == "localhost") ? "127.0.0.1" : connection.host

        do {
            let newClient: SSHClient

            if connection.authMethod == .password {
                let authMethod: SSHAuthenticationMethod = .passwordBased(
                    username: connection.username,
                    password: session.password
                )
                newClient = try await SSHClient.connect(
                    host: normalizedHost,
                    port: connection.port,
                    authenticationMethod: authMethod,
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never,
                    group: session.eventLoopGroup
                )
            } else if let keyPath = connection.privateKeyPath {
                let keyURL = URL(fileURLWithPath: keyPath)
                let keyData = try Data(contentsOf: keyURL)
                guard let keyString = String(data: keyData, encoding: .utf8) else {
                    return false
                }
                let authMethod: SSHAuthenticationMethod = try .rsa(
                    username: connection.username,
                    privateKey: .init(sshRsa: keyString)
                )
                newClient = try await SSHClient.connect(
                    host: normalizedHost,
                    port: connection.port,
                    authenticationMethod: authMethod,
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never,
                    group: session.eventLoopGroup
                )
            } else {
                return false
            }

            // Start new SOCKS5 proxy
            var newSocksServer: Socks5ProxyServer? = nil
            if connection.socksProxyEnabled && connection.socksProxyPort > 0 {
                let server = Socks5ProxyServer(
                    port: connection.socksProxyPort,
                    sshClient: newClient,
                    allowLAN: connection.socksProxyAllowLAN
                )
                try await server.start()
                newSocksServer = server
            }

            // Update session with new client
            await MainActor.run {
                let oldTask = self.activeSessions[connectionId]?.monitorTask
                self.activeSessions[connectionId] = ActiveSession(
                    connection: connection,
                    client: newClient,
                    eventLoopGroup: session.eventLoopGroup,
                    socksServer: newSocksServer,
                    password: session.password,
                    connectedAt: session.connectedAt,
                    monitorTask: oldTask
                )
            }

            return true
        } catch {
            logError("Failed to reconnect session for \(connection.name): \(error)", category: .network)
            return false
        }
    }
}
