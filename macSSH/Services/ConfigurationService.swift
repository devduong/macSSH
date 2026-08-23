//
//  ConfigurationService.swift
//  macSSH
//
//  Service for managing app configurations (Import, Export, Save, Save As, New)
//

import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

extension Notification.Name {
    static let configurationDataDidChange = Notification.Name("configurationDataDidChange")
    static let newConnectionRequested = Notification.Name("newConnectionRequested")
    static let newFolderRequested = Notification.Name("newFolderRequested")
    static let settingsRequested = Notification.Name("settingsRequested")
    static let donateRequested = Notification.Name("donateRequested")
    static let aboutRequested = Notification.Name("aboutRequested")
}

struct AppSettingsData: Codable, Sendable {
    var biometricLockEnabled: Bool?
    var lockOnAppResume: Bool?
    var lockBeforeConnection: Bool?
    var lockAfterInactivity: Bool?
    var inactivityTimeoutSeconds: Int?
}

struct EncryptedCredentialItem: Codable, Sendable {
    var encryptedPassword: String?       // AES-256-GCM ciphertext bound to physical Mac
    var encryptedPrivateKeyData: String? // AES-256-GCM ciphertext of private key content
}

struct AppConfigurationData: Codable, Sendable {
    var version: String = "1.0"
    var exportDate: Date = Date()
    var appName: String = "macSSH"
    var connections: [Connection]
    var folders: [Folder]
    var settings: AppSettingsData?
    var encryptedCredentials: [UUID: EncryptedCredentialItem]?
}

@MainActor
final class ConfigurationService: ObservableObject {
    static let shared = ConfigurationService()

    private static let currentFileURLKey = "configurationCurrentFileURL"

    @Published var currentFileURL: URL? {
        didSet {
            if let url = currentFileURL {
                UserDefaults.standard.set(url.path, forKey: Self.currentFileURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentFileURLKey)
            }
        }
    }
    @Published var lastOperationStatus: String?
    @Published var isProcessing: Bool = false
    @Published var hasUnsavedChanges: Bool = false

    private let connectionRepository: ConnectionRepositoryProtocol
    private let folderRepository: FolderRepositoryProtocol

    init(
        connectionRepository: ConnectionRepositoryProtocol = ConnectionRepository(),
        folderRepository: FolderRepositoryProtocol = FolderRepository()
    ) {
        self.connectionRepository = connectionRepository
        self.folderRepository = folderRepository

        // Restore last opened file URL from UserDefaults
        if let savedPath = UserDefaults.standard.string(forKey: Self.currentFileURLKey) {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                self.currentFileURL = url
            }
        }
    }

    // MARK: - Export / Build Data

    func buildConfigurationData() async throws -> AppConfigurationData {
        let connections = try await connectionRepository.fetchAll()
        let folders = try await folderRepository.fetchAll()

        let appLock = AppLockManager.shared
        let settings = AppSettingsData(
            biometricLockEnabled: appLock.isBiometricLockEnabled,
            lockOnAppResume: appLock.lockOnAppResume,
            lockBeforeConnection: appLock.lockBeforeConnection,
            lockAfterInactivity: appLock.lockAfterInactivity,
            inactivityTimeoutSeconds: appLock.inactivityTimeout.rawValue
        )

        // Encrypt credentials with hardware-bound AES-256-GCM
        var credentials: [UUID: EncryptedCredentialItem] = [:]
        for conn in connections {
            var item = EncryptedCredentialItem()
            var hasSecret = false

            // Save & encrypt password if savePassword is enabled and available in session cache
            if conn.savePassword, let pass = ConnectionSessionManager.shared.getCachedPassword(for: conn.id), !pass.isEmpty {
                if let encrypted = try? DeviceSecurityService.encrypt(pass) {
                    item.encryptedPassword = encrypted
                    hasSecret = true
                }
            }

            // Save & encrypt private key file content if present
            if let keyPath = conn.privateKeyPath, !keyPath.isEmpty,
               FileManager.default.fileExists(atPath: keyPath),
               let keyData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)),
               let keyString = String(data: keyData, encoding: .utf8) {
                if let encryptedKey = try? DeviceSecurityService.encrypt(keyString) {
                    item.encryptedPrivateKeyData = encryptedKey
                    hasSecret = true
                }
            }

            if hasSecret {
                credentials[conn.id] = item
            }
        }

        return AppConfigurationData(
            version: "1.0",
            exportDate: Date(),
            appName: "macSSH",
            connections: connections,
            folders: folders,
            settings: settings,
            encryptedCredentials: credentials.isEmpty ? nil : credentials
        )
    }

    func exportToJSONData() async throws -> Data {
        let config = try await buildConfigurationData()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(config)
    }

    // MARK: - Save / Save As

    func save() async throws {
        if let url = currentFileURL {
            try await save(to: url)
        } else {
            _ = try await saveAs()
        }
    }

    func save(to url: URL) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let data = try await exportToJSONData()
        try data.write(to: url, options: .atomic)
        currentFileURL = url
        hasUnsavedChanges = false
        lastOperationStatus = "Configuration saved to \(url.lastPathComponent)"
        logInfo("Configuration saved to \(url.path)", category: .database)
    }

    func saveAs() async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Configuration"
        panel.prompt = "Save"
        panel.nameFieldStringValue = currentFileURL?.lastPathComponent ?? "macSSH-Settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let response = await panel.begin()
        guard response == .OK, let selectedURL = panel.url else {
            return nil
        }

        try await save(to: selectedURL)
        return selectedURL
    }

    // MARK: - Export

    func exportSettings() async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Settings to JSON"
        panel.prompt = "Export"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        panel.nameFieldStringValue = "macSSH-Export-\(dateStr).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let response = await panel.begin()
        guard response == .OK, let selectedURL = panel.url else {
            return nil
        }

        try await save(to: selectedURL)
        lastOperationStatus = "Settings exported to \(selectedURL.lastPathComponent)"
        return selectedURL
    }

    // MARK: - Open / Load / Import

    func loadConfiguration() async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Open Configuration File"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let response = await panel.begin()
        guard response == .OK, let selectedURL = panel.url else {
            return false
        }

        try await importFromJSON(fileURL: selectedURL, replaceExisting: true)
        currentFileURL = selectedURL
        return true
    }

    func importSettings(replaceExisting: Bool = false) async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Import Settings from JSON"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let response = await panel.begin()
        guard response == .OK, let selectedURL = panel.url else {
            return false
        }

        try await importFromJSON(fileURL: selectedURL, replaceExisting: replaceExisting)
        return true
    }

    func importFromJSON(fileURL: URL, replaceExisting: Bool) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let config = try decoder.decode(AppConfigurationData.self, from: data)

        if replaceExisting {
            // Disconnect any active sessions
            await ConnectionSessionManager.shared.disconnectAll()

            // Delete existing connections
            let existingConnections = try await connectionRepository.fetchAll()
            for connection in existingConnections {
                try await connectionRepository.delete(id: connection.id)
            }

            // Delete existing folders
            let existingFolders = try await folderRepository.fetchAll()
            for folder in existingFolders {
                try await folderRepository.delete(id: folder.id)
            }
        }

        // Import folders first so connections can reference them
        let currentFolders = try await folderRepository.fetchAll()
        let existingFolderIds = Set(currentFolders.map(\.id))

        for folder in config.folders {
            if !existingFolderIds.contains(folder.id) {
                try await folderRepository.save(folder)
            } else if replaceExisting {
                try await folderRepository.update(folder)
            }
        }

        // Import connections
        let currentConnections = try await connectionRepository.fetchAll()
        let existingConnIds = Set(currentConnections.map(\.id))

        for connection in config.connections {
            if !existingConnIds.contains(connection.id) {
                try await connectionRepository.save(connection)
            } else if replaceExisting {
                try await connectionRepository.update(connection)
            }
        }

        // Apply settings if present
        if let settings = config.settings {
            let appLock = AppLockManager.shared
            if let lockOnResume = settings.lockOnAppResume {
                appLock.lockOnAppResume = lockOnResume
            }
            if let lockBeforeConn = settings.lockBeforeConnection {
                appLock.lockBeforeConnection = lockBeforeConn
            }
            if let lockInactivity = settings.lockAfterInactivity {
                appLock.lockAfterInactivity = lockInactivity
            }
            if let timeoutSeconds = settings.inactivityTimeoutSeconds,
               let timeout = InactivityTimeout(rawValue: timeoutSeconds) {
                appLock.inactivityTimeout = timeout
            }
        }

        // Restore encrypted credentials if running on the authorized Mac
        if let credentials = config.encryptedCredentials {
            for (connId, cred) in credentials {
                if let encPassword = cred.encryptedPassword {
                    do {
                        let plainPassword = try DeviceSecurityService.decrypt(encPassword)
                        ConnectionSessionManager.shared.cachePassword(plainPassword, for: connId)
                        logInfo("Successfully decrypted and restored credentials for connection \(connId)", category: .auth)
                    } catch {
                        logWarning("Could not decrypt password for connection \(connId): File is protected and locked to its original Mac hardware.", category: .auth)
                    }
                }
            }
        }

        NotificationCenter.default.post(name: .configurationDataDidChange, object: nil)
        hasUnsavedChanges = false
        lastOperationStatus = "Successfully loaded configuration from \(fileURL.lastPathComponent)"
        logInfo("Imported \(config.connections.count) connections and \(config.folders.count) folders from \(fileURL.path)", category: .database)
    }

    // MARK: - New Configuration

    /// Prompts the user to save unsaved changes or confirm resetting to a brand new configuration.
    @MainActor
    func requestNewConfiguration() async throws -> Bool {
        let existingConnections = (try? await connectionRepository.fetchAll()) ?? []
        let existingFolders = (try? await folderRepository.fetchAll()) ?? []

        if existingConnections.isEmpty && existingFolders.isEmpty {
            try await newConfiguration()
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning

        if hasUnsavedChanges {
            alert.messageText = L10n.tr("save_before_new_config_prompt")
            alert.informativeText = L10n.tr("unsaved_changes_warning")
            alert.addButton(withTitle: L10n.tr("save_and_new"))
            alert.addButton(withTitle: L10n.tr("dont_save"))
            alert.addButton(withTitle: L10n.tr("cancel"))

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                try await save()
                try await newConfiguration()
                return true
            case .alertSecondButtonReturn:
                try await newConfiguration()
                return true
            default:
                return false
            }
        } else {
            alert.messageText = L10n.tr("create_new_config_title")
            alert.informativeText = L10n.tr("create_new_config_desc")
            alert.addButton(withTitle: L10n.tr("create_new_clear_all"))
            alert.addButton(withTitle: L10n.tr("cancel"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                try await newConfiguration()
                return true
            }
            return false
        }
    }

    func newConfiguration() async throws {
        isProcessing = true
        defer { isProcessing = false }

        await ConnectionSessionManager.shared.disconnectAll()

        let existingConnections = try await connectionRepository.fetchAll()
        for connection in existingConnections {
            try await connectionRepository.delete(id: connection.id)
        }

        let existingFolders = try await folderRepository.fetchAll()
        for folder in existingFolders {
            try await folderRepository.delete(id: folder.id)
        }

        currentFileURL = nil
        hasUnsavedChanges = false
        lastOperationStatus = "New configuration created"
        NotificationCenter.default.post(name: .configurationDataDidChange, object: nil)
        logInfo("Reset to new configuration", category: .database)
    }

    // MARK: - Unsaved Changes Tracking

    /// Call this whenever the user modifies connection/folder data
    func markUnsavedChanges() {
        hasUnsavedChanges = true
    }

    // MARK: - Auto Load on Launch

    /// If a file was previously open, automatically reload it on app launch.
    func autoLoadLastFileIfNeeded() async {
        guard let url = currentFileURL else { return }
        do {
            try await importFromJSON(fileURL: url, replaceExisting: true)
            currentFileURL = url   // importFromJSON doesn't change currentFileURL, keep it
            hasUnsavedChanges = false
            logInfo("Auto-loaded configuration from \(url.lastPathComponent)", category: .database)
        } catch {
            logError("Failed to auto-load configuration from \(url.path): \(error)", category: .database)
            // If file no longer accessible, clear the saved URL
            currentFileURL = nil
        }
    }
}
