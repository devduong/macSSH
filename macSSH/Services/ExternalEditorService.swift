//
//  ExternalEditorService.swift
//  macSSH
//
//  Service that manages opening remote files with external applications.
//  Downloads file to a temporary location, opens with system app,
//  polls for changes (modification date), and auto-uploads back to remote on save.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Tracks an externally-opened file: local temp path, remote path, and file watcher.
struct ExternalEditSession: Identifiable {
    let id = UUID()
    let remoteFile: RemoteFile
    let localURL: URL
    let remotePath: String
    var lastModified: Date
    var lastFileSize: Int64
    var isActive: Bool = true
    var isUploading: Bool = false
}

@MainActor
final class ExternalEditorService {
    // MARK: - Shared Instance
    static let shared = ExternalEditorService()

    // MARK: - State
    private(set) var activeSessions: [UUID: ExternalEditSession] = [:]
    private var pollTimers: [UUID: DispatchSourceTimer] = [:]
    private var uploadHandlers: [UUID: (URL, String) async -> Void] = [:]

    /// Callback for logging
    var onLog: ((String, SFTPLogLevel) -> Void)?

    private init() {}

    // MARK: - Temp Directory

    /// Gets a stable temp directory for remote file editing
    private func tempDirectory(for connectionId: UUID) -> URL {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSSH_ExternalEdit")
            .appendingPathComponent(connectionId.uuidString)
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        return tempBase
    }

    // MARK: - Open With External App

    /// Downloads a remote file to temp and opens it with the default system app.
    /// Polls the file for changes and auto-uploads when saved.
    func openFileExternally(
        file: RemoteFile,
        connectionId: UUID,
        downloadHandler: @escaping (RemoteFile, URL) async throws -> Void,
        uploadHandler: @escaping (URL, String) async -> Void
    ) async {
        // Build a temp file path preserving the filename
        let tempDir = tempDirectory(for: connectionId)
        // Use a subdirectory based on the remote path to avoid collisions
        let pathHash = String(file.path.hashValue, radix: 16, uppercase: false)
        let sessionDir = tempDir.appendingPathComponent(pathHash)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let localURL = sessionDir.appendingPathComponent(file.name)

        // Check if already open — just re-activate the window
        if let existingSession = activeSessions.values.first(where: { $0.remotePath == file.path && $0.isActive }) {
            NSWorkspace.shared.open(existingSession.localURL)
            onLog?("Re-opened \(file.name) in external editor", .info)
            return
        }

        // Download file to temp location
        do {
            // Remove stale local file if exists
            try? FileManager.default.removeItem(at: localURL)
            try await downloadHandler(file, localURL)
        } catch {
            onLog?("Failed to download \(file.name) for external editing: \(error.localizedDescription)", .error)
            return
        }

        // Get the initial modification date and size
        guard let (modDate, fileSize) = getFileAttributes(at: localURL) else {
            onLog?("Failed to read file attributes for \(file.name)", .error)
            return
        }

        // Create session
        let session = ExternalEditSession(
            remoteFile: file,
            localURL: localURL,
            remotePath: file.path,
            lastModified: modDate,
            lastFileSize: fileSize
        )
        activeSessions[session.id] = session
        uploadHandlers[session.id] = uploadHandler

        // Start polling for changes
        startPolling(sessionId: session.id)

        // Open with default system application
        NSWorkspace.shared.open(localURL)
        onLog?("Opened \(file.name) with external editor — changes will auto-upload", .info)
    }

    /// Opens file with a specific application chosen by the user
    func openFileWithApp(
        file: RemoteFile,
        connectionId: UUID,
        applicationURL: URL,
        downloadHandler: @escaping (RemoteFile, URL) async throws -> Void,
        uploadHandler: @escaping (URL, String) async -> Void
    ) async {
        // Build temp file path
        let tempDir = tempDirectory(for: connectionId)
        let pathHash = String(file.path.hashValue, radix: 16, uppercase: false)
        let sessionDir = tempDir.appendingPathComponent(pathHash)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let localURL = sessionDir.appendingPathComponent(file.name)

        // Check if already open
        if let existingSession = activeSessions.values.first(where: { $0.remotePath == file.path && $0.isActive }) {
            try? await NSWorkspace.shared.open([existingSession.localURL], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
            onLog?("Re-opened \(file.name) with selected app", .info)
            return
        }

        // Download
        do {
            try? FileManager.default.removeItem(at: localURL)
            try await downloadHandler(file, localURL)
        } catch {
            onLog?("Failed to download \(file.name) for external editing: \(error.localizedDescription)", .error)
            return
        }

        guard let (modDate, fileSize) = getFileAttributes(at: localURL) else {
            onLog?("Failed to read file attributes for \(file.name)", .error)
            return
        }

        let session = ExternalEditSession(
            remoteFile: file,
            localURL: localURL,
            remotePath: file.path,
            lastModified: modDate,
            lastFileSize: fileSize
        )
        activeSessions[session.id] = session
        uploadHandlers[session.id] = uploadHandler

        startPolling(sessionId: session.id)

        // Open with specific application
        let config = NSWorkspace.OpenConfiguration()
        try? await NSWorkspace.shared.open([localURL], withApplicationAt: applicationURL, configuration: config)
        onLog?("Opened \(file.name) with \(applicationURL.deletingPathExtension().lastPathComponent) — changes will auto-upload", .info)
    }

    // MARK: - File Change Polling
    // Uses a timer to poll file modification date every 2 seconds.
    // This is more reliable than DispatchSource because macOS editors use
    // "atomic save" (write to temp file → rename), which invalidates file descriptors.

    private func startPolling(sessionId: UUID) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(500))

        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.checkForChanges(sessionId: sessionId)
            }
        }

        timer.resume()
        pollTimers[sessionId] = timer
    }

    private func checkForChanges(sessionId: UUID) async {
        guard var session = activeSessions[sessionId],
              session.isActive,
              !session.isUploading else { return }

        // Check if file still exists
        guard FileManager.default.fileExists(atPath: session.localURL.path) else { return }

        // Get current attributes
        guard let (currentModDate, currentSize) = getFileAttributes(at: session.localURL) else { return }

        // Check if file was modified (compare both date AND size for reliability)
        let dateChanged = currentModDate > session.lastModified
        let sizeChanged = currentSize != session.lastFileSize

        guard dateChanged || sizeChanged else { return }

        // Update session state
        session.lastModified = currentModDate
        session.lastFileSize = currentSize
        session.isUploading = true
        activeSessions[sessionId] = session

        let fileName = session.localURL.lastPathComponent
        let remotePath = session.remotePath

        onLog?("Detected changes in \(fileName) — uploading to \(remotePath)...", .info)

        // Perform upload
        if let uploadHandler = uploadHandlers[sessionId] {
            await uploadHandler(session.localURL, remotePath)
        }

        // Mark upload complete
        if var updatedSession = activeSessions[sessionId] {
            updatedSession.isUploading = false
            activeSessions[sessionId] = updatedSession
        }

        onLog?("Auto-uploaded \(fileName) to remote ✓", .success)
    }

    // MARK: - Helpers

    private func getFileAttributes(at url: URL) -> (modificationDate: Date, fileSize: Int64)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        let size = (attrs[.size] as? Int64) ?? 0
        return (modDate, size)
    }

    // MARK: - Session Management

    /// Stops monitoring a specific session
    func closeSession(_ sessionId: UUID) {
        if let timer = pollTimers.removeValue(forKey: sessionId) {
            timer.cancel()
        }
        uploadHandlers.removeValue(forKey: sessionId)

        if var session = activeSessions[sessionId] {
            session.isActive = false
            activeSessions[sessionId] = session
        }

        // Clean up temp file
        if let session = activeSessions[sessionId] {
            try? FileManager.default.removeItem(at: session.localURL)
        }

        activeSessions.removeValue(forKey: sessionId)
    }

    /// Stops all active sessions (called when file browser window closes)
    func closeAllSessions() {
        for sessionId in activeSessions.keys {
            closeSession(sessionId)
        }
    }

    /// Returns the number of active editing sessions
    var activeSessionCount: Int {
        activeSessions.values.filter { $0.isActive }.count
    }

    // MARK: - App Suggestions

    /// Returns a list of applications that can open the given file type
    static func suggestedApplications(for fileName: String) -> [(name: String, url: URL)] {
        let fileExtension = (fileName as NSString).pathExtension
        guard !fileExtension.isEmpty else { return [] }

        // Get the UTType for this extension
        guard let uti = UTType(filenameExtension: fileExtension) else { return [] }

        // Get apps that can open this type
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: uti)

        return appURLs.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            return (name: name, url: url)
        }.sorted { $0.name < $1.name }
    }
}
