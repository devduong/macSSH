//
//  PasswordPromptSheet.swift
//  macSSH
//
//  Password prompt for connecting to a server
//

import SwiftUI

struct PasswordPromptSheet: View {
    let connectionName: String
    var errorMessage: String? = nil
    let onConnect: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @FocusState private var isFocused: Bool

    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: UIConstants.spacing) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundStyle(errorMessage != nil ? .red : .secondary)

            Text(loc("Enter Password", "Nhập mật khẩu"))
                .font(.headline)

            Text("\(loc("Enter the password for", "Nhập mật khẩu cho")) \"\(connectionName)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            SecureField(loc("Password", "Mật khẩu"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !password.isEmpty {
                        onConnect(password)
                    }
                }

            HStack {
                Button(loc("Cancel", "Hủy")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(loc("Connect", "Kết nối")) {
                    onConnect(password)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding(UIConstants.spacing * 2)
        .frame(width: 320)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Preview
#Preview {
    PasswordPromptSheet(
        connectionName: "Production Server",
        onConnect: { _ in },
        onCancel: {}
    )
}
