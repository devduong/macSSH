//
//  DualPaneFileBrowserView.swift
//  macSSH
//
//  Dual-pane file browser view with Local Files on the left and Remote Files on the right
//

import SwiftUI

struct DualPaneFileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    let onOpenEditor: (RemoteFile) -> Void
    let onGetInfo: (RemoteFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // MARK: - Left Pane: Local Files
                LocalPaneView(viewModel: viewModel)
                    .frame(minWidth: 350, maxWidth: .infinity)

                // MARK: - Right Pane: Remote Files
                RemotePaneView(
                    viewModel: viewModel,
                    onOpenEditor: onOpenEditor,
                    onGetInfo: onGetInfo
                )
                .frame(minWidth: 350, maxWidth: .infinity)
            }

            // MARK: - Bottom Panel: Upload Queue, Download Queue & Activity Log
            Divider()
            TransferQueueBottomPanel(viewModel: viewModel)
        }
    }
}

// MARK: - Local Pane View
private struct LocalPaneView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var isPathHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)

                Text(L10n.tr("local_files"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.blue)

                if viewModel.localState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Spacer()

                Text("\(viewModel.localState.files.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.06))

            Divider()

            // Navigation Toolbar & Path
            HStack(spacing: 4) {
                // Back button
                Button {
                    Task { await viewModel.localState.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.localState.canGoBack)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Back")

                // Forward button
                Button {
                    Task { await viewModel.localState.goForward() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.localState.canGoForward)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Forward")

                // Up directory
                Button {
                    Task { await viewModel.localState.goUp() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.localState.canGoUp)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Up one level")

                // Home button
                Button {
                    Task { await viewModel.localState.goHome() }
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Home Folder")

                // New Folder
                Button {
                    viewModel.localState.isShowingNewFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("New Local Folder")

                // Refresh
                Button {
                    Task { await viewModel.localState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Refresh")

                Spacer(minLength: 4)

                // Upload Button (Local -> Remote)
                Button {
                    Task { await viewModel.uploadSelectedLocalFiles() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                        Text(L10n.tr("upload_to_remote"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(viewModel.localState.selectedFiles.isEmpty || !viewModel.isConnected)
                .help("Upload selected local files to remote server")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

            // Path Bar
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Local Path", text: $viewModel.localState.pathInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        Task {
                            await viewModel.localState.navigateToPath(viewModel.localState.pathInputText)
                        }
                    }

                if viewModel.localState.pathInputText != viewModel.localState.currentPath {
                    Button {
                        Task {
                            await viewModel.localState.navigateToPath(viewModel.localState.pathInputText)
                        }
                    } label: {
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.textBackgroundColor).opacity(0.5))

            Divider()

            // Local Table View
            ZStack {
                LocalFileTableView(
                    state: viewModel.localState,
                    onUpload: { file in
                        Task { await viewModel.uploadLocalFile(file) }
                    },
                    onNavigate: { url in
                        Task { await viewModel.localState.navigate(to: url) }
                    },
                    onDropRemoteFiles: { destinationURL, remoteFiles in
                        Task {
                            await viewModel.downloadFilesToLocal(remoteFiles, localDirectory: destinationURL)
                        }
                    }
                )

                if viewModel.localState.files.isEmpty && !viewModel.localState.isLoading {
                    EmptyStateView(
                        icon: "folder",
                        title: L10n.tr("no_files_found", default: "No Files Found"),
                        message: L10n.tr("directory_empty", default: "This directory is empty.")
                    )
                }

                if viewModel.localState.isLoading {
                    Color.black.opacity(0.08)
                    ProgressView()
                        .controlSize(.regular)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .sheet(isPresented: $viewModel.localState.isShowingNewFolderSheet) {
            NameInputSheet.newFolder { name in
                Task { await viewModel.localState.createFolder(name: name) }
            } onCancel: {
                viewModel.localState.isShowingNewFolderSheet = false
            }
        }
        .sheet(isPresented: $viewModel.localState.isShowingRenameSheet) {
            if let file = viewModel.localState.fileToRename {
                NameInputSheet.rename(
                    currentName: file.name,
                    onConfirm: { newName in
                        Task { await viewModel.localState.renameFile(file, to: newName) }
                    },
                    onCancel: {
                        viewModel.localState.isShowingRenameSheet = false
                        viewModel.localState.fileToRename = nil
                    }
                )
            }
        }
        .alert(L10n.tr("confirm_delete_selected_title"), isPresented: $viewModel.localState.isShowingDeleteConfirmation) {
            Button(L10n.tr("cancel"), role: .cancel) {}
            Button(L10n.tr("move_to_trash"), role: .destructive) {
                Task { await viewModel.localState.deleteFiles(viewModel.localState.filesToDelete) }
            }
        } message: {
            let count = viewModel.localState.filesToDelete.count
            Text(L10n.tr("confirm_delete_selected_desc", count))
        }
    }
}

// MARK: - Remote Pane View
private struct RemotePaneView: View {
    @Bindable var viewModel: FileBrowserViewModel
    let onOpenEditor: (RemoteFile) -> Void
    let onGetInfo: (RemoteFile) -> Void
    @State private var pathInputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)

                Text(L10n.tr("remote_files"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)

                Text("(\(viewModel.connection.name))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if viewModel.isRemoteLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Spacer()

                Text("\(viewModel.sortedFiles.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.06))

            Divider()

            // Navigation Toolbar & Path
            HStack(spacing: 4) {
                // Back button
                Button {
                    Task { await viewModel.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.canGoBack)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Back")

                // Forward button
                Button {
                    Task { await viewModel.goForward() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.canGoForward)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Forward")

                // Up directory
                Button {
                    Task { await viewModel.goUp() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(!viewModel.canGoUp)
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Up one level")

                // Home button
                Button {
                    Task { await viewModel.navigateTo("~") }
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Home Folder (~)")

                // New Folder
                Button {
                    viewModel.requestNewFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("New Remote Folder")

                // New File
                Button {
                    viewModel.requestNewFile()
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("New Remote File")

                // Refresh
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .help("Refresh")

                Spacer(minLength: 4)

                // View File Button (SFTP, FTP, SMB)
                Button {
                    if let firstFile = viewModel.selectedRemoteFiles.first(where: { $0.isFile }) {
                        Task { await viewModel.viewFile(firstFile) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11))
                        Text(loc("View", "Xem tệp"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(!viewModel.selectedRemoteFiles.contains(where: { $0.isFile }) || !viewModel.isConnected)
                .help(loc("View selected remote file", "Xem nội dung tệp đã chọn"))

                // Download Button (Remote -> Local)
                Button {
                    Task { await viewModel.downloadSelectedRemoteFiles() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 11))
                        Text("Download")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .disabled(viewModel.selectedRemoteFiles.isEmpty || !viewModel.isConnected)
                .help("Download selected remote files to local directory")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

            // Path Bar (Direct text input, same style as Local pane)
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Remote Path", text: $pathInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        Task {
                            await viewModel.navigateTo(pathInputText)
                        }
                    }

                if pathInputText != viewModel.currentPath {
                    Button {
                        Task {
                            await viewModel.navigateTo(pathInputText)
                        }
                    } label: {
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .onAppear {
                pathInputText = viewModel.currentPath
            }
            .onChange(of: viewModel.currentPath) { _, newPath in
                pathInputText = newPath
            }

            Divider()

            // Remote Table View
            ZStack {
                FileListView(
                    viewModel: viewModel,
                    onOpenEditor: onOpenEditor,
                    onGetInfo: onGetInfo
                )

                if viewModel.isRemoteLoading {
                    Color.black.opacity(0.08)
                    ProgressView()
                        .controlSize(.regular)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
