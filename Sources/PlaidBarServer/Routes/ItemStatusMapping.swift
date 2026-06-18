import Foundation
import PlaidBarCore

enum ItemStatusMapping {
    static func status(forAPIError error: Error) -> ItemConnectionStatus {
        guard case PlaidError.apiError(_, _, let errorCode, _) = error else {
            return .error
        }
        return status(forPlaidCode: errorCode) ?? .error
    }

    static func status(forWebhookCode code: String, currentStatus: ItemConnectionStatus) -> ItemConnectionStatus? {
        let normalized = normalize(code)
        switch normalized {
        case "LOGIN_REPAIRED":
            return currentStatus.applyingLoginRepaired()
        case "LOGIN_REPAIRED_WITH_NEW_ACCOUNTS":
            // Login was repaired AND Plaid has newly available accounts to grant;
            // surface the actionable new-accounts state rather than silently
            // clearing the prompt. Like the sibling `LOGIN_REPAIRED` branch (and
            // `applyingLoginRepaired()`), a repair signal must never clobber a hard
            // `.error` this receiver cannot resolve — the item still needs a full
            // reconnect, so preserve `.error` instead of downgrading it.
            return currentStatus == .error ? .error : .newAccountsAvailable
        case "ERROR":
            // A bare ITEM `ERROR` webhook whose granular `error.error_code` this
            // receiver does not yet parse: keep the item degraded (login needed)
            // rather than dropping the signal, preserving prior behavior.
            return .loginRequired
        default:
            return status(forPlaidCode: normalized)
        }
    }

    private static func status(forPlaidCode code: String?) -> ItemConnectionStatus? {
        switch normalize(code) {
        case "ITEM_LOGIN_REQUIRED":
            return .loginRequired
        case "PENDING_EXPIRATION", "ITEM_PENDING_EXPIRATION":
            return .pendingExpiration
        case "PENDING_DISCONNECT", "ITEM_PENDING_DISCONNECT":
            return .pendingDisconnect
        case "USER_PERMISSION_REVOKED", "ITEM_PERMISSION_REVOKED", "ITEM_NOT_ACCESSIBLE":
            return .permissionRevoked
        case "NEW_ACCOUNTS_AVAILABLE":
            return .newAccountsAvailable
        // Transient Plaid-side outages: degraded but NOT a user-actionable
        // reconnect (mirrors LinkRoutes.retryableProviderCodes). VaultPeek shows
        // a "we'll retry automatically" advisory instead of an Update flow.
        case "INSTITUTION_DOWN", "INSTITUTION_NOT_RESPONDING", "PLANNED_MAINTENANCE", "INTERNAL_SERVER_ERROR":
            return .providerOutage
        default:
            return nil
        }
    }

    private static func normalize(_ code: String?) -> String {
        code?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            ?? ""
    }
}
