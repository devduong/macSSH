//
//  UpdatePromptView.swift
//  macSSH
//
//  Native macOS Software Update popup window showing release notes,
//  DMG download progress, "Skip This Version", and "Never Remind Again".
//

import SwiftUI
import AppKit

@MainActor
final class UpdatePromptWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdatePromptWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = L10n.tr("update_available_title")
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = UpdatePromptView()
        let hostingController = NSHostingController(rootView: contentView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.identifier = NSUserInterfaceItemIdentifier(WindowID.update)
        newWindow.title = L10n.tr("update_available_title")
        newWindow.styleMask = [.titled, .closable]
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.setContentSize(NSSize(width: 520, height: 390))
        newWindow.center()
        newWindow.delegate = self
        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if UpdateService.shared.isDownloading {
            UpdateService.shared.cancelDownload()
        }
    }
}

struct UpdatePromptView: View {
    @State private var updateService = UpdateService.shared
    @ObservedObject private var l10n = LocalizationManager.shared

    private var release: ReleaseUpdateInfo? {
        updateService.availableUpdate
    }

    private var formattedFileSize: String? {
        guard let bytes = release?.dmgSizeBytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("update_available_headline"))
                        .font(.system(size: 15, weight: .bold))

                    if let release {
                        Text(L10n.tr("update_version_summary", release.version, AppVersion.version))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Label("v\(release.version)", systemImage: "sparkles")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())

                            if let sizeText = formattedFileSize {
                                Text(sizeText)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }

                            Spacer()

                            Button {
                                NSWorkspace.shared.open(release.htmlURL)
                            } label: {
                                Label(L10n.tr("view_on_github"), systemImage: "arrow.up.right.square")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Release Notes
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("release_notes"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ScrollView {
                    let notes = release?.releaseNotes.isEmpty == false
                        ? release!.releaseNotes
                        : L10n.tr("no_release_notes")
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Download progress bar (when downloading)
            if updateService.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr("downloading_update"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int((updateService.downloadProgress * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: updateService.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            Divider()

            // Footer Actions
            HStack(spacing: 8) {
                Button(L10n.tr("never_remind_again")) {
                    updateService.neverRemindAgain()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(L10n.tr("skip_this_version")) {
                    updateService.skipCurrentUpdate()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                if updateService.isDownloading {
                    Button(L10n.tr("cancel")) {
                        updateService.cancelDownload()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                } else {
                    Button(L10n.tr("remind_me_later")) {
                        updateService.remindMeLater()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await updateService.downloadAndOpenUpdate()
                        }
                    } label: {
                        Label(
                            release?.dmgDownloadURL != nil ? L10n.tr("download_update") : L10n.tr("open_release_page"),
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 520, height: 390)
    }
}
