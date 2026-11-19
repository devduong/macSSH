//
//  TransfersPopover.swift
//  macSSH
//
//  Safari-style popover showing file transfer progress
//

import SwiftUI

struct TransfersPopover: View {
    @Bindable var viewModel: FileBrowserViewModel
    @ObservedObject private var l10n = LocalizationManager.shared

    private var needsScrolling: Bool {
        viewModel.allTransfers.count > 5
    }

    var body: some View {
        let _ = l10n.currentLanguage

        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.allTransfers.isEmpty {
                emptyState
            } else if needsScrolling {
                scrollableTransfersList
            } else {
                staticTransfersList
            }
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Transfers")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            let failedCount = viewModel.uploadFailedCount + viewModel.downloadFailedCount
            if failedCount > 0 {
                Button("\(L10n.tr("retry_all_failed")) (\(failedCount))") {
                    viewModel.retryAllFailed()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            }

            if viewModel.hasActiveTransfers {
                Button("Cancel All") {
                    viewModel.cancelAllTransfers()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.red)
            }

            if viewModel.hasCompletedTransfers {
                Button("Clear") {
                    viewModel.clearCompletedTransfers()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No transfers")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // When few items, use a plain VStack so it sizes to content exactly
    private var staticTransfersList: some View {
        VStack(spacing: 0) {
            transferItems
        }
    }

    // When many items, use ScrollView with a fixed max height
    private var scrollableTransfersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                transferItems
            }
        }
        .frame(maxHeight: 380)
    }

    @ViewBuilder
    private var transferItems: some View {
        ForEach(viewModel.allTransfers) { transfer in
            TransferItemView(
                transfer: transfer,
                onCancel: {
                    viewModel.cancelTransfer(transfer)
                },
                onRetry: {
                    viewModel.retryTransfer(transfer)
                },
                onRemove: {
                    viewModel.removeTransfer(transfer)
                }
            )

            if transfer.id != viewModel.allTransfers.last?.id {
                Divider()
                    .padding(.leading, 54) // Aligns with filename: 16 padding + 10 spacing + 28 icon
            }
        }
    }
}

// MARK: - Transfer Item View
struct TransferItemView: View {
    let transfer: TransferProgress
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            // File info and progress
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if transfer.isInProgress {
                    ProgressView(value: transfer.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    HStack {
                        Text(transfer.progressText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(transfer.percentCompleted)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else if transfer.status == .pending {
                    Text(L10n.tr("pending", default: "Queued"))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else if transfer.isComplete {
                    Text(transfer.totalSizeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if transfer.status == .failed {
                    Text(transfer.error ?? "Transfer failed")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if transfer.status == .cancelled {
                    Text("Cancelled")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            // Trailing action — always rendered to prevent layout shifts on hover
            HStack(spacing: 6) {
                if transfer.isRetryable {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("retry"))
                }

                Button(action: transfer.isCancellable ? onCancel : onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: transfer.isCancellable ? 16 : 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(transfer.isCancellable || transfer.isRetryable || isHovering ? 1 : 0)
                .help(transfer.isCancellable
                    ? (transfer.transferType == .download ? "Cancel download" : "Cancel upload")
                    : "Remove from list")
            }
            .frame(minWidth: 20, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let action = transfer.transferType == .download ? "downloading" : "uploading"
        switch transfer.status {
        case .inProgress:
            return "\(transfer.fileName), \(action), \(transfer.percentCompleted) percent complete"
        case .completed:
            return "\(transfer.fileName), completed, \(transfer.totalSizeText)"
        case .failed:
            return "\(transfer.fileName), failed, \(transfer.error ?? "Transfer failed")"
        case .cancelled:
            return "\(transfer.fileName), cancelled"
        case .pending:
            return "\(transfer.fileName), pending"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusBackgroundColor)

            if transfer.isInProgress {
                Image(systemName: transfer.transferType == .download ? "arrow.down" : "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            } else if transfer.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            } else if transfer.status == .failed {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            } else if transfer.status == .cancelled {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var statusBackgroundColor: Color {
        switch transfer.status {
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .pending:
            return .orange
        case .cancelled:
            return .gray
        }
    }
}

// MARK: - Toolbar Transfers Button
struct TransfersToolbarButton: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        Button {
            viewModel.isShowingTransfersPopover.toggle()
        } label: {
            Label("Transfers", systemImage: viewModel.hasActiveTransfers ? "arrow.up.circle.fill" : "arrow.up.arrow.down.circle")
                .symbolEffect(.pulse, options: .repeating, isActive: viewModel.hasActiveTransfers)
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.activeTransferCount > 0 {
                Text("\(viewModel.activeTransferCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue))
                    .offset(x: 4, y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .popover(isPresented: $viewModel.isShowingTransfersPopover, arrowEdge: .bottom) {
            TransfersPopover(viewModel: viewModel)
        }
        .help("Transfers")
        .accessibilityLabel(viewModel.activeTransferCount > 0
            ? "Transfers, \(viewModel.activeTransferCount) active"
            : "Transfers")
    }
}

// MARK: - Preview
#Preview {
    TransfersPopover(
        viewModel: DependencyContainer.shared.makeFileBrowserViewModel(
            connection: Connection(name: "Test", host: "localhost", username: "user"),
            sftpSession: SFTPSession(),
            password: "test"
        )
    )
}
