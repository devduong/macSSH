//
//  LocalFileManagerService.swift
//  macSSH
//
//  Service for managing local filesystem operations
//

import Foundation

final class LocalFileManagerService: Sendable {
    static let shared = LocalFileManagerService()

    private let fileManager = FileManager.default

    var homeDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    var defaultDirectory: URL {
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        return downloads ?? documents ?? homeDirectory
    }

    /// List files in a local directory converted to RemoteFile domain models
    func listFiles(at directoryURL: URL, showHidden: Bool = false) throws -> [RemoteFile] {
        let path = directoryURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw AppError.fileNotFound
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey
            ],
            options: showHidden ? [] : [.skipsHiddenFiles]
        )

        var result: [RemoteFile] = []

        for itemURL in contents {
            let itemName = itemURL.lastPathComponent
            if !showHidden && itemName.hasPrefix(".") {
                continue
            }

            let resourceValues = try? itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isSymbolicLinkKey
            ])

            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate
            let fileAttributes = try? fileManager.attributesOfItem(atPath: itemURL.path)
            let permissionsInt = (fileAttributes?[.posixPermissions] as? Int) ?? (isDir ? 0o755 : 0o644)
            let permissionsStr = formatPermissions(permissionsInt, isDirectory: isDir)

            let file = RemoteFile(
                name: itemName,
                path: itemURL.path,
                isDirectory: isDir,
                size: isDir ? 0 : size,
                permissions: permissionsStr,
                modificationDate: modDate
            )
            result.append(file)
        }

        return result
    }

    /// Create a new folder at the specified URL
    func createFolder(at parentURL: URL, name: String) throws {
        let newFolderURL = parentURL.appendingPathComponent(name)
        try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
    }

    /// Create a new empty file
    func createFile(at parentURL: URL, name: String) throws {
        let newFileURL = parentURL.appendingPathComponent(name)
        fileManager.createFile(atPath: newFileURL.path, contents: Data())
    }

    /// Rename a local file or folder
    func renameItem(at sourceURL: URL, to newName: String) throws {
        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    /// Delete local files or move to trash
    func deleteItems(at urls: [URL]) throws {
        for url in urls {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    private func formatPermissions(_ mode: Int, isDirectory: Bool) -> String {
        let typeChar = isDirectory ? "d" : "-"
        let user = String(
            [
                (mode & 0o400 != 0) ? "r" : "-",
                (mode & 0o200 != 0) ? "w" : "-",
                (mode & 0o100 != 0) ? "x" : "-"
            ]
        )
        let group = String(
            [
                (mode & 0o040 != 0) ? "r" : "-",
                (mode & 0o020 != 0) ? "w" : "-",
                (mode & 0o010 != 0) ? "x" : "-"
            ]
        )
        let other = String(
            [
                (mode & 0o004 != 0) ? "r" : "-",
                (mode & 0o002 != 0) ? "w" : "-",
                (mode & 0o001 != 0) ? "x" : "-"
            ]
        )
        return "\(typeChar)\(user)\(group)\(other)"
    }
}
