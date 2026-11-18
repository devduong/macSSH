//
//  FileBrowserViewModel.swift
//  macSSH
//
//  ViewModel for the file browser feature
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class FileBrowserViewModel {
    // MARK: - Published State
    private(set) var files: [RemoteFile] = []
    private(set) var state: ViewState<Void> = .idle
    var isRemoteLoading: Bool = false
    private(set) var currentPath: String = "/"
    private(set) var isConnected: Bool = false
    var error: AppError?

    // MARK: - Transfer Progress State
    private(set) var activeTransfers: [UUID: TransferProgress] = [:]
    private(set) var recentTransfers: [TransferProgress] = []  // Completed/failed transfers
    private var transferTasks: [UUID: Task<Void, Never>] = [:]  // Tasks for cancellation
    var isShowingTransfersPopover: Bool = false
    var draggedRemoteFiles: [RemoteFile] = []

    /// Whether any transfer is currently in progress
    var hasActiveTransfers: Bool {
        !activeTransfers.isEmpty
    }

    /// Total number of active transfers
    var activeTransferCount: Int {
        activeTransfers.count
    }

    /// All transfers for display (active + recent)
    var allTransfers: [TransferProgress] {
        let active = activeTransfers.values.sorted { $0.startTime > $1.startTime }
        return active + recentTransfers
    }

    /// Upload transfers (active + recent)
    var uploadTransfers: [TransferProgress] {
        let active = activeTransfers.values.filter { $0.transferType == .upload }.sorted { $0.startTime > $1.startTime }
        let recent = recentTransfers.filter { $0.transferType == .upload }
        return active + recent
    }

    /// Download transfers (active + recent)
    var downloadTransfers: [TransferProgress] {
        let active = activeTransfers.values.filter { $0.transferType == .download }.sorted { $0.startTime > $1.startTime }
        let recent = recentTransfers.filter { $0.transferType == .download }
        return active + recent
    }

    var activeUploadCount: Int {
        activeTransfers.values.filter { $0.transferType == .upload && $0.isInProgress }.count
    }

    var activeDownloadCount: Int {
        activeTransfers.values.filter { $0.transferType == .download && $0.isInProgress }.count
    }

    var totalUploadSpeed: Double {
        activeTransfers.values.filter { $0.transferType == .upload && $0.isInProgress }.reduce(0) { $0 + $1.speed }
    }

    var totalDownloadSpeed: Double {
        activeTransfers.values.filter { $0.transferType == .download && $0.isInProgress }.reduce(0) { $0 + $1.speed }
    }

    var totalUploadSpeedFormatted: String {
        let str = ByteCountFormatter.string(fromByteCount: Int64(totalUploadSpeed), countStyle: .file)
        return "\(str)/s"
    }

    var totalDownloadSpeedFormatted: String {
        let str = ByteCountFormatter.string(fromByteCount: Int64(totalDownloadSpeed), countStyle: .file)
        return "\(str)/s"
    }

    var hasCompletedTransfers: Bool {
        !recentTransfers.isEmpty
    }

    /// Overall progress of all active transfers (0.0 to 1.0)
    var overallProgress: Double {
        guard !activeTransfers.isEmpty else { return 0 }
        let totalBytes = activeTransfers.values.reduce(0) { $0 + $1.totalBytes }
        let transferredBytes = activeTransfers.values.reduce(0) { $0 + $1.bytesTransferred }
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    // MARK: - Activity Logs (In-Memory Session Only)
    var activityLogs: [SFTPLogEntry] = []

    func addLog(_ message: String, level: SFTPLogLevel = .info) {
        let entry = SFTPLogEntry(timestamp: Date(), level: level, message: message)
        activityLogs.insert(entry, at: 0)
        if activityLogs.count > 500 {
            activityLogs.removeLast(50)
        }
    }

    func clearLogs() {
        activityLogs.removeAll()
    }

    var selectedFiles: Set<UUID> = []
    var sortCriteria: RemoteFile.SortCriteria = .name
    var sortAscending: Bool = true
    var showHiddenFiles: Bool = true

    // Sheet states
    var isShowingNewFolderSheet = false
    var isShowingNewFileSheet = false
    var isShowingRenameSheet = false
    var isShowingMoveSheet = false
    var isShowingDeleteConfirmation = false

    // File to operate on
    var fileToRename: RemoteFile?
    var fileToMove: RemoteFile?
    var moveDestinationPath: String = ""
    var filesToDelete: [RemoteFile] = []
    var targetNewItemDirectory: String? = nil

    // Built-in File Viewer session (SFTP, FTP, SMB)
    struct ViewedFileSession: Identifiable {
        let id = UUID()
        let file: RemoteFile
        let localURL: URL
    }
    var viewedFileSession: ViewedFileSession? = nil

    // Window opening state
    var pendingFileInfoWindowId: String?
    var pendingEditorWindowId: String?
    var pendingTerminalWindowId: String?

    // MARK: - Local Files Pane State
    var localState = LocalFileBrowserState()

    // MARK: - Connection Info
    let connection: Connection
    private var password: String
    var isShowingPasswordPrompt = false
    var isAuthFailed = false

    // MARK: - Dependencies
    private let sftpSession: SFTPSessionProtocol
    private let fileRepository: FileRepositoryProtocol
    private let clipboardService: ClipboardService
    private let navigationService = NavigationService()

    // MARK: - Initialization
    init(
        connection: Connection,
        sftpSession: SFTPSessionProtocol,
        fileRepository: FileRepositoryProtocol,
        clipboardService: ClipboardService,
        password: String
    ) {
        self.connection = connection
        self.sftpSession = sftpSession
        self.fileRepository = fileRepository
        self.clipboardService = clipboardService
        self.password = password
    }

    // MARK: - Computed Properties

    var sortedFiles: [RemoteFile] {
        var result = files

        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }

        return RemoteFile.sortedFiles(result, by: sortCriteria, ascending: sortAscending)
    }

    var selectedFilesList: [RemoteFile] {
        files.filter { selectedFiles.contains($0.id) }
    }

    var canGoBack: Bool {
        navigationService.canGoBack
    }

    var canGoForward: Bool {
        navigationService.canGoForward
    }

    var canGoUp: Bool {
        currentPath != "/"
    }

    var pathComponents: [PathComponent] {
        var components: [PathComponent] = []
        var path = ""

        for component in currentPath.split(separator: "/") {
            path += "/" + component
            components.append(PathComponent(name: String(component), path: path))
        }

        if components.isEmpty {
            components.append(PathComponent(name: "/", path: "/"))
        }

        return components
    }

    var clipboardDisplayText: String {
        clipboardService.displayText
    }

    var hasClipboardItems: Bool {
        !clipboardService.isEmpty
    }

    var canPaste: Bool {
        clipboardService.canPaste(to: connection.id)
    }

    // MARK: - Connection

    func connect(withPassword newPassword: String? = nil) async {
        if let newPassword {
            self.password = newPassword
        }

        state = .loading

        do {
            var effectiveProxyEnabled = connection.socksProxyEnabled
            if effectiveProxyEnabled && connection.socksProxyPort > 0 {
                if let activeName = ConnectionSessionManager.shared.activeConnectionName(forSocksPort: connection.socksProxyPort, excludingConnectionId: connection.id) {
                    logWarning("SOCKS proxy port \(connection.socksProxyPort) is already in use by active session '\(activeName)'. Turning proxy OFF for \(connection.name).", category: .network)
                    effectiveProxyEnabled = false
                    ConnectionSessionManager.shared.handleProxyPortConflict(for: connection.id, port: connection.socksProxyPort, reason: .usedBySession(name: activeName))
                }
            }

            let socksPort = effectiveProxyEnabled ? connection.socksProxyPort : nil
            let allowLAN = effectiveProxyEnabled && connection.socksProxyAllowLAN
            if connection.authMethod == .password {
                try await sftpSession.connect(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    password: password,
                    socksProxyPort: socksPort,
                    socksProxyAllowLAN: allowLAN
                )
            } else if let keyPath = connection.privateKeyPath {
                try await sftpSession.connect(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    privateKeyPath: keyPath,
                    passphrase: password.isEmpty ? nil : password,
                    socksProxyPort: socksPort,
                    socksProxyAllowLAN: allowLAN
                )
            }
            isConnected = true
            isShowingPasswordPrompt = false
            isAuthFailed = false
            ConnectionSessionManager.shared.markConnected(for: connection.id)
            if !self.password.isEmpty {
                ConnectionSessionManager.shared.cachePassword(self.password, for: connection.id)
            }
            currentPath = await sftpSession.currentPath
            navigationService.reset(to: currentPath)
            await loadFiles()
            await localState.loadFiles()
        } catch {
            logError("Connection failed: \(error)", category: .sftp)
            let appError = AppError.from(error)
            state = .error(appError)
            if case .authenticationFailed = appError {
                isAuthFailed = true
                isShowingPasswordPrompt = true
                ConnectionSessionManager.shared.clearSession(for: connection.id)
            } else {
                self.error = appError
            }
        }
    }

    func disconnect() async {
        // Stop all external editing file watchers and clean up viewed file cache
        ExternalEditorService.shared.closeAllSessions()
        closeFileViewer()
        let previewRoot = "/tmp/macSSH_View/\(connection.id.uuidString)"
        try? FileManager.default.removeItem(atPath: previewRoot)

        // Cancel all ongoing transfer tasks
        for (_, task) in transferTasks {
            task.cancel()
        }
        transferTasks.removeAll()

        // Purge transfer and log memory
        activeTransfers.removeAll()
        recentTransfers.removeAll()
        activityLogs.removeAll()
        draggedRemoteFiles.removeAll()
        selectedFiles.removeAll()
        files.removeAll()

        // Purge local browser state memory
        localState.files.removeAll()
        localState.selectedFileIds.removeAll()

        // Disconnect SFTP network session & release event loop threads
        await sftpSession.disconnect()
        isConnected = false
        ConnectionSessionManager.shared.markDisconnected(for: connection.id)
        currentPath = "/"
        navigationService.reset()
    }

    deinit {
        let connectionId = connection.id
        Task { @MainActor in
            ConnectionSessionManager.shared.markDisconnected(for: connectionId)
        }
    }

    // MARK: - Navigation

    func updateTransferProgress(id: UUID, bytesTransferred: Int64) {
        guard var transfer = activeTransfers[id] else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(transfer.startTime)
        if elapsed > 0.2 {
            transfer.speed = Double(bytesTransferred) / elapsed
        }
        transfer.bytesTransferred = bytesTransferred
        activeTransfers[id] = transfer
    }

    func loadFiles(silent: Bool = false) async {
        if !silent {
            isRemoteLoading = true
            if !state.isSuccess {
                state = .loading
            }
        }
        defer {
            if !silent {
                isRemoteLoading = false
            }
        }

        do {
            let fetchedFiles = try await fileRepository.listFiles(at: currentPath)
            self.files = fetchedFiles
            self.currentPath = await sftpSession.currentPath
            self.state = .success(())
            addLog("Listed directory '\(currentPath)' (\(fetchedFiles.count) items)")
        } catch {
            logError("Failed to load files: \(error)", category: .sftp)
            addLog("Failed to list directory '\(currentPath)': \(error.localizedDescription)", level: .error)
            if !state.isSuccess {
                state = .error(AppError.from(error))
            } else {
                self.error = AppError.from(error)
            }
        }
    }

    func navigateTo(_ path: String) async {
        isRemoteLoading = true
        defer {
            isRemoteLoading = false
        }

        do {
            files = try await fileRepository.listFiles(at: path)
            currentPath = await sftpSession.currentPath
            navigationService.navigate(to: currentPath)
            selectedFiles.removeAll()
            state = .success(())
            addLog("Navigated to '\(currentPath)' (\(files.count) items)")
        } catch {
            logError("Failed to navigate to \(path): \(error)", category: .sftp)
            addLog("Failed to navigate to '\(path)': \(error.localizedDescription)", level: .error)
            if !state.isSuccess {
                state = .error(AppError.from(error))
            } else {
                self.error = AppError.from(error)
            }
        }
    }

    func openFile(_ file: RemoteFile) async {
        if file.isDirectory {
            await navigateTo(file.path)
        } else if FileTypeService.isPreviewable(file) {
            // Open in editor - handled by view
        }
    }

    func goBack() async {
        if let path = navigationService.goBack() {
            await navigateWithoutHistory(to: path)
        }
    }

    func goForward() async {
        if let path = navigationService.goForward() {
            await navigateWithoutHistory(to: path)
        }
    }

    func goUp() async {
        await navigateTo(currentPath.parentPath)
    }

    func goHome() async {
        await navigateTo("~")
    }

    func refresh(silent: Bool = false) async {
        await loadFiles(silent: silent)
    }

    private func navigateWithoutHistory(to path: String) async {
        isRemoteLoading = true
        defer {
            isRemoteLoading = false
        }

        do {
            files = try await fileRepository.listFiles(at: path)
            currentPath = await sftpSession.currentPath
            selectedFiles.removeAll()
            state = .success(())
            addLog("Navigated to '\(currentPath)' (\(files.count) items)")
        } catch {
            logError("Failed to navigate to \(path): \(error)", category: .sftp)
            addLog("Failed to navigate to '\(path)': \(error.localizedDescription)", level: .error)
            if !state.isSuccess {
                state = .error(AppError.from(error))
            } else {
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - File Operations

    func requestNewFolder(inDirectory dirPath: String? = nil) {
        if let dirPath {
            targetNewItemDirectory = dirPath
        } else if selectedRemoteFiles.count == 1, let selected = selectedRemoteFiles.first, selected.isDirectory {
            targetNewItemDirectory = selected.path
        } else {
            targetNewItemDirectory = currentPath
        }
        isShowingNewFolderSheet = true
    }

    func requestNewFile(inDirectory dirPath: String? = nil) {
        if let dirPath {
            targetNewItemDirectory = dirPath
        } else if selectedRemoteFiles.count == 1, let selected = selectedRemoteFiles.first, selected.isDirectory {
            targetNewItemDirectory = selected.path
        } else {
            targetNewItemDirectory = currentPath
        }
        isShowingNewFileSheet = true
    }

    func createFolder(name: String) async {
        let baseDir = targetNewItemDirectory ?? currentPath
        let path = baseDir.appendingPathComponent(name)
        targetNewItemDirectory = nil

        do {
            try await fileRepository.createDirectory(at: path)
            isShowingNewFolderSheet = false
            addLog("Created directory: \(path)", level: .info)
            AnalyticsService.trackFileOperation(.createFolder, protocol: .init(from: connection.connectionType))
            await loadFiles(silent: true)
        } catch {
            logError("Failed to create folder: \(error)", category: .sftp)
            addLog("Failed to create folder '\(name)': \(error.localizedDescription)", level: .error)
            self.error = AppError.from(error)
        }
    }

    func createFile(name: String) async {
        let baseDir = targetNewItemDirectory ?? currentPath
        let path = baseDir.appendingPathComponent(name)
        targetNewItemDirectory = nil

        do {
            try await fileRepository.createFile(at: path)
            isShowingNewFileSheet = false
            addLog("Created file: \(path)", level: .info)
            await loadFiles(silent: true)
        } catch {
            logError("Failed to create file: \(error)", category: .sftp)
            addLog("Failed to create file '\(name)': \(error.localizedDescription)", level: .error)
            self.error = AppError.from(error)
        }
    }

    // MARK: - Built-in File Viewer (SFTP, FTP, SMB)

    func viewFile(_ file: RemoteFile) async {
        guard file.isFile else { return }

        isRemoteLoading = true
        defer { isRemoteLoading = false }

        let tempDir = URL(fileURLWithPath: "/tmp/macSSH_View/\(connection.id.uuidString)/\(UUID().uuidString)")
        let localURL = tempDir.appendingPathComponent(file.name)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            addLog("Loading file preview: \(file.name) (\(file.displaySize))")
            try await fileRepository.download(remotePath: file.path, to: localURL)
            viewedFileSession = ViewedFileSession(file: file, localURL: localURL)
            addLog("Opened file viewer for: \(file.name)", level: .info)
        } catch {
            logError("Failed to load file for viewing: \(error)", category: .sftp)
            addLog("Failed to view '\(file.name)': \(error.localizedDescription)", level: .error)
            self.error = AppError.from(error)
        }
    }

    func closeFileViewer() {
        if let session = viewedFileSession {
            try? FileManager.default.removeItem(at: session.localURL.deletingLastPathComponent())
        }
        viewedFileSession = nil
    }

    func renameFile(_ file: RemoteFile, to newName: String) async {
        let newPath = file.path.directoryPath.appendingPathComponent(newName)

        do {
            try await fileRepository.rename(from: file.path, to: newPath)
            isShowingRenameSheet = false
            fileToRename = nil
            addLog("Renamed: '\(file.name)' -> '\(newName)'", level: .info)
            AnalyticsService.trackFileOperation(.rename, protocol: .init(from: connection.connectionType))
            await loadFiles(silent: true)
        } catch {
            logError("Failed to rename file: \(error)", category: .sftp)
            addLog("Failed to rename '\(file.name)': \(error.localizedDescription)", level: .error)
            self.error = AppError.from(error)
        }
    }

    func requestMove(_ file: RemoteFile) {
        fileToMove = file
        moveDestinationPath = currentPath
        isShowingMoveSheet = true
    }

    func confirmMove(to destination: String) async {
        guard let file = fileToMove else { return }
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await moveFiles([file], to: trimmed)
        isShowingMoveSheet = false
        fileToMove = nil
    }

    func deleteFiles(_ filesToDeleteList: [RemoteFile]) async {
        let deletedIds = Set(filesToDeleteList.map(\.id))
        // Optimistic dynamic removal immediately without reloading entire view:
        self.files.removeAll { deletedIds.contains($0.id) }
        self.selectedFiles.subtract(deletedIds)
        self.isShowingDeleteConfirmation = false
        self.filesToDelete = []

        for file in filesToDeleteList {
            do {
                try await fileRepository.delete(at: file.path, isDirectory: file.isDirectory)
                addLog("Deleted \(file.isDirectory ? "directory" : "file"): \(file.name)", level: .warning)
            } catch {
                logError("Failed to delete \(file.name): \(error)", category: .sftp)
                addLog("Failed to delete '\(file.name)': \(error.localizedDescription)", level: .error)
                self.error = AppError.from(error)
                await loadFiles(silent: true)
                return
            }
        }

        AnalyticsService.trackFileOperation(.delete, protocol: .init(from: connection.connectionType), count: filesToDeleteList.count)
        await loadFiles(silent: true)
    }

    func deleteSelectedFiles() async {
        await deleteFiles(selectedFilesList)
    }

    // MARK: - Clipboard Operations

    func copySelectedFiles() {
        clipboardService.copy(files: selectedFilesList, from: currentPath, connectionId: connection.id)
    }

    func cutSelectedFiles() {
        clipboardService.cut(files: selectedFilesList, from: currentPath, connectionId: connection.id)
    }

    func paste() async {
        guard canPaste else { return }

        let items = clipboardService.items
        let isCut = clipboardService.isCut

        for item in items {
            let destinationPath = currentPath.appendingPathComponent(item.fileName)

            do {
                if isCut {
                    try await fileRepository.move(from: item.fullSourcePath, to: destinationPath)
                } else {
                    try await fileRepository.copy(
                        from: item.fullSourcePath,
                        to: destinationPath,
                        isDirectory: item.isDirectory
                    )
                }
            } catch {
                logError("Failed to paste \(item.fileName): \(error)", category: .sftp)
                self.error = AppError.from(error)
                await loadFiles(silent: true)
                return
            }
        }

        if isCut {
            clipboardService.clear()
        }

        await loadFiles(silent: true)
    }

    // MARK: - Download/Upload

    func downloadFile(_ file: RemoteFile) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let transferId = UUID()
        let transfer = TransferProgress(
            id: transferId,
            fileName: file.name,
            localURL: url,
            remotePath: file.path,
            bytesTransferred: 0,
            totalBytes: file.size,
            transferType: .download,
            status: .inProgress
        )
        activeTransfers[transferId] = transfer
        addLog("Download started: \(file.name) (\(file.displaySize)) -> \(url.path)")

        let downloadTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try Task.checkCancellation()

                try await self.fileRepository.download(remotePath: file.path, to: url) { [weak self] bytesTransferred in
                    Task { @MainActor in
                        self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    if var completedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                        completedTransfer.status = .completed
                        completedTransfer.bytesTransferred = file.size
                        self.recentTransfers.insert(completedTransfer, at: 0)
                        if self.recentTransfers.count > 50 {
                            self.recentTransfers = Array(self.recentTransfers.prefix(50))
                        }
                    }
                    self.transferTasks.removeValue(forKey: transferId)
                    self.addLog("Download complete: \(file.name) (\(file.displaySize))", level: .success)
                }

                AnalyticsService.trackFileDownloaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: file.size)
                logInfo("Downloaded: \(file.name)", category: .sftp)

            } catch {
                let isCancellation = error is CancellationError ||
                    Task.isCancelled ||
                    String(describing: error).contains("CancellationError")

                if isCancellation {
                    await MainActor.run {
                        if var cancelledTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            cancelledTransfer.status = .cancelled
                            self.recentTransfers.insert(cancelledTransfer, at: 0)
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                        self.addLog("Download cancelled: \(file.name)", level: .warning)
                    }
                    logInfo("Download cancelled: \(file.name)", category: .sftp)
                } else {
                    await MainActor.run {
                        if var failedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            failedTransfer.status = .failed
                            failedTransfer.error = error.localizedDescription
                            self.recentTransfers.insert(failedTransfer, at: 0)
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                        self.addLog("Download failed: \(file.name) - \(error.localizedDescription)", level: .error)
                        self.error = AppError.from(error)
                    }

                    logError("Download failed: \(error)", category: .sftp)
                }
            }
        }

        transferTasks[transferId] = downloadTask
    }

    // MARK: - Dual-Pane Transfers (Local <-> Remote)

    var selectedRemoteFiles: [RemoteFile] {
        files.filter { selectedFiles.contains($0.id) }
    }

    /// Upload selected local files from the Local Pane to the Remote current directory
    func uploadSelectedLocalFiles() async {
        let selected = localState.selectedFiles
        guard !selected.isEmpty else { return }
        let urls = selected.map { URL(fileURLWithPath: $0.path) }
        await uploadURLs(urls, destinationDirectory: currentPath)
    }

    /// Upload a single local file (e.g. on double-click or context menu)
    func uploadLocalFile(_ file: RemoteFile) async {
        let url = URL(fileURLWithPath: file.path)
        await uploadURLs([url], destinationDirectory: currentPath)
    }

    /// Download selected remote files from the Remote Pane to the Local current directory
    func downloadSelectedRemoteFiles() async {
        let remoteList = selectedRemoteFiles
        guard !remoteList.isEmpty else { return }
        await downloadFilesToLocal(remoteList, localDirectory: localState.currentURL)
    }

    /// Download a single remote file to the Local current directory
    func downloadRemoteFileToLocalPane(_ file: RemoteFile) async {
        await downloadFilesToLocal([file], localDirectory: localState.currentURL)
    }

    /// Download multiple files/folders into a destination local directory
    func downloadFilesToLocal(_ files: [RemoteFile], localDirectory: URL) async {
        for file in files {
            let destURL = localDirectory.appendingPathComponent(file.name)
            await downloadItemToLocal(file: file, localURL: destURL)
        }
        await localState.loadFiles(silent: true)
    }

    // MARK: - Overwrite Confirmation Dialog

    /// Displays an NSAlert modal asking the user whether to replace an existing file or cancel.
    /// Returns true if the user confirmed replacement, false if cancelled.
    private func confirmOverwrite(fileName: String, destinationDescription: String, isUpload: Bool) -> Bool {
        let alert = NSAlert()
        if isUpload {
            alert.messageText = L10n.tr("file_exists_remote_title")
            alert.informativeText = L10n.tr("file_exists_remote_desc", fileName, destinationDescription)
        } else {
            alert.messageText = L10n.tr("file_exists_local_title")
            alert.informativeText = L10n.tr("file_exists_local_desc", fileName, destinationDescription)
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("replace"))
        alert.addButton(withTitle: L10n.tr("cancel"))

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private func downloadItemToLocal(file: RemoteFile, localURL: URL) async {
        if file.isDirectory {
            try? FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            do {
                let children = try await fileRepository.listFiles(at: file.path)
                for child in children {
                    let childDest = localURL.appendingPathComponent(child.name)
                    await downloadItemToLocal(file: child, localURL: childDest)
                }
            } catch {
                logError("Failed to download directory contents \(file.path): \(error)", category: .sftp)
                addLog("Failed to download folder '\(file.name)': \(error.localizedDescription)", level: .error)
            }
        } else {
            // Check if file already exists at local destination
            if FileManager.default.fileExists(atPath: localURL.path) {
                let shouldOverwrite = confirmOverwrite(
                    fileName: file.name,
                    destinationDescription: localURL.deletingLastPathComponent().path,
                    isUpload: false
                )
                if !shouldOverwrite {
                    addLog("Download skipped: '\(file.name)' already exists locally", level: .warning)
                    return
                }
            }

            do {
                try await downloadFileToURL(file, destinationURL: localURL)
            } catch {
                logError("Failed to download file \(file.name): \(error)", category: .sftp)
            }
        }
    }

    func uploadFiles() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        await uploadURLs(panel.urls)
    }

    /// Core upload method that handles multiple files with progress tracking
    private func uploadURLs(_ urls: [URL], destinationDirectory: String? = nil) async {
        let targetDir = destinationDirectory ?? currentPath

        for url in urls {
            guard url.isFileURL else { continue }

            let fileName = url.lastPathComponent
            let remotePath = targetDir.appendingPathComponent(fileName)

            // Check if file already exists on remote destination
            var fileExistsOnRemote = false
            if targetDir == currentPath {
                fileExistsOnRemote = files.contains(where: { $0.name == fileName })
            } else {
                if let _ = try? await fileRepository.getFileInfo(at: remotePath) {
                    fileExistsOnRemote = true
                }
            }

            if fileExistsOnRemote {
                let shouldOverwrite = confirmOverwrite(
                    fileName: fileName,
                    destinationDescription: targetDir,
                    isUpload: true
                )
                if !shouldOverwrite {
                    addLog("Upload skipped: '\(fileName)' already exists on remote", level: .warning)
                    continue
                }
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

            // Create transfer tracking entry
            let transferId = UUID()
            let transfer = TransferProgress(
                id: transferId,
                fileName: fileName,
                localURL: url,
                remotePath: remotePath,
                bytesTransferred: 0,
                totalBytes: fileSize,
                transferType: .upload,
                status: .inProgress
            )
            activeTransfers[transferId] = transfer
            addLog("Upload started: \(fileName) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))) -> \(remotePath)")

            // Create a task for this upload so it can be cancelled
            let uploadTask = Task { [weak self] in
                guard let self = self else { return }

                do {
                    // Check for cancellation before starting
                    try Task.checkCancellation()

                    try await self.fileRepository.upload(localURL: url, to: remotePath) { [weak self] bytesTransferred in
                        Task { @MainActor in
                            self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                        }
                    }

                    // Check for cancellation after upload
                    try Task.checkCancellation()

                    // Mark as completed
                    await MainActor.run {
                        if var completedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                            completedTransfer.status = .completed
                            completedTransfer.bytesTransferred = fileSize
                            self.recentTransfers.insert(completedTransfer, at: 0)
                            if self.recentTransfers.count > 50 {
                                self.recentTransfers = Array(self.recentTransfers.prefix(50))
                            }
                        }
                        self.transferTasks.removeValue(forKey: transferId)
                        self.addLog("Upload complete: \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))", level: .success)
                    }

                    AnalyticsService.trackFileUploaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: fileSize)
                    logInfo("Uploaded: \(url.lastPathComponent)", category: .sftp)

                } catch {
                    let isCancellation = error is CancellationError ||
                        Task.isCancelled ||
                        String(describing: error).contains("CancellationError")

                    if isCancellation {
                        await MainActor.run {
                            if var cancelledTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                                cancelledTransfer.status = .cancelled
                                self.recentTransfers.insert(cancelledTransfer, at: 0)
                            }
                            self.transferTasks.removeValue(forKey: transferId)
                            self.addLog("Upload cancelled: \(url.lastPathComponent)", level: .warning)
                        }
                        logInfo("Upload cancelled: \(url.lastPathComponent)", category: .sftp)
                    } else {
                        await MainActor.run {
                            if var failedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                                failedTransfer.status = .failed
                                failedTransfer.error = error.localizedDescription
                                self.recentTransfers.insert(failedTransfer, at: 0)
                            }
                            self.transferTasks.removeValue(forKey: transferId)
                            self.addLog("Upload failed: \(url.lastPathComponent) - \(error.localizedDescription)", level: .error)
                            self.error = AppError.from(error)
                        }

                        logError("Upload failed: \(error)", category: .sftp)
                    }
                }
            }

            transferTasks[transferId] = uploadTask

            // Wait for this upload to complete before starting the next one
            await uploadTask.value
        }

        await loadFiles(silent: true)
    }

    /// Cancels an active transfer
    func cancelTransfer(_ transfer: TransferProgress) {
        guard transfer.isInProgress else { return }

        // Cancel the task
        if let task = transferTasks[transfer.id] {
            task.cancel()
        }

        // Immediately update UI to show cancelled state
        if var cancelledTransfer = activeTransfers.removeValue(forKey: transfer.id) {
            cancelledTransfer.status = .cancelled
            recentTransfers.insert(cancelledTransfer, at: 0)
        }
        transferTasks.removeValue(forKey: transfer.id)
    }

    /// Cancels all active transfers
    func cancelAllTransfers() {
        for (id, task) in transferTasks {
            task.cancel()
            if var cancelledTransfer = activeTransfers.removeValue(forKey: id) {
                cancelledTransfer.status = .cancelled
                recentTransfers.insert(cancelledTransfer, at: 0)
            }
        }
        transferTasks.removeAll()
    }

    // MARK: - Drag and Drop

    /// Downloads a file to a specific URL (used for drag-out file promises)
    func downloadFileToURL(_ file: RemoteFile, destinationURL: URL) async throws {
        let transferId = UUID()
        let transfer = TransferProgress(
            id: transferId,
            fileName: file.name,
            localURL: destinationURL,
            remotePath: file.path,
            bytesTransferred: 0,
            totalBytes: file.size,
            transferType: .download,
            status: .inProgress
        )
        activeTransfers[transferId] = transfer
        addLog("Download started: \(file.name) (\(file.displaySize)) -> \(destinationURL.path)")

        do {
            try await fileRepository.download(remotePath: file.path, to: destinationURL) { [weak self] bytesTransferred in
                Task { @MainActor in
                    self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                }
            }

            if var completedTransfer = activeTransfers.removeValue(forKey: transferId) {
                completedTransfer.status = .completed
                completedTransfer.bytesTransferred = file.size
                recentTransfers.insert(completedTransfer, at: 0)
                if recentTransfers.count > 50 {
                    recentTransfers = Array(recentTransfers.prefix(50))
                }
            }

            AnalyticsService.trackFileDownloaded(protocol: .init(from: connection.connectionType), fileCount: 1, totalBytes: file.size)
            addLog("Download complete: \(file.name) (\(file.displaySize))", level: .success)
            logInfo("Downloaded via drag: \(file.name)", category: .sftp)
        } catch {
            if var failedTransfer = activeTransfers.removeValue(forKey: transferId) {
                failedTransfer.status = .failed
                failedTransfer.error = error.localizedDescription
                recentTransfers.insert(failedTransfer, at: 0)
            }
            addLog("Download failed for '\(file.name)': \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    /// Uploads files dropped from Finder into the specified or current directory
    func uploadDroppedFiles(_ urls: [URL], to destinationDirectory: String? = nil) async {
        await uploadURLs(urls, destinationDirectory: destinationDirectory)
    }

    /// Moves remote files to a destination directory
    func moveFiles(_ files: [RemoteFile], to targetDirectory: String) async {
        guard isConnected else { return }

        for file in files {
            guard file.path != targetDirectory else { continue }
            let targetPath = targetDirectory.appendingPathComponent(file.name)
            guard file.path != targetPath else { continue }

            do {
                try await fileRepository.rename(from: file.path, to: targetPath)
                AnalyticsService.trackFileOperation(.rename, protocol: .init(from: connection.connectionType))
            } catch {
                logError("Failed to move file '\(file.name)' to '\(targetDirectory)': \(error)", category: .sftp)
                self.error = AppError.from(error)
            }
        }

        await refresh(silent: true)
    }

    /// Clears completed/failed transfers from the list
    func clearCompletedTransfers() {
        recentTransfers.removeAll()
    }

    /// Removes a specific transfer from the recent list
    func removeTransfer(_ transfer: TransferProgress) {
        recentTransfers.removeAll { $0.id == transfer.id }
    }

    // MARK: - File Content

    func getFileContent(_ file: RemoteFile) async throws -> String {
        try await fileRepository.readFileContent(at: file.path)
    }

    func saveFileContent(_ content: String, to path: String) async throws {
        try await fileRepository.writeFileContent(content, to: path)
    }

    // MARK: - Open With External App

    /// Opens a remote file with the default system application.
    /// File is downloaded to a temp location, opened externally, and monitored for changes.
    /// When the user saves in the external app, the file is auto-uploaded back to remote.
    func openWithExternalApp(_ file: RemoteFile) async {
        guard file.isFile else { return }

        let service = ExternalEditorService.shared
        service.onLog = { [weak self] message, level in
            self?.addLog(message, level: level)
        }

        await service.openFileExternally(
            file: file,
            connectionId: connection.id,
            downloadHandler: { [weak self] remoteFile, localURL in
                guard let self = self else { throw AppError.unknown("Disconnected") }
                try await self.fileRepository.download(remotePath: remoteFile.path, to: localURL)
            },
            uploadHandler: { [weak self] localURL, remotePath in
                guard let self = self else { return }
                await self.performAutoUpload(localURL: localURL, remotePath: remotePath)
            }
        )
    }

    /// Opens a remote file with a specific application.
    func openWithSpecificApp(_ file: RemoteFile, applicationURL: URL) async {
        guard file.isFile else { return }

        let service = ExternalEditorService.shared
        service.onLog = { [weak self] message, level in
            self?.addLog(message, level: level)
        }

        await service.openFileWithApp(
            file: file,
            connectionId: connection.id,
            applicationURL: applicationURL,
            downloadHandler: { [weak self] remoteFile, localURL in
                guard let self = self else { throw AppError.unknown("Disconnected") }
                try await self.fileRepository.download(remotePath: remoteFile.path, to: localURL)
            },
            uploadHandler: { [weak self] localURL, remotePath in
                guard let self = self else { return }
                await self.performAutoUpload(localURL: localURL, remotePath: remotePath)
            }
        )
    }

    /// Handles uploading a modified file from external editor back to remote,
    /// creating a tracked TransferProgress entry in the Upload Queue and Activity Log.
    private func performAutoUpload(localURL: URL, remotePath: String) async {
        let fileName = localURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        let transferId = UUID()
        let transfer = TransferProgress(
            id: transferId,
            fileName: fileName,
            localURL: localURL,
            remotePath: remotePath,
            bytesTransferred: 0,
            totalBytes: fileSize,
            transferType: .upload,
            status: .inProgress
        )

        activeTransfers[transferId] = transfer
        addLog("Auto-upload started: \(fileName) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))) -> \(remotePath)")

        let uploadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try Task.checkCancellation()

                try await self.fileRepository.upload(localURL: localURL, to: remotePath) { [weak self] bytesTransferred in
                    Task { @MainActor in
                        self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    if var completedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                        completedTransfer.status = .completed
                        completedTransfer.bytesTransferred = fileSize
                        self.recentTransfers.insert(completedTransfer, at: 0)
                        if self.recentTransfers.count > 50 {
                            self.recentTransfers = Array(self.recentTransfers.prefix(50))
                        }
                    }
                    self.transferTasks.removeValue(forKey: transferId)
                    self.addLog("Auto-upload complete: \(fileName) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))", level: .success)
                }

                AnalyticsService.trackFileUploaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: fileSize)
                logInfo("Auto-uploaded: \(fileName)", category: .sftp)
                await self.loadFiles(silent: true)

            } catch {
                await MainActor.run {
                    if var failedTransfer = self.activeTransfers.removeValue(forKey: transferId) {
                        failedTransfer.status = .failed
                        failedTransfer.error = error.localizedDescription
                        self.recentTransfers.insert(failedTransfer, at: 0)
                    }
                    self.transferTasks.removeValue(forKey: transferId)
                    self.addLog("Auto-upload failed: \(fileName) - \(error.localizedDescription)", level: .error)
                }
                logError("Auto-upload failed for \(fileName): \(error)", category: .sftp)
            }
        }

        transferTasks[transferId] = uploadTask
        await uploadTask.value
    }
    // MARK: - Selection

    func selectAll() {
        selectedFiles = Set(sortedFiles.map { $0.id })
    }

    func deselectAll() {
        selectedFiles.removeAll()
    }

    func toggleSelection(for file: RemoteFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    // MARK: - UI Actions

    func confirmDelete(_ files: [RemoteFile]) {
        filesToDelete = files
        isShowingDeleteConfirmation = true
    }

    func confirmDeleteSelected() {
        confirmDelete(selectedFilesList)
    }

    func startRename(_ file: RemoteFile) {
        fileToRename = file
        isShowingRenameSheet = true
    }

    func showFileInfo(_ file: RemoteFile) {
        let data = FileInfoWindowData(
            file: file,
            connectionName: connection.name
        )
        let windowId = WindowManager.shared.storeFileInfoData(data)
        pendingFileInfoWindowId = windowId
        AnalyticsService.track(.fileInfoOpened)
    }

    func clearPendingFileInfoWindow() {
        pendingFileInfoWindowId = nil
    }

    func openEditor(for file: RemoteFile, content: String) {
        let data = FileEditorWindowData(
            filePath: file.path,
            fileName: file.name,
            content: content,
            connectionId: connection.id,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            connectionType: connection.connectionType
        )
        let windowId = WindowManager.shared.storeFileEditorData(data)
        pendingEditorWindowId = windowId
        AnalyticsService.trackEditorOpened(fileExtension: (file.name as NSString).pathExtension)
    }

    func clearPendingEditorWindow() {
        pendingEditorWindowId = nil
    }

    func clearPendingTerminalWindow() {
        pendingTerminalWindowId = nil
    }

    // MARK: - Terminal

    func openTerminal() {
        // Only supported for SFTP connections
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
            socksProxyPort: connection.socksProxyPort,
            socksProxyAllowLAN: connection.socksProxyAllowLAN
        )

        let windowId = WindowManager.shared.storeTerminalData(data)
        pendingTerminalWindowId = windowId
        logInfo("Opening terminal from file browser", category: .ui)
    }

    func clearError() {
        error = nil
    }
}

// MARK: - Path Component
struct PathComponent: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String

    static func == (lhs: PathComponent, rhs: PathComponent) -> Bool {
        lhs.path == rhs.path && lhs.name == rhs.name
    }
}
