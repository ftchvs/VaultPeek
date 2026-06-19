import CoreSpotlight
import Foundation
import PlaidBarCore
import UniformTypeIdentifiers

// MARK: - Spotlight account index (AND-513, Epic E — E3)
//
// Display-only Spotlight indexing of linked account *names* and *last-4* so users
// can type "Chase Checking" into Spotlight and jump straight into VaultPeek. This
// is intentionally minimal and privacy-first:
//   - NEVER indexes balances, transactions, or any figure.
//   - NEVER indexes the Plaid `account_id` / `item_id` (the searchable item's
//     unique identifier is a non-reversible salted hash of the display fields, so
//     the index cannot be used to recover a Plaid identifier).
//   - When Privacy Mask / App Lock is active, the index is cleared so account
//     names do not linger in system search while the user has masked the app.
//
// The opener uses the existing `vaultpeek://dashboard` deep link — selecting a
// result just brings VaultPeek forward; no per-account balance is revealed until
// the user is in the (possibly unlocked) app.

/// A display-safe projection of one account for Spotlight. Names and last-4 only.
struct AccountSpotlightEntry: Sendable, Equatable {
    let displayName: String
    let mask: String?
    let institutionName: String?

    init(displayName: String, mask: String?, institutionName: String?) {
        self.displayName = displayName
        self.mask = mask
        self.institutionName = institutionName
    }

    /// Builds an entry from an `AccountDTO`, dropping every sensitive field. Note:
    /// `account.id` (Plaid `account_id`) is deliberately NOT carried through.
    init(account: AccountDTO) {
        self.init(
            displayName: account.name,
            mask: account.mask,
            institutionName: account.institutionName
        )
    }

    /// Subtitle shown under the name in Spotlight: "Institution •••• 1234".
    var spotlightSubtitle: String {
        var parts: [String] = []
        if let institutionName, !institutionName.isEmpty {
            parts.append(institutionName)
        }
        if let mask, !mask.isEmpty {
            parts.append("•••• \(mask)")
        }
        return parts.joined(separator: " ")
    }

    /// Stable, non-reversible identifier for the searchable item. Salting with the
    /// app's bundle/domain prevents the digest from being used as a lookup oracle
    /// for the (unindexed) Plaid identifiers.
    var searchableIdentifier: String {
        let material = "\(AccountSpotlightIndexer.domainIdentifier)|\(displayName)|\(mask ?? "")|\(institutionName ?? "")"
        // Spotlight identifiers use the minimal-width hex form (historical format).
        return "vaultpeek.account.\(StableHash.hex(material))"
    }
}

/// Indexes / clears the display-only account entries in Spotlight.
///
/// `@MainActor` because it is driven from app state transitions; the actual
/// `CSSearchableIndex` calls are async and thread-safe.
@MainActor
enum AccountSpotlightIndexer {
    /// Groups VaultPeek's searchable items so the whole set can be replaced or
    /// cleared atomically. `nonisolated` so the display-safe `AccountSpotlightEntry`
    /// (a plain value type) can salt its identifier with it off the main actor.
    nonisolated static let domainIdentifier = "com.ftchvs.PlaidBar.accounts"

    /// Deep link selecting a result opens — the shared dashboard URL.
    nonisolated static let deepLinkURL = GlanceSnapshot.deepLinkURL

    /// Replaces the indexed account set with `entries`. When `entries` is empty
    /// (no accounts) the domain is cleared. Safe to call repeatedly — it replaces
    /// the whole domain, so removed accounts drop out of search.
    static func index(
        _ entries: [AccountSpotlightEntry],
        index: CSSearchableIndex = .default()
    ) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        guard !entries.isEmpty else {
            clear(index: index)
            return
        }
        let items = entries.map(makeSearchableItem)
        // Replace the whole domain atomically via the async API so the delete and
        // re-index stay ordered without nesting non-Sendable captures across a
        // `@Sendable` completion-handler boundary (Swift 6 strict concurrency).
        Task { @MainActor in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
            try? await index.indexSearchableItems(items)
        }
    }

    /// Removes every VaultPeek account from Spotlight. Called when Privacy Mask /
    /// App Lock engages or all accounts are unlinked so names never linger in
    /// system search.
    static func clear(index: CSSearchableIndex = .default()) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        Task { @MainActor in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
        }
    }

    /// Convenience entry point from app state: index display-safe entries derived
    /// from the live accounts, or clear the index when figures are masked.
    ///
    /// Wired from `AppState.writeFinanceSnapshot()` — the shared seam for account
    /// load/refresh, demo data, and the Privacy Mask / App Lock transitions — so
    /// the index stays in lockstep with the App Group snapshot (AND-513). The
    /// empty-accounts and reset clears live alongside it in `AppState`
    /// (`writeGlanceSnapshot` / `clearGlanceSnapshot`).
    static func refresh(accounts: [AccountDTO], isMasked: Bool) {
        guard !isMasked else {
            clear()
            return
        }
        index(accounts.map(AccountSpotlightEntry.init(account:)))
    }

    private static func makeSearchableItem(_ entry: AccountSpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.displayName
        attributes.contentDescription = entry.spotlightSubtitle
        // Selecting the result opens VaultPeek's dashboard. No per-account payload.
        attributes.contentURL = URL(string: deepLinkURL)
        let item = CSSearchableItem(
            uniqueIdentifier: entry.searchableIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        return item
    }
}
