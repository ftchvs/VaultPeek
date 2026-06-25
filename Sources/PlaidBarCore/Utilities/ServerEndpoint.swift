import Foundation

public enum ServerEndpoint {
    public static func url(baseURL: String, path: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.percentEncodedPath = path
        return components.url
    }

    public static func transactionSyncURL(baseURL: String, itemId: String? = nil) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = "/api/transactions/sync"
        if let itemId {
            components.percentEncodedQuery = "item_id=\(percentEncodedQueryValue(itemId))"
        }
        return components.url
    }

    public static func statusURL(baseURL: String, includeItems: Bool = false) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = "/api/status"
        if includeItems {
            components.percentEncodedQuery = "include=items"
        }
        return components.url
    }

    public static func transactionCursorCommitURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/transactions/sync/cursors")
    }

    public static func updateLinkTokenURL(baseURL: String, itemId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/link/update/\(percentEncodedPathComponent(itemId))")
    }

    public static func removeItemURL(baseURL: String, itemId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/accounts/\(percentEncodedPathComponent(itemId))")
    }

    public static func investmentHoldingsURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/investments/holdings")
    }

    public static func investmentTransactionsURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/investments/transactions")
    }

    public static func categoryBudgetsURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/budgets")
    }

    public static func saveCategoryBudgetURL(baseURL: String, categoryId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/budgets/\(percentEncodedPathComponent(categoryId))")
    }

    public static func deleteCategoryBudgetURL(baseURL: String, categoryId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/budgets/\(percentEncodedPathComponent(categoryId))")
    }

    /// `/api/review` — opt-in server-synced review state (AND-552). `GET` pulls the
    /// stored snapshot; `PUT` uploads a device snapshot and gets the merged union
    /// back; `DELETE` clears the synced state (opt-out). Only reached when the user
    /// has enabled ``ServerSyncedReviewFeatureFlag``.
    public static func reviewStateURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/review")
    }

    private static func percentEncodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func percentEncodedQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
