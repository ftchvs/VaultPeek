import PlaidBarCore
import SwiftUI

/// The shared "workspace coming soon" placeholder every window-first destination
/// renders today (AND-580/581).
///
/// Each destination has its own `…DestinationView` file (so Epics 4–7 can fill
/// them in parallel without colliding in `AppShellView`), but until that real
/// content lands they all show this one labeled `ContentUnavailableView` — the
/// exact placeholder `AppShellView` showed inline before the content-column
/// router (AND-600). Centralizing the copy keeps every scaffold byte-identical
/// and makes the eventual "replace the body" diff per destination trivial.
///
/// Window-first surface only: `AppShellView` is built solely behind
/// `WindowFirstFeatureFlag` (default OFF), so with the flag off none of this is
/// ever instantiated and the popover is unchanged.
struct DestinationPlaceholder: View {
    let destination: RouteDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            Text("The \(destination.title) workspace is coming soon.")
        }
        .navigationTitle(destination.title)
    }
}

/// The inspector (detail-column) empty state a 3-column destination shows when
/// nothing is selected. The third column is **content-gated, not
/// existence-gated**: it always exists and shows this "Select a …"
/// prompt rather than collapsing. The prompt copy is the pure
/// `RouteDestination.detailColumnEmptyPrompt` (PlaidBarCore), so it stays in
/// lockstep with the column policy and is unit-tested at the Core layer.
struct DestinationInspectorPlaceholder: View {
    let destination: RouteDestination

    var body: some View {
        ContentUnavailableView {
            Label(prompt, systemImage: destination.systemImage)
        } description: {
            Text("Choose an item from \(destination.title) to see its details here.")
        }
    }

    /// Falls back to a generic prompt for the (unreachable) case of a 2-column
    /// destination being rendered with an inspector — the router only mounts this
    /// for destinations whose `detailColumnEmptyPrompt` is non-nil.
    private var prompt: String {
        destination.detailColumnEmptyPrompt ?? "Select an item"
    }
}

#Preview("Content placeholder") {
    DestinationPlaceholder(destination: .dashboard)
}

#Preview("Inspector placeholder") {
    DestinationInspectorPlaceholder(destination: .review)
}
