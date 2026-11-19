//
//  LocalFileTableView.swift
//  macSSH
//
//  Native NSTableView for Local Files pane with drag-and-drop upload and context menus
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalFileTableView: NSViewRepresentable {
    @Bindable var state: LocalFileBrowserState
    let onUpload: (RemoteFile) -> Void
    let onNavigate: (URL) -> Void
    var onDropRemoteFiles: ((URL, [RemoteFile]) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = LocalContextMenuTableView()

        // Configure columns
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 180
        nameColumn.minWidth = 100
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 70
        sizeColumn.minWidth = 50
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Type"
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

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(sizeColumn)
        tableView.addTableColumn(kindColumn)
        tableView.addTableColumn(dateColumn)

        // Configure table appearance
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 24

        // Drag source and destination setup
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.registerForDraggedTypes([.fileURL, .remoteFiles, NSPasteboard.PasteboardType("com.apple.NSFilePromiseProvider")])

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.onDoubleClicked(_:))

        context.coordinator.tableView = tableView
        context.coordinator.files = state.files

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let currentFiles = state.files
        let filesChanged = context.coordinator.files != currentFiles
        context.coordinator.files = currentFiles
        context.coordinator.state = state
        context.coordinator.onUpload = onUpload
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onDropRemoteFiles = onDropRemoteFiles

        if let tableView = scrollView.documentView as? NSTableView {
            context.coordinator.isUpdating = true
            if filesChanged {
                tableView.reloadData()
            }

            // Update selection without triggering recursive observer loop
            let currentSelected = state.selectedFileIds
            var indexSet = IndexSet()
            for (index, file) in currentFiles.enumerated() {
                if currentSelected.contains(file.id) {
                    indexSet.insert(index)
                }
            }
            if filesChanged || tableView.selectedRowIndexes != indexSet {
                tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
            }
            context.coordinator.isUpdating = false
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let tableView = scrollView.documentView as? NSTableView {
            tableView.delegate = nil
            tableView.dataSource = nil
            tableView.target = nil
        }
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onUpload: onUpload, onNavigate: onNavigate, onDropRemoteFiles: onDropRemoteFiles)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var state: LocalFileBrowserState?
        var files: [RemoteFile] = []
        var onUpload: (RemoteFile) -> Void
        var onNavigate: (URL) -> Void
        var onDropRemoteFiles: ((URL, [RemoteFile]) -> Void)?
        weak var tableView: NSTableView?
        var isUpdating: Bool = false

        func cleanup() {
            files.removeAll()
            state = nil
            tableView = nil
            onUpload = { _ in }
            onNavigate = { _ in }
            onDropRemoteFiles = nil
        }

        init(state: LocalFileBrowserState, onUpload: @escaping (RemoteFile) -> Void, onNavigate: @escaping (URL) -> Void, onDropRemoteFiles: ((URL, [RemoteFile]) -> Void)? = nil) {
            self.state = state
            self.files = state.files
            self.onUpload = onUpload
            self.onNavigate = onNavigate
            self.onDropRemoteFiles = onDropRemoteFiles
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            state?.files.count ?? 0
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let state = state, row < state.files.count else { return nil }
            let file = state.files[row]
            let columnId = tableColumn?.identifier.rawValue ?? ""
            let cellId = NSUserInterfaceItemIdentifier("LocalCell_\(columnId)")
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
                    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                    cell.imageView?.image = image.withSymbolConfiguration(config)
                    if file.isDirectory {
                        cell.imageView?.contentTintColor = .systemBlue
                    } else {
                        cell.imageView?.contentTintColor = .secondaryLabelColor
                    }
                }

            case "size":
                cell.textField?.stringValue = file.displaySize
                cell.textField?.textColor = .secondaryLabelColor

            case "kind":
                cell.textField?.stringValue = FileTypeService.typeDescription(for: file)
                cell.textField?.textColor = .secondaryLabelColor

            case "date":
                cell.textField?.stringValue = file.modificationDate?.fileListDisplayString ?? "--"
                cell.textField?.textColor = .secondaryLabelColor

            default:
                break
            }

            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let state = state, let tableView = notification.object as? NSTableView else { return }
            let selectedIndexes = tableView.selectedRowIndexes
            var newSelectedIds = Set<UUID>()
            for index in selectedIndexes {
                if index < state.files.count {
                    newSelectedIds.insert(state.files[index].id)
                }
            }
            state.selectedFileIds = newSelectedIds
        }

        @objc func onDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard let state = state, row >= 0, row < state.files.count else { return }
            let file = state.files[row]

            if file.isDirectory {
                let targetURL = URL(fileURLWithPath: file.path)
                onNavigate(targetURL)
            } else {
                let url = URL(fileURLWithPath: file.path)
                NSWorkspace.shared.open(url)
            }
        }

        // MARK: - Drag & Drop Source (Local files dragged out)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard let state = state, row < state.files.count else { return nil }
            let file = state.files[row]
            return NSURL(fileURLWithPath: file.path)
        }

        // MARK: - Drag & Drop Destination (Remote files or Finder files dropped into Local pane)

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard let state = state else { return [] }
            // Check if this is an internal remote file drag
            let isRemoteFileDrag = info.draggingPasteboard.data(forType: .remoteFiles) != nil
            let isFinderDrag = info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])

            guard isRemoteFileDrag || isFinderDrag else {
                // Also accept NSFilePromiseReceiver
                if info.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
                    if row >= 0 && row < state.files.count && state.files[row].isDirectory {
                        tableView.setDropRow(row, dropOperation: .on)
                    } else {
                        tableView.setDropRow(-1, dropOperation: .on)
                    }
                    return .copy
                }
                return []
            }

            // Hovering over a directory row -> Drop into that folder
            if row >= 0 && row < state.files.count {
                let targetFile = state.files[row]
                if targetFile.isDirectory {
                    tableView.setDropRow(row, dropOperation: .on)
                    return .copy
                }
            }

            // Drop on table background (current directory)
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let state = state else { return false }
            // Determine destination directory URL
            let destinationURL: URL = {
                if row >= 0 && row < state.files.count && state.files[row].isDirectory {
                    return URL(fileURLWithPath: state.files[row].path)
                }
                return state.currentURL
            }()

            // 1. Handle Remote Files drop (download to local directory)
            if let remoteData = info.draggingPasteboard.data(forType: .remoteFiles),
               let remoteFiles = try? JSONDecoder().decode([RemoteFile].self, from: remoteData),
               !remoteFiles.isEmpty {
                onDropRemoteFiles?(destinationURL, remoteFiles)
                return true
            }

            // 2. Handle NSFilePromiseReceiver (drag from remote file table via promise)
            if let receivers = info.draggingPasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
               !receivers.isEmpty {
                let dropOperationQueue = OperationQueue()
                dropOperationQueue.qualityOfService = .userInitiated
                for receiver in receivers {
                    receiver.receivePromisedFiles(atDestination: destinationURL, options: [:], operationQueue: dropOperationQueue) { [weak self] fileURL, error in
                        if error == nil {
                            Task { @MainActor [weak self] in
                                await self?.state?.loadFiles(silent: true)
                            }
                        }
                    }
                }
                return true
            }

            // 3. Handle Finder file drop (copy local files into the target folder)
            if let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                let validURLs = urls.filter { url in
                    var isDir: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                }
                guard !validURLs.isEmpty else { return false }

                Task { @MainActor [weak self] in
                    for url in validURLs {
                        let dest = destinationURL.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: dest)
                    }
                    await self?.state?.loadFiles(silent: true)
                }
                return true
            }

            return false
        }

        // MARK: - Sort

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let state = state,
                  let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key else { return }

            switch key {
            case "name": state.sortCriteria = .name
            case "size": state.sortCriteria = .size
            case "kind": state.sortCriteria = .type
            case "date": state.sortCriteria = .date
            default: break
            }
            state.sortAscending = sortDescriptor.ascending
        }
    }
}

// MARK: - Local Context Menu Table View

@MainActor
final class LocalContextMenuTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else {
            return super.menu(for: event)
        }

        let menu = NSMenu()

        if row >= 0, row < state.files.count {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            let file = state.files[row]

            if !file.isDirectory {
                let uploadItem = NSMenuItem(
                    title: L10n.tr("upload_to_remote"),
                    action: #selector(handleUpload(_:)),
                    keyEquivalent: ""
                )
                uploadItem.target = self
                uploadItem.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)
                menu.addItem(uploadItem)

                // Open With Default App
                let openWithDefaultItem = NSMenuItem(
                    title: L10n.tr("open_with_default"),
                    action: #selector(handleOpenWithDefaultApp(_:)),
                    keyEquivalent: ""
                )
                openWithDefaultItem.target = self
                openWithDefaultItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
                menu.addItem(openWithDefaultItem)

                // Open With → submenu listing compatible apps
                let suggestedApps = ExternalEditorService.suggestedApplications(for: file.name)
                if !suggestedApps.isEmpty {
                    let openWithSubmenu = NSMenu(title: L10n.tr("open_with"))
                    for app in suggestedApps {
                        let appItem = NSMenuItem(title: app.name, action: #selector(handleOpenWithSpecificApp(_:)), keyEquivalent: "")
                        appItem.target = self
                        appItem.representedObject = app.url
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
            }

            let openFinderItem = NSMenuItem(
                title: L10n.tr("show_in_finder"),
                action: #selector(handleShowInFinder(_:)),
                keyEquivalent: ""
            )
            openFinderItem.target = self
            openFinderItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            menu.addItem(openFinderItem)

            menu.addItem(NSMenuItem.separator())

            let renameItem = NSMenuItem(
                title: L10n.tr("rename"),
                action: #selector(handleRename(_:)),
                keyEquivalent: ""
            )
            renameItem.target = self
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(
                title: L10n.tr("move_to_trash"),
                action: #selector(handleDelete(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            menu.addItem(deleteItem)

            menu.addItem(NSMenuItem.separator())
        }

        let newFolderItem = NSMenuItem(
            title: L10n.tr("new_folder"),
            action: #selector(handleNewFolder(_:)),
            keyEquivalent: ""
        )
        newFolderItem.target = self
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        menu.addItem(newFolderItem)

        let refreshItem = NSMenuItem(
            title: L10n.tr("refresh"),
            action: #selector(handleRefresh(_:)),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refreshItem)

        return menu
    }

    @objc private func handleUpload(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        for file in state.selectedFiles where !file.isDirectory {
            coordinator.onUpload(file)
        }
    }

    @objc private func handleOpenWithDefaultApp(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        for file in state.selectedFiles where !file.isDirectory {
            let url = URL(fileURLWithPath: file.path)
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleOpenWithSpecificApp(_ sender: Any) {
        guard let menuItem = sender as? NSMenuItem,
              let appURL = menuItem.representedObject as? URL,
              let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        let config = NSWorkspace.OpenConfiguration()
        for file in state.selectedFiles where !file.isDirectory {
            let fileURL = URL(fileURLWithPath: file.path)
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
        }
    }

    @objc private func handleShowInFinder(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        for file in state.selectedFiles {
            let url = URL(fileURLWithPath: file.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func handleRename(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state,
              let first = state.selectedFiles.first else { return }
        state.fileToRename = first
        state.isShowingRenameSheet = true
    }

    @objc private func handleDelete(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        let selected = state.selectedFiles
        guard !selected.isEmpty else { return }
        state.filesToDelete = selected
        state.isShowingDeleteConfirmation = true
    }

    @objc private func handleNewFolder(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        state.isShowingNewFolderSheet = true
    }

    @objc private func handleRefresh(_ sender: Any) {
        guard let coordinator = delegate as? LocalFileTableView.Coordinator,
              let state = coordinator.state else { return }
        Task { await state.refresh() }
    }
}
