//
//  ConnectionFormSheet.swift
//  macSSH
//
//  Form for creating and editing connections
//

import SwiftUI

enum ConnectionFormMode {
    case create
    case edit(Connection)

    var title: String {
        switch self {
        case .create: return loc("New Connection", "Thêm kết nối mới")
        case .edit: return loc("Edit Connection", "Chỉnh sửa kết nối")
        }
    }

    var saveButtonTitle: String {
        switch self {
        case .create: return loc("Create", "Tạo")
        case .edit: return loc("Save", "Lưu")
        }
    }
}

struct ConnectionFormSheet: View {
    let mode: ConnectionFormMode
    let savedPassword: String?
    let folders: [Folder]
    let onSave: (Connection, String?) -> Void
    let onCancel: () -> Void

    @ObservedObject private var l10n = LocalizationManager.shared

    // Form fields
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var authMethod: AuthMethod = .password
    @State private var privateKeyPath: String = ""
    @State private var savePassword: Bool = false
    @State private var password: String = ""
    @State private var description: String = ""
    @State private var iconName: String = "server.rack"
    @State private var selectedFolderId: UUID?
    @State private var tags: [String] = []
    @State private var newTag: String = ""

    // SOCKS5 Dynamic Port Forwarding
    @State private var socksProxyEnabled: Bool = false
    @State private var socksProxyPort: String = "1080"
    @State private var socksProxyAllowLAN: Bool = false

    init(
        mode: ConnectionFormMode,
        savedPassword: String? = nil,
        folders: [Folder] = [],
        onSave: @escaping (Connection, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.savedPassword = savedPassword
        self.folders = folders
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(mode.title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()

            Divider()

            Form {
                // Connection details
                Section(loc("Connection Details", "Thông tin kết nối")) {
                    TextField(loc("Name", "Tên kết nối"), text: $name)
                    TextField(loc("Host / IP", "Địa chỉ máy chủ / IP"), text: $host)
                    TextField(loc("Port", "Cổng"), text: $port)
                    TextField(loc("Username", "Tên đăng nhập"), text: $username)
                }

                // Authentication
                Section(loc("Authentication", "Xác thực")) {
                    Picker(loc("Method", "Phương thức"), selection: $authMethod) {
                        ForEach(AuthMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    if authMethod == .password {
                        SecureField(loc("Password", "Mật khẩu"), text: $password)
                        Toggle(loc("Save password in configuration file", "Lưu mật khẩu vào file cấu hình"), isOn: $savePassword)
                    } else {
                        HStack {
                            TextField(loc("Private Key Path", "Đường dẫn khóa riêng (Private Key)"), text: $privateKeyPath)
                            Button(loc("Browse…", "Chọn tệp…")) {
                                browseForKey()
                            }
                        }
                    }
                }

                // SOCKS5 Proxy
                Section(loc("SOCKS5 Proxy (Dynamic Port Forwarding)", "SOCKS5 Proxy (Chuyển tiếp cổng)")) {
                    Toggle(loc("Enable SOCKS5 Proxy", "Bật SOCKS5 Proxy"), isOn: $socksProxyEnabled)
                    if socksProxyEnabled {
                        TextField(loc("Local Proxy Port", "Cổng Proxy cục bộ"), text: $socksProxyPort)
                            .help("Port for SOCKS5 proxy (default 1080)")

                        Toggle(loc("Allow Local Network (LAN) Access", "Cho phép truy cập qua mạng LAN"), isOn: $socksProxyAllowLAN)
                            .help("When enabled, listens on 0.0.0.0 allowing other devices on your LAN to use this proxy.")

                        if socksProxyAllowLAN, let localIP = NetworkUtils.getLocalIPAddress() {
                            Text("LAN Endpoint: \(localIP):\(socksProxyPort)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Organization
                Section(loc("Organization", "Nhóm & Thư mục")) {
                    Picker(loc("Folder", "Thư mục"), selection: $selectedFolderId) {
                        Text(loc("None", "Không có")).tag(nil as UUID?)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(folder.id as UUID?)
                        }
                    }

                    // Tags
                    LabeledContent(loc("Tags", "Thẻ gắn")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField(loc("Add new tag...", "Thêm thẻ mới..."), text: $newTag)
                                    .onSubmit {
                                        addTag()
                                    }
                                Button {
                                    addTag()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(newTag.trimmed.isEmpty ? Color.gray : Color.blue)
                                }
                                .buttonStyle(.plain)
                                .disabled(newTag.trimmed.isEmpty)
                            }

                            if !tags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        TagChip(tag: tag) {
                                            removeTag(tag)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Optional
                Section(loc("Optional", "Tùy chọn bổ sung")) {
                    TextField(loc("Description / Notes", "Mô tả / Ghi chú"), text: $description, axis: .vertical)
                        .lineLimit(2...4)

                    IconPickerRow(selectedIcon: $iconName)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(loc("Cancel", "Hủy")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button(mode.saveButtonTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 580)
        .onAppear {
            loadExistingData()
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        let isPortValid = (Int(port) ?? 0) > 0 && (Int(port) ?? 0) <= 65535
        let isSocksPortValid = !socksProxyEnabled || ((Int(socksProxyPort) ?? 0) > 0 && (Int(socksProxyPort) ?? 0) <= 65535)
        return !name.trimmed.isEmpty &&
            !host.trimmed.isEmpty &&
            !username.trimmed.isEmpty &&
            isPortValid &&
            isSocksPortValid &&
            (authMethod == .password || !privateKeyPath.trimmed.isEmpty)
    }

    // MARK: - Data Loading

    private func loadExistingData() {
        if case .edit(let connection) = mode {
            name = connection.name
            host = connection.host
            port = String(connection.port)
            username = connection.username
            authMethod = connection.authMethod
            privateKeyPath = connection.privateKeyPath ?? ""
            savePassword = connection.savePassword
            description = connection.description ?? ""
            iconName = connection.iconName
            selectedFolderId = connection.folderId
            tags = connection.tags
            socksProxyEnabled = connection.socksProxyEnabled
            socksProxyPort = String(connection.socksProxyPort)
            socksProxyAllowLAN = connection.socksProxyAllowLAN

            if let saved = savedPassword {
                password = saved
            }
        }
    }

    // MARK: - Save

    private func save() {
        let portNumber = Int(port) ?? 22
        let socksPortNumber = Int(socksProxyPort) ?? 1080

        let connection: Connection
        if case .edit(let existing) = mode {
            connection = Connection(
                id: existing.id,
                name: name.trimmed,
                host: host.trimmed,
                port: portNumber,
                username: username.trimmed,
                authMethod: authMethod,
                privateKeyPath: authMethod == .privateKey ? privateKeyPath.trimmed : nil,
                savePassword: savePassword,
                description: description.trimmed.isEmpty ? nil : description.trimmed,
                tags: tags,
                iconName: iconName,
                folderId: selectedFolderId,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                connectionType: .sftp,
                socksProxyEnabled: socksProxyEnabled,
                socksProxyPort: socksPortNumber,
                socksProxyAllowLAN: socksProxyAllowLAN
            )
        } else {
            connection = Connection(
                name: name.trimmed,
                host: host.trimmed,
                port: portNumber,
                username: username.trimmed,
                authMethod: authMethod,
                privateKeyPath: authMethod == .privateKey ? privateKeyPath.trimmed : nil,
                savePassword: savePassword,
                description: description.trimmed.isEmpty ? nil : description.trimmed,
                tags: tags,
                iconName: iconName,
                folderId: selectedFolderId,
                connectionType: .sftp,
                socksProxyEnabled: socksProxyEnabled,
                socksProxyPort: socksPortNumber,
                socksProxyAllowLAN: socksProxyAllowLAN
            )
        }

        let passwordToSave: String? = savePassword && !password.isEmpty ? password : nil
        onSave(connection, passwordToSave)
    }

    // MARK: - Helpers

    private func browseForKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }

    private func addTag() {
        let tag = newTag.trimmed
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

// MARK: - Icon Picker Row
struct IconPickerRow: View {
    @Binding var selectedIcon: String
    @State private var showingIconSelector = false

    var body: some View {
        HStack {
            Text("Icon")
            Spacer()
            Button {
                showingIconSelector.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(selectedIcon)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingIconSelector, arrowEdge: .trailing) {
                IconSelectorView(selectedIcon: $selectedIcon)
            }
        }
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? .red : .primary)

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(.fill.tertiary, in: Capsule())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onRemove()
        }
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview
#Preview("Create") {
    ConnectionFormSheet(
        mode: .create,
        folders: [
            Folder(name: "Production"),
            Folder(name: "Development")
        ],
        onSave: { _, _ in },
        onCancel: {}
    )
}

#Preview("Edit") {
    ConnectionFormSheet(
        mode: .edit(Connection(
            name: "Test Server",
            host: "test.example.com",
            username: "admin",
            tags: ["production", "critical"]
        )),
        savedPassword: "secret123",
        folders: [
            Folder(name: "Production"),
            Folder(name: "Development")
        ],
        onSave: { _, _ in },
        onCancel: {}
    )
}
