//
//  StartupAutomationService.swift
//  macSSH
//
//  Coordinates automatic connection and Finder mounting on app launch
//  or when loading a saved configuration file.
//

import Foundation

@MainActor
final class StartupAutomationService {
    static let shared = StartupAutomationService()

    private var pendingLaunchAutomation = false
    private var isRunningAutomation = false
    private var unlockObserver: NSObjectProtocol?

    private init() {
        setupUnlockObserver()
    }

    // MARK: - Public Entry Points

    /// Runs startup auto-connect and auto-mount if the app is unlocked;
    /// otherwise waits until Touch ID / app lock is unlocked.
    func runOnLaunchIfUnlocked() async {
        if AppLockManager.shared.isLocked {
            pendingLaunchAutomation = true
            logInfo("[Startup] Deferred auto-connect/auto-mount until app lock is unlocked.", category: .app)
            return
        }

        pendingLaunchAutomation = false
        await runAutomation(reason: "startup")
    }

    /// Executes `autoConnect` and `autoMount` across all saved connections.
    func runAutomation(reason: String) async {
        guard !AppLockManager.shared.isLocked else {
            pendingLaunchAutomation = true
            return
        }

        guard !isRunningAutomation else { return }
        isRunningAutomation = true
        defer { isRunningAutomation = false }

        let connections: [Connection]
        do {
            connections = try await DependencyContainer.shared.connectionRepository.fetchAll()
        } catch {
            logError("[Startup] Failed to fetch connections for automation: \(error)", category: .database)
            return
        }

        let targets = connections.filter {
            $0.autoConnect || ($0.autoMount && $0.connectionType.supportsAutoMount)
        }
        guard !targets.isEmpty else { return }

        logInfo("[Startup] Running automation (\(reason)) for \(targets.count) connection(s)...", category: .network)

        var missingPasswordNames: [String] = []
        var runnableTargets: [(connection: Connection, password: String)] = []

        for connection in targets {
            if let password = resolvePasswordIfAvailable(for: connection) {
                runnableTargets.append((connection, password))
            } else {
                missingPasswordNames.append(connection.name)
                logWarning("[Startup] Skipped '\(connection.name)': password is not saved in the loaded configuration.", category: .auth)
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for target in runnableTargets {
                group.addTask { @MainActor in
                    await self.executeAutomation(for: target.connection, password: target.password)
                }
            }
        }

        if !missingPasswordNames.isEmpty {
            ToastManager.shared.show(
                title: L10n.tr("auto_startup_missing_password_title"),
                message: L10n.tr("auto_startup_missing_password", missingPasswordNames.joined(separator: ", ")),
                type: .warning,
                duration: 5.0
            )
        }
    }

    // MARK: - Private Helpers

    private func setupUnlockObserver() {
        unlockObserver = NotificationCenter.default.addObserver(
            forName: .appDidUnlock,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.pendingLaunchAutomation else { return }
                self.pendingLaunchAutomation = false
                await self.runAutomation(reason: "app unlocked")
            }
        }
    }

    private func resolvePasswordIfAvailable(for connection: Connection) -> String? {
        if let saved = ConnectionSessionManager.shared.getCachedPassword(for: connection.id) {
            return saved
        }
        if connection.authMethod == .privateKey || connection.supportsAnonymousAuth {
            return ""
        }
        return nil
    }

    private func executeAutomation(for connection: Connection, password: String) async {
        // Run Auto Connect before Auto Mount for the same connection so connect()
        // never tears down an already-mounted Finder volume when replacing a session.
        if connection.autoConnect {
            let sessionManager = ConnectionSessionManager.shared
            if !sessionManager.isConnected(connection.id) && !sessionManager.isConnecting(connection.id) {
                do {
                    try await sessionManager.connect(connection, password: password)
                    AnalyticsService.trackConnectionConnected(protocol: .init(from: connection.connectionType), success: true)
                    logSuccess("[AutoConnect] Connected to '\(connection.name)'", category: .network)
                } catch {
                    logError("[AutoConnect] Failed for '\(connection.name)': \(error.localizedDescription)", category: .network)
                }
            }
        }

        if connection.autoMount && connection.connectionType.supportsAutoMount {
            await FinderMountManager.shared.autoMountOnConnectIfEnabled(for: connection, password: password)
        }
    }
}
