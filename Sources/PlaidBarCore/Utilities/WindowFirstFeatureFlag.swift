import Foundation

/// Feature flag gating the window-first hybrid experience (Epic 1 / AND-579,
/// first code step AND-591; default flipped in Epic 9 / AND-616).
///
/// The migration to a primary `Window` workspace ran **dual-run behind this
/// flag**. Epic 9 (AND-616) flipped the default **ON**: window-first is now the
/// shipping experience and the menu bar is reduced to a glance that routes into
/// the window. The flag is retained this stage only as a hidden escape hatch —
/// a user (or a QA pass via the `--window-first off` CLI override) can force the
/// legacy popover back. Stage 2 removes the flag entirely once the flip has
/// soaked.
///
/// The flag defaults **ON** as of AND-616: a fresh install, and every existing
/// user who never toggles it, gets the window-first hybrid (glance + primary
/// window). The resolution rule is pure and lives here in `PlaidBarCore` so it
/// is `Sendable`, testable without launching the app, and shared by the UI
/// process. The `CommandLine`/`UserDefaults` plumbing in `resolved()` is a thin
/// wrapper over the pure `resolve(...)` decision.
public enum WindowFirstFeatureFlag {
    /// `UserDefaults` key persisting the user's opt-in. Absent ⇒ OFF (default).
    public static let storageKey = "featureFlag.windowFirst"

    /// CLI override (QA/screenshot aid, mirrors `--appearance` / `--text-size`):
    /// `--window-first on|off|true|false|1|0`. Lets a QA pass force the now-legacy
    /// popover back on without leaving a durable preference behind, and lets the
    /// window-first default be exercised explicitly. The override wins over the
    /// stored preference when present and parseable.
    public static let commandLineFlag = "--window-first"

    /// The flag's default when neither a CLI override nor a stored preference is
    /// present. **ON** as of AND-616 — window-first is the shipping default; the
    /// menu bar is a glance into the primary window.
    public static let defaultValue = true

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
