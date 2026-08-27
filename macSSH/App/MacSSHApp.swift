//
//  MacSSHApp.swift
//  macSSH
//
//  Main application entry point
//

import SwiftUI
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if !window.title.contains("Terminal") && !window.title.contains("Editor") && !window.title.contains("Info") {
                    window.setIsVisible(true)
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
            if let window = sender.windows.first {
                window.setIsVisible(true)
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }

    private var hasShownBackgroundWarning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up any leftover temporary terminal scripts from previous sessions
        TerminalLauncherService.cleanupOldScripts()

        // Auto-load the last opened config file if it exists
        Task { @MainActor in
            await ConfigurationService.shared.autoLoadLastFileIfNeeded()
        }

        // Monitor window closures to warn about SOCKS5 background crash risk
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard !hasShownBackgroundWarning else { return }

        // All checks must happen on main actor since activeSessions is @MainActor-isolated
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if any SOCKS5 proxy session is active
            let hasActiveSocks = ConnectionSessionManager.shared.activeSessions.values.contains {
                $0.socksServer != nil
            }
            guard hasActiveSocks else { return }

            // Count remaining visible windows (excluding the one being closed and menu bar)
            let closingWindow = notification.object as? NSWindow
            let remainingVisible = NSApp.windows.filter {
                $0 != closingWindow &&
                $0.isVisible &&
                !$0.className.contains("StatusBar") &&
                !$0.className.contains("MenuBar") &&
                $0.level == .normal
            }

            if remainingVisible.isEmpty {
                self.hasShownBackgroundWarning = true
                self.showBackgroundSocksWarning()
            }
        }
    }

    private func showBackgroundSocksWarning() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("bg_socks5_warning_title")
        alert.informativeText = L10n.tr("bg_socks5_warning_msg")
        alert.addButton(withTitle: L10n.tr("bg_socks5_warning_dismiss"))
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let configService = ConfigurationService.shared

        if !configService.hasUnsavedChanges {
            Task { @MainActor in
                await performTerminationCleanup()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        // Show save prompt on main thread
        let alert = NSAlert()
        alert.messageText = L10n.tr("save_changes_prompt")
        alert.informativeText = L10n.tr("unsaved_changes_warning")
        alert.addButton(withTitle: L10n.tr("save"))
        alert.addButton(withTitle: L10n.tr("dont_save"))
        alert.addButton(withTitle: L10n.tr("cancel"))
        alert.alertStyle = .warning

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  // Save
            Task { @MainActor in
                try? await configService.save()
                await performTerminationCleanup()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater

        case .alertSecondButtonReturn:  // Don't save
            Task { @MainActor in
                await performTerminationCleanup()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater

        default:  // Cancel
            return .terminateCancel
        }
    }

    private func performTerminationCleanup() async {
        logInfo("Application terminating, closing all active SSH connections...", category: .app)
        TerminalLauncherService.cleanupOldScripts()
        await ConnectionSessionManager.shared.disconnectAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup is handled in applicationShouldTerminate
        // This is kept as a safety net for forced terminations
    }
}

@main
struct MacSSHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = DependencyContainer.shared

    init() {
        AnalyticsService.initialize()
        AppLockManager.shared.lockIfNeeded()
    }

    var body: some Scene {
        // Main Window - Connection List (Single-instance window)
        Window("macSSH", id: WindowID.main) {
            ConnectionListView(viewModel: container.makeConnectionListViewModel())
                .toastOverlay()
                .appLockOverlay()
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.main)
        .commands {
            appCommands
        }

        // Menu Bar Status Item
        MenuBarExtra("macSSH", systemImage: "terminal.fill") {
            MenuBarContentView()
                .modelContainer(container.modelContainer)
        }

        // File Browser Window
        WindowGroup(id: WindowID.fileBrowser, for: String.self) { $windowId in
            if let windowId = windowId {
                FileBrowserWindow(windowId: windowId)
                    .toastOverlay()
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileBrowser)

        // File Editor Window
        WindowGroup(id: WindowID.fileEditor, for: String.self) { $windowId in
            if let windowId = windowId {
                FileEditorWindow(windowId: windowId)
                    .toastOverlay()
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileEditor)

        // File Info Window
        WindowGroup(id: WindowID.fileInfo, for: String.self) { $windowId in
            if let windowId = windowId {
                FileInfoWindow(windowId: windowId)
                    .toastOverlay()
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.fileInfo)

        // Terminal Window
        WindowGroup(id: WindowID.terminal, for: String.self) { $windowId in
            if let windowId = windowId {
                TerminalWindow(windowId: windowId)
                    .toastOverlay()
                    .appLockOverlay()
            }
        }
        .modelContainer(container.modelContainer)
        .defaultSize(WindowSize.terminal)

        // Settings Window (Cmd+,)
        Settings {
            SettingsView()
                .toastOverlay()
                .appLockOverlay()
        }
    }

    // MARK: - Commands
    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.tr("new_ssh_connection")) {
                NotificationCenter.default.post(name: .newConnectionRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.tr("new_folder")) {
                NotificationCenter.default.post(name: .newFolderRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(L10n.tr("new_configuration")) {
                Task {
                    _ = try? await ConfigurationService.shared.requestNewConfiguration()
                }
            }

            Button(L10n.tr("open_configuration")) {
                Task {
                    _ = try? await ConfigurationService.shared.loadConfiguration()
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button(L10n.tr("save_configuration")) {
                Task {
                    try? await ConfigurationService.shared.save()
                }
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(L10n.tr("save_configuration_as")) {
                Task {
                    _ = try? await ConfigurationService.shared.saveAs()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(L10n.tr("export_settings")) {
                Task {
                    _ = try? await ConfigurationService.shared.exportSettings()
                }
            }

            Button(L10n.tr("import_settings")) {
                Task {
                    _ = try? await ConfigurationService.shared.importSettings(replaceExisting: false)
                }
            }
        }

        CommandGroup(after: .toolbar) {
            Button(L10n.tr("refresh")) {
                NotificationCenter.default.post(name: .configurationDataDidChange, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button(L10n.tr("about")) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .aboutRequested, object: nil)
            }

            Divider()

            Button(L10n.tr("settings")) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .settingsRequested, object: nil)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button(L10n.tr("donate")) {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .donateRequested, object: nil)
            }

            Button(L10n.tr("repository")) {
                if let url = URL(string: "https://github.com/devduong/macSSH") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button(L10n.tr("report_bug")) {
                if let url = URL(string: "https://github.com/devduong/macSSH/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
