//
//  AboutSheetView.swift
//  macSSH
//
//  About macSSH information sheet
//

import SwiftUI

struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(radius: 4)

            // App Name & Version
            VStack(spacing: 4) {
                Text(AppVersion.appName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version \(AppVersion.version) (\(AppVersion.buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.tr("app_tagline"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Divider()

            // Links & Details
            VStack(spacing: 8) {
                HStack {
                    Text(L10n.tr("developer"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Hoang Duong")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(L10n.tr("repository"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("GitHub") {
                        if let url = URL(string: "https://github.com/devduong/macSSH") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }

                HStack {
                    Text(L10n.tr("license"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(L10n.tr("license_type"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button(L10n.tr("ok")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .frame(width: 380, height: 380)
    }
}
