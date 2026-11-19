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
        // Restore Dock icon when app is reopened
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        if !flag {
            if let mainWindow = sender.windows.first(where: {
                ($0.identifier?.rawValue.contains(WindowID.main) == true || $0.title == "macSSH") &&
                $0.level == .normal &&
                !$0.className.contains("StatusBar")
            }) {
                mainWindow.setIsVisible(true)
                mainWindow.makeKeyAndOrderFront(nil)
                return true
            }
            if let window = sender.windows.first(where: {
                $0.level == .normal &&
                !$0.className.contains("StatusBar") &&
                !$0.title.contains("Terminal") &&
                !$0.title.contains("Editor") &&
                !$0.title.contains("Info") &&
                !($0.identifier?.rawValue.contains(WindowID.about) == true) &&
                !($0.identifier?.rawValue.contains(WindowID.donate) == true) &&
                !$0.title.contains("Settings") &&
                !$0.className.contains("Settings")
            }) {
                window.setIsVisible(true)
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply persisted Light/Dark/System appearance
        AppearanceManager.shared.applyAppearance()

        // Clean up any leftover orphan ssh/socks processes, scripts, and stale Finder mounts from previous sessions/crashes
        NativeProcessRegistry.shared.cleanupOrphanProcesses()
        TerminalLauncherService.cleanupOldScripts()

        // Wait for orphan mount cleanup, auto-load saved config, then run auto-connect/auto-mount
        Task { @MainActor in
            await FinderMountManager.cleanupOrphanMountsAndWait()
            await ConfigurationService.shared.autoLoadLastFileIfNeeded()
            await StartupAutomationService.shared.runOnLaunchIfUnlocked()
        }

        // Monitor window close notifications to hide Dock icon when no regular windows are open
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Monitor window key notifications to restore Dock icon when a window becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.level == .normal,
              !window.className.contains("StatusBar"),
              !window.className.contains("MenuBar") else { return }

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let closingWindow = notification.object as? NSWindow
            let remainingVisible = NSApp.windows.filter {
                $0 != closingWindow &&
                $0.isVisible &&
                !$0.className.contains("StatusBar") &&
                !$0.className.contains("MenuBar") &&
                $0.level == .normal
            }

            if remainingVisible.isEmpty {
                // Hide icon from Dock when running purely in background on Menu Bar
                NSApp.setActivationPolicy(.accessory)
            }
        }
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
        logInfo("Application terminating, unmounting Finder volumes and closing all active SSH connections and SOCKS tunnels...", category: .app)
        TerminalLauncherService.cleanupOldScripts()
        await FinderMountManager.shared.unmountAll()
        await ConnectionSessionManager.shared.disconnectAll()
        NativeProcessRegistry.shared.terminateAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FinderMountManager.emergencyUnmountAllSync()
        NativeProcessRegistry.shared.terminateAll()
    }
}

@main
struct MacSSHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = DependencyContainer.shared
    @ObservedObject private var l10n = LocalizationManager.shared

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
            AppCommands()
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

        // About Window
        Window(L10n.tr("about"), id: WindowID.about) {
            AboutSheetView()
                .navigationTitle(L10n.tr("about"))
                .toastOverlay()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Donate Window
        Window(L10n.tr("donate"), id: WindowID.donate) {
            DonateSheetView()
                .navigationTitle(L10n.tr("donate"))
                .toastOverlay()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Top Menu Bar Commands

private struct AppCommands: Commands {
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @FocusedValue(\.connectionMenuActions) private var connectionActions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.tr("about")) {
                ensureRegularActivation()
                openWindow(id: WindowID.about)
            }

            Button(L10n.tr("donate")) {
                ensureRegularActivation()
                openWindow(id: WindowID.donate)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L10n.tr("new_connection")) {
                openMainWindowAndPost(.newConnectionRequested)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.tr("new_folder")) {
                openMainWindowAndPost(.newFolderRequested)
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

            Divider()

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
            Menu(L10n.tr("appearance")) {
                Picker(L10n.tr("appearance"), selection: $appearanceManager.currentAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.localizedTitle, systemImage: appearance.iconName)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Button(L10n.tr("toggle_activity_logs")) {
                NotificationCenter.default.post(name: .toggleLogPanelRequested, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button(L10n.tr("refresh")) {
                NotificationCenter.default.post(name: .configurationDataDidChange, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(L10n.tr("connection_menu")) {
            Button(L10n.tr("new_connection")) {
                openMainWindowAndPost(.newConnectionRequested)
            }

            Divider()

            if connectionActions?.isConnected == true {
                Button(L10n.tr("disconnect")) {
                    connectionActions?.onDisconnect()
                }
                .disabled(connectionActions?.selectedConnection == nil)
            } else {
                Button(L10n.tr("connect")) {
                    connectionActions?.onConnect()
                }
                .disabled(connectionActions?.selectedConnection == nil)
            }

            Button(L10n.tr("open_file_browser")) {
                connectionActions?.onOpenFileBrowser()
            }
            .disabled(connectionActions?.selectedConnection == nil)

            if connectionActions?.isMountedInFinder == true {
                Button(L10n.tr("open_mounted_folder")) {
                    connectionActions?.onOpenMountedFolder()
                }

                Button(L10n.tr("unmount_from_finder")) {
                    connectionActions?.onUnmountFromFinder()
                }
            } else {
                Button(L10n.tr("mount_in_finder")) {
                    connectionActions?.onMountInFinder()
                }
                .disabled(connectionActions?.selectedConnection?.connectionType.supportsFinderMount != true)
            }

            Button(L10n.tr("open_terminal")) {
                connectionActions?.onOpenTerminal()
            }
            .disabled(connectionActions?.selectedConnection?.connectionType.supportsTerminal != true)

            Button(L10n.tr("open_in_macos_terminal")) {
                connectionActions?.onOpenMacOSTerminal()
            }
            .disabled(connectionActions?.selectedConnection?.connectionType.supportsTerminal != true)

            Divider()

            Button(L10n.tr("edit")) {
                connectionActions?.onEdit()
            }
            .disabled(connectionActions?.selectedConnection == nil)

            Button(L10n.tr("duplicate")) {
                connectionActions?.onDuplicate()
            }
            .disabled(connectionActions?.selectedConnection == nil)

            Divider()

            Button(L10n.tr("delete")) {
                connectionActions?.onDelete()
            }
            .disabled(connectionActions?.selectedConnection == nil)
        }

        CommandGroup(replacing: .help) {
            Button(L10n.tr("donate")) {
                ensureRegularActivation()
                openWindow(id: WindowID.donate)
            }

            Divider()

            Button(L10n.tr("github_repository")) {
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

    private func ensureRegularActivation() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMainWindowAndPost(_ notificationName: Notification.Name) {
        ensureRegularActivation()
        let hasVisibleMain = NSApp.windows.contains {
            $0.isVisible && (($0.identifier?.rawValue.contains(WindowID.main) == true) || $0.title == "macSSH")
        }
        if hasVisibleMain {
            NotificationCenter.default.post(name: notificationName, object: nil)
        } else {
            openWindow(id: WindowID.main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: notificationName, object: nil)
            }
        }
    }
}
