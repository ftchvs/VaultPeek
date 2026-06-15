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
