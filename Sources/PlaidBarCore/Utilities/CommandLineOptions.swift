public enum CommandLineOptions {
    /// Flag that drives the headless snapshot renderer
    /// (`--demo --render-snapshot <dir>`); see `SnapshotRenderer`.
    public static let renderSnapshotFlag = "--render-snapshot"

    public static func value(for flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else {
            return nil
        }

        let value = arguments[index + 1]
        guard !value.hasPrefix("--") else { return nil }
        return value
    }

    /// True when the process was launched to render headless snapshots. Such
    /// runs must behave deterministically regardless of host/CI defaults, so
    /// callers use this to neutralize persisted intents (e.g. a stale
    /// `dashboard.detached = true`) that would otherwise change which window is
    /// captured. Keyed on the flag's presence — no real app launch passes it.
    public static func isRenderingSnapshot(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(renderSnapshotFlag)
    }
}
