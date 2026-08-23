//
//  SFTPLogEntry.swift
//  macSSH
//
//  Model for SFTP activity log entries in the File Browser
//

import Foundation
import SwiftUI

enum SFTPLogLevel: String, Sendable, CaseIterable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARN"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct SFTPLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: SFTPLogLevel
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: SFTPLogLevel = .info, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
