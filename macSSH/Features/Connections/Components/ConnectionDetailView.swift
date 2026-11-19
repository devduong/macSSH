//
//  ConnectionDetailView.swift
//  macSSH
//
//  Detail panel showing connection info — Apple Contacts style
//

import SwiftUI

struct ConnectionDetailView: View {
    let connection: Connection
    let onConnect: () -> Void
    let onOpenTerminal: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var iconColor: Color {
        connection.connectionType.accentColor
    }

    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Avatar + Name (Contacts-style header)
                headerSection

                // Quick action buttons row (like Contacts' message/call/video/mail)
                quickActionsRow

                // Grouped detail cards
                detailCards

                // Footer metadata
                footerSection
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onEdit) {
                    Text(loc("Edit", "Chỉnh sửa"))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: connection.iconName)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 80, height: 80)

            // Name
            Text(connection.name)
                .font(.system(size: 22, weight: .bold))

            // Connection type subtitle
            Text(connection.connectionType.displayName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: 16) {
            // Open Files
            ContactActionButton(
                icon: "folder.fill",
                label: loc("Files", "Tệp tin"),
                action: onConnect
            )

            // Terminal
            ContactActionButton(
                icon: "terminal.fill",
                label: loc("Terminal", "Terminal"),
                action: onOpenTerminal
            )

            // Duplicate
            ContactActionButton(
                icon: "doc.on.doc",
                label: loc("Duplicate", "Nhân bản"),
                action: onDuplicate
            )

            // Delete
            ContactActionButton(
                icon: "trash",
                label: loc("Delete", "Xóa"),
                isDestructive: true,
                action: onDelete
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Cards

    private var detailCards: some View {
        VStack(spacing: 12) {
            // Connection info card
            sftpCard

            // Tags card
            if !connection.tags.isEmpty {
                tagsCard
            }

            // Notes card
            if let description = connection.description, !description.isEmpty {
                notesCard(description)
            }
        }
    }

    private var sftpCard: some View {
        GroupBox {
            VStack(spacing: 0) {
                contactDetailRow(label: loc("host", "máy chủ"), value: connection.host, icon: "globe")
                Divider().padding(.leading, 36)
                contactDetailRow(label: loc("port", "cổng"), value: String(connection.port), icon: "number")
                Divider().padding(.leading, 36)
                contactDetailRow(label: loc("username", "tài khoản"), value: connection.username, icon: "person")
                Divider().padding(.leading, 36)
                contactDetailRow(label: loc("auth", "xác thực"), value: connection.authMethod.displayName, icon: "key")
                Divider().padding(.leading, 36)
                contactDetailRow(
                    label: loc("save password", "lưu mật khẩu"),
                    value: connection.savePassword ? loc("Enabled (Saved in config file)", "Đã bật (Đã lưu trong file cấu hình)") : loc("Disabled (Prompt on connect)", "Đã tắt (Hỏi khi kết nối)"),
                    icon: connection.savePassword ? "key.fill" : "key.slash"
                )
                if connection.authMethod == .privateKey, let keyPath = connection.privateKeyPath {
                    Divider().padding(.leading, 36)
                    contactDetailRow(label: loc("key path", "đường dẫn khóa"), value: keyPath, icon: "doc.text")
                }
                if connection.socksProxyEnabled {
                    Divider().padding(.leading, 36)
                    let proxyEndpoint: String = {
                        if connection.socksProxyAllowLAN, let lanIP = NetworkUtils.getLocalIPAddress() {
                            return "127.0.0.1:\(String(connection.socksProxyPort)) (LAN: \(lanIP):\(String(connection.socksProxyPort)))"
                        } else {
                            return "127.0.0.1:\(String(connection.socksProxyPort))"
                        }
                    }()
                    contactDetailRow(label: "socks5 proxy", value: proxyEndpoint, icon: "network")
                }
                if connection.autoConnect {
                    Divider().padding(.leading, 36)
                    contactDetailRow(label: L10n.tr("auto_connect"), value: L10n.tr("auto_connect_on_launch"), icon: "bolt.badge.automatic.fill")
                }
                if connection.autoMount && connection.connectionType.supportsAutoMount {
                    Divider().padding(.leading, 36)
                    contactDetailRow(label: L10n.tr("auto_mount"), value: L10n.tr("auto_mount_on_launch"), icon: "externaldrive.fill.badge.checkmark")
                }
            }
        }
    }


    private var tagsCard: some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: "tag")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("tags")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    FlowLayout(spacing: 6) {
                        ForEach(connection.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.fill.tertiary, in: Capsule())
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func notesCard(_ text: String) -> some View {
        GroupBox {
            HStack(alignment: .top) {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("notes")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Detail Row

    private func contactDetailRow(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 2) {
            Text("Created \(connection.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Updated \(connection.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Contact Action Button

private struct ContactActionButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: Circle())

                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isDestructive ? .red : .primary)
        }
        .buttonStyle(.plain)
    }
}
