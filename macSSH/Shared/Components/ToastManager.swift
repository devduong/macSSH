//
//  ToastManager.swift
//  macSSH
//
//  Centralized Toast notification manager with auto-dismiss (default 5 seconds).
//

import SwiftUI
import Combine

public enum ToastType: Sendable {
    case warning
    case error
    case info
    case success

    var iconName: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        case .success: return .green
        }
    }
}

public struct ToastMessage: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let message: String
    public let type: ToastType
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        type: ToastType = .warning,
        duration: TimeInterval = 5.0
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.duration = duration
    }

    public static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()

    @Published public private(set) var currentToast: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    public func show(
        title: String,
        message: String,
        type: ToastType = .warning,
        duration: TimeInterval = 5.0
    ) {
        dismissTask?.cancel()

        let toast = ToastMessage(title: title, message: message, type: type, duration: duration)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentToast = toast
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.dismiss()
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeOut(duration: 0.25)) {
            self.currentToast = nil
        }
    }
}

// MARK: - Toast Banner View

public struct ToastBannerView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: toast.type.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toast.type.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)

                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(toast.type.accentColor.opacity(0.35), lineWidth: 1)
        )
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: - ViewModifier & Extension

public struct ToastOverlayModifier: ViewModifier {
    @ObservedObject private var toastManager = ToastManager.shared

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let toast = toastManager.currentToast {
                ToastBannerView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9999)
            }
        }
    }
}

public extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}
