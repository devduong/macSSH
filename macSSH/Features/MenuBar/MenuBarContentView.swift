//
//  MenuBarContentView.swift
//  macSSH
//
//  Menu Bar extra dropdown view
//

import SwiftUI
import SwiftData

struct MenuBarContentView: View {
    @ObservedObject private var sessionManager = ConnectionSessionManager.shared
    @ObservedObject private var mountManager = FinderMountManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \ConnectionEntity.updatedAt, order: .reverse) private var connectionEntities: [ConnectionEntity]

    private var prioritizedConnections: [Connection] {
        let all = connectionEntities.map { ConnectionMapper.toDomain($0) }
        let connected = all.filter { sessionManager.isConnected($0.id) }
        let disconnected = all.filter { !sessionManager.isConnected($0.id) }
        return Array((connected + disconnected).prefix(8))
    }

    var body: some View {
        VStack {
            // Internet status banner
            if !NetworkMonitor.shared.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.tr("internet_lost_title"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.red)

                Divider()
            }

            Button {
                openMainWindow()
            } label: {
                Label(L10n.tr("open_macssh"), systemImage: "macwindow")
            }

            Button {
                openMainWindowAndRequestNewConnection()
            } label: {
                Label(L10n.tr("new_connection"), systemImage: "plus.circle")
            }

            Divider()

            if prioritizedConnections.isEmpty {
                Text(L10n.tr("no_servers_configured"))
            } else {
                Text("\(L10n.tr("servers")) (\(prioritizedConnections.count))")

                ForEach(prioritizedConnections) { connection in
                    let isConnected = sessionManager.isConnected(connection.id)
                    let isMounted = mountManager.isMounted(connection.id)

                    Menu {
                        // Info Header
                        Text("\(L10n.tr("host")): \(connection.host):\(String(connection.port))")
                        Text("\(L10n.tr("user")): \(connection.username)")
                        if connection.socksProxyEnabled {
                            let proxyScope = connection.socksProxyAllowLAN ? "LAN + 127.0.0.1" : "127.0.0.1 only"
                            Text("SOCKS5 Proxy: :\(String(connection.socksProxyPort)) (\(proxyScope))")
                        }
                        Text("\(L10n.tr("status")): \(isConnected ? (NetworkMonitor.shared.isConnected ? L10n.tr("connected") : L10n.tr("no_internet")) : L10n.tr("disconnected"))")

                        Divider()

                        if isConnected {
                            Button {
                                Task {
                                    await sessionManager.disconnect(connection.id)
                                }
                            } label: {
                                Label(L10n.tr("disconnect"), systemImage: "bolt.slash.fill")
                            }
                        } else {
                            Button {
                                Task {
                                    let password = sessionManager.getCachedPassword(for: connection.id) ?? ""
                                    do {
                                        try await sessionManager.connect(connection, password: password)
                                        await FinderMountManager.shared.autoMountOnConnectIfEnabled(for: connection, password: password)
                                    } catch {
                                        logError("Failed to connect from menu bar: \(error.localizedDescription)", category: .network)
                                    }
                                }
                            } label: {
                                Label(L10n.tr("connect"), systemImage: "bolt.fill")
                            }
                        }

                        Button {
                            openFileBrowser(for: connection)
                        } label: {
                            Label(L10n.tr("open_file_browser"), systemImage: "folder")
                        }

                        if connection.connectionType.supportsFinderMount {
                            if isMounted {
                                Button {
                                    FinderMountManager.shared.openInFinder(connectionId: connection.id)
                                } label: {
                                    Label(L10n.tr("open_mounted_folder"), systemImage: "externaldrive.fill")
                                }

                                Button {
                                    Task {
                                        await FinderMountManager.shared.unmount(connectionId: connection.id)
                                    }
                                } label: {
                                    Label(L10n.tr("unmount_from_finder"), systemImage: "eject.fill")
                                }
                            } else {
                                Button {
                                    Task {
                                        let password = sessionManager.getCachedPassword(for: connection.id) ?? ""
                                        do {
                                            try await FinderMountManager.shared.mount(connection: connection, password: password)
                                        } catch {
                                            ToastManager.shared.show(
                                                title: L10n.tr("finder_mount_failed"),
                                                message: AppError.from(error).localizedDescription,
                                                type: .error,
                                                duration: 5.0
                                            )
                                        }
                                    }
                                } label: {
                                    Label(L10n.tr("mount_in_finder"), systemImage: "externaldrive.badge.plus")
                                }
                            }
                        }

                        Button {
                            openTerminal(for: connection)
                        } label: {
                            Label(L10n.tr("open_terminal"), systemImage: "terminal")
                        }
                        .disabled(connection.connectionType != .sftp)

                        Button {
                            TerminalLauncherService.openInMacOSTerminal(connection: connection)
                        } label: {
                            Label(L10n.tr("open_in_macos_terminal"), systemImage: "terminal.fill")
                        }
                        .disabled(connection.connectionType != .sftp)
                    } label: {
                        let internetDown = !NetworkMonitor.shared.isConnected
                        let statusIcon = (isConnected || isMounted) ? (internetDown ? "🔴" : "🟢") : "⚪️"
                        let mountBadge = isMounted ? " [Finder]" : ""
                        let proxyBadge = connection.socksProxyEnabled ? " [Proxy :\(String(connection.socksProxyPort))]" : ""
                        Text(verbatim: "\(statusIcon) \(connection.name) (\(connection.host))\(mountBadge)\(proxyBadge)")
                    }
                }
            }

            Divider()

            Button {
                ensureRegularActivation()
                openSettings()
            } label: {
                Label(L10n.tr("settings"), systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                ensureRegularActivation()
                openWindow(id: WindowID.donate)
            } label: {
                Label(L10n.tr("donate"), systemImage: "cup.and.saucer.fill")
            }

            Button {
                ensureRegularActivation()
                openWindow(id: WindowID.about)
            } label: {
                Label(L10n.tr("about"), systemImage: "info.circle")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(L10n.tr("quit"), systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func serverMenuTitle(for connection: Connection, isConnected: Bool) -> String {
        var parts: [String] = []
        parts.append(connection.name)
        parts.append("(\(connection.host))")
        if connection.socksProxyEnabled {
            let scope = connection.socksProxyAllowLAN ? "LAN" : "Local"
            parts.append("[\(scope) Proxy :\(String(connection.socksProxyPort))]")
        }
        parts.append(isConnected ? "[Active]" : "[Disconnected]")
        return parts.joined(separator: " ")
    }

    private func ensureRegularActivation() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMainWindow() {
        ensureRegularActivation()
        if let mainWindow = NSApp.windows.first(where: {
            ($0.identifier?.rawValue.contains(WindowID.main) == true || $0.title == "macSSH") &&
            !$0.className.contains("NSStatusBar") &&
            $0.canBecomeKey
        }) {
            mainWindow.setIsVisible(true)
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: WindowID.main)
    }

    private func openMainWindowAndRequestNewConnection() {
        ensureRegularActivation()
        let hasVisibleMain = NSApp.windows.contains {
            $0.isVisible && (($0.identifier?.rawValue.contains(WindowID.main) == true) || $0.title == "macSSH")
        }
        if hasVisibleMain {
            openMainWindow()
            NotificationCenter.default.post(name: .newConnectionRequested, object: nil)
        } else {
            openWindow(id: WindowID.main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .newConnectionRequested, object: nil)
            }
        }
    }

    private func openFileBrowser(for connection: Connection) {
        ensureRegularActivation()
        let savedPassword = sessionManager.getCachedPassword(for: connection.id) ?? ""
        let windowData = FileBrowserWindowData(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: savedPassword,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            connectionType: connection.connectionType,
            socksProxyEnabled: connection.socksProxyEnabled,
            socksProxyPort: connection.socksProxyPort,
            socksProxyAllowLAN: connection.socksProxyAllowLAN,
            ftpMaxStreams: connection.ftpMaxStreams,
            autoMount: connection.autoMount
        )
        let windowId = WindowManager.shared.storeFileBrowserData(windowData)
        openWindow(id: WindowID.fileBrowser, value: windowId)
    }

    private func openTerminal(for connection: Connection) {
        ensureRegularActivation()
        let savedPassword = sessionManager.getCachedPassword(for: connection.id) ?? ""
        let windowData = TerminalWindowData(
            connectionId: connection.id,
            connectionName: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: savedPassword,
            authMethod: connection.authMethod,
            privateKeyPath: connection.privateKeyPath,
            socksProxyEnabled: connection.socksProxyEnabled,
            socksProxyPort: connection.socksProxyPort,
            socksProxyAllowLAN: connection.socksProxyAllowLAN
        )
        let windowId = WindowManager.shared.storeTerminalData(windowData)
        openWindow(id: WindowID.terminal, value: windowId)
    }
}
