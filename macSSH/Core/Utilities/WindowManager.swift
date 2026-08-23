//
//  WindowManager.swift
//  macSSH
//
//  Manages window data passing for multi-window support
//

import Foundation
import SwiftUI
import Combine

// MARK: - Window Data Types
struct FileBrowserWindowData: Sendable {
    let connectionId: UUID
    let connectionName: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    let connectionType: ConnectionType
    let socksProxyEnabled: Bool
    let socksProxyPort: Int
    let socksProxyAllowLAN: Bool
    let savePassword: Bool

    init(
        connectionId: UUID,
        connectionName: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        connectionType: ConnectionType = .sftp,
        socksProxyEnabled: Bool = false,
        socksProxyPort: Int = 1080,
        socksProxyAllowLAN: Bool = false,
        savePassword: Bool = false
    ) {
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.connectionType = connectionType
        self.socksProxyEnabled = socksProxyEnabled
        self.socksProxyPort = socksProxyPort
        self.socksProxyAllowLAN = socksProxyAllowLAN
        self.savePassword = savePassword
    }
}

struct FileEditorWindowData: Sendable {
    let filePath: String
    let fileName: String
    let content: String
    let connectionId: UUID
    // Connection details for saving
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    let connectionType: ConnectionType

    init(
        filePath: String,
        fileName: String,
        content: String,
        connectionId: UUID,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        connectionType: ConnectionType = .sftp
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.content = content
        self.connectionId = connectionId
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.connectionType = connectionType
    }
}


struct FileInfoWindowData: Sendable {
    let file: RemoteFile
    let connectionName: String
}

struct TerminalWindowData: Sendable {
    let connectionId: UUID
    let connectionName: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let authMethod: AuthMethod
    let privateKeyPath: String?
    let socksProxyEnabled: Bool
    let socksProxyPort: Int
    let socksProxyAllowLAN: Bool
    let savePassword: Bool

    init(
        connectionId: UUID,
        connectionName: String,
        host: String,
        port: Int,
        username: String,
        password: String,
        authMethod: AuthMethod,
        privateKeyPath: String?,
        socksProxyEnabled: Bool = false,
        socksProxyPort: Int = 1080,
        socksProxyAllowLAN: Bool = false,
        savePassword: Bool = false
    ) {
        self.connectionId = connectionId
        self.connectionName = connectionName
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.socksProxyEnabled = socksProxyEnabled
        self.socksProxyPort = socksProxyPort
        self.socksProxyAllowLAN = socksProxyAllowLAN
        self.savePassword = savePassword
    }
}

// MARK: - Window Manager
@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published private(set) var activeConnectionIds: Set<UUID> = []

    private var fileBrowserData: [String: FileBrowserWindowData] = [:]
    private var fileEditorData: [String: FileEditorWindowData] = [:]
    private var fileInfoData: [String: FileInfoWindowData] = [:]
    private var terminalData: [String: TerminalWindowData] = [:]

    private init() {}

    // MARK: - Active Connection Tracking
    func markConnectionActive(_ connectionId: UUID) {
        activeConnectionIds.insert(connectionId)
    }

    func markConnectionInactive(_ connectionId: UUID) {
        activeConnectionIds.remove(connectionId)
    }

    func isConnectionActive(_ connectionId: UUID) -> Bool {
        activeConnectionIds.contains(connectionId)
    }


    // MARK: - File Browser Window
    func storeFileBrowserData(_ data: FileBrowserWindowData) -> String {
        let id = UUID().uuidString
        fileBrowserData[id] = data
        return id
    }

    func getFileBrowserData(for id: String) -> FileBrowserWindowData? {
        fileBrowserData[id]
    }

    func removeFileBrowserData(for id: String) {
        fileBrowserData.removeValue(forKey: id)
    }

    // MARK: - File Editor Window
    func storeFileEditorData(_ data: FileEditorWindowData) -> String {
        let id = UUID().uuidString
        fileEditorData[id] = data
        return id
    }

    func getFileEditorData(for id: String) -> FileEditorWindowData? {
        fileEditorData[id]
    }

    func removeFileEditorData(for id: String) {
        fileEditorData.removeValue(forKey: id)
    }

    // MARK: - File Info Window
    func storeFileInfoData(_ data: FileInfoWindowData) -> String {
        let id = UUID().uuidString
        fileInfoData[id] = data
        return id
    }

    func getFileInfoData(for id: String) -> FileInfoWindowData? {
        fileInfoData[id]
    }

    func removeFileInfoData(for id: String) {
        fileInfoData.removeValue(forKey: id)
    }

    // MARK: - Terminal Window
    func storeTerminalData(_ data: TerminalWindowData) -> String {
        let id = UUID().uuidString
        terminalData[id] = data
        return id
    }

    func getTerminalData(for id: String) -> TerminalWindowData? {
        terminalData[id]
    }

    func removeTerminalData(for id: String) {
        terminalData.removeValue(forKey: id)
    }

    // MARK: - Cleanup
    func clearAllData() {
        fileBrowserData.removeAll()
        fileEditorData.removeAll()
        fileInfoData.removeAll()
        terminalData.removeAll()
    }
}
