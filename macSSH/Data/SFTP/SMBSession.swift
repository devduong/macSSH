//
//  SMBSession.swift
//  macSSH
//
//  Actor-based SMB/CIFS session conforming to SFTPSessionProtocol using macOS NetFS & smbfs
//

import Foundation
import NetFS
import Darwin

actor SMBSession: SFTPSessionProtocol {
    private let sessionId = UUID().uuidString
    private var serverHost: String = ""
    private var port: Int = 445
    private var username: String = ""
    private var password: String = ""
    private var initialShare: String? = nil
    private var initialPath: String = "/"

    /// Maps shareName -> local mounted filesystem path
    private var mountedShares: [String: String] = [:]
    /// Tracks local mount paths created by this session so they can be unmounted on disconnect
    private var ownedMountPaths: Set<String> = []
    /// Cached list of share names when connecting to a bare SMB server root
    private var discoveredShares: [String] = []

    private(set) var isConnected: Bool = false
    private(set) var currentPath: String = "/"

    init() {}

    deinit {
        let mounts = Array(ownedMountPaths)
        let sessionDir = "/tmp/macSSH_SMB/\(sessionId)"
        Task.detached {
            for mountPath in mounts {
                Self.unmountPath(mountPath)
            }
            try? FileManager.default.removeItem(atPath: sessionDir)
        }
    }

    // MARK: - Connection

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        socksProxyPort: Int? = nil,
        socksProxyAllowLAN: Bool = false
    ) async throws {
        var raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("smb://") {
            raw = String(raw.dropFirst("smb://".count))
        } else if raw.lowercased().hasPrefix("cifs://") {
            raw = String(raw.dropFirst("cifs://".count))
        }
        while raw.hasPrefix("/") || raw.hasPrefix("\\") {
            raw.removeFirst()
        }
        raw = raw.replacingOccurrences(of: "\\", with: "/")

        let segments = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let firstHost = segments.first, !firstHost.isEmpty else {
            throw AppError.connectionFailed("Invalid SMB server host.")
        }

        self.serverHost = (firstHost.lowercased() == "localhost") ? "127.0.0.1" : firstHost
        self.port = port > 0 ? port : 445
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password

        if segments.count >= 2 {
            let share = segments[1]
            self.initialShare = share
            let fullVirtualPath = "/" + segments.dropFirst().joined(separator: "/")
            self.initialPath = fullVirtualPath
            self.currentPath = fullVirtualPath

            logInfo("Connecting to SMB share //\(self.serverHost):\(self.port)/\(share)", category: .sftp)
            _ = try await ensureShareMounted(share)
            self.isConnected = true
            logInfo("Connected and mounted SMB share '\(share)' on \(self.serverHost)", category: .sftp)
        } else {
            self.initialShare = nil
            self.initialPath = "/"
            self.currentPath = "/"

            logInfo("Connecting to SMB server //\(self.serverHost):\(self.port) to discover shares", category: .sftp)
            let shares = try await fetchServerShares()
            self.discoveredShares = shares
            self.isConnected = true
            logInfo("Connected to SMB server \(self.serverHost) (found \(shares.count) share(s))", category: .sftp)
        }
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        passphrase: String?,
        socksProxyPort: Int? = nil,
        socksProxyAllowLAN: Bool = false
    ) async throws {
        try await connect(
            host: host,
            port: port,
            username: username,
            password: passphrase ?? "",
            socksProxyPort: socksProxyPort,
            socksProxyAllowLAN: socksProxyAllowLAN
        )
    }

    func disconnect() async {
        logInfo("Disconnecting from SMB server \(serverHost)", category: .sftp)
        let mounts = Array(ownedMountPaths)
        ownedMountPaths.removeAll()
        mountedShares.removeAll()
        discoveredShares.removeAll()
        isConnected = false
        currentPath = "/"

        let sessionDir = "/tmp/macSSH_SMB/\(sessionId)"
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                for mountPath in mounts {
                    Self.unmountPath(mountPath)
                }
                try? FileManager.default.removeItem(atPath: sessionDir)
                continuation.resume()
            }
        }
    }

    // MARK: - File Operations

    func listFiles(at path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)

        // If at root "/" without a share segment, list available SMB shares as directories
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.isEmpty {
            if discoveredShares.isEmpty {
                if let initShare = initialShare {
                    discoveredShares = [initShare]
                } else {
                    discoveredShares = (try? await fetchServerShares()) ?? []
                }
            }
            currentPath = "/"
            let shareFiles = discoveredShares.map { share in
                RemoteFile(
                    name: share,
                    path: "/\(share)",
                    isDirectory: true,
                    size: 0,
                    permissions: "drwxr-xr-x",
                    modificationDate: nil
                )
            }
            return RemoteFile.sortedFiles(shareFiles, by: .name)
        }

        let localURL = try await resolveLocalFileURL(for: normalized)
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isReadableKey,
            .isWritableKey
        ]

        let contents = try fm.contentsOfDirectory(
            at: localURL,
            includingPropertiesForKeys: resourceKeys,
            options: []
        )

        var files: [RemoteFile] = []
        for itemURL in contents {
            let name = itemURL.lastPathComponent
            guard name != "." && name != ".." else { continue }

            let vals = try? itemURL.resourceValues(forKeys: Set(resourceKeys))
            let isDir = vals?.isDirectory ?? false
            let isSymlink = vals?.isSymbolicLink ?? false
            let size = Int64(vals?.fileSize ?? 0)
            let modDate = vals?.contentModificationDate
            let readable = vals?.isReadable ?? true
            let writable = vals?.isWritable ?? true

            let prefix = isSymlink ? "l" : (isDir ? "d" : "-")
            let r = readable ? "r" : "-"
            let w = writable ? "w" : "-"
            let x = isDir ? "x" : "-"
            let perms = "\(prefix)\(r)\(w)\(x)\(r)-\(x)\(r)-\(x)"

            let fullVirtualPath = normalized.hasSuffix("/") ? "\(normalized)\(name)" : "\(normalized)/\(name)"
            files.append(
                RemoteFile(
                    name: name,
                    path: fullVirtualPath,
                    isDirectory: isDir,
                    size: size,
                    permissions: perms,
                    modificationDate: modDate
                )
            )
        }

        currentPath = normalized
        return RemoteFile.sortedFiles(files, by: .name)
    }

    func getFileInfo(at path: String) async throws -> RemoteFile {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)
        let localURL = try await resolveLocalFileURL(for: normalized)

        var isDirObj: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirObj) else {
            throw AppError.fileNotFound
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let size = (attrs[.size] as? Int64) ?? 0
        let modDate = attrs[.modificationDate] as? Date
        let isDir = isDirObj.boolValue
        let perms = isDir ? "drwxr-xr-x" : "-rw-r--r--"

        return RemoteFile(
            name: localURL.lastPathComponent,
            path: normalized,
            isDirectory: isDir,
            size: size,
            permissions: perms,
            modificationDate: modDate
        )
    }

    func createDirectory(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        logInfo("Created SMB directory: \(path)", category: .sftp)
    }

    func createFile(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        guard FileManager.default.createFile(atPath: localURL.path, contents: Data()) else {
            throw AppError.sftpOperationFailed("Could not create file at \(path)")
        }
        logInfo("Created SMB file: \(path)", category: .sftp)
    }

    func deleteFile(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        try FileManager.default.removeItem(at: localURL)
        logInfo("Deleted SMB file: \(path)", category: .sftp)
    }

    func deleteDirectory(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        try FileManager.default.removeItem(at: localURL)
        logInfo("Deleted SMB directory: \(path)", category: .sftp)
    }

    func rename(from sourcePath: String, to destinationPath: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let srcURL = try await resolveLocalFileURL(for: sourcePath)
        let dstURL = try await resolveLocalFileURL(for: destinationPath)
        if FileManager.default.fileExists(atPath: dstURL.path) {
            try? FileManager.default.removeItem(at: dstURL)
        }
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
        logInfo("Renamed SMB item: \(sourcePath) -> \(destinationPath)", category: .sftp)
    }

    func copyFile(from sourcePath: String, to destinationPath: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let srcURL = try await resolveLocalFileURL(for: sourcePath)
        let dstURL = try await resolveLocalFileURL(for: destinationPath)
        if FileManager.default.fileExists(atPath: dstURL.path) {
            try? FileManager.default.removeItem(at: dstURL)
        }
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
    }

    func copyDirectory(from sourcePath: String, to destinationPath: String) async throws {
        try await copyFile(from: sourcePath, to: destinationPath)
    }

    func move(from sourcePath: String, to destinationPath: String) async throws {
        try await rename(from: sourcePath, to: destinationPath)
    }

    func downloadFile(from remotePath: String, to localURL: URL) async throws {
        try await downloadFile(from: remotePath, to: localURL, progress: nil)
    }

    func downloadFile(from remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws {
        guard isConnected else { throw AppError.notConnected }
        let remoteFileURL = try await resolveLocalFileURL(for: remotePath)
        try await Self.streamCopyFile(from: remoteFileURL, to: localURL, progress: progress)
        logInfo("Downloaded SMB file: \(remotePath) -> \(localURL.path)", category: .sftp)
    }

    func uploadFile(from localURL: URL, to remotePath: String) async throws {
        try await uploadFile(from: localURL, to: remotePath, progress: nil)
    }

    func uploadFile(from localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws {
        guard isConnected else { throw AppError.notConnected }
        let remoteFileURL = try await resolveLocalFileURL(for: remotePath)
        try await Self.streamCopyFile(from: localURL, to: remoteFileURL, progress: progress)
        logInfo("Uploaded SMB file: \(localURL.path) -> \(remotePath)", category: .sftp)
    }

    func readFileContent(at path: String) async throws -> String {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        let data = try Data(contentsOf: localURL)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw AppError.sftpOperationFailed("File is binary or uses an unsupported text encoding.")
    }

    func writeFileContent(_ content: String, to path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let localURL = try await resolveLocalFileURL(for: path)
        guard let data = content.data(using: .utf8) else {
            throw AppError.sftpOperationFailed("Failed to encode content as UTF-8.")
        }
        try data.write(to: localURL, options: .atomic)
        logInfo("Wrote SMB file content: \(path)", category: .sftp)
    }

    func getRealPath(at path: String) async throws -> String {
        resolveNormalizedPath(path)
    }

    func executeCommand(_ command: String) async throws -> String {
        throw AppError.sftpOperationFailed("Shell execution is only available on SSH servers.")
    }

    // MARK: - Private Mounting & Resolution Helpers

    private func resolveNormalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." {
            return currentPath
        }
        if trimmed == "~" {
            return initialPath
        }
        if trimmed == ".." {
            return currentPath.parentPath
        }
        let rawPath = trimmed.hasPrefix("/") ? trimmed : currentPath.appendingPathComponent(trimmed)
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [String] = []
        for comp in components {
            if comp == "." { continue }
            if comp == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.append(String(comp))
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }

    private func resolveLocalFileURL(for virtualPath: String) async throws -> URL {
        let normalized = resolveNormalizedPath(virtualPath)
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let shareName = segments.first else {
            throw AppError.sftpOperationFailed("Please select or enter an SMB share folder first.")
        }

        let mountRoot = try await ensureShareMounted(shareName)
        var url = URL(fileURLWithPath: mountRoot)
        for sub in segments.dropFirst() {
            url.appendPathComponent(sub)
        }
        return url
    }

    private func ensureShareMounted(_ shareName: String) async throws -> String {
        if let existing = mountedShares[shareName],
           FileManager.default.fileExists(atPath: existing) {
            return existing
        }

        let mountBaseDir = "/tmp/macSSH_SMB/\(sessionId)/\(shareName)"
        try FileManager.default.createDirectory(atPath: mountBaseDir, withIntermediateDirectories: true)

        let host = self.serverHost
        let port = self.port
        let user = self.username
        let pass = self.password

        let mountedPath = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let encodedShare = shareName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareName
                let portPart = (port == 445) ? "" : ":\(port)"
                guard let smbURL = URL(string: "smb://\(host)\(portPart)/\(encodedShare)") else {
                    continuation.resume(throwing: AppError.connectionFailed("Invalid SMB URL for share '\(shareName)'."))
                    return
                }

                let mountDirURL = URL(fileURLWithPath: mountBaseDir)
                let openOptions: NSMutableDictionary = [
                    kNAUIOptionKey: kNAUIOptionNoUI
                ]
                let mountOptions: NSMutableDictionary = [
                    kNetFSMountAtMountDirKey: true,
                    kNetFSSoftMountKey: true
                ]

                let cfUser: CFString? = user.isEmpty ? ("GUEST" as CFString) : (user as CFString)
                let cfPass: CFString? = pass.isEmpty ? ("" as CFString) : (pass as CFString)

                var mountpoints: Unmanaged<CFArray>? = nil
                let status = NetFSMountURLSync(
                    smbURL as CFURL,
                    mountDirURL as CFURL,
                    cfUser,
                    cfPass,
                    openOptions,
                    mountOptions,
                    &mountpoints
                )

                if status == 0 {
                    if let array = mountpoints?.takeRetainedValue() as? [String], let first = array.first {
                        continuation.resume(returning: first)
                    } else {
                        continuation.resume(returning: mountBaseDir)
                    }
                    return
                }

                // Check error code from NetFSMountURLSync
                if status == EAUTH || status == EACCES || status == -5014 || status == -5015 {
                    continuation.resume(throwing: AppError.authenticationFailed)
                } else if status == ETIMEDOUT {
                    continuation.resume(throwing: AppError.connectionTimeout)
                } else if status == ECONNREFUSED || status == EHOSTDOWN || status == EHOSTUNREACH {
                    continuation.resume(throwing: AppError.connectionFailed("Could not connect to SMB server \(host):\(port)."))
                } else {
                    let errMsg = String(cString: strerror(status))
                    continuation.resume(throwing: AppError.connectionFailed("SMB mount failed for '\(shareName)' (\(errMsg), code \(status)). Tip: Specify Host as 'ip/ShareName'."))
                }
            }
        }

        mountedShares[shareName] = mountedPath
        ownedMountPaths.insert(mountedPath)
        return mountedPath
    }

    private func fetchServerShares() async throws -> [String] {
        let host = self.serverHost
        let port = self.port
        let user = self.username
        let pass = self.password

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")

                let portPart = (port == 445) ? "" : ":\(port)"
                let authPart: String
                if user.isEmpty {
                    authPart = "guest@"
                } else {
                    let encUser = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
                    let encPass = pass.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? pass
                    authPart = pass.isEmpty ? "\(encUser)@" : "\(encUser):\(encPass)@"
                }

                var args = ["view"]
                if user.isEmpty {
                    args.append("-g")
                } else {
                    args.append("-N")
                }
                args.append("//\(authPart)\(host)\(portPart)")
                process.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    if process.terminationStatus != 0 {
                        let lower = errStr.lowercased()
                        if lower.contains("authentication") || lower.contains("auth") || lower.contains("permission") || lower.contains("login") {
                            continuation.resume(throwing: AppError.authenticationFailed)
                        } else {
                            continuation.resume(throwing: AppError.connectionFailed(errStr.isEmpty ? "Could not list SMB shares on \(host). Try entering 'host/ShareName' in the Host field." : errStr))
                        }
                        return
                    }

                    var shares: [String] = []
                    for line in outStr.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed.hasPrefix("Share") || trimmed.hasPrefix("---") || trimmed.contains("shares listed") {
                            continue
                        }
                        // Format: ShareName    Disk    Comment
                        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                        if tokens.count >= 2 {
                            let typeToken = String(tokens[1]).lowercased()
                            if typeToken == "disk" {
                                let shareName = String(tokens[0])
                                if !shareName.hasSuffix("$") {
                                    shares.append(shareName)
                                }
                            }
                        }
                    }
                    continuation.resume(returning: shares)
                } catch {
                    continuation.resume(throwing: AppError.connectionFailed(error.localizedDescription))
                }
            }
        }
    }

    nonisolated private static func streamCopyFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: TransferProgressHandler?
    ) async throws {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? UInt64) ?? 0
        let chunkSize = FileOperationConstants.chunkSize

        try? FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)

        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? readHandle.close() }

        let writeHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? writeHandle.close() }

        progress?(0)
        var offset: UInt64 = 0

        while offset < fileSize {
            try Task.checkCancellation()
            try readHandle.seek(toOffset: offset)
            guard let chunk = try readHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            try writeHandle.write(contentsOf: chunk)
            offset += UInt64(chunk.count)
            progress?(Int64(offset))
        }
    }

    nonisolated private static func unmountPath(_ path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/umount")
        proc.arguments = ["-f", path]
        try? proc.run()
        proc.waitUntilExit()
    }
}
