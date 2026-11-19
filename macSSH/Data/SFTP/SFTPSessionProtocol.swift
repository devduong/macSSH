//
//  SFTPSessionProtocol.swift
//  macSSH
//
//  Protocol for SFTP session operations
//

import Foundation

protocol SFTPSessionProtocol: Sendable {
    /// Whether the session is currently connected
    var isConnected: Bool { get async }

    /// Current working directory
    var currentPath: String { get async }

    /// Connect to the server with password authentication
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        socksProxyPort: Int?,
        socksProxyAllowLAN: Bool
    ) async throws

    /// Connect to the server with private key authentication
    /// - Note: Passphrase support depends on the underlying implementation.
    ///         Currently, passphrase-protected keys may not be supported.
    ///         Use unencrypted keys or convert encrypted keys to unencrypted format.
    func connect(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        passphrase: String?,
        socksProxyPort: Int?,
        socksProxyAllowLAN: Bool
    ) async throws

    /// Disconnect from the server
    func disconnect() async

    /// List files in a directory
    func listFiles(at path: String) async throws -> [RemoteFile]

    /// Get file attributes
    func getFileInfo(at path: String) async throws -> RemoteFile

    /// Create a directory
    func createDirectory(at path: String) async throws

    /// Create multiple directories (optimized batch operation when supported)
    func createDirectories(at paths: [String]) async throws

    /// Create an empty file
    func createFile(at path: String) async throws

    /// Delete a file
    func deleteFile(at path: String) async throws

    /// Delete a directory (recursively)
    func deleteDirectory(at path: String) async throws

    /// Rename/move a file or directory
    func rename(from sourcePath: String, to destinationPath: String) async throws

    /// Copy a file
    func copyFile(from sourcePath: String, to destinationPath: String) async throws

    /// Copy a directory (recursively)
    func copyDirectory(from sourcePath: String, to destinationPath: String) async throws

    /// Move a file or directory
    func move(from sourcePath: String, to destinationPath: String) async throws

    /// Download a file
    func downloadFile(from remotePath: String, to localURL: URL) async throws

    /// Download a file with progress reporting
    func downloadFile(from remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws

    /// Download a file with optional multi-stream concurrency override and progress reporting
    func downloadFile(from remotePath: String, to localURL: URL, streamCount: Int?, progress: TransferProgressHandler?) async throws

    /// Download a specific byte range of a remote file without downloading the entire file
    func downloadRange(from remotePath: String, offset: Int64, length: Int64) async throws -> Data

    /// Stream bytes of a remote file (optionally from offset/length) directly to a consumer; cancels cleanly when consumer stops
    func streamFile(
        from remotePath: String,
        offset: Int64,
        length: Int64?,
        onChunk: @escaping @Sendable (Data) async throws -> Void
    ) async throws

    /// Configure preferred maximum concurrent transfer streams for the session (used by FTP)
    func setPreferredMaxStreams(_ count: Int) async

    /// Upload a file
    func uploadFile(from localURL: URL, to remotePath: String) async throws

    /// Upload a file with progress reporting
    func uploadFile(from localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws

    /// Read file content as string
    func readFileContent(at path: String) async throws -> String

    /// Write string content to a file
    func writeFileContent(_ content: String, to path: String) async throws

    /// Get the real/absolute path (resolves ~ and symlinks)
    func getRealPath(at path: String) async throws -> String

    /// Execute a shell command
    func executeCommand(_ command: String) async throws -> String
}

// MARK: - Default Implementations
extension SFTPSessionProtocol {
    func setPreferredMaxStreams(_ count: Int) async {}

    func createDirectories(at paths: [String]) async throws {
        for path in paths {
            try Task.checkCancellation()
            try? await createDirectory(at: path)
        }
    }

    func downloadFile(
        from remotePath: String,
        to localURL: URL,
        streamCount: Int?,
        progress: TransferProgressHandler?
    ) async throws {
        try await downloadFile(from: remotePath, to: localURL, progress: progress)
    }

    func downloadRange(from remotePath: String, offset: Int64, length: Int64) async throws -> Data {
        guard length > 0 else { return Data() }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_range_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await downloadFile(from: remotePath, to: tempURL, progress: nil)
        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        return try handle.read(upToCount: Int(length)) ?? Data()
    }

    func streamFile(
        from remotePath: String,
        offset: Int64,
        length: Int64?,
        onChunk: @escaping @Sendable (Data) async throws -> Void
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("macssh_stream_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await downloadFile(from: remotePath, to: tempURL, progress: nil)
        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seek(toOffset: UInt64(offset))
        }
        var remaining = length ?? Int64.max
        let chunkSize = 256 * 1024
        while remaining > 0 {
            try Task.checkCancellation()
            let toRead = Int(min(Int64(chunkSize), remaining))
            guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else { break }
            try await onChunk(chunk)
            if length != nil {
                remaining -= Int64(chunk.count)
            }
        }
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String
    ) async throws {
        try await connect(
            host: host,
            port: port,
            username: username,
            password: password,
            socksProxyPort: nil,
            socksProxyAllowLAN: false
        )
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        socksProxyPort: Int?
    ) async throws {
        try await connect(
            host: host,
            port: port,
            username: username,
            password: password,
            socksProxyPort: socksProxyPort,
            socksProxyAllowLAN: false
        )
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        passphrase: String?
    ) async throws {
        try await connect(
            host: host,
            port: port,
            username: username,
            privateKeyPath: privateKeyPath,
            passphrase: passphrase,
            socksProxyPort: nil,
            socksProxyAllowLAN: false
        )
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        passphrase: String?,
        socksProxyPort: Int?
    ) async throws {
        try await connect(
            host: host,
            port: port,
            username: username,
            privateKeyPath: privateKeyPath,
            passphrase: passphrase,
            socksProxyPort: socksProxyPort,
            socksProxyAllowLAN: false
        )
    }
}
