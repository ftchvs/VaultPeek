import Foundation

/// Local-only haptic-feedback policy for VaultPeek (AND-576).
///
/// Force Touch trackpads can give a small tactile confirmation when the user
/// directly manipulates a control — approving a review row, flipping a toggle,
/// reordering. The app uses `NSHapticFeedbackManager` nowhere today, so this
/// pure model owns the *policy*: which interaction maps to which feedback
/// pattern, and whether haptics fire at all. The actual AppKit call stays in
/// the app target behind a thin helper; keeping the decision here makes it
/// `Sendable` and unit-testable without AppKit.
///
/// Two cardinal rules are encoded:
/// 1. **Respectful by default but opt-out-able.** A user setting gates the whole
///    system. When disabled, `pattern(for:)` returns `nil` and the app performs
///    no feedback — behavior equals today.
/// 2. **Only meaningful, committed direct manipulations get feedback.** This is
///    a fixed, finite set of interaction kinds; minor/continuous state changes
///    are intentionally absent so haptics never fire on every keystroke or
///    hover.

// MARK: - Interaction kinds

/// The committed direct-manipulation interactions that may emit haptic
/// feedback. Deliberately small: only discrete, user-initiated commitments —
/// not hover, scroll, focus, or every transient state change.
public enum HapticInteraction: String, CaseIterable, Sendable {
    /// A review row was approved / marked reviewed (single-row or bulk). The
    /// primary "this is done" confirmation.
    case reviewResolved
    /// A review row was ignored / dismissed from the queue. A softer "removed"
    /// confirmation, distinct from a positive resolution.
    case reviewIgnored
    /// A binary control (toggle/switch) was flipped by the user.
    case toggle
    /// A row/item was pinned or unpinned, or a discrete selection committed.
    case pinToggle
    /// A drag-to-reorder move was committed (drop), not the continuous drag.
    case reorder
}

/// A SwiftUI/AppKit-free token for the kind of tactile feedback to play. The
/// app maps each case onto `NSHapticFeedbackManager.FeedbackPattern`; keeping
/// the enum here lets the mapping be asserted in pure tests.
///
/// - `alignment`: light, for snapping/committing a position (reorder, pin).
/// - `levelChange`: a firmer click for a discrete state change (toggle, ignore).
/// - `generic`: the default confirmation for a committed action (resolve).
public enum HapticPattern: String, CaseIterable, Sendable {
    case alignment
    case levelChange
    case generic
}

// MARK: - User preference

/// Whether direct-manipulation haptics fire. Local-only, opt-out-able, and on
/// by default (sensible default for Force Touch hardware; a no-op on hardware
/// without a haptic engine, which AppKit handles silently).
public enum HapticFeedbackPreference: String, CaseIterable, Sendable, Identifiable {
    case on
    case off

    public static let storageKey = "interaction.hapticFeedback"
    public static let defaultValue: HapticFeedbackPreference = .on

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        }
    }

    /// Whether haptics are enabled under this preference.
    public var isEnabled: Bool { self == .on }
}

// MARK: - Policy

/// Pure mapping from an interaction to the feedback pattern that should play,
/// gated by the enabled flag. The single source of truth the app helper calls.
public enum HapticFeedbackPolicy {
    /// The pattern to play for `interaction`, or `nil` when haptics are disabled.
    ///
    /// `nil` is the off-state contract: the app performs no feedback, so behavior
    /// with haptics disabled (or on Reduce-Motion-style opt-out) equals today.
    public static func pattern(for interaction: HapticInteraction, enabled: Bool) -> HapticPattern? {
        guard enabled else { return nil }
        return pattern(for: interaction)
    }

    /// The pattern an interaction maps to when haptics are enabled. Stable,
    /// total mapping — every interaction has exactly one pattern.
    public static func pattern(for interaction: HapticInteraction) -> HapticPattern {
        switch interaction {
        case .reviewResolved:
            // A committed positive resolution — the default confirmation.
            .generic
        case .reviewIgnored:
            // A discrete "removed" state change — a firmer click distinguishes
            // it from a positive resolution.
            .levelChange
        case .toggle:
            // Binary control flip — the canonical discrete state change.
            .levelChange
        case .pinToggle:
            // Snapping a discrete selection/pin into place — light alignment.
            .alignment
        case .reorder:
            // Committing a reorder drop — light alignment, matching macOS list
            // reordering feel.
            .alignment
        }
    }
}
