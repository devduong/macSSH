//
//  Connection.swift
//  macSSH
//
//  Domain model for SSH connections
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let connection = UTType(exportedAs: "com.devduong.macSSH.connection")
}

struct Connection: Identifiable, Hashable, Sendable, Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .connection)
    }
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var privateKeyPath: String?
    var savePassword: Bool
    var description: String?
    var tags: [String]
    var iconName: String
    var folderId: UUID?
    var createdAt: Date
    var updatedAt: Date

    // Connection type
    var connectionType: ConnectionType

    // SOCKS5 Dynamic Port Forwarding
    var socksProxyEnabled: Bool
    var socksProxyPort: Int
    var socksProxyAllowLAN: Bool

    // FTP Multi-Stream Transfer Concurrency (nil = use global default, 10)
    var ftpMaxStreams: Int?

    // Startup automation quick settings
    var autoConnect: Bool
    var autoMount: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        privateKeyPath: String? = nil,
        savePassword: Bool = false,
        description: String? = nil,
        tags: [String] = [],
        iconName: String? = nil,
        folderId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        connectionType: ConnectionType = .sftp,
        socksProxyEnabled: Bool = false,
        socksProxyPort: Int = 1080,
        socksProxyAllowLAN: Bool = false,
        ftpMaxStreams: Int? = nil,
        autoConnect: Bool = false,
        autoMount: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.savePassword = savePassword
        self.description = description
        self.tags = tags
        self.iconName = iconName ?? connectionType.iconName
        self.folderId = folderId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.connectionType = connectionType
        self.socksProxyEnabled = socksProxyEnabled
        self.socksProxyPort = socksProxyPort
        self.socksProxyAllowLAN = socksProxyAllowLAN
        self.ftpMaxStreams = ftpMaxStreams
        self.autoConnect = autoConnect
        self.autoMount = autoMount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ConnectionType.self, forKey: .connectionType) ?? .sftp
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? type.defaultPort
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .password
        self.privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        self.savePassword = try container.decodeIfPresent(Bool.self, forKey: .savePassword) ?? false
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? type.iconName
        self.folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.connectionType = type
        self.socksProxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .socksProxyEnabled) ?? false
        self.socksProxyPort = try container.decodeIfPresent(Int.self, forKey: .socksProxyPort) ?? 1080
        self.socksProxyAllowLAN = try container.decodeIfPresent(Bool.self, forKey: .socksProxyAllowLAN) ?? false
        self.ftpMaxStreams = try container.decodeIfPresent(Int.self, forKey: .ftpMaxStreams)
        self.autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        self.autoMount = try container.decodeIfPresent(Bool.self, forKey: .autoMount) ?? false
    }

    // MARK: - Computed Properties
    var displayHost: String {
        if port == connectionType.defaultPort {
            return host
        }
        return "\(host):\(port)"
    }

    var connectionString: String {
        if username.isBlank {
            return displayHost
        }
        return "\(username)@\(displayHost)"
    }

    var hasDescription: Bool {
        description?.isBlank == false
    }

    var hasTags: Bool {
        !tags.isEmpty
    }

    /// True for FTP/SMB connections using empty/anonymous/guest login without a password prompt
    var supportsAnonymousAuth: Bool {
        connectionType != .sftp && ["anonymous", "guest", ""].contains(username.lowercased())
    }

    // MARK: - Methods
    func withUpdatedTimestamp() -> Connection {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}

// MARK: - Validation
extension Connection {
    var isValid: Bool {
        !name.isBlank &&
        !host.isBlank &&
        !username.isBlank &&
        port > 0 && port <= 65535 &&
        (!socksProxyEnabled || (socksProxyPort > 0 && socksProxyPort <= 65535)) &&
        (authMethod == .password || privateKeyPath != nil)
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if name.isBlank {
            errors.append("Name is required")
        }
        if host.isBlank {
            errors.append("Host is required")
        }
        if username.isBlank {
            errors.append("Username is required")
        }
        if port <= 0 || port > 65535 {
            errors.append("Port must be between 1 and 65535")
        }
        if socksProxyEnabled && (socksProxyPort <= 0 || socksProxyPort > 65535) {
            errors.append("SOCKS5 Proxy port must be between 1 and 65535")
        }
        if authMethod == .privateKey && (privateKeyPath?.isBlank ?? true) {
            errors.append("Private key path is required for key authentication")
        }
        return errors
    }

    var isSFTPConnection: Bool {
        true
    }
}

