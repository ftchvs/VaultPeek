import Foundation
import PlaidBarCore
#if canImport(Security)
import Security
#endif

enum PlaidTokenVault {
    private static let referencePrefix = "keychain:"

    static func store(accessToken: String, itemId: String) throws -> String {
        #if canImport(Security)
        try saveToKeychain(accessToken: accessToken, itemId: itemId)
        return reference(for: itemId)
        #else
        return accessToken
        #endif
    }

    static func resolve(storedToken: String) throws -> String {
        guard let itemId = itemId(fromReference: storedToken) else {
            return storedToken
        }

        #if canImport(Security)
        return try loadFromKeychain(itemId: itemId)
        #else
        throw PlaidTokenVaultError.keychainUnavailable
        #endif
    }

    static func delete(storedToken: String, fallbackItemId: String) throws {
        let itemId = itemId(fromReference: storedToken) ?? fallbackItemId

        #if canImport(Security)
        try deleteFromKeychain(itemId: itemId)
        #endif
    }

    static func deleteOrphanedTokens(referencedItemIds: Set<String>) throws {
        #if canImport(Security)
        for itemId in try storedKeychainItemIds() where !referencedItemIds.contains(itemId) {
            try deleteFromKeychain(itemId: itemId)
        }
        #endif
    }

    static func reference(for itemId: String) -> String {
        "\(referencePrefix)\(itemId)"
    }

    static func isReference(_ value: String) -> Bool {
        itemId(fromReference: value) != nil
    }

    private static func itemId(fromReference value: String) -> String? {
        guard value.hasPrefix(referencePrefix) else { return nil }
        let itemId = String(value.dropFirst(referencePrefix.count))
        return itemId.isEmpty ? nil : itemId
    }

    #if canImport(Security)
    private static func saveToKeychain(accessToken: String, itemId: String) throws {
        var query = keychainQuery(itemId: itemId)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = Data(accessToken.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PlaidTokenVaultError.keychainSaveFailed(Int32(status))
        }
    }

    private static func loadFromKeychain(itemId: String) throws -> String {
        var query = keychainQuery(itemId: itemId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw PlaidTokenVaultError.keychainLoadFailed(Int32(status))
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw PlaidTokenVaultError.invalidStoredToken
        }
        return token
    }

    private static func deleteFromKeychain(itemId: String) throws {
        let status = SecItemDelete(keychainQuery(itemId: itemId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlaidTokenVaultError.keychainDeleteFailed(Int32(status))
        }
    }

    private static func storedKeychainItemIds() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalDataStore.plaidAccessTokenKeychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return [] }
        guard status == errSecSuccess else {
            throw PlaidTokenVaultError.keychainLoadFailed(Int32(status))
        }

        if let values = result as? [[String: Any]] {
            return values.compactMap { $0[kSecAttrAccount as String] as? String }
        }
        if let value = result as? [String: Any],
           let itemId = value[kSecAttrAccount as String] as? String {
            return [itemId]
        }
        return []
    }

    private static func keychainQuery(itemId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalDataStore.plaidAccessTokenKeychainService,
            kSecAttrAccount as String: itemId
        ]
    }
    #endif
}

enum PlaidTokenVaultError: Error, LocalizedError, Sendable {
    case keychainUnavailable
    case keychainSaveFailed(Int32)
    case keychainLoadFailed(Int32)
    case keychainDeleteFailed(Int32)
    case invalidStoredToken

    var errorDescription: String? {
        switch self {
        case .keychainUnavailable:
            "macOS Keychain is unavailable"
        case .keychainSaveFailed(let status):
            "Failed to save Plaid access token to Keychain (status \(status))"
        case .keychainLoadFailed(let status):
            "Failed to load Plaid access token from Keychain (status \(status))"
        case .keychainDeleteFailed(let status):
            "Failed to delete Plaid access token from Keychain (status \(status))"
        case .invalidStoredToken:
            "Stored Plaid access token is invalid"
        }
    }
}
