//
//  NetworkMonitor.swift
//  macSSH
//
//  Real-time internet connectivity monitoring using Apple NWPathMonitor.
//  Publishes `isConnected` state and posts notifications for UI/service reactivity.
//

import Foundation
import Network
import SwiftUI

@MainActor
@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    /// Current internet connectivity state
    public private(set) var isConnected: Bool = true

    /// Human-readable description of the active connection type
    public private(set) var connectionType: String = "Unknown"

    /// Timestamp of the last connectivity state change
    public private(set) var lastStateChangeDate: Date? = nil

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.duong.macSSH.NetworkMonitor", qos: .utility)

    private init() {
        startMonitoring()
    }

    // MARK: - Monitoring Lifecycle

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                let nowConnected = (path.status == .satisfied)

                // Update connection type description
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = "Wi-Fi"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = "Ethernet"
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = "Cellular"
                } else if nowConnected {
                    self.connectionType = "Other"
                } else {
                    self.connectionType = "None"
                }

                // Only fire events on actual state transitions
                if wasConnected && !nowConnected {
                    // ── Internet Lost ──
                    self.isConnected = false
                    self.lastStateChangeDate = Date()

                    logWarning("Internet connection lost (was: \(self.connectionType)). Active sessions may be interrupted.", category: .network)

                    ToastManager.shared.show(
                        title: L10n.tr("internet_lost_title"),
                        message: L10n.tr("internet_lost_msg"),
                        type: .error,
                        duration: 8.0
                    )

                    NotificationCenter.default.post(name: .internetStatusChanged, object: nil, userInfo: ["connected": false])

                } else if !wasConnected && nowConnected {
                    // ── Internet Restored ──
                    self.isConnected = true
                    self.lastStateChangeDate = Date()

                    logInfo("Internet connection restored via \(self.connectionType). Initiating reconnection...", category: .network)

                    ToastManager.shared.show(
                        title: L10n.tr("internet_restored_title"),
                        message: L10n.tr("internet_restored_msg"),
                        type: .info,
                        duration: 5.0
                    )

                    NotificationCenter.default.post(name: .internetStatusChanged, object: nil, userInfo: ["connected": true])
                }
            }
        }
        monitor.start(queue: queue)
        logInfo("NetworkMonitor started — monitoring system internet connectivity.", category: .network)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let internetStatusChanged = Notification.Name("internetStatusChanged")
}
