//
//  FTPSession.swift
//  macSSH
//
//  Actor-based FTP/FTPS session conforming to SFTPSessionProtocol
//

import Foundation

nonisolated private final class CurlProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func setProcess(_ proc: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { return false }
        process = proc
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let proc = process
        lock.unlock()
        if let proc, proc.isRunning {
            proc.terminate()
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

nonisolated private final class PipeDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()

    func setStdout(_ data: Data) {
        lock.lock()
        outData = data
        lock.unlock()
    }

    func appendStderr(_ chunk: Data) {
        lock.lock()
        errData.append(chunk)
        lock.unlock()
    }

    func snapshot() -> (out: Data, err: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (outData, errData)
    }
}

actor FTPSession: SFTPSessionProtocol {
    private var host: String = ""
    private var port: Int = 21
    private var username: String = "anonymous"
    private var password: String = ""
    private var useFTPS: Bool = false
    private var initialPath: String = "/"
    private var preferredMaxStreams: Int = FTPTransferConstants.defaultMaxStreams

    private(set) var isConnected: Bool = false
    private(set) var currentPath: String = "/"

    init() {}

    func setPreferredMaxStreams(_ count: Int) async {
        preferredMaxStreams = FTPTransferSettings.clamped(count)
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
        var rawHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var detectedFTPS = (port == 990)

        if rawHost.lowercased().hasPrefix("ftps://") {
            detectedFTPS = true
            rawHost = String(rawHost.dropFirst("ftps://".count))
        } else if rawHost.lowercased().hasPrefix("ftp://") {
            rawHost = String(rawHost.dropFirst("ftp://".count))
        }

        // Extract optional subpath from host (e.g. "ftp.example.com/pub/files")
        let parts = rawHost.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let cleanHost = parts.first.map(String.init) ?? rawHost
        let startPath: String
        if parts.count > 1 {
            startPath = "/" + String(parts[1])
        } else {
            startPath = "/"
        }

        self.host = (cleanHost.lowercased() == "localhost") ? "127.0.0.1" : cleanHost
        self.port = port > 0 ? port : (detectedFTPS ? 990 : 21)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : username
        self.password = password.isEmpty && self.username == "anonymous" ? "anonymous@macssh.local" : password
        self.useFTPS = detectedFTPS
        self.initialPath = startPath
        self.currentPath = startPath

        logInfo("Connecting to FTP server \(self.username)@\(self.host):\(self.port)\(startPath)", category: .sftp)

        do {
            // Verify connection and credentials by listing the initial directory
            _ = try await fetchDirectoryListing(at: startPath)
            self.isConnected = true
            logInfo("Connected successfully to FTP server \(self.host)", category: .sftp)
        } catch {
            self.isConnected = false
            throw error
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
        // FTP uses password/anonymous auth; fall back to passphrase if provided
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
        logInfo("Disconnecting from FTP server \(host)", category: .sftp)
        isConnected = false
        currentPath = "/"
    }

    // MARK: - File Operations

    func listFiles(at path: String) async throws -> [RemoteFile] {
        guard isConnected else { throw AppError.notConnected }

        let targetPath = resolveNormalizedPath(path)
        logInfo("Listing FTP files at '\(targetPath)'", category: .sftp)

        let files = try await fetchDirectoryListing(at: targetPath)
        currentPath = targetPath
        return RemoteFile.sortedFiles(files, by: .name)
    }

    func getFileInfo(at path: String) async throws -> RemoteFile {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)
        let parent = normalized.parentPath
        let name = (normalized as NSString).lastPathComponent
        let items = try await fetchDirectoryListing(at: parent)
        if let found = items.first(where: { $0.name == name }) {
            return found
        }
        throw AppError.fileNotFound
    }

    func createDirectory(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)
        let ftpPath = normalized.hasPrefix("/") ? normalized : "/" + normalized
        _ = try await runCurlQuoteCommands(["MKD \(ftpPath)"])
        logInfo("Created FTP directory: \(normalized)", category: .sftp)
    }

    func createFile(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_ftp_empty_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await uploadFile(from: tempURL, to: path, progress: nil)
        logInfo("Created FTP file: \(path)", category: .sftp)
    }

    func deleteFile(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)
        let ftpPath = normalized.hasPrefix("/") ? normalized : "/" + normalized
        _ = try await runCurlQuoteCommands(["DELE \(ftpPath)"])
        logInfo("Deleted FTP file: \(normalized)", category: .sftp)
    }

    func deleteDirectory(at path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(path)

        // Recursively delete contents first
        if let children = try? await fetchDirectoryListing(at: normalized) {
            for child in children {
                if child.isDirectory {
                    try await deleteDirectory(at: child.path)
                } else {
                    try await deleteFile(at: child.path)
                }
            }
        }

        let ftpPath = normalized.hasPrefix("/") ? normalized : "/" + normalized
        _ = try await runCurlQuoteCommands(["RMD \(ftpPath)"])
        logInfo("Deleted FTP directory: \(normalized)", category: .sftp)
    }

    func rename(from sourcePath: String, to destinationPath: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let src = resolveNormalizedPath(sourcePath)
        let dst = resolveNormalizedPath(destinationPath)
        _ = try await runCurlQuoteCommands([
            "RNFR \(src)",
            "RNTO \(dst)"
        ])
        logInfo("Renamed FTP item '\(src)' to '\(dst)'", category: .sftp)
    }

    func copyFile(from sourcePath: String, to destinationPath: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_ftp_copy_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await downloadFile(from: sourcePath, to: tempURL, progress: nil)
        try await uploadFile(from: tempURL, to: destinationPath, progress: nil)
    }

    func copyDirectory(from sourcePath: String, to destinationPath: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        try await createDirectory(at: destinationPath)
        let children = try await fetchDirectoryListing(at: sourcePath)
        for child in children {
            let destChild = destinationPath.appendingPathComponent(child.name)
            if child.isDirectory {
                try await copyDirectory(from: child.path, to: destChild)
            } else {
                try await copyFile(from: child.path, to: destChild)
            }
        }
    }

    func move(from sourcePath: String, to destinationPath: String) async throws {
        try await rename(from: sourcePath, to: destinationPath)
    }

    func downloadFile(from remotePath: String, to localURL: URL) async throws {
        try await downloadFile(from: remotePath, to: localURL, streamCount: nil, progress: nil)
    }

    func downloadFile(from remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws {
        try await downloadFile(from: remotePath, to: localURL, streamCount: nil, progress: progress)
    }

    func downloadFile(
        from remotePath: String,
        to localURL: URL,
        streamCount: Int?,
        progress: TransferProgressHandler?
    ) async throws {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(remotePath)
        let urlString = buildFTPURL(for: normalized, isDirectory: false)
        let effectiveStreams = FTPTransferSettings.clamped(streamCount ?? preferredMaxStreams)

        try? FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: localURL)

        progress?(0)

        // Use multi-part parallel range streams for large files when server supports REST
        if effectiveStreams > 1,
           let metadata = try? await probeRemoteFileMetadata(at: normalized),
           metadata.supportsRanges,
           metadata.size >= FTPTransferConstants.multiPartThresholdBytes {
            let chunkCount = min(effectiveStreams, Int(metadata.size / FTPTransferConstants.minChunkBytes))
            if chunkCount > 1 {
                do {
                    try await downloadFileMultiPart(
                        urlString: urlString,
                        remotePath: normalized,
                        remoteSize: metadata.size,
                        chunkCount: chunkCount,
                        to: localURL,
                        progress: progress
                    )
                    return
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        throw CancellationError()
                    }
                    logWarning("Multi-part FTP download failed for '\(normalized)' (\(error.localizedDescription)); falling back to single stream.", category: .sftp)
                    try? FileManager.default.removeItem(at: localURL)
                }
            }
        }

        // Single-stream fallback / standard download
        let monitorTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                   let size = attrs[.size] as? Int64 {
                    progress?(size)
                }
            }
        }
        defer { monitorTask.cancel() }

        _ = try await executeCurl(args: [
            "--silent", "--show-error", "--fail",
            "--connect-timeout", "15",
            "-o", localURL.path,
            urlString
        ])

        if let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let finalSize = attrs[.size] as? Int64 {
            progress?(finalSize)
        }
        logInfo("Downloaded FTP file: \(normalized) -> \(localURL.path)", category: .sftp)
    }

    func uploadFile(from localURL: URL, to remotePath: String) async throws {
        try await uploadFile(from: localURL, to: remotePath, progress: nil)
    }

    func uploadFile(from localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws {
        guard isConnected else { throw AppError.notConnected }
        let normalized = resolveNormalizedPath(remotePath)
        let urlString = buildFTPURL(for: normalized, isDirectory: false)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        progress?(0)

        let progressCallback: (@Sendable (Double) -> Void)?
        if let progress {
            progressCallback = { @Sendable percent in
                let transferred = Int64((Double(fileSize) * percent / 100.0).rounded())
                progress(min(fileSize, max(0, transferred)))
            }
        } else {
            progressCallback = nil
        }

        _ = try await executeCurl(
            args: [
                "--connect-timeout", "15",
                "--ftp-create-dirs",
                "-T", localURL.path,
                urlString
            ],
            onProgressPercent: progressCallback
        )

        progress?(fileSize)
        logInfo("Uploaded FTP file: \(localURL.path) -> \(normalized)", category: .sftp)
    }

    func readFileContent(at path: String) async throws -> String {
        guard isConnected else { throw AppError.notConnected }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_ftp_read_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await downloadFile(from: path, to: tempURL, progress: nil)
        let data = try Data(contentsOf: tempURL)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw AppError.sftpOperationFailed("File is binary or uses an unsupported text encoding.")
    }

    func writeFileContent(_ content: String, to path: String) async throws {
        guard isConnected else { throw AppError.notConnected }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_ftp_write_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let data = content.data(using: .utf8) else {
            throw AppError.sftpOperationFailed("Failed to encode text as UTF-8.")
        }
        try data.write(to: tempURL, options: .atomic)
        try await uploadFile(from: tempURL, to: path, progress: nil)
    }

    func getRealPath(at path: String) async throws -> String {
        resolveNormalizedPath(path)
    }

    func executeCommand(_ command: String) async throws -> String {
        throw AppError.sftpOperationFailed("Shell execution is only available on SFTP (SSH) servers.")
    }

    // MARK: - Private Helpers

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

    private func buildFTPURL(for path: String, isDirectory: Bool) -> String {
        let scheme = useFTPS ? "ftps" : "ftp"
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let encodedSegments = cleanPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { segment -> String in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")

        if encodedSegments.isEmpty {
            return "\(scheme)://\(host):\(port)/"
        }
        let suffix = isDirectory ? "/" : ""
        return "\(scheme)://\(host):\(port)/\(encodedSegments)\(suffix)"
    }

    private func fetchDirectoryListing(at path: String) async throws -> [RemoteFile] {
        let urlString = buildFTPURL(for: path, isDirectory: true)
        let output = try await executeCurl(args: [
            "--silent", "--show-error", "--fail",
            "--connect-timeout", "15",
            urlString
        ])
        return Self.parseFTPListOutput(output, directoryPath: path)
    }

    private func runCurlQuoteCommands(_ commands: [String]) async throws -> String {
        let rootURL = buildFTPURL(for: "/", isDirectory: true)
        var args = [
            "--silent", "--show-error", "--fail",
            "--connect-timeout", "15"
        ]
        for cmd in commands {
            args.append("-Q")
            args.append(cmd)
        }
        args.append(rootURL)
        return try await executeCurl(args: args)
    }

    private struct RemoteFileMetadata: Sendable {
        let size: Int64
        let supportsRanges: Bool
    }

    private func probeRemoteFileMetadata(at path: String) async throws -> RemoteFileMetadata {
        let urlString = buildFTPURL(for: path, isDirectory: false)
        let output = try await executeCurl(args: [
            "--silent", "--show-error", "--fail",
            "--connect-timeout", "10",
            "--head",
            urlString
        ])

        var size: Int64 = 0
        var supportsRanges = false
        for line in output.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valueStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                size = Int64(valueStr) ?? 0
            } else if lower.hasPrefix("accept-ranges:") {
                let valueStr = lower.dropFirst("accept-ranges:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if valueStr.contains("bytes") {
                    supportsRanges = true
                }
            }
        }
        return RemoteFileMetadata(size: size, supportsRanges: supportsRanges)
    }

    private func downloadFileMultiPart(
        urlString: String,
        remotePath: String,
        remoteSize: Int64,
        chunkCount: Int,
        to localURL: URL,
        progress: TransferProgressHandler?
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macSSH_FTP_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let chunkSize = remoteSize / Int64(chunkCount)
        var parts: [(index: Int, start: Int64, end: Int64, url: URL)] = []
        parts.reserveCapacity(chunkCount)

        for i in 0..<chunkCount {
            let start = Int64(i) * chunkSize
            let end = (i == chunkCount - 1) ? (remoteSize - 1) : (start + chunkSize - 1)
            let partURL = tempDir.appendingPathComponent("part_\(i)")
            parts.append((i, start, end, partURL))
        }

        let partURLs = parts.map(\.url)
        let monitorTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                var total: Int64 = 0
                for url in partURLs {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? Int64 {
                        total += size
                    }
                }
                progress?(min(remoteSize, total))
            }
        }
        defer { monitorTask.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for part in parts {
                group.addTask {
                    try Task.checkCancellation()
                    _ = try await self.executeCurl(args: [
                        "--silent", "--show-error", "--fail",
                        "--connect-timeout", "15",
                        "--range", "\(part.start)-\(part.end)",
                        "-o", part.url.path,
                        urlString
                    ])

                    let attrs = try FileManager.default.attributesOfItem(atPath: part.url.path)
                    let actualSize = (attrs[.size] as? Int64) ?? -1
                    let expectedSize = part.end - part.start + 1
                    guard actualSize == expectedSize else {
                        throw AppError.sftpOperationFailed("FTP range chunk \(part.index) size mismatch (\(actualSize) != \(expectedSize))")
                    }
                }
            }
            try await group.waitForAll()
        }

        try Task.checkCancellation()
        monitorTask.cancel()

        // Merge parts sequentially using 1 MB streaming buffer
        let stagingURL = tempDir.appendingPathComponent("merged_output")
        FileManager.default.createFile(atPath: stagingURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: stagingURL)
        defer { try? outHandle.close() }

        let copyBufferSize = 1024 * 1024
        for part in parts {
            try Task.checkCancellation()
            let inHandle = try FileHandle(forReadingFrom: part.url)
            defer { try? inHandle.close() }
            while true {
                let data = try inHandle.read(upToCount: copyBufferSize)
                guard let data, !data.isEmpty else { break }
                try outHandle.write(contentsOf: data)
            }
        }
        try outHandle.close()

        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: stagingURL, to: localURL)
        progress?(remoteSize)
        logInfo("Downloaded FTP file in \(chunkCount) streams: \(remotePath) -> \(localURL.path)", category: .sftp)
    }

    /// Runs `/usr/bin/curl` passing credentials securely via stdin (`--config -`)
    private func executeCurl(
        args: [String],
        onProgressPercent: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let configLine = "user = \"\(escapedUser):\(escapedPass)\"\n"

        var fullArgs = ["--config", "-"]
        if useFTPS {
            fullArgs.append(contentsOf: ["--ssl-reqd", "-k"])
        }
        if onProgressPercent != nil {
            fullArgs.append(contentsOf: ["--progress-bar", "--show-error", "--fail"])
        }
        fullArgs.append(contentsOf: args)

        let box = CurlProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    if box.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                    process.arguments = fullArgs

                    let stdinPipe = Pipe()
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardInput = stdinPipe
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    guard box.setProcess(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    do {
                        try process.run()
                        if let configData = configLine.data(using: .utf8) {
                            stdinPipe.fileHandleForWriting.write(configData)
                        }
                        try? stdinPipe.fileHandleForWriting.close()

                        let ioGroup = DispatchGroup()
                        let buffer = PipeDataBuffer()

                        ioGroup.enter()
                        DispatchQueue.global(qos: .utility).async {
                            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            buffer.setStdout(data)
                            ioGroup.leave()
                        }

                        ioGroup.enter()
                        DispatchQueue.global(qos: .utility).async {
                            var lastReportedPercent: Double = -1
                            let stderrHandle = stderrPipe.fileHandleForReading
                            var pendingText = ""

                            while true {
                                let chunk = stderrHandle.availableData
                                if chunk.isEmpty { break }

                                buffer.appendStderr(chunk)

                                if let onProgressPercent,
                                   let str = String(data: chunk, encoding: .utf8) ?? String(data: chunk, encoding: .isoLatin1) {
                                    pendingText += str
                                    let segments = pendingText.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                                    if let tail = segments.last {
                                        pendingText = tail
                                    }
                                    for seg in segments.dropLast() {
                                        if let pct = Self.parseProgressPercentage(from: seg),
                                           pct >= lastReportedPercent + 0.5 || (pct >= 100 && lastReportedPercent < 100) {
                                            lastReportedPercent = pct
                                            onProgressPercent(pct)
                                        }
                                    }
                                    if let pct = Self.parseProgressPercentage(from: pendingText),
                                       pct >= lastReportedPercent + 0.5 || (pct >= 100 && lastReportedPercent < 100) {
                                        lastReportedPercent = pct
                                        onProgressPercent(pct)
                                    }
                                }
                            }
                            ioGroup.leave()
                        }

                        ioGroup.wait()
                        process.waitUntilExit()

                        if box.isCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }

                        let captured = buffer.snapshot()
                        let outString = String(data: captured.out, encoding: .utf8) ?? String(data: captured.out, encoding: .isoLatin1) ?? ""
                        let rawErrString = String(data: captured.err, encoding: .utf8) ?? ""
                        let errString = Self.extractCurlErrorMessage(from: rawErrString)

                        if process.terminationStatus == 0 {
                            continuation.resume(returning: outString)
                        } else {
                            let exitCode = process.terminationStatus
                            if exitCode == 67 || errString.lowercased().contains("login") || errString.lowercased().contains("530") || errString.lowercased().contains("password") || errString.lowercased().contains("auth") {
                                continuation.resume(throwing: AppError.authenticationFailed)
                            } else if exitCode == 7 || errString.lowercased().contains("couldn't connect") {
                                continuation.resume(throwing: AppError.connectionFailed(errString.isEmpty ? "Could not connect to FTP server." : errString))
                            } else if exitCode == 28 || errString.lowercased().contains("timed out") {
                                continuation.resume(throwing: AppError.connectionTimeout)
                            } else if exitCode == 9 || errString.lowercased().contains("550") {
                                continuation.resume(throwing: AppError.sftpOperationFailed(errString.isEmpty ? "FTP permission denied or file not found (550)." : errString))
                            } else {
                                continuation.resume(throwing: AppError.sftpOperationFailed(errString.isEmpty ? "FTP operation failed (code \(exitCode))." : errString))
                            }
                        }
                    } catch {
                        if box.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: AppError.connectionFailed(error.localizedDescription))
                        }
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    nonisolated private static func parseProgressPercentage(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("%"), let lastToken = trimmed.split(separator: " ").last else { return nil }
        let numberStr = lastToken.dropLast()
        guard let value = Double(numberStr), value >= 0, value <= 100 else { return nil }
        return value
    }

    nonisolated private static func extractCurlErrorMessage(from rawStderr: String) -> String {
        let lines = rawStderr
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasSuffix("%") }
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - FTP LIST Parser (Unix ls -l & Windows/DOS formats)

    nonisolated static func parseFTPListOutput(_ output: String, directoryPath: String) -> [RemoteFile] {
        var results: [RemoteFile] = []
        let lines = output.components(separatedBy: .newlines)

        let dateFormatterRecent = DateFormatter()
        dateFormatterRecent.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterRecent.dateFormat = "MMM d HH:mm yyyy"

        let dateFormatterYear = DateFormatter()
        dateFormatterYear.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterYear.dateFormat = "MMM d yyyy"

        let dosDateFormatter = DateFormatter()
        dosDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dosDateFormatter.dateFormat = "MM-dd-yy hh:mma"

        let currentYear = Calendar.current.component(.year, from: Date())

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            guard !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("total ") { continue }

            // 1. Try Unix-style ls -l line:
            // drwxr-xr-x   2 owner group      4096 Nov 18 15:30 filename
            if let firstChar = line.first, "dl-bcps".contains(firstChar), line.count > 30 {
                let tokens = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                if tokens.count >= 9 {
                    let perms = String(tokens[0])
                    let owner = String(tokens[2])
                    let group = String(tokens[3])
                    let size = Int64(tokens[4]) ?? 0
                    let month = String(tokens[5])
                    let day = String(tokens[6])
                    let timeOrYear = String(tokens[7])
                    var rawName = String(tokens[8])

                    // Handle symlink "name -> target"
                    if perms.hasPrefix("l"), let arrowRange = rawName.range(of: " -> ") {
                        rawName = String(rawName[..<arrowRange.lowerBound])
                    }

                    guard rawName != ".", rawName != "..", !rawName.isEmpty else { continue }

                    let isDir = perms.hasPrefix("d")
                    let modDate: Date?
                    if timeOrYear.contains(":") {
                        modDate = dateFormatterRecent.date(from: "\(month) \(day) \(timeOrYear) \(currentYear)")
                    } else {
                        modDate = dateFormatterYear.date(from: "\(month) \(day) \(timeOrYear)")
                    }

                    let fullPath = directoryPath.hasSuffix("/") ? "\(directoryPath)\(rawName)" : "\(directoryPath)/\(rawName)"
                    results.append(
                        RemoteFile(
                            name: rawName,
                            path: fullPath,
                            isDirectory: isDir,
                            size: size,
                            permissions: perms,
                            modificationDate: modDate,
                            owner: owner,
                            group: group
                        )
                    )
                    continue
                }
            }

            // 2. Try Windows/DOS FTP style:
            // 11-18-26  03:30PM       <DIR>          FolderName
            // 11-18-26  03:30PM                12345 FileName.txt
            let dosTokens = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            if dosTokens.count == 4 {
                let dateStr = String(dosTokens[0])
                let timeStr = String(dosTokens[1])
                let dirOrSize = String(dosTokens[2])
                let name = String(dosTokens[3])
                guard name != ".", name != ".." else { continue }

                if let modDate = dosDateFormatter.date(from: "\(dateStr) \(timeStr)") {
                    let isDir = dirOrSize.uppercased() == "<DIR>"
                    let size = isDir ? 0 : (Int64(dirOrSize) ?? 0)
                    let perms = isDir ? "drwxr-xr-x" : "-rw-r--r--"
                    let fullPath = directoryPath.hasSuffix("/") ? "\(directoryPath)\(name)" : "\(directoryPath)/\(name)"
                    results.append(
                        RemoteFile(
                            name: name,
                            path: fullPath,
                            isDirectory: isDir,
                            size: size,
                            permissions: perms,
                            modificationDate: modDate
                        )
                    )
                }
            }
        }

        return results
    }
}
