//
//  KeychainService.swift
//  macSSH
//
//  Keychain implementation for secure password storage
//

import Foundation
import Security

final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    static let shared = KeychainService()

    private let service = AppConstants.keychainService
    private var memoryCache: [UUID: String] = [:]
    private let lock = NSLock()

    private init() {}

    func savePassword(_ password: String, for connectionId: UUID) throws {
        lock.lock()
        memoryCache[connectionId] = password
        lock.unlock()

        guard let passwordData = password.data(using: .utf8) else {
            throw AppError.keychainSaveFailed
        }

        // Delete any existing password first
        try? deletePassword(for: connectionId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            logError("Keychain save failed with status: \(status)", category: .keychain)
            throw AppError.keychainSaveFailed
        }

        logDebug("Password saved for connection: \(connectionId)", category: .keychain)
    }

    func getPassword(for connectionId: UUID) -> String? {
        lock.lock()
        if let cached = memoryCache[connectionId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        lock.lock()
        memoryCache[connectionId] = password
        lock.unlock()

        return password
    }

    func deletePassword(for connectionId: UUID) throws {
        lock.lock()
        memoryCache.removeValue(forKey: connectionId)
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionId.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            logError("Keychain delete failed with status: \(status)", category: .keychain)
            throw AppError.keychainDeleteFailed
        }

        logDebug("Password deleted for connection: \(connectionId)", category: .keychain)
    }

    func updatePassword(_ password: String, for connectionId: UUID) throws {
        lock.lock()
        memoryCache[connectionId] = password
        lock.unlock()

        guard let passwordData = password.data(using: .utf8) else {
            throw AppError.keychainSaveFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionId.uuidString
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, create it
            try savePassword(password, for: connectionId)
            return
        }

        if status != errSecSuccess {
            logError("Keychain update failed with status: \(status)", category: .keychain)
            throw AppError.keychainSaveFailed
        }

        logDebug("Password updated for connection: \(connectionId)", category: .keychain)
    }

    func hasPassword(for connectionId: UUID) -> Bool {
        getPassword(for: connectionId) != nil
    }
}
