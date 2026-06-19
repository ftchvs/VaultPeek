import AppIntents
import Foundation
import PlaidBarCore
import WidgetKit

// MARK: - Focus-aware Privacy Mask (AND-506)
//
// A `SetFocusFilterIntent` lets the user attach VaultPeek to any Focus (Work, a
// shared Focus, Do Not Disturb…) in System Settings → Focus → Focus Filters.
// When that Focus turns on, the system calls `perform()` with the configured
// parameters; when it turns off, the system calls `perform()` again with the
// default parameters. We translate each callback into a desired Privacy-Mask
// state and route it through the EXISTING privacy-mask command channel
// (`PrivacyMaskControlCommandReader.write` →
// `AppState.applyPendingPrivacyMaskControlCommand`) — the app-side twin of the
// Control Center toggle's writer (`WidgetControlCommandStore.savePrivacyCommand`,
// extension target). No new state machinery in `AppState`.
//
// All the real logic — "given the Focus turned on/off, what should the mask be,
// and what prior state must I remember so I can restore it" — lives in
// `FocusPrivacyMaskDecision` (PlaidBarCore) and is unit-tested there. This file
// is the thin AppIntents shell: read inputs, call the pure decision, persist the
// command + the remembered prior state.
//
// `openAppWhenRun` is intentionally **false** (inherited default): toggling a
// Focus should silently mask figures without yanking VaultPeek to the
// foreground. The app applies the pending command on its next activation, the
// same way the Control Center toggle is consumed. Values only — never tokens or
// balances.

struct FocusPrivacyFilterIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Privacy Mask while focused"
    static let description = IntentDescription(
        "Automatically hide VaultPeek balances while this Focus is on, then restore your previous setting when it ends."
    )

    /// Whether this Focus should turn Privacy Mask on. Defaulting to `true` means
    /// adding the filter does the obvious thing (mask while focused); the user can
    /// uncheck it to make the filter inert without removing it. A non-optional
    /// `SetFocusFilterIntent` parameter must supply a default.
    @Parameter(title: "Hide balances", default: true)
    var hideBalances: Bool

    /// The configuration summary the system shows in the Focus settings UI.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: hideBalances ? "Hide VaultPeek balances" : "Leave VaultPeek balances visible"
        )
    }

    func perform() async throws -> some IntentResult {
        // The system invokes `perform()` with the configured parameters when a
        // Focus carrying this filter turns on, and again with the default
        // parameters when it turns off. `SetFocusFilterIntent.current` resolves to
        // the active filter instance while a matching Focus is on and throws once
        // none is — that's our activate/deactivate signal.
        let focusActive = await Self.isFocusActive()
        let currentMask = AppGroupSnapshotStore.loadIfAvailable()?.isMasked ?? false
        let remembered = FocusPrivacyMaskMemory.load()

        let outcome = FocusPrivacyMaskDecision.resolve(
            focusActive: focusActive,
            maskWhileFocused: hideBalances,
            currentMaskEnabled: currentMask,
            rememberedMask: remembered
        )

        // Persist the prior-state bookkeeping first so a crash between the two
        // writes can't strand a mask the user can't undo via this filter.
        FocusPrivacyMaskMemory.store(outcome.rememberedMask)

        // Only write a command when the desired state actually differs, so a
        // no-op callback (inert filter, or restoring to the same value) doesn't
        // churn the snapshot or fight an in-app toggle.
        if outcome.desiredMaskEnabled != currentMask {
            try PrivacyMaskControlCommandReader.write(
                PrivacyMaskControlCommand(maskEnabled: outcome.desiredMaskEnabled, requestedAt: Date())
            )
            // Reload the Control Center toggle + widgets so the "Privacy Mask"
            // control reflects the new state even before the app applies it.
            ControlCenter.shared.reloadAllControls()
            WidgetCenter.shared.reloadAllTimelines()
        }

        return .result()
    }

    /// Whether a Focus that includes this filter is currently active.
    ///
    /// `SetFocusFilterIntent.current` resolves to the configured filter instance
    /// while a matching Focus is on and throws when none is, so a successful read
    /// means "active" and a throw means "deactivating". This is the one place
    /// that distinguishes the activation call from the deactivation call.
    private static func isFocusActive() async -> Bool {
        (try? await current) != nil
    }
}

// MARK: - Remembered pre-Focus mask state

/// Persists the user's Privacy-Mask state from *before* a Focus turned masking
/// on, so deactivation can restore it. Stored in the App Group `UserDefaults`
/// (shared with the widget/control surfaces); a single bool, never a balance.
enum FocusPrivacyMaskMemory {
    private static let key = "focusPrivacyMask.rememberedPriorMask"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: FinanceSnapshot.appGroupIdentifier) ?? .standard
    }

    /// The remembered pre-Focus mask, or `nil` when nothing is stored.
    static func load() -> Bool? {
        let store = defaults
        guard store.object(forKey: key) != nil else { return nil }
        return store.bool(forKey: key)
    }

    /// Stores the remembered value, or removes it when `value == nil`.
    static func store(_ value: Bool?) {
        let store = defaults
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }
}
