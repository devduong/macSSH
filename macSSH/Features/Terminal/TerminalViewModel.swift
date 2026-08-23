//
//  TerminalViewModel.swift
//  macSSH
//
//  ViewModel for the terminal feature
//

import Foundation
import SwiftUI

/// State of the terminal connection
enum TerminalState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(AppError)

    static func == (lhs: TerminalState, rhs: TerminalState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
final class TerminalViewModel {
    // MARK: - Published State
    private(set) var state: TerminalState = .disconnected
    private(set) var isConnected: Bool = false
    var error: AppError?
    var isShowingPasswordPrompt: Bool = false
    var isAuthFailed: Bool = false

    let connectionName: String
    private var currentPassword: String

    /// Connection string displayed in the subtitle (e.g. "user@host")
    var connectionString: String {
        "\(connectionData.username)@\(connectionData.host)"
    }

    /// Current terminal dimensions as a display string (e.g. "80 x 24")
    private(set) var terminalSizeText: String = TerminalSize.default.displayString

    // MARK: - Dependencies
    private let session: TerminalSessionProtocol
    let connectionData: TerminalWindowData

    // MARK: - Output handling
    private var outputTask: Task<Void, Never>?
    private var pendingOutputBuffer: [Data] = []

    var onOutput: ((Data) -> Void)? {
        didSet {
            // When callback is set, flush any buffered data
            if let callback = onOutput {
                for data in pendingOutputBuffer {
                    callback(data)
                }
                pendingOutputBuffer.removeAll()
            }
        }
    }

    // MARK: - Terminal size
    private var currentSize: TerminalSize = .default

    // MARK: - Initialization

    init(
        connectionName: String,
        session: TerminalSessionProtocol,
        connectionData: TerminalWindowData
    ) {
        self.connectionName = connectionName
        self.session = session
        self.connectionData = connectionData
        self.currentPassword = connectionData.password
    }

    // MARK: - Connection

    func connect(withPassword newPassword: String? = nil) async {
        if let newPassword {
            self.currentPassword = newPassword
        }

        // Only connect if disconnected or in error state
        switch state {
        case .disconnected, .error:
            break
        case .connecting, .connected:
            return
        }

        state = .connecting
        error = nil

        // Start output listener before connecting so no early output is missed
        startOutputListener()

        do {
            let socksPort = connectionData.socksProxyEnabled ? connectionData.socksProxyPort : nil
            let allowLAN = connectionData.socksProxyEnabled && connectionData.socksProxyAllowLAN
            if connectionData.authMethod == .password {
                try await session.connect(
                    host: connectionData.host,
                    port: connectionData.port,
                    username: connectionData.username,
                    password: currentPassword,
                    terminalSize: currentSize,
                    socksProxyPort: socksPort,
                    socksProxyAllowLAN: allowLAN
                )
            } else if let keyPath = connectionData.privateKeyPath {
                try await session.connect(
                    host: connectionData.host,
                    port: connectionData.port,
                    username: connectionData.username,
                    privateKeyPath: keyPath,
                    passphrase: currentPassword.isEmpty ? nil : currentPassword,
                    terminalSize: currentSize,
                    socksProxyPort: socksPort,
                    socksProxyAllowLAN: allowLAN
                )
            }

            isConnected = true
            state = .connected
            isShowingPasswordPrompt = false
            isAuthFailed = false
            ConnectionSessionManager.shared.markConnected(for: connectionData.connectionId)

            if !currentPassword.isEmpty {
                ConnectionSessionManager.shared.cachePassword(currentPassword, for: connectionData.connectionId)
            }

            logInfo("Terminal connected to \(connectionData.host)", category: .network)
        } catch {
            logError("Terminal connection failed: \(error)", category: .network)
            let appError = AppError.from(error)
            state = .error(appError)
            if case .authenticationFailed = appError {
                isAuthFailed = true
                isShowingPasswordPrompt = true
                ConnectionSessionManager.shared.clearSession(for: connectionData.connectionId)
            } else {
                self.error = appError
            }
        }
    }

    func disconnect() async {
        outputTask?.cancel()
        outputTask = nil
        pendingOutputBuffer.removeAll()

        await session.disconnect()
        isConnected = false
        state = .disconnected
        ConnectionSessionManager.shared.markDisconnected(for: connectionData.connectionId)

        logInfo("Terminal disconnected", category: .network)
    }

    deinit {
        let connectionId = connectionData.connectionId
        Task { @MainActor in
            ConnectionSessionManager.shared.markDisconnected(for: connectionId)
        }
    }

    func reconnect(withPassword newPassword: String? = nil) async {
        await disconnect()
        await connect(withPassword: newPassword)
    }

    // MARK: - Input/Output

    func sendInput(_ data: Data) {
        guard isConnected else { return }
        Task { [session] in
            do {
                try await session.send(data)
            } catch {
                logError("Failed to send terminal input: \(error)", category: .network)
            }
        }
    }

    func sendInput(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        sendInput(data)
    }

    private func startOutputListener() {
        outputTask = Task { [weak self] in
            guard let self else { return }

            let stream = await self.session.outputStream

            for await data in stream {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    if let callback = self.onOutput {
                        callback(data)
                    } else {
                        self.pendingOutputBuffer.append(data)
                    }
                }
            }

            // Stream ended - check if session ended gracefully or unexpectedly
            let graceful = await self.session.sessionEndedGracefully
            await MainActor.run {
                if self.isConnected {
                    self.isConnected = false
                    if graceful {
                        self.state = .disconnected
                    } else {
                        self.state = .error(.terminalConnectionLost)
                    }
                }
            }
        }
    }

    // MARK: - Terminal Size

    func resize(columns: Int, rows: Int) {
        // Validate size - must be positive
        guard columns > 0 && rows > 0 else { return }

        currentSize = TerminalSize(columns: columns, rows: rows)
        terminalSizeText = currentSize.displayString

        guard isConnected else { return }

        Task {
            do {
                try await session.resize(columns: columns, rows: rows)
            } catch {
                logError("Failed to resize terminal: \(error)", category: .network)
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() async {
        onOutput = nil
        await disconnect()
    }

    // MARK: - Error Handling

    func clearError() {
        error = nil
        if case .error = state {
            state = .disconnected
        }
    }
}
