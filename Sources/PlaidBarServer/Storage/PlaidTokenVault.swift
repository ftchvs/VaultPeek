import Foundation
import PlaidBarCore
#if canImport(Security)
import Security
#endif

enum PlaidTokenVault {
    private static let referencePrefix = "keychain:"

    /// The Keychain `kSecAttrService` under which Plaid access tokens are
    /// stored. Production always uses the single shared service; the `service`
    /// parameter exists so tests can write under an isolated, easily-purgeable
    /// service and never touch the developer's real token entries.
    static func store(
        accessToken: String,
        itemId: String,
        service: String = LocalDataStore.plaidAccessTokenKeychainService
    ) throws -> String {
        #if canImport(Security)
        try saveToKeychain(accessToken: accessToken, itemId: itemId, service: service)
        return reference(for: itemId)
        #else
        return accessToken
        #endif
    }

    static func resolve(
        storedToken: String,
        service: String = LocalDataStore.plaidAccessTokenKeychainService
    ) throws -> String {
        guard let itemId = itemId(fromReference: storedToken) else {
            return storedToken
        }

        #if canImport(Security)
        return try loadFromKeychain(itemId: itemId, service: service)
        #else
        throw PlaidTokenVaultError.keychainUnavailable
        #endif
    }

    static func delete(
        storedToken: String,
        fallbackItemId: String,
        service: String = LocalDataStore.plaidAccessTokenKeychainService
    ) throws {
        let itemId = itemId(fromReference: storedToken) ?? fallbackItemId

        #if canImport(Security)
        try deleteFromKeychain(itemId: itemId, service: service)
        #endif
    }

    static func deleteOrphanedTokens(
        referencedItemIds: Set<String>,
        service: String = LocalDataStore.plaidAccessTokenKeychainService
    ) throws {
        #if canImport(Security)
        for itemId in try storedKeychainItemIds(service: service) where !referencedItemIds.contains(itemId) {
            try deleteFromKeychain(itemId: itemId, service: service)
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
    /// Concrete `kSecAttrAccessible` CFString for the hardened policy
    /// (`KeychainAccessPolicy`). Tokens are pinned to this device, readable by
    /// the background server after the first post-boot unlock, and never synced
    /// to iCloud Keychain (AND-572).
    private static var accessibleClass: CFString {
        switch KeychainAccessPolicy.accessibility {
        case .afterFirstUnlockThisDeviceOnly:
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:
            kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlocked:
            kSecAttrAccessibleWhenUnlocked
        }
    }

    private static func saveToKeychain(accessToken: String, itemId: String, service: String) throws {
        let query = keychainQuery(itemId: itemId, service: service)
        // Re-assert the hardened accessibility on every write. The query omits
        // `kSecAttrSynchronizable`, so it matches only the existing
        // non-synchronizable item (Keychain's default search semantics), and
        // `SecItemUpdate` rewrites `kSecAttrAccessible` in place — refreshing
        // the device-only protection class for tokens an older build may have
        // written under a weaker class.
        //
        // `kSecAttrSynchronizable = false` below is redundant with the Keychain
        // default (omitting the key already yields a non-synchronizable item;
        // it can never be paired with a `ThisDeviceOnly` accessibility class).
        // It is kept only as an explicit, self-documenting assertion of the
        // on-device-only policy — it does not, and cannot, migrate a token that
        // was somehow already synced to iCloud Keychain, because such an item
        // would not match this query in the first place.
        let attributes: [String: Any] = [
            kSecValueData as String: Data(accessToken.utf8),
            kSecAttrAccessible as String: accessibleClass,
            kSecAttrSynchronizable as String: KeychainAccessPolicy.isSynchronizable
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PlaidTokenVaultError.keychainSaveFailed(Int32(updateStatus))
        }

        let addQuery = query.merging(attributes) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PlaidTokenVaultError.keychainSaveFailed(Int32(status))
        }
    }

    private static func loadFromKeychain(itemId: String, service: String) throws -> String {
        var query = keychainQuery(itemId: itemId, service: service)
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

    private static func deleteFromKeychain(itemId: String, service: String) throws {
        let status = SecItemDelete(keychainQuery(itemId: itemId, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlaidTokenVaultError.keychainDeleteFailed(Int32(status))
        }
    }

    private static func storedKeychainItemIds(service: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    private static func keychainQuery(itemId: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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
