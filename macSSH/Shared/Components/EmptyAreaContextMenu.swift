//
//  EmptyAreaContextMenu.swift
//  macSSH
//
//  Provides reliable macOS right-click context menu support on empty areas of SwiftUI Lists
//

import SwiftUI
import AppKit

struct EmptyAreaContextMenuItem {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

private final class EmptyAreaMenuTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func handleAction(_ sender: NSMenuItem) {
        action()
    }
}

/// Marker NSView used to explicitly exclude overlaid/inset regions (e.g. bottom log panel)
private final class EmptyAreaExcludedNSView: NSView {}

private struct EmptyAreaExclusionRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> EmptyAreaExcludedNSView {
        let view = EmptyAreaExcludedNSView()
        view.isHidden = false
        return view
    }

    func updateNSView(_ nsView: EmptyAreaExcludedNSView, context: Context) {}
}

private final class EmptyAreaDetectorNSView: NSView {
    var itemsProvider: () -> [EmptyAreaContextMenuItem] = { [] }
    nonisolated(unsafe) private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()

        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleMouseEvent(event)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
        let isRightClick = event.type == .rightMouseDown
        let isControlClick = event.type == .leftMouseDown &&
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control
        guard isRightClick || isControlClick else { return event }

        guard let window = self.window,
              event.window === window,
              window.attachedSheet == nil,
              !AppLockManager.shared.isLocked,
              !self.isHiddenOrHasHiddenAncestor else {
            return event
        }

        let pointInSelf = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(pointInSelf),
              self.safeAreaRect.contains(pointInSelf) else {
            return event
        }

        guard let hitView = (window.contentView?.superview ?? window.contentView)?.hitTest(event.locationInWindow) else {
            return event
        }

        if shouldIgnoreHitView(hitView, eventLocationInWindow: event.locationInWindow) {
            return event
        }

        let items = itemsProvider()
        guard !items.isEmpty else { return event }

        let menu = NSMenu()
        for itemConfig in items {
            let menuItem = NSMenuItem(
                title: itemConfig.title,
                action: #selector(EmptyAreaMenuTarget.handleAction(_:)),
                keyEquivalent: ""
            )
            if let symbolName = itemConfig.systemImage,
               let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: itemConfig.title) {
                menuItem.image = image
            }
            let target = EmptyAreaMenuTarget(action: itemConfig.action)
            menuItem.target = target
            menuItem.representedObject = target
            menu.addItem(menuItem)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        return nil
    }

    private func shouldIgnoreHitView(_ hitView: NSView, eventLocationInWindow: NSPoint) -> Bool {
        var current: NSView? = hitView
        while let view = current {
            if view is EmptyAreaExcludedNSView ||
               view is NSScroller ||
               view is NSTableHeaderView ||
               view is NSControl ||
               view is NSTextView ||
               view is NSTableRowView {
                return true
            }

            let className = NSStringFromClass(type(of: view))
            if className.contains("Titlebar") ||
               className.contains("Toolbar") ||
               className.contains("ThemeFrame") {
                return true
            }

            if let tableView = view as? NSTableView {
                let pointInTable = tableView.convert(eventLocationInWindow, from: nil)
                if tableView.row(at: pointInTable) >= 0 {
                    return true
                }
            } else if let clipView = view as? NSClipView,
                      let tableView = clipView.documentView as? NSTableView {
                let pointInTable = tableView.convert(eventLocationInWindow, from: nil)
                if tableView.row(at: pointInTable) >= 0 {
                    return true
                }
            }

            current = view.superview
        }

        // Also check sibling excluded views in case an excluded panel overlaps in safeAreaInset
        if let contentView = window?.contentView,
           hasExcludedDescendant(in: contentView, containingWindowPoint: eventLocationInWindow) {
            return true
        }

        return false
    }

    private func hasExcludedDescendant(in root: NSView, containingWindowPoint point: NSPoint) -> Bool {
        if root is EmptyAreaExcludedNSView {
            let localPoint = root.convert(point, from: nil)
            return root.bounds.contains(localPoint) && !root.isHiddenOrHasHiddenAncestor
        }
        for subview in root.subviews {
            if hasExcludedDescendant(in: subview, containingWindowPoint: point) {
                return true
            }
        }
        return false
    }
}

private struct EmptyAreaContextMenuRepresentable: NSViewRepresentable {
    let itemsProvider: () -> [EmptyAreaContextMenuItem]

    func makeNSView(context: Context) -> EmptyAreaDetectorNSView {
        let view = EmptyAreaDetectorNSView()
        view.itemsProvider = itemsProvider
        return view
    }

    func updateNSView(_ nsView: EmptyAreaDetectorNSView, context: Context) {
        nsView.itemsProvider = itemsProvider
    }

    static func dismantleNSView(_ nsView: EmptyAreaDetectorNSView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

extension View {
    func emptyAreaContextMenu(_ itemsProvider: @escaping () -> [EmptyAreaContextMenuItem]) -> some View {
        background(EmptyAreaContextMenuRepresentable(itemsProvider: itemsProvider))
    }

    func excludeFromEmptyAreaContextMenu() -> some View {
        background(EmptyAreaExclusionRepresentable())
    }
}
