//
//  Logger.swift
//  macSSH
//
//  Centralized logging using OSLog
//

import Foundation
import os.log

enum LogCategory: String {
    case app = "App"
    case sftp = "SFTP"
    case keychain = "Keychain"
    case database = "Database"
    case ui = "UI"
    case network = "Network"
    case auth = "Auth"
}

enum LogLevel {
    case debug
    case info
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARNING]"
        case .error: return "[ERROR]"
        }
    }
}

final class Logger {
    static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? AppConstants.bundleIdentifier
    private var loggers: [LogCategory: os.Logger] = [:]

    private init() {
        for category in [LogCategory.app, .sftp, .keychain, .database, .ui, .network, .auth] {
            loggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
    }

    func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .info,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let msg = message()
        let logger = loggers[category] ?? os.Logger(subsystem: subsystem, category: category.rawValue)
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.prefix) [\(fileName):\(line)] \(function) - \(msg)"

        logger.log(level: level.osLogType, "\(logMessage)")
        print(logMessage)
        #else
        // In Release builds: Only log errors and warnings; ignore debug & info for zero memory allocation
        if level == .error || level == .warning {
            let msg = message()
            let logger = loggers[category] ?? os.Logger(subsystem: subsystem, category: category.rawValue)
            let fileName = (file as NSString).lastPathComponent
            let logMessage = "\(level.prefix) [\(fileName):\(line)] \(function) - \(msg)"
            logger.log(level: level.osLogType, "\(logMessage)")
        }
        #endif
    }

    @inline(__always)
    func debug(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log(message(), level: .debug, category: category, file: file, function: function, line: line)
        #endif
    }

    @inline(__always)
    func info(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log(message(), level: .info, category: category, file: file, function: function, line: line)
        #endif
    }

    @inline(__always)
    func warning(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .warning, category: category, file: file, function: function, line: line)
    }

    @inline(__always)
    func error(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .error, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Functions (Zero-Allocation in Release)

@inline(__always)
func logDebug(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    Logger.shared.debug(message(), category: category, file: file, function: function, line: line)
    #endif
}

@inline(__always)
func logInfo(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    Logger.shared.info(message(), category: category, file: file, function: function, line: line)
    #endif
}

@inline(__always)
func logWarning(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message(), category: category, file: file, function: function, line: line)
}

@inline(__always)
func logError(_ message: @autoclosure () -> String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message(), category: category, file: file, function: function, line: line)
}
