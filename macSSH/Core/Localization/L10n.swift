//
//  L10n.swift
//  macSSH
//
//  Centralized L10N (Localization) Manager
//

import Foundation
import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"
    case french = "fr"
    case russian = "ru"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case system = "auto"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .french: return "Français"
        case .russian: return "Русский"
        case .chineseSimplified: return "简体中文 (Chinese Simplified)"
        case .chineseTraditional: return "繁體中文 (Chinese Traditional)"
        case .system: return "System Default / Theo hệ thống"
        }
    }
}

public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()

    private static let languageDefaultsKey = "appLanguage"
    private static let lock = NSLock()
    private var cachedLanguage: String

    @Published public var currentLanguage: String {
        didSet {
            Self.lock.withLock {
                cachedLanguage = currentLanguage
            }
            UserDefaults.standard.set(currentLanguage, forKey: Self.languageDefaultsKey)
        }
    }

    private let dictionaries: [String: [String: String]] = [
        "en": L10n_EN.strings,
        "vi": L10n_VI.strings,
        "fr": L10n_FR.strings,
        "ru": L10n_RU.strings,
        "zh-Hans": L10n_ZH_Hans.strings,
        "zh-Hant": L10n_ZH_Hant.strings
    ]

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? AppLanguage.system.rawValue
        self.cachedLanguage = saved
        self.currentLanguage = saved
    }

    public var activeLanguageCode: String {
        let selected = Self.lock.withLock { cachedLanguage }
        if selected != "auto" && dictionaries[selected] != nil {
            return selected
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.starts(with: "vi") { return "vi" }
        if preferred.starts(with: "fr") { return "fr" }
        if preferred.starts(with: "ru") { return "ru" }
        if preferred.starts(with: "zh-Hant") || preferred.starts(with: "zh-TW") || preferred.starts(with: "zh-HK") { return "zh-Hant" }
        if preferred.starts(with: "zh") { return "zh-Hans" }
        return "en"
    }

    public var locale: Locale {
        Locale(identifier: activeLanguageCode)
    }

    public var isVietnamese: Bool {
        activeLanguageCode == "vi"
    }

    /// Primary localized string lookup by key with fallback to English (EN)
    public func tr(_ key: String, _ args: CVarArg...) -> String {
        let lang = activeLanguageCode
        let format = dictionaries[lang]?[key]
            ?? dictionaries["en"]?[key]
            ?? key

        if args.isEmpty {
            return format
        } else {
            return String(format: format, arguments: args)
        }
    }

    public func tr(_ key: String, default fallback: String, _ args: CVarArg...) -> String {
        let lang = activeLanguageCode
        let format = dictionaries[lang]?[key]
            ?? dictionaries["en"]?[key]
            ?? fallback

        if args.isEmpty {
            return format
        } else {
            return String(format: format, arguments: args)
        }
    }

    /// Convenience for direct bilingual string pairs
    public func localized(_ en: String, vi: String) -> String {
        isVietnamese ? vi : en
    }
}

public enum L10n {
    public static func tr(_ key: String, _ args: CVarArg...) -> String {
        if args.isEmpty {
            return LocalizationManager.shared.tr(key)
        } else {
            let format = LocalizationManager.shared.tr(key)
            return String(format: format, arguments: args)
        }
    }

    public static func tr(_ key: String, default fallback: String, _ args: CVarArg...) -> String {
        if args.isEmpty {
            return LocalizationManager.shared.tr(key, default: fallback)
        } else {
            let format = LocalizationManager.shared.tr(key, default: fallback)
            return String(format: format, arguments: args)
        }
    }
}

public func tr(_ key: String, _ args: CVarArg...) -> String {
    if args.isEmpty {
        return LocalizationManager.shared.tr(key)
    } else {
        let format = LocalizationManager.shared.tr(key)
        return String(format: format, arguments: args)
    }
}

public func tr(_ key: String, default fallback: String, _ args: CVarArg...) -> String {
    if args.isEmpty {
        return LocalizationManager.shared.tr(key, default: fallback)
    } else {
        let format = LocalizationManager.shared.tr(key, default: fallback)
        return String(format: format, arguments: args)
    }
}

public func loc(_ en: String, _ vi: String) -> String {
    LocalizationManager.shared.localized(en, vi: vi)
}
