//
//  Socks5ProxyServer.swift
//  macSSH
//
//  Local SOCKS5 proxy server that routes traffic over an SSH connection
//  using SSH direct-tcpip channels (equivalent to ssh -D <port>).
//

import Foundation
import Network
import Citadel
import NIO
import NIOCore
import NIOFoundationCompat
import NIOSSH


/// Manages a local SOCKS5 proxy server forwarding connections through an SSH client.
/// Pure stream redirector: zero data caching, zero payload inspection, zero logging in the data hot path.
actor Socks5ProxyServer {
    private let port: Int
    private let allowLAN: Bool
    private let sshClient: SSHClient
    private var listener: NWListener?
    private var isRunning = false
    private var activeSessions: [UUID: Task<Void, Never>] = [:]

    /// Shared concurrent queue for handling all active client I/O streams efficiently
    private static let sessionQueue = DispatchQueue(
        label: "com.macssh.socks5.session-pool",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(port: Int, sshClient: SSHClient, allowLAN: Bool = false) {
        self.port = port
        self.sshClient = sshClient
        self.allowLAN = allowLAN
    }

    /// Starts listening for SOCKS5 connections on 127.0.0.1:<port> or 0.0.0.0:<port>
    func start() async throws {
        guard !isRunning else { return }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw AppError.connectionFailed("Invalid SOCKS5 port: \(port)")
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let newListener: NWListener
        if allowLAN {
            newListener = try NWListener(using: parameters, on: nwPort)
        } else {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            newListener = try NWListener(using: parameters)
        }

        let localPort = self.port
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var hasResumed = false

            newListener.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleListenerStateChange(state)
                }

                lock.lock()
                defer { lock.unlock() }

                switch state {
                case .ready:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: AppError.connectionFailed("SOCKS5 Proxy listener failed on port \(localPort): \(error.localizedDescription)"))
                    }
                case .cancelled:
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: AppError.connectionFailed("SOCKS5 Proxy listener cancelled on port \(localPort)"))
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { [weak self] in
                    await self?.handleNewConnection(connection)
                }
            }

            let listenerQueue = DispatchQueue(label: "com.macssh.socks5.listener.\(port)", qos: .userInitiated)
            newListener.start(queue: listenerQueue)
            self.listener = newListener
            self.isRunning = true
        }

        let bindDesc = allowLAN ? "0.0.0.0:\(port) (LAN + Localhost)" : "127.0.0.1:\(port) (Localhost only)"
        logInfo("SOCKS5 Proxy Server active on \(bindDesc) (stream mode: zero-copy/no-log)", category: .network)
    }

    /// Stops the SOCKS5 proxy server and cancels all active client sessions
    func stop() {
        guard isRunning else { return }
        isRunning = false

        listener?.cancel()
        listener = nil

        for (_, task) in activeSessions {
            task.cancel()
        }
        activeSessions.removeAll()

        logInfo("SOCKS5 Proxy Server stopped on port \(port)", category: .network)
    }

    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            break
        case .failed(let error):
            logError("SOCKS5 Proxy listener failed on port \(port): \(error.localizedDescription)", category: .network)
            stop()
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        guard isRunning else {
            connection.cancel()
            return
        }

        let sessionId = UUID()
        let sessionTask = Task { [weak self, sshClient] in
            guard let self = self else { return }
            await self.runSocksSession(connection: connection, sshClient: sshClient)
            await self.removeSession(id: sessionId)
        }

        activeSessions[sessionId] = sessionTask
    }

    private func removeSession(id: UUID) {
        activeSessions.removeValue(forKey: id)
    }

    // MARK: - SOCKS5 Handshake & Transparent Stream Forwarding

    private func runSocksSession(connection: NWConnection, sshClient: SSHClient) async {
        connection.start(queue: Self.sessionQueue)

        let coordinator = SocksSessionCoordinator(connection: connection)

        do {
            // 1. Handshake: Method negotiation (RFC 1928 Section 3)
            let greetingData: Data
            do {
                greetingData = try await receiveExactBytes(connection: connection, count: 2)
            } catch {
                coordinator.terminate(closingChannel: false)
                return
            }

            guard greetingData.count >= 2, greetingData[0] == 0x05 else {
                coordinator.terminate(closingChannel: false)
                return
            }

            let numMethods = Int(greetingData[1])
            guard numMethods > 0 else {
                _ = try? await sendData(connection: connection, data: Data([0x05, 0xFF]))
                coordinator.terminate(closingChannel: false)
                return
            }

            let methodsData: Data
            do {
                methodsData = try await receiveExactBytes(connection: connection, count: numMethods)
            } catch {
                coordinator.terminate(closingChannel: false)
                return
            }

            // Must support 0x00 (NO AUTHENTICATION REQUIRED)
            guard methodsData.contains(0x00) else {
                _ = try? await sendData(connection: connection, data: Data([0x05, 0xFF]))
                coordinator.terminate(closingChannel: false)
                return
            }

            // Reply: Version 5, Method 0 (No Auth)
            do {
                try await sendData(connection: connection, data: Data([0x05, 0x00]))
            } catch {
                coordinator.terminate(closingChannel: false)
                return
            }

            // 2. Request Details (RFC 1928 Section 4)
            let reqHeader: Data
            do {
                reqHeader = try await receiveExactBytes(connection: connection, count: 4)
            } catch {
                coordinator.terminate(closingChannel: false)
                return
            }

            guard reqHeader.count == 4, reqHeader[0] == 0x05 else {
                coordinator.terminate(closingChannel: false)
                return
            }

            let cmd = reqHeader[1]
            guard cmd == 0x01 else {
                // CMD 0x01 = CONNECT. (BIND 0x02 and UDP 0x03 not supported)
                let resp = Data([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]) // Command not supported
                _ = try? await sendData(connection: connection, data: resp)
                coordinator.terminate(closingChannel: false)
                return
            }

            let atyp = reqHeader[3]
            var targetHost = ""

            do {
                switch atyp {
                case 0x01: // IPv4 (4 bytes)
                    let ipBytes = try await receiveExactBytes(connection: connection, count: 4)
                    targetHost = ipBytes.map { String($0) }.joined(separator: ".")
                case 0x03: // Domain Name (1 byte length + domain string)
                    let lenData = try await receiveExactBytes(connection: connection, count: 1)
                    let domainLen = Int(lenData[0])
                    guard domainLen > 0 else { throw AppError.connectionFailed("Empty domain") }
                    let domainBytes = try await receiveExactBytes(connection: connection, count: domainLen)
                    guard let domainStr = String(data: domainBytes, encoding: .utf8), !domainStr.isEmpty else {
                        throw AppError.connectionFailed("Invalid domain string")
                    }
                    targetHost = domainStr
                case 0x04: // IPv6 (16 bytes)
                    let ip6Bytes = try await receiveExactBytes(connection: connection, count: 16)
                    var hexParts: [String] = []
                    for i in stride(from: 0, to: 16, by: 2) {
                        let val = (UInt16(ip6Bytes[i]) << 8) | UInt16(ip6Bytes[i + 1])
                        hexParts.append(String(format: "%x", val))
                    }
                    targetHost = hexParts.joined(separator: ":")
                default:
                    let resp = Data([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]) // Address type not supported
                    _ = try? await sendData(connection: connection, data: resp)
                    coordinator.terminate(closingChannel: false)
                    return
                }
            } catch {
                let resp = Data([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                _ = try? await sendData(connection: connection, data: resp)
                coordinator.terminate(closingChannel: false)
                return
            }

            // Port (2 bytes big endian)
            let targetPort: Int
            do {
                let portBytes = try await receiveExactBytes(connection: connection, count: 2)
                targetPort = (Int(portBytes[0]) << 8) | Int(portBytes[1])
            } catch {
                coordinator.terminate(closingChannel: false)
                return
            }

            guard targetPort > 0 && targetPort <= 65535 else {
                let resp = Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]) // General SOCKS failure
                _ = try? await sendData(connection: connection, data: resp)
                coordinator.terminate(closingChannel: false)
                return
            }

            // 3. Open Direct-TCPIP Channel via Citadel SSH Client
            let originator: SocketAddress
            do {
                originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            } catch {
                let resp = Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                _ = try? await sendData(connection: connection, data: resp)
                coordinator.terminate(closingChannel: false)
                return
            }

            let directTCPIP = SSHChannelType.DirectTCPIP(
                targetHost: targetHost,
                targetPort: targetPort,
                originatorAddress: originator
            )

            let channel: Channel
            do {
                channel = try await sshClient.createDirectTCPIPChannel(using: directTCPIP) { channel in
                    let bridgeHandler = Socks5InboundHandler(coordinator: coordinator)
                    return channel.pipeline.addHandler(bridgeHandler)
                }
            } catch {
                // Remote side refused or host unreachable — send RFC 1928 0x05 (Connection Refused)
                let resp = Data([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                _ = try? await sendData(connection: connection, data: resp)
                coordinator.terminate(closingChannel: false)
                return
            }

            coordinator.setChannel(channel)

            // Reply: Succeeded (0x00) with bound address 0.0.0.0:0
            do {
                let successResp = Data([0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
                try await sendData(connection: connection, data: successResp)
            } catch {
                coordinator.terminate(closingChannel: true)
                return
            }

            // 4. Pipe local client -> SSH Channel (Hot raw stream path)
            await pipeClientToSSHChannel(connection: connection, channel: channel, coordinator: coordinator)

        } catch {
            coordinator.terminate(closingChannel: true)
        }
    }

    // MARK: - Local to SSH Pure Stream Pipe

    private func pipeClientToSSHChannel(
        connection: NWConnection,
        channel: Channel,
        coordinator: SocksSessionCoordinator
    ) async {
        while !Task.isCancelled && !coordinator.isTerminated {
            do {
                let data = try await receiveSomeData(connection: connection)
                guard !data.isEmpty else {
                    // Local client closed connection (EOF)
                    coordinator.terminate(closingChannel: true)
                    break
                }

                guard channel.isActive && !coordinator.isTerminated else {
                    coordinator.terminate(closingChannel: false)
                    break
                }

                var buffer = channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)

                do {
                    try await channel.writeAndFlush(buffer)
                } catch {
                    // Channel pipe broken or closed by remote
                    coordinator.terminate(closingChannel: false)
                    break
                }
            } catch {
                // Connection read error or cancelled
                coordinator.terminate(closingChannel: true)
                break
            }
        }
    }

    // MARK: - Raw Network Helpers (Thread-Safe Protected Continuations)

    private func receiveExactBytes(connection: NWConnection, count: Int) async throws -> Data {
        var accumulated = Data()
        accumulated.reserveCapacity(count)
        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let lock = NSLock()
                var hasResumed = false

                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true

                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let content = content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(throwing: AppError.connectionClosed)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            if chunk.isEmpty {
                throw AppError.connectionClosed
            }
            accumulated.append(chunk)
        }
        return accumulated
    }

    private func receiveSomeData(connection: NWConnection) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: error)
                } else if let content = content {
                    continuation.resume(returning: content)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func sendData(connection: NWConnection, data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            connection.send(content: data, completion: .contentProcessed { error in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

// MARK: - Session Coordinator (Thread-Safe Lifecycle Management)

/// Coordinates the synchronized teardown between NWConnection and NIO Channel
/// ensuring idempotent, safe cleanup without double-close or precondition crashes.
private final class SocksSessionCoordinator: @unchecked Sendable {
    let connection: NWConnection
    private weak var channel: Channel?
    private let lock = NSLock()
    private var _isTerminated = false

    var isTerminated: Bool {
        lock.withLock { _isTerminated }
    }

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setChannel(_ channel: Channel) {
        lock.withLock {
            self.channel = channel
        }
    }

    func terminate(closingChannel: Bool = true) {
        var chan: Channel?
        lock.withLock {
            guard !_isTerminated else { return }
            _isTerminated = true
            chan = self.channel
        }

        connection.cancel()

        if closingChannel, let channel = chan {
            // Safe full-close on the correct event loop.
            // Do NOT use half-close (.output) — it can trigger NIO/NIOSSH precondition
            // failures during cascading teardown when the SSH transport dies unexpectedly.
            channel.eventLoop.execute {
                guard channel.isActive else { return }
                channel.close(mode: .all, promise: nil)
            }
        }
    }
}

// MARK: - Inbound Bridge Handler (SSH -> NWConnection)

/// Pure raw stream redirector from SSH channel to NWConnection.
/// Zero caching, zero logging, zero packet inspection.
private final class Socks5InboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let coordinator: SocksSessionCoordinator

    init(coordinator: SocksSessionCoordinator) {
        self.coordinator = coordinator
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !coordinator.isTerminated, context.channel.isActive else { return }

        let buffer = unwrapInboundIn(data)
        let bytes = Data(buffer.readableBytesView)

        guard !bytes.isEmpty else { return }

        coordinator.connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.coordinator.terminate(closingChannel: false)
            }
        })
    }

    func channelInactive(context: ChannelHandlerContext) {
        coordinator.terminate(closingChannel: false)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        coordinator.terminate(closingChannel: false)
        if context.channel.isActive {
            context.close(promise: nil)
        }
    }
}

// MARK: - Network Utilities
enum NetworkUtils {
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) &&
               (flags & IFF_LOOPBACK) == 0 &&
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
