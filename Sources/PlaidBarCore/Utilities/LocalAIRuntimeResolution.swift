import Foundation

/// Pure decision logic for the optional on-device AI runtime: whether the user
/// has opted in, and what availability state to surface.
///
/// This lives in `PlaidBarCore` (not the app target) so it stays `Sendable` and
/// unit-testable. It owns no runtime: the app target constructs the actual model
/// (Ollama/`URLSession`) and feeds the few facts this type needs (`hasWiredModel`,
/// `endpointIsLocalhost`, a generation result). The type only decides states and
/// copy.
///
/// Boundary rationale (see `AGENTS.md`): the app may move Plaid-derived data only
/// to the local `PlaidBarServer`. Routing transaction-derived prompt text into a
/// *separate* local service (Ollama) is an additional data movement, so it must be
/// an explicit user opt-in — never the default for anyone who happens to run
/// something on `127.0.0.1:11434`.
public enum LocalAIRuntimeResolution {
    /// Environment variable that opts a user in to a local model runtime.
    public static let optInEnvironmentKey = "PLAIDBAR_LOCAL_AI_RUNTIME"

    /// Runtime tokens this build can actually wire. Anything else is treated as
    /// a misconfiguration and never auto-wired.
    private static let supportedRuntimes: Set<String> = ["auto", "ollama"]
    private static let disabledValues: Set<String> = ["disabled", "off", "false", "none"]

    /// Trimmed runtime token; empty string when the variable is unset.
    public static func runtimeName(from rawValue: String?) -> String {
        rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The runtime is OFF unless the user explicitly opts in with a supported
    /// value. An unset variable must NOT auto-wire a model.
    public static func isOptedIn(rawValue: String?) -> Bool {
        let name = runtimeName(from: rawValue).lowercased()
        guard !name.isEmpty, !disabledValues.contains(name) else { return false }
        return supportedRuntimes.contains(name)
    }

    /// App settings take precedence over environment variables. A `nil`
    /// preference means no persisted app choice exists yet, so environment
    /// fallback can still opt in for CLI/debug launches.
    public static func isOptedIn(enabledPreference: Bool?, rawValue: String?) -> Bool {
        if let enabledPreference { return enabledPreference }
        return isOptedIn(rawValue: rawValue)
    }

    /// True only when the user set the variable to an explicit "off" value, as
    /// opposed to leaving it unset (also off, but opt-in copy differs).
    public static func isExplicitlyDisabled(rawValue: String?) -> Bool {
        disabledValues.contains(runtimeName(from: rawValue).lowercased())
    }

    public static func isExplicitlyDisabled(enabledPreference: Bool?, rawValue: String?) -> Bool {
        if let enabledPreference { return !enabledPreference }
        return isExplicitlyDisabled(rawValue: rawValue)
    }

    /// True when a non-empty value names a runtime this build does not support
    /// (e.g. a cloud model name). Such values never auto-wire anything.
    public static func isUnsupportedRuntime(rawValue: String?) -> Bool {
        let name = runtimeName(from: rawValue).lowercased()
        guard !name.isEmpty, !disabledValues.contains(name) else { return false }
        return !supportedRuntimes.contains(name)
    }

    /// Synchronous, configuration-level availability. It never returns
    /// `.available`: on-device liveness can only be proven by a real call, so an
    /// opted-in, statically valid runtime reports `.checking` until
    /// `resolved(...)` upgrades it from an actual generation.
    public static func configuredAvailability(
        enabledPreference: Bool? = nil,
        rawValue: String?,
        hasWiredModel: Bool,
        endpointIsLocalhost: Bool
    ) -> LocalAIAvailability {
        let runtime = enabledPreference == true ? "ollama" : runtimeName(from: rawValue)

        guard isOptedIn(enabledPreference: enabledPreference, rawValue: rawValue) else {
            return LocalAIAvailability(
                state: .disabled,
                detail: disabledDetail(enabledPreference: enabledPreference, rawValue: rawValue)
            )
        }

        guard endpointIsLocalhost else {
            return LocalAIAvailability(
                state: .unavailable,
                runtimeName: runtime,
                detail: "Local AI must run on localhost. VaultPeek refused the non-local endpoint and used deterministic summaries without cloud fallback."
            )
        }

        guard hasWiredModel else {
            return LocalAIAvailability(
                state: .unavailable,
                runtimeName: runtime,
                detail: "Local \(runtime) could not be configured. Deterministic summaries remain active; cloud models are not supported."
            )
        }

        return LocalAIAvailability(
            state: .checking,
            runtimeName: runtime,
            detail: "Verifying local runtime '\(runtime)' on this Mac. VaultPeek only talks to localhost, validates output, and falls back to deterministic local summaries."
        )
    }

    /// Resolve a `.checking`/`.available` base into a final state from the result
    /// of a real generation attempt. Terminal states (`.disabled`,
    /// `.unavailable`) pass through unchanged.
    public static func resolved(
        base: LocalAIAvailability,
        usedModelOutput: Bool,
        fallbackReason: LocalInsightModelFallbackReason?,
        fallbackDiagnostic: String? = nil
    ) -> LocalAIAvailability {
        guard base.state == .checking || base.state == .available else { return base }

        if usedModelOutput {
            return LocalAIAvailability(
                state: .available,
                runtimeName: base.runtimeName,
                detail: availableDetail(runtimeName: base.runtimeName),
                probeErrorText: nil
            )
        }

        guard let fallbackReason else { return base }

        return LocalAIAvailability(
            state: .unavailable,
            runtimeName: base.runtimeName,
            detail: fallbackDetail(
                runtimeName: base.runtimeName,
                reason: fallbackReason,
                diagnostic: fallbackDiagnostic
            ),
            probeErrorText: fallbackDiagnostic
        )
    }

    /// Whether a state should still feed transaction-derived prompts to the
    /// model. Only engaged runtimes (`.available`/`.checking`) do.
    public static func usesModel(for state: LocalAIAvailabilityState) -> Bool {
        state == .checking || state == .available
    }

    // MARK: - Copy

    static func disabledDetail(enabledPreference: Bool? = nil, rawValue: String?) -> String {
        if isExplicitlyDisabled(enabledPreference: enabledPreference, rawValue: rawValue) {
            return "Local AI is disabled. VaultPeek is using deterministic local summaries and category hints only."
        }
        if isUnsupportedRuntime(rawValue: rawValue) {
            return "Local runtime '\(runtimeName(from: rawValue))' is not supported. This build only wires a local Ollama runtime, and only when you opt in. Deterministic summaries remain active; cloud models are not supported."
        }
        return "Local AI is off. Set \(optInEnvironmentKey)=ollama to opt in to on-device summaries via a local Ollama runtime; until then VaultPeek uses deterministic local summaries and category hints only."
    }

    static func availableDetail(runtimeName: String?) -> String {
        let runtime = runtimeName.map { "Local runtime '\($0)'" } ?? "The local runtime"
        return "\(runtime) produced this summary on-device. VaultPeek only talks to localhost, validates output, and falls back to deterministic local summaries."
    }

    static func fallbackDetail(
        runtimeName: String?,
        reason: LocalInsightModelFallbackReason,
        diagnostic: String? = nil
    ) -> String {
        let runtime = runtimeName.map { "Local runtime '\($0)'" } ?? "The configured local runtime"
        let reasonText = switch reason {
        case .noModel:
            "has no model adapter"
        case .runtimeUnavailable:
            "is not reachable on this Mac"
        case .noInstalledModel:
            "has no installed local model"
        case .unsupportedConfiguration:
            "is configured with an unsupported local endpoint"
        case .timeout:
            "timed out before producing output"
        case .modelError:
            "returned an error"
        case .invalidOutput:
            "returned invalid or unsafe output"
        }
        var detail = "\(runtime) \(reasonText). VaultPeek used deterministic local summaries and did not call cloud AI."
        if let diagnostic, !diagnostic.isEmpty {
            detail += " Probe error: \(diagnostic)"
        }
        return detail
    }
}
