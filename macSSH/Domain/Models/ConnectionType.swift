//
//  ConnectionType.swift
//  macSSH
//
//  Connection type representation (SFTP, FTP, SMB)
//

import Foundation

enum ConnectionType: String, Codable, Sendable, CaseIterable {
    case sftp
    case ftp
    case smb

    var displayName: String {
        switch self {
        case .sftp:
            return "SFTP (SSH)"
        case .ftp:
            return "FTP"
        case .smb:
            return "SMB"
        }
    }

    var badgeName: String {
        switch self {
        case .sftp:
            return "SFTP"
        case .ftp:
            return "FTP"
        case .smb:
            return "SMB"
        }
    }

    var defaultPort: Int {
        switch self {
        case .sftp:
            return 22
        case .ftp:
            return 21
        case .smb:
            return 445
        }
    }

    var iconName: String {
        switch self {
        case .sftp:
            return "server.rack"
        case .ftp:
            return "network"
        case .smb:
            return "externaldrive.connected.to.line.below"
        }
    }

    var description: String {
        switch self {
        case .sftp:
            return "SSH / Secure File Transfer Protocol"
        case .ftp:
            return "File Transfer Protocol"
        case .smb:
            return "Server Message Block (SMB/CIFS)"
        }
    }

    var supportsTerminal: Bool {
        self == .sftp
    }

    var supportsSocksProxy: Bool {
        self == .sftp
    }

    var supportsPrivateKey: Bool {
        self == .sftp
    }
}
