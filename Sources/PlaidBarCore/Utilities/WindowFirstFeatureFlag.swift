import Foundation

/// Feature flag gating the window-first hybrid experience (ADR-001, Epic 1 /
/// AND-579, first code step AND-591).
///
/// The migration to a primary `Window` workspace runs **dual-run behind this
/// flag**: while it is OFF the app behaves byte-identically to the popover-first
/// build that shipped today — the menu-bar glance is the only surface and the
/// declarative `Window` scene must not change launch or activation behavior. The
/// window is opt-in until the workspace reaches parity (Epic 9 flips the default
/// and removes the flag).
///
/// The flag defaults **OFF** on purpose: a fresh install, and every existing
/// user who never toggles it, keeps the current popover-only experience. The
/// resolution rule is pure and lives here in `PlaidBarCore` so it is `Sendable`,
/// testable without launching the app, and shared by the UI process. The
/// `CommandLine`/`UserDefaults` plumbing in `resolved()` is a thin wrapper over
/// the pure `resolve(...)` decision.
public enum WindowFirstFeatureFlag {
    /// `UserDefaults` key persisting the user's opt-in. Absent ⇒ OFF (default).
    public static let storageKey = "featureFlag.windowFirst"

    /// CLI override (QA/screenshot aid, mirrors `--appearance` / `--text-size`):
    /// `--window-first on|off|true|false|1|0`. Lets a QA pass exercise the window
    /// without leaving a durable preference behind, and lets a flag-ON build be
    /// forced OFF for a regression capture. The override wins over the stored
    /// preference when present and parseable.
    public static let commandLineFlag = "--window-first"

    /// The flag's default when neither a CLI override nor a stored preference is
    /// present. **OFF** — popover-first stays the shipping default.
    public static let defaultValue = false

    /// Pure resolution: CLI override (if parseable) wins, else the stored
    /// preference, else `defaultValue`. No I/O — every input is passed in, so the
    /// whole policy is unit-testable. `cliOverrideRaw` is the raw string that
    /// followed `--window-first` (or `nil` when the flag was absent).
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
    /// a recognized on/off spelling (in which case the caller falls through to the
    /// stored preference / default — an unparseable value never silently enables).
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
