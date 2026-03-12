import Foundation
import Security

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .readFailed(let s): return "Keychain read failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        case .unexpectedData: return "Keychain returned unexpected data"
        case .itemNotFound: return "Keychain item not found"
        }
    }
}

final class KeychainService: Sendable {
    static let shared = KeychainService()
    static let githubOAuthService = "com.devjourney.github.oauth"
    static let providerAPIService = "com.devjourney.provider.apikey"

    // MARK: - Core Operations

    func save(service: String, account: String, data: Data) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    func saveString(service: String, account: String = "default", value: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedData }
        try save(service: service, account: account, data: data)
    }

    func read(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.readFailed(status)
        }
        guard let data = result as? Data else { throw KeychainError.unexpectedData }
        return data
    }

    func readString(service: String, account: String = "default") -> String? {
        guard let data = try? read(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(service: String, account: String = "default") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func exists(service: String, account: String = "default") -> Bool {
        readString(service: service, account: account) != nil
    }

    // MARK: - GitHub Convenience

    func saveGitHubToken(_ token: String, username: String = "default") throws {
        try saveString(service: Self.githubOAuthService, account: username, value: token)
    }

    func readGitHubToken(username: String = "default") -> String? {
        readString(service: Self.githubOAuthService, account: username)
    }

    func deleteGitHubToken(username: String = "default") throws {
        try delete(service: Self.githubOAuthService, account: username)
    }

    // MARK: - Provider Convenience

    func saveProviderAPIKey(_ token: String, reference: String) throws {
        try saveString(service: Self.providerAPIService, account: reference, value: token)
    }

    func readProviderAPIKey(reference: String) -> String? {
        readString(service: Self.providerAPIService, account: reference)
    }

    func deleteProviderAPIKey(reference: String) throws {
        try delete(service: Self.providerAPIService, account: reference)
    }

}
