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
    @AppStorage("appLanguage") private var selectedLanguage: String = "en"
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = true

    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var ftpSettings = FTPTransferSettings.shared
    @State private var updateService = UpdateService.shared

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                Form {
                    generalSection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(loc("General", "Cài đặt chung"), systemImage: "gearshape")
                }

                Form {
                    securitySection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(loc("Security", "Bảo mật"), systemImage: "lock.shield")
                }

                Form {
                    configurationSection
                }
                .formStyle(.grouped)
                .tabItem {
                    Label(loc("Configuration", "Cấu hình"), systemImage: "doc.badge.gearshape")
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Spacer()
                Button(loc("Done", "Xong")) {
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
            loc("Create New Configuration?", "Tạo file cấu hình mới?"),
            isPresented: $showNewConfirmation,
            titleVisibility: .visible
        ) {
            Button(loc("Create New (Clear All)", "Tạo mới (Xóa tất cả)"), role: .destructive) {
                Task {
                    do {
                        try await configService.newConfiguration()
                        statusMessage = loc("Created new empty configuration.", "Đã tạo cấu hình trống mới.")
                        isErrorMessage = false
                    } catch {
                        statusMessage = "\(loc("Failed", "Thất bại")): \(error.localizedDescription)"
                        isErrorMessage = true
                    }
                }
            }
            Button(loc("Cancel", "Hủy"), role: .cancel) {}
        } message: {
            Text(loc("This will remove all current connections and folders from the application. Make sure to export or save your settings first if you want to keep them.", "Hành động này sẽ xóa toàn bộ các kết nối và thư mục hiện tại. Hãy đảm bảo bạn đã xuất hoặc lưu cài đặt trước."))
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
            Picker(L10n.tr("language"), selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedLanguage) { _, newValue in
                LocalizationManager.shared.currentLanguage = newValue
            }

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
                Label(loc("Require Touch ID", "Yêu cầu Touch ID"), systemImage: "touchid")
            }
            .disabled(!isBiometricAvailable)

            if !isBiometricAvailable {
                Text(loc("Touch ID is not available on this Mac. Use a Mac with Touch ID or an Apple Watch to enable this feature.", "Touch ID không khả dụng trên máy Mac này."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Toggle(isOn: Bindable(appLockManager).lockOnAppResume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Lock when switching apps", "Khóa khi chuyển ứng dụng"))
                        Text(loc("Require authentication when returning to macSSH", "Yêu cầu xác thực khi quay lại macSSH"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Bindable(appLockManager).lockBeforeConnection) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Require before each connection", "Yêu cầu trước mỗi kết nối"))
                        Text(loc("Authenticate before connecting to any server", "Xác thực trước khi kết nối tới bất kỳ máy chủ nào"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Toggle(isOn: Bindable(appLockManager).lockAfterInactivity) {
                        Text(loc("Lock after inactivity", "Khóa khi không hoạt động"))
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
            Text(loc("Security", "Bảo mật"))
        } footer: {
            if isEnabled {
                Text(loc("The app always requires authentication on launch.", "Ứng dụng luôn yêu cầu xác thực khi mở."))
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
                                statusMessage = "\(loc("Exported to", "Đã xuất ra")): \(url.lastPathComponent)"
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(loc("Export failed", "Xuất thất bại")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(loc("Export to JSON…", "Xuất ra JSON…"), systemImage: "square.and.arrow.up")
                }

                Button {
                    Task {
                        do {
                            if try await configService.importSettings(replaceExisting: false) {
                                statusMessage = loc("Settings imported successfully.", "Đã nhập cài đặt thành công.")
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(loc("Import failed", "Nhập thất bại")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(loc("Import from JSON…", "Nhập từ JSON…"), systemImage: "square.and.arrow.down")
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            try await configService.save()
                            statusMessage = configService.lastOperationStatus ?? loc("Saved.", "Đã lưu.")
                            isErrorMessage = false
                        } catch {
                            statusMessage = "\(loc("Save failed", "Lưu thất bại")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(loc("Save", "Lưu"), systemImage: "tray.and.arrow.down")
                }

                Button {
                    Task {
                        do {
                            if let url = try await configService.saveAs() {
                                statusMessage = "\(loc("Saved as", "Đã lưu thành")): \(url.lastPathComponent)"
                                isErrorMessage = false
                            }
                        } catch {
                            statusMessage = "\(loc("Save As failed", "Lưu thành thất bại")): \(error.localizedDescription)"
                            isErrorMessage = true
                        }
                    }
                } label: {
                    Label(loc("Save As…", "Lưu thành…"), systemImage: "folder.badge.plus")
                }

                Spacer()

                Button(role: .destructive) {
                    showNewConfirmation = true
                } label: {
                    Label(loc("New Config", "Cấu hình mới"), systemImage: "plus.square.dashed")
                }
            }
        } header: {
            Text(loc("Configuration & Data", "Cấu hình & Dữ liệu"))
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
