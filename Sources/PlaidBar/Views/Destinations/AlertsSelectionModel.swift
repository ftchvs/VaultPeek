import PlaidBarCore
import SwiftUI

/// Shared selection + acknowledgement state for the 3-column **Alerts**
/// destination (Epic 7 / AND-585, ADR-001 window-first).
///
/// `AppShellView` mounts ``AlertsDestinationView`` (content, the alert list) and
/// ``AlertsDestinationView/Inspector`` (detail, the selected alert) as **separate**
/// views in different columns of a `NavigationSplitView`, so they cannot share
/// `@State`. This tiny `@MainActor @Observable` singleton is the bridge: the list
/// writes the tapped alert id and toggles acknowledgement; the inspector reads the
/// selected id to show that alert's detail and reflects the acknowledged bit.
///
/// **Scope note:** ideally alert selection would live on a *per-window*
/// `NavigationModel` (so two open windows keep independent selections), but Epic 7
/// owns only the destination files and must not edit `NavigationModel`. This
/// mirrors the established ``BudgetsSelectionModel`` shared-singleton bridge for
/// the same split-column constraint. The acknowledged-id set is ephemeral, session-
/// scoped UI state (muting an alert from the unacknowledged count without resolving
/// the underlying condition) — no persistence schema — so a shared in-memory model
/// is the right scope. It is pruned to the live rows on every list render via
/// ``AlertsInbox/pruneAcknowledgedIDs(_:toRowsIn:)`` so it never accumulates ids for
/// conditions that have since resolved.
///
/// Window-first surface only: referenced solely from the Alerts destination, built
/// behind `WindowFirstFeatureFlag` via `AppShellView`. With the flag OFF the
/// workspace never mounts, so this is never instantiated and the popover is
/// byte-identical.
@MainActor
@Observable
final class AlertsSelectionModel {
    /// Process-wide shared instance — the only way the two split-view columns can
    /// observe the same state (they have no common SwiftUI parent to inject an
    /// environment object through). Mirrors ``BudgetsSelectionModel/shared``.
    static let shared = AlertsSelectionModel()

    /// The id of the alert whose detail the inspector shows. `nil` means the
    /// inspector is content-gated — it renders the "Select an alert" prompt
    /// (IA §3.1), never collapsing.
    var selectedAlertID: String?

    /// Ids the user has acknowledged this session. Acknowledging mutes an alert
    /// from the unacknowledged count; it does not resolve the underlying condition
    /// (that clears on its own when the fact changes).
    var acknowledgedIDs: Set<String> = []

    private init() {}

    /// Acknowledge a single alert.
    func acknowledge(_ id: String) {
        acknowledgedIDs.insert(id)
    }

    /// Un-acknowledge a single alert (re-surface it in the count).
    func unacknowledge(_ id: String) {
        acknowledgedIDs.remove(id)
    }

    /// Acknowledge every currently-listed alert ("acknowledge all"/"clear").
    func acknowledgeAll(in inbox: AlertsInbox) {
        for entry in inbox.entries {
            acknowledgedIDs.insert(entry.id)
        }
    }

    /// Drop acknowledged ids for conditions no longer present in the live rows, so
    /// the set stays bounded and a re-occurring condition surfaces again.
    func prune(toRowsIn rows: [AttentionQueueRow]) {
        let pruned = AlertsInbox.pruneAcknowledgedIDs(acknowledgedIDs, toRowsIn: rows)
        if pruned != acknowledgedIDs {
            acknowledgedIDs = pruned
        }
        if let selectedAlertID, !rows.contains(where: { $0.id == selectedAlertID }) {
            self.selectedAlertID = nil
        }
    }
}
