//
//  TransferQueueBottomPanel.swift
//  macSSH
//
//  Bottom panel displaying Upload queue, Download queue, and SFTP Activity Log
//

import SwiftUI

enum TransferQueueTab: String, CaseIterable, Identifiable {
    case uploads = "Upload queue"
    case downloads = "Download queue"
    case log = "Log"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .uploads: return "arrow.up.circle.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .log: return "list.bullet.rectangle"
        }
    }
}

struct TransferQueueBottomPanel: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var selectedTab: TransferQueueTab = .uploads
    @State private var isExpanded: Bool = true
    @State private var panelHeight: CGFloat = 160
    @State private var isShowingStreamSettingsPopover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            if isExpanded {
                Divider()

                // Content for selected tab
                tabContent
                    .frame(height: panelHeight)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Tab Selector
            HStack(spacing: 2) {
                tabButton(
                    tab: .uploads,
                    count: viewModel.uploadTransfers.count,
                    activeCount: viewModel.activeUploadCount,
                    icon: "icloud.and.arrow.up",
                    activeColor: .blue
                )

                tabButton(
                    tab: .downloads,
                    count: viewModel.downloadTransfers.count,
                    activeCount: viewModel.activeDownloadCount,
                    icon: "icloud.and.arrow.down",
                    activeColor: .green
                )

                tabButton(
                    tab: .log,
                    count: viewModel.activityLogs.count,
                    activeCount: 0,
                    icon: "list.bullet.clipboard",
                    activeColor: .orange
                )
            }

            Spacer()

            // FTP Multi-Stream Concurrency Control (FTP only)
            if viewModel.connection.connectionType == .ftp {
                Button {
                    isShowingStreamSettingsPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 10))
                        Text("\(viewModel.effectiveFTPStreams) \(L10n.tr("streams"))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("ftp_max_streams"))
                .popover(isPresented: $isShowingStreamSettingsPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("ftp_max_streams"))
                            .font(.system(size: 12, weight: .semibold))

                        Stepper(
                            value: Binding(
                                get: { viewModel.effectiveFTPStreams },
                                set: { viewModel.setSessionFTPStreams($0) }
                            ),
                            in: FTPTransferConstants.minStreams...FTPTransferConstants.maxStreams
                        ) {
                            Text("\(viewModel.effectiveFTPStreams) \(L10n.tr("streams"))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }

                        HStack(spacing: 6) {
                            ForEach([1, 5, 10, 20, 32], id: \.self) { count in
                                Button("\(count)") {
                                    viewModel.setSessionFTPStreams(count)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(viewModel.effectiveFTPStreams == count ? .teal : nil)
                            }
                        }

                        Text(L10n.tr("ftp_max_streams_desc"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(width: 260)
                }
            }

            // Active Speed Summary
            if viewModel.hasActiveTransfers {
                HStack(spacing: 8) {
                    if viewModel.activeUploadCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.blue)
                            Text(viewModel.totalUploadSpeedFormatted)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if viewModel.activeDownloadCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                            Text(viewModel.totalDownloadSpeedFormatted)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
            }

            // Action Buttons
            if selectedTab == .log {
                if !viewModel.activityLogs.isEmpty {
                    Button {
                        viewModel.clearLogs()
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Clear activity log")
                }
            } else {
                if viewModel.hasCompletedTransfers {
                    Button {
                        viewModel.clearCompletedTransfers()
                    } label: {
                        Label("Clear Done", systemImage: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Clear completed transfers")
                }
            }

            // Expand / Collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Collapse panel" : "Expand panel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func tabButton(
        tab: TransferQueueTab,
        count: Int,
        activeCount: Int,
        icon: String,
        activeColor: Color
    ) -> some View {
        Button {
            if selectedTab == tab && !isExpanded {
                withAnimation { isExpanded = true }
            } else {
                selectedTab = tab
                if !isExpanded {
                    withAnimation { isExpanded = true }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? activeColor : .secondary)

                Text(tab.rawValue)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            activeCount > 0
                                ? activeColor.opacity(0.8)
                                : Color.secondary.opacity(0.2)
                        )
                        .foregroundStyle(activeCount > 0 ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selectedTab == tab
                    ? Color(NSColor.selectedControlColor).opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .uploads:
            transferListView(transfers: viewModel.uploadTransfers, emptyText: "No uploads in queue")
        case .downloads:
            transferListView(transfers: viewModel.downloadTransfers, emptyText: "No downloads in queue")
        case .log:
            logListView
        }
    }

    // MARK: - Transfer List View

    private func transferListView(transfers: [TransferProgress], emptyText: String) -> some View {
        Group {
            if transfers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: selectedTab == .uploads ? "icloud.and.arrow.up" : "icloud.and.arrow.down")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transfers) { transfer in
                            transferRow(transfer)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func transferRow(_ transfer: TransferProgress) -> some View {
        HStack(spacing: 10) {
            // Status Icon
            statusIcon(for: transfer.status)

            // File Name & Path
            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(transfer.remotePath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .leading)

            Spacer()

            // Progress Bar & Percentage
            VStack(spacing: 3) {
                ProgressView(value: transfer.fractionCompleted)
                    .progressViewStyle(.linear)
                    .frame(width: 120)

                HStack {
                    Text("\(transfer.percentCompleted)%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text(transfer.progressText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 120)
            }

            // Speed & ETA
            VStack(alignment: .trailing, spacing: 2) {
                Text(transfer.formattedSpeed)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(transfer.isInProgress ? .primary : .secondary)

                Text(transfer.formattedETA)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 85, alignment: .trailing)

            // Action Button (Cancel)
            if transfer.isCancellable {
                Button {
                    viewModel.cancelTransfer(transfer)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel transfer")
            } else {
                Color.clear.frame(width: 13, height: 13)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func statusIcon(for status: TransferStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
            case .inProgress:
                ProgressView()
                    .controlSize(.mini)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.gray)
            }
        }
        .font(.system(size: 13))
        .frame(width: 16)
    }

    // MARK: - Log List View

    private var logListView: some View {
        Group {
            if viewModel.activityLogs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No SFTP activity recorded yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(viewModel.activityLogs) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: viewModel.activityLogs.count) { _, _ in
                        if let first = viewModel.activityLogs.first {
                            withAnimation {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func logRow(_ entry: SFTPLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(entry.formattedTime)]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text("[\(entry.level.rawValue)]")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .frame(width: 55, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
    }
}
