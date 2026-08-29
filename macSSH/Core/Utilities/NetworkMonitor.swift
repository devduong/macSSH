//
//  NetworkMonitor.swift
//  macSSH
//
//  Real-time internet connectivity monitoring using Apple NWPathMonitor.
//  Publishes `isConnected` state, posts notifications for UI/service reactivity,
//  and sends native macOS notifications (auto-hide after 5s) for internet loss/restore.
//

import Foundation
import Network
import SwiftUI
import UserNotifications

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
        requestNotificationPermission()
        startMonitoring()
    }

    // MARK: - Native Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logInfo("macOS notification permission granted.", category: .app)
            } else if let error {
                logWarning("macOS notification permission denied: \(error.localizedDescription)", category: .app)
            } else {
                logWarning("macOS notification permission denied by user.", category: .app)
            }
        }
    }

    // MARK: - Native macOS Notification (auto-hide after 5s)

    private func sendNativeNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Fire immediately (trigger with 1-second interval)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logError("Failed to deliver native notification: \(error.localizedDescription)", category: .app)
            }
        }

        // Auto-remove after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
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

                    // Native macOS notification (auto-hide after 5s)
                    self.sendNativeNotification(
                        title: L10n.tr("internet_lost_title"),
                        body: L10n.tr("internet_lost_msg"),
                        identifier: "macSSH.internet.lost"
                    )

                    NotificationCenter.default.post(name: .internetStatusChanged, object: nil, userInfo: ["connected": false])

                } else if !wasConnected && nowConnected {
                    // ── Internet Restored ──
                    self.isConnected = true
                    self.lastStateChangeDate = Date()

                    logInfo("Internet connection restored via \(self.connectionType). Initiating reconnection...", category: .network)

                    // Remove the "lost" notification if still visible
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["macSSH.internet.lost"])

                    ToastManager.shared.show(
                        title: L10n.tr("internet_restored_title"),
                        message: L10n.tr("internet_restored_msg"),
                        type: .info,
                        duration: 5.0
                    )

                    // Native macOS notification (auto-hide after 5s)
                    self.sendNativeNotification(
                        title: L10n.tr("internet_restored_title"),
                        body: L10n.tr("internet_restored_msg"),
                        identifier: "macSSH.internet.restored"
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
