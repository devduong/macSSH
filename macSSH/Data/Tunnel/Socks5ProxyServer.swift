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


/// Manages a local SOCKS5 proxy server forwarding connections through an SSH client
actor Socks5ProxyServer {
    private let port: Int
    private let allowLAN: Bool
    private let sshClient: SSHClient
    private var listener: NWListener?
    private var isRunning = false
    private var activeSessions: [UUID: Task<Void, Never>] = [:]

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

            let queue = DispatchQueue(label: "com.macssh.socks5.\(port)", qos: .userInitiated)
            newListener.start(queue: queue)
            self.listener = newListener
            self.isRunning = true
        }

        let bindDesc = allowLAN ? "0.0.0.0:\(port) (LAN + Localhost)" : "127.0.0.1:\(port) (Localhost only)"
        logInfo("SOCKS5 Proxy Server successfully listening on \(bindDesc)", category: .network)
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
            logInfo("SOCKS5 Proxy listener is ready on port \(port)", category: .network)
        case .failed(let error):
            logError("SOCKS5 Proxy listener failed on port \(port): \(error)", category: .network)
            stop()
        case .cancelled:
            logInfo("SOCKS5 Proxy listener cancelled on port \(port)", category: .network)
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
            await self.runSocksSession(id: sessionId, connection: connection, sshClient: sshClient)
            await self.removeSession(id: sessionId)
        }

        activeSessions[sessionId] = sessionTask
    }

    private func removeSession(id: UUID) {
        activeSessions.removeValue(forKey: id)
    }

    // MARK: - SOCKS5 Protocol Handling

    private func runSocksSession(id: UUID, connection: NWConnection, sshClient: SSHClient) async {
        let queue = DispatchQueue(label: "com.macssh.socks5.session.\(id)")
        connection.start(queue: queue)

        do {
            // 1. Handshake: Method negotiation (RFC 1928 Section 3)
            // Client greeting: [VER, NMETHODS, METHODS...]
            let greetingData = try await receiveExactBytes(connection: connection, count: 2)
            guard greetingData.count >= 2, greetingData[0] == 0x05 else {
                connection.cancel()
                return
            }

            let numMethods = Int(greetingData[1])
            let methodsData = try await receiveExactBytes(connection: connection, count: numMethods)

            // We support 0x00 (NO AUTHENTICATION REQUIRED)
            guard methodsData.contains(0x00) else {
                // 0xFF = NO ACCEPTABLE METHODS
                _ = try? await sendData(connection: connection, data: Data([0x05, 0xFF]))
                connection.cancel()
                return
            }

            // Reply: Version 5, Method 0 (No Auth)
            try await sendData(connection: connection, data: Data([0x05, 0x00]))

            // 2. Request Details (RFC 1928 Section 4)
            // Client request: [VER(0x05), CMD, RSV(0x00), ATYP, DST.ADDR, DST.PORT]
            let reqHeader = try await receiveExactBytes(connection: connection, count: 4)
            guard reqHeader.count == 4, reqHeader[0] == 0x05 else {
                connection.cancel()
                return
            }

            let cmd = reqHeader[1]
            guard cmd == 0x01 else {
                // CMD 0x01 is CONNECT. Others (BIND, UDP) not supported
                // Reply: Command not supported (0x07)
                let resp = Data([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                _ = try? await sendData(connection: connection, data: resp)
                connection.cancel()
                return
            }

            let atyp = reqHeader[3]
            var targetHost = ""

            switch atyp {
            case 0x01: // IPv4 (4 bytes)
                let ipBytes = try await receiveExactBytes(connection: connection, count: 4)
                targetHost = ipBytes.map { String($0) }.joined(separator: ".")
            case 0x03: // Domain Name (1 byte length + domain)
                let lenData = try await receiveExactBytes(connection: connection, count: 1)
                let domainLen = Int(lenData[0])
                let domainBytes = try await receiveExactBytes(connection: connection, count: domainLen)
                guard let domainStr = String(data: domainBytes, encoding: .utf8) else {
                    let resp = Data([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]) // Address type not supported
                    _ = try? await sendData(connection: connection, data: resp)
                    connection.cancel()
                    return
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
                connection.cancel()
                return
            }

            // Port (2 bytes big endian)
            let portBytes = try await receiveExactBytes(connection: connection, count: 2)
            let targetPort = (Int(portBytes[0]) << 8) | Int(portBytes[1])

            logDebug("SOCKS5 request to forward to \(targetHost):\(targetPort)", category: .network)

            // 3. Open Direct-TCPIP Channel via Citadel SSH Client
            let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            let directTCPIP = SSHChannelType.DirectTCPIP(
                targetHost: targetHost,
                targetPort: targetPort,
                originatorAddress: originator
            )

            // Bridge SSH Channel data to NWConnection
            let channel: Channel
            do {
                channel = try await sshClient.createDirectTCPIPChannel(using: directTCPIP) { channel in
                    let bridgeHandler = Socks5InboundHandler(connection: connection)
                    return channel.pipeline.addHandler(bridgeHandler)
                }
            } catch {
                logError("Failed to open SSH direct-tcpip channel to \(targetHost):\(targetPort): \(error)", category: .network)
                // Reply: Connection refused (0x05)
                let resp = Data([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                _ = try? await sendData(connection: connection, data: resp)
                connection.cancel()
                return
            }

            // Reply: Succeeded (0x00) with dummy bound address 0.0.0.0:0
            let successResp = Data([0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            try await sendData(connection: connection, data: successResp)

            // 4. Pipe local client -> SSH Channel
            await pipeClientToSSHChannel(connection: connection, channel: channel)

        } catch {
            connection.cancel()
        }
    }

    // MARK: - Local to SSH Data Pipe

    private func pipeClientToSSHChannel(connection: NWConnection, channel: Channel) async {
        while !Task.isCancelled {
            do {
                let data = try await receiveSomeData(connection: connection)
                guard !data.isEmpty else {
                    // Client closed stream
                    try? await channel.close()
                    connection.cancel()
                    break
                }

                var buffer = channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                try await channel.writeAndFlush(buffer)
            } catch {
                try? await channel.close()
                connection.cancel()
                break
            }
        }
    }

    // MARK: - Async Network Helpers

    private func receiveExactBytes(connection: NWConnection, count: Int) async throws -> Data {
        var accumulated = Data()
        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
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
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
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
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

// MARK: - Inbound Bridge Handler (SSH -> NWConnection)

private final class Socks5InboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let data = Data(buffer.readableBytesView)

        connection.send(content: data, completion: .contentProcessed { error in

            if let error = error {
                logError("Failed to write SSH data to SOCKS client: \(error)", category: .network)
                context.close(promise: nil)
            }
        })
    }

    func channelInactive(context: ChannelHandlerContext) {
        connection.cancel()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logError("SOCKS5 SSH channel error: \(error)", category: .network)
        connection.cancel()
        context.close(promise: nil)
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
