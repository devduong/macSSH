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
        var socksTunnel: NativeSocksTunnel?
        let password: String
        let connectedAt: Date
    }

    @Published private(set) var activeSessions: [UUID: ActiveSession] = [:]
    @Published private(set) var connectingIds: Set<UUID> = []
    @Published private(set) var isInternetAvailable: Bool = true
    private var cachedPasswords: [UUID: String] = [:]
    private var internetObserver: Any?

    private init() {
        setupInternetMonitoring()
    }

    // MARK: - Internet Monitoring

    private func setupInternetMonitoring() {
        // Force initialization of NetworkMonitor singleton
        _ = NetworkMonitor.shared

        internetObserver = NotificationCenter.default.addObserver(
            forName: .internetStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let connected = notification.userInfo?["connected"] as? Bool ?? false
            Task { @MainActor in
                await self.handleInternetStatusChange(connected: connected)
            }
        }
    }

    private func handleInternetStatusChange(connected: Bool) async {
        let previousState = isInternetAvailable
        isInternetAvailable = connected
        objectWillChange.send()

        if !connected && previousState {
            // ── Internet Lost ──
            logWarning("Internet connection lost — all \(activeSessions.count) active session(s) marked as interrupted.", category: .network)
        } else if connected && !previousState {
            // ── Internet Restored ──
            logInfo("Internet connection restored — starting reconnection for \(activeSessions.count) active session(s)...", category: .network)
            await reconnectAllSessions()
        }
    }

    /// Kills all SOCKS5 PIDs, closes stale SSH clients, and reconnects every active session
    private func reconnectAllSessions() async {
        let sessionsSnapshot = activeSessions
        guard !sessionsSnapshot.isEmpty else {
            logInfo("No active sessions to reconnect.", category: .network)
            return
        }

        for (connectionId, session) in sessionsSnapshot {
            let connName = session.connection.name
            logInfo("[Reconnect] Processing session: \(connName) (ID: \(connectionId))", category: .network)

            // 1. Kill SOCKS5 tunnel PID
            if let tunnel = session.socksTunnel {
                logInfo("[Reconnect] Stopping SOCKS5 tunnel on port \(tunnel.socksPort) for \(connName)...", category: .socks5)
                await tunnel.stop()
                logInfo("[Reconnect] SOCKS5 tunnel stopped for \(connName).", category: .socks5)
            }

            // 2. Close old SSH client
            logInfo("[Reconnect] Closing stale SSH client for \(connName)...", category: .network)
            try? await session.client.close()
            try? await session.eventLoopGroup.shutdownGracefully()
            logInfo("[Reconnect] Old SSH client closed for \(connName).", category: .network)

            // 3. Remove old session
            activeSessions.removeValue(forKey: connectionId)

            // 4. Reconnect
            let password = session.password.isEmpty ? (cachedPasswords[connectionId] ?? "") : session.password
            logInfo("[Reconnect] Reconnecting to \(connName) (\(session.connection.host):\(session.connection.port))...", category: .network)

            do {
                try await connect(session.connection, password: password)
                logSuccess("[Reconnect] ✅ Successfully reconnected to \(connName).", category: .network)
            } catch {
                logError("[Reconnect] ❌ Failed to reconnect to \(connName): \(error.localizedDescription)", category: .network)

                // Show toast for failed reconnection
                ToastManager.shared.show(
                    title: L10n.tr("reconnect_failed"),
                    message: "\(connName): \(error.localizedDescription)",
                    type: .error,
                    duration: 5.0
                )

                // Clean up the failed connection state
                WindowManager.shared.markConnectionInactive(connectionId)
            }
        }

        objectWillChange.send()
        logInfo("[Reconnect] Reconnection process completed for all sessions.", category: .network)
    }

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

        var socksTunnel: NativeSocksTunnel? = nil
        if effectiveProxyEnabled && connection.socksProxyPort > 0 {
            let tunnel = NativeSocksTunnel(
                socksPort: connection.socksProxyPort,
                allowLAN: connection.socksProxyAllowLAN
            )
            do {
                try await tunnel.start(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    password: password,
                    privateKeyPath: connection.privateKeyPath,
                    passphrase: nil
                )
                socksTunnel = tunnel
                logInfo("Native SOCKS5 Proxy started on port \(connection.socksProxyPort) for \(connection.name) (allowLAN: \(connection.socksProxyAllowLAN))", category: .network)
            } catch {
                logError("Failed to start Native SOCKS5 proxy on port \(connection.socksProxyPort): \(error). Turning proxy OFF.", category: .network)
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
            socksTunnel: socksTunnel,
            password: password,
            connectedAt: Date()
        )

        activeSessions[connection.id] = session
        WindowManager.shared.markConnectionActive(connection.id)
        logInfo("Session established and retained for \(connection.name) (proxy: \(effectiveProxyEnabled ? "ON:\(connection.socksProxyPort)" : "OFF"))", category: .network)
    }

    /// Checks if a SOCKS proxy port is currently active on another session
    func isSocksProxyPortInUse(_ port: Int) -> Bool {
        activeSessions.values.contains {
            $0.socksTunnel?.socksPort == port && $0.connection.socksProxyEnabled
        }
    }

    /// Returns the name of the active connection currently using the specified SOCKS proxy port
    func activeConnectionName(forSocksPort port: Int, excludingConnectionId: UUID? = nil) -> String? {
        return activeSessions.values.first { session in
            session.connection.id != excludingConnectionId &&
            session.socksTunnel != nil &&
            session.connection.socksProxyPort == port
        }?.connection.name
    }

    // MARK: - Disconnect

    func disconnect(_ connectionId: UUID) async {
        guard let session = activeSessions.removeValue(forKey: connectionId) else {
            WindowManager.shared.markConnectionInactive(connectionId)
            return
        }

        await session.socksTunnel?.stop()
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
            if session.socksTunnel == nil && session.connection.socksProxyPort > 0 {
                if let activeName = activeConnectionName(forSocksPort: session.connection.socksProxyPort, excludingConnectionId: connectionId) {
                    handleProxyPortConflict(for: connectionId, port: session.connection.socksProxyPort, reason: .usedBySession(name: activeName))
                    return
                }

                let tunnel = NativeSocksTunnel(
                    socksPort: session.connection.socksProxyPort,
                    allowLAN: session.connection.socksProxyAllowLAN
                )
                do {
                    try await tunnel.start(
                        host: session.connection.host,
                        port: session.connection.port,
                        username: session.connection.username,
                        password: session.password,
                        privateKeyPath: session.connection.privateKeyPath,
                        passphrase: nil
                    )
                    session.socksTunnel = tunnel
                    var updatedConn = session.connection
                    updatedConn.socksProxyEnabled = true
                    let newSession = ActiveSession(
                        connection: updatedConn,
                        client: session.client,
                        eventLoopGroup: session.eventLoopGroup,
                        socksTunnel: tunnel,
                        password: session.password,
                        connectedAt: session.connectedAt
                    )
                    activeSessions[connectionId] = newSession
                    logInfo("Native SOCKS5 Proxy started dynamically on port \(session.connection.socksProxyPort) for \(session.connection.name)", category: .network)
                } catch {
                    logError("Failed to start Native SOCKS5 proxy dynamically on port \(session.connection.socksProxyPort): \(error)", category: .network)
                    handleProxyPortConflict(for: connectionId, port: session.connection.socksProxyPort, reason: .alreadyBoundOrFailed)
                }
            }
        } else {
            if let tunnel = session.socksTunnel {
                await tunnel.stop()
                var updatedConn = session.connection
                updatedConn.socksProxyEnabled = false
                let newSession = ActiveSession(
                    connection: updatedConn,
                    client: session.client,
                    eventLoopGroup: session.eventLoopGroup,
                    socksTunnel: nil,
                    password: session.password,
                    connectedAt: session.connectedAt
                )
                activeSessions[connectionId] = newSession
                logInfo("Native SOCKS5 Proxy stopped dynamically for \(session.connection.name)", category: .network)
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
}



