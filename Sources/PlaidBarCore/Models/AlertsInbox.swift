import Foundation

/// Pure reduction of the live ``AttentionQueue`` rows into the **Alerts**
/// destination's list → detail feed (Epic 7 / AND-585, ADR-001 window-first).
///
/// The ``AttentionQueue`` rows are *stateless* — they are recomputed every render
/// from the current connection/sync/financial facts, so they carry no
/// acknowledged/cleared bit. The Alerts destination needs exactly that: a user
/// can acknowledge an alert (mute it from the unacknowledged count without making
/// the underlying condition disappear) and the feed must reflect how many remain
/// unacknowledged. ``AlertsInbox`` layers that per-window acknowledgement state on
/// top of the live rows **without mutating the rows or the queue** — the
/// acknowledged-id set is owned by the view (per-window `@State`), passed in here,
/// and reduced into a sorted, display-safe list.
///
/// This stays in `PlaidBarCore` (pure, `Sendable`, unit-tested) so the destination
/// view is a thin renderer and the sort/acknowledge/count policy is verifiable
/// without the app target (CLAUDE.md).
///
/// Meaning never rides on color alone: every entry exposes a severity label +
/// SF Symbol the view pairs with its tint (ACCESSIBILITY.md).
public struct AlertsInbox: Sendable, Equatable {
    /// One alert in the feed — a live ``AttentionQueueRow`` plus its
    /// acknowledged bit. Identifiable by the row id so SwiftUI selection and the
    /// acknowledged set key off the same stable identity.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let row: AttentionQueueRow
        public let isAcknowledged: Bool

        public var id: String { row.id }
        public var severity: AttentionQueueSeverity { row.severity }
        public var title: String { row.title }
        public var detail: String { row.detail }

        public init(row: AttentionQueueRow, isAcknowledged: Bool) {
            self.row = row
            self.isAcknowledged = isAcknowledged
        }

        /// VoiceOver label for the row, folding in the acknowledged state so the
        /// status is spoken, never carried by tint alone.
        public var accessibilityLabel: String {
            let base = row.accessibilityLabel
            return isAcknowledged ? "\(base) Acknowledged." : base
        }
    }

    /// All alerts, most-urgent first (blocked → warning), acknowledged entries
    /// sinking below unacknowledged ones of the same severity so the list reads
    /// as a work queue. Healthy rows are excluded — they are not alerts.
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Reduce the live attention rows + the acknowledged-id set into a sorted
    /// feed. Healthy rows are dropped (they are not alerts to act on); the
    /// remainder are ordered blocked-before-warning, then unacknowledged before
    /// acknowledged, then by the queue's own order (stable) so the list never
    /// reshuffles spuriously between renders.
    public static func make(
        rows: [AttentionQueueRow],
        acknowledgedIDs: Set<String>
    ) -> AlertsInbox {
        let actionable = rows.filter { $0.severity != .healthy }
        let entries = actionable
            .enumerated()
            .map { index, row in
                (index: index, entry: Entry(row: row, isAcknowledged: acknowledgedIDs.contains(row.id)))
            }
            .sorted { lhs, rhs in
                let leftRank = severityRank(lhs.entry.severity)
                let rightRank = severityRank(rhs.entry.severity)
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.entry.isAcknowledged != rhs.entry.isAcknowledged {
                    return !lhs.entry.isAcknowledged // unacknowledged first
                }
                return lhs.index < rhs.index // stable: preserve queue order
            }
            .map(\.entry)
        return AlertsInbox(entries: entries)
    }

    /// `true` when there are no actionable alerts (every condition is healthy).
    public var isEmpty: Bool { entries.isEmpty }

    /// Total actionable alerts, regardless of acknowledgement.
    public var totalCount: Int { entries.count }

    /// Alerts the user has not yet acknowledged — the number the feed surfaces as
    /// "needs you". This is the same "do I need to act?" rollup the sidebar badge
    /// keys off, minus the ones the user has muted.
    public var unacknowledgedCount: Int {
        entries.lazy.filter { !$0.isAcknowledged }.count
    }

    /// Highest severity across unacknowledged alerts; `nil` when none remain.
    /// Chrome that escalates only on hard failures keys off `.blocked`.
    public var highestUnacknowledgedSeverity: AttentionQueueSeverity? {
        entries
            .lazy
            .filter { !$0.isAcknowledged }
            .map(\.severity)
            .max { Self.severityRank($0) > Self.severityRank($1) }
    }

    /// The entry for a given id, if it is still in the live feed. Used by the
    /// detail column to resolve a selection that may have aged out (the
    /// underlying condition resolved between renders).
    public func entry(id: String?) -> Entry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    /// Restrict an acknowledged-id set to ids still present in the feed, so the
    /// set never accumulates ids for conditions that have since resolved. The
    /// view calls this when it observes new rows, keeping its `@State` bounded.
    public static func pruneAcknowledgedIDs(
        _ acknowledgedIDs: Set<String>,
        toRowsIn rows: [AttentionQueueRow]
    ) -> Set<String> {
        let liveIDs = Set(rows.map(\.id))
        return acknowledgedIDs.intersection(liveIDs)
    }

    // MARK: - Sort policy

    /// Lower rank = more urgent, so the natural ascending sort lists blocked
    /// before warning. Healthy is ranked last but never appears (filtered out).
    private static func severityRank(_ severity: AttentionQueueSeverity) -> Int {
        switch severity {
        case .blocked: 0
        case .warning: 1
        case .healthy: 2
        }
    }
}

// MARK: - Alerts summary

/// One-line, display-safe header summary for the Alerts destination: how many
/// alerts there are and how many still need acknowledgement, phrased for both the
/// visible header chip and VoiceOver. Pure so the wording is unit-tested.
public struct AlertsSummary: Sendable, Equatable {
    public let title: String
    public let accessibilityLabel: String
    /// Discrete count chip text for the header, or `nil` when nothing is
    /// unacknowledged (the chip hides at zero rather than showing "0").
    public let unacknowledgedBadge: String?

    public init(title: String, accessibilityLabel: String, unacknowledgedBadge: String?) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.unacknowledgedBadge = unacknowledgedBadge
    }

    public static func make(from inbox: AlertsInbox) -> AlertsSummary {
        let total = inbox.totalCount
        let unacked = inbox.unacknowledgedCount

        if total == 0 {
            return AlertsSummary(
                title: "All clear",
                accessibilityLabel: "Alerts. All clear, nothing needs attention.",
                unacknowledgedBadge: nil
            )
        }

        let title: String
        if unacked == 0 {
            let alertWord = total == 1 ? "alert" : "alerts"
            title = "\(total) \(alertWord), all acknowledged"
        } else if unacked == total {
            // Grammatically agree with the count: "1 alert needs" / "2 alerts need".
            let verb = unacked == 1 ? "needs" : "need"
            let alertWord = unacked == 1 ? "alert" : "alerts"
            title = "\(unacked) \(alertWord) \(verb) attention"
        } else {
            title = "\(unacked) of \(total) alerts need attention"
        }

        return AlertsSummary(
            title: title,
            accessibilityLabel: "Alerts. \(title).",
            unacknowledgedBadge: unacked == 0 ? nil : "\(unacked)"
        )
    }
}
