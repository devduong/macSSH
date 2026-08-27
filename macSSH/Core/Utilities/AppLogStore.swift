//
//  AppLogStore.swift
//  macSSH
//
//  Observable in-memory log store for real-time application and connection activity logging
//

import Foundation
import SwiftUI
import AppKit

public struct AppLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel = .info,
        category: LogCategory = .app,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    public var shortTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
@Observable
public final class AppLogStore {
    public static let shared = AppLogStore()

    public private(set) var entries: [AppLogEntry] = []
    public var maxEntries: Int = 200

    private init() {
        // Initial startup log entry
        append(
            level: .info,
            category: .app,
            message: "macSSH Activity Log initialized. Monitoring SSH, SOCKS5, SFTP & system operations."
        )
    }

    public func append(level: LogLevel, category: LogCategory, message: String) {
        let entry = AppLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        // Log mới nhất ở đầu danh sách (index 0)
        entries.insert(entry, at: 0)
        // Giới hạn tối đa 200 log
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }

    public func emitTestLogs() {
        append(
            level: .info,
            category: .app,
            message: "🧪 [TEST] Log subsystem test started."
        )
        append(
            level: .info,
            category: .network,
            message: "Initiating SSH handshake with 10.0.1.233:22 (SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.10)..."
        )
        append(
            level: .success,
            category: .auth,
            message: "Authentication successful using stored credentials for user 'root'."
        )
        append(
            level: .info,
            category: .socks5,
            message: "Native OpenSSH SOCKS5 Dynamic Forwarding active on 127.0.0.1:1080 (allowLAN: false, PID: 49102)."
        )
        append(
            level: .info,
            category: .sftp,
            message: "SFTP channel opened. Listing remote directory '/var/log/nginx' (found 14 items)."
        )
        append(
            level: .warning,
            category: .network,
            message: "Network round-trip latency jitter observed: 124ms (threshold: 100ms)."
        )
        append(
            level: .error,
            category: .network,
            message: "Simulated test error: Connection dropped by peer (demonstration error message)."
        )
        append(
            level: .success,
            category: .app,
            message: "🧪 [TEST] All log levels (INFO, SUCCESS, WARN, ERROR) verified successfully."
        )
    }

    public func formattedPlainText(filteredEntries: [AppLogEntry]) -> String {
        filteredEntries.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    public func copyToClipboard(filteredEntries: [AppLogEntry]) {
        let text = formattedPlainText(filteredEntries: filteredEntries)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
