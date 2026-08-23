//
//  AppLockView.swift
//  macSSH
//
//  Full-screen lock overlay requiring Touch ID to unlock
//

import SwiftUI

struct AppLockView: View {
    @State private var appLockManager = AppLockManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("macSSH is Locked")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Authenticate to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = appLockManager.authenticationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                appLockManager.unlock()
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
                    .frame(minWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(appLockManager.isAuthenticating)

            if appLockManager.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task {
            // Auto-prompt Touch ID on appear
            if !appLockManager.isAuthenticating {
                appLockManager.unlock()
            }
        }
    }
}

#Preview {
    AppLockView()
}
