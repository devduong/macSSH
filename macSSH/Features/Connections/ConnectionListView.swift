//
//  ConnectionListView.swift
//  macSSH
//
//  Main view for managing SSH connections
//

import SwiftUI

struct ConnectionListView: View {
    @Bindable var viewModel: ConnectionListViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var newFolderName = ""
    @State private var isShowingAboutSheet = false
    @State private var isShowingDonateSheet = false
    @State private var isShowingSettingsSheet = false

    init(viewModel: ConnectionListViewModel) {
        self.viewModel = viewModel
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let connection = viewModel.activeDetailConnection {
            ConnectionDetailView(
                connection: connection,
                onConnect: {
                    viewModel.requestFileBrowser(for: connection)
                },
                onOpenTerminal: {
                    viewModel.requestTerminal(for: connection)
                },
                onEdit: {
                    viewModel.editConnection(connection)
                },
                onDuplicate: {
                    Task {
                        await viewModel.duplicateConnection(connection)
                    }
                },
                onDelete: {
                    Task {
                        await viewModel.deleteConnection(connection)
                    }
                }
            )
        } else {
            ContentUnavailableView(
                "No Connection Selected",
                systemImage: "server.rack",
                description: Text("Double-click or press Return on a connection to view details.")
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Color.clear.frame(width: 0, height: 0)
                }
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            ConnectionListColumn(viewModel: viewModel)
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: viewModel.selectedSidebarItem) {
            viewModel.selectedConnectionId = nil
            viewModel.activeDetailConnectionId = nil
        }
        .task {
            await viewModel.loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .configurationDataDidChange)) { _ in
            Task {
                await viewModel.loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newConnectionRequested)) { _ in
            viewModel.isShowingNewConnectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFolderRequested)) { _ in
            viewModel.isShowingNewFolderSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
            isShowingSettingsSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .donateRequested)) { _ in
            isShowingDonateSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aboutRequested)) { _ in
            isShowingAboutSheet = true
        }
        .sheet(isPresented: $isShowingSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingDonateSheet) {
            DonateSheetView()
        }
        .sheet(isPresented: $isShowingAboutSheet) {
            AboutSheetView()
        }
        .sheet(isPresented: $viewModel.isShowingNewConnectionSheet) {
            ConnectionFormSheet(
                mode: .create,
                folders: viewModel.folders,
                onSave: { connection, password in
                    Task {
                        await viewModel.saveConnection(connection, password: password)
                    }
                },
                onCancel: {
                    viewModel.isShowingNewConnectionSheet = false
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingEditConnectionSheet) {
            if let connection = viewModel.connectionToEdit {
                ConnectionFormSheet(
                    mode: .edit(connection),
                    savedPassword: viewModel.getSavedPassword(for: connection),
                    folders: viewModel.folders,
                    onSave: { updatedConnection, password in
                        Task {
                            await viewModel.updateConnection(updatedConnection, password: password)
                        }
                    },
                    onCancel: {
                        viewModel.isShowingEditConnectionSheet = false
                        viewModel.connectionToEdit = nil
                    }
                )
            }
        }
        .alert(L10n.tr("new_folder"), isPresented: $viewModel.isShowingNewFolderSheet) {
            TextField(L10n.tr("folder_name"), text: $newFolderName)
            Button(L10n.tr("create")) {
                let name = newFolderName.trimmed
                if !name.isEmpty {
                    Task { await viewModel.createFolder(name: name) }
                }
                newFolderName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.tr("cancel"), role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text(L10n.tr("enter_folder_name_desc"))
        }
        .sheet(isPresented: $viewModel.isShowingPasswordPrompt) {
            if let connection = viewModel.connectionToConnect {
                PasswordPromptSheet(
                    connectionName: connection.name,
                    errorMessage: viewModel.authErrorMessage,
                    onConnect: { password in
                        viewModel.connectWithPassword(password)
                    },
                    onCancel: {
                        viewModel.cancelConnect()
                    }
                )
            }
        }
        .alert(L10n.tr("delete_folder"), isPresented: $viewModel.isShowingDeleteFolderAlert) {
            Button(L10n.tr("cancel"), role: .cancel) {
                viewModel.cancelDeleteFolder()
            }
            Button(L10n.tr("delete"), role: .destructive) {
                if let folder = viewModel.folderToDelete {
                    Task {
                        await viewModel.deleteFolder(folder)
                    }
                }
            }
        } message: {
            if let folder = viewModel.folderToDelete {
                Text(L10n.tr("delete_folder_desc", folder.name))
            }
        }
        .errorAlert($viewModel.error)
        .onChange(of: viewModel.pendingWindowId) { _, windowId in
            if let windowId = windowId {
                logInfo("Opening file browser window with ID: \(windowId)", category: .ui)
                openWindow(id: WindowID.fileBrowser, value: windowId)
                viewModel.clearPendingWindow()
            }
        }
        .onChange(of: viewModel.pendingTerminalWindowId) { _, windowId in
            if let windowId = windowId {
                logInfo("Opening terminal window with ID: \(windowId)", category: .ui)
                openWindow(id: WindowID.terminal, value: windowId)
                viewModel.clearPendingTerminalWindow()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ConnectionListView(viewModel: DependencyContainer.shared.makeConnectionListViewModel())
}
