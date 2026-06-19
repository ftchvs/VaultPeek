import Foundation

/// Pure presenter for the animated shared-element reflow of the dashboard
/// filter bar's selection pill (AND-577).
///
/// The view layer renders a single glass "pill" behind the active filter
/// segment and uses `matchedGeometryEffect` to glide it from one segment to the
/// next on selection change. All of the policy that decides *which* segment owns
/// the pill and *whether* the glide animates lives here so it stays `Sendable`,
/// testable without SwiftUI, and identical across the popover and the detached
/// window.
///
/// Additive + reversible: when the glide is disabled (Reduce Motion on) the
/// pill snaps instantly, exactly matching the native segmented control's prior
/// behavior — the selection itself is never changed by this model.
public enum DashboardFilterReflowModel {
    /// Fixed namespace prefix for the pill's `matchedGeometryEffect` id. Keeps
    /// the id collision-resistant against any other matched-geometry pair in
    /// the same SwiftUI `Namespace` and keeps it human-debuggable.
    public static let geometryIDPrefix = "dashboard.filter.pill"

    /// Stable `matchedGeometryEffect` id for a filter segment.
    ///
    /// Derived only from the kind's raw value, so a given kind always yields the
    /// same id — the pill matches the same logical segment across renders,
    /// windows, and processes. Distinct per kind, so the matched-geometry pair
    /// never fuses two segments.
    public static func geometryID(for kind: DashboardAccountFilterKind) -> String {
        "\(geometryIDPrefix).\(kind.rawValue)"
    }

    /// Whether the selection pill should *glide* (animated reflow) rather than
    /// snap when the filter changes.
    ///
    /// Reduce Motion on ⇒ `false`: no geometry animation, instant snap, byte-for-
    /// byte the same end state as today. This is the single gate that satisfies
    /// the project's one-place Reduce-Motion policy (`MotionTokens`).
    public static func shouldAnimateGlide(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// True only for the currently selected segment. The view uses this to place
    /// the single pill (`matchedGeometryEffect(isSource: true)`) on exactly one
    /// segment and to weight that segment's label.
    public static func isSelected(
        _ candidate: DashboardAccountFilterKind,
        selected: DashboardAccountFilterKind
    ) -> Bool {
        candidate == selected
    }
}
