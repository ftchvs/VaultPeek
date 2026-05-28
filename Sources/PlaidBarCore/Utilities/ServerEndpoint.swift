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

    public static func transactionCursorCommitURL(baseURL: String) -> URL? {
        url(baseURL: baseURL, path: "/api/transactions/sync/cursors")
    }

    public static func updateLinkTokenURL(baseURL: String, itemId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/link/update/\(percentEncodedPathComponent(itemId))")
    }

    public static func removeItemURL(baseURL: String, itemId: String) -> URL? {
        url(baseURL: baseURL, path: "/api/accounts/\(percentEncodedPathComponent(itemId))")
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
