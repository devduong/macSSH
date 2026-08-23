//
//  BreadcrumbView.swift
//  macSSH
//
//  Finder-style path bar for the file browser
//

import SwiftUI

struct BreadcrumbView: View {
    let currentPath: String
    let components: [PathComponent]
    let onNavigate: (String) -> Void

    @State private var hoveredPath: String?
    @State private var isEditingPath = false
    @State private var editablePathText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isEditingPath {
                // Manual path input mode
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Enter path (e.g. /var/www or ~/.config)", text: $editablePathText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($isFieldFocused)
                        .onSubmit {
                            submitManualPath()
                        }
                        .onExitCommand {
                            cancelEditing()
                        }

                    Button {
                        submitManualPath()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .help("Go to Path (Return)")

                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel (Esc)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.textBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                )
                .onAppear {
                    editablePathText = currentPath
                    isFieldFocused = true
                }
            } else {
                // Breadcrumbs mode
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            // Root
                            pathButton(icon: "externaldrive.fill", path: "/", isLast: components.isEmpty)

                            ForEach(components) { component in
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 1)

                                pathButton(text: component.name, path: component.path, isLast: component.path == components.last?.path)
                                    .id(component.path)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: components) { _, newComponents in
                        if let lastPath = newComponents.last?.path {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(lastPath, anchor: .trailing)
                            }
                        }
                    }
                }

                Spacer()

                // Edit path button
                Button {
                    startEditing()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Edit Path (⌘L)")
                .keyboardShortcut("l", modifiers: .command)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isEditingPath {
                startEditing()
            }
        }
    }

    private func startEditing() {
        editablePathText = currentPath
        isEditingPath = true
        isFieldFocused = true
    }

    private func cancelEditing() {
        isEditingPath = false
    }

    private func submitManualPath() {
        let trimmed = editablePathText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onNavigate(trimmed)
        }
        isEditingPath = false
    }

    @ViewBuilder
    private func pathButton(icon: String? = nil, text: String? = nil, path: String, isLast: Bool) -> some View {
        let isHovered = hoveredPath == path

        Button {
            onNavigate(path)
        } label: {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                } else if let text = text {
                    Text(text)
                        .font(.system(size: 12, weight: isLast ? .medium : .regular))
                }
            }
            .foregroundStyle(isLast ? .primary : .tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPath = hovering ? path : nil
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        BreadcrumbView(
            currentPath: "/",
            components: [],
            onNavigate: { _ in }
        )

        Divider()

        BreadcrumbView(
            currentPath: "/home/user/documents",
            components: [
                PathComponent(name: "home", path: "/home"),
                PathComponent(name: "user", path: "/home/user"),
                PathComponent(name: "documents", path: "/home/user/documents")
            ],
            onNavigate: { _ in }
        )

        Divider()

        BreadcrumbView(
            currentPath: "/var/www/html/myproject/src",
            components: [
                PathComponent(name: "var", path: "/var"),
                PathComponent(name: "www", path: "/var/www"),
                PathComponent(name: "html", path: "/var/www/html"),
                PathComponent(name: "myproject", path: "/var/www/html/myproject"),
                PathComponent(name: "src", path: "/var/www/html/myproject/src")
            ],
            onNavigate: { _ in }
        )
    }
    .frame(width: 400)
}
