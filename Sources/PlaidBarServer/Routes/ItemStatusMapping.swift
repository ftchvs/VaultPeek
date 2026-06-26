import Foundation
import PlaidBarCore

enum ItemStatusMapping {
    static func status(forAPIError error: Error) -> ItemConnectionStatus {
        // A token-vault / Keychain availability failure (device locked, Keychain
        // temporarily unavailable, an ACL prompt the background server can't
        // satisfy) is transient, not a genuine Plaid item fault. Treat those like
        // provider outages: degraded, non-actionable, and auto-retried. A corrupt
        // stored token is different: re-reading the same invalid bytes will not
        // self-heal, so keep it in the hard-error recovery lane.
        if let tokenVaultError = error as? PlaidTokenVaultError {
            switch tokenVaultError {
            case .keychainUnavailable, .keychainSaveFailed, .keychainLoadFailed, .keychainDeleteFailed:
                return .providerOutage
            case .invalidStoredToken:
                return .error
            }
        }
        guard case PlaidError.apiError(_, _, let errorCode, _) = error else {
            return .error
        }
        return status(forPlaidCode: errorCode) ?? .error
    }

    /// Whether `error`/`status` represents a transient token-vault failure that
    /// was downgraded to the non-actionable `.providerOutage` state (rather than
    /// the hard `.error` reconnect lane). Callers use this to emit a diagnostic
    /// log so an item parked in "we'll retry automatically" stays visible in the
    /// field. The terminal `.invalidStoredToken` variant maps to `.error`, so it
    /// is deliberately NOT reported here.
    static func didDowngradeTokenVaultFailure(
        _ error: Error,
        toStatus status: ItemConnectionStatus
    ) -> Bool {
        error is PlaidTokenVaultError && status == .providerOutage
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
