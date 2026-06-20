import PlaidBarCore
import SwiftUI

/// Shared selection state for the 3-column **Budgets** destination (Epic 5 /
/// AND-583).
///
/// `AppShellView` mounts `BudgetsDestinationView` (content) and
/// `BudgetsDestinationView.Inspector` (detail) as **separate** views in different
/// columns of a `NavigationSplitView`, so they cannot share `@State`. This tiny
/// `@MainActor @Observable` singleton is the bridge: the content column writes the
/// tapped category; the inspector column reads it to show that category's
/// detail/editor. Selection is ephemeral UI state — no persistence schema — so a
/// shared in-memory model is exactly the right scope.
///
/// Window-first surface only: it is referenced solely from the Budgets
/// destination, which is built behind `WindowFirstFeatureFlag` via `AppShellView`.
/// With the flag OFF the workspace never mounts, so this is never instantiated and
/// the popover is byte-identical.
@MainActor
@Observable
final class BudgetsSelectionModel {
    /// Process-wide shared instance — the only way the two split-view columns can
    /// observe the same selection (they have no common SwiftUI parent to inject an
    /// environment object through). Mirrors the app's existing singleton pattern
    /// (e.g. `ServerProcessService.shared`).
    static let shared = BudgetsSelectionModel()

    /// The category whose detail/editor the inspector shows. `nil` means the
    /// inspector is content-gated — it renders the "Select a category" prompt
    /// (IA §3.1), never collapsing.
    var selectedCategory: SpendingCategory?

    private init() {}
}
