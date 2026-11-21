//
//  ConnectionListColumn.swift
//  macSSH
//
//  List view displaying connections for the middle column (Apple Notes style)
//

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionListColumn: View {
    @Bindable var viewModel: ConnectionListViewModel
    @ObservedObject private var sessionManager = ConnectionSessionManager.shared
    @ObservedObject private var mountManager = FinderMountManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var configService = ConfigurationService.shared
    @State private var updateService = UpdateService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        switch appearanceManager.currentAppearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    var body: some View {
        let _ = l10n.currentLanguage

        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingView(message: "Loading connections...")

            case .success:
                // Always show connectionList so UI stays stable across empty searches.
                // Use safeAreaInset to avoid clipping/overlapping the top navigation title.
                connectionList
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if viewModel.isShowingLogPanel {
                            VStack(spacing: 0) {
                                Divider()
                                MainLogBottomPanel(isPresented: $viewModel.isShowingLogPanel)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

            case .error(let error):
                ErrorView(error: error) {
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(listTitle)
        .navigationSubtitle("\(viewModel.filteredConnections.count) connections")
        .background {
            // Local Cmd+F shortcut to focus the toolbar search field without conflicting with FileEditorView
            Button("") {
                NotificationCenter.default.post(name: .focusConnectionSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.requestNewConnection()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.tr("new_connection"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .help(L10n.tr("new_connection"))

                Button {
                    Task { try? await ConfigurationService.shared.save() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text(L10n.tr("save_configuration"))
                            .font(.system(size: 12, weight: .medium))
                        if configService.hasUnsavedChanges {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .help(L10n.tr("save_configuration"))

                Button {
                    Task { _ = try? await ConfigurationService.shared.requestNewConfiguration() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                        Text(L10n.tr("new_configuration"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .help(L10n.tr("new_configuration"))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isShowingLogPanel.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isShowingLogPanel ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.isShowingLogPanel ? Color.accentColor : Color.secondary)
                        Text(loc("Logs", "Nhật ký"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .fixedSize()
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("Toggle Activity Log (Cmd+Shift+L)", "Bật/Tắt khung nhật ký (Cmd+Shift+L)"))

                ToolbarSearchField(
                    text: $viewModel.searchText,
                    prompt: L10n.tr("search_connections")
                )
                .frame(width: 175)

                Button {
                    appearanceManager.toggleLightDark(currentlyDark: isDarkMode)
                } label: {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDarkMode ? Color.yellow : Color.orange)
                }
                .help(isDarkMode ? L10n.tr("switch_to_light") : L10n.tr("switch_to_dark"))

                if let available = updateService.availableUpdate {
                    Button {
                        updateService.showAvailableUpdatePrompt()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.primary)
                                .padding(.top, 2)
                                .padding(.trailing, 3)

                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                                .overlay(
                                    Circle()
                                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.2)
                                )
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .hoverTooltip(L10n.tr("update_available_toolbar_help", available.version))
                    .help(L10n.tr("update_available_toolbar_help", available.version))
                }
            }
        }
    }

    private var listTitle: String {
        switch viewModel.selectedSidebarItem {
        case .allConnections:
            return L10n.tr("all_connections")
        case .folder(let id):
            return viewModel.folders.first { $0.id == id }?.name ?? L10n.tr("folder")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.searchText.isEmpty {
            switch viewModel.selectedSidebarItem {
            case .allConnections:
                EmptyStateView(
                    icon: "server.rack",
                    title: L10n.tr("no_connections"),
                    message: L10n.tr("no_connections_desc"),
                    actionTitle: L10n.tr("add_connection")
                ) {
                    viewModel.requestNewConnection()
                }
            case .folder:
                EmptyStateView(
                    icon: "folder",
                    title: loc("Empty Folder", "Thư mục trống"),
                    message: loc("This folder has no connections.\nDrag connections here or create a new one.", "Thư mục này chưa có kết nối nào.\nKéo kết nối vào đây hoặc tạo mới."),
                    actionTitle: L10n.tr("add_connection")
                ) {
                    viewModel.requestNewConnection()
                }
            }
        } else {
            EmptyStateView.noSearchResults
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedConnectionId },
            set: { newId in
                if let newId = newId {
                    if viewModel.selectedConnectionId == newId {
                        // Second click on already selected item -> Show details
                        viewModel.activeDetailConnectionId = newId
                    } else {
                        // First click on a different item -> Select only, hide details
                        viewModel.selectedConnectionId = newId
                        viewModel.activeDetailConnectionId = nil
                    }
                } else {
                    viewModel.selectedConnectionId = nil
                    viewModel.activeDetailConnectionId = nil
                }
            }
        )
    }

    private var connectionList: some View {
        List(viewModel.filteredConnections, selection: selectionBinding) { connection in
            ConnectionRowView(
                connection: connection,
                folderName: viewModel.folders.first { $0.id == connection.folderId }?.name,
                isActive: sessionManager.isConnected(connection.id),
                isConnecting: sessionManager.isConnecting(connection.id),
                onProxyToggle: {
                    Task { await viewModel.toggleProxy(connection) }
                },
                onSavePasswordToggle: {
                    Task { await viewModel.toggleSavePassword(connection) }
                },
                onTerminal: {
                    viewModel.requestTerminal(for: connection)
                },
                onFileBrowser: {
                    viewModel.requestFileBrowser(for: connection)
                },
                onMountInFinder: {
                    viewModel.requestFinderMount(for: connection)
                },
                onUnmountFromFinder: {
                    viewModel.unmountFromFinder(connection)
                },
                onAutoConnectToggle: {
                    Task { await viewModel.toggleAutoConnect(connection) }
                },
                onAutoMountToggle: {
                    Task { await viewModel.toggleAutoMount(connection) }
                }
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                viewModel.requestFileBrowser(for: connection)
            })
            .simultaneousGesture(TapGesture().onEnded {
                if viewModel.selectedConnectionId == connection.id {
                    viewModel.activeDetailConnectionId = connection.id
                } else {
                    viewModel.selectedConnectionId = connection.id
                    viewModel.activeDetailConnectionId = nil
                }
            })
            .onDrag {
                // Use NSItemProvider for cross-column drag in NavigationSplitView
                let provider = NSItemProvider()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(connection) {
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.connection.identifier,
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                }
                return provider
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await viewModel.deleteConnection(connection) }
                } label: {
                    Image(systemName: "trash")
                }
            }
            .contextMenu {
                if sessionManager.isConnected(connection.id) {
                    Button {
                        viewModel.disconnectConnection(connection)
                    } label: {
                        Label(L10n.tr("disconnect"), systemImage: "bolt.slash.fill")
                    }
                } else {
                    Button {
                        viewModel.connectToServer(connection)
                    } label: {
                        Label(L10n.tr("connect"), systemImage: "bolt.fill")
                    }
                }

                Button {
                    viewModel.requestFileBrowser(for: connection)
                } label: {
                    Label(L10n.tr("open_file_browser"), systemImage: "folder")
                }

                if connection.connectionType.supportsFinderMount {
                    if mountManager.isMounted(connection.id) {
                        Button {
                            FinderMountManager.shared.openInFinder(connectionId: connection.id)
                        } label: {
                            Label(L10n.tr("open_mounted_folder"), systemImage: "externaldrive.fill")
                        }

                        Button {
                            viewModel.unmountFromFinder(connection)
                        } label: {
                            Label(L10n.tr("unmount_from_finder"), systemImage: "eject.fill")
                        }
                    } else {
                        Button {
                            viewModel.requestFinderMount(for: connection)
                        } label: {
                            Label(L10n.tr("mount_in_finder"), systemImage: "externaldrive.badge.plus")
                        }
                    }
                }

                Button {
                    viewModel.requestTerminal(for: connection)
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

                Divider()

                Button {
                    Task { await viewModel.toggleSavePassword(connection) }
                } label: {
                    Label(
                        connection.savePassword ? loc("Disable Save Password", "Tắt lưu mật khẩu") : loc("Enable Save Password", "Bật lưu mật khẩu"),
                        systemImage: connection.savePassword ? "key.slash" : "key.fill"
                    )
                }

                if connection.connectionType.supportsSocksProxy {
                    Button {
                        Task { await viewModel.toggleProxy(connection) }
                    } label: {
                        Label(
                            connection.socksProxyEnabled ? loc("Disable SOCKS5 Proxy", "Tắt SOCKS5 Proxy") : loc("Enable SOCKS5 Proxy", "Bật SOCKS5 Proxy"),
                            systemImage: connection.socksProxyEnabled ? "wifi.slash" : "wifi"
                        )
                    }
                }

                Button {
                    Task { await viewModel.toggleAutoConnect(connection) }
                } label: {
                    Label(
                        connection.autoConnect ? L10n.tr("disable_auto_connect") : L10n.tr("enable_auto_connect"),
                        systemImage: connection.autoConnect ? "bolt.badge.automatic.fill" : "bolt.badge.automatic"
                    )
                }

                if connection.connectionType.supportsAutoMount {
                    Button {
                        Task { await viewModel.toggleAutoMount(connection) }
                    } label: {
                        Label(
                            connection.autoMount ? L10n.tr("disable_auto_mount") : L10n.tr("enable_auto_mount"),
                            systemImage: connection.autoMount ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.checkmark"
                        )
                    }
                }

                Divider()

                Button {
                    viewModel.editConnection(connection)
                } label: {
                    Label(L10n.tr("edit"), systemImage: "pencil")
                }

                Button {
                    Task { await viewModel.duplicateConnection(connection) }
                } label: {
                    Label(L10n.tr("duplicate"), systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    Task { await viewModel.deleteConnection(connection) }
                } label: {
                    Label(L10n.tr("delete"), systemImage: "trash")
                }
            }
            .tag(connection.id)
        }
        .listStyle(.inset)
        .overlay {
            // Empty state overlay — shown when list has no results
            if viewModel.filteredConnections.isEmpty {
                emptyStateView
            }
        }
        .emptyAreaContextMenu {
            [
                EmptyAreaContextMenuItem(
                    title: L10n.tr("new_connection"),
                    systemImage: "plus.circle.fill"
                ) {
                    viewModel.requestNewConnection()
                }
            ]
        }
        .onKeyPress(.return) {
            if let connection = viewModel.selectedConnection {
                if viewModel.activeDetailConnectionId == connection.id {
                    viewModel.connectToServer(connection)
                } else {
                    viewModel.activeDetailConnectionId = connection.id
                }
                return .handled
            }
            return .ignored
        }
        .onDeleteCommand {
            if let connection = viewModel.selectedConnection {
                Task { await viewModel.deleteConnection(connection) }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ConnectionListColumn(viewModel: DependencyContainer.shared.makeConnectionListViewModel())
}
