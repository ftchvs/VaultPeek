import SwiftUI

/// Skeleton for the window-first primary workspace (ADR-001, Epic 1 / AND-579,
/// first code step AND-591).
///
/// This is an **empty** `NavigationSplitView` shell — a sidebar placeholder and a
/// content placeholder, with **no routing or destinations yet**. The typed
/// `Route` enum, the `@Observable` navigation model, the sidebar groups, and the
/// ⌘K command palette all land in Epic 2 (AND-580+). Keeping this PR to the scene
/// + skeleton makes the window scaffolding reviewable on its own and lets it ship
/// behind a flag (`WindowFirstFeatureFlag`, default OFF) without touching the
/// popover.
///
/// Liquid Glass on chrome is applied at the scene level via
/// `.containerBackground(.ultraThinMaterial, for: .window)` in `PlaidBarApp`, not
/// here — per ADR-001 the glass goes on chrome only, never on data.
struct AppShellView: View {
    var body: some View {
        NavigationSplitView {
            // Sidebar placeholder. Epic 2 replaces this with the 4 navigation
            // groups (Overview / Workflows / Insights / Money / System) backed by
            // a typed `Route` enum and a single `@Observable` navigation model.
            ContentUnavailableView {
                Label("VaultPeek", systemImage: "sidebar.left")
            } description: {
                Text("Navigation arrives in a later step.")
            }
            .navigationTitle("VaultPeek")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            // Content placeholder. Epic 2 routes the selected sidebar destination
            // (Dashboard, Transactions, Budgets, …) into this column.
            ContentUnavailableView(
                "Window-First Workspace",
                systemImage: "macwindow",
                description: Text("The primary workspace is under construction.")
            )
        }
    }
}

#Preview {
    AppShellView()
}
