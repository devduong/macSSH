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
    private(set) var uploadTransfers: [TransferProgress] = []
    private(set) var downloadTransfers: [TransferProgress] = []
    private var transferIndexById: [UUID: (type: TransferType, index: Int)] = [:]
    private var inProgressTransferIds: Set<UUID> = []

    // O(1) accurate session counters (preserved across large batches)
    private(set) var activeUploadCount: Int = 0
    private(set) var pendingUploadCount: Int = 0
    private(set) var uploadSuccessCount: Int = 0
    private(set) var uploadFailedCount: Int = 0
    private(set) var uploadCancelledCount: Int = 0

    private(set) var activeDownloadCount: Int = 0
    private(set) var pendingDownloadCount: Int = 0
    private(set) var downloadSuccessCount: Int = 0
    private(set) var downloadFailedCount: Int = 0
    private(set) var downloadCancelledCount: Int = 0

    // O(1) overall progress accumulators for active & pending items
    private var activeAndPendingTotalBytes: Int64 = 0
    private var activeAndPendingTransferredBytes: Int64 = 0

    // Bounded worker scheduler state
    private var pendingJobs: [PendingTransferJob] = []
    private var pendingJobsHead: Int = 0
    private var activeJobTokenByTransferId: [UUID: UUID] = [:]
    private var runningTransferTasks: [UUID: Task<Void, Never>] = [:]
    private var batchTrackers: [UUID: BatchCompletionTracker] = [:]

    private(set) var isPreparingTransfers: Bool = false
    private(set) var preparingTransferMessage: String = ""
    private(set) var latestTransferBatch: TransferBatchSignal?

    var ftpStreamsOverride: Int? = nil
    var isShowingTransfersPopover: Bool = false
    var draggedRemoteFiles: [RemoteFile] = []

    private static let maxCompletedHistoryPerQueue = 10_000

    struct TransferBatchSignal: Equatable {
        let sequence: Int
        let type: TransferType
    }

    private struct PendingTransferJob {
        let id: UUID
        let token: UUID
        let type: TransferType
        let remotePath: String
        let localURL: URL
        let totalBytes: Int64
        let perFileStreams: Int?
        let batchId: UUID?
        let showErrorAlertOnFailure: Bool
    }

    private final class BatchCompletionTracker {
        var remaining: Int
        let type: TransferType
        var continuations: [CheckedContinuation<Void, Never>] = []

        init(remaining: Int, type: TransferType) {
            self.remaining = remaining
            self.type = type
        }
    }

    var effectiveFTPStreams: Int {
        guard connection.connectionType == .ftp else { return 1 }
        return FTPTransferSettings.clamped(
            ftpStreamsOverride ?? connection.ftpMaxStreams ?? FTPTransferSettings.shared.maxConcurrentStreams
        )
    }

    func setSessionFTPStreams(_ count: Int) {
        let clamped = FTPTransferSettings.clamped(count)
        ftpStreamsOverride = clamped
        Task {
            await fileRepository.setPreferredMaxStreams(clamped)
        }
        addLog("FTP concurrent streams set to \(clamped)", level: .info)
        pumpTransferQueue()
    }

    /// Whether any transfer is currently active or queued
    var hasActiveTransfers: Bool {
        activeTransferCount > 0
    }

    /// Total number of active + queued transfers
    var activeTransferCount: Int {
        activeUploadCount + pendingUploadCount + activeDownloadCount + pendingDownloadCount
    }

    /// All transfers for display in the popover (uploads + downloads)
    var allTransfers: [TransferProgress] {
        if uploadTransfers.isEmpty { return downloadTransfers }
        if downloadTransfers.isEmpty { return uploadTransfers }
        return uploadTransfers + downloadTransfers
    }

    var totalUploadSpeed: Double {
        var sum: Double = 0
        for id in inProgressTransferIds {
            if let loc = transferIndexById[id], loc.type == .upload, loc.index < uploadTransfers.count {
                let item = uploadTransfers[loc.index]
                if item.isInProgress { sum += item.speed }
            }
        }
        return sum
    }

    var totalDownloadSpeed: Double {
        var sum: Double = 0
        for id in inProgressTransferIds {
            if let loc = transferIndexById[id], loc.type == .download, loc.index < downloadTransfers.count {
                let item = downloadTransfers[loc.index]
                if item.isInProgress { sum += item.speed }
            }
        }
        return sum
    }

    var totalUploadSpeedFormatted: String {
        let str = TransferByteFormatter.string(for: Int64(totalUploadSpeed))
        return "\(str)/s"
    }

    var totalDownloadSpeedFormatted: String {
        let str = TransferByteFormatter.string(for: Int64(totalDownloadSpeed))
        return "\(str)/s"
    }

    var hasCompletedTransfers: Bool {
        (uploadSuccessCount + uploadFailedCount + uploadCancelledCount +
         downloadSuccessCount + downloadFailedCount + downloadCancelledCount) > 0
    }

    func hasFinishedTransfers(for type: TransferType) -> Bool {
        switch type {
        case .upload:
            return (uploadSuccessCount + uploadFailedCount + uploadCancelledCount) > 0
        case .download:
            return (downloadSuccessCount + downloadFailedCount + downloadCancelledCount) > 0
        }
    }

    func hasSucceededTransfers(for type: TransferType) -> Bool {
        switch type {
        case .upload: return uploadSuccessCount > 0
        case .download: return downloadSuccessCount > 0
        }
    }

    func failedCount(for type: TransferType) -> Int {
        switch type {
        case .upload: return uploadFailedCount
        case .download: return downloadFailedCount
        }
    }

    func successCount(for type: TransferType) -> Int {
        switch type {
        case .upload: return uploadSuccessCount
        case .download: return downloadSuccessCount
        }
    }

    func cancelledCount(for type: TransferType) -> Int {
        switch type {
        case .upload: return uploadCancelledCount
        case .download: return downloadCancelledCount
        }
    }

    /// Overall progress of all active & queued transfers (0.0 to 1.0)
    var overallProgress: Double {
        guard activeAndPendingTotalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(activeAndPendingTransferredBytes) / Double(activeAndPendingTotalBytes)))
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
            if connection.connectionType == .ftp {
                let streams = effectiveFTPStreams
                await fileRepository.setPreferredMaxStreams(streams)
                addLog("FTP multi-stream enabled: \(streams) streams", level: .info)
            }
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

        // Cancel all running and pending transfer tasks
        for (_, task) in runningTransferTasks {
            task.cancel()
        }
        runningTransferTasks.removeAll()
        pendingJobs.removeAll()
        pendingJobsHead = 0
        activeJobTokenByTransferId.removeAll()
        for (_, tracker) in batchTrackers {
            for cont in tracker.continuations {
                cont.resume()
            }
        }
        batchTrackers.removeAll()

        // Purge transfer and log memory
        uploadTransfers.removeAll()
        downloadTransfers.removeAll()
        transferIndexById.removeAll()
        inProgressTransferIds.removeAll()
        activeUploadCount = 0
        pendingUploadCount = 0
        uploadSuccessCount = 0
        uploadFailedCount = 0
        uploadCancelledCount = 0
        activeDownloadCount = 0
        pendingDownloadCount = 0
        downloadSuccessCount = 0
        downloadFailedCount = 0
        downloadCancelledCount = 0
        activeAndPendingTotalBytes = 0
        activeAndPendingTransferredBytes = 0
        isPreparingTransfers = false
        preparingTransferMessage = ""
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
        guard let loc = transferIndexById[id] else { return }

        if loc.type == .upload {
            guard loc.index < uploadTransfers.count, uploadTransfers[loc.index].isInProgress else { return }
            let previousBytes = min(uploadTransfers[loc.index].bytesTransferred, uploadTransfers[loc.index].totalBytes)
            let clampedBytes = uploadTransfers[loc.index].totalBytes > 0
                ? min(uploadTransfers[loc.index].totalBytes, max(0, bytesTransferred))
                : max(0, bytesTransferred)
            let elapsed = Date().timeIntervalSince(uploadTransfers[loc.index].startTime)
            if elapsed > 0.2 {
                uploadTransfers[loc.index].speed = Double(bytesTransferred) / elapsed
            }
            uploadTransfers[loc.index].bytesTransferred = bytesTransferred
            let delta = max(0, clampedBytes) - max(0, previousBytes)
            activeAndPendingTransferredBytes = max(0, activeAndPendingTransferredBytes + delta)
        } else {
            guard loc.index < downloadTransfers.count, downloadTransfers[loc.index].isInProgress else { return }
            let previousBytes = min(downloadTransfers[loc.index].bytesTransferred, downloadTransfers[loc.index].totalBytes)
            let clampedBytes = downloadTransfers[loc.index].totalBytes > 0
                ? min(downloadTransfers[loc.index].totalBytes, max(0, bytesTransferred))
                : max(0, bytesTransferred)
            let elapsed = Date().timeIntervalSince(downloadTransfers[loc.index].startTime)
            if elapsed > 0.2 {
                downloadTransfers[loc.index].speed = Double(bytesTransferred) / elapsed
            }
            downloadTransfers[loc.index].bytesTransferred = bytesTransferred
            let delta = max(0, clampedBytes) - max(0, previousBytes)
            activeAndPendingTransferredBytes = max(0, activeAndPendingTransferredBytes + delta)
        }
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
        let streamCount: Int? = connection.connectionType == .ftp ? effectiveFTPStreams : nil

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            addLog("Loading file preview: \(file.name) (\(file.displaySize))")
            try await fileRepository.download(remotePath: file.path, to: localURL, streamCount: streamCount, progress: nil)
            viewedFileSession = ViewedFileSession(file: file, localURL: localURL)
            addLog("Opened file viewer for: \(file.name)", level: .info)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
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

    private var currentMaxConcurrentTransfers: Int {
        connection.connectionType == .ftp ? effectiveFTPStreams : 1
    }

    private var transferBatchSequence: Int = 0

    func downloadFile(_ file: RemoteFile) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let streamCount: Int? = connection.connectionType == .ftp ? effectiveFTPStreams : nil
        enqueueTransferBatch(
            items: [(fileName: file.name, localURL: url, remotePath: file.path, totalBytes: file.size)],
            type: .download,
            perFileStreams: streamCount,
            showErrorAlertOnFailure: true,
            awaitCompletion: false
        )
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

    /// Download multiple files/folders into a destination local directory (concurrently in FTP mode)
    func downloadFilesToLocal(_ files: [RemoteFile], localDirectory: URL) async {
        isPreparingTransfers = true
        preparingTransferMessage = L10n.tr("preparing_transfers")

        let collected = await collectDownloadItemsParallel(roots: files, localDirectory: localDirectory)
        let collectedItems = collected.items
        let directoriesToCreate = collected.directoriesToCreate

        // Perform local filesystem directory creation & existence probing off the main thread
        let prepResult: (existingIndices: Set<Int>, Void) = await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            for dirURL in directoriesToCreate {
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
            var existing = Set<Int>()
            for (idx, item) in collectedItems.enumerated() {
                if fm.fileExists(atPath: item.localURL.path) {
                    existing.insert(idx)
                }
            }
            return (existing, ())
        }.value

        isPreparingTransfers = false
        preparingTransferMessage = ""

        guard !collectedItems.isEmpty else {
            await localState.loadFiles(silent: true)
            return
        }

        // Resolve overwrite decisions upfront before dispatching parallel streams
        var approvedItems: [(file: RemoteFile, localURL: URL)] = []
        approvedItems.reserveCapacity(collectedItems.count)
        var replaceAll = false
        let hasMultipleConflicts = prepResult.existingIndices.count > 1

        for (idx, item) in collectedItems.enumerated() {
            if prepResult.existingIndices.contains(idx) && !replaceAll {
                let decision = confirmOverwriteBatch(
                    fileName: item.file.name,
                    destinationDescription: item.localURL.deletingLastPathComponent().path,
                    isUpload: false,
                    allowReplaceAll: hasMultipleConflicts
                )
                switch decision {
                case .replace:
                    break
                case .replaceAll:
                    replaceAll = true
                case .skip:
                    addLog("Download skipped: '\(item.file.name)' already exists locally", level: .warning)
                    continue
                case .cancelAll:
                    addLog("Download batch cancelled by user", level: .warning)
                    await localState.loadFiles(silent: true)
                    return
                }
            }
            approvedItems.append(item)
        }

        guard !approvedItems.isEmpty else {
            await localState.loadFiles(silent: true)
            return
        }

        let maxConcurrent = currentMaxConcurrentTransfers
        let perFileStreams: Int? = connection.connectionType == .ftp
            ? max(1, maxConcurrent / min(approvedItems.count, maxConcurrent))
            : nil

        if connection.connectionType == .ftp && (approvedItems.count > 1 || maxConcurrent > 1) {
            addLog("Starting FTP download of \(approvedItems.count) file(s) using up to \(maxConcurrent) stream(s)", level: .info)
        }

        let queueItems = approvedItems.map { (fileName: $0.file.name, localURL: $0.localURL, remotePath: $0.file.path, totalBytes: $0.file.size) }
        await enqueueTransferBatchAndWait(
            items: queueItems,
            type: .download,
            perFileStreams: perFileStreams,
            showErrorAlertOnFailure: approvedItems.count == 1
        )
    }

    private func collectDownloadItemsParallel(
        roots: [RemoteFile],
        localDirectory: URL
    ) async -> (items: [(file: RemoteFile, localURL: URL)], directoriesToCreate: [URL]) {
        var collectedItems: [(file: RemoteFile, localURL: URL)] = []
        var directoriesToCreate: [URL] = []
        var dirQueue: [(remotePath: String, name: String, localURL: URL)] = []

        for file in roots {
            let destURL = localDirectory.appendingPathComponent(file.name)
            if file.isDirectory {
                directoriesToCreate.append(destURL)
                dirQueue.append((file.path, file.name, destURL))
            } else {
                collectedItems.append((file, destURL))
            }
        }

        let maxConcurrentListings = connection.connectionType == .ftp ? min(4, max(1, effectiveFTPStreams)) : 1
        let repo = fileRepository

        while !dirQueue.isEmpty {
            let batchCount = min(maxConcurrentListings, dirQueue.count)
            let currentBatch = Array(dirQueue.prefix(batchCount))
            dirQueue.removeFirst(batchCount)

            let results: [(String, URL, Result<[RemoteFile], Error>)] = await withTaskGroup(
                of: (String, URL, Result<[RemoteFile], Error>).self
            ) { group in
                for dir in currentBatch {
                    group.addTask {
                        do {
                            let children = try await repo.listFiles(at: dir.remotePath)
                            return (dir.name, dir.localURL, .success(children))
                        } catch {
                            return (dir.name, dir.localURL, .failure(error))
                        }
                    }
                }
                var out: [(String, URL, Result<[RemoteFile], Error>)] = []
                out.reserveCapacity(currentBatch.count)
                for await result in group {
                    out.append(result)
                }
                return out
            }

            for (dirName, dirLocalURL, result) in results {
                switch result {
                case .success(let children):
                    for child in children {
                        let childDest = dirLocalURL.appendingPathComponent(child.name)
                        if child.isDirectory {
                            directoriesToCreate.append(childDest)
                            dirQueue.append((child.path, child.name, childDest))
                        } else {
                            collectedItems.append((child, childDest))
                        }
                    }
                case .failure(let error):
                    logError("Failed to list directory contents for '\(dirName)': \(error)", category: .sftp)
                    addLog("Failed to list folder '\(dirName)': \(error.localizedDescription)", level: .error)
                }
            }
        }

        return (collectedItems, directoriesToCreate)
    }

    // MARK: - Overwrite Confirmation Dialog

    private enum OverwriteDecision {
        case replace
        case replaceAll
        case skip
        case cancelAll
    }

    /// Displays an NSAlert modal asking the user whether to replace an existing file, replace all, skip, or cancel.
    private func confirmOverwriteBatch(
        fileName: String,
        destinationDescription: String,
        isUpload: Bool,
        allowReplaceAll: Bool
    ) -> OverwriteDecision {
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
        if allowReplaceAll {
            alert.addButton(withTitle: L10n.tr("replace_all"))
            alert.addButton(withTitle: L10n.tr("skip"))
            alert.addButton(withTitle: L10n.tr("cancel"))
        } else {
            alert.addButton(withTitle: L10n.tr("cancel"))
        }

        let response = alert.runModal()
        if allowReplaceAll {
            switch response {
            case .alertFirstButtonReturn: return .replace
            case .alertSecondButtonReturn: return .replaceAll
            case .alertThirdButtonReturn: return .skip
            default: return .cancelAll
            }
        } else {
            return response == .alertFirstButtonReturn ? .replace : .skip
        }
    }

    func uploadFiles() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        await uploadURLs(panel.urls)
    }

    /// Core upload method that scans local folders off the main thread and dispatches bounded concurrent transfers
    private func uploadURLs(_ urls: [URL], destinationDirectory: String? = nil) async {
        let targetDir = destinationDirectory ?? currentPath
        isPreparingTransfers = true
        preparingTransferMessage = L10n.tr("preparing_transfers")

        // Scan local filesystem tree off the main thread to keep the UI responsive
        let scanResult: (items: [(localURL: URL, remotePath: String, size: Int64)], directories: [String]) = await Task.detached(priority: .userInitiated) {
            var uploadItems: [(localURL: URL, remotePath: String, size: Int64)] = []
            var directoriesToEnsure: [String] = []
            let fm = FileManager.default

            for url in urls {
                guard url.isFileURL else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    let remoteBase = targetDir.appendingPathComponent(url.lastPathComponent)
                    directoriesToEnsure.append(remoteBase)
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
                        options: []
                    ) {
                        let basePath = url.path
                        while let itemURL = enumerator.nextObject() as? URL {
                            let resourceValues = try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
                            let relativePath = String(itemURL.path.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                            guard !relativePath.isEmpty else { continue }
                            let remoteChildPath = remoteBase.appendingPathComponent(relativePath)
                            if resourceValues?.isDirectory == true {
                                directoriesToEnsure.append(remoteChildPath)
                            } else if resourceValues?.isRegularFile == true {
                                let size = Int64(resourceValues?.fileSize ?? 0)
                                uploadItems.append((itemURL, remoteChildPath, size))
                            }
                        }
                    }
                } else {
                    let fileName = url.lastPathComponent
                    let remotePath = targetDir.appendingPathComponent(fileName)
                    let fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    uploadItems.append((url, remotePath, fileSize))
                }
            }

            return (uploadItems, directoriesToEnsure)
        }.value

        let uploadItems = scanResult.items
        let directoriesToEnsure = scanResult.directories

        // Create any selected/nested remote directories in batch
        if !directoriesToEnsure.isEmpty {
            try? await fileRepository.createDirectories(at: directoriesToEnsure)
        }

        guard !uploadItems.isEmpty else {
            isPreparingTransfers = false
            preparingTransferMessage = ""
            await loadFiles(silent: true)
            return
        }

        // Check existing top-level collisions upfront in one remote listing
        let existingTargetNames: Set<String>
        if targetDir == currentPath {
            existingTargetNames = Set(files.map(\.name))
        } else {
            let listed = (try? await fileRepository.listFiles(at: targetDir)) ?? []
            existingTargetNames = Set(listed.map(\.name))
        }

        isPreparingTransfers = false
        preparingTransferMessage = ""

        var approvedItems: [(localURL: URL, remotePath: String, size: Int64)] = []
        approvedItems.reserveCapacity(uploadItems.count)
        var replaceAll = false
        let topLevelConflicts = uploadItems.filter {
            $0.remotePath.directoryPath == targetDir && existingTargetNames.contains($0.localURL.lastPathComponent)
        }.count

        for item in uploadItems {
            let isTopLevel = item.remotePath.directoryPath == targetDir
            let fileName = item.localURL.lastPathComponent
            if isTopLevel && existingTargetNames.contains(fileName) && !replaceAll {
                let decision = confirmOverwriteBatch(
                    fileName: fileName,
                    destinationDescription: targetDir,
                    isUpload: true,
                    allowReplaceAll: topLevelConflicts > 1
                )
                switch decision {
                case .replace:
                    break
                case .replaceAll:
                    replaceAll = true
                case .skip:
                    addLog("Upload skipped: '\(fileName)' already exists on remote", level: .warning)
                    continue
                case .cancelAll:
                    addLog("Upload batch cancelled by user", level: .warning)
                    return
                }
            }
            approvedItems.append(item)
        }

        guard !approvedItems.isEmpty else { return }

        let maxConcurrent = currentMaxConcurrentTransfers
        if connection.connectionType == .ftp && approvedItems.count > 1 && maxConcurrent > 1 {
            addLog("Starting FTP upload of \(approvedItems.count) file(s) using up to \(maxConcurrent) concurrent stream(s)", level: .info)
        }

        let queueItems = approvedItems.map { (fileName: $0.localURL.lastPathComponent, localURL: $0.localURL, remotePath: $0.remotePath, totalBytes: $0.size) }
        await enqueueTransferBatchAndWait(
            items: queueItems,
            type: .upload,
            perFileStreams: nil,
            showErrorAlertOnFailure: approvedItems.count == 1
        )
    }

    // MARK: - Bounded Worker Transfer Scheduler

    private func enqueueTransferBatch(
        items: [(fileName: String, localURL: URL, remotePath: String, totalBytes: Int64)],
        type: TransferType,
        perFileStreams: Int?,
        showErrorAlertOnFailure: Bool,
        awaitCompletion: Bool
    ) {
        guard !items.isEmpty else { return }
        _ = enqueueBatchInternal(
            items: items,
            type: type,
            perFileStreams: perFileStreams,
            showErrorAlertOnFailure: showErrorAlertOnFailure,
            trackCompletion: awaitCompletion
        )
    }

    private func enqueueTransferBatchAndWait(
        items: [(fileName: String, localURL: URL, remotePath: String, totalBytes: Int64)],
        type: TransferType,
        perFileStreams: Int?,
        showErrorAlertOnFailure: Bool
    ) async {
        guard !items.isEmpty else { return }
        guard let batchId = enqueueBatchInternal(
            items: items,
            type: type,
            perFileStreams: perFileStreams,
            showErrorAlertOnFailure: showErrorAlertOnFailure,
            trackCompletion: true
        ) else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let tracker = batchTrackers[batchId], tracker.remaining > 0 {
                tracker.continuations.append(continuation)
            } else {
                continuation.resume()
            }
        }

        if type == .download {
            await localState.loadFiles(silent: true)
        } else {
            await loadFiles(silent: true)
        }
    }

    private func enqueueBatchInternal(
        items: [(fileName: String, localURL: URL, remotePath: String, totalBytes: Int64)],
        type: TransferType,
        perFileStreams: Int?,
        showErrorAlertOnFailure: Bool,
        trackCompletion: Bool
    ) -> UUID? {
        guard !items.isEmpty else { return nil }

        let batchId: UUID? = trackCompletion ? UUID() : nil
        if let batchId {
            batchTrackers[batchId] = BatchCompletionTracker(remaining: items.count, type: type)
        }

        var newTransfers: [TransferProgress] = []
        newTransfers.reserveCapacity(items.count)
        var newJobs: [PendingTransferJob] = []
        newJobs.reserveCapacity(items.count)
        var addedBytes: Int64 = 0

        for item in items {
            let transferId = UUID()
            let jobToken = UUID()
            activeJobTokenByTransferId[transferId] = jobToken
            let transfer = TransferProgress(
                id: transferId,
                fileName: item.fileName,
                localURL: item.localURL,
                remotePath: item.remotePath,
                bytesTransferred: 0,
                totalBytes: item.totalBytes,
                transferType: type,
                status: .pending
            )
            newTransfers.append(transfer)
            newJobs.append(PendingTransferJob(
                id: transferId,
                token: jobToken,
                type: type,
                remotePath: item.remotePath,
                localURL: item.localURL,
                totalBytes: item.totalBytes,
                perFileStreams: perFileStreams,
                batchId: batchId,
                showErrorAlertOnFailure: showErrorAlertOnFailure
            ))
            addedBytes += max(0, item.totalBytes)
        }

        // Single batch prepend to avoid N @Observable notifications on the main thread
        if type == .upload {
            uploadTransfers = newTransfers + uploadTransfers
            pendingUploadCount += newTransfers.count
            trimCompletedHistoryIfNeeded(for: .upload)
            rebuildTransferIndex(for: .upload)
        } else {
            downloadTransfers = newTransfers + downloadTransfers
            pendingDownloadCount += newTransfers.count
            trimCompletedHistoryIfNeeded(for: .download)
            rebuildTransferIndex(for: .download)
        }

        activeAndPendingTotalBytes += addedBytes
        pendingJobs.append(contentsOf: newJobs)

        transferBatchSequence += 1
        latestTransferBatch = TransferBatchSignal(sequence: transferBatchSequence, type: type)

        pumpTransferQueue()
        return batchId
    }

    private func pumpTransferQueue() {
        let limit = currentMaxConcurrentTransfers
        while runningTransferTasks.count < limit, pendingJobsHead < pendingJobs.count {
            let job = pendingJobs[pendingJobsHead]
            pendingJobsHead += 1

            if pendingJobsHead > 64 && pendingJobsHead * 2 >= pendingJobs.count {
                pendingJobs.removeFirst(pendingJobsHead)
                pendingJobsHead = 0
            }

            guard activeJobTokenByTransferId[job.id] == job.token else {
                markBatchItemFinished(batchId: job.batchId)
                continue
            }
            activeJobTokenByTransferId.removeValue(forKey: job.id)

            startTransferJob(job)
        }

        if pendingJobsHead >= pendingJobs.count {
            pendingJobs.removeAll()
            pendingJobsHead = 0
        }
    }

    private func startTransferJob(_ job: PendingTransferJob) {
        guard let loc = transferIndexById[job.id] else {
            markBatchItemFinished(batchId: job.batchId)
            return
        }

        let fileName: String
        if loc.type == .upload, loc.index < uploadTransfers.count {
            guard uploadTransfers[loc.index].status == .pending else {
                markBatchItemFinished(batchId: job.batchId)
                return
            }
            fileName = uploadTransfers[loc.index].fileName
        } else if loc.type == .download, loc.index < downloadTransfers.count {
            guard downloadTransfers[loc.index].status == .pending else {
                markBatchItemFinished(batchId: job.batchId)
                return
            }
            fileName = downloadTransfers[loc.index].fileName
        } else {
            markBatchItemFinished(batchId: job.batchId)
            return
        }

        transitionTransfer(id: job.id, to: .inProgress)

        let sizeText = TransferByteFormatter.string(for: job.totalBytes)
        if job.type == .download {
            addLog("Download started: \(fileName) (\(sizeText)) -> \(job.localURL.path)")
        } else {
            addLog("Upload started: \(fileName) (\(sizeText)) -> \(job.remotePath)")
        }

        let throttler = TransferProgressThrottler(totalBytes: job.totalBytes)
        let task = Task { [weak self] in
            guard let self = self else { return }

            do {
                try Task.checkCancellation()

                if job.type == .download {
                    try await self.fileRepository.download(
                        remotePath: job.remotePath,
                        to: job.localURL,
                        streamCount: job.perFileStreams
                    ) { [weak self] bytesTransferred in
                        guard throttler.shouldEmit(bytes: bytesTransferred) else { return }
                        Task { @MainActor [weak self] in
                            self?.updateTransferProgress(id: job.id, bytesTransferred: bytesTransferred)
                        }
                    }
                } else {
                    try await self.fileRepository.upload(
                        localURL: job.localURL,
                        to: job.remotePath
                    ) { [weak self] bytesTransferred in
                        guard throttler.shouldEmit(bytes: bytesTransferred) else { return }
                        Task { @MainActor [weak self] in
                            self?.updateTransferProgress(id: job.id, bytesTransferred: bytesTransferred)
                        }
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    self.transitionTransfer(id: job.id, to: .completed, bytesTransferred: job.totalBytes)
                    self.runningTransferTasks.removeValue(forKey: job.id)
                    if job.type == .download {
                        self.addLog("Download complete: \(fileName) (\(sizeText))", level: .success)
                    } else {
                        self.addLog("Upload complete: \(fileName) (\(sizeText))", level: .success)
                    }
                    self.markBatchItemFinished(batchId: job.batchId)
                    self.pumpTransferQueue()
                }

                if job.type == .download {
                    AnalyticsService.trackFileDownloaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: job.totalBytes)
                    logInfo("Downloaded: \(fileName)", category: .sftp)
                } else {
                    AnalyticsService.trackFileUploaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: job.totalBytes)
                    logInfo("Uploaded: \(fileName)", category: .sftp)
                }
            } catch {
                let isCancellation = error is CancellationError ||
                    Task.isCancelled ||
                    String(describing: error).contains("CancellationError")

                await MainActor.run {
                    self.runningTransferTasks.removeValue(forKey: job.id)
                    if isCancellation {
                        self.transitionTransfer(id: job.id, to: .cancelled)
                        self.addLog("\(job.type == .download ? "Download" : "Upload") cancelled: \(fileName)", level: .warning)
                    } else {
                        self.transitionTransfer(id: job.id, to: .failed, error: error.localizedDescription)
                        self.addLog("\(job.type == .download ? "Download" : "Upload") failed: \(fileName) - \(error.localizedDescription)", level: .error)
                        if job.showErrorAlertOnFailure {
                            self.error = AppError.from(error)
                        }
                    }
                    self.markBatchItemFinished(batchId: job.batchId)
                    self.pumpTransferQueue()
                }

                if isCancellation {
                    logInfo("\(job.type == .download ? "Download" : "Upload") cancelled: \(fileName)", category: .sftp)
                } else {
                    logError("\(job.type == .download ? "Download" : "Upload") failed for \(fileName): \(error)", category: .sftp)
                }
            }
        }

        runningTransferTasks[job.id] = task
    }

    private func markBatchItemFinished(batchId: UUID?) {
        guard let batchId, let tracker = batchTrackers[batchId] else { return }
        tracker.remaining -= 1
        if tracker.remaining <= 0 {
            let continuations = tracker.continuations
            batchTrackers.removeValue(forKey: batchId)
            for cont in continuations {
                cont.resume()
            }
        }
    }

    private func rebuildTransferIndex(for type: TransferType) {
        if type == .upload {
            for idx in uploadTransfers.indices {
                transferIndexById[uploadTransfers[idx].id] = (.upload, idx)
            }
        } else {
            for idx in downloadTransfers.indices {
                transferIndexById[downloadTransfers[idx].id] = (.download, idx)
            }
        }
    }

    private func adjustCounters(type: TransferType, status: TransferStatus, delta: Int) {
        switch (type, status) {
        case (.upload, .pending): pendingUploadCount = max(0, pendingUploadCount + delta)
        case (.upload, .inProgress): activeUploadCount = max(0, activeUploadCount + delta)
        case (.upload, .completed): uploadSuccessCount = max(0, uploadSuccessCount + delta)
        case (.upload, .failed): uploadFailedCount = max(0, uploadFailedCount + delta)
        case (.upload, .cancelled): uploadCancelledCount = max(0, uploadCancelledCount + delta)
        case (.download, .pending): pendingDownloadCount = max(0, pendingDownloadCount + delta)
        case (.download, .inProgress): activeDownloadCount = max(0, activeDownloadCount + delta)
        case (.download, .completed): downloadSuccessCount = max(0, downloadSuccessCount + delta)
        case (.download, .failed): downloadFailedCount = max(0, downloadFailedCount + delta)
        case (.download, .cancelled): downloadCancelledCount = max(0, downloadCancelledCount + delta)
        }
    }

    private func transitionTransfer(
        id: UUID,
        to newStatus: TransferStatus,
        bytesTransferred: Int64? = nil,
        error: String? = nil
    ) {
        guard let loc = transferIndexById[id] else { return }

        if loc.type == .upload {
            guard loc.index < uploadTransfers.count else { return }
            let oldStatus = uploadTransfers[loc.index].status
            guard oldStatus == .pending || oldStatus == .inProgress, oldStatus != newStatus else { return }

            let totalBytes = uploadTransfers[loc.index].totalBytes
            let oldClampedBytes = totalBytes > 0
                ? min(totalBytes, max(0, uploadTransfers[loc.index].bytesTransferred))
                : max(0, uploadTransfers[loc.index].bytesTransferred)

            adjustCounters(type: .upload, status: oldStatus, delta: -1)
            adjustCounters(type: .upload, status: newStatus, delta: 1)

            uploadTransfers[loc.index].status = newStatus
            if newStatus == .inProgress {
                uploadTransfers[loc.index].startTime = Date()
                uploadTransfers[loc.index].speed = 0
                uploadTransfers[loc.index].error = nil
                inProgressTransferIds.insert(id)
            } else {
                uploadTransfers[loc.index].speed = 0
                uploadTransfers[loc.index].error = error
                if let bytesTransferred {
                    uploadTransfers[loc.index].bytesTransferred = bytesTransferred
                }
                inProgressTransferIds.remove(id)
                activeAndPendingTotalBytes = max(0, activeAndPendingTotalBytes - max(0, totalBytes))
                activeAndPendingTransferredBytes = max(0, activeAndPendingTransferredBytes - oldClampedBytes)
                if activeTransferCount == 0 {
                    activeAndPendingTotalBytes = 0
                    activeAndPendingTransferredBytes = 0
                }
            }
        } else {
            guard loc.index < downloadTransfers.count else { return }
            let oldStatus = downloadTransfers[loc.index].status
            guard oldStatus == .pending || oldStatus == .inProgress, oldStatus != newStatus else { return }

            let totalBytes = downloadTransfers[loc.index].totalBytes
            let oldClampedBytes = totalBytes > 0
                ? min(totalBytes, max(0, downloadTransfers[loc.index].bytesTransferred))
                : max(0, downloadTransfers[loc.index].bytesTransferred)

            adjustCounters(type: .download, status: oldStatus, delta: -1)
            adjustCounters(type: .download, status: newStatus, delta: 1)

            downloadTransfers[loc.index].status = newStatus
            if newStatus == .inProgress {
                downloadTransfers[loc.index].startTime = Date()
                downloadTransfers[loc.index].speed = 0
                downloadTransfers[loc.index].error = nil
                inProgressTransferIds.insert(id)
            } else {
                downloadTransfers[loc.index].speed = 0
                downloadTransfers[loc.index].error = error
                if let bytesTransferred {
                    downloadTransfers[loc.index].bytesTransferred = bytesTransferred
                }
                inProgressTransferIds.remove(id)
                activeAndPendingTotalBytes = max(0, activeAndPendingTotalBytes - max(0, totalBytes))
                activeAndPendingTransferredBytes = max(0, activeAndPendingTransferredBytes - oldClampedBytes)
                if activeTransferCount == 0 {
                    activeAndPendingTotalBytes = 0
                    activeAndPendingTransferredBytes = 0
                }
            }
        }
    }

    private func trimCompletedHistoryIfNeeded(for type: TransferType) {
        if type == .upload {
            guard uploadTransfers.count > Self.maxCompletedHistoryPerQueue else { return }
            var excess = uploadTransfers.count - Self.maxCompletedHistoryPerQueue
            var kept: [TransferProgress] = []
            kept.reserveCapacity(Self.maxCompletedHistoryPerQueue)
            // Keep all active/pending/failed/cancelled items; drop oldest completed from tail
            for item in uploadTransfers.reversed() {
                if excess > 0 && item.status == .completed {
                    transferIndexById.removeValue(forKey: item.id)
                    excess -= 1
                } else {
                    kept.append(item)
                }
            }
            uploadTransfers = kept.reversed()
        } else {
            guard downloadTransfers.count > Self.maxCompletedHistoryPerQueue else { return }
            var excess = downloadTransfers.count - Self.maxCompletedHistoryPerQueue
            var kept: [TransferProgress] = []
            kept.reserveCapacity(Self.maxCompletedHistoryPerQueue)
            for item in downloadTransfers.reversed() {
                if excess > 0 && item.status == .completed {
                    transferIndexById.removeValue(forKey: item.id)
                    excess -= 1
                } else {
                    kept.append(item)
                }
            }
            downloadTransfers = kept.reversed()
        }
    }

    /// Cancels an active or queued transfer
    func cancelTransfer(_ transfer: TransferProgress) {
        guard transfer.isCancellable else { return }

        if let task = runningTransferTasks[transfer.id] {
            task.cancel()
        } else if transfer.status == .pending {
            activeJobTokenByTransferId.removeValue(forKey: transfer.id)
        }

        transitionTransfer(id: transfer.id, to: .cancelled)
        runningTransferTasks.removeValue(forKey: transfer.id)
        pumpTransferQueue()
    }

    /// Cancels all active and queued transfers
    func cancelAllTransfers() {
        for (id, task) in runningTransferTasks {
            task.cancel()
            transitionTransfer(id: id, to: .cancelled)
        }
        runningTransferTasks.removeAll()

        for job in pendingJobs[pendingJobsHead...] {
            transitionTransfer(id: job.id, to: .cancelled)
        }
        pendingJobs.removeAll()
        pendingJobsHead = 0
        activeJobTokenByTransferId.removeAll()

        for (_, tracker) in batchTrackers {
            for cont in tracker.continuations {
                cont.resume()
            }
        }
        batchTrackers.removeAll()
    }

    // MARK: - Retry Transfers

    /// Retries a single failed or cancelled transfer
    func retryTransfer(_ transfer: TransferProgress) {
        retryTransfers([transfer])
    }

    /// Retries all failed transfers for the given type (or both upload and download if nil)
    func retryAllFailed(type: TransferType? = nil) {
        var failedItems: [TransferProgress] = []
        if type == nil || type == .upload {
            failedItems.append(contentsOf: uploadTransfers.filter { $0.status == .failed && $0.isRetryable })
        }
        if type == nil || type == .download {
            failedItems.append(contentsOf: downloadTransfers.filter { $0.status == .failed && $0.isRetryable })
        }
        retryTransfers(failedItems)
    }

    private func retryTransfers(_ transfersToRetry: [TransferProgress]) {
        let retryable = transfersToRetry.filter { $0.isRetryable }
        guard !retryable.isEmpty else { return }

        let maxConcurrent = currentMaxConcurrentTransfers
        let requestedDownloadsCount = retryable.filter { $0.transferType == .download }.count
        let perFileDownloadStreams: Int? = connection.connectionType == .ftp && requestedDownloadsCount > 0
            ? max(1, maxConcurrent / min(requestedDownloadsCount, maxConcurrent))
            : nil

        let downloadBatchId = UUID()
        let uploadBatchId = UUID()

        var newJobs: [PendingTransferJob] = []
        newJobs.reserveCapacity(retryable.count)
        var addedBytes: Int64 = 0
        var retriedDownloads = 0
        var retriedUploads = 0

        for item in retryable {
            guard let localURL = item.localURL,
                  let loc = transferIndexById[item.id] else { continue }

            let oldStatus: TransferStatus
            var refreshedBytes = item.totalBytes

            if loc.type == .upload, loc.index < uploadTransfers.count {
                oldStatus = uploadTransfers[loc.index].status
                guard oldStatus == .failed || oldStatus == .cancelled else { continue }
                if let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) {
                    refreshedBytes = size
                }
                adjustCounters(type: .upload, status: oldStatus, delta: -1)
                adjustCounters(type: .upload, status: .pending, delta: 1)

                uploadTransfers[loc.index] = TransferProgress(
                    id: item.id,
                    fileName: item.fileName,
                    localURL: localURL,
                    remotePath: item.remotePath,
                    bytesTransferred: 0,
                    totalBytes: refreshedBytes,
                    transferType: .upload,
                    status: .pending
                )
                retriedUploads += 1
            } else if loc.type == .download, loc.index < downloadTransfers.count {
                oldStatus = downloadTransfers[loc.index].status
                guard oldStatus == .failed || oldStatus == .cancelled else { continue }
                adjustCounters(type: .download, status: oldStatus, delta: -1)
                adjustCounters(type: .download, status: .pending, delta: 1)

                downloadTransfers[loc.index] = TransferProgress(
                    id: item.id,
                    fileName: item.fileName,
                    localURL: localURL,
                    remotePath: item.remotePath,
                    bytesTransferred: 0,
                    totalBytes: refreshedBytes,
                    transferType: .download,
                    status: .pending
                )
                retriedDownloads += 1
            } else {
                continue
            }

            let jobToken = UUID()
            activeJobTokenByTransferId[item.id] = jobToken
            addedBytes += max(0, refreshedBytes)

            newJobs.append(PendingTransferJob(
                id: item.id,
                token: jobToken,
                type: item.transferType,
                remotePath: item.remotePath,
                localURL: localURL,
                totalBytes: refreshedBytes,
                perFileStreams: item.transferType == .download ? perFileDownloadStreams : nil,
                batchId: item.transferType == .download ? downloadBatchId : uploadBatchId,
                showErrorAlertOnFailure: retryable.count == 1
            ))
        }

        guard !newJobs.isEmpty else { return }

        if retriedDownloads > 0 {
            batchTrackers[downloadBatchId] = BatchCompletionTracker(remaining: retriedDownloads, type: .download)
            Task { @MainActor [weak self] in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    if let t = self?.batchTrackers[downloadBatchId], t.remaining > 0 {
                        t.continuations.append(cont)
                    } else {
                        cont.resume()
                    }
                }
                await self?.localState.loadFiles(silent: true)
            }
        }

        if retriedUploads > 0 {
            batchTrackers[uploadBatchId] = BatchCompletionTracker(remaining: retriedUploads, type: .upload)
            Task { @MainActor [weak self] in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    if let t = self?.batchTrackers[uploadBatchId], t.remaining > 0 {
                        t.continuations.append(cont)
                    } else {
                        cont.resume()
                    }
                }
                await self?.loadFiles(silent: true)
            }
        }

        activeAndPendingTotalBytes += addedBytes
        pendingJobs.append(contentsOf: newJobs)
        addLog("Retrying \(newJobs.count) transfer(s)", level: .info)

        pumpTransferQueue()
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
        downloadTransfers.insert(transfer, at: 0)
        activeDownloadCount += 1
        activeAndPendingTotalBytes += max(0, file.size)
        inProgressTransferIds.insert(transferId)
        rebuildTransferIndex(for: .download)
        addLog("Download started: \(file.name) (\(file.displaySize)) -> \(destinationURL.path)")

        let throttler = TransferProgressThrottler(totalBytes: file.size)
        do {
            try await fileRepository.download(remotePath: file.path, to: destinationURL) { [weak self] bytesTransferred in
                guard throttler.shouldEmit(bytes: bytesTransferred) else { return }
                Task { @MainActor [weak self] in
                    self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                }
            }

            transitionTransfer(id: transferId, to: .completed, bytesTransferred: file.size)
            AnalyticsService.trackFileDownloaded(protocol: .init(from: connection.connectionType), fileCount: 1, totalBytes: file.size)
            addLog("Download complete: \(file.name) (\(file.displaySize))", level: .success)
            logInfo("Downloaded via drag: \(file.name)", category: .sftp)
        } catch {
            transitionTransfer(id: transferId, to: .failed, error: error.localizedDescription)
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

    /// Clears finished transfers: removes completed items first (preserving failed items for retry),
    /// or clears all non-active items if no completed items remain in the target queue.
    func clearCompletedTransfers(type: TransferType? = nil) {
        if type == nil || type == .upload {
            let removeCompletedOnly = uploadSuccessCount > 0
            uploadTransfers.removeAll { item in
                let shouldRemove = removeCompletedOnly ? (item.status == .completed) : !item.isCancellable
                if shouldRemove {
                    transferIndexById.removeValue(forKey: item.id)
                }
                return shouldRemove
            }
            if removeCompletedOnly {
                uploadSuccessCount = 0
            } else {
                uploadSuccessCount = 0
                uploadFailedCount = 0
                uploadCancelledCount = 0
            }
            rebuildTransferIndex(for: .upload)
        }

        if type == nil || type == .download {
            let removeCompletedOnly = downloadSuccessCount > 0
            downloadTransfers.removeAll { item in
                let shouldRemove = removeCompletedOnly ? (item.status == .completed) : !item.isCancellable
                if shouldRemove {
                    transferIndexById.removeValue(forKey: item.id)
                }
                return shouldRemove
            }
            if removeCompletedOnly {
                downloadSuccessCount = 0
            } else {
                downloadSuccessCount = 0
                downloadFailedCount = 0
                downloadCancelledCount = 0
            }
            rebuildTransferIndex(for: .download)
        }
    }

    /// Removes a specific finished transfer from its queue
    func removeTransfer(_ transfer: TransferProgress) {
        guard !transfer.isCancellable, let loc = transferIndexById[transfer.id] else { return }
        adjustCounters(type: loc.type, status: transfer.status, delta: -1)
        transferIndexById.removeValue(forKey: transfer.id)
        if loc.type == .upload {
            uploadTransfers.removeAll { $0.id == transfer.id }
            rebuildTransferIndex(for: .upload)
        } else {
            downloadTransfers.removeAll { $0.id == transfer.id }
            rebuildTransferIndex(for: .download)
        }
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

        uploadTransfers.insert(transfer, at: 0)
        activeUploadCount += 1
        activeAndPendingTotalBytes += max(0, fileSize)
        inProgressTransferIds.insert(transferId)
        rebuildTransferIndex(for: .upload)
        let sizeText = TransferByteFormatter.string(for: fileSize)
        addLog("Auto-upload started: \(fileName) (\(sizeText)) -> \(remotePath)")

        let throttler = TransferProgressThrottler(totalBytes: fileSize)
        let uploadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try Task.checkCancellation()

                try await self.fileRepository.upload(localURL: localURL, to: remotePath) { [weak self] bytesTransferred in
                    guard throttler.shouldEmit(bytes: bytesTransferred) else { return }
                    Task { @MainActor [weak self] in
                        self?.updateTransferProgress(id: transferId, bytesTransferred: bytesTransferred)
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    self.transitionTransfer(id: transferId, to: .completed, bytesTransferred: fileSize)
                    self.runningTransferTasks.removeValue(forKey: transferId)
                    self.addLog("Auto-upload complete: \(fileName) (\(sizeText))", level: .success)
                }

                AnalyticsService.trackFileUploaded(protocol: .init(from: self.connection.connectionType), fileCount: 1, totalBytes: fileSize)
                logInfo("Auto-uploaded: \(fileName)", category: .sftp)
                await self.loadFiles(silent: true)

            } catch {
                await MainActor.run {
                    self.transitionTransfer(id: transferId, to: .failed, error: error.localizedDescription)
                    self.runningTransferTasks.removeValue(forKey: transferId)
                    self.addLog("Auto-upload failed: \(fileName) - \(error.localizedDescription)", level: .error)
                }
                logError("Auto-upload failed for \(fileName): \(error)", category: .sftp)
            }
        }

        runningTransferTasks[transferId] = uploadTask
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

// MARK: - Transfer Progress Throttler
private final class TransferProgressThrottler: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmitTime: CFAbsoluteTime = 0
    private let minInterval: CFAbsoluteTime
    private let totalBytes: Int64

    init(totalBytes: Int64, minInterval: CFAbsoluteTime = 0.12) {
        self.totalBytes = totalBytes
        self.minInterval = minInterval
    }

    func shouldEmit(bytes: Int64) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }
        if totalBytes > 0 && bytes >= totalBytes {
            lastEmitTime = now
            return true
        }
        if now - lastEmitTime >= minInterval {
            lastEmitTime = now
            return true
        }
        return false
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
