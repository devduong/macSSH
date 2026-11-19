//
//  FileBrowserView.swift
//  macSSH
//
//  Main file browser view
//

import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @ObservedObject private var mountManager = FinderMountManager.shared
    @Environment(\.openWindow) private var openWindow

    init(viewModel: FileBrowserViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            contentView

            Divider()

            // Status Bar
            statusBar
        }
        .frame(minWidth: 800, minHeight: 480)
        .navigationTitle(viewModel.currentPath == "/" ? viewModel.connection.name : (viewModel.currentPath as NSString).lastPathComponent)
        .navigationSubtitle(viewModel.isConnected ? viewModel.connection.connectionString : "Disconnected")
        .toolbar(id: "browserToolbar") {
            FileBrowserLeadingToolbar(viewModel: viewModel)
            FileBrowserTrailingToolbar(viewModel: viewModel, mountManager: mountManager)
        }
        .task {
            await viewModel.connect()
        }
        .modifier(FileBrowserSheets(viewModel: viewModel))
        .errorAlert($viewModel.error)
        .onDisappear {
            Task {
                await viewModel.disconnect()
            }
        }
        .onChange(of: viewModel.pendingFileInfoWindowId) { _, windowId in
            if let windowId = windowId {
                openWindow(id: WindowID.fileInfo, value: windowId)
                viewModel.clearPendingFileInfoWindow()
            }
        }
        .onChange(of: viewModel.pendingEditorWindowId) { _, windowId in
            if let windowId = windowId {
                openWindow(id: WindowID.fileEditor, value: windowId)
                viewModel.clearPendingEditorWindow()
            }
        }
        .onChange(of: viewModel.pendingTerminalWindowId) { _, windowId in
            if let windowId = windowId {
                openWindow(id: WindowID.terminal, value: windowId)
                viewModel.clearPendingTerminalWindow()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView(message: viewModel.isConnected ? "Loading..." : "Connecting...")

        case .success:
            DualPaneFileBrowserView(
                viewModel: viewModel,
                onOpenEditor: openFileInEditor,
                onGetInfo: showFileInfo
            )

        case .error(let error):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(viewModel.isAuthFailed ? .red : .orange)

                Text(error.localizedDescription)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    if viewModel.isAuthFailed {
                        Button {
                            viewModel.isShowingPasswordPrompt = true
                        } label: {
                            Label("Enter Password", systemImage: "key")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button {
                            Task {
                                await viewModel.connect()
                            }
                        } label: {
                            Text("Try Again")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    } else {
                        Button {
                            Task {
                                if viewModel.isConnected {
                                    await viewModel.refresh()
                                } else {
                                    await viewModel.connect()
                                }
                            }
                        } label: {
                            Text("Try Again")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Connection status
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)

                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Active transfers indicator (clicking opens the popover)
            if viewModel.hasActiveTransfers {
                ActiveTransfersIndicator(viewModel: viewModel)
            }

            // Clipboard status
            if viewModel.hasClipboardItems && !viewModel.hasActiveTransfers {
                ClipboardStatusView(displayText: viewModel.clipboardDisplayText)
            }

            Spacer()

            // File count
            HStack(spacing: 6) {
                Text("\(viewModel.sortedFiles.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if !viewModel.selectedFiles.isEmpty {
                    Text("\(viewModel.selectedFiles.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func openFileInEditor(_ file: RemoteFile) {
        Task {
            do {
                let content = try await viewModel.getFileContent(file)
                viewModel.openEditor(for: file, content: content)
            } catch {
                viewModel.error = AppError.from(error)
            }
        }
    }

    private func showFileInfo(_ file: RemoteFile) {
        viewModel.showFileInfo(file)
    }
}

// MARK: - File Browser Toolbar Sections
private struct FileBrowserLeadingToolbar: CustomizableToolbarContent {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "back", placement: .navigation) {
            Button {
                Task { await viewModel.goBack() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .help("Go Back")
        }

        ToolbarItem(id: "forward", placement: .navigation) {
            Button {
                Task { await viewModel.goForward() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .help("Go Forward")
        }

        ToolbarItem(id: "newItem", placement: .primaryAction) {
            Menu {
                Button {
                    viewModel.requestNewFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.requestNewFile()
                } label: {
                    Label("New File", systemImage: "doc.badge.plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help("New File or Folder")
        }

        ToolbarItem(id: "upload", placement: .primaryAction) {
            Button {
                Task { await viewModel.uploadFiles() }
            } label: {
                Label("Upload", systemImage: "square.and.arrow.up")
            }
            .help("Upload Files")
        }

        ToolbarItem(id: "delete", placement: .primaryAction) {
            Button {
                viewModel.confirmDeleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.selectedFiles.isEmpty)
            .help("Delete Selected")
        }

        ToolbarItem(id: "spacer1", placement: .primaryAction) {
            Spacer()
        }
    }
}

private struct FileBrowserTrailingToolbar: CustomizableToolbarContent {
    @Bindable var viewModel: FileBrowserViewModel
    @ObservedObject var mountManager: FinderMountManager

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "finderMount", placement: .primaryAction) {
            if viewModel.connection.connectionType.supportsFinderMount {
                FinderMountToolbarButton(viewModel: viewModel, mountManager: mountManager)
            }
        }

        ToolbarItem(id: "terminal", placement: .primaryAction) {
            if viewModel.connection.connectionType == .sftp {
                Menu {
                    Button {
                        viewModel.openTerminal()
                    } label: {
                        Label("Open Built-in Terminal", systemImage: "terminal")
                    }

                    Button {
                        TerminalLauncherService.openInMacOSTerminal(connection: viewModel.connection)
                    } label: {
                        Label("Open in macOS Terminal", systemImage: "terminal.fill")
                    }
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .disabled(!viewModel.isConnected)
                .help("Open Terminal options")
            }
        }

        ToolbarItem(id: "transfers", placement: .primaryAction) {
            TransfersToolbarButton(viewModel: viewModel)
        }

        ToolbarItem(id: "hiddenFiles", placement: .primaryAction) {
            Toggle(isOn: $viewModel.showHiddenFiles) {
                Label(
                    viewModel.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                    systemImage: viewModel.showHiddenFiles ? "eye.fill" : "eye.slash"
                )
            }
            .help("Toggle Hidden Files")
        }

        ToolbarItem(id: "sort", placement: .primaryAction) {
            Menu {
                ForEach(RemoteFile.SortCriteria.allCases, id: \.self) { criteria in
                    Button {
                        if viewModel.sortCriteria == criteria {
                            viewModel.sortAscending.toggle()
                        } else {
                            viewModel.sortCriteria = criteria
                            viewModel.sortAscending = true
                        }
                    } label: {
                        HStack {
                            Text(criteria.rawValue)
                            if viewModel.sortCriteria == criteria {
                                Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort Options")
        }
    }
}

// MARK: - Finder Mount Toolbar Button
private struct FinderMountToolbarButton: View {
    @Bindable var viewModel: FileBrowserViewModel
    @ObservedObject var mountManager: FinderMountManager

    private var isMounted: Bool {
        mountManager.isMounted(viewModel.connection.id)
    }

    private var isBusy: Bool {
        mountManager.isMounting(viewModel.connection.id) || mountManager.isUnmounting(viewModel.connection.id)
    }

    var body: some View {
        if isMounted {
            Menu {
                Button {
                    FinderMountManager.shared.openInFinder(connectionId: viewModel.connection.id)
                } label: {
                    Label(L10n.tr("open_mounted_folder"), systemImage: "macwindow")
                }

                Button {
                    Task { await viewModel.unmountFromFinder() }
                } label: {
                    Label(L10n.tr("unmount_from_finder"), systemImage: "eject.fill")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.teal)
                    Text("Finder")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help(L10n.tr("mounted_in_finder"))
        } else {
            Button {
                Task { await viewModel.mountInFinder() }
            } label: {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "externaldrive.badge.plus")
                    }
                    Text("Finder")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .disabled(isBusy)
            .help(L10n.tr("mount_in_finder"))
        }
    }
}

// MARK: - Clipboard Status View
struct ClipboardStatusView: View {
    let displayText: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(displayText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Active Transfers Indicator
struct ActiveTransfersIndicator: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        Button {
            viewModel.isShowingTransfersPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)

                ProgressView(value: viewModel.overallProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 50)

                Text("\(Int(viewModel.overallProgress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Browser Sheets Modifier
private struct FileBrowserSheets: ViewModifier {
    @Bindable var viewModel: FileBrowserViewModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $viewModel.isShowingNewFolderSheet) {
                NameInputSheet.newFolder(
                    onConfirm: { name in
                        Task { await viewModel.createFolder(name: name) }
                    },
                    onCancel: {
                        viewModel.isShowingNewFolderSheet = false
                        viewModel.targetNewItemDirectory = nil
                    }
                )
            }
            .sheet(isPresented: $viewModel.isShowingNewFileSheet) {
                NameInputSheet.newFile(
                    onConfirm: { name in
                        Task { await viewModel.createFile(name: name) }
                    },
                    onCancel: {
                        viewModel.isShowingNewFileSheet = false
                        viewModel.targetNewItemDirectory = nil
                    }
                )
            }
            .sheet(item: $viewModel.viewedFileSession, onDismiss: {
                viewModel.closeFileViewer()
            }) { session in
                FileViewerSheet(
                    file: session.file,
                    localFileURL: session.localURL,
                    connection: viewModel.connection,
                    onOpenInEditor: { content in
                        viewModel.openEditor(for: session.file, content: content)
                    },
                    onClose: {
                        viewModel.closeFileViewer()
                    }
                )
            }
            .sheet(isPresented: $viewModel.isShowingRenameSheet) {
                if let file = viewModel.fileToRename {
                    NameInputSheet.rename(
                        currentName: file.name,
                        onConfirm: { newName in
                            Task { await viewModel.renameFile(file, to: newName) }
                        },
                        onCancel: {
                            viewModel.isShowingRenameSheet = false
                            viewModel.fileToRename = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.isShowingMoveSheet) {
                if let file = viewModel.fileToMove {
                    NameInputSheet.move(
                        fileName: file.name,
                        currentDestination: viewModel.moveDestinationPath,
                        onConfirm: { destination in
                            Task { await viewModel.confirmMove(to: destination) }
                        },
                        onCancel: {
                            viewModel.isShowingMoveSheet = false
                            viewModel.fileToMove = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.isShowingPasswordPrompt) {
                PasswordPromptSheet(
                    connectionName: viewModel.connection.name,
                    errorMessage: viewModel.isAuthFailed ? "Authentication failed. Please check your credentials and try again." : nil,
                    onConnect: { password in
                        viewModel.isShowingPasswordPrompt = false
                        Task { await viewModel.connect(withPassword: password) }
                    },
                    onCancel: {
                        viewModel.isShowingPasswordPrompt = false
                    }
                )
            }
            .alert("Delete Files", isPresented: $viewModel.isShowingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteFiles(viewModel.filesToDelete) }
                }
            } message: {
                let count = viewModel.filesToDelete.count
                Text("Are you sure you want to delete \(count) item\(count == 1 ? "" : "s")? This cannot be undone.")
            }
    }
}

// MARK: - Preview
#Preview {
    FileBrowserView(
        viewModel: DependencyContainer.shared.makeFileBrowserViewModel(
            connection: Connection(name: "Test", host: "localhost", username: "user"),
            sftpSession: SFTPSession(),
            password: "test"
        )
    )
}
