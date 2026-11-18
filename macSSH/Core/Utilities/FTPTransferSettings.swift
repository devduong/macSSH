//
//  FTPTransferSettings.swift
//  macSSH
//
//  Manages configurable multi-stream concurrency for FTP uploads and downloads
//

import Foundation
import Combine

public enum FTPTransferConstants {
    public static let defaultMaxStreams = 10
    public static let minStreams = 1
    public static let maxStreams = 32
    /// Minimum single-file size (4 MB) before splitting a single FTP download across byte-range streams
    public static let multiPartThresholdBytes: Int64 = 4 * 1024 * 1024
    /// Minimum chunk size per byte-range stream (1 MB)
    public static let minChunkBytes: Int64 = 1024 * 1024
}

@MainActor
public final class FTPTransferSettings: ObservableObject {
    public static let shared = FTPTransferSettings()

    private static let storageKey = "ftpMaxConcurrentStreams"

    @Published public var maxConcurrentStreams: Int {
        didSet {
            let clampedValue = Self.clamped(maxConcurrentStreams)
            if maxConcurrentStreams != clampedValue {
                maxConcurrentStreams = clampedValue
                return
            }
            UserDefaults.standard.set(clampedValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: Self.storageKey)
        if saved >= FTPTransferConstants.minStreams {
            self.maxConcurrentStreams = Self.clamped(saved)
        } else {
            self.maxConcurrentStreams = FTPTransferConstants.defaultMaxStreams
        }
    }

    public nonisolated static func clamped(_ value: Int) -> Int {
        min(FTPTransferConstants.maxStreams, max(FTPTransferConstants.minStreams, value))
    }
}
