import Foundation

/// Opt-in feature flag gating **server-synced review state** (AND-552 — deferred
/// epic AND-524).
///
/// VaultPeek is local-first: the transaction review state (per-transaction
/// overrides + categorization rules) lives in app-local JSON and the local server
/// never sees it. AND-552 lets a user *optionally* sync that state across their
/// own devices through the local server's new `/api/review` table. Because that
/// expands what the server stores (it would hold the user's category overrides,
/// merchant renames, and notes), it is **strictly opt-in**.
///
/// ## Default OFF — additive, byte-identical when not opted in
///
/// `defaultValue` is **`false`**. With the flag off (the default for a fresh
/// install and every existing user who never enables it), the app never
/// constructs or sends a review snapshot and the server route is simply unused —
/// behavior is byte-identical to before AND-552, and **no review data leaves the
/// device**. Only an explicit, consent-gated opt-in (the Settings toggle) turns
/// syncing on.
///
/// The resolution rule is pure and lives in `PlaidBarCore` so it is `Sendable`,
/// testable without launching the app, and mirrors ``WindowFirstFeatureFlag``.
public enum ServerSyncedReviewFeatureFlag {
    /// `UserDefaults` key persisting the user's opt-in. Absent ⇒ OFF (default).
    public static let storageKey = "featureFlag.serverSyncedReview"

    /// CLI override (QA aid, mirrors `--window-first`): `--server-synced-review
    /// on|off|true|false|1|0`. Lets a QA/test pass exercise the opt-in path
    /// without leaving a durable preference behind. Wins over the stored
    /// preference when present and parseable.
    public static let commandLineFlag = "--server-synced-review"

    /// The flag's default when neither a CLI override nor a stored preference is
    /// present. **OFF** — local-first stays the product; syncing review state to
    /// the server requires explicit consent.
    public static let defaultValue = false

    /// Pure resolution: CLI override (if parseable) wins, else the stored
    /// preference, else `defaultValue` (OFF). No I/O — every input is passed in,
    /// so the whole policy is unit-testable. `cliOverrideRaw` is the raw string
    /// that followed `--server-synced-review` (or `nil` when the flag was absent).
    public static func resolve(
        cliOverrideRaw: String?,
        storedValue: Bool?
    ) -> Bool {
        if let parsed = parse(cliOverrideRaw) {
            return parsed
        }
        if let storedValue {
            return storedValue
        }
        return defaultValue
    }

    /// Parses a CLI override token into a bool, or `nil` when it is absent or not
    /// a recognized on/off spelling — an unparseable value never silently enables
    /// syncing (the caller falls through to the stored preference / OFF default).
    public static func parse(_ raw: String?) -> Bool? {
        guard let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !token.isEmpty else {
            return nil
        }
        switch token {
        case "on", "true", "yes", "1":
            return true
        case "off", "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    /// Resolves the live flag from the CLI arguments and a `UserDefaults` store.
    /// Defaults to the process arguments and `.standard`; both are injectable so
    /// tests drive the wrapper without touching real global state.
    public static func resolved(
        arguments: [String] = CommandLine.arguments,
        defaults: UserDefaults = .standard
    ) -> Bool {
        resolve(
            cliOverrideRaw: CommandLineOptions.value(for: commandLineFlag, in: arguments),
            storedValue: defaults.object(forKey: storageKey) == nil
                ? nil
                : defaults.bool(forKey: storageKey)
        )
    }
}
