//
//  WebDAVBridge.swift
//  macSSH
//
//  WebDAV Class 2 protocol handler backed by SFTPSessionProtocol (FTP, SFTP).
//  Includes short-TTL directory caching, ranged GET read caching with coalescing,
//  virtual Apple metadata shadow handling (._*, .DS_Store, .TemporaryItems),
//  and Class 2 LOCK/UNLOCK support for full Read-Write Finder mounting.
//

import Foundation

nonisolated private enum WebDAVDateFormatters {
    static let rfc1123Lock = NSLock()
    static let iso8601Lock = NSLock()

    private static let rfc1123Formatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "GMT")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return df
    }()

    private static let iso8601Formatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return df
    }()

    static func rfc1123(_ date: Date) -> String {
        rfc1123Lock.lock()
        defer { rfc1123Lock.unlock() }
        return rfc1123Formatter.string(from: date)
    }

    static func iso8601(_ date: Date) -> String {
        iso8601Lock.lock()
        defer { iso8601Lock.unlock() }
        return iso8601Formatter.string(from: date)
    }

    static func parseHTTPDate(_ string: String) -> Date? {
        rfc1123Lock.lock()
        defer { rfc1123Lock.unlock() }
        return rfc1123Formatter.date(from: string)
    }
}

nonisolated private final class CacheTeeWriter: @unchecked Sendable {
    private let lock = NSLock()
    let url: URL
    private var handle: FileHandle?
    private var writtenBytes: Int64 = 0

    init?(url: URL) {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        self.handle = h
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            writtenBytes += Int64(data.count)
        } catch {
            try? handle.close()
            self.handle = nil
        }
    }

    func finish() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
        return writtenBytes
    }

    func abort() {
        lock.lock()
        try? handle?.close()
        handle = nil
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }
}

actor WebDAVReadGate {
    private let maxConcurrent: Int
    private var activeCount: Int = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        let waiterId = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.waiters.append((waiterId, continuation))
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterId)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let idx = waiters.firstIndex(where: { $0.id == id }) {
            let entry = waiters.remove(at: idx)
            entry.continuation.resume(throwing: CancellationError())
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}

actor WebDAVBridge {
    private struct WebDAVLock: Sendable {
        let token: String
        let path: String
        let isExclusive: Bool
        let createdAt: Date
    }

    private struct VirtualEntry: Sendable {
        let path: String
        let isDirectory: Bool
        var data: Data
        var modifiedAt: Date
    }

    private struct CachedDirectoryEntry: Sendable {
        let fetchedAt: Date
        let files: [RemoteFile]
    }

    private struct CachedReadFile: Sendable {
        let path: String
        let localURL: URL
        let size: Int64
        let signature: String
        var lastAccessed: Date
    }

    private var session: SFTPSessionProtocol
    private let connectionType: ConnectionType
    private let urlPrefix: String
    private let mountTempDir: URL
    private let readCacheDir: URL
    private let mountStartDate = Date()

    private var dirCache: [String: CachedDirectoryEntry] = [:]
    private var inFlightListings: [String: Task<[RemoteFile], Error>] = [:]

    private var readCache: [String: CachedReadFile] = [:]
    private var inFlightDownloads: [String: Task<CachedReadFile, Error>] = [:]
    private let readGate = WebDAVReadGate(maxConcurrent: 3)

    private var locks: [String: WebDAVLock] = [:]
    private var virtualEntries: [String: VirtualEntry] = [:]
    private var virtualTotalBytes: Int = 0

    private static let dirCacheTTL: TimeInterval = 15.0
    private static let readCacheTTL: TimeInterval = 60.0
    private static let maxReadCacheBytes: Int64 = 256 * 1024 * 1024
    private static let maxOpportunisticCacheFileSize: Int64 = 8 * 1024 * 1024
    private static let maxSmallRangeBufferBytes: Int64 = 2 * 1024 * 1024
    private static let maxVirtualEntryBytes = 2 * 1024 * 1024
    private static let maxVirtualTotalBytes = 16 * 1024 * 1024

    /// Root sentinel entries exposed on direct lookup (Depth: 0 / GET / HEAD) to stop
    /// macOS Spotlight, QuickLook thumbnailing, and FSEvents from crawling remote files,
    /// while staying hidden from root directory listings (Depth: 1).
    private static let hiddenRootSentinels: Set<String> = [
        "/.metadata_never_index",
        "/.ql_disablethumbnails",
        "/.ql_disablecache",
        "/.fseventsd",
        "/.fseventsd/no_log"
    ]

    private static let appleMetadataNames: Set<String> = [
        ".DS_Store",
        ".Trashes",
        ".TemporaryItems",
        ".Spotlight-V100",
        ".fseventsd",
        ".VolumeIcon.icns",
        ".ql_disablethumbnails",
        ".ql_disablecache",
        ".hidden",
        ".metadata_never_index",
        ".apdisk",
        ".localized",
        ".com.apple.timemachine.donotpresent",
        ".DocumentRevisions-V100",
        ".PKInstallSandboxManager",
        ".PKInstallSandboxManager-SystemSoftware",
        "Backups.backupdb",
        ".file",
        ".vol",
        "mach_kernel",
        ".hotfiles.btree",
        "Icon\r",
        "Desktop.ini",
        "Thumbs.db"
    ]

    init(
        session: SFTPSessionProtocol,
        connectionType: ConnectionType,
        urlPrefix: String,
        mountTempDir: URL
    ) {
        self.session = session
        self.connectionType = connectionType
        self.urlPrefix = urlPrefix.hasSuffix("/") ? String(urlPrefix.dropLast()) : urlPrefix
        self.mountTempDir = mountTempDir
        self.readCacheDir = mountTempDir.appendingPathComponent("read_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.readCacheDir, withIntermediateDirectories: true)

        // Pre-seed macOS root sentinels to prevent Spotlight / QuickLook / FSEvents from
        // eagerly downloading files just when opening a folder in Finder.
        let now = Date()
        self.virtualEntries["/.TemporaryItems"] = VirtualEntry(
            path: "/.TemporaryItems",
            isDirectory: true,
            data: Data(),
            modifiedAt: now
        )
        self.virtualEntries["/.metadata_never_index"] = VirtualEntry(
            path: "/.metadata_never_index",
            isDirectory: false,
            data: Data(),
            modifiedAt: now
        )
        self.virtualEntries["/.ql_disablethumbnails"] = VirtualEntry(
            path: "/.ql_disablethumbnails",
            isDirectory: false,
            data: Data(),
            modifiedAt: now
        )
        self.virtualEntries["/.ql_disablecache"] = VirtualEntry(
            path: "/.ql_disablecache",
            isDirectory: false,
            data: Data(),
            modifiedAt: now
        )
        self.virtualEntries["/.fseventsd"] = VirtualEntry(
            path: "/.fseventsd",
            isDirectory: true,
            data: Data(),
            modifiedAt: now
        )
        self.virtualEntries["/.fseventsd/no_log"] = VirtualEntry(
            path: "/.fseventsd/no_log",
            isDirectory: false,
            data: Data(),
            modifiedAt: now
        )
    }

    func replaceSession(_ newSession: SFTPSessionProtocol) {
        session = newSession
        dirCache.removeAll()
        inFlightListings.removeAll()
    }

    func cleanup() {
        for (_, task) in inFlightDownloads {
            task.cancel()
        }
        inFlightDownloads.removeAll()
        inFlightListings.removeAll()
        dirCache.removeAll()
        readCache.removeAll()
        virtualEntries.removeAll()
        locks.removeAll()
        try? FileManager.default.removeItem(at: mountTempDir)
    }

    // MARK: - Main Request Router

    func handle(_ request: WebDAVHTTPRequest) async -> WebDAVHTTPResponse {
        guard let remotePath = resolveRemotePath(fromTarget: request.target) else {
            return .text(403, "Forbidden")
        }

        do {
            switch request.method {
            case "OPTIONS":
                return handleOptions()
            case "PROPFIND":
                return try await handlePropfind(request, remotePath: remotePath)
            case "PROPPATCH":
                return handleProppatch(request, remotePath: remotePath)
            case "HEAD":
                return try await handleHeadOrGet(request, remotePath: remotePath, isHead: true)
            case "GET":
                return try await handleHeadOrGet(request, remotePath: remotePath, isHead: false)
            case "PUT":
                return try await handlePut(request, remotePath: remotePath)
            case "MKCOL":
                return try await handleMkcol(request, remotePath: remotePath)
            case "DELETE":
                return try await handleDelete(remotePath: remotePath)
            case "MOVE":
                return try await handleMoveOrCopy(request, sourcePath: remotePath, isMove: true)
            case "COPY":
                return try await handleMoveOrCopy(request, sourcePath: remotePath, isMove: false)
            case "LOCK":
                return handleLock(request, remotePath: remotePath)
            case "UNLOCK":
                return handleUnlock(request)
            default:
                return WebDAVHTTPResponse(
                    statusCode: 405,
                    headers: [
                        ("Allow", Self.allowedMethods),
                        ("Content-Length", "0")
                    ]
                )
            }
        } catch {
            return mapErrorToResponse(error)
        }
    }

    // MARK: - OPTIONS

    private static let allowedMethods = "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, MOVE, COPY, LOCK, UNLOCK"

    private func handleOptions() -> WebDAVHTTPResponse {
        WebDAVHTTPResponse(
            statusCode: 200,
            headers: [
                ("DAV", "1, 2"),
                ("Allow", Self.allowedMethods),
                ("MS-Author-Via", "DAV"),
                ("Accept-Ranges", "bytes"),
                ("Content-Length", "0")
            ]
        )
    }

    // MARK: - PROPFIND

    private func handlePropfind(_ request: WebDAVHTTPRequest, remotePath: String) async throws -> WebDAVHTTPResponse {
        let depthHeader = (request.header("Depth") ?? "1").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let depth = (depthHeader == "0") ? 0 : 1

        let bodyStr = String(data: request.bodyData(), encoding: .utf8) ?? ""
        let includeQuota = bodyStr.contains("quota") || remotePath == "/"

        // 1. Virtual Apple metadata path
        if Self.isAppleMetadataPath(remotePath) {
            guard let vEntry = virtualEntries[remotePath] else {
                return .text(404, "Not Found")
            }

            var responsesXML = buildResponseXML(
                remotePath: vEntry.path,
                isDirectory: vEntry.isDirectory,
                size: Int64(vEntry.data.count),
                modifiedAt: vEntry.modifiedAt,
                includeQuota: false
            )

            if depth == 1 && vEntry.isDirectory {
                let prefix = vEntry.path == "/" ? "/" : vEntry.path + "/"
                for (childPath, child) in virtualEntries where childPath != vEntry.path && childPath.hasPrefix(prefix) {
                    let remainder = String(childPath.dropFirst(prefix.count))
                    if !remainder.contains("/") && !remainder.isEmpty {
                        responsesXML += buildResponseXML(
                            remotePath: child.path,
                            isDirectory: child.isDirectory,
                            size: Int64(child.data.count),
                            modifiedAt: child.modifiedAt,
                            includeQuota: false
                        )
                    }
                }
            }

            return buildMultiStatusResponse(responsesXML)
        }

        // 2. Remote resource lookup
        guard let targetInfo = try await lookupRemoteFile(at: remotePath) else {
            return .text(404, "Not Found")
        }

        var responsesXML = buildResponseXML(
            remotePath: remotePath,
            isDirectory: targetInfo.isDirectory,
            size: targetInfo.size,
            modifiedAt: targetInfo.modificationDate ?? mountStartDate,
            includeQuota: includeQuota && targetInfo.isDirectory
        )

        if depth == 1 && targetInfo.isDirectory {
            let children = try await listDirectory(at: remotePath)
            for child in children {
                let childPath = remotePath == "/" ? "/\(child.name)" : "\(remotePath)/\(child.name)"
                responsesXML += buildResponseXML(
                    remotePath: childPath,
                    isDirectory: child.isDirectory,
                    size: child.size,
                    modifiedAt: child.modificationDate ?? mountStartDate,
                    includeQuota: false
                )
            }

            // Include user-created virtual metadata files (excluding hidden root sentinels)
            let dirPrefix = remotePath == "/" ? "/" : remotePath + "/"
            for (vPath, vEntry) in virtualEntries where vPath.hasPrefix(dirPrefix) && !Self.hiddenRootSentinels.contains(vPath) {
                let remainder = String(vPath.dropFirst(dirPrefix.count))
                if !remainder.contains("/") && !remainder.isEmpty {
                    responsesXML += buildResponseXML(
                        remotePath: vEntry.path,
                        isDirectory: vEntry.isDirectory,
                        size: Int64(vEntry.data.count),
                        modifiedAt: vEntry.modifiedAt,
                        includeQuota: false
                    )
                }
            }
        }

        return buildMultiStatusResponse(responsesXML)
    }

    private func buildMultiStatusResponse(_ entriesXML: String) -> WebDAVHTTPResponse {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
        \(entriesXML)</D:multistatus>
        """
        let data = Data(xml.utf8)
        return WebDAVHTTPResponse(
            statusCode: 207,
            reasonPhrase: "Multi-Status",
            headers: [
                ("Content-Type", "text/xml; charset=\"utf-8\""),
                ("Content-Length", "\(data.count)")
            ],
            body: .data(data)
        )
    }

    private func buildResponseXML(
        remotePath: String,
        isDirectory: Bool,
        size: Int64,
        modifiedAt: Date,
        includeQuota: Bool
    ) -> String {
        let href = Self.xmlEscape(buildHref(for: remotePath, isDirectory: isDirectory))
        let lastMod = WebDAVDateFormatters.rfc1123(modifiedAt)
        let created = WebDAVDateFormatters.iso8601(modifiedAt)

        var propXML = """
                <D:creationdate>\(created)</D:creationdate>
                <D:getlastmodified>\(lastMod)</D:getlastmodified>
        """

        if isDirectory {
            propXML += "\n                <D:resourcetype><D:collection/></D:resourcetype>"
            if includeQuota {
                propXML += """
                \n                <D:quota-available-bytes>1099511627776</D:quota-available-bytes>
                <D:quota-used-bytes>0</D:quota-used-bytes>
                <D:quota>2147483648</D:quota>
                <D:quotaused>0</D:quotaused>
                """
            }
        } else {
            let etag = Self.makeETag(size: size, modifiedAt: modifiedAt)
            propXML += """
            \n                <D:getcontentlength>\(max(0, size))</D:getcontentlength>
                <D:getetag>\(Self.xmlEscape(etag))</D:getetag>
                <D:resourcetype/>
            """
        }

        return """
          <D:response>
            <D:href>\(href)</D:href>
            <D:propstat>
              <D:prop>
        \(propXML)
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>

        """
    }

    // MARK: - PROPPATCH

    private func handleProppatch(_ request: WebDAVHTTPRequest, remotePath: String) -> WebDAVHTTPResponse {
        let href = Self.xmlEscape(buildHref(for: remotePath, isDirectory: false))
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>\(href)</D:href>
            <D:propstat>
              <D:prop>
                <D:getlastmodified/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let data = Data(xml.utf8)
        return WebDAVHTTPResponse(
            statusCode: 207,
            reasonPhrase: "Multi-Status",
            headers: [
                ("Content-Type", "text/xml; charset=\"utf-8\""),
                ("Content-Length", "\(data.count)")
            ],
            body: .data(data)
        )
    }

    // MARK: - GET & HEAD

    private func handleHeadOrGet(
        _ request: WebDAVHTTPRequest,
        remotePath: String,
        isHead: Bool
    ) async throws -> WebDAVHTTPResponse {
        // 1. Virtual metadata files
        if Self.isAppleMetadataPath(remotePath) {
            guard let entry = virtualEntries[remotePath], !entry.isDirectory else {
                return .text(404, "Not Found")
            }
            let etag = Self.makeETag(size: Int64(entry.data.count), modifiedAt: entry.modifiedAt)
            return serveInMemoryBytes(
                entry.data,
                modifiedAt: entry.modifiedAt,
                etag: etag,
                request: request,
                isHead: isHead
            )
        }

        // 2. Real remote file lookup
        guard let info = try await lookupRemoteFile(at: remotePath) else {
            return .text(404, "Not Found")
        }
        if info.isDirectory {
            return WebDAVHTTPResponse(
                statusCode: 200,
                headers: [
                    ("Content-Type", "text/html; charset=utf-8"),
                    ("Content-Length", "0")
                ]
            )
        }

        let modDate = info.modificationDate ?? mountStartDate
        let etag = Self.makeETag(size: info.size, modifiedAt: modDate)

        if let ifModSince = request.header("If-Modified-Since"),
           let clientDate = WebDAVDateFormatters.parseHTTPDate(ifModSince),
           Int(modDate.timeIntervalSince1970) <= Int(clientDate.timeIntervalSince1970) {
            return WebDAVHTTPResponse(
                statusCode: 304,
                headers: [
                    ("ETag", etag),
                    ("Last-Modified", WebDAVDateFormatters.rfc1123(modDate)),
                    ("Content-Length", "0")
                ]
            )
        }

        if isHead {
            return WebDAVHTTPResponse(
                statusCode: 200,
                headers: [
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", "\(max(0, info.size))"),
                    ("Last-Modified", WebDAVDateFormatters.rfc1123(modDate)),
                    ("ETag", etag),
                    ("Accept-Ranges", "bytes")
                ]
            )
        }

        // 2a. Fast-path: serve immediately from read cache if valid
        let signature = "\(info.size)-\(Int(info.modificationDate?.timeIntervalSince1970 ?? -1))"
        if let cached = validCachedFile(at: remotePath, signature: signature) {
            return serveCachedFile(cached, modDate: modDate, etag: etag, request: request)
        }

        let total = max(0, info.size)
        let baseHeaders: [(String, String)] = [
            ("Content-Type", "application/octet-stream"),
            ("Last-Modified", WebDAVDateFormatters.rfc1123(modDate)),
            ("ETag", etag),
            ("Accept-Ranges", "bytes")
        ]

        // 2b. Range GET: fetch ONLY requested byte range (never downloads full file for header/preview probes)
        if let rangeHeader = request.header("Range"),
           Self.shouldHonorRange(request: request, etag: etag, modDate: modDate) {
            guard let (start, end) = Self.parseByteRange(rangeHeader, totalLength: total) else {
                return WebDAVHTTPResponse(
                    statusCode: 416,
                    headers: [
                        ("Content-Range", "bytes */\(total)"),
                        ("Content-Length", "0")
                    ]
                )
            }
            let sliceLen = end - start + 1
            var headers = baseHeaders
            headers.append(("Content-Range", "bytes \(start)-\(end)/\(total)"))
            headers.append(("Content-Length", "\(sliceLen)"))

            if sliceLen <= Self.maxSmallRangeBufferBytes {
                let activeSession = self.session
                let gate = self.readGate
                let rangeData = try await gate.withPermit {
                    try await activeSession.downloadRange(from: remotePath, offset: start, length: sliceLen)
                }
                let actualLen = Int64(rangeData.count)
                if actualLen != sliceLen {
                    headers = baseHeaders
                    if actualLen > 0 {
                        headers.append(("Content-Range", "bytes \(start)-\(start + actualLen - 1)/\(total)"))
                    }
                    headers.append(("Content-Length", "\(actualLen)"))
                }
                return WebDAVHTTPResponse(statusCode: 206, headers: headers, body: .data(rangeData))
            }

            let activeSession = self.session
            let gate = self.readGate
            return WebDAVHTTPResponse(
                statusCode: 206,
                headers: headers,
                body: .stream(length: sliceLen) { emit in
                    try await gate.withPermit {
                        try await activeSession.streamFile(
                            from: remotePath,
                            offset: start,
                            length: sliceLen,
                            onChunk: emit
                        )
                    }
                }
            )
        }

        // 2c. Full GET: stream directly without blocking on whole-file download;
        // cancels remote transfer immediately if Finder/QuickLook closes the socket early.
        var headers = baseHeaders
        headers.append(("Content-Length", "\(total)"))
        if total == 0 {
            return WebDAVHTTPResponse(statusCode: 200, headers: headers, body: .empty)
        }

        let activeSession = self.session
        let gate = self.readGate
        let shouldCacheOnComplete = total <= Self.maxOpportunisticCacheFileSize
        let cacheStagingURL = shouldCacheOnComplete
            ? readCacheDir.appendingPathComponent("cache_\(UUID().uuidString).bin")
            : nil

        return WebDAVHTTPResponse(
            statusCode: 200,
            headers: headers,
            body: .stream(length: total) { [weak self] emit in
                try await gate.withPermit {
                    let tee = cacheStagingURL.flatMap { CacheTeeWriter(url: $0) }
                    do {
                        try await activeSession.streamFile(
                            from: remotePath,
                            offset: 0,
                            length: total
                        ) { chunk in
                            try await emit(chunk)
                            tee?.append(chunk)
                        }
                        if let tee {
                            let written = tee.finish()
                            if written == total, let self {
                                await self.promoteToReadCache(
                                    path: remotePath,
                                    localURL: tee.url,
                                    size: written,
                                    signature: signature
                                )
                            } else {
                                try? FileManager.default.removeItem(at: tee.url)
                            }
                        }
                    } catch {
                        tee?.abort()
                        throw error
                    }
                }
            }
        )
    }

    private func serveInMemoryBytes(
        _ data: Data,
        modifiedAt: Date,
        etag: String,
        request: WebDAVHTTPRequest,
        isHead: Bool
    ) -> WebDAVHTTPResponse {
        let total = Int64(data.count)
        let baseHeaders: [(String, String)] = [
            ("Content-Type", "application/octet-stream"),
            ("Last-Modified", WebDAVDateFormatters.rfc1123(modifiedAt)),
            ("ETag", etag),
            ("Accept-Ranges", "bytes")
        ]

        if let rangeHeader = request.header("Range"),
           Self.shouldHonorRange(request: request, etag: etag, modDate: modifiedAt) {
            guard let (start, end) = Self.parseByteRange(rangeHeader, totalLength: total) else {
                return WebDAVHTTPResponse(
                    statusCode: 416,
                    headers: [
                        ("Content-Range", "bytes */\(total)"),
                        ("Content-Length", "0")
                    ]
                )
            }
            let sliceLen = end - start + 1
            var headers = baseHeaders
            headers.append(("Content-Range", "bytes \(start)-\(end)/\(total)"))
            headers.append(("Content-Length", "\(sliceLen)"))
            if isHead {
                return WebDAVHTTPResponse(statusCode: 206, headers: headers)
            }
            let slice = data[Int(start)...Int(end)]
            return WebDAVHTTPResponse(statusCode: 206, headers: headers, body: .data(Data(slice)))
        }

        var headers = baseHeaders
        headers.append(("Content-Length", "\(total)"))
        return WebDAVHTTPResponse(
            statusCode: 200,
            headers: headers,
            body: isHead ? .empty : .data(data)
        )
    }

    private func serveCachedFile(
        _ cached: CachedReadFile,
        modDate: Date,
        etag: String,
        request: WebDAVHTTPRequest
    ) -> WebDAVHTTPResponse {
        let total = cached.size
        let baseHeaders: [(String, String)] = [
            ("Content-Type", "application/octet-stream"),
            ("Last-Modified", WebDAVDateFormatters.rfc1123(modDate)),
            ("ETag", etag),
            ("Accept-Ranges", "bytes")
        ]

        if let rangeHeader = request.header("Range"),
           Self.shouldHonorRange(request: request, etag: etag, modDate: modDate) {
            guard let (start, end) = Self.parseByteRange(rangeHeader, totalLength: total) else {
                return WebDAVHTTPResponse(
                    statusCode: 416,
                    headers: [
                        ("Content-Range", "bytes */\(total)"),
                        ("Content-Length", "0")
                    ]
                )
            }
            let sliceLen = end - start + 1
            var headers = baseHeaders
            headers.append(("Content-Range", "bytes \(start)-\(end)/\(total)"))
            headers.append(("Content-Length", "\(sliceLen)"))
            return WebDAVHTTPResponse(
                statusCode: 206,
                headers: headers,
                body: .fileRange(url: cached.localURL, offset: start, length: sliceLen)
            )
        }

        var headers = baseHeaders
        headers.append(("Content-Length", "\(total)"))
        return WebDAVHTTPResponse(
            statusCode: 200,
            headers: headers,
            body: total > 0 ? .fileRange(url: cached.localURL, offset: 0, length: total) : .empty
        )
    }

    // MARK: - PUT

    private func handlePut(_ request: WebDAVHTTPRequest, remotePath: String) async throws -> WebDAVHTTPResponse {
        guard remotePath != "/" else {
            return .text(405, "Cannot PUT to root")
        }

        // Handle virtual Apple metadata files locally without touching remote server
        if Self.isAppleMetadataPath(remotePath) {
            let existed = virtualEntries[remotePath] != nil
            let data = request.bodyData(maxBytes: Self.maxVirtualEntryBytes)
            storeVirtualFile(at: remotePath, data: data)
            return WebDAVHTTPResponse(statusCode: existed ? 204 : 201, headers: [("Content-Length", "0")])
        }

        let existed = (try? await lookupRemoteFile(at: remotePath)) != nil

        // Ensure we have a file on disk to stream to remote
        let uploadURL: URL
        var createdTempForUpload = false
        switch request.body {
        case .tempFile(let url):
            uploadURL = url
        case .data(let data):
            let tmp = mountTempDir.appendingPathComponent("put_mem_\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            uploadURL = tmp
            createdTempForUpload = true
        case .empty:
            let tmp = mountTempDir.appendingPathComponent("put_empty_\(UUID().uuidString).tmp")
            FileManager.default.createFile(atPath: tmp.path, contents: Data())
            uploadURL = tmp
            createdTempForUpload = true
        }
        defer {
            if createdTempForUpload {
                try? FileManager.default.removeItem(at: uploadURL)
            }
        }

        try await session.uploadFile(from: uploadURL, to: remotePath, progress: nil)

        // Immediately invalidate caches for this file & parent directory
        invalidateCaches(for: remotePath)
        let uploadedSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int64) ?? 0
        let now = Date()
        let etag = Self.makeETag(size: uploadedSize, modifiedAt: now)

        return WebDAVHTTPResponse(
            statusCode: existed ? 204 : 201,
            headers: [
                ("ETag", etag),
                ("Content-Length", "0")
            ]
        )
    }

    // MARK: - MKCOL

    private func handleMkcol(_ request: WebDAVHTTPRequest, remotePath: String) async throws -> WebDAVHTTPResponse {
        if case .data(let data) = request.body, !data.isEmpty {
            return .text(415, "Unsupported Media Type")
        }
        if case .tempFile = request.body {
            return .text(415, "Unsupported Media Type")
        }

        if Self.isAppleMetadataPath(remotePath) {
            if virtualEntries[remotePath] != nil {
                return .text(405, "Already exists")
            }
            virtualEntries[remotePath] = VirtualEntry(
                path: remotePath,
                isDirectory: true,
                data: Data(),
                modifiedAt: Date()
            )
            return WebDAVHTTPResponse(statusCode: 201, headers: [("Content-Length", "0")])
        }

        if (try? await lookupRemoteFile(at: remotePath)) != nil {
            return .text(405, "Method Not Allowed")
        }

        let parent = remotePath.parentPath
        if parent != "/" && !Self.isAppleMetadataPath(parent) {
            guard let parentInfo = try? await lookupRemoteFile(at: parent), parentInfo.isDirectory else {
                return .text(409, "Conflict: parent collection does not exist")
            }
        }

        try await session.createDirectory(at: remotePath)
        invalidateCaches(for: remotePath)
        return WebDAVHTTPResponse(statusCode: 201, headers: [("Content-Length", "0")])
    }

    // MARK: - DELETE

    private func handleDelete(remotePath: String) async throws -> WebDAVHTTPResponse {
        guard remotePath != "/" else {
            return .text(403, "Cannot delete root")
        }

        if Self.isAppleMetadataPath(remotePath) {
            let prefix = remotePath + "/"
            var removedAny = false
            if let removed = virtualEntries.removeValue(forKey: remotePath) {
                virtualTotalBytes = max(0, virtualTotalBytes - removed.data.count)
                removedAny = true
            }
            let childKeys = virtualEntries.keys.filter { $0.hasPrefix(prefix) }
            for key in childKeys {
                if let removed = virtualEntries.removeValue(forKey: key) {
                    virtualTotalBytes = max(0, virtualTotalBytes - removed.data.count)
                }
                removedAny = true
            }
            return WebDAVHTTPResponse(statusCode: removedAny ? 204 : 404, headers: [("Content-Length", "0")])
        }

        guard let target = try await lookupRemoteFile(at: remotePath) else {
            return .text(404, "Not Found")
        }

        if target.isDirectory {
            try await session.deleteDirectory(at: remotePath)
        } else {
            try await session.deleteFile(at: remotePath)
        }

        invalidateCaches(for: remotePath, recursivePrefix: target.isDirectory)
        return WebDAVHTTPResponse(statusCode: 204, headers: [("Content-Length", "0")])
    }

    // MARK: - MOVE & COPY

    private func handleMoveOrCopy(
        _ request: WebDAVHTTPRequest,
        sourcePath: String,
        isMove: Bool
    ) async throws -> WebDAVHTTPResponse {
        guard let destHeader = request.header("Destination"),
              let destPath = resolveDestinationPath(fromHeader: destHeader) else {
            return .text(400, "Missing or invalid Destination header")
        }

        guard sourcePath != "/", destPath != "/" else {
            return .text(403, "Forbidden")
        }

        if sourcePath == destPath {
            return .text(403, "Source and destination are identical")
        }

        let overwrite = (request.header("Overwrite") ?? "T").uppercased() != "F"
        let srcIsVirtual = Self.isAppleMetadataPath(sourcePath)
        let dstIsVirtual = Self.isAppleMetadataPath(destPath)

        // Case 1: Both virtual (e.g. Finder managing ._ files or .TemporaryItems)
        if srcIsVirtual && dstIsVirtual {
            guard let srcEntry = virtualEntries[sourcePath] else {
                return .text(404, "Not Found")
            }
            let destExisted = virtualEntries[destPath] != nil
            if destExisted && !overwrite {
                return .text(412, "Precondition Failed")
            }
            storeVirtualFile(at: destPath, data: srcEntry.data, isDirectory: srcEntry.isDirectory)
            if isMove {
                if let removed = virtualEntries.removeValue(forKey: sourcePath) {
                    virtualTotalBytes = max(0, virtualTotalBytes - removed.data.count)
                }
            }
            return WebDAVHTTPResponse(statusCode: destExisted ? 204 : 201, headers: [("Content-Length", "0")])
        }

        // Case 2: Virtual -> Remote (macOS atomic safe-save moving from /.TemporaryItems/... to real file!)
        if srcIsVirtual && !dstIsVirtual {
            guard let srcEntry = virtualEntries[sourcePath], !srcEntry.isDirectory else {
                return .text(404, "Not Found")
            }
            let destExisted = (try? await lookupRemoteFile(at: destPath)) != nil
            if destExisted && !overwrite {
                return .text(412, "Precondition Failed")
            }
            let tmp = mountTempDir.appendingPathComponent("move_v2r_\(UUID().uuidString).tmp")
            try srcEntry.data.write(to: tmp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmp) }

            try await session.uploadFile(from: tmp, to: destPath, progress: nil)
            if isMove {
                if let removed = virtualEntries.removeValue(forKey: sourcePath) {
                    virtualTotalBytes = max(0, virtualTotalBytes - removed.data.count)
                }
            }
            invalidateCaches(for: destPath)
            return WebDAVHTTPResponse(statusCode: destExisted ? 204 : 201, headers: [("Content-Length", "0")])
        }

        // Case 3: Remote -> Virtual (e.g. moving a file into /.TemporaryItems or /.Trashes)
        if !srcIsVirtual && dstIsVirtual {
            guard let srcInfo = try await lookupRemoteFile(at: sourcePath) else {
                return .text(404, "Not Found")
            }
            let destExisted = virtualEntries[destPath] != nil
            if destExisted && !overwrite {
                return .text(412, "Precondition Failed")
            }
            if !srcInfo.isDirectory {
                let cached = try await fetchCachedFile(at: sourcePath, info: srcInfo)
                let data = (try? Data(contentsOf: cached.localURL)) ?? Data()
                storeVirtualFile(at: destPath, data: data)
            } else {
                storeVirtualFile(at: destPath, data: Data(), isDirectory: true)
            }
            if isMove {
                if srcInfo.isDirectory {
                    try await session.deleteDirectory(at: sourcePath)
                } else {
                    try await session.deleteFile(at: sourcePath)
                }
                invalidateCaches(for: sourcePath, recursivePrefix: srcInfo.isDirectory)
            }
            return WebDAVHTTPResponse(statusCode: destExisted ? 204 : 201, headers: [("Content-Length", "0")])
        }

        // Case 4: Remote -> Remote
        guard let srcInfo = try await lookupRemoteFile(at: sourcePath) else {
            return .text(404, "Not Found")
        }

        let dstParent = destPath.parentPath
        if dstParent != "/" {
            guard let parentInfo = try? await lookupRemoteFile(at: dstParent), parentInfo.isDirectory else {
                return .text(409, "Conflict: destination parent missing")
            }
        }

        let existingDest = try? await lookupRemoteFile(at: destPath)
        if existingDest != nil && !overwrite {
            return .text(412, "Precondition Failed")
        }

        if let existingDest {
            // FTP RNTO fails on many servers if target already exists; remove first when Overwrite=T
            if existingDest.isDirectory {
                try await session.deleteDirectory(at: destPath)
            } else {
                try await session.deleteFile(at: destPath)
            }
        }

        if isMove {
            try await session.rename(from: sourcePath, to: destPath)
            invalidateCaches(for: sourcePath, recursivePrefix: srcInfo.isDirectory)
            invalidateCaches(for: destPath, recursivePrefix: srcInfo.isDirectory)
        } else {
            if srcInfo.isDirectory {
                try await session.copyDirectory(from: sourcePath, to: destPath)
            } else {
                try await session.copyFile(from: sourcePath, to: destPath)
            }
            invalidateCaches(for: destPath, recursivePrefix: srcInfo.isDirectory)
        }

        return WebDAVHTTPResponse(
            statusCode: existingDest != nil ? 204 : 201,
            headers: [("Content-Length", "0")]
        )
    }

    // MARK: - LOCK & UNLOCK (WebDAV Class 2)

    private func handleLock(_ request: WebDAVHTTPRequest, remotePath: String) -> WebDAVHTTPResponse {
        let bodyStr = String(data: request.bodyData(), encoding: .utf8) ?? ""
        let isShared = bodyStr.contains("shared")
        let scopeTag = isShared ? "<D:shared/>" : "<D:exclusive/>"

        // Refresh lock if If: (<opaquelocktoken:...>) header is present
        let token: String
        if let ifHeader = request.header("If"),
           let existingToken = Self.extractLockToken(from: ifHeader),
           locks[existingToken] != nil {
            token = existingToken
        } else {
            token = "opaquelocktoken:\(UUID().uuidString.lowercased())"
            locks[token] = WebDAVLock(
                token: token,
                path: remotePath,
                isExclusive: !isShared,
                createdAt: Date()
            )
        }

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:prop xmlns:D="DAV:">
          <D:lockdiscovery>
            <D:activelock>
              <D:locktype><D:write/></D:locktype>
              <D:lockscope>\(scopeTag)</D:lockscope>
              <D:depth>0</D:depth>
              <D:owner><D:href>http://www.apple.com/webdav_fs/</D:href></D:owner>
              <D:timeout>Second-3600</D:timeout>
              <D:locktoken><D:href>\(token)</D:href></D:locktoken>
            </D:activelock>
          </D:lockdiscovery>
        </D:prop>
        """
        let data = Data(xml.utf8)
        return WebDAVHTTPResponse(
            statusCode: 200,
            headers: [
                ("Content-Type", "text/xml; charset=\"utf-8\""),
                ("Lock-Token", "<\(token)>"),
                ("Content-Length", "\(data.count)")
            ],
            body: .data(data)
        )
    }

    private func handleUnlock(_ request: WebDAVHTTPRequest) -> WebDAVHTTPResponse {
        if let lockTokenHeader = request.header("Lock-Token"),
           let token = Self.extractLockToken(from: lockTokenHeader) {
            locks.removeValue(forKey: token)
        }
        return WebDAVHTTPResponse(statusCode: 204, headers: [("Content-Length", "0")])
    }

    // MARK: - Remote Lookup, Directory Cache & Read Cache

    private func listDirectory(at path: String) async throws -> [RemoteFile] {
        let now = Date()
        if let cached = dirCache[path], now.timeIntervalSince(cached.fetchedAt) <= Self.dirCacheTTL {
            return cached.files
        }

        if let existingTask = inFlightListings[path] {
            return try await existingTask.value
        }

        let task = Task<[RemoteFile], Error> {
            try await self.session.listFiles(at: path)
        }
        inFlightListings[path] = task

        do {
            let files = try await task.value
            inFlightListings.removeValue(forKey: path)
            dirCache[path] = CachedDirectoryEntry(fetchedAt: Date(), files: files)
            return files
        } catch {
            inFlightListings.removeValue(forKey: path)
            throw error
        }
    }

    private func lookupRemoteFile(at path: String) async throws -> RemoteFile? {
        if path == "/" {
            return RemoteFile(
                name: "",
                path: "/",
                isDirectory: true,
                size: 0,
                permissions: "drwxr-xr-x",
                modificationDate: mountStartDate
            )
        }

        let parent = path.parentPath
        let targetName = (path as NSString).lastPathComponent

        // Negative short-circuit: if parent itself is already known from its parent cache
        // to be missing or a regular file, avoid an unnecessary remote LIST call.
        if parent != "/" {
            let grandParent = parent.parentPath
            let parentName = (parent as NSString).lastPathComponent
            if let gpCached = dirCache[grandParent],
               Date().timeIntervalSince(gpCached.fetchedAt) <= Self.dirCacheTTL {
                guard let parentEntry = gpCached.files.first(where: { $0.name == parentName }),
                      parentEntry.isDirectory else {
                    return nil
                }
            }
        }

        do {
            let siblings = try await listDirectory(at: parent)
            return siblings.first(where: { $0.name == targetName })
        } catch {
            // If parent listing is restricted or failed, fall back to direct stat if not a clear 404
            if Self.isNotFoundError(error) {
                return nil
            }
            do {
                return try await session.getFileInfo(at: path)
            } catch {
                if Self.isNotFoundError(error) {
                    return nil
                }
                throw error
            }
        }
    }

    private func validCachedFile(at path: String, signature: String) -> CachedReadFile? {
        let now = Date()
        guard var cached = readCache[path],
              cached.signature == signature,
              now.timeIntervalSince(cached.lastAccessed) <= Self.readCacheTTL,
              FileManager.default.fileExists(atPath: cached.localURL.path) else {
            return nil
        }
        cached.lastAccessed = now
        readCache[path] = cached
        return cached
    }

    private func promoteToReadCache(path: String, localURL: URL, size: Int64, signature: String) {
        if let old = readCache[path], old.localURL != localURL {
            try? FileManager.default.removeItem(at: old.localURL)
        }
        readCache[path] = CachedReadFile(
            path: path,
            localURL: localURL,
            size: size,
            signature: signature,
            lastAccessed: Date()
        )
        evictReadCacheIfNeeded()
    }

    private func fetchCachedFile(at path: String, info: RemoteFile) async throws -> CachedReadFile {
        let signature = "\(info.size)-\(Int(info.modificationDate?.timeIntervalSince1970 ?? -1))"
        let now = Date()

        if var cached = readCache[path],
           cached.signature == signature,
           now.timeIntervalSince(cached.lastAccessed) <= Self.readCacheTTL,
           FileManager.default.fileExists(atPath: cached.localURL.path) {
            cached.lastAccessed = now
            readCache[path] = cached
            return cached
        }

        if let existingTask = inFlightDownloads[path] {
            let result = try await existingTask.value
            if result.signature == signature && FileManager.default.fileExists(atPath: result.localURL.path) {
                return result
            }
        }

        let localURL = readCacheDir.appendingPathComponent("cache_\(UUID().uuidString).bin")
        let task = Task<CachedReadFile, Error> {
            try await self.session.downloadFile(from: path, to: localURL, progress: nil)
            let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
            let actualSize = (attrs?[.size] as? Int64) ?? info.size
            return CachedReadFile(
                path: path,
                localURL: localURL,
                size: actualSize,
                signature: signature,
                lastAccessed: Date()
            )
        }
        inFlightDownloads[path] = task

        do {
            let entry = try await task.value
            inFlightDownloads.removeValue(forKey: path)
            if let old = readCache[path], old.localURL != entry.localURL {
                try? FileManager.default.removeItem(at: old.localURL)
            }
            readCache[path] = entry
            evictReadCacheIfNeeded()
            return entry
        } catch {
            inFlightDownloads.removeValue(forKey: path)
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
    }

    private func evictReadCacheIfNeeded() {
        var totalSize = readCache.values.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > Self.maxReadCacheBytes else { return }

        let sortedByAge = readCache.values.sorted { $0.lastAccessed < $1.lastAccessed }
        for entry in sortedByAge {
            guard totalSize > Self.maxReadCacheBytes else { break }
            readCache.removeValue(forKey: entry.path)
            try? FileManager.default.removeItem(at: entry.localURL)
            totalSize -= entry.size
        }
    }

    private func invalidateCaches(for path: String, recursivePrefix: Bool = false) {
        let parent = path.parentPath
        dirCache.removeValue(forKey: parent)
        dirCache.removeValue(forKey: path)

        if recursivePrefix {
            let prefix = path == "/" ? "/" : path + "/"
            for key in dirCache.keys where key.hasPrefix(prefix) {
                dirCache.removeValue(forKey: key)
            }
            for key in readCache.keys where key == path || key.hasPrefix(prefix) {
                if let removed = readCache.removeValue(forKey: key) {
                    try? FileManager.default.removeItem(at: removed.localURL)
                }
            }
        } else if let removed = readCache.removeValue(forKey: path) {
            try? FileManager.default.removeItem(at: removed.localURL)
        }
    }

    private func storeVirtualFile(at path: String, data: Data, isDirectory: Bool = false) {
        if let existing = virtualEntries[path] {
            virtualTotalBytes = max(0, virtualTotalBytes - existing.data.count)
        }

        // Evict oldest virtual entries if total exceeds cap
        if virtualTotalBytes + data.count > Self.maxVirtualTotalBytes {
            let candidates = virtualEntries.values
                .filter { !$0.isDirectory }
                .sorted { $0.modifiedAt < $1.modifiedAt }
            for item in candidates {
                guard virtualTotalBytes + data.count > Self.maxVirtualTotalBytes else { break }
                virtualEntries.removeValue(forKey: item.path)
                virtualTotalBytes = max(0, virtualTotalBytes - item.data.count)
            }
        }

        virtualEntries[path] = VirtualEntry(
            path: path,
            isDirectory: isDirectory,
            data: data,
            modifiedAt: Date()
        )
        virtualTotalBytes += data.count
    }

    // MARK: - Path & Parsing Helpers

    private func resolveRemotePath(fromTarget rawTarget: String) -> String? {
        var rawPath = rawTarget
        if rawPath.lowercased().hasPrefix("http://") || rawPath.lowercased().hasPrefix("https://"),
           let components = URLComponents(string: rawPath) {
            rawPath = components.percentEncodedPath
        } else if let queryIndex = rawPath.firstIndex(of: "?") {
            rawPath = String(rawPath[..<queryIndex])
        }

        if rawPath == urlPrefix || rawPath == urlPrefix + "/" {
            return "/"
        }

        guard rawPath.hasPrefix(urlPrefix + "/") else {
            return nil
        }

        let suffix = String(rawPath.dropFirst(urlPrefix.count))
        guard let decoded = suffix.removingPercentEncoding else {
            return nil
        }
        return Self.sanitizeNormalizedPath(decoded)
    }

    private func resolveDestinationPath(fromHeader header: String) -> String? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           components.scheme != nil {
            return resolveRemotePath(fromTarget: components.percentEncodedPath)
        }
        return resolveRemotePath(fromTarget: trimmed)
    }

    private func buildHref(for remotePath: String, isDirectory: Bool) -> String {
        if remotePath == "/" {
            return urlPrefix + "/"
        }
        let encodedSegments = remotePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { seg -> String in
                String(seg).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(seg)
            }
            .joined(separator: "/")
        let suffix = isDirectory ? "/" : ""
        return "\(urlPrefix)/\(encodedSegments)\(suffix)"
    }

    nonisolated private static func sanitizeNormalizedPath(_ decoded: String) -> String {
        var stack: [String] = []
        for comp in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.append(String(comp))
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }

    nonisolated private static func isAppleMetadataPath(_ path: String) -> Bool {
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            let name = String(comp)
            if name.hasPrefix("._") || appleMetadataNames.contains(name) {
                return true
            }
        }
        return false
    }

    nonisolated private static func makeETag(size: Int64, modifiedAt: Date) -> String {
        "\"\(size)-\(Int64(modifiedAt.timeIntervalSince1970))\""
    }

    nonisolated private static func xmlEscape(_ str: String) -> String {
        var out = str
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }

    nonisolated private static func extractLockToken(from header: String) -> String? {
        guard let start = header.range(of: "opaquelocktoken:") else { return nil }
        let tail = header[start.lowerBound...]
        let end = tail.firstIndex(where: { $0 == ">" || $0 == ")" || $0.isWhitespace }) ?? tail.endIndex
        return String(tail[..<end])
    }

    nonisolated private static func shouldHonorRange(
        request: WebDAVHTTPRequest,
        etag: String,
        modDate: Date
    ) -> Bool {
        guard let ifRange = request.header("If-Range")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ifRange.isEmpty else {
            return true
        }
        if ifRange.hasPrefix("\"") || ifRange.hasPrefix("W/\"") {
            return ifRange == etag
        }
        if let date = WebDAVDateFormatters.parseHTTPDate(ifRange) {
            return Int(modDate.timeIntervalSince1970) <= Int(date.timeIntervalSince1970)
        }
        return true
    }

    nonisolated private static func parseByteRange(_ header: String, totalLength: Int64) -> (Int64, Int64)? {
        guard totalLength > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count).split(separator: ",", maxSplits: 1).first ?? ""
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)

        if startStr.isEmpty {
            guard let suffix = Int64(endStr), suffix > 0 else { return nil }
            let start = max(0, totalLength - suffix)
            return (start, totalLength - 1)
        }

        guard let start = Int64(startStr), start >= 0, start < totalLength else { return nil }
        if endStr.isEmpty {
            return (start, totalLength - 1)
        }
        guard let rawEnd = Int64(endStr), rawEnd >= start else { return nil }
        return (start, min(totalLength - 1, rawEnd))
    }

    nonisolated private static func isNotFoundError(_ error: Error) -> Bool {
        if case AppError.fileNotFound = error { return true }
        let desc = String(describing: error).lowercased()
        return desc.contains("not found") ||
            desc.contains("no such file") ||
            desc.contains("no_such_file") ||
            desc.contains("nosuchfile") ||
            desc.contains("550") ||
            desc.contains("enoent") ||
            desc.contains("does not exist") ||
            desc.contains("curl: (78)")
    }

    private func mapErrorToResponse(_ error: Error) -> WebDAVHTTPResponse {
        if Self.isNotFoundError(error) {
            return .text(404, "Not Found")
        }
        if case AppError.permissionDenied = error {
            return .text(403, "Permission Denied")
        }
        if case AppError.fileAlreadyExists = error {
            return .text(405, "Already Exists")
        }
        if case AppError.notConnected = error {
            return .text(503, "Remote session not connected")
        }
        if case AppError.connectionLost = error {
            return .text(503, "Remote connection lost")
        }
        if case AppError.connectionTimeout = error {
            return .text(504, "Remote connection timed out")
        }
        let desc = String(describing: error).lowercased()
        if desc.contains("permission denied") || desc.contains("530") {
            return .text(403, error.localizedDescription)
        }
        logWarning("[WebDAVBridge] Operation failed: \(error.localizedDescription)", category: .sftp)
        return .text(502, error.localizedDescription)
    }
}
