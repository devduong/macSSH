//
//  LocalFileBrowserState.swift
//  macSSH
//
//  Observable state for managing the Local Files pane
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class LocalFileBrowserState {
    // MARK: - Navigation State
    var currentURL: URL {
        didSet {
            pathInputText = currentURL.path
        }
    }
    var pathInputText: String = ""
    var files: [RemoteFile] = []
    var selectedFileIds: Set<UUID> = []
    var isLoading: Bool = false
    var error: AppError?

    // MARK: - Navigation History
    private var history: [URL] = []
    private var historyIndex: Int = -1

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < history.count - 1
    }

    var canGoUp: Bool {
        currentURL.path != "/"
    }

    // MARK: - Sort & View State
    var sortCriteria: RemoteFile.SortCriteria = .name {
        didSet { applySort() }
    }
    var sortAscending: Bool = true {
        didSet { applySort() }
    }
    var showHiddenFiles: Bool = false {
        didSet { Task { await loadFiles() } }
    }

    // MARK: - Sheet / UI State
    var isShowingNewFolderSheet: Bool = false
    var isShowingNewFileSheet: Bool = false
    var fileToRename: RemoteFile?
    var isShowingRenameSheet: Bool = false
    var isShowingDeleteConfirmation: Bool = false
    var filesToDelete: [RemoteFile] = []

    // MARK: - Computed Properties
    var selectedFiles: [RemoteFile] {
        files.filter { selectedFileIds.contains($0.id) }
    }

    var currentPath: String {
        currentURL.path
    }

    var pathComponents: [(name: String, path: String)] {
        let path = currentURL.path
        if path == "/" {
            return [("Root", "/")]
        }

        var components: [(name: String, path: String)] = []
        let rawParts = path.split(separator: "/").map(String.init)
        var accumulated = ""

        for part in rawParts {
            accumulated += "/" + part
            components.append((part, accumulated))
        }

        return components
    }

    // MARK: - Dependencies
    private let fileService: LocalFileManagerService

    init(fileService: LocalFileManagerService = .shared) {
        self.fileService = fileService
        let defaultURL = fileService.defaultDirectory
        self.currentURL = defaultURL
        self.pathInputText = defaultURL.path
        self.history = [defaultURL]
        self.historyIndex = 0
    }

    // MARK: - File Loading & Navigation

    func loadFiles(silent: Bool = false) async {
        if !silent {
            isLoading = true
        }
        defer {
            if !silent {
                isLoading = false
            }
        }

        let targetURL = currentURL
        let showHidden = showHiddenFiles
        let service = fileService

        do {
            let loadedFiles = try await Task.detached(priority: .userInitiated) {
                try service.listFiles(at: targetURL, showHidden: showHidden)
            }.value

            self.files = loadedFiles
            applySort()
        } catch {
            self.error = AppError.from(error)
        }
    }

    func navigate(to url: URL) async {
        guard url != currentURL else { return }

        // Truncate forward history if navigating to a new path
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }

        history.append(url)
        historyIndex = history.count - 1
        currentURL = url
        selectedFileIds.removeAll()

        await loadFiles()
    }

    func navigateToPath(_ pathString: String) async {
        let trimmed = pathString.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedPath = trimmed
        if resolvedPath.hasPrefix("~") {
            resolvedPath = resolvedPath.replacingOccurrences(
                of: "~",
                with: FileManager.default.homeDirectoryForCurrentUser.path
            )
        }

        let targetURL = URL(fileURLWithPath: resolvedPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
            await navigate(to: targetURL)
        } else {
            error = AppError.fileNotFound
        }
    }

    func goBack() async {
        guard canGoBack else { return }
        historyIndex -= 1
        currentURL = history[historyIndex]
        selectedFileIds.removeAll()
        await loadFiles()
    }

    func goForward() async {
        guard canGoForward else { return }
        historyIndex += 1
        currentURL = history[historyIndex]
        selectedFileIds.removeAll()
        await loadFiles()
    }

    func goUp() async {
        guard canGoUp else { return }
        let parentURL = currentURL.deletingLastPathComponent()
        await navigate(to: parentURL)
    }

    func goHome() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        await navigate(to: home)
    }

    func refresh(silent: Bool = false) async {
        await loadFiles(silent: silent)
    }

    // MARK: - Sorting

    private func applySort() {
        files = RemoteFile.sortedFiles(files, by: sortCriteria, ascending: sortAscending)
    }

    // MARK: - Operations

    func createFolder(name: String) async {
        do {
            try await fileService.createFolder(at: currentURL, name: name)
            isShowingNewFolderSheet = false
            await loadFiles(silent: true)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func createFile(name: String) async {
        do {
            try await fileService.createFile(at: currentURL, name: name)
            isShowingNewFileSheet = false
            await loadFiles(silent: true)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func renameFile(_ file: RemoteFile, to newName: String) async {
        do {
            let sourceURL = URL(fileURLWithPath: file.path)
            try await fileService.renameItem(at: sourceURL, to: newName)
            isShowingRenameSheet = false
            fileToRename = nil
            await loadFiles(silent: true)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func deleteFiles(_ filesToDeleteList: [RemoteFile]) async {
        let deletedIds = Set(filesToDeleteList.map(\.id))
        // Optimistic removal
        self.files.removeAll { deletedIds.contains($0.id) }
        self.selectedFileIds.subtract(deletedIds)
        self.isShowingDeleteConfirmation = false
        self.filesToDelete.removeAll()

        do {
            let urls = filesToDeleteList.map { URL(fileURLWithPath: $0.path) }
            try await fileService.deleteItems(at: urls)
            await loadFiles(silent: true)
        } catch {
            self.error = AppError.from(error)
            await loadFiles(silent: true)
        }
    }
}
