//
//  NativeFileTableView.swift
//  macSSH
//
//  NSViewRepresentable wrapping NSTableView for native drag and drop support
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Custom pasteboard type for internal Remote → Local file drag
extension NSPasteboard.PasteboardType {
    static let remoteFiles = NSPasteboard.PasteboardType("com.macSSH.remoteFiles")
}

struct NativeFileTableView: NSViewRepresentable {
    @Bindable var viewModel: FileBrowserViewModel
    let files: [RemoteFile]
    let onDoubleClick: (RemoteFile) -> Void
    let onGetInfo: (RemoteFile) -> Void
    let onOpenEditor: ((RemoteFile) -> Void)?

    init(
        viewModel: FileBrowserViewModel,
        files: [RemoteFile],
        onDoubleClick: @escaping (RemoteFile) -> Void,
        onGetInfo: @escaping (RemoteFile) -> Void,
        onOpenEditor: ((RemoteFile) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.files = files
        self.onDoubleClick = onDoubleClick
        self.onGetInfo = onGetInfo
        self.onOpenEditor = onOpenEditor
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = ContextMenuTableView()

        // Configure columns
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 180
        nameColumn.minWidth = 100
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 80
        kindColumn.minWidth = 50
        kindColumn.resizingMask = .userResizingMask
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date Modified"
        dateColumn.width = 120
        dateColumn.minWidth = 80
        dateColumn.resizingMask = .userResizingMask
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 70
        sizeColumn.minWidth = 50
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(kindColumn)
        tableView.addTableColumn(dateColumn)
        tableView.addTableColumn(sizeColumn)

        // Configure table appearance
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.gridStyleMask = []

        // Set up actions
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        // Enable drag and drop
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.registerForDraggedTypes([.fileURL, .remoteFiles, NSPasteboard.PasteboardType("com.apple.NSFilePromiseProvider")])

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        // Set up context menu
        tableView.contextMenuDelegate = context.coordinator

        // Configure scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        context.coordinator.tableView = tableView
        context.coordinator.files = files
        tableView.reloadData()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.files = files
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onGetInfo = onGetInfo
        context.coordinator.onOpenEditor = onOpenEditor

        // Update selection state and reload data
        if let tableView = context.coordinator.tableView {
            context.coordinator.isUpdating = true
            tableView.reloadData()

            // Sync selection from viewModel to tableView
            let selectedIndexes = NSMutableIndexSet()
            for (index, file) in files.enumerated() {
                if viewModel.selectedFiles.contains(file.id) {
                    selectedIndexes.add(index)
                }
            }
            tableView.selectRowIndexes(selectedIndexes as IndexSet, byExtendingSelection: false)
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            files: files,
            onDoubleClick: onDoubleClick,
            onGetInfo: onGetInfo,
            onOpenEditor: onOpenEditor
        )
    }

    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSFilePromiseProviderDelegate, ContextMenuTableViewDelegate {
        var viewModel: FileBrowserViewModel
        var files: [RemoteFile]
        var onDoubleClick: (RemoteFile) -> Void
        var onGetInfo: (RemoteFile) -> Void
        var onOpenEditor: ((RemoteFile) -> Void)?
        weak var tableView: NSTableView?
        var isUpdating = false

        // Track files being dragged for file promise
        private var draggedFiles: [RemoteFile] = []
        private let filePromiseQueue = OperationQueue()

        init(
            viewModel: FileBrowserViewModel,
            files: [RemoteFile],
            onDoubleClick: @escaping (RemoteFile) -> Void,
            onGetInfo: @escaping (RemoteFile) -> Void,
            onOpenEditor: ((RemoteFile) -> Void)?
        ) {
            self.viewModel = viewModel
            self.files = files
            self.onDoubleClick = onDoubleClick
            self.onGetInfo = onGetInfo
            self.onOpenEditor = onOpenEditor
            self.filePromiseQueue.qualityOfService = .userInitiated
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            files.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < files.count else { return nil }
            let file = files[row]
            let columnId = tableColumn?.identifier.rawValue ?? "name"
            let cellId = NSUserInterfaceItemIdentifier("Cell_\(columnId)")
            let isNameColumn = (columnId == "name")

            let cell: FileTableCellView
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? FileTableCellView {
                cell = reused
            } else {
                cell = FileTableCellView(identifier: cellId, isNameColumn: isNameColumn)
            }

            switch columnId {
            case "name":
                cell.textField?.stringValue = file.name
                cell.textField?.textColor = .labelColor
                let iconName = FileTypeService.iconName(for: file)
                if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                    cell.imageView?.image = image.withSymbolConfiguration(config)
                    if file.isDirectory {
                        cell.imageView?.contentTintColor = .systemBlue
                    } else {
                        cell.imageView?.contentTintColor = .secondaryLabelColor
                    }
                }
            case "kind":
                cell.textField?.stringValue = FileTypeService.typeDescription(for: file)
                cell.textField?.textColor = .secondaryLabelColor
            case "date":
                cell.textField?.stringValue = file.modificationDate?.fileListDisplayString ?? "--"
                cell.textField?.textColor = .secondaryLabelColor
            case "size":
                cell.textField?.stringValue = file.displaySize
                cell.textField?.textColor = .secondaryLabelColor
            default:
                break
            }

            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let tableView = tableView else { return }
            let selectedIndexes = tableView.selectedRowIndexes
            var newSelection = Set<UUID>()
            for index in selectedIndexes {
                if index < files.count {
                    newSelection.insert(files[index].id)
                }
            }
            viewModel.selectedFiles = newSelection
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key else { return }

            switch key {
            case "name":
                viewModel.sortCriteria = .name
            case "kind":
                viewModel.sortCriteria = .type
            case "date":
                viewModel.sortCriteria = .date
            case "size":
                viewModel.sortCriteria = .size
            default:
                break
            }

            viewModel.sortAscending = sortDescriptor.ascending
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 && row < files.count else { return }
            let file = files[row]
            onDoubleClick(file)
        }

        // MARK: - Drag OUT (Download via File Promise + Custom Pasteboard)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < files.count else { return nil }
            let file = files[row]

            // Use NSFilePromiseProvider for drags to Finder
            let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: self)
            provider.userInfo = ["file": file, "row": row]
            return provider
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            // Collect all files being dragged
            draggedFiles = rowIndexes.compactMap { index in
                guard index < files.count else { return nil }
                return files[index]
            }
            viewModel.draggedRemoteFiles = draggedFiles

            // Also write serialized remote files to pasteboard for in-app drops
            if let jsonData = try? JSONEncoder().encode(draggedFiles) {
                session.draggingPasteboard.setData(jsonData, forType: .remoteFiles)
            }
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            draggedFiles = []
            viewModel.draggedRemoteFiles = []
        }

        // MARK: - NSFilePromiseProviderDelegate

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
                  let file = userInfo["file"] as? RemoteFile else {
                return "unknown"
            }
            return file.name
        }

        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            guard let userInfo = filePromiseProvider.userInfo as? [String: Any],
                  let file = userInfo["file"] as? RemoteFile else {
                completionHandler(nil)
                return
            }

            Task { @MainActor in
                do {
                    try await viewModel.downloadFileToURL(file, destinationURL: url)
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                }
            }
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            filePromiseQueue
        }

        // MARK: - Drop IN (Upload & Move)

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            let isFinderDrag = info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            let isInternalDrag = !draggedFiles.isEmpty

            guard isFinderDrag || isInternalDrag else { return [] }

            // Hovering over a specific directory row -> Drop into that folder
            if row >= 0 && row < files.count {
                let targetFile = files[row]
                if targetFile.isDirectory {
                    // Prevent moving a directory into itself
                    if isInternalDrag && draggedFiles.contains(where: { $0.path == targetFile.path }) {
                        return []
                    }
                    tableView.setDropRow(row, dropOperation: .on)
                    return isInternalDrag ? .move : .copy
                }
            }

            // Drop on table background (current directory)
            if isFinderDrag {
                tableView.setDropRow(-1, dropOperation: .on)
                return .copy
            }

            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let targetDir: String = {
                if row >= 0 && row < files.count && files[row].isDirectory {
                    return files[row].path
                }
                return viewModel.currentPath
            }()

            // Handle internal remote file move
            if !draggedFiles.isEmpty {
                let filesToMove = draggedFiles
                draggedFiles = []
                Task { @MainActor in
                    await viewModel.moveFiles(filesToMove, to: targetDir)
                }
                return true
            }

            // Handle external Finder drag-and-drop upload
            if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                let validURLs = urls.filter { url in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                }

                guard !validURLs.isEmpty else { return false }

                Task { @MainActor in
                    await viewModel.uploadDroppedFiles(validURLs, to: targetDir)
                }
                return true
            }

            return false
        }
    }
}

// MARK: - Context Menu Support
extension NativeFileTableView.Coordinator {
    func contextMenu(for row: Int) -> NSMenu? {
        guard row >= 0 && row < files.count else { return nil }
        let file = files[row]

        let menu = NSMenu()

        if file.isFile {
            let openItem = NSMenuItem(title: L10n.tr("open_in_editor"), action: #selector(handleOpenInEditor(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = file
            openItem.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
            menu.addItem(openItem)

            // Open With Default App (download, open, auto-upload on save)
            let openWithDefaultItem = NSMenuItem(title: L10n.tr("open_with_default"), action: #selector(handleOpenWithDefaultApp(_:)), keyEquivalent: "")
            openWithDefaultItem.target = self
            openWithDefaultItem.representedObject = file
            openWithDefaultItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            menu.addItem(openWithDefaultItem)

            // Open With → submenu listing compatible apps
            let suggestedApps = ExternalEditorService.suggestedApplications(for: file.name)
            if !suggestedApps.isEmpty {
                let openWithSubmenu = NSMenu(title: L10n.tr("open_with"))
                for app in suggestedApps {
                    let appItem = NSMenuItem(title: app.name, action: #selector(handleOpenWithSpecificApp(_:)), keyEquivalent: "")
                    appItem.target = self
                    appItem.representedObject = ["file": file, "appURL": app.url]
                    if let appIcon = NSWorkspace.shared.icon(forFile: app.url.path) as NSImage? {
                        appIcon.size = NSSize(width: 16, height: 16)
                        appItem.image = appIcon
                    }
                    openWithSubmenu.addItem(appItem)
                }
                let openWithItem = NSMenuItem(title: L10n.tr("open_with"), action: nil, keyEquivalent: "")
                openWithItem.image = NSImage(systemSymbolName: "app.badge.checkmark", accessibilityDescription: nil)
                openWithItem.submenu = openWithSubmenu
                menu.addItem(openWithItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        let copyItem = NSMenuItem(title: L10n.tr("copy"), action: #selector(handleCopy(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = file
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)

        let cutItem = NSMenuItem(title: L10n.tr("cut"), action: #selector(handleCut(_:)), keyEquivalent: "")
        cutItem.target = self
        cutItem.representedObject = file
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        menu.addItem(cutItem)

        if viewModel.canPaste {
            let pasteItem = NSMenuItem(title: L10n.tr("paste"), action: #selector(handlePaste(_:)), keyEquivalent: "")
            pasteItem.target = self
            pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            menu.addItem(pasteItem)
        }

        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: L10n.tr("rename"), action: #selector(handleRename(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = file
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(renameItem)

        let moveItem = NSMenuItem(title: L10n.tr("move_to"), action: #selector(handleMoveTo(_:)), keyEquivalent: "m")
        moveItem.target = self
        moveItem.representedObject = file
        moveItem.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil)
        menu.addItem(moveItem)

        let infoItem = NSMenuItem(title: L10n.tr("get_info"), action: #selector(handleGetInfo(_:)), keyEquivalent: "")
        infoItem.target = self
        infoItem.representedObject = file
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let downloadToLocalItem = NSMenuItem(title: L10n.tr("download_to_local"), action: #selector(handleDownloadToLocalPane(_:)), keyEquivalent: "")
        downloadToLocalItem.target = self
        downloadToLocalItem.representedObject = file
        downloadToLocalItem.image = NSImage(systemSymbolName: "arrow.left.circle", accessibilityDescription: nil)
        menu.addItem(downloadToLocalItem)

        if file.isFile {
            let downloadAsItem = NSMenuItem(title: L10n.tr("download_as"), action: #selector(handleDownload(_:)), keyEquivalent: "")
            downloadAsItem.target = self
            downloadAsItem.representedObject = file
            downloadAsItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(downloadAsItem)
        }

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: L10n.tr("delete"), action: #selector(handleDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = file
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)

        return menu
    }

    @objc func handleOpenInEditor(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        onOpenEditor?(file)
    }

    @objc func handleOpenWithDefaultApp(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        Task { @MainActor in
            await viewModel.openWithExternalApp(file)
        }
    }

    @objc func handleOpenWithSpecificApp(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let file = info["file"] as? RemoteFile,
              let appURL = info["appURL"] as? URL else { return }
        Task { @MainActor in
            await viewModel.openWithSpecificApp(file, applicationURL: appURL)
        }
    }

    @objc func handleCopy(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.selectedFiles = [file.id]
        viewModel.copySelectedFiles()
    }

    @objc func handleCut(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.selectedFiles = [file.id]
        viewModel.cutSelectedFiles()
    }

    @objc func handlePaste(_ sender: NSMenuItem) {
        Task { @MainActor in
            await viewModel.paste()
        }
    }

    @objc func handleRename(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.startRename(file)
    }

    @objc func handleMoveTo(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        viewModel.requestMove(file)
    }

    @objc func handleGetInfo(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        onGetInfo(file)
    }

    @objc func handleDownloadToLocalPane(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        Task { @MainActor in
            await viewModel.downloadRemoteFileToLocalPane(file)
        }
    }

    @objc func handleDownload(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        Task { @MainActor in
            await viewModel.downloadFile(file)
        }
    }

    @objc func handleDelete(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? RemoteFile else { return }
        // If the right-clicked file is part of a multi-selection, delete all selected files
        if viewModel.selectedFiles.contains(file.id) && viewModel.selectedFiles.count > 1 {
            viewModel.confirmDeleteSelected()
        } else {
            viewModel.confirmDelete([file])
        }
    }
}

// MARK: - Context Menu Table View
protocol ContextMenuTableViewDelegate: AnyObject {
    func contextMenu(for row: Int) -> NSMenu?
}

class ContextMenuTableView: NSTableView {
    weak var contextMenuDelegate: ContextMenuTableViewDelegate?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)

        if row >= 0 {
            // Select the row if not already selected
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return contextMenuDelegate?.contextMenu(for: row)
        }

        return super.menu(for: event)
    }
}

// MARK: - File Table Cell View

final class FileTableCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let labelTextField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier, isNameColumn: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier

        if isNameColumn {
            iconImageView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(iconImageView)
            self.imageView = iconImageView
        }

        labelTextField.lineBreakMode = .byTruncatingTail
        labelTextField.font = NSFont.systemFont(ofSize: 13)
        labelTextField.maximumNumberOfLines = 1
        addSubview(labelTextField)
        self.textField = labelTextField
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if let imageView = imageView {
            let iconSize: CGFloat = 18
            let iconY = (bounds.height - iconSize) / 2
            imageView.frame = NSRect(x: 4, y: iconY, width: iconSize, height: iconSize)

            let textX: CGFloat = 28
            let textHeight: CGFloat = 18
            let textY = (bounds.height - textHeight) / 2
            let textWidth = max(0, bounds.width - textX - 4)
            textField?.frame = NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
        } else {
            let textHeight: CGFloat = 18
            let textY = (bounds.height - textHeight) / 2
            let textWidth = max(0, bounds.width - 8)
            textField?.frame = NSRect(x: 4, y: textY, width: textWidth, height: textHeight)
        }
    }
}
