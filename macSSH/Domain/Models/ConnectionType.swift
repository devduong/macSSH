//
//  ConnectionType.swift
//  macSSH
//
//  Connection type representation
//


import Foundation

enum ConnectionType: String, Codable, Sendable, CaseIterable {
    case sftp

    var displayName: String {
        switch self {
        case .sftp:
            return "SSH"
        }
    }

    var iconName: String {
        switch self {
        case .sftp:
            return "server.rack"
        }
    }

    var description: String {
        switch self {
        case .sftp:
            return "Secure File Transfer Protocol"
        }
    }
}

