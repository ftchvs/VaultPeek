import Foundation

public enum ReconnectRecoveryMessage {
    private static let maxErrorDetailLength = 80

    public static func invalidUpdateLinkURL(institutionName: String?) -> String {
        "PlaidBar could not prepare a safe reconnect link\(institutionSuffix(institutionName)). Refresh status, then use Settings > Accounts > \(reconnectAction(institutionName))."
    }

    public static func browserOpenFailed(institutionName: String?) -> String {
        "PlaidBar could not open Plaid Link in your browser\(institutionSuffix(institutionName)). Set a default browser, then use Settings > Accounts > \(reconnectAction(institutionName))."
    }

    public static func createFailed(errorMessage: String?, institutionName: String?) -> String {
        let safeDetail = UserFacingError.sanitizedDetail(from: errorMessage, maxLength: maxErrorDetailLength)
        let fallback = "PlaidBar could not create a reconnect link\(institutionSuffix(institutionName))."
        let detail = safeDetail.map { "\(fallback) \($0)" } ?? fallback
        return "\(detail) Refresh status, then use Settings > Accounts > \(reconnectAction(institutionName))."
    }

    private static func institutionSuffix(_ institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else { return "" }
        return " for \(institutionName)"
    }

    private static func reconnectAction(_ institutionName: String?) -> String {
        guard let institutionName = normalizedInstitutionName(institutionName) else { return "Reconnect Item" }
        return "Reconnect \(institutionName)"
    }

    private static func normalizedInstitutionName(_ institutionName: String?) -> String? {
        guard let institutionName else { return nil }
        let trimmed = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
