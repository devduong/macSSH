//
//  ConnectionRowView.swift
//  macSSH
//
//  List row for the connection list column
//

import SwiftUI

struct ConnectionRowView: View {
    let connection: Connection
    var folderName: String? = nil
    var isActive: Bool = false
    var isConnecting: Bool = false
    var onProxyToggle: (() -> Void)? = nil
    var onSavePasswordToggle: (() -> Void)? = nil
    var onTerminal: (() -> Void)? = nil
    var onFileBrowser: (() -> Void)? = nil
    var onMountInFinder: (() -> Void)? = nil
    var onUnmountFromFinder: (() -> Void)? = nil
    var onAutoConnectToggle: (() -> Void)? = nil
    var onAutoMountToggle: (() -> Void)? = nil

    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var sessionManager = ConnectionSessionManager.shared
    @ObservedObject private var mountManager = FinderMountManager.shared
    @State private var isHovered = false
    @State private var isPulsing = false

    private var isMountedInFinder: Bool {
        mountManager.isMounted(connection.id)
    }

    private var isMountingInFinder: Bool {
        mountManager.isMounting(connection.id) || mountManager.isUnmounting(connection.id)
    }

    /// Whether this active connection is affected by internet outage
    private var isInternetDown: Bool {
        (isActive || isMountedInFinder) && !sessionManager.isInternetAvailable
    }

    private var iconColor: Color {
        if isConnecting || isMountingInFinder { return .orange }
        if isInternetDown { return .red }
        if isActive { return .green }
        if isMountedInFinder { return .teal }
        return connection.connectionType.accentColor
    }

    private var protocolBadgeColor: Color {
        switch connection.connectionType {
        case .sftp: return .secondary
        case .ftp: return .teal
        case .smb: return .indigo
        }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                // Icon with status badge overlay
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: connection.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(iconColor)
                        .frame(width: 34, height: 34)
                        .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    if isConnecting || isMountingInFinder {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 10, height: 10)
                            .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                            .offset(x: 2, y: 2)
                    } else {
                        Circle()
                            .fill(isInternetDown ? Color.red : (isActive ? Color.green : (isMountedInFinder ? Color.teal : Color.secondary.opacity(0.35))))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .opacity(isInternetDown && isPulsing ? 0.4 : 1.0)
                            .offset(x: 2, y: 2)
                    }
                }

                // Text content
                VStack(alignment: .leading, spacing: 2.5) {
                    // Name row with badges
                    HStack(spacing: 6) {
                        Text(connection.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        // Action buttons (always visible)
                        HStack(spacing: 4) {
                            // File Browser button (available for SFTP, FTP, SMB)
                            Button(action: { onFileBrowser?() }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 20)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help(loc("Open File Browser", "Mở trình duyệt tệp"))

                            // Finder Mount button (FTP & SFTP via local WebDAV loopback)
                            if connection.connectionType.supportsFinderMount {
                                Button(action: { onMountInFinder?() }) {
                                    Group {
                                        if isMountingInFinder {
                                            ProgressView()
                                                .controlSize(.mini)
                                        } else {
                                            Image(systemName: isMountedInFinder ? "externaldrive.fill" : "externaldrive")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(isMountedInFinder ? Color.teal : Color.secondary)
                                        }
                                    }
                                    .frame(width: 24, height: 20)
                                    .background(
                                        isMountedInFinder ? AnyShapeStyle(Color.teal.opacity(0.16)) : AnyShapeStyle(.quaternary),
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isMountingInFinder)
                                .help(isMountedInFinder ? L10n.tr("open_mounted_folder") : L10n.tr("mount_in_finder"))

                                if isMountedInFinder {
                                    Button(action: { onUnmountFromFinder?() }) {
                                        Image(systemName: "eject.fill")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.orange)
                                            .frame(width: 22, height: 20)
                                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.tr("unmount_from_finder"))
                                }
                            }

                            // Terminal button (SFTP/SSH only)
                            if connection.connectionType.supportsTerminal {
                                Button(action: { onTerminal?() }) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, height: 20)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help(loc("Open Terminal", "Mở Terminal"))
                            }
                        }

                        // Password saved badge (shown when savePassword is true or on hover)
                        if isHovered || connection.savePassword {
                            Button(action: { onSavePasswordToggle?() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: connection.savePassword ? "key.fill" : "key.slash")
                                        .font(.system(size: 8))
                                    if connection.savePassword {
                                        Text(loc("Saved", "Đã lưu pass"))
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(connection.savePassword ? .orange : .secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    connection.savePassword
                                        ? Color.orange.opacity(0.15)
                                        : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(
                                    connection.savePassword ? Color.orange.opacity(0.4) : Color.clear,
                                    lineWidth: 0.5
                                ))
                            }
                            .buttonStyle(.plain)
                            .help(connection.savePassword ? loc("Password saved. Click to disable", "Đã lưu mật khẩu. Bấm để tắt") : loc("Click to enable password saving", "Bấm để bật lưu mật khẩu"))
                            .transition(.opacity)
                        }

                        // Proxy quick-toggle (shown on hover for SFTP connections)
                        if connection.connectionType.supportsSocksProxy && (isHovered || connection.socksProxyEnabled) {
                            Button(action: { onProxyToggle?() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: connection.socksProxyEnabled ? "wifi" : "wifi.slash")
                                        .font(.system(size: 8))
                                    Text(verbatim: connection.socksProxyEnabled ? "SOCKS5 :\(String(connection.socksProxyPort))" : "SOCKS5")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(connection.socksProxyEnabled ? .purple : .secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    connection.socksProxyEnabled
                                        ? Color.purple.opacity(0.15)
                                        : Color.secondary.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(
                                    connection.socksProxyEnabled ? Color.purple.opacity(0.4) : Color.clear,
                                    lineWidth: 0.5
                                ))
                            }
                            .buttonStyle(.plain)
                            .help(connection.socksProxyEnabled ? loc("Disable SOCKS5 Proxy", "Tắt SOCKS5 Proxy") : loc("Enable SOCKS5 Proxy", "Bật SOCKS5 Proxy"))
                            .transition(.opacity)
                        }

                        // Status Badge
                        if isConnecting {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text(loc("Connecting", "Đang kết nối"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        } else if isInternetDown {
                            HStack(spacing: 4) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 8, weight: .bold))
                                Text(L10n.tr("no_internet"))
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .opacity(isPulsing ? 0.6 : 1.0)
                        } else if isActive {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text(loc("Active", "Đang chạy"))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        } else if isMountedInFinder {
                            HStack(spacing: 4) {
                                Circle().fill(Color.teal).frame(width: 5, height: 5)
                                Text("Finder")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.teal)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.teal.opacity(0.12), in: Capsule())
                        } else {
                            Text(connection.connectionType.badgeName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(protocolBadgeColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }

                    // Host details
                    HStack(spacing: 6) {
                        if let folder = folderName, !folder.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill").font(.system(size: 9))
                                Text(folder).font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }

                        Text(connection.connectionString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Description
                    if let desc = connection.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // Bottom row: Auth + Tags (left) and Quick Settings (right)
                    HStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Image(systemName: connection.authMethod == .privateKey ? "key.fill" : "lock.fill")
                                .font(.system(size: 8))
                            Text(connection.authMethod == .privateKey ? "Key" : "Password")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                        if !connection.tags.isEmpty {
                            ForEach(connection.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            if connection.tags.count > 3 {
                                Text("+\(connection.tags.count - 3)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 6)

                        HStack(spacing: 5) {
                            quickSettingToggleButton(
                                title: L10n.tr("auto_connect"),
                                systemImage: connection.autoConnect ? "bolt.badge.automatic.fill" : "bolt.badge.automatic",
                                isEnabled: connection.autoConnect,
                                activeColor: .green,
                                helpText: connection.autoConnect
                                    ? L10n.tr("auto_connect_on_help")
                                    : L10n.tr("auto_connect_off_help"),
                                action: onAutoConnectToggle
                            )

                            if connection.connectionType.supportsAutoMount {
                                quickSettingToggleButton(
                                    title: L10n.tr("auto_mount"),
                                    systemImage: connection.autoMount ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.checkmark",
                                    isEnabled: connection.autoMount,
                                    activeColor: .teal,
                                    helpText: connection.autoMount
                                        ? L10n.tr("auto_mount_on_help")
                                        : L10n.tr("auto_mount_off_help"),
                                    action: onAutoMountToggle
                                )
                            }
                        }
                    }
                    .padding(.top, 1)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.vertical, 5)
        }
        .frame(height: 86)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onChange(of: isInternetDown) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }

    private func quickSettingToggleButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        activeColor: Color,
        helpText: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 8.5, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? activeColor : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isEnabled ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    isEnabled ? activeColor.opacity(0.45) : Color.secondary.opacity(0.22),
                    lineWidth: 0.5
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
