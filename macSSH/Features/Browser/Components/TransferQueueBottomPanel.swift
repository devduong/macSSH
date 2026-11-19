//
//  TransferQueueBottomPanel.swift
//  macSSH
//
//  Bottom panel displaying Upload queue, Download queue, and SFTP Activity Log
//  with real-time success/failure counters, status filtering, and transfer retry.
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

enum TransferStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.tr("all")
        case .active: return L10n.tr("active")
        case .completed: return L10n.tr("succeeded")
        case .failed: return L10n.tr("failed")
        case .cancelled: return L10n.tr("cancelled")
        }
    }

    func matches(_ status: TransferStatus) -> Bool {
        switch self {
        case .all: return true
        case .active: return status == .inProgress || status == .pending
        case .completed: return status == .completed
        case .failed: return status == .failed
        case .cancelled: return status == .cancelled
        }
    }
}

struct TransferQueueBottomPanel: View {
    @Bindable var viewModel: FileBrowserViewModel
    var maxExpandedHeight: CGFloat = 520

    @State private var selectedTab: TransferQueueTab = .uploads
    @State private var uploadFilter: TransferStatusFilter = .all
    @State private var downloadFilter: TransferStatusFilter = .all
    @State private var uploadSearchText: String = ""
    @State private var downloadSearchText: String = ""
    @State private var isExpanded: Bool = true
    @AppStorage("fileBrowserBottomPanelHeight") private var panelHeight: Double = 180
    @State private var dragStartHeight: CGFloat? = nil
    @State private var isHoveringResizeHandle: Bool = false
    @State private var isShowingStreamSettingsPopover: Bool = false

    private var effectivePanelHeight: CGFloat {
        min(maxExpandedHeight, max(100, CGFloat(panelHeight)))
    }

    private var summaryTransferType: TransferType {
        switch selectedTab {
        case .uploads:
            return .upload
        case .downloads:
            return .download
        case .log:
            if !viewModel.downloadTransfers.isEmpty { return .download }
            return .upload
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                resizeHandleBar
            }

            headerBar

            if isExpanded {
                Divider()
                tabContent
                    .frame(height: effectivePanelHeight)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: viewModel.latestTransferBatch) { _, batch in
            guard let batch else { return }
            selectedTab = (batch.type == .download) ? .downloads : .uploads
            if !isExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
    }

    // MARK: - Drag Resize Handle

    private var resizeHandleBar: some View {
        let isHighlighted = isHoveringResizeHandle || dragStartHeight != nil
        return ZStack {
            isHighlighted
                ? Color.accentColor.opacity(0.12)
                : Color(NSColor.controlBackgroundColor)

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: isHighlighted ? 44 : 36, height: 3)

                if isHighlighted {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(height: 11)
        .frame(maxWidth: .infinity)
        .overlay(ResizeCursorView())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringResizeHandle = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = effectivePanelHeight
                    }
                    let base = dragStartHeight ?? effectivePanelHeight
                    let newHeight = base - value.translation.height
                    panelHeight = Double(max(100, min(maxExpandedHeight, newHeight)))
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
        .help(loc("Drag up or down to resize panel", "Kéo lên hoặc xuống để tăng giảm kích thước"))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Tab Selector
            HStack(spacing: 2) {
                tabButton(
                    tab: .uploads,
                    count: viewModel.uploadTransfers.count,
                    activeCount: viewModel.activeUploadCount + viewModel.pendingUploadCount,
                    failedCount: viewModel.uploadFailedCount,
                    icon: "icloud.and.arrow.up",
                    activeColor: .blue
                )

                tabButton(
                    tab: .downloads,
                    count: viewModel.downloadTransfers.count,
                    activeCount: viewModel.activeDownloadCount + viewModel.pendingDownloadCount,
                    failedCount: viewModel.downloadFailedCount,
                    icon: "icloud.and.arrow.down",
                    activeColor: .green
                )

                tabButton(
                    tab: .log,
                    count: viewModel.activityLogs.count,
                    activeCount: 0,
                    failedCount: 0,
                    icon: "list.bullet.clipboard",
                    activeColor: .orange
                )
            }

            // Success & Failure Counters Summary (always visible at bottom bar)
            let statsType = summaryTransferType
            let totalForSummary = statsType == .download ? viewModel.downloadTransfers.count : viewModel.uploadTransfers.count
            if totalForSummary > 0 {
                transferSummaryCounters(for: statsType)
            }

            if viewModel.isPreparingTransfers {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(viewModel.preparingTransferMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            Spacer(minLength: 4)

            // FTP Multi-Stream Concurrency Control (FTP only)
            if viewModel.connection.connectionType == .ftp {
                ftpStreamControlPill
            }

            // Active Speed Summary
            if viewModel.activeUploadCount > 0 || viewModel.activeDownloadCount > 0 {
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
                let currentType: TransferType = selectedTab == .uploads ? .upload : .download
                if viewModel.hasFinishedTransfers(for: currentType) {
                    let hasSucceeded = viewModel.hasSucceededTransfers(for: currentType)
                    Button {
                        viewModel.clearCompletedTransfers(type: currentType)
                    } label: {
                        Label(
                            hasSucceeded ? L10n.tr("clear_done") : L10n.tr("clear_finished"),
                            systemImage: "xmark.circle"
                        )
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(hasSucceeded ? "Clear succeeded transfers" : "Clear finished transfers")
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

    @ViewBuilder
    private func transferSummaryCounters(for type: TransferType) -> some View {
        let succeeded = viewModel.successCount(for: type)
        let failed = viewModel.failedCount(for: type)

        HStack(spacing: 6) {
            Button {
                applyQuickFilter(.completed, for: type)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(succeeded) \(L10n.tr("succeeded"))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(loc("Click to filter succeeded transfers", "Bấm để lọc các tệp thành công"))

            Button {
                applyQuickFilter(.failed, for: type)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(failed) \(L10n.tr("failed"))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(failed > 0 ? Color.red : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background((failed > 0 ? Color.red : Color.secondary).opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(loc("Click to filter failed transfers", "Bấm để lọc các tệp thất bại"))
        }
    }

    private func applyQuickFilter(_ filter: TransferStatusFilter, for type: TransferType) {
        selectedTab = (type == .download) ? .downloads : .uploads
        if type == .download {
            downloadFilter = (downloadFilter == filter) ? .all : filter
        } else {
            uploadFilter = (uploadFilter == filter) ? .all : filter
        }
        if !isExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        }
    }

    private var ftpStreamControlPill: some View {
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

    private func tabButton(
        tab: TransferQueueTab,
        count: Int,
        activeCount: Int,
        failedCount: Int,
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

                if failedCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
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
            transferQueueContent(
                type: .upload,
                allTransfers: viewModel.uploadTransfers,
                filter: $uploadFilter,
                searchText: $uploadSearchText,
                emptyText: "No uploads in queue"
            )
        case .downloads:
            transferQueueContent(
                type: .download,
                allTransfers: viewModel.downloadTransfers,
                filter: $downloadFilter,
                searchText: $downloadSearchText,
                emptyText: "No downloads in queue"
            )
        case .log:
            logListView
        }
    }

    // MARK: - Transfer Queue Tab Content (Filter + Retry + List)

    private func transferQueueContent(
        type: TransferType,
        allTransfers: [TransferProgress],
        filter: Binding<TransferStatusFilter>,
        searchText: Binding<String>,
        emptyText: String
    ) -> some View {
        let filteredTransfers: [TransferProgress] = {
            let statusFilter = filter.wrappedValue
            let query = searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if statusFilter == .all && query.isEmpty {
                return allTransfers
            }
            return allTransfers.filter { transfer in
                let matchesStatus = statusFilter.matches(transfer.status)
                if !matchesStatus { return false }
                if query.isEmpty { return true }
                return transfer.fileName.localizedCaseInsensitiveContains(query) ||
                    transfer.remotePath.localizedCaseInsensitiveContains(query)
            }
        }()

        return VStack(spacing: 0) {
            if !allTransfers.isEmpty {
                filterBar(type: type, filter: filter, searchText: searchText)
                Divider()
            }

            if allTransfers.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: type == .upload ? "icloud.and.arrow.up" : "icloud.and.arrow.down")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTransfers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(L10n.tr("no_matching_transfers"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(L10n.tr("all")) {
                        filter.wrappedValue = .all
                        searchText.wrappedValue = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTransfers) { transfer in
                            TransferQueueRowView(
                                transfer: transfer,
                                onCancel: { viewModel.cancelTransfer(transfer) },
                                onRetry: { viewModel.retryTransfer(transfer) },
                                onRemove: { viewModel.removeTransfer(transfer) }
                            )
                            .equatable()
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func filterBar(
        type: TransferType,
        filter: Binding<TransferStatusFilter>,
        searchText: Binding<String>
    ) -> some View {
        let total = type == .upload ? viewModel.uploadTransfers.count : viewModel.downloadTransfers.count
        let active = type == .upload
            ? (viewModel.activeUploadCount + viewModel.pendingUploadCount)
            : (viewModel.activeDownloadCount + viewModel.pendingDownloadCount)
        let succeeded = viewModel.successCount(for: type)
        let failed = viewModel.failedCount(for: type)
        let cancelled = viewModel.cancelledCount(for: type)

        return HStack(spacing: 6) {
            filterChip(.all, count: total, tint: .accentColor, selection: filter)
            filterChip(.active, count: active, tint: .blue, selection: filter)
            filterChip(.completed, count: succeeded, tint: .green, selection: filter)
            filterChip(.failed, count: failed, tint: .red, selection: filter)
            if cancelled > 0 || filter.wrappedValue == .cancelled {
                filterChip(.cancelled, count: cancelled, tint: .gray, selection: filter)
            }

            Spacer(minLength: 6)

            if failed > 0 {
                Button {
                    viewModel.retryAllFailed(type: type)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(L10n.tr("retry_all_failed")) (\(failed))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.mini)
                .help(loc("Retry all failed transfers", "Thử lại tất cả các tệp bị lỗi"))
            }

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField(L10n.tr("filter_files"), text: searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 120)
                if !searchText.wrappedValue.isEmpty {
                    Button {
                        searchText.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    private func filterChip(
        _ option: TransferStatusFilter,
        count: Int,
        tint: Color,
        selection: Binding<TransferStatusFilter>
    ) -> some View {
        let isSelected = selection.wrappedValue == option
        return Button {
            selection.wrappedValue = option
        } label: {
            HStack(spacing: 4) {
                Text(option.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(isSelected ? tint.opacity(0.25) : Color.secondary.opacity(0.15), in: Capsule())
            }
            .foregroundStyle(isSelected ? tint : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                isSelected ? tint.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? tint.opacity(0.4) : Color.secondary.opacity(0.18), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
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
                            proxy.scrollTo(first.id, anchor: .top)
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

// MARK: - Equatable Transfer Row View
private struct TransferQueueRowView: View, Equatable {
    let transfer: TransferProgress
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    static func == (lhs: TransferQueueRowView, rhs: TransferQueueRowView) -> Bool {
        lhs.transfer == rhs.transfer
    }

    var body: some View {
        HStack(spacing: 10) {
            statusIcon(for: transfer.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if transfer.status == .failed, let error = transfer.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(error)
                } else {
                    Text(transfer.remotePath)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 140, alignment: .leading)

            Spacer()

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

            VStack(alignment: .trailing, spacing: 2) {
                Text(transfer.formattedSpeed)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(transfer.isInProgress ? .primary : .secondary)

                Text(transfer.formattedETA)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 85, alignment: .trailing)

            HStack(spacing: 6) {
                if transfer.isCancellable {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel transfer")
                } else if transfer.isRetryable {
                    Button(action: onRetry) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L10n.tr("retry"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.mini)
                    .help(loc("Retry transfer", "Thử lại"))

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from list")
                } else {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from list")
                }
            }
            .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
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
}
