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
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @Environment(\.openWindow) private var openWindow
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

            Divider()

            if prioritizedConnections.isEmpty {
                Text(L10n.tr("no_servers_configured"))
            } else {
                Text("\(L10n.tr("servers")) (\(prioritizedConnections.count))")

                ForEach(prioritizedConnections) { connection in
                    let isConnected = sessionManager.isConnected(connection.id)

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
                                    try? await sessionManager.connect(connection, password: password)
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
                        let statusIcon = isConnected ? (internetDown ? "🔴" : "🟢") : "⚪️"
                        Text(verbatim: "\(statusIcon) \(connection.name) (\(connection.host))\(connection.socksProxyEnabled ? " [Proxy :\(String(connection.socksProxyPort))]" : "")")
                    }
                }
            }

            Divider()

            Button {
                openMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .settingsRequested, object: nil)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } label: {
                Label(L10n.tr("settings"), systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                openMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .donateRequested, object: nil)
                }
            } label: {
                Label(L10n.tr("donate"), systemImage: "cup.and.saucer.fill")
            }

            Button {
                openMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .aboutRequested, object: nil)
                }
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
        for window in NSApp.windows {
            if !window.title.contains("Terminal") &&
               !window.title.contains("Editor") &&
               !window.title.contains("Info") &&
               !window.className.contains("NSStatusBar") &&
               window.canBecomeKey {
                window.setIsVisible(true)
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        openWindow(id: WindowID.main)
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
            socksProxyAllowLAN: connection.socksProxyAllowLAN
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
