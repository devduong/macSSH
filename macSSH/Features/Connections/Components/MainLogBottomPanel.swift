//
//  MainLogBottomPanel.swift
//  macSSH
//
//  Bottom log panel displayed on the main connection list view
//

import SwiftUI
import AppKit

struct MainLogBottomPanel: View {
    @Binding var isPresented: Bool
    @State private var logStore = AppLogStore.shared
    @State private var selectedLevel: LogLevelFilter = .all
    @State private var selectedCategory: LogCategoryFilter = .all
    @State private var searchText = ""
    @State private var isAutoScrollEnabled = true
    @State private var panelHeight: CGFloat = 220
    @State private var isCopiedFeedback = false

    enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case info = "INFO"
        case success = "SUCCESS"
        case warning = "WARN"
        case error = "ERROR"

        var id: String { rawValue }

        func matches(_ level: LogLevel) -> Bool {
            switch self {
            case .all: return true
            case .info: return level == .info
            case .success: return level == .success
            case .warning: return level == .warning
            case .error: return level == .error
            }
        }
    }

    enum LogCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case network = "Network"
        case socks5 = "SOCKS5"
        case sftp = "SFTP"
        case terminal = "Terminal"
        case auth = "Auth"
        case database = "Database"
        case app = "App"

        var id: String { rawValue }

        func matches(_ category: LogCategory) -> Bool {
            switch self {
            case .all: return true
            case .network: return category == .network
            case .socks5: return category == .socks5
            case .sftp: return category == .sftp
            case .terminal: return category == .terminal
            case .auth: return category == .auth
            case .database: return category == .database
            case .app: return category == .app
            }
        }
    }

    private var filteredEntries: [AppLogEntry] {
        logStore.entries.filter { entry in
            let matchesLevel = selectedLevel.matches(entry.level)
            let matchesCategory = selectedCategory.matches(entry.category)
            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
                entry.level.rawValue.localizedCaseInsensitiveContains(searchText)

            return matchesLevel && matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag Resize Handle Bar
            resizeHandleBar

            // Header Toolbar
            headerToolbar

            Divider()

            // Console Log List Area
            logListView
        }
        .frame(height: panelHeight)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Drag Resize Handle
    private var resizeHandleBar: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 3)
            Spacer()
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(ResizeCursorView())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newHeight = panelHeight - value.translation.height
                    panelHeight = max(120, min(600, newHeight))
                }
        )
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 8) {
            // Title with Live Indicator
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                Text(loc("Activity Logs", "Nhật ký hoạt động"))
                    .font(.system(size: 11, weight: .semibold))

                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help(loc("Live monitoring active", "Đang ghi nhận nhật ký trực tiếp"))

                Text("\(filteredEntries.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer()

            // Filter Level Menu
            Picker("", selection: $selectedLevel) {
                ForEach(LogLevelFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 85)
            .controlSize(.small)

            // Filter Category Menu
            Picker("", selection: $selectedCategory) {
                ForEach(LogCategoryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 95)
            .controlSize(.small)

            // Search Text Field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField(loc("Filter...", "Lọc..."), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(width: 120)

            Divider()
                .frame(height: 14)

            // Test Log Button
            Button {
                logStore.emitTestLogs()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "flask.fill")
                    Text(loc("Test Log", "Thử log"))
                }
                .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(loc("Emit simulated test log messages", "Phát các bản ghi log thử nghiệm"))

            // Copy Button
            Button {
                logStore.copyToClipboard(filteredEntries: filteredEntries)
                isCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isCopiedFeedback = false
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopiedFeedback ? "checkmark" : "doc.on.doc")
                    Text(isCopiedFeedback ? loc("Copied!", "Đã sao chép!") : loc("Copy", "Sao chép"))
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(loc("Copy visible logs to clipboard", "Sao chép toàn bộ log hiển thị"))

            // Clear Button
            Button {
                logStore.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(loc("Clear all logs", "Xoá sạch nhật ký"))

            // Close Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
            .help(loc("Close log panel", "Đóng khung nhật ký"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Log List View
    private var logListView: some View {
        Group {
            if filteredEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(loc("No logs recorded matching current filter", "Không có nhật ký phù hợp với bộ lọc hiện tại"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button(loc("Emit Test Logs", "Tạo Log Mẫu")) {
                        logStore.emitTestLogs()
                    }
                    .controlSize(.small)
                    .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: logStore.entries.count) { _, _ in
                        if isAutoScrollEnabled, let first = filteredEntries.first {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    private func logRow(_ entry: AppLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text("[\(entry.formattedTime)]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            // Category Badge
            Text("[\(entry.category.rawValue)]")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor.opacity(0.85))
                .frame(minWidth: 55, alignment: .leading)

            // Level Badge
            Text("[\(entry.level.rawValue)]")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .frame(minWidth: 50, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button(loc("Copy Row", "Sao chép dòng này")) {
                let text = "[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)"
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            Button(loc("Copy Message Only", "Chỉ sao chép nội dung")) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(entry.message, forType: .string)
            }
        }
    }
}

// MARK: - Native AppKit Resize Cursor View
private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorTrackingNSView {
        let view = CursorTrackingNSView()
        return view
    }

    func updateNSView(_ nsView: CursorTrackingNSView, context: Context) {}

    class CursorTrackingNSView: NSView {
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }
}
