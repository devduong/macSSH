//
//  SidebarView.swift
//  macSSH
//
//  Sidebar view for connection folders - Minimal macOS style with bottom action footer
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var viewModel: ConnectionListViewModel
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var folderToRename: Folder?
    @State private var renameText = ""
    @State private var isShowingRenameAlert = false
    @State private var isShowingSettingsSheet = false
    @State private var isShowingDonateSheet = false
    @State private var isShowingAboutSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Folders and connections list
            List(selection: $viewModel.selectedSidebarItem) {
            // All Connections
            NavigationLink(value: SidebarSelection.allConnections) {
                Label {
                    Text(loc("All Connections", "Tất cả kết nối"))
                } icon: {
                    Image(systemName: "server.rack")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .onDrop(of: [UTType.connection], isTargeted: nil) { providers in
                for provider in providers {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.connection.identifier) { data, _ in
                        guard let data = data else { return }
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        guard let connection = try? decoder.decode(Connection.self, from: data) else { return }
                        Task { @MainActor in
                            await viewModel.moveConnection(connection, to: nil)
                        }
                    }
                }
                return true
            }

            // Folders Section
            Section(loc("Folders", "Thư mục")) {
                ForEach(viewModel.folders) { folder in
                    NavigationLink(value: SidebarSelection.folder(folder.id)) {
                        FolderRowView(
                            folder: folder,
                            connectionCount: viewModel.connectionCount(for: folder.id)
                        )
                    }
                    .onDrop(of: [UTType.connection], isTargeted: nil) { providers in
                        for provider in providers {
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.connection.identifier) { data, _ in
                                guard let data = data else { return }
                                let decoder = JSONDecoder()
                                decoder.dateDecodingStrategy = .iso8601
                                guard let connection = try? decoder.decode(Connection.self, from: data) else { return }
                                Task { @MainActor in
                                    await viewModel.moveConnection(connection, to: folder)
                                }
                            }
                        }
                        return true
                    }
                    .contextMenu {
                        Button {
                            viewModel.requestNewConnection(inFolder: folder.id)
                        } label: {
                            Label(loc("New Connection", "Thêm kết nối mới"), systemImage: "plus.circle")
                        }

                        Divider()

                        Button {
                            folderToRename = folder
                            renameText = folder.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(loc("Rename", "Đổi tên"), systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.confirmDeleteFolder(folder)
                        } label: {
                            Label(loc("Delete", "Xóa"), systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    viewModel.reorderFolders(from: source, to: destination)
                }
            }
        }
        .listStyle(.sidebar)
        .emptyAreaContextMenu {
            [
                EmptyAreaContextMenuItem(
                    title: L10n.tr("new_folder"),
                    systemImage: "folder.badge.plus"
                ) {
                    viewModel.isShowingNewFolderSheet = true
                }
            ]
        }

            Divider()

            // Bottom Footer with Settings, Donate, About
            sidebarFooter
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    viewModel.isShowingNewFolderSheet = true
                } label: {
                    Label(loc("New Folder", "Thư mục mới"), systemImage: "folder.badge.plus")
                }
                .help(loc("New Folder", "Thư mục mới"))
            }
        }
        .alert(loc("Rename Folder", "Đổi tên thư mục"), isPresented: $isShowingRenameAlert) {
            TextField(loc("Folder name", "Tên thư mục"), text: $renameText)
            Button(loc("Rename", "Đổi tên")) {
                let name = renameText.trimmed
                if !name.isEmpty, let folder = folderToRename {
                    Task { await viewModel.renameFolder(folder, to: name) }
                }
                folderToRename = nil
                renameText = ""
            }
            .keyboardShortcut(.defaultAction)
            Button(loc("Cancel", "Hủy"), role: .cancel) {
                folderToRename = nil
                renameText = ""
            }
        } message: {
            Text(loc("Enter a new name for the folder.", "Nhập tên mới cho thư mục."))
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
    }

    // MARK: - Sidebar Bottom Footer

    private var sidebarFooter: some View {
        VStack(spacing: 2) {
            footerButton(
                title: loc("Settings", "Cài đặt"),
                icon: "gearshape",
                color: .secondary
            ) {
                isShowingSettingsSheet = true
            }

            footerButton(
                title: loc("Donate", "Ủng hộ"),
                icon: "cup.and.saucer.fill",
                color: .orange
            ) {
                isShowingDonateSheet = true
            }

            footerButton(
                title: loc("About", "Giới thiệu"),
                icon: "info.circle",
                color: .blue
            ) {
                isShowingAboutSheet = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .excludeFromEmptyAreaContextMenu()
    }

    private func footerButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.001))
        )
    }
}

// MARK: - Folder Row
struct FolderRowView: View {
    let folder: Folder
    let connectionCount: Int

    var body: some View {
        Label {
            Text(folder.name)
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                .resizable()
                .frame(width: 20, height: 20)
        }
        .badge("\(connectionCount)")
    }
}

// MARK: - Preview
#Preview {
    SidebarView(viewModel: DependencyContainer.shared.makeConnectionListViewModel())
        .frame(width: 250)
}
