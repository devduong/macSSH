//
//  ConnectionEntity.swift
//  macSSH
//
//  SwiftData entity for SSH connections
//

import Foundation
import SwiftData

@Model
final class ConnectionEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: String
    var privateKeyPath: String?
    var savePassword: Bool
    var connectionDescription: String?
    var tags: [String]
    var iconName: String
    var createdAt: Date
    var updatedAt: Date

    // Connection type (defaults to "sftp" for migration compatibility)
    var connectionType: String = "sftp"

    // SOCKS5 Dynamic Port Forwarding
    var socksProxyEnabled: Bool = false
    var socksProxyPort: Int = 1080
    var socksProxyAllowLAN: Bool = false

    var folder: FolderEntity?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: String = "password",
        privateKeyPath: String? = nil,
        savePassword: Bool = false,
        connectionDescription: String? = nil,
        tags: [String] = [],
        iconName: String = "server.rack",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        connectionType: String = "sftp",
        socksProxyEnabled: Bool = false,
        socksProxyPort: Int = 1080,
        socksProxyAllowLAN: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.savePassword = savePassword
        self.connectionDescription = connectionDescription
        self.tags = tags
        self.iconName = iconName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.connectionType = connectionType
        self.socksProxyEnabled = socksProxyEnabled
        self.socksProxyPort = socksProxyPort
        self.socksProxyAllowLAN = socksProxyAllowLAN
    }
}

