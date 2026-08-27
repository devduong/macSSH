//
//  Logger.swift
//  macSSH
//
//  Centralized logging using OSLog and in-memory AppLogStore
//

import Foundation
import SwiftUI
import os.log

public enum LogCategory: String, Sendable, CaseIterable {
    case app = "App"
    case network = "Network"
    case socks5 = "SOCKS5"
    case sftp = "SFTP"
    case terminal = "Terminal"
    case auth = "Auth"
    case keychain = "Keychain"
    case database = "Database"
    case ui = "UI"

    public var icon: String {
        switch self {
        case .app: return "app.badge"
        case .network: return "network"
        case .socks5: return "wifi"
        case .sftp: return "folder.badge.gearshape"
        case .terminal: return "terminal"
        case .auth: return "lock.shield"
        case .keychain: return "key"
        case .database: return "cylinder"
        case .ui: return "macwindow"
        }
    }
}

public enum LogLevel: String, Sendable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARN"
    case error = "ERROR"

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info, .success: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    public var prefix: String {
        "[\(rawValue)]"
    }

    public var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? AppConstants.bundleIdentifier
    private var loggers: [LogCategory: os.Logger] = [:]

    private init() {
        for category in LogCategory.allCases {
            loggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
    }

    public func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .info,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let msg = message()
        let logger = loggers[category] ?? os.Logger(subsystem: subsystem, category: category.rawValue)
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.prefix) [\(fileName):\(line)] \(function) - \(msg)"

        logger.log(level: level.osLogType, "\(logMessage)")
        #if DEBUG
        print(logMessage)
        #endif

        Task { @MainActor in
            AppLogStore.shared.append(level: level, category: category, message: msg)
        }
    }

    @inline(__always)
    public func debug(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log(message(), level: .debug, category: category, file: file, function: function, line: line)
        #endif
    }

    @inline(__always)
    public func info(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .info, category: category, file: file, function: function, line: line)
    }

    @inline(__always)
    public func success(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .success, category: category, file: file, function: function, line: line)
    }

    @inline(__always)
    public func warning(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .warning, category: category, file: file, function: function, line: line)
    }

    @inline(__always)
    public func error(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .error, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Functions

@inline(__always)
public func logDebug(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    Logger.shared.debug(message(), category: category, file: file, function: function, line: line)
    #endif
}

@inline(__always)
public func logInfo(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message(), category: category, file: file, function: function, line: line)
}

@inline(__always)
public func logSuccess(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.success(message(), category: category, file: file, function: function, line: line)
}

@inline(__always)
public func logWarning(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message(), category: category, file: file, function: function, line: line)
}

@inline(__always)
public func logError(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message(), category: category, file: file, function: function, line: line)
}
