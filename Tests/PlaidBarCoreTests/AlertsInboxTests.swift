import Foundation
@testable import PlaidBarCore
import Testing

@Suite("AlertsInbox Tests")
struct AlertsInboxTests {
    private func row(
        _ id: String,
        severity: AttentionQueueSeverity,
        title: String = "Title",
        detail: String = "Detail"
    ) -> AttentionQueueRow {
        AttentionQueueRow(id: id, severity: severity, title: title, detail: detail)
    }

    @Test("Healthy rows are excluded from the alerts feed")
    func healthyRowsExcluded() {
        let inbox = AlertsInbox.make(
            rows: [
                row("a", severity: .healthy),
                row("b", severity: .warning),
                row("c", severity: .blocked),
            ],
            acknowledgedIDs: []
        )
        #expect(inbox.totalCount == 2)
        #expect(!inbox.entries.contains { $0.id == "a" })
    }

    @Test("Empty when every row is healthy")
    func emptyWhenAllHealthy() {
        let inbox = AlertsInbox.make(rows: [row("a", severity: .healthy)], acknowledgedIDs: [])
        #expect(inbox.isEmpty)
        #expect(inbox.totalCount == 0)
        #expect(inbox.unacknowledgedCount == 0)
        #expect(inbox.highestUnacknowledgedSeverity == nil)
    }

    @Test("Blocked sorts before warning")
    func blockedBeforeWarning() {
        let inbox = AlertsInbox.make(
            rows: [
                row("warn", severity: .warning),
                row("block", severity: .blocked),
            ],
            acknowledgedIDs: []
        )
        #expect(inbox.entries.map(\.id) == ["block", "warn"])
    }

    @Test("Unacknowledged sort before acknowledged within a severity")
    func unacknowledgedBeforeAcknowledged() {
        let inbox = AlertsInbox.make(
            rows: [
                row("w1", severity: .warning),
                row("w2", severity: .warning),
                row("w3", severity: .warning),
            ],
            acknowledgedIDs: ["w1"]
        )
        // w1 is acknowledged → sinks below w2, w3 (which keep queue order).
        #expect(inbox.entries.map(\.id) == ["w2", "w3", "w1"])
        #expect(inbox.entries.first { $0.id == "w1" }?.isAcknowledged == true)
    }

    @Test("Sort is stable within the same severity + acknowledged state")
    func stableSortPreservesQueueOrder() {
        let inbox = AlertsInbox.make(
            rows: [
                row("first", severity: .blocked),
                row("second", severity: .blocked),
                row("third", severity: .blocked),
            ],
            acknowledgedIDs: []
        )
        #expect(inbox.entries.map(\.id) == ["first", "second", "third"])
    }

    @Test("Unacknowledged count reflects the acknowledged set")
    func unacknowledgedCount() {
        let rows = [
            row("a", severity: .blocked),
            row("b", severity: .warning),
            row("c", severity: .warning),
        ]
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: []).unacknowledgedCount == 3)
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: ["a"]).unacknowledgedCount == 2)
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: ["a", "b", "c"]).unacknowledgedCount == 0)
    }

    @Test("Highest unacknowledged severity ignores acknowledged blocked rows")
    func highestUnacknowledgedSeverity() {
        let rows = [
            row("block", severity: .blocked),
            row("warn", severity: .warning),
        ]
        // Nothing acknowledged → blocked is highest.
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: []).highestUnacknowledgedSeverity == .blocked)
        // Acknowledge the blocked row → highest unacknowledged is now warning.
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: ["block"]).highestUnacknowledgedSeverity == .warning)
        // Acknowledge everything → nil.
        #expect(AlertsInbox.make(rows: rows, acknowledgedIDs: ["block", "warn"]).highestUnacknowledgedSeverity == nil)
    }

    @Test("entry(id:) resolves a live id and returns nil otherwise")
    func entryLookup() {
        let inbox = AlertsInbox.make(rows: [row("a", severity: .warning)], acknowledgedIDs: [])
        #expect(inbox.entry(id: "a")?.id == "a")
        #expect(inbox.entry(id: "missing") == nil)
        #expect(inbox.entry(id: nil) == nil)
    }

    @Test("Acknowledged entry accessibility label folds in the acknowledged status")
    func entryAccessibilityLabel() {
        let inbox = AlertsInbox.make(
            rows: [row("a", severity: .warning, title: "Sync stale", detail: "Refresh")],
            acknowledgedIDs: ["a"]
        )
        let label = inbox.entry(id: "a")?.accessibilityLabel ?? ""
        #expect(label.contains("Acknowledged."))
    }

    @Test("pruneAcknowledgedIDs drops ids no longer in the live rows")
    func pruneAcknowledged() {
        let rows = [row("live", severity: .warning)]
        let pruned = AlertsInbox.pruneAcknowledgedIDs(["live", "stale"], toRowsIn: rows)
        #expect(pruned == ["live"])
    }
}

@Suite("AlertsSummary Tests")
struct AlertsSummaryTests {
    private func inbox(rows: [(String, AttentionQueueSeverity)], acked: Set<String> = []) -> AlertsInbox {
        AlertsInbox.make(
            rows: rows.map { AttentionQueueRow(id: $0.0, severity: $0.1, title: "T", detail: "D") },
            acknowledgedIDs: acked
        )
    }

    @Test("All-clear when there are no alerts")
    func allClear() {
        let summary = AlertsSummary.make(from: inbox(rows: []))
        #expect(summary.title == "All clear")
        #expect(summary.unacknowledgedBadge == nil)
        #expect(summary.accessibilityLabel.contains("All clear"))
    }

    @Test("All alerts need attention when none acknowledged")
    func allNeedAttention() {
        let summary = AlertsSummary.make(from: inbox(rows: [("a", .blocked), ("b", .warning)]))
        #expect(summary.title == "2 alerts need attention")
        #expect(summary.unacknowledgedBadge == "2")
    }

    @Test("Partial acknowledgement reads as N of M")
    func partialAcknowledged() {
        let summary = AlertsSummary.make(from: inbox(rows: [("a", .blocked), ("b", .warning)], acked: ["a"]))
        #expect(summary.title == "1 of 2 alerts need attention")
        #expect(summary.unacknowledgedBadge == "1")
    }

    @Test("All acknowledged hides the badge")
    func allAcknowledged() {
        let summary = AlertsSummary.make(from: inbox(rows: [("a", .blocked)], acked: ["a"]))
        #expect(summary.title == "1 alert, all acknowledged")
        #expect(summary.unacknowledgedBadge == nil)
    }

    @Test("Singular wording for a single alert")
    func singularWording() {
        let summary = AlertsSummary.make(from: inbox(rows: [("a", .warning)]))
        // A single unacknowledged alert uses the singular noun + verb agreement.
        #expect(summary.title == "1 alert needs attention")
        #expect(!summary.title.contains("alerts"))
    }
}
