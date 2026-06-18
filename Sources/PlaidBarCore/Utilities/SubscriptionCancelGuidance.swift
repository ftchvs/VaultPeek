import Foundation

/// Where to send a user who wants to cancel a recurring subscription (AND-497).
///
/// Pure, Sendable, table-driven resolver: a small hand-curated map from known
/// merchant names to the merchant's own cancellation/manage-subscription page.
/// Unknown merchants fall back to a generic web search for "how to cancel
/// <merchant>". No network, no Date — fully testable in PlaidBarCore.
public enum SubscriptionCancelGuidance {
    /// Resolved guidance for one merchant.
    public struct Result: Sendable, Hashable {
        /// Destination to open (the merchant's own page, or a generic search).
        public let url: URL
        /// Short link text for the UI, e.g. "How to cancel".
        public let linkText: String
        /// True when `url` points at the merchant's own cancellation page rather
        /// than a generic search fallback. Lets the UI phrase it more precisely.
        public let isSpecific: Bool

        public init(url: URL, linkText: String, isSpecific: Bool) {
            self.url = url
            self.linkText = linkText
            self.isSpecific = isSpecific
        }
    }

    /// Curated merchant → cancellation-page map. Keys are normalized (lowercased,
    /// trimmed) so " Netflix " and "netflix" both match. Values are the
    /// merchant's public account/cancellation page.
    private static let knownCancelPages: [String: String] = [
        "netflix": "https://www.netflix.com/cancelplan",
        "spotify": "https://support.spotify.com/article/cancel-premium/",
        "adobe": "https://account.adobe.com/plans",
        "hulu": "https://help.hulu.com/article/hulu-how-do-i-cancel-my-subscription",
        "disney+": "https://help.disneyplus.com/article/disneyplus-cancel-subscription",
        "disney plus": "https://help.disneyplus.com/article/disneyplus-cancel-subscription",
        "apple": "https://support.apple.com/118428",
        "amazon prime": "https://www.amazon.com/gp/primecentral",
        "youtube premium": "https://www.youtube.com/paid_memberships",
        "planet fitness": "https://www.planetfitness.com/account",
        "audible": "https://www.audible.com/account/membership",
        "dropbox": "https://www.dropbox.com/account/plan",
        "icloud": "https://support.apple.com/118428",
    ]

    /// Resolve cancellation guidance for a merchant name.
    ///
    /// - Parameter merchantName: the displayed merchant name (any casing/whitespace).
    /// - Returns: a specific merchant page when known, otherwise a generic
    ///   "how to cancel <merchant>" web search. Always non-nil with a valid URL.
    public static func guidance(for merchantName: String) -> Result {
        let normalized = normalize(merchantName)

        if !normalized.isEmpty,
           let page = knownCancelPages[normalized],
           let url = URL(string: page) {
            return Result(url: url, linkText: "How to cancel", isSpecific: true)
        }

        return Result(url: searchURL(for: merchantName), linkText: "How to cancel", isSpecific: false)
    }

    /// Lowercased, whitespace-trimmed key used for map lookups.
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Generic fallback: a web search for how to cancel the named subscription.
    static func searchURL(for merchantName: String) -> URL {
        let trimmed = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.isEmpty ? "how to cancel a subscription" : "how to cancel \(trimmed) subscription"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? "how%20to%20cancel%20a%20subscription"
        // DuckDuckGo HTML search — no tracking redirect, stable query format.
        return URL(string: "https://duckduckgo.com/?q=\(encoded)")
            ?? URL(string: "https://duckduckgo.com")!
    }
}
