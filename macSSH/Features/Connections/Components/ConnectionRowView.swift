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

    private enum RowMetrics {
        static let rowHeight: CGFloat = 88
        static let mainIconSize: CGFloat = 36
        static let mainIconFont: CGFloat = 19
        static let mainIconCornerRadius: CGFloat = 8
        static let mainStatusDotSize: CGFloat = 9.5

        // ~1.3x original size (2x reduced by 35%)
        static let actionButtonWidth: CGFloat = 31
        static let ejectButtonWidth: CGFloat = 29
        static let actionButtonHeight: CGFloat = 26
        static let actionButtonCornerRadius: CGFloat = 6.5
        static let actionIconFont: CGFloat = 14
        static let ejectIconFont: CGFloat = 13

        // ~1.3x original size (2x pillHeight 32 reduced by 35% -> 21)
        static let pillHeight: CGFloat = 21
        static let pillFontSize: CGFloat = 11
        static let pillIconFontSize: CGFloat = 10.5
        static let quickToggleIconFontSize: CGFloat = 11
        static let pillDotSize: CGFloat = 6
    }

    var body: some View {
        let _ = l10n.currentLanguage

        HStack(alignment: .center, spacing: 12) {
            mainConnectionIcon

            leftInfoColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            rightControlsColumn
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxHeight: .infinity)
        }
        .padding(.vertical, 5)
        .frame(height: RowMetrics.rowHeight)
        .contentShape(Rectangle())
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

    // MARK: - Left Column

    private var mainIconTooltip: String {
        if isConnecting {
            return loc("Connecting to server…", "Đang kết nối tới máy chủ…")
        }
        if isMountingInFinder {
            return loc("Mounting or unmounting in Finder…", "Đang mount hoặc gỡ mount trong Finder…")
        }
        if isInternetDown {
            return loc("Internet connection lost — active session interrupted", "Mất kết nối Internet — phiên hoạt động bị gián đoạn")
        }
        if isActive {
            return loc("Connected — active session is running", "Đã kết nối — phiên làm việc đang chạy")
        }
        if isMountedInFinder {
            return L10n.tr("mounted_in_finder")
        }
        return loc(
            "\(connection.connectionType.badgeName) connection (\(connection.host):\(connection.port))",
            "Kết nối \(connection.connectionType.badgeName) (\(connection.host):\(connection.port))"
        )
    }

    private var authTooltip: String {
        if connection.authMethod == .privateKey {
            return loc("Authenticates using an SSH private key", "Xác thực bằng SSH Private Key")
        }
        return loc("Authenticates using username and password", "Xác thực bằng tên đăng nhập và mật khẩu")
    }

    private var mainConnectionIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: connection.iconName)
                .font(.system(size: RowMetrics.mainIconFont))
                .foregroundStyle(iconColor)
                .frame(width: RowMetrics.mainIconSize, height: RowMetrics.mainIconSize)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: RowMetrics.mainIconCornerRadius))

            if isConnecting || isMountingInFinder {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: RowMetrics.mainStatusDotSize, height: RowMetrics.mainStatusDotSize)
                    .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                    .offset(x: 2, y: 2)
            } else {
                Circle()
                    .fill(isInternetDown ? Color.red : (isActive ? Color.green : (isMountedInFinder ? Color.teal : Color.secondary.opacity(0.35))))
                    .frame(width: RowMetrics.mainStatusDotSize, height: RowMetrics.mainStatusDotSize)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .opacity(isInternetDown && isPulsing ? 0.4 : 1.0)
                    .offset(x: 2, y: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: RowMetrics.mainIconCornerRadius))
        .hoverTooltip(mainIconTooltip)
    }

    private var leftInfoColumn: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(connection.name)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                if let folder = folderName, !folder.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill").font(.system(size: 9.5))
                        Text(folder).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    .hoverTooltip(loc("Folder: \(folder)", "Thư mục: \(folder)"))
                }

                Text(connection.connectionString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let desc = connection.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 3)

            HStack(spacing: 5) {
                HStack(spacing: 3.5) {
                    Image(systemName: connection.authMethod == .privateKey ? "key.fill" : "lock.fill")
                        .font(.system(size: 9))
                    Text(connection.authMethod == .privateKey ? "Key" : "Password")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4.5))
                .contentShape(RoundedRectangle(cornerRadius: 4.5))
                .hoverTooltip(authTooltip)

                if !connection.tags.isEmpty {
                    ForEach(connection.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if connection.tags.count > 3 {
                        Text("+\(connection.tags.count - 3)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Right Column (Actions, Badges & Quick Toggles)

    private var rightControlsColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .center, spacing: 5) {
                actionButtonsGroup
                savedPasswordBadge
                socksProxyBadge
                statusBadge
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
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
    }

    private var actionButtonsGroup: some View {
        HStack(spacing: 5) {
            // File Browser button (available for SFTP, FTP, SMB)
            actionIconButton(
                systemImage: "folder",
                foreground: .secondary,
                background: AnyShapeStyle(.quaternary),
                width: RowMetrics.actionButtonWidth,
                iconFontSize: RowMetrics.actionIconFont,
                helpText: L10n.tr("open_file_browser")
            ) {
                onFileBrowser?()
            }

            // Finder Mount button (FTP & SFTP via local WebDAV loopback)
            if connection.connectionType.supportsFinderMount {
                Button(action: { onMountInFinder?() }) {
                    Group {
                        if isMountingInFinder {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isMountedInFinder ? "externaldrive.fill" : "externaldrive")
                                .font(.system(size: RowMetrics.actionIconFont, weight: .medium))
                                .foregroundStyle(isMountedInFinder ? Color.teal : Color.secondary)
                        }
                    }
                    .frame(width: RowMetrics.actionButtonWidth, height: RowMetrics.actionButtonHeight)
                    .background(
                        isMountedInFinder ? AnyShapeStyle(Color.teal.opacity(0.16)) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: RowMetrics.actionButtonCornerRadius)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: RowMetrics.actionButtonCornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(isMountingInFinder)
                .hoverTooltip(
                    isMountedInFinder
                        ? L10n.tr("open_mounted_folder")
                        : L10n.tr("mount_in_finder")
                )

                if isMountedInFinder {
                    actionIconButton(
                        systemImage: "eject.fill",
                        foreground: .orange,
                        background: AnyShapeStyle(Color.orange.opacity(0.14)),
                        width: RowMetrics.ejectButtonWidth,
                        iconFontSize: RowMetrics.ejectIconFont,
                        helpText: L10n.tr("unmount_from_finder")
                    ) {
                        onUnmountFromFinder?()
                    }
                }
            }

            // Terminal button (SFTP/SSH only)
            if connection.connectionType.supportsTerminal {
                actionIconButton(
                    systemImage: "terminal",
                    foreground: .secondary,
                    background: AnyShapeStyle(.quaternary),
                    width: RowMetrics.actionButtonWidth,
                    iconFontSize: RowMetrics.actionIconFont,
                    helpText: L10n.tr("open_terminal")
                ) {
                    onTerminal?()
                }
            }
        }
    }

    private func actionIconButton(
        systemImage: String,
        foreground: Color,
        background: AnyShapeStyle,
        width: CGFloat,
        iconFontSize: CGFloat,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconFontSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: width, height: RowMetrics.actionButtonHeight)
                .background(background, in: RoundedRectangle(cornerRadius: RowMetrics.actionButtonCornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: RowMetrics.actionButtonCornerRadius))
        }
        .buttonStyle(.plain)
        .hoverTooltip(helpText)
    }

    @ViewBuilder
    private var savedPasswordBadge: some View {
        if isHovered || connection.savePassword {
            capsuleToggleButton(
                title: connection.savePassword ? loc("Saved", "Đã lưu pass") : nil,
                systemImage: connection.savePassword ? "key.fill" : "key.slash",
                iconFontSize: RowMetrics.pillIconFontSize,
                iconWeight: .regular,
                spacing: 4,
                horizontalPadding: 8,
                isEnabled: connection.savePassword,
                activeColor: .orange,
                inactiveBorderColor: .clear,
                helpText: connection.savePassword
                    ? loc("Password saved. Click to disable", "Đã lưu mật khẩu. Bấm để tắt")
                    : loc("Click to enable password saving", "Bấm để bật lưu mật khẩu")
            ) {
                onSavePasswordToggle?()
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var socksProxyBadge: some View {
        if connection.connectionType.supportsSocksProxy && (isHovered || connection.socksProxyEnabled) {
            capsuleToggleButton(
                title: connection.socksProxyEnabled ? "SOCKS5 :\(String(connection.socksProxyPort))" : "SOCKS5",
                systemImage: connection.socksProxyEnabled ? "wifi" : "wifi.slash",
                iconFontSize: RowMetrics.pillIconFontSize,
                iconWeight: .regular,
                spacing: 4,
                horizontalPadding: 8,
                isEnabled: connection.socksProxyEnabled,
                activeColor: .purple,
                inactiveBorderColor: .clear,
                helpText: connection.socksProxyEnabled
                    ? loc("Disable SOCKS5 Proxy", "Tắt SOCKS5 Proxy")
                    : loc("Enable SOCKS5 Proxy", "Bật SOCKS5 Proxy")
            ) {
                onProxyToggle?()
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isConnecting {
            HStack(spacing: 4.5) {
                ProgressView().controlSize(.mini)
                Text(L10n.tr("connecting"))
                    .font(.system(size: RowMetrics.pillFontSize, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: RowMetrics.pillHeight)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .hoverTooltip(loc("Connecting to server…", "Đang kết nối tới máy chủ…"))
        } else if isInternetDown {
            HStack(spacing: 4.5) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: RowMetrics.pillIconFontSize, weight: .bold))
                Text(L10n.tr("no_internet"))
                    .font(.system(size: RowMetrics.pillFontSize, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 9)
            .frame(height: RowMetrics.pillHeight)
            .background(Color.red.opacity(0.12), in: Capsule())
            .opacity(isPulsing ? 0.6 : 1.0)
            .contentShape(Capsule())
            .hoverTooltip(loc("Internet connection lost — waiting to reconnect", "Mất kết nối Internet — đang chờ kết nối lại"))
        } else if isActive {
            dotStatusPill(
                title: L10n.tr("active"),
                color: .green,
                widthMultiplier: 1.2,
                tooltip: loc("Connection is active — session is running", "Kết nối đang hoạt động — phiên làm việc đang chạy")
            )
        } else if isMountedInFinder {
            dotStatusPill(
                title: "Finder",
                color: .teal,
                tooltip: loc("Mounted in macOS Finder", "Đã mount vào macOS Finder")
            )
        } else {
            Text(connection.connectionType.badgeName)
                .font(.system(size: RowMetrics.pillFontSize, weight: .semibold))
                .foregroundStyle(protocolBadgeColor)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: RowMetrics.pillHeight)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
                .hoverTooltip(loc("Protocol: \(connection.connectionType.displayName) — disconnected", "Giao thức: \(connection.connectionType.displayName) — chưa kết nối"))
        }
    }

    private func dotStatusPill(
        title: String,
        color: Color,
        widthMultiplier: CGFloat = 1.0,
        tooltip: String
    ) -> some View {
        ExpandedWidthLayout(widthMultiplier: widthMultiplier) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: RowMetrics.pillDotSize, height: RowMetrics.pillDotSize)
                Text(title)
                    .font(.system(size: RowMetrics.pillFontSize, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: RowMetrics.pillHeight)
        }
        .background(color.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
        .hoverTooltip(tooltip)
    }

    private func quickSettingToggleButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        activeColor: Color,
        helpText: String,
        action: (() -> Void)?
    ) -> some View {
        capsuleToggleButton(
            title: title,
            systemImage: systemImage,
            iconFontSize: RowMetrics.quickToggleIconFontSize,
            iconWeight: .medium,
            spacing: 4.5,
            horizontalPadding: 9,
            isEnabled: isEnabled,
            activeColor: activeColor,
            inactiveBorderColor: Color.secondary.opacity(0.22),
            helpText: helpText
        ) {
            action?()
        }
    }

    private func capsuleToggleButton(
        title: String?,
        systemImage: String,
        iconFontSize: CGFloat,
        iconWeight: Font.Weight,
        spacing: CGFloat,
        horizontalPadding: CGFloat,
        isEnabled: Bool,
        activeColor: Color,
        inactiveBorderColor: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: spacing) {
                Image(systemName: systemImage)
                    .font(.system(size: iconFontSize, weight: iconWeight))
                if let title {
                    Text(verbatim: title)
                        .font(.system(size: RowMetrics.pillFontSize, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isEnabled ? activeColor : Color.secondary)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: RowMetrics.pillHeight, minHeight: RowMetrics.pillHeight, maxHeight: RowMetrics.pillHeight)
            .background(
                isEnabled ? activeColor.opacity(0.15) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    isEnabled ? activeColor.opacity(0.45) : inactiveBorderColor,
                    lineWidth: 0.75
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverTooltip(helpText)
    }
}

private struct ExpandedWidthLayout: Layout {
    let widthMultiplier: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(proposal)
        return CGSize(width: ceil(size.width * widthMultiplier), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let naturalSize = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(naturalSize)
        )
    }
}
