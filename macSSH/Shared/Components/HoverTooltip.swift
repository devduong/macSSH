//
//  HoverTooltip.swift
//  macSSH
//
//  Reliable non-activating floating hover tooltip for macOS SwiftUI views
//  using AppKit NSTrackingArea + NSPanel so tooltips appear immediately next to
//  the hovered icon/pill, even inside List/NSTableView rows.
//

import SwiftUI
import AppKit

@MainActor
final class HoverTooltipPresenter {
    static let shared = HoverTooltipPresenter()

    private var panel: NSPanel?
    private var containerView: NSView?
    private var hostingController: NSHostingController<TooltipBubbleView>?
    private var activeOwnerID: UUID?
    private var showTask: Task<Void, Never>?
    nonisolated(unsafe) private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?

    private init() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    func scheduleShow(ownerID: UUID, text: String, anchorScreenRect: NSRect) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let wasAlreadyVisible = panel?.isVisible == true
        showTask?.cancel()
        activeOwnerID = ownerID
        installEventMonitorIfNeeded()

        // Fast response so tooltip appears immediately beside the hovered icon
        let delayNanoseconds: UInt64 = wasAlreadyVisible ? 60_000_000 : 180_000_000
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.activeOwnerID == ownerID, NSApp.isActive else { return }
            self.presentPanel(text: trimmed, anchorScreenRect: anchorScreenRect)
        }
    }

    func updateIfVisible(ownerID: UUID, text: String, anchorScreenRect: NSRect) {
        guard activeOwnerID == ownerID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide(ownerID: ownerID)
            return
        }
        if panel?.isVisible == true {
            presentPanel(text: trimmed, anchorScreenRect: anchorScreenRect)
        }
    }

    func hide(ownerID: UUID? = nil) {
        if let ownerID, activeOwnerID != ownerID {
            return
        }
        showTask?.cancel()
        showTask = nil
        activeOwnerID = nil
        panel?.orderOut(nil)
        removeEventMonitor()
    }

    private func presentPanel(text: String, anchorScreenRect: NSRect) {
        let panel = ensurePanel()
        guard let hostingController, let containerView else { return }

        hostingController.rootView = TooltipBubbleView(text: text)
        let measured = hostingController.sizeThatFits(in: CGSize(width: 300, height: 240))
        let fittingSize = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        containerView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingController.view.frame = containerView.bounds

        let shadowPad: CGFloat = 6
        let gap: CGFloat = 4

        let centerPoint = NSPoint(x: anchorScreenRect.midX, y: anchorScreenRect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(centerPoint) }) ?? NSScreen.main

        var originX = anchorScreenRect.midX - fittingSize.width / 2
        // Visual top sits `gap` pts directly below the icon's bottom edge
        var originY = anchorScreenRect.minY - (fittingSize.height - shadowPad) - gap

        if let visible = screen?.visibleFrame {
            originX = max(visible.minX + 2, min(originX, visible.maxX - fittingSize.width - 2))
            if originY + shadowPad < visible.minY + 4 {
                // Flip directly above the icon if near the bottom of the screen
                originY = anchorScreenRect.maxY + gap - shadowPad
            }
        }

        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: fittingSize), display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }

        let controller = NSHostingController(rootView: TooltipBubbleView(text: ""))
        // Prevent NSHostingView window-min-size constraints from inflating NSPanel height to ~190pt
        controller.sizingOptions = [.intrinsicContentSize]
        let container = NSView(frame: .zero)
        controller.view.autoresizingMask = [.width, .height]
        container.addSubview(controller.view)

        let newPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.minSize = NSSize(width: 1, height: 1)
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.ignoresMouseEvents = true
        newPanel.hidesOnDeactivate = true
        newPanel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        newPanel.animationBehavior = .none
        newPanel.contentView = container

        self.hostingController = controller
        self.containerView = container
        self.panel = newPanel
        return newPanel
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.hide()
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

private struct TooltipBubbleView: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 5, x: 0, y: 2)
            .padding(6)
    }
}

private final class TooltipTrackingNSView: NSView {
    let ownerID = UUID()
    var tooltipText: String = "" {
        didSet {
            if isCurrentlyHovering, let screenRect = screenAnchorRect {
                HoverTooltipPresenter.shared.updateIfVisible(
                    ownerID: ownerID,
                    text: tooltipText,
                    anchorScreenRect: screenRect
                )
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isCurrentlyHovering = false

    private var screenAnchorRect: NSRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept clicks, double-clicks, drags, or context menus
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isCurrentlyHovering = true
        guard let screenRect = screenAnchorRect else { return }
        HoverTooltipPresenter.shared.scheduleShow(
            ownerID: ownerID,
            text: tooltipText,
            anchorScreenRect: screenRect
        )
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isCurrentlyHovering = false
        HoverTooltipPresenter.shared.hide(ownerID: ownerID)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            isCurrentlyHovering = false
            HoverTooltipPresenter.shared.hide(ownerID: ownerID)
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

private struct HoverTooltipRepresentable: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipTrackingNSView {
        let view = TooltipTrackingNSView()
        view.tooltipText = text
        return view
    }

    func updateNSView(_ nsView: TooltipTrackingNSView, context: Context) {
        if nsView.tooltipText != text {
            nsView.tooltipText = text
        }
    }

    static func dismantleNSView(_ nsView: TooltipTrackingNSView, coordinator: ()) {
        HoverTooltipPresenter.shared.hide(ownerID: nsView.ownerID)
    }
}

extension View {
    /// Attaches a responsive floating hover tooltip anchored directly beside the view
    /// using AppKit NSTrackingArea (works reliably inside macOS List/NSTableView rows).
    func hoverTooltip(_ text: String) -> some View {
        overlay(HoverTooltipRepresentable(text: text))
            .accessibilityHint(text)
    }
}
