//
//  TransferProgress.swift
//  macSSH
//
//  Model for tracking file transfer progress with speed and ETA calculations
//

import Foundation

/// Thread-safe cached byte formatter to avoid allocating ByteCountFormatter per transfer row render.
enum TransferByteFormatter {
    private static let lock = NSLock()
    private static let formatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt
    }()

    static func string(for bytes: Int64) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(fromByteCount: bytes)
    }
}

/// Represents the progress of a file transfer operation
struct TransferProgress: Identifiable, Sendable, Equatable {
    let id: UUID
    let fileName: String
    let localURL: URL?
    let remotePath: String
    let totalBytes: Int64
    var startTime: Date
    let transferType: TransferType

    /// Number of bytes transferred so far
    var bytesTransferred: Int64

    /// Current status of the transfer
    var status: TransferStatus

    /// Error if the transfer failed
    var error: String?

    /// Current transfer speed in bytes per second
    var speed: Double = 0

    init(
        id: UUID = UUID(),
        fileName: String,
        localURL: URL? = nil,
        remotePath: String = "",
        bytesTransferred: Int64 = 0,
        totalBytes: Int64,
        transferType: TransferType = .upload,
        status: TransferStatus = .inProgress,
        startTime: Date = Date(),
        speed: Double = 0,
        error: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.localURL = localURL
        self.remotePath = remotePath
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.transferType = transferType
        self.status = status
        self.startTime = startTime
        self.speed = speed
        self.error = error
    }

    /// Progress as a fraction (0.0 to 1.0)
    var fractionCompleted: Double {
        guard totalBytes > 0 else { return status == .completed ? 1.0 : 0 }
        return min(1.0, max(0.0, Double(bytesTransferred) / Double(totalBytes)))
    }

    /// Progress as a percentage (0 to 100)
    var percentCompleted: Int {
        Int(fractionCompleted * 100)
    }

    /// Formatted string showing bytes transferred / total bytes
    var progressText: String {
        let transferred = TransferByteFormatter.string(for: bytesTransferred)
        let total = TransferByteFormatter.string(for: totalBytes)
        return "\(transferred) / \(total)"
    }

    /// Formatted speed string (e.g. "4.5 MB/s")
    var formattedSpeed: String {
        guard status == .inProgress, speed > 0 else {
            return status == .completed ? "Done" : "--"
        }
        let speedStr = TransferByteFormatter.string(for: Int64(speed))
        return "\(speedStr)/s"
    }

    /// Formatted estimated time remaining string (e.g. "12s left")
    var formattedETA: String {
        guard status == .inProgress, speed > 1024, totalBytes > bytesTransferred else {
            return "--"
        }
        let remainingBytes = Double(totalBytes - bytesTransferred)
        let remainingSeconds = Int(remainingBytes / speed)

        if remainingSeconds < 60 {
            return "\(remainingSeconds)s left"
        } else if remainingSeconds < 3600 {
            let minutes = remainingSeconds / 60
            let seconds = remainingSeconds % 60
            return "\(minutes)m \(seconds)s left"
        } else {
            let hours = remainingSeconds / 3600
            let minutes = (remainingSeconds % 3600) / 60
            return "\(hours)h \(minutes)m left"
        }
    }

    /// Whether the transfer is complete
    var isComplete: Bool {
        status == .completed
    }

    /// Whether the transfer is still in progress
    var isInProgress: Bool {
        status == .inProgress
    }

    /// Whether the transfer can be cancelled (queued or active)
    var isCancellable: Bool {
        status == .inProgress || status == .pending
    }

    /// Whether the transfer can be retried (failed or cancelled with a known local URL)
    var isRetryable: Bool {
        (status == .failed || status == .cancelled) && localURL != nil
    }

    /// Total size formatted
    var totalSizeText: String {
        TransferByteFormatter.string(for: totalBytes)
    }
}

/// Status of a transfer operation
enum TransferStatus: Sendable, Equatable, Hashable {
    case pending
    case inProgress
    case completed
    case failed
    case cancelled
}

/// Type of transfer
enum TransferType: Sendable, Equatable, Hashable {
    case upload
    case download
}

/// Type alias for progress callback - receives bytes transferred
typealias TransferProgressHandler = @Sendable (_ bytesTransferred: Int64) -> Void
