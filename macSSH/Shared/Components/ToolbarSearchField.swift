//
//  ToolbarSearchField.swift
//  macSSH
//
//  Native NSSearchField wrapper for macOS toolbar placement
//

import SwiftUI
import AppKit

struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = prompt
        searchField.stringValue = text
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .regular
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = context.coordinator
        searchField.setContentHuggingPriority(.required, for: .vertical)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        context.coordinator.searchField = searchField
        context.coordinator.observeFocusNotification()
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.placeholderString != prompt {
            searchField.placeholderString = prompt
        }
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    static func dismantleNSView(_ searchField: NSSearchField, coordinator: Coordinator) {
        searchField.delegate = nil
        coordinator.searchField = nil
        coordinator.removeObserver()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        weak var searchField: NSSearchField?
        nonisolated(unsafe) private var focusObserver: NSObjectProtocol?

        init(_ parent: ToolbarSearchField) {
            self.parent = parent
        }

        func observeFocusNotification() {
            removeObserver()
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusConnectionSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let field = self?.searchField else { return }
                    field.window?.makeFirstResponder(field)
                }
            }
        }

        func removeObserver() {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
                focusObserver = nil
            }
        }

        deinit {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }
    }
}
