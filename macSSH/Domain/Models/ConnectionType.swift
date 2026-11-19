//
//  ConnectionType.swift
//  macSSH
//
//  Connection type representation (SFTP, FTP, SMB)
//

import Foundation
import SwiftUI

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
            return "apple.terminal"
        case .ftp:
            return "arrow.up.arrow.down.circle"
        case .smb:
            return "externaldrive.connected.to.line.below"
        }
    }

    var accentColor: Color {
        switch self {
        case .sftp:
            return .blue
        case .ftp:
            return .teal
        case .smb:
            return .indigo
        }
    }

    /// All current and legacy default protocol icons so editing/switching protocols auto-updates cleanly
    static let allDefaultIcons: Set<String> = [
        "apple.terminal",
        "apple.terminal.fill",
        "terminal",
        "terminal.fill",
        "server.rack",
        "network",
        "arrow.up.arrow.down.circle",
        "arrow.up.arrow.down.circle.fill",
        "externaldrive.connected.to.line.below",
        "externaldrive.connected.to.line.below.fill"
    ]

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

    var supportsFinderMount: Bool {
        self == .ftp || self == .sftp
    }
}
