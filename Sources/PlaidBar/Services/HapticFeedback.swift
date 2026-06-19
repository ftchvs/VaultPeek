import AppKit
import PlaidBarCore

/// Thin app-side bridge from the pure `HapticFeedbackPolicy` (Core) to AppKit's
/// `NSHapticFeedbackManager` (AND-576).
///
/// The *policy* — which interaction maps to which pattern, and whether haptics
/// fire at all — lives in `PlaidBarCore` so it stays `Sendable` and unit-tested.
/// This helper is the only place that touches AppKit: it resolves the pattern
/// for an interaction (gated by the user preference) and, when one is returned,
/// performs it on `NSHapticFeedbackManager.defaultPerformer`.
///
/// Force Touch trackpads give a small tactile confirmation; on hardware without
/// a haptic engine the performer is a silent no-op, which AppKit handles — so
/// this is safe to call unconditionally on any Mac. When the preference is off
/// (or `enabled: false` is passed) `pattern(for:enabled:)` returns `nil` and
/// nothing is performed, so behavior equals today.
@MainActor
enum HapticFeedback {
    /// Plays the feedback pattern the policy maps `interaction` to, if any.
    ///
    /// - Parameters:
    ///   - interaction: the committed direct-manipulation kind.
    ///   - enabled: the resolved user preference (default on). When `false`,
    ///     no feedback is performed.
    static func play(_ interaction: HapticInteraction, enabled: Bool) {
        guard let pattern = HapticFeedbackPolicy.pattern(for: interaction, enabled: enabled) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            feedbackPattern(for: pattern),
            performanceTime: .default
        )
    }

    /// Maps the Core, AppKit-free `HapticPattern` token onto AppKit's concrete
    /// `NSHapticFeedbackManager.FeedbackPattern`. Kept private and exhaustive so
    /// adding a Core pattern forces a decision here.
    private static func feedbackPattern(
        for pattern: HapticPattern
    ) -> NSHapticFeedbackManager.FeedbackPattern {
        switch pattern {
        case .alignment: .alignment
        case .levelChange: .levelChange
        case .generic: .generic
        }
    }
}
