//
//  DonateSheetView.swift
//  macSSH
//
//  Donate & Support macSSH sheet with Ko-fi, GitHub, and Crypto (BEP20) QR Code
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct DonateSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var copied = false

    private let cryptoAddress = "0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E"
    private let cryptoNetwork = "BEP20 (BSC – Binance Smart Chain)"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    // Header Banner
                    VStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                            .padding(14)
                            .background(Circle().fill(Color.orange.opacity(0.15)))

                        Text(L10n.tr("buy_me_coffee_title", default: "Support macSSH"))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(L10n.tr("buy_me_coffee_desc", default: "macSSH is free and open-source software.\nIf you find it helpful, please consider supporting development!"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)

                    // Support Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                            Text(L10n.tr("support_dev_title", default: "Support macSSH Development"))
                                .font(.headline)
                        }

                        Text(L10n.tr("support_dev_desc", default: "macSSH là ứng dụng mã nguồn mở hoàn toàn miễn phí mang trải nghiệm quản lý SSH, SFTP, Terminal & SOCKS5 Proxy mượt mà lên macOS."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        // Action Buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                if let url = URL(string: "https://ko-fi.com/X4P324ZPZ3") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "cup.and.saucer.fill")
                                    Text(L10n.tr("support_kofi", default: "Support on Ko-fi"))
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(red: 1.0, green: 0.37, blue: 0.36))
                                .foregroundStyle(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                if let url = URL(string: "https://github.com/devduong/macSSH") {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                    Text(L10n.tr("star_github", default: "Star on GitHub"))
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

                    // Crypto Donation Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.title3)
                            Text(L10n.tr("donate_crypto", default: "Donate via Crypto"))
                                .font(.headline)
                            Spacer()
                            Text("BEP20")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                .foregroundStyle(.orange)
                        }

                        HStack(alignment: .top, spacing: 16) {
                            if let qrImage = generateQRCode(from: cryptoAddress) {
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .padding(6)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.tr("crypto_network", default: "Network"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(cryptoNetwork)
                                        .font(.system(size: 11, weight: .medium))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.tr("crypto_wallet", default: "Wallet Address"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(cryptoAddress)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .textSelection(.enabled)
                                        .foregroundStyle(.primary)
                                }

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cryptoAddress, forType: .string)
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copied = false
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                        Text(copied ? L10n.tr("crypto_copied", default: "Copied!") : L10n.tr("crypto_copy", default: "Copy Address"))
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(copied ? Color.green : Color.accentColor)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)

                                Text(L10n.tr("crypto_hint", default: "Scan the QR code or copy the address to send any BEP20 token (USDT, BNB, BUSD, etc.)"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n.tr("close", default: "Close")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 520, height: 600)
    }

    // MARK: - QR Code Generator

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}

#Preview {
    DonateSheetView()
}
