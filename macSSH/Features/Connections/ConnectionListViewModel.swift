//
//  ConnectionListViewModel.swift
//  macSSH
//
//  ViewModel for the connection list feature
//

import Foundation
import SwiftUI

enum SidebarSelection: Hashable, Sendable {
    case allConnections
    case folder(UUID)
}

@MainActor
@Observable
final class ConnectionListViewModel {
    // MARK: - Published State
    private(set) var connections: [Connection] = []
    private(set) var folders: [Folder] = []
    private(set) var state: ViewState<Void> = .idle
    var error: AppError?

    var selectedSidebarItem: SidebarSelection = .allConnections
    var searchText: String = ""
    var selectedConnectionId: UUID?
    var activeDetailConnectionId: UUID?

    // Sheet states
    var isShowingNewConnectionSheet = false
    var isShowingEditConnectionSheet = false
    var isShowingNewFolderSheet = false
    var isShowingPasswordPrompt = false
    var isShowingDeleteFolderAlert = false
    var isShowingLogPanel = true

    enum PasswordPromptTarget: Sendable {
        case connectSession
        case fileBrowser
        case terminal
    }
    var passwordPromptTarget: PasswordPromptTarget = .connectSession
    var authErrorMessage: String? = nil

    // Editing state
    var connectionToEdit: Connection?
    var connectionToConnect: Connection?
    var folderToDelete: Folder?
    var targetNewConnectionFolderId: UUID?

    // Window opening state
    var pendingWindowId: String?
    var pendingTerminalWindowId: String?

    // MARK: - Dependencies
    private let connectionRepository: ConnectionRepositoryProtocol
    private let folderRepository: FolderRepositoryProtocol
    private let windowManager: WindowManager

    // MARK: - Initialization
    init(
        connectionRepository: ConnectionRepositoryProtocol,
        folderRepository: FolderRepositoryProtocol,
        windowManager: WindowManager
    ) {
        self.connectionRepository = connectionRepository
        self.folderRepository = folderRepository
        self.windowManager = windowManager
    }

    // MARK: - Computed Properties

    var filteredConnections: [Connection] {
        var result: [Connection]

        switch selectedSidebarItem {
        case .allConnections:
            result = connections
        case .folder(let folderId):
            result = connections.filter { $0.folderId == folderId }
        }

        if !searchText.isEmpty {
            result = result.filter { connection in
                connection.name.localizedCaseInsensitiveContains(searchText) ||
                connection.host.localizedCaseInsensitiveContains(searchText) ||
                connection.username.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var unfolderedConnections: [Connection] {
        connections.filter { $0.folderId == nil }
    }

    var totalConnectionCount: Int {
        connections.count
    }

    func connectionCount(for folderId: UUID) -> Int {
        connections.filter { $0.folderId == folderId }.count
    }

    var selectedConnection: Connection? {
        guard let id = selectedConnectionId else { return nil }
        return connections.first { $0.id == id }
    }

    var activeDetailConnection: Connection? {
        guard let id = activeDetailConnectionId else { return nil }
        return connections.first { $0.id == id }
    }

    func handleConnectionClick(_ connection: Connection) {
        if selectedConnectionId == connection.id {
            activeDetailConnectionId = connection.id
        } else {
            selectedConnectionId = connection.id
            activeDetailConnectionId = nil
        }
    }

    var selectedFolder: Folder? {
        guard case .folder(let id) = selectedSidebarItem else { return nil }
        return folders.first { $0.id == id }
    }

    /// Contextual folder ID for creating a new connection (uses explicit target folder or currently selected sidebar folder)
    var currentContextFolderId: UUID? {
        targetNewConnectionFolderId ?? selectedFolder?.id
    }

    func requestNewConnection(inFolder folderId: UUID? = nil) {
        targetNewConnectionFolderId = folderId ?? selectedFolder?.id
        isShowingNewConnectionSheet = true
    }

    func cancelNewConnection() {
        isShowingNewConnectionSheet = false
        targetNewConnectionFolderId = nil
    }

    // MARK: - Data Loading

    func loadData() async {
        state = .loading

        do {
            async let connectionsTask = connectionRepository.fetchAll()
            async let foldersTask = folderRepository.fetchAll()

            connections = try await connectionsTask
            folders = try await foldersTask
            state = .success(())
        } catch {
            logError("Failed to load data: \(error)", category: .database)
            state = .error(AppError.from(error))
        }
    }

    func refresh() async {
        await loadData()
    }

    // MARK: - Connection Actions

    func saveConnection(_ connection: Connection, password: String?) async {
        do {
            try await connectionRepository.save(connection)

            if connection.savePassword, let password = password, !password.isEmpty {
                ConnectionSessionManager.shared.cachePassword(password, for: connection.id)
            } else if !connection.savePassword {
                ConnectionSessionManager.shared.clearPassword(for: connection.id)
            }

            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            isShowingNewConnectionSheet = false
            targetNewConnectionFolderId = nil
            AnalyticsService.trackConnectionCreated(protocol: .init(from: connection.connectionType))
            logInfo("Connection saved: \(connection.name)", category: .database)
        } catch {
            logError("Failed to save connection: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func updateConnection(_ connection: Connection, password: String?) async {
        do {
            try await connectionRepository.update(connection)

            if connection.savePassword, let password = password, !password.isEmpty {
                ConnectionSessionManager.shared.cachePassword(password, for: connection.id)
            } else if !connection.savePassword {
                ConnectionSessionManager.shared.clearPassword(for: connection.id)
            }

            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            isShowingEditConnectionSheet = false
            logInfo("Connection updated: \(connection.name)", category: .database)
        } catch {
            logError("Failed to update connection: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func deleteConnection(_ connection: Connection) async {
        do {
            await ConnectionSessionManager.shared.disconnect(connection.id)
            ConnectionSessionManager.shared.clearSession(for: connection.id)
            try await connectionRepository.delete(id: connection.id)
            if selectedConnectionId == connection.id {
                selectedConnectionId = nil
            }
            if activeDetailConnectionId == connection.id {
                activeDetailConnectionId = nil
            }
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            AnalyticsService.trackConnectionDeleted(protocol: .init(from: connection.connectionType))
            logInfo("Connection deleted: \(connection.name)", category: .database)
        } catch {
            logError("Failed to delete connection: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func moveConnection(_ connection: Connection, to folder: Folder?) async {
        do {
            try await connectionRepository.move(connectionId: connection.id, toFolderId: folder?.id)
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            logInfo("Connection moved: \(connection.name)", category: .database)
        } catch {
            logError("Failed to move connection: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func toggleProxy(_ connection: Connection) async {
        // If user is trying to enable proxy, check if the port is already used by an active session
        if !connection.socksProxyEnabled {
            if let activeName = ConnectionSessionManager.shared.activeConnectionName(forSocksPort: connection.socksProxyPort, excludingConnectionId: connection.id) {
                logWarning("Cannot enable proxy: port \(connection.socksProxyPort) is currently active on session '\(activeName)'", category: .network)
                self.error = AppError.unknown("Cổng SOCKS5 :\(connection.socksProxyPort) đang được sử dụng bởi kết nối đang chạy '\(activeName)'. Vui lòng chọn cổng khác hoặc ngắt kết nối trước.")
                return
            }
        }

        var updated = connection
        updated.socksProxyEnabled.toggle()
        do {
            try await connectionRepository.update(updated)
            if ConnectionSessionManager.shared.isConnected(connection.id) {
                try? await ConnectionSessionManager.shared.updateProxyState(for: connection.id, enabled: updated.socksProxyEnabled)
            }
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            logInfo("Proxy toggled for \(connection.name): \(updated.socksProxyEnabled)", category: .database)
        } catch {
            logError("Failed to toggle proxy: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func toggleSavePassword(_ connection: Connection) async {
        var updated = connection
        updated.savePassword.toggle()
        if !updated.savePassword {
            ConnectionSessionManager.shared.clearPassword(for: connection.id)
        }
        do {
            try await connectionRepository.update(updated)
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            logInfo("Save password toggled for \(connection.name): \(updated.savePassword)", category: .database)
        } catch {
            logError("Failed to toggle save password: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    // MARK: - Folder Actions

    func createFolder(name: String) async {
        let nextOrder = (folders.map(\.displayOrder).max() ?? -1) + 1
        let folder = Folder(name: name, displayOrder: nextOrder)

        do {
            try await folderRepository.save(folder)
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            isShowingNewFolderSheet = false
            AnalyticsService.track(.folderCreated)
            logInfo("Folder created: \(name)", category: .database)
        } catch {
            logError("Failed to create folder: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func reorderFolders(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        for (index, _) in folders.enumerated() {
            folders[index].displayOrder = index
        }
        Task {
            do {
                try await folderRepository.updateOrder(folders)
            } catch {
                logError("Failed to reorder folders: \(error)", category: .database)
                self.error = AppError.from(error)
            }
        }
    }

    func renameFolder(_ folder: Folder, to newName: String) async {
        var updatedFolder = folder
        updatedFolder.name = newName

        do {
            try await folderRepository.update(updatedFolder)
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            logInfo("Folder renamed: \(newName)", category: .database)
        } catch {
            logError("Failed to rename folder: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    func deleteFolder(_ folder: Folder) async {
        do {
            try await folderRepository.delete(id: folder.id)
            if case .folder(let id) = selectedSidebarItem, id == folder.id {
                selectedSidebarItem = .allConnections
            }
            ConfigurationService.shared.markUnsavedChanges()
            await loadData()
            isShowingDeleteFolderAlert = false
            folderToDelete = nil
            AnalyticsService.track(.folderDeleted)
            logInfo("Folder deleted: \(folder.name)", category: .database)
        } catch {
            logError("Failed to delete folder: \(error)", category: .database)
            self.error = AppError.from(error)
        }
    }

    // MARK: - Connection & Session Operations

    func connectToServer(_ connection: Connection) {
        logInfo("Connect session requested for: \(connection.name)", category: .ui)

        Task { @MainActor in
            let allowed = await AppLockManager.shared.authenticateForConnection()
            guard allowed else {
                logInfo("Connection cancelled: biometric auth denied", category: .auth)
                return
            }

            connectionToConnect = connection

            let isAnonymousOrGuest = connection.connectionType != .sftp &&
                ["anonymous", "guest", ""].contains(connection.username.lowercased())

            if let savedPassword = ConnectionSessionManager.shared.getCachedPassword(for: connection.id) {
                logInfo("Found password, establishing persistent session", category: .ui)
                await performSessionConnect(connection: connection, password: savedPassword)
            } else if connection.authMethod == .privateKey || isAnonymousOrGuest {
                logInfo("Key/Anonymous auth, establishing session without password prompt", category: .ui)
                await performSessionConnect(connection: connection, password: "")
            } else {
                logInfo("No saved password, showing password prompt", category: .ui)
                passwordPromptTarget = .connectSession
                isShowingPasswordPrompt = true
            }
        }
    }

    func disconnectConnection(_ connection: Connection) {
        Task { @MainActor in
            await ConnectionSessionManager.shared.disconnect(connection.id)
        }
    }

    func requestFileBrowser(for connection: Connection) {
        logInfo("File browser requested for: \(connection.name)", category: .ui)

        Task { @MainActor in
            let allowed = await AppLockManager.shared.authenticateForConnection()
            guard allowed else {
                logInfo("File browser cancelled: biometric auth denied", category: .auth)
                return
            }

            connectionToConnect = connection

            let isAnonymousOrGuest = connection.connectionType != .sftp &&
                ["anonymous", "guest", ""].contains(connection.username.lowercased())

            if let savedPassword = ConnectionSessionManager.shared.getCachedPassword(for: connection.id) {
                logInfo("Found password/session, opening file browser immediately", category: .ui)
                openFileBrowser(for: connection, password: savedPassword)
            } else if connection.authMethod == .privateKey || isAnonymousOrGuest {
                logInfo("Key/Anonymous auth, opening file browser", category: .ui)
                openFileBrowser(for: connection, password: "")
            } else {
                logInfo("No saved password, prompting password for file browser", category: .ui)
                passwordPromptTarget = .fileBrowser
                isShowingPasswordPrompt = true
            }
        }
    }

    func requestTerminal(for connection: Connection) {
        logInfo("Terminal requested for: \(connection.name)", category: .ui)

        Task { @MainActor in
            let allowed = await AppLockManager.shared.authenticateForConnection()
            guard allowed else {
                logInfo("Terminal cancelled: biometric auth denied", category: .auth)
                return
            }

            connectionToConnect = connection

            if let savedPassword = ConnectionSessionManager.shared.getCachedPassword(for: connection.id) {
                logInfo("Found password/session, opening terminal immediately", category: .ui)
                openTerminal(for: connection, password: savedPassword)
            } else if connection.authMethod == .privateKey {
                logInfo("Private key auth, opening terminal without password", category: .ui)
                openTerminal(for: connection, password: "")
            } else {
                logInfo("No saved password, prompting password for terminal", category: .ui)
                passwordPromptTarget = .terminal
                isShowingPasswordPrompt = true
            }
        }
    }

    func connectWithPassword(_ password: String) {
        guard let connection = connectionToConnect else { return }
        isShowingPasswordPrompt = false
        authErrorMessage = nil

        if !password.isEmpty {
            ConnectionSessionManager.shared.cachePassword(password, for: connection.id)
        }

        switch passwordPromptTarget {
        case .connectSession:
            Task {
                await performSessionConnect(connection: connection, password: password)
            }
        case .fileBrowser:
            openFileBrowser(for: connection, password: password)
        case .terminal:
            openTerminal(for: connection, password: password)
        }

        connectionToConnect = nil
    }

    func cancelConnect() {
        isShowingPasswordPrompt = false
        authErrorMessage = nil
        connectionToConnect = nil
    }

    private func performSessionConnect(connection: Connection, password: String) async {
        do {
            try await ConnectionSessionManager.shared.connect(connection, password: password)
            AnalyticsService.trackConnectionConnected(protocol: .init(from: connection.connectionType), success: true)
        } catch {
            logError("Failed to connect session: \(error)", category: .network)
            let appError = AppError.from(error)
            if case .authenticationFailed = appError {
                ConnectionSessionManager.shared.clearSession(for: connection.id)
                connectionToConnect = connection
                passwordPromptTarget = .connectSession
                authErrorMessage = loc(
                    "Authentication failed. Please check your password and try again.",
                    "Xác thực thất bại. Vui lòng kiểm tra lại mật khẩu và thử lại."
                )
                isShowingPasswordPrompt = true
            } else {
                self.error = appError
            }
        }
    }

    private func openFileBrowser(for connection: Connection, password: String) {
        let data = FileBrowserWindowData(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            connectionType: connection.connectionType,
            socksProxyEnabled: connection.socksProxyEnabled,
            socksProxyPort: connection.socksProxyPort,
            ftpMaxStreams: connection.ftpMaxStreams
        )

        let windowId = windowManager.storeFileBrowserData(data)
        logInfo("Stored window data with ID: \(windowId)", category: .ui)
        pendingWindowId = windowId
        AnalyticsService.trackFileBrowserOpened(protocol: .init(from: connection.connectionType))
    }

    func clearPendingWindow() {
        pendingWindowId = nil
    }

    func clearPendingTerminalWindow() {
        pendingTerminalWindowId = nil
    }

    // MARK: - Terminal Operations

    private func openTerminal(for connection: Connection, password: String) {
        // Only allow terminal for SFTP connections
        guard connection.connectionType == .sftp else {
            logWarning("Terminal only supported for SFTP connections", category: .ui)
            return
        }

        let data = TerminalWindowData(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            socksProxyEnabled: connection.socksProxyEnabled,
            socksProxyPort: connection.socksProxyPort
        )

        let windowId = windowManager.storeTerminalData(data)
        logInfo("Stored terminal window data with ID: \(windowId)", category: .ui)
        pendingTerminalWindowId = windowId
    }

    // MARK: - Edit Actions

    func editConnection(_ connection: Connection) {
        connectionToEdit = connection
        isShowingEditConnectionSheet = true
    }

    func duplicateConnection(_ connection: Connection) async {
        let newConnection = Connection(
            name: "\(connection.name) Copy",
            host: connection.host,
            port: connection.port,
            username: connection.username,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            savePassword: connection.savePassword,
            description: connection.description,
            tags: connection.tags,
            iconName: connection.iconName,
            folderId: connection.folderId,
            connectionType: connection.connectionType,
            socksProxyEnabled: connection.socksProxyEnabled,
            socksProxyPort: connection.socksProxyPort,
            ftpMaxStreams: connection.ftpMaxStreams
        )


        // Copy password if saved
        if connection.savePassword, let password = ConnectionSessionManager.shared.getCachedPassword(for: connection.id) {
            await saveConnection(newConnection, password: password)
        } else {
            await saveConnection(newConnection, password: nil)
        }
    }

    // MARK: - UI Actions

    func confirmDeleteFolder(_ folder: Folder) {
        folderToDelete = folder
        isShowingDeleteFolderAlert = true
    }

    func cancelDeleteFolder() {
        folderToDelete = nil
        isShowingDeleteFolderAlert = false
    }

    func clearError() {
        error = nil
    }

    func getSavedPassword(for connection: Connection) -> String? {
        ConnectionSessionManager.shared.getCachedPassword(for: connection.id)
    }
}
