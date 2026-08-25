//
//  AppVersion.swift
//  macSSH
//
//  Centralized version metadata for the application.
//  Used by create-dmg.sh to generate DMG filenames.
//

import Foundation

enum AppVersion {
    /// App display name derived dynamically from Bundle Info.plist
    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "macSSH"
    }

    /// App version derived dynamically from Bundle Info.plist (stamped from .env during build)
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Build number derived dynamically from Bundle Info.plist (stamped from .env during build)
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Architecture type
    static var architecture: String {
        #if arch(arm64) && arch(x86_64)
        return "Universal"
        #elseif arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Universal"
        #endif
    }
}
