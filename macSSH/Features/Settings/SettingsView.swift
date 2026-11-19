//
//  SettingsView.swift
//  macSSH
//
//  Application settings view (Cmd+, shortcut via Settings scene)
//

import SwiftUI

struct SettingsView: View {
    @State private var appLockManager = AppLockManager.shared
    @ObservedObject private var configService = ConfigurationService.shared
    private let biometricService: BiometricAuthServiceProtocol = BiometricAuthService.shared

    @State private var showNewConfirmation = false
    @State private var statusMessage: String?
    @State private var isErrorMessage = false

    private var isBiometricAvailable: Bool {
        biometricService.isBiometricAvailable()
    }

    private var isEnabled: Bool {
        appLockManager.isBiometricLockEnabled
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = true

    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var ftpSettings = FTPTransferSettings.shared
    @State private var updateService = UpdateService.shared

    var body: some View {
        let _ = l10n.currentLanguage

        VStack(spacing: 0) {
            TabView {
                Form {
                    generalSection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(L10n.tr("general"), systemImage: "gearshape")
                }

                Form {
                    securitySection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(L10n.tr("security"), systemImage: "lock.shield")
                }

                Form {
                    configurationSection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(L10n.tr("configuration"), systemImage: "doc.badge.gearshape")
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .frame(width: 520, height: 465)
        .confirmationDialog(
            L10n.tr("create_new_config_title"),
            isPresented: $showNewConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("create_new_clear_all"), role: .destructive) {
                Task {
                    do {
                        try await configService.newConfiguration()
                        statusMessage = L10n.tr("created_new_config")
                        isErrorMessage = false
                    } catch {
                        statusMessage = "\(L10n.tr("failed")): \(error.localizedDescription)"
                        isErrorMessage = true
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("create_new_config_desc"))
        }
    }

    // MARK: - General Section

    @ViewBuilder
    private var generalSection: some View {
        Section(L10n.tr("appearance")) {
            Picker(L10n.tr("appearance"), selection: $appearanceManager.currentAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.localizedTitle)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Text(L10n.tr("appearance_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section(L10n.tr("language")) {
            Picker(L10n.tr("language"), selection: $l10n.currentLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)

            Text(L10n.tr("language_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section(L10n.tr("ftp_transfers")) {
            HStack {
                Text(L10n.tr("ftp_max_streams"))
                Spacer()
                Stepper(
                    value: $ftpSettings.maxConcurrentStreams,
                    in: FTPTransferConstants.minStreams...FTPTransferConstants.maxStreams
                ) {
                    Text("\(ftpSettings.maxConcurrentStreams) \(L10n.tr("streams"))")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }

            Text(L10n.tr("ftp_max_streams_desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section(L10n.tr("updates_startup")) {
            Toggle(L10n.tr("auto_check_updates"), isOn: $autoCheckUpdates)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateService.checkForUpdates(manual: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if updateService.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(updateService.isChecking ? L10n.tr("checking_for_updates") : L10n.tr("check_for_updates"))
                    }
                }
                .disabled(updateService.isChecking)

                Spacer()

                Text("v\(AppVersion.version) (\(AppVersion.buildNumber))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let msg = updateService.statusMessage {
                HStack(spacing: 6) {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(updateService.isStatusError ? .red : .secondary)
                    if updateService.availableUpdate != nil {
                        Button(L10n.tr("download_update")) {
                            updateService.showAvailableUpdatePrompt()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            if let skipped = updateService.skippedVersion, !skipped.isEmpty {
                HStack {
                    Text(L10n.tr("skipped_version_label", skipped))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("reset_skipped_version")) {
                        updateService.resetSkippedVersion()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Security Section

    @ViewBuilder
    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appLockManager.isBiometricLockEnabled },
                set: { newValue in
                    if newValue {
                        appLockManager.enableBiometricLock()
                    } else {
                        Task {
                            await appLockManager.disableBiometricLock()
                        }
                    }
                }
            )) {
                Label(L10n.tr("require_touch_id"), systemImage: "touchid")
            }
            .disabled(!isBiometricAvailable)

            if !isBiometricAvailable {
                Text(L10n.tr("touch_id_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Toggle(isOn: Bindable(appLockManager).lockOnAppResume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("lock_when_switching"))
                        Text(L10n.tr("lock_when_switching_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Bindable(appLockManager).lockBeforeConnection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("lock_before_connection"))
                        Text(L10n.tr("lock_before_connection_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Toggle(isOn: Bindable(appLockManager).lockAfterInactivity) {
                        Text(L10n.tr("lock_after_inactivity"))
                    }

                    Spacer()

                    Picker("", selection: Bindable(appLockManager).inactivityTimeout) {
                        ForEach(InactivityTimeout.allCases) { timeout in
                            Text(timeout.label).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!appLockManager.lockAfterInactivity)
                }
            }
        } header: {
            Text(L10n.tr("security"))
        } footer: {
            if isEnabled {
                Text(L10n.tr("lock_on_launch_notice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Configuration & Backup Section

    @ViewBuilder
    private var configurationSection: some View {
        Section {
            if let status = statusMessage ?? configService.lastOperationStatus {
                HStack(spacing: 8) {
                    Image(systemName: isErrorMessage ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isErrorMessage ? Color.red : Color.green)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(isErrorMessage ? Color.red : Color.secondary)
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            if let url = try await configService.exportSettings() {
                                statusMessage = "\(L10n.tr("exported_to")): \(url.lastPathComponent)"
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(L10n.tr("export_failed")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(L10n.tr("export_to_json"), systemImage: "square.and.arrow.up")
                }

                Button {
                    Task {
                        do {
                            if try await configService.importSettings(replaceExisting: false) {
                                statusMessage = L10n.tr("settings_imported")
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(L10n.tr("import_failed")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(L10n.tr("import_from_json"), systemImage: "square.and.arrow.down")
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            try await configService.save()
                            statusMessage = configService.lastOperationStatus ?? L10n.tr("saved")
                            isErrorMessage = false
                        } catch {
                            statusMessage = "\(L10n.tr("save_failed")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(L10n.tr("save"), systemImage: "tray.and.arrow.down")
                }

                Button {
                    Task {
                        do {
                            if let url = try await configService.saveAs() {
                                statusMessage = "\(L10n.tr("saved_as")): \(url.lastPathComponent)"
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(L10n.tr("save_failed")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(L10n.tr("save_as"), systemImage: "folder.badge.plus")
                }

                Spacer()

                Button(role: .destructive) {
                    showNewConfirmation = true
                } label: {
                    Label(L10n.tr("new_configuration"), systemImage: "plus.square.dashed")
                }
            }
        } header: {
            Text(L10n.tr("config_backup"))
        } footer: {
            Text(loc("Export connections, folders, and preferences to a JSON file, or restore from a previous backup.", "Xuất danh sách kết nối, thư mục và tùy chọn ra tệp JSON, hoặc khôi phục từ bản sao lưu."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
