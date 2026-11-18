//
//  AppearanceManager.swift
//  macSSH
//
//  Manages application-wide Light, Dark, and System appearance preferences
//

import Foundation
import SwiftUI
import AppKit
import Combine

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .system: return L10n.tr("appearance_system")
        case .light: return L10n.tr("appearance_light")
        case .dark: return L10n.tr("appearance_dark")
        }
    }
}

@MainActor
public final class AppearanceManager: ObservableObject {
    public static let shared = AppearanceManager()

    private static let appearanceKey = "appAppearance"

    @Published public var currentAppearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(currentAppearance.rawValue, forKey: Self.appearanceKey)
            applyAppearance()
        }
    }

    private init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? AppAppearance.system.rawValue
        self.currentAppearance = AppAppearance(rawValue: savedRaw) ?? .system
    }

    public func setAppearance(_ appearance: AppAppearance) {
        guard currentAppearance != appearance else { return }
        currentAppearance = appearance
    }

    public var isEffectivelyDark: Bool {
        switch currentAppearance {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            let effective = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
            return effective.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    public func toggleLightDark(currentlyDark: Bool? = nil) {
        let isDark = currentlyDark ?? isEffectivelyDark
        currentAppearance = isDark ? .light : .dark
    }

    public func applyAppearance() {
        guard let app = NSApp else { return }
        let targetAppearance = currentAppearance.nsAppearance
        if app.appearance?.name != targetAppearance?.name {
            app.appearance = targetAppearance
        }
        for window in app.windows where window.appearance != nil {
            window.appearance = nil
        }
    }
}
