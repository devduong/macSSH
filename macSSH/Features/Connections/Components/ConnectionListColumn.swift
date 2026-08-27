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
    @ObservedObject private var windowManager = WindowManager.shared

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingView(message: "Loading connections...")

            case .success:
                // Always show connectionList so .searchable toolbar stays attached.
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { _ = try? await ConfigurationService.shared.requestNewConfiguration() }
                    } label: {
                        Label("New Configuration", systemImage: "doc.badge.plus")
                    }

                    Button {
                        Task { try? await ConfigurationService.shared.save() }
                    } label: {
                        Label("Save Configuration", systemImage: "tray.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: .command)

                    Button {
                        Task { _ = try? await ConfigurationService.shared.saveAs() }
                    } label: {
                        Label("Save Configuration As…", systemImage: "folder.badge.plus")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button {
                        Task { _ = try? await ConfigurationService.shared.loadConfiguration() }
                    } label: {
                        Label("Open Configuration…", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Divider()

                    Button {
                        Task { _ = try? await ConfigurationService.shared.exportSettings() }
                    } label: {
                        Label("Export Settings to JSON…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        Task { _ = try? await ConfigurationService.shared.importSettings(replaceExisting: false) }
                    } label: {
                        Label("Import Settings from JSON…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Configuration", systemImage: "gearshape")
                }
                .help("Save, Open, Import, or Export Configuration")

                Button {
                    viewModel.isShowingNewConnectionSheet = true
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .help("New Connection")

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
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("Toggle Activity Log (Cmd+Shift+L)", "Bật/Tắt khung nhật ký (Cmd+Shift+L)"))
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }

    private var listTitle: String {
        switch viewModel.selectedSidebarItem {
        case .allConnections:
            return "All Connections"
        case .folder(let id):
            return viewModel.folders.first { $0.id == id }?.name ?? "Folder"
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.searchText.isEmpty {
            switch viewModel.selectedSidebarItem {
            case .allConnections:
                EmptyStateView(
                    icon: "server.rack",
                    title: "No Connections",
                    message: "Add a new SSH connection to get started\nwith remote file management.",
                    actionTitle: "Add Connection"
                ) {
                    viewModel.isShowingNewConnectionSheet = true
                }
            case .folder:
                EmptyStateView(
                    icon: "folder",
                    title: "Empty Folder",
                    message: "This folder has no connections.\nDrag connections here or create a new one.",
                    actionTitle: "Add Connection"
                ) {
                    viewModel.isShowingNewConnectionSheet = true
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
                        Label(loc("Disconnect", "Ngắt kết nối"), systemImage: "bolt.slash.fill")
                    }
                } else {
                    Button {
                        viewModel.connectToServer(connection)
                    } label: {
                        Label(loc("Connect", "Kết nối"), systemImage: "bolt.fill")
                    }
                }

                Button {
                    viewModel.requestFileBrowser(for: connection)
                } label: {
                    Label(loc("Open File Browser", "Mở trình duyệt tệp"), systemImage: "folder")
                }

                Button {
                    viewModel.requestTerminal(for: connection)
                } label: {
                    Label(loc("Open Terminal", "Mở Terminal"), systemImage: "terminal")
                }
                .disabled(connection.connectionType != .sftp)

                Button {
                    TerminalLauncherService.openInMacOSTerminal(connection: connection)
                } label: {
                    Label(loc("Open in macOS Terminal", "Mở trong macOS Terminal"), systemImage: "terminal.fill")
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

                Button {
                    Task { await viewModel.toggleProxy(connection) }
                } label: {
                    Label(
                        connection.socksProxyEnabled ? loc("Disable SOCKS5 Proxy", "Tắt SOCKS5 Proxy") : loc("Enable SOCKS5 Proxy", "Bật SOCKS5 Proxy"),
                        systemImage: connection.socksProxyEnabled ? "wifi.slash" : "wifi"
                    )
                }

                Divider()

                Button {
                    viewModel.editConnection(connection)
                } label: {
                    Label(loc("Edit", "Chỉnh sửa"), systemImage: "pencil")
                }

                Button {
                    Task { await viewModel.duplicateConnection(connection) }
                } label: {
                    Label(loc("Duplicate", "Nhân bản"), systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    Task { await viewModel.deleteConnection(connection) }
                } label: {
                    Label(loc("Delete", "Xóa"), systemImage: "trash")
                }
            }
            .tag(connection.id)
        }
        .listStyle(.inset)
        .searchable(text: $viewModel.searchText, prompt: "Search connections")
        .overlay {
            // Empty state overlay — shown when list has no results
            if viewModel.filteredConnections.isEmpty {
                emptyStateView
            }
        }
        .background(
            Color.clear
                .contextMenu {
                    Button {
                        viewModel.isShowingNewConnectionSheet = true
                    } label: {
                        Label("New SSH Connection", systemImage: "plus.circle.fill")
                    }
                    Button {
                        viewModel.isShowingNewFolderSheet = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
        )
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
