import Foundation

// MARK: - Focus-aware Privacy Mask decision (AND-506)
//
// A `SetFocusFilterIntent` (in the app target) fires `perform()` when a Focus
// the user has configured with VaultPeek's filter turns **on** (with the
// configured parameters) and again when it turns **off** (with default
// parameters). The intent itself is a thin shell: it converts that callback into
// a desired Privacy-Mask state and routes it through the existing privacy-mask
// command channel (`WidgetControlCommandStore.savePrivacyCommand` →
// `AppState.applyPendingPrivacyMaskControlCommand`).
//
// The only real logic — "given the Focus turned on/off, what should the mask be,
// and what prior state must I remember so I can restore it" — lives here so it is
// unit-testable without the AppIntents runtime. The Focus callback is otherwise
// stateless, so we thread the remembered pre-Focus mask state through the
// decision rather than reading app state inside the intent.

/// The outcome of reconciling a Focus activation/deactivation with the current
/// Privacy-Mask state.
public struct FocusPrivacyMaskOutcome: Sendable, Equatable {
    /// The Privacy-Mask state the app should apply (`true` hides figures).
    public let desiredMaskEnabled: Bool

    /// The pre-Focus mask state to persist so it can be restored when the Focus
    /// later deactivates, or `nil` when nothing should be remembered (the Focus
    /// is off, or this filter does not drive masking).
    ///
    /// `Bool??` would be ambiguous, so this is modeled as: write `rememberedMask`
    /// when non-`nil`; clear any stored value when `nil`.
    public let rememberedMask: Bool?

    public init(desiredMaskEnabled: Bool, rememberedMask: Bool?) {
        self.desiredMaskEnabled = desiredMaskEnabled
        self.rememberedMask = rememberedMask
    }
}

/// Pure decision for the Focus-aware Privacy Mask feature (AND-506).
///
/// `SetFocusFilterIntent.perform()` is invoked on both Focus activation and
/// deactivation; this helper turns each invocation into the desired mask state
/// plus the prior-state bookkeeping needed to restore the user's choice when the
/// Focus ends — without the intent touching app state directly.
public enum FocusPrivacyMaskDecision {
    /// Reconciles a Focus filter callback with the current mask state.
    ///
    /// - Parameters:
    ///   - focusActive: Whether the configured Focus is currently on. The system
    ///     passes the configured parameters when on and the defaults (Focus off)
    ///     when off.
    ///   - maskWhileFocused: The filter's user choice — whether this Focus should
    ///     enable Privacy Mask while active. When `false`, the filter is inert and
    ///     never changes the mask in either direction.
    ///   - currentMaskEnabled: The mask state at the moment of the callback, used
    ///     to remember what to restore on deactivation.
    ///   - rememberedMask: The pre-Focus mask state previously stored by an
    ///     activation, or `nil` when none is stored.
    /// - Returns: The mask state to apply and the prior-state value to persist
    ///   (`rememberedMask == nil` means "clear any stored value").
    public static func resolve(
        focusActive: Bool,
        maskWhileFocused: Bool,
        currentMaskEnabled: Bool,
        rememberedMask: Bool?
    ) -> FocusPrivacyMaskOutcome {
        // An inert filter (the user did not ask this Focus to mask) must never
        // move the mask or strand a remembered value — leave everything as-is and
        // forget any prior bookkeeping so a later toggle starts clean.
        guard maskWhileFocused else {
            return FocusPrivacyMaskOutcome(desiredMaskEnabled: currentMaskEnabled, rememberedMask: nil)
        }

        if focusActive {
            // Turning the Focus on: force the mask on. Remember the pre-Focus
            // state so deactivation can restore it — but only capture it the
            // first time (when nothing is remembered yet), so repeated
            // activations while already focused don't overwrite the true prior
            // value with the now-masked `true`.
            let priorToRemember = rememberedMask ?? currentMaskEnabled
            return FocusPrivacyMaskOutcome(desiredMaskEnabled: true, rememberedMask: priorToRemember)
        }

        // Turning the Focus off: restore the remembered pre-Focus state. If we
        // never recorded one (e.g. the app launched mid-Focus), fall back to
        // revealing, since the Focus filter is what was holding the mask on.
        let restored = rememberedMask ?? false
        return FocusPrivacyMaskOutcome(desiredMaskEnabled: restored, rememberedMask: nil)
    }
}
