//
//  FileViewerSheet.swift
//  macSSH
//
//  Built-in Universal File Viewer for SFTP, FTP, and SMB servers
//  Supports Text/Code, Images, PDF Documents, Audio/Video, and Hex/Binary Preview
//

import SwiftUI
import AppKit
import PDFKit
import AVKit

struct FileViewerSheet: View {
    let file: RemoteFile
    let localFileURL: URL
    let connection: Connection
    let onOpenInEditor: ((String) -> Void)?
    let onClose: () -> Void

    @State private var viewerMode: ViewerContentMode = .loading
    @State private var zoomScale: CGFloat = 1.0
    @State private var searchText: String = ""
    @State private var isCopied: Bool = false

    enum ViewerContentMode {
        case loading
        case text(String)
        case image(NSImage)
        case pdf(PDFDocument)
        case media(URL)
        case binaryHex(String, Int)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 540, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadFileForViewing()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: FileTypeService.iconName(for: file))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FileTypeService.iconColor(for: file))
                .frame(width: 30, height: 30)
                .background(FileTypeService.iconColor(for: file).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(connection.connectionType.badgeName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                Text("\(connection.name) • \(file.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Mode-specific controls
            switch viewerMode {
            case .text(let content):
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField(loc("Find in file…", "Tìm trong tệp…"), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 140)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isCopied = false
                        }
                    } label: {
                        Label(isCopied ? loc("Copied!", "Đã chép!") : loc("Copy", "Sao chép"), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let onOpenInEditor {
                        Button {
                            onClose()
                            onOpenInEditor(content)
                        } label: {
                            Label(loc("Open in Editor", "Mở trình sửa"), systemImage: "pencil.and.outline")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

            case .image:
                HStack(spacing: 6) {
                    Button {
                        zoomScale = max(0.25, zoomScale - 0.25)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44)

                    Button {
                        zoomScale = min(4.0, zoomScale + 0.25)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(loc("Reset", "Mặc định")) {
                        zoomScale = 1.0
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            default:
                EmptyView()
            }

            Button {
                NSWorkspace.shared.open(localFileURL)
            } label: {
                Label(loc("Open Externally", "Mở bằng App ngoài"), systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch viewerMode {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(loc("Loading file preview…", "Đang tải nội dung tệp…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text(let content):
            textViewer(content: content)

        case .image(let nsImage):
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    VStack {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: max(120, min(nsImage.size.width, geo.size.width - 40) * zoomScale),
                                height: max(120, min(nsImage.size.height, geo.size.height - 40) * zoomScale)
                            )
                            .shadow(radius: 4)
                            .padding(20)
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))

        case .pdf(let document):
            PDFKitRepresentedView(document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .media(let url):
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .binaryHex(let hexDump, let byteCount):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.orange)
                    Text(loc(
                        "Binary File Preview (Hex & ASCII — showing first \(byteCount) bytes)",
                        "Xem trước tệp nhị phân (Hex & ASCII — hiển thị \(byteCount) byte đầu tiên)"
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))

                Divider()

                ScrollView {
                    Text(hexDump)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }

        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    // MARK: - Text Viewer with Line Numbers

    private func textViewer(content: String) -> some View {
        let allLines = content.components(separatedBy: .newlines)
        let filteredLines: [(index: Int, line: String)] = {
            let indexed = allLines.enumerated().map { ($0.offset + 1, $0.element) }
            guard !searchText.isEmpty else { return indexed }
            return indexed.filter { $0.1.localizedCaseInsensitiveContains(searchText) }
        }()

        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(filteredLines, id: \.index) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(item.index)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .trailing)

                        Text(item.line.isEmpty ? " " : item.line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 16) {
            Label(file.displaySize, systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Label(FileTypeService.typeDescription(for: file), systemImage: "doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if !file.permissions.isEmpty {
                Label(file.permissions, systemImage: "lock.shield")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let modDate = file.modificationDate {
                Label(modDate.fileListDisplayString, systemImage: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch viewerMode {
            case .text(let content):
                let lines = content.components(separatedBy: .newlines).count
                Text("\(lines) lines • \(content.count) chars")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .image(let img):
                Text("\(Int(img.size.width)) × \(Int(img.size.height)) px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .pdf(let doc):
                Text("\(doc.pageCount) page(s)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - File Loader & Classifier

    private func loadFileForViewing() async {
        let ext = file.fileExtension.lowercased()

        // 1. Check PDF
        if ext == "pdf", let pdfDoc = PDFDocument(url: localFileURL) {
            viewerMode = .pdf(pdfDoc)
            return
        }

        // 2. Check Image
        if file.fileType == .image, let img = NSImage(contentsOf: localFileURL) {
            viewerMode = .image(img)
            return
        }

        // 3. Check Audio / Video
        if file.fileType == .video || file.fileType == .audio {
            viewerMode = .media(localFileURL)
            return
        }

        // 4. Read raw bytes for text or hex dump
        do {
            let data = try Data(contentsOf: localFileURL)
            if data.isEmpty {
                viewerMode = .text("")
                return
            }

            // Detect if file is text (no null bytes in first 8KB and decodable as UTF-8 / Latin-1)
            let sampleSize = min(data.count, 8192)
            let sample = data.prefix(sampleSize)
            let hasNullByte = sample.contains(0)

            if !hasNullByte {
                if let utf8Text = String(data: data, encoding: .utf8) {
                    viewerMode = .text(utf8Text)
                    return
                } else if let utf16Text = String(data: data, encoding: .utf16) {
                    viewerMode = .text(utf16Text)
                    return
                } else if let latinText = String(data: data, encoding: .isoLatin1) {
                    viewerMode = .text(latinText)
                    return
                }
            }

            // 5. Fallback: Binary Hex + ASCII preview (first 4096 bytes)
            let previewBytes = data.prefix(4096)
            let hexDump = Self.formatHexDump(data: previewBytes)
            viewerMode = .binaryHex(hexDump, previewBytes.count)
        } catch {
            viewerMode = .error(error.localizedDescription)
        }
    }

    private static func formatHexDump(data: Data) -> String {
        var lines: [String] = []
        let bytes = Array(data)
        let rowSize = 16

        for offset in stride(from: 0, to: bytes.count, by: rowSize) {
            let end = min(offset + rowSize, bytes.count)
            let slice = bytes[offset..<end]

            let hexPart = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let paddedHex = hexPart.padding(toLength: rowSize * 3 - 1, withPad: " ", startingAt: 0)

            let asciiPart = slice.map { byte -> String in
                if byte >= 32 && byte <= 126 {
                    return String(UnicodeScalar(byte))
                }
                return "."
            }.joined()

            lines.append(String(format: "%08X  %@  |%@|", offset, paddedHex, asciiPart))
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - PDFKit NSViewRepresentable
private struct PDFKitRepresentedView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
