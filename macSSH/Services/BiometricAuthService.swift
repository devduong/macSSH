//
//  BiometricAuthService.swift
//  macSSH
//
//  Touch ID / biometric authentication service
//

import Foundation
import LocalAuthentication

protocol BiometricAuthServiceProtocol: Sendable {
    func isBiometricAvailable() -> Bool
    func authenticate(reason: String) async -> Result<Void, BiometricError>
}

enum BiometricError: LocalizedError, Sendable {
    case notAvailable
    case authenticationFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Touch ID is not available on this Mac."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .userCancelled:
            return "Authentication was cancelled."
        }
    }
}

final class BiometricAuthService: BiometricAuthServiceProtocol, @unchecked Sendable {
    static let shared = BiometricAuthService()

    private init() {}

    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(.notAvailable)
        }

        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return .success(())
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .failure(.userCancelled)
            default:
                return .failure(.authenticationFailed(authError.localizedDescription))
            }
        } catch {
            return .failure(.authenticationFailed(error.localizedDescription))
        }
    }
}
