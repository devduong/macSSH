//
//  WebDAVHTTPServer.swift
//  macSSH
//
//  Lightweight streaming HTTP/1.1 server built on SwiftNIO for local loopback WebDAV bridging.
//  Supports Keep-Alive, Expect: 100-continue, Transfer-Encoding: chunked,
//  disk-backed PUT uploads, and ranged file streaming responses.
//

import Foundation
import NIO
import NIOCore
import NIOFoundationCompat

nonisolated struct WebDAVHTTPRequest: Sendable {
    enum Body: Sendable {
        case empty
        case data(Data)
        case tempFile(URL)
    }

    let method: String
    let target: String
    let httpVersion: String
    let headers: [String: String]
    let body: Body

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    func bodyData(maxBytes: Int = 2 * 1024 * 1024) -> Data {
        switch body {
        case .empty:
            return Data()
        case .data(let data):
            return data
        case .tempFile(let url):
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int,
                  size <= maxBytes,
                  let data = try? Data(contentsOf: url) else {
                return Data()
            }
            return data
        }
    }

    func cleanupBodyTempFile() {
        if case .tempFile(let url) = body {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

nonisolated struct WebDAVHTTPResponse: Sendable {
    typealias StreamProducer = @Sendable (@escaping @Sendable (Data) async throws -> Void) async throws -> Void

    enum Body: Sendable {
        case empty
        case data(Data)
        case fileRange(url: URL, offset: Int64, length: Int64)
        case stream(length: Int64, producer: StreamProducer)
    }

    let statusCode: Int
    let reasonPhrase: String
    var headers: [(String, String)]
    let body: Body
    let completionCleanupURL: URL?

    init(
        statusCode: Int,
        reasonPhrase: String? = nil,
        headers: [(String, String)] = [],
        body: Body = .empty,
        completionCleanupURL: URL? = nil
    ) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase ?? Self.defaultReasonPhrase(for: statusCode)
        self.headers = headers
        self.body = body
        self.completionCleanupURL = completionCleanupURL
    }

    static func text(_ statusCode: Int, _ message: String = "") -> WebDAVHTTPResponse {
        let data = Data(message.utf8)
        return WebDAVHTTPResponse(
            statusCode: statusCode,
            headers: [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Content-Length", "\(data.count)")
            ],
            body: data.isEmpty ? .empty : .data(data)
        )
    }

    static func xml(_ statusCode: Int, _ xmlString: String) -> WebDAVHTTPResponse {
        let data = Data(xmlString.utf8)
        return WebDAVHTTPResponse(
            statusCode: statusCode,
            headers: [
                ("Content-Type", "application/xml; charset=\"utf-8\""),
                ("Content-Length", "\(data.count)")
            ],
            body: .data(data)
        )
    }

    private static func defaultReasonPhrase(for code: Int) -> String {
        switch code {
        case 100: return "Continue"
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 207: return "Multi-Status"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 423: return "Locked"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

nonisolated final class WebDAVHTTPServer: @unchecked Sendable {
    typealias RequestHandler = @Sendable (WebDAVHTTPRequest) async -> WebDAVHTTPResponse

    private let tempDirectory: URL
    private let handler: RequestHandler
    private let lock = NSLock()

    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private(set) var listeningPort: Int = 0

    init(tempDirectory: URL, handler: @escaping RequestHandler) {
        self.tempDirectory = tempDirectory
        self.handler = handler
    }

    deinit {
        stopSync()
    }

    func start() async throws -> Int {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let tempDir = self.tempDirectory
        let requestHandler = self.handler

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(
                    HTTPServerChannelHandler(tempDirectory: tempDir, requestHandler: requestHandler)
                )
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            let port = channel.localAddress?.port ?? 0
            setRunningState(channel: channel, group: eventLoopGroup, port: port)
            return port
        } catch {
            try? await eventLoopGroup.shutdownGracefully()
            throw error
        }
    }

    func stop() async {
        let (channel, eventLoopGroup) = takeRunningState()

        if let channel {
            try? await channel.close().get()
        }
        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func stopSync() {
        let (channel, eventLoopGroup) = takeRunningState()

        if let channel {
            try? channel.close().wait()
        }
        if let eventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func setRunningState(channel: Channel, group: MultiThreadedEventLoopGroup, port: Int) {
        lock.lock()
        self.group = group
        self.serverChannel = channel
        self.listeningPort = port
        lock.unlock()
    }

    private func takeRunningState() -> (Channel?, MultiThreadedEventLoopGroup?) {
        lock.lock()
        defer { lock.unlock() }
        let channel = serverChannel
        let eventLoopGroup = group
        serverChannel = nil
        group = nil
        listeningPort = 0
        return (channel, eventLoopGroup)
    }
}

// MARK: - HTTP/1.1 Streaming Channel Handler

nonisolated private final class HTTPServerChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private struct ParsedHead {
        let method: String
        let target: String
        let httpVersion: String
        let headers: [String: String]
        let isChunked: Bool
        let contentLength: Int64
        let expectContinue: Bool
        let shouldClose: Bool
    }

    private final class BodySink {
        let tempURL: URL?
        let fileHandle: FileHandle?
        var memoryBuffer = Data()
        private(set) var bytesWritten: Int64 = 0
        private let maxMemoryBytes = 2 * 1024 * 1024

        init(useTempFile: Bool, tempDirectory: URL) throws {
            if useTempFile {
                let url = tempDirectory.appendingPathComponent("put_\(UUID().uuidString).tmp")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)
                self.tempURL = url
                self.fileHandle = handle
            } else {
                self.tempURL = nil
                self.fileHandle = nil
            }
        }

        func append(_ slice: ArraySlice<UInt8>) throws {
            guard !slice.isEmpty else { return }
            if let fileHandle {
                try fileHandle.write(contentsOf: slice)
                bytesWritten += Int64(slice.count)
            } else {
                if memoryBuffer.count + slice.count > maxMemoryBytes {
                    throw NSError(domain: "WebDAVHTTP", code: 413, userInfo: nil)
                }
                memoryBuffer.append(contentsOf: slice)
                bytesWritten += Int64(slice.count)
            }
        }

        func append(_ data: Data) throws {
            guard !data.isEmpty else { return }
            if let fileHandle {
                try fileHandle.write(contentsOf: data)
                bytesWritten += Int64(data.count)
            } else {
                if memoryBuffer.count + data.count > maxMemoryBytes {
                    throw NSError(domain: "WebDAVHTTP", code: 413, userInfo: nil)
                }
                memoryBuffer.append(data)
                bytesWritten += Int64(data.count)
            }
        }

        func finalize() -> WebDAVHTTPRequest.Body {
            if let fileHandle {
                try? fileHandle.close()
            }
            if let tempURL {
                return .tempFile(tempURL)
            }
            return memoryBuffer.isEmpty ? .empty : .data(memoryBuffer)
        }

        func abortCleanup() {
            if let fileHandle {
                try? fileHandle.close()
            }
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    private enum ParseState {
        case readingHead
        case readingFixedBody(head: ParsedHead, remaining: Int64, sink: BodySink)
        case readingChunkSize(head: ParsedHead, sink: BodySink)
        case readingChunkData(head: ParsedHead, remaining: Int64, sink: BodySink)
        case readingChunkCRLF(head: ParsedHead, sink: BodySink)
        case readingChunkTrailer(head: ParsedHead, sink: BodySink)
    }

    private let tempDirectory: URL
    private let requestHandler: WebDAVHTTPServer.RequestHandler
    private var buffer = ByteBuffer()
    private var state: ParseState = .readingHead
    private var isProcessingRequest = false
    private var isClosed = false
    private var activeRequestTask: Task<Void, Never>?

    private static let maxHeaderBytes = 64 * 1024

    init(tempDirectory: URL, requestHandler: @escaping WebDAVHTTPServer.RequestHandler) {
        self.tempDirectory = tempDirectory
        self.requestHandler = requestHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)
        buffer.writeBuffer(&inbound)

        if !isProcessingRequest {
            processBufferedData(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        isClosed = true
        activeRequestTask?.cancel()
        activeRequestTask = nil
        abortCurrentSink()
        buffer.clear()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        isClosed = true
        activeRequestTask?.cancel()
        activeRequestTask = nil
        abortCurrentSink()
        buffer.clear()
        context.close(promise: nil)
    }

    private func abortCurrentSink() {
        switch state {
        case .readingFixedBody(_, _, let sink),
             .readingChunkSize(_, let sink),
             .readingChunkData(_, _, let sink),
             .readingChunkCRLF(_, let sink),
             .readingChunkTrailer(_, let sink):
            sink.abortCleanup()
        case .readingHead:
            break
        }
        state = .readingHead
    }

    private func processBufferedData(context: ChannelHandlerContext) {
        while !isClosed && !isProcessingRequest {
            switch state {
            case .readingHead:
                guard let headerEndIndex = findHeaderDelimiter(in: buffer) else {
                    if buffer.readableBytes > Self.maxHeaderBytes {
                        sendImmediateErrorAndClose(context: context, status: 400, message: "Header too large")
                    }
                    return
                }

                let headerLength = headerEndIndex - buffer.readerIndex
                guard let headerString = buffer.readString(length: headerLength),
                      let head = parseRequestHead(headerString) else {
                    sendImmediateErrorAndClose(context: context, status: 400, message: "Malformed HTTP request")
                    return
                }
                buffer.moveReaderIndex(forwardBy: 4) // Skip "\r\n\r\n"

                if head.expectContinue {
                    var continueBuf = context.channel.allocator.buffer(capacity: 32)
                    continueBuf.writeString("HTTP/1.1 100 Continue\r\n\r\n")
                    context.writeAndFlush(wrapOutboundOut(continueBuf), promise: nil)
                }

                if head.isChunked {
                    do {
                        let sink = try BodySink(useTempFile: head.method == "PUT", tempDirectory: tempDirectory)
                        state = .readingChunkSize(head: head, sink: sink)
                    } catch {
                        sendImmediateErrorAndClose(context: context, status: 500, message: "Staging error")
                        return
                    }
                } else if head.contentLength > 0 {
                    do {
                        let sink = try BodySink(useTempFile: head.method == "PUT", tempDirectory: tempDirectory)
                        state = .readingFixedBody(head: head, remaining: head.contentLength, sink: sink)
                    } catch {
                        sendImmediateErrorAndClose(context: context, status: 500, message: "Staging error")
                        return
                    }
                } else {
                    let body: WebDAVHTTPRequest.Body
                    if head.method == "PUT" {
                        // Create empty temp file so PUT 0 bytes works uniformly
                        if let sink = try? BodySink(useTempFile: true, tempDirectory: tempDirectory) {
                            body = sink.finalize()
                        } else {
                            body = .empty
                        }
                    } else {
                        body = .empty
                    }
                    dispatchRequest(context: context, head: head, body: body)
                    return
                }

            case .readingFixedBody(let head, var remaining, let sink):
                let available = buffer.readableBytes
                guard available > 0 else { return }

                let toTake = Int(min(Int64(available), remaining))
                guard let bytes = buffer.readBytes(length: toTake) else { return }
                do {
                    try sink.append(Data(bytes))
                } catch {
                    sink.abortCleanup()
                    sendImmediateErrorAndClose(context: context, status: 413, message: "Payload Too Large")
                    return
                }
                remaining -= Int64(toTake)

                if remaining == 0 {
                    state = .readingHead
                    let body = sink.finalize()
                    dispatchRequest(context: context, head: head, body: body)
                    return
                } else {
                    state = .readingFixedBody(head: head, remaining: remaining, sink: sink)
                    return
                }

            case .readingChunkSize(let head, let sink):
                guard let lineEndIndex = findCRLF(in: buffer) else { return }
                let lineLen = lineEndIndex - buffer.readerIndex
                guard let sizeLine = buffer.readString(length: lineLen) else {
                    sink.abortCleanup()
                    sendImmediateErrorAndClose(context: context, status: 400, message: "Invalid chunk size")
                    return
                }
                buffer.moveReaderIndex(forwardBy: 2)

                let hexToken = sizeLine.split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let chunkSize = Int64(hexToken, radix: 16), chunkSize >= 0 else {
                    sink.abortCleanup()
                    sendImmediateErrorAndClose(context: context, status: 400, message: "Malformed chunk size")
                    return
                }

                if chunkSize == 0 {
                    state = .readingChunkTrailer(head: head, sink: sink)
                } else {
                    state = .readingChunkData(head: head, remaining: chunkSize, sink: sink)
                }

            case .readingChunkData(let head, var remaining, let sink):
                let available = buffer.readableBytes
                guard available > 0 else { return }

                let toTake = Int(min(Int64(available), remaining))
                guard let bytes = buffer.readBytes(length: toTake) else { return }
                do {
                    try sink.append(Data(bytes))
                } catch {
                    sink.abortCleanup()
                    sendImmediateErrorAndClose(context: context, status: 413, message: "Payload Too Large")
                    return
                }
                remaining -= Int64(toTake)

                if remaining == 0 {
                    state = .readingChunkCRLF(head: head, sink: sink)
                } else {
                    state = .readingChunkData(head: head, remaining: remaining, sink: sink)
                    return
                }

            case .readingChunkCRLF(let head, let sink):
                guard buffer.readableBytes >= 2 else { return }
                buffer.moveReaderIndex(forwardBy: 2)
                state = .readingChunkSize(head: head, sink: sink)

            case .readingChunkTrailer(let head, let sink):
                guard let lineEndIndex = findCRLF(in: buffer) else { return }
                let lineLen = lineEndIndex - buffer.readerIndex
                let line = buffer.readString(length: lineLen) ?? ""
                buffer.moveReaderIndex(forwardBy: 2)

                if line.isEmpty {
                    state = .readingHead
                    let body = sink.finalize()
                    dispatchRequest(context: context, head: head, body: body)
                    return
                }
            }
        }
    }

    private func dispatchRequest(
        context: ChannelHandlerContext,
        head: ParsedHead,
        body: WebDAVHTTPRequest.Body
    ) {
        isProcessingRequest = true
        let channel = context.channel
        _ = channel.setOption(ChannelOptions.autoRead, value: false)

        if buffer.readableBytes == 0 {
            buffer.discardReadBytes()
        }

        let request = WebDAVHTTPRequest(
            method: head.method,
            target: head.target,
            httpVersion: head.httpVersion,
            headers: head.headers,
            body: body
        )
        let shouldClose = head.shouldClose
        let handler = self.requestHandler

        activeRequestTask = Task.detached(priority: .userInitiated) { [weak self] in
            defer { request.cleanupBodyTempFile() }
            let response = await handler(request)
            let completedCleanly = await Self.writeResponse(response, to: channel, closeAfterWrite: shouldClose)

            if shouldClose || !completedCleanly {
                try? await channel.close().get()
            } else {
                channel.eventLoop.execute {
                    guard let self, !self.isClosed else { return }
                    self.activeRequestTask = nil
                    self.isProcessingRequest = false
                    _ = channel.setOption(ChannelOptions.autoRead, value: true)
                    // Resume buffered pipelined data if any
                    if self.buffer.readableBytes > 0,
                       let ctx = try? channel.pipeline.syncOperations.context(handler: self) {
                        self.processBufferedData(context: ctx)
                    }
                }
            }
        }
    }

    private static func writeResponse(
        _ response: WebDAVHTTPResponse,
        to channel: Channel,
        closeAfterWrite: Bool
    ) async -> Bool {
        defer {
            if let cleanupURL = response.completionCleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        guard channel.isActive else { return false }

        var headerLines = "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)\r\n"
        var hasConnection = false
        var hasContentLength = false
        var hasServer = false

        for (name, value) in response.headers {
            let lower = name.lowercased()
            if lower == "connection" { hasConnection = true }
            if lower == "content-length" { hasContentLength = true }
            if lower == "server" { hasServer = true }
            headerLines += "\(name): \(value)\r\n"
        }

        if !hasServer {
            headerLines += "Server: macSSH-WebDAV/1.0\r\n"
        }
        if !hasContentLength {
            switch response.body {
            case .empty:
                headerLines += "Content-Length: 0\r\n"
            case .data(let data):
                headerLines += "Content-Length: \(data.count)\r\n"
            case .fileRange(_, _, let length):
                headerLines += "Content-Length: \(length)\r\n"
            case .stream(let length, _):
                headerLines += "Content-Length: \(length)\r\n"
            }
        }
        if !hasConnection {
            headerLines += closeAfterWrite ? "Connection: close\r\n" : "Connection: keep-alive\r\n"
        }
        headerLines += "\r\n"

        var headBuffer = channel.allocator.buffer(capacity: headerLines.utf8.count)
        headBuffer.writeString(headerLines)

        do {
            switch response.body {
            case .empty:
                try await channel.writeAndFlush(headBuffer).get()
                return true

            case .data(let data):
                if !data.isEmpty {
                    headBuffer.writeBytes(data)
                }
                try await channel.writeAndFlush(headBuffer).get()
                return true

            case .fileRange(let url, let offset, let length):
                try await channel.writeAndFlush(headBuffer).get()
                guard length > 0 else { return true }

                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(max(0, offset)))

                var remaining = length
                let chunkSize = 256 * 1024
                while remaining > 0 && channel.isActive {
                    try Task.checkCancellation()
                    let toRead = Int(min(Int64(chunkSize), remaining))
                    guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else {
                        break
                    }
                    var chunkBuf = channel.allocator.buffer(capacity: chunk.count)
                    chunkBuf.writeBytes(chunk)
                    try await channel.writeAndFlush(chunkBuf).get()
                    remaining -= Int64(chunk.count)
                }
                return remaining == 0

            case .stream(let expectedLength, let producer):
                try await channel.writeAndFlush(headBuffer).get()
                guard expectedLength > 0 else { return true }

                final class RemainingCounter: @unchecked Sendable {
                    private let lock = NSLock()
                    var remaining: Int64
                    init(_ initial: Int64) { self.remaining = initial }
                    func consume(_ count: Int64) -> Int64 {
                        lock.lock()
                        defer { lock.unlock() }
                        let take = min(remaining, count)
                        remaining -= take
                        return take
                    }
                    func value() -> Int64 {
                        lock.lock()
                        defer { lock.unlock() }
                        return remaining
                    }
                }

                let counter = RemainingCounter(expectedLength)
                try await producer { chunk in
                    try Task.checkCancellation()
                    guard channel.isActive else { throw CancellationError() }
                    guard !chunk.isEmpty else { return }
                    let toSend = counter.consume(Int64(chunk.count))
                    guard toSend > 0 else { throw CancellationError() }

                    var chunkBuf = channel.allocator.buffer(capacity: Int(toSend))
                    if toSend == Int64(chunk.count) {
                        chunkBuf.writeBytes(chunk)
                    } else {
                        chunkBuf.writeBytes(chunk.prefix(Int(toSend)))
                    }
                    try await channel.writeAndFlush(chunkBuf).get()
                }
                return counter.value() == 0
            }
        } catch {
            // Client closed connection or stream aborted mid-transfer
            return false
        }
    }

    private func sendImmediateErrorAndClose(context: ChannelHandlerContext, status: Int, message: String) {
        isClosed = true
        let bodyData = Data(message.utf8)
        let header = "HTTP/1.1 \(status) Error\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var buf = context.channel.allocator.buffer(capacity: header.utf8.count + bodyData.count)
        buf.writeString(header)
        buf.writeBytes(bodyData)
        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(buf)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }

    private func findHeaderDelimiter(in buffer: ByteBuffer) -> Int? {
        let view = buffer.readableBytesView
        guard view.count >= 4 else { return nil }
        let start = view.startIndex
        let end = view.endIndex - 3
        var idx = start
        while idx < end {
            if view[idx] == 13 && view[idx + 1] == 10 && view[idx + 2] == 13 && view[idx + 3] == 10 {
                let offset = view.distance(from: start, to: idx)
                return buffer.readerIndex + offset
            }
            idx = view.index(after: idx)
        }
        return nil
    }

    private func findCRLF(in buffer: ByteBuffer) -> Int? {
        let view = buffer.readableBytesView
        guard view.count >= 2 else { return nil }
        let start = view.startIndex
        let end = view.endIndex - 1
        var idx = start
        while idx < end {
            if view[idx] == 13 && view[idx + 1] == 10 {
                let offset = view.distance(from: start, to: idx)
                return buffer.readerIndex + offset
            }
            idx = view.index(after: idx)
        }
        return nil
    }

    private func parseRequestHead(_ raw: String) -> ParsedHead? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let version = String(parts[2]).uppercased()

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let existing = headers[key] {
                headers[key] = "\(existing), \(val)"
            } else {
                headers[key] = val
            }
        }

        let transferEncoding = headers["transfer-encoding"]?.lowercased() ?? ""
        let isChunked = transferEncoding.contains("chunked")
        let contentLength = Int64(headers["content-length"] ?? "0") ?? 0
        let expectContinue = headers["expect"]?.lowercased().contains("100-continue") ?? false
        let connHeader = headers["connection"]?.lowercased() ?? ""
        let shouldClose = connHeader.contains("close") || (version == "HTTP/1.0" && !connHeader.contains("keep-alive"))

        return ParsedHead(
            method: method,
            target: target,
            httpVersion: version,
            headers: headers,
            isChunked: isChunked,
            contentLength: contentLength,
            expectContinue: expectContinue,
            shouldClose: shouldClose
        )
    }
}
