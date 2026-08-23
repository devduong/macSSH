//
//  DeviceSecurityService.swift
//  macSSH
//
//  Hardware-bound cryptographic service for macOS
//  Encrypts and decrypts sensitive settings (passwords, private keys) using
//  Apple CryptoKit AES-256-GCM combined with device-unique hardware platform identifiers.
//

import Foundation
import CryptoKit
import Security
import IOKit

/// Cryptographic service that binds encryption directly to the physical macOS hardware.
/// Ciphertext encrypted with this service cannot be decrypted on any other computer.
enum DeviceSecurityService {

    private static let keychainService = "com.macSSH.hardwareSecurity"
    private static let masterSeedAccount = "deviceMasterKeyMaterial"
    private static let hkdfInfo = "macSSH.hardware-bound.v1".data(using: .utf8)!

    // In-memory cache so Keychain/Hardware derivation is ONLY performed once per app run
    private static var cachedKey: SymmetricKey?

    // MARK: - Public API

    /// Encrypts plain text using AES-256-GCM with a hardware-derived machine key.
    /// Returns a Base64-encoded sealed box (nonce + ciphertext + tag).
    static func encrypt(_ plainText: String) throws -> String {
        guard let data = plainText.data(using: .utf8) else {
            throw AppError.fileReadFailed
        }
        let key = try getHardwareBoundKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw AppError.fileWriteFailed
        }
        return combined.base64EncodedString()
    }

    /// Decrypts a Base64-encoded AES-256-GCM sealed box using this device's hardware-bound key.
    /// Throws an error if attempted on a different computer or if data was tampered with.
    static func decrypt(_ base64Ciphertext: String) throws -> String {
        guard let combinedData = Data(base64Encoded: base64Ciphertext) else {
            throw AppError.unknown("Dữ liệu mã hoá không hợp lệ (Invalid Base64)")
        }
        let key = try getHardwareBoundKey()
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let plainText = String(data: decryptedData, encoding: .utf8) else {
            throw AppError.unknown("Không thể giải mã dữ liệu chuỗi (Corrupted UTF-8)")
        }
        return plainText
    }

    // MARK: - Key Derivation & Hardware Binding

    /// Derives a 256-bit AES-GCM symmetric key uniquely bound to this physical Mac.
    private static func getHardwareBoundKey() throws -> SymmetricKey {
        if let key = cachedKey {
            return key
        }

        guard let hardwareUUID = getHardwareUUID(), !hardwareUUID.isEmpty else {
            throw AppError.unknown("Không thể truy xuất Hardware Platform UUID của máy Mac")
        }

        let deviceSeed = try getOrCreateDeviceKeychainSeed()
        let salt = Data(hardwareUUID.utf8)

        // Derive 256-bit symmetric key using HKDF-SHA256
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: deviceSeed),
            salt: salt,
            info: hkdfInfo,
            outputByteCount: 32 // 256-bit key for AES-256-GCM
        )

        cachedKey = derivedKey
        return derivedKey
    }

    /// Retrieves the unique hardware platform UUID from IOKit IOPlatformExpertDevice
    private static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let uuidAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        return uuidAsCFString
    }

    /// Retrieves or generates a 256-bit random master seed from macOS Keychain
    /// marked with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
    private static func getOrCreateDeviceKeychainSeed() throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterSeedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let existingData = result as? Data, existingData.count == 32 {
            return existingData
        }

        // Generate a new 256-bit (32 bytes) cryptographically secure random seed
        var newSeed = Data(count: 32)
        let randomStatus = newSeed.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw AppError.unknown("Không thể tạo khóa ngẫu nhiên từ hệ điều hành (SecRandom error)")
        }

        // Delete any outdated item
        var deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterSeedAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Save with ThisDeviceOnly restriction (cannot sync via iCloud or transfer to another Mac)
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: masterSeedAccount,
            kSecValueData as String: newSeed,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logError("Failed to store hardware master seed in Keychain: \(addStatus)", category: .keychain)
            throw AppError.keychainSaveFailed
        }

        logInfo("Created new hardware-bound master seed in Keychain (ThisDeviceOnly)", category: .keychain)
        return newSeed
    }
}
