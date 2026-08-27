//
//  TerminalView.swift
//  macSSH
//
//  Terminal view with SwiftTerm integration
//

import SwiftUI
import AppKit
import SwiftTerm

// MARK: - Terminal View

struct TerminalContentView: View {
    @Bindable var viewModel: TerminalViewModel

    @State private var showConnectionLostBanner = false
    @State private var showSessionEndedBanner = false

    var body: some View {
        VStack(spacing: 0) {
            // Terminal content
            terminalContent

            Divider()

            // Status bar
            statusBar
        }
        .frame(minWidth: WindowSize.minTerminal.width, minHeight: WindowSize.minTerminal.height)
        .navigationTitle(viewModel.connectionName)
        .navigationSubtitle(navigationSubtitleText)
        .toolbar(id: "terminalToolbar") {
            ToolbarItem(id: "openInMacTerminal", placement: .automatic) {
                Button {
                    TerminalLauncherService.openInMacOSTerminal(windowData: viewModel.connectionData)
                } label: {
                    Label("Open in macOS Terminal", systemImage: "terminal.fill")
                }
                .help("Open in macOS Terminal.app")
            }

            ToolbarItem(id: "reconnect", placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.reconnect()
                    }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.state == .connecting)
                .help("Reconnect")
            }


        }
        .task {
            await viewModel.connect()
        }
        .onDisappear {
            Task {
                await viewModel.cleanup()
            }
        }
        .onChange(of: viewModel.state) { oldState, newState in
            // Show banner overlay when connection is lost while terminal was connected
            if case .connected = oldState, case .error = newState {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showConnectionLostBanner = true
                    showSessionEndedBanner = false
                }
            } else if case .connected = oldState, case .disconnected = newState {
                // Graceful session end (e.g. CTRL-D / exit)
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSessionEndedBanner = true
                    showConnectionLostBanner = false
                }
            } else if case .connected = newState {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showConnectionLostBanner = false
                    showSessionEndedBanner = false
                }
            } else if case .connecting = newState {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showConnectionLostBanner = false
                    showSessionEndedBanner = false
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingPasswordPrompt) {
            PasswordPromptSheet(
                connectionName: viewModel.connectionName,
                errorMessage: viewModel.isAuthFailed ? "Authentication failed. Please check your credentials and try again." : nil,
                onConnect: { password in
                    viewModel.isShowingPasswordPrompt = false
                    Task {
                        await viewModel.reconnect(withPassword: password)
                    }
                },
                onCancel: {
                    viewModel.isShowingPasswordPrompt = false
                }
            )
        }
        .errorAlert($viewModel.error)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusBarText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Terminal dimensions
            if viewModel.isConnected || showConnectionLostBanner || showSessionEndedBanner {
                Text(viewModel.terminalSizeText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var terminalContent: some View {
        switch viewModel.state {
        case .disconnected:
            if showSessionEndedBanner {
                // Session ended gracefully — preserve terminal content with overlay
                ZStack {
                    SwiftTermView(viewModel: viewModel)
                        .allowsHitTesting(false)
                        .opacity(0.4)

                    sessionEndedBanner
                }
            } else {
                ContentUnavailableView {
                    Label("Disconnected", systemImage: "terminal")
                } description: {
                    Text("The terminal session is not connected.")
                } actions: {
                    Button {
                        Task {
                            await viewModel.reconnect()
                        }
                    } label: {
                        Text("Connect")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

        case .connecting:
            LoadingView(message: "Connecting...")

        case .connected:
            SwiftTermView(viewModel: viewModel)
                .onAppear {
                    // Focus the terminal once it appears on screen after connection
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // Find and focus the TerminalView inside the SwiftTermView
                        NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView?.findSubview(ofType: SwiftTerm.TerminalView.self))
                    }
                }

        case .error:
            if showConnectionLostBanner {
                // Keep the terminal visible with a reconnect banner overlay
                ZStack {
                    SwiftTermView(viewModel: viewModel)
                        .allowsHitTesting(false)
                        .opacity(0.4)

                    connectionLostBanner
                }
            } else {
                // Initial connection error — no terminal to preserve
                ContentUnavailableView {
                    Label(
                        viewModel.isAuthFailed ? "Authentication Failed" : "Connection Failed",
                        systemImage: viewModel.isAuthFailed ? "key.slash" : "wifi.exclamationmark"
                    )
                } description: {
                    if case .error(let error) = viewModel.state {
                        Text(error.localizedDescription)
                    }
                } actions: {
                    HStack(spacing: 12) {
                        if viewModel.isAuthFailed {
                            Button {
                                viewModel.isShowingPasswordPrompt = true
                            } label: {
                                Label("Enter Password", systemImage: "key")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            Button {
                                Task {
                                    await viewModel.reconnect()
                                }
                            } label: {
                                Text("Try Again")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        } else {
                            Button {
                                Task {
                                    await viewModel.reconnect()
                                }
                            } label: {
                                Text("Try Again")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                }
            }
        }
    }

    private var sessionEndedBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Session Ended")
                .font(.system(size: 15, weight: .semibold))

            Text("The remote shell has exited.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    showSessionEndedBanner = false
                    await viewModel.reconnect()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 5)
        }
    }

    private var connectionLostBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Connection Lost")
                .font(.system(size: 15, weight: .semibold))

            if case .error(let error) = viewModel.state {
                Text(error.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    showConnectionLostBanner = false
                    await viewModel.reconnect()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 5)
        }
    }

    private var statusColor: SwiftUI.Color {
        switch viewModel.state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return showSessionEndedBanner ? .gray : .red
        case .error:
            return .red
        }
    }

    /// Text shown in the window's navigation subtitle
    private var navigationSubtitleText: String {
        switch viewModel.state {
        case .connected:
            return viewModel.connectionString
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return showSessionEndedBanner ? "Session Ended" : "Disconnected"
        case .error:
            return viewModel.isAuthFailed ? "Authentication Failed" : "Connection Error"
        }
    }

    /// Text shown in the bottom status bar
    private var statusBarText: String {
        switch viewModel.state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return showSessionEndedBanner ? "Session Ended" : "Disconnected"
        case .error:
            return viewModel.isAuthFailed ? "Auth Failed" : "Connection Lost"
        }
    }
}

// MARK: - Direct Input Terminal View

/// Subclass of SwiftTerm.TerminalView that bypasses Cocoa / IME marked text composition buffering.
/// Standard SwiftTerm delegates regular typing to `interpretKeyEvents` which gets trapped in `setMarkedText`
/// (which does nothing in SwiftTerm) until Enter or Space is pressed. This class forwards normal character
/// keystrokes immediately so that every keystroke appears in real-time.
final class DirectInputTerminalView: TerminalView {
    private var eventMonitor: Any?
    private var mouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  event.window == window,
                  window.firstResponder == self else {
                return event
            }
            // If modifier keys like Control, Command are held, let SwiftTerm handle them
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.control) || flags.contains(.command) {
                return event
            }

            // If special keys (Esc, Tab, Return, Backspace, Arrow keys, Delete, F-keys)
            if let chars = event.characters, let scalar = chars.unicodeScalars.first?.value {
                if scalar == 0x0D || scalar == 0x0A || // Enter
                   scalar == 0x09 ||                   // Tab
                   scalar == 0x1B ||                   // Esc
                   scalar == 0x7F || scalar == 0x08 || // Backspace
                   flags.contains(.function) {         // Arrows, Function keys
                    return event
                }
            }

            // For printable characters, send directly to terminal and consume event
            if let chars = event.characters, !chars.isEmpty {
                self.send(txt: chars)
                return nil // Event consumed, bypasses interpretKeyEvents buffering
            }

            return event
        }

        // Mouse monitor: double-click to copy, right-click to paste
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  event.window == window else {
                return event
            }

            // Check if the click is inside this terminal view
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else {
                return event
            }

            if event.type == .leftMouseUp && event.clickCount == 2 {
                // Double-click: SwiftTerm has already selected the word in mouseDown.
                // Copy the selection to clipboard.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self else { return }
                    if let selectedText = self.getSelection(), !selectedText.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selectedText, forType: .string)
                        let preview = selectedText.count > 40
                            ? String(selectedText.prefix(40)) + "…"
                            : selectedText
                        self.showLocalToast("Copied: \(preview)", icon: "checkmark.circle.fill", accentColor: .systemGreen)
                    }
                }
                return event
            }

            if event.type == .rightMouseDown {
                // Right-click: paste clipboard content into the terminal
                if let clipboardString = NSPasteboard.general.string(forType: .string),
                   !clipboardString.isEmpty {
                    self.send(txt: clipboardString)
                    let preview = clipboardString.count > 40
                        ? String(clipboardString.prefix(40)) + "…"
                        : clipboardString
                    self.showLocalToast("Pasted: \(preview)", icon: "doc.on.clipboard.fill", accentColor: .systemBlue)
                }
                return nil // Consume event to prevent context menu
            }

            return event
        }
    }

    // MARK: - Local Inline Toast (scoped to this terminal view only)

    private var currentToastView: NSView?
    private var toastDismissWork: DispatchWorkItem?

    private func showLocalToast(_ message: String, icon: String = "doc.on.clipboard", accentColor: NSColor = .systemGreen, duration: TimeInterval = 1.8) {
        // Remove existing toast if any
        toastDismissWork?.cancel()
        currentToastView?.removeFromSuperview()

        // Icon
        let iconView = NSImageView()
        if let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            iconView.image = iconImage.withSymbolConfiguration(config)
            iconView.contentTintColor = accentColor
        }
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Label
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Stack
        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        stack.translatesAutoresizingMaskIntoConstraints = false
        let fittingSize = stack.fittingSize
        let containerWidth = min(fittingSize.width, bounds.width - 32)
        let containerHeight = fittingSize.height

        // Wrapper container (holds shadow, positioned at top-center of terminal)
        let topY = self.isFlipped ? 12 : (bounds.height - containerHeight - 12)
        let container = NSView(frame: NSRect(
            x: (bounds.width - containerWidth) / 2,
            y: topY,
            width: containerWidth,
            height: containerHeight
        ))
        container.autoresizingMask = [.minXMargin, .maxXMargin, self.isFlipped ? .maxYMargin : .minYMargin]
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.25
        container.layer?.shadowRadius = 12
        container.layer?.shadowOffset = CGSize(width: 0, height: -3)

        // Blur background (glassmorphic) with rounded mask
        let blurView = NSVisualEffectView(frame: container.bounds)
        blurView.autoresizingMask = [.width, .height]
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 10
        blurView.layer?.masksToBounds = true
        blurView.layer?.borderWidth = 1
        blurView.layer?.borderColor = accentColor.withAlphaComponent(0.5).cgColor

        // Apply rounded rect mask to clip the blur effect itself
        let maskImage = NSImage(size: blurView.bounds.size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        blurView.maskImage = maskImage

        container.addSubview(blurView)
        stack.frame = blurView.bounds
        stack.autoresizingMask = [.width, .height]
        blurView.addSubview(stack)

        // Fade in
        container.alphaValue = 0
        addSubview(container)
        currentToastView = container

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            container.animator().alphaValue = 1.0
        }

        // Auto-dismiss
        let work = DispatchWorkItem { [weak self, weak container] in
            guard let container = container else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                container.animator().alphaValue = 0
            }, completionHandler: {
                container.removeFromSuperview()
                if self?.currentToastView == container {
                    self?.currentToastView = nil
                }
            })
        }
        toastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? NSString {
            text = str as String
        } else {
            return
        }
        if !text.isEmpty {
            send(txt: text)
        }
    }
}

// MARK: - SwiftTerm View (Minimal Wrapper)

struct SwiftTermView: NSViewRepresentable {
    // Use regular (non-@Bindable) reference — we don't need SwiftUI to track
    // ViewModel changes here; all output goes through the coordinator directly.
    let viewModel: TerminalViewModel

    func makeNSView(context: Context) -> DirectInputTerminalView {
        let terminal = DirectInputTerminalView()
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminal = terminal

        // Set up direct output callback
        viewModel.onOutput = { [weak coordinator = context.coordinator] data in
            coordinator?.receiveOutput(data)
        }

        // Request focus once after the view is added to the window hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard terminal.window != nil else { return }
            terminal.window?.makeFirstResponder(terminal)
        }

        return terminal
    }

    func updateNSView(_ terminal: DirectInputTerminalView, context: Context) {
        context.coordinator.terminal = terminal
        context.coordinator.viewModel = viewModel
    }

    static func dismantleNSView(_ terminal: DirectInputTerminalView, coordinator: Coordinator) {
        terminal.terminalDelegate = nil
        coordinator.viewModel?.onOutput = nil
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        weak var viewModel: TerminalViewModel?
        weak var terminal: TerminalView?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        func cleanup() {
            viewModel?.onOutput = nil
            viewModel = nil
            terminal = nil
        }

        /// Direct output delivery to SwiftTerm — no timer delay
        func receiveOutput(_ data: Data) {
            let bytes = [UInt8](data)
            guard let terminal = self.terminal, !bytes.isEmpty else { return }
            terminal.feed(byteArray: ArraySlice(bytes))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            Task { @MainActor [weak self] in
                self?.viewModel?.resize(columns: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let dataToSend = Data(data)
            viewModel?.sendInput(dataToSend)
        }

        func scrolled(source: TerminalView, position: Double) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(string, forType: .string)
                }
            }
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

// MARK: - Preview

#Preview {
    TerminalContentView(
        viewModel: TerminalViewModel(
            connectionName: "Test Server",
            session: NativeTerminalSession(),
            connectionData: TerminalWindowData(
                connectionId: UUID(),
                connectionName: "Test",
                host: "localhost",
                port: 2222,
                username: "testuser",
                password: "testpass",
                authMethod: .password,
                privateKeyPath: nil
            )
        )
    )
}

// MARK: - NSView Helper

extension NSView {
    /// Recursively finds the first subview of the given type
    func findSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let self = self as? T { return self }
        for subview in subviews {
            if let found = subview.findSubview(ofType: type) {
                return found
            }
        }
        return nil
    }
}
