import Foundation

/// The pure, testable contract for the reduced menu-bar **glance** that becomes
/// the only menu-bar surface once the window-first hybrid is the default
/// (AND-616 / AND-587).
///
/// The full dashboard moved into the primary `Window`'s Dashboard destination.
/// The glance is read + route only: a sync line, a few high-signal numbers, and
/// a short list of attention chips that **deep-link into window destinations**.
/// It never hosts the dashboard, never mutates finance data, and never carries
/// meaning through color alone (every metric and chip has a label + a glyph).
///
/// Keeping the assembly here in `PlaidBarCore` (CLAUDE.md: shared logic lives in
/// Core) makes the contract — at most ``maximumMetricCount`` metrics and at most
/// ``maximumChipCount`` chips, every chip's route — unit-testable without
/// launching the SwiftUI app. The `MenuBarGlanceView` is a thin renderer over
/// this model.
public struct MenuBarGlanceModel: Equatable, Sendable {
    /// The glance is capped at four metrics so it stays a glance, not a
    /// second dashboard. ``make(...)`` truncates to this.
    public static let maximumMetricCount = 4

    /// Attention chips are capped at three (reusing the existing
    /// ``AttentionQueue.maximumRowCount`` budget so the glance and the
    /// dashboard's status strip can never disagree on how many it shows).
    public static let maximumChipCount = AttentionQueue.maximumRowCount

    /// A single high-signal number (net worth, safe-to-spend, unreviewed count).
    /// Color is never the sole carrier of meaning — every metric pairs a `label`
    /// with a `glyph` (an SF Symbol name) so the signal survives a grayscale /
    /// color-blind reading.
    public struct Metric: Equatable, Sendable, Identifiable {
        public let id: String
        /// Short caption, e.g. "Net worth", "Safe to spend", "To review".
        public let label: String
        /// Pre-formatted, already privacy-masked value, e.g. "$12,450" or "••••".
        public let value: String
        /// SF Symbol backing the metric so the meaning is shape-borne, not tint.
        public let glyph: String

        public init(id: String, label: String, value: String, glyph: String) {
            self.id = id
            self.label = label
            self.value = value
            self.glyph = glyph
        }
    }

    /// One attention chip: a launcher into a window destination (or, for the
    /// local-infrastructure rows, an in-place action). The chip carries the
    /// route the menu-bar hand-off should fire (`route`); when `route` is `nil`
    /// the chip falls back to the underlying row's existing `action` (check the
    /// server, open Settings, refresh) — exactly the `Route.from(attentionRow:)`
    /// contract.
    public struct Chip: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let severity: AttentionQueueSeverity
        /// SF Symbol chosen for distinct *shape* per severity, so a chip's
        /// urgency never rests on color alone.
        public let glyph: String
        public let accessibilityLabel: String
        public let accessibilityHint: String?
        /// The window destination this chip deep-links into, or `nil` for a
        /// local-infrastructure row that keeps its in-place action.
        public let route: Route?
        /// The in-place action to run when `route` is `nil` (server offline,
        /// missing credentials, generic recent-error/sync rows).
        public let fallbackAction: DashboardStatusReadinessAction?

        public init(
            id: String,
            title: String,
            detail: String,
            severity: AttentionQueueSeverity,
            glyph: String,
            accessibilityLabel: String,
            accessibilityHint: String?,
            route: Route?,
            fallbackAction: DashboardStatusReadinessAction?
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.severity = severity
            self.glyph = glyph
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.route = route
            self.fallbackAction = fallbackAction
        }

        /// `true` when the chip routes into a window destination rather than
        /// running an in-place action.
        public var deepLinks: Bool { route != nil }
    }

    /// The one-line sync/connection status text shown at the top of the glance.
    public let syncStatusText: String
    /// SF Symbol for the sync line (shape-borne status, never color alone).
    public let syncStatusGlyph: String
    public let metrics: [Metric]
    public let chips: [Chip]

    public init(syncStatusText: String, syncStatusGlyph: String, metrics: [Metric], chips: [Chip]) {
        self.syncStatusText = syncStatusText
        self.syncStatusGlyph = syncStatusGlyph
        // Defend the contract caps even if a caller over-supplies, so the
        // invariants hold no matter the construction path.
        self.metrics = Array(metrics.prefix(Self.maximumMetricCount))
        self.chips = Array(chips.prefix(Self.maximumChipCount))
    }

    /// Assembles the glance from the live finance signals. Pure: every input is
    /// passed in, so the whole contract is testable without the app.
    ///
    /// - Parameters:
    ///   - netWorth: total assets minus debt (already computed in `WealthSummaryPresentation`).
    ///   - safeToSpend: discretionary headroom (the `SafeToSpendCalculator` amount).
    ///   - unreviewedCount: transactions awaiting review (drives the menu-bar badge too).
    ///   - syncStatusText / syncSeverity: the sync line and its severity glyph.
    ///   - attention: the ≤3-row attention queue (reused so the glance and the
    ///     dashboard status strip stay in lockstep).
    ///   - isMasked: Privacy Mask / App Lock — when on, currency metrics are
    ///     redacted, the unreviewed *count* is withheld (matching
    ///     ``MenuBarReviewBadge/isVisible(unreviewedCount:isMasked:)`` and the
    ///     status-item badge, AND-483), and each attention chip is rebuilt from
    ///     generic, non-identifying copy so institution names and transaction
    ///     counts never leak through the glance.
    public static func make(
        netWorth: Double,
        safeToSpend: Double,
        unreviewedCount: Int,
        syncStatusText: String,
        syncSeverity: AttentionQueueSeverity,
        attention: AttentionQueue,
        isMasked: Bool
    ) -> MenuBarGlanceModel {
        var metrics: [Metric] = [
            Metric(
                id: "net-worth",
                label: "Net worth",
                value: PrivacyMaskPresentation.currency(netWorth, format: .compact, isEnabled: isMasked),
                glyph: "chart.line.uptrend.xyaxis"
            ),
            Metric(
                id: "safe-to-spend",
                label: "Safe to spend",
                value: PrivacyMaskPresentation.currency(safeToSpend, format: .compact, isEnabled: isMasked),
                glyph: "wallet.pass"
            ),
        ]

        // The unreviewed count is withheld while masked — it tracks the same
        // contract as the status-item badge
        // (``MenuBarReviewBadge/isVisible(unreviewedCount:isMasked:)`` and
        // ``ReviewInboxPrivacyPresentation/unreviewedBadge(count:isMasked:)``,
        // AND-483) so the two surfaces can never disagree. When visible it is
        // only surfaced if there is something to review, keeping the glance to
        // the smallest set of high-signal numbers.
        if MenuBarReviewBadge.isVisible(unreviewedCount: unreviewedCount, isMasked: isMasked) {
            metrics.append(
                Metric(
                    id: "to-review",
                    label: "To review",
                    value: String(unreviewedCount),
                    glyph: "tray.full"
                )
            )
        }

        let chips = attention.rows.map { row in
            isMasked
                ? Self.maskedChip(from: row)
                : Chip(
                    id: row.id,
                    title: row.title,
                    detail: row.detail,
                    severity: row.severity,
                    glyph: row.severity.statusSymbolName,
                    accessibilityLabel: row.accessibilityLabel,
                    accessibilityHint: row.accessibilityHint,
                    route: Route.from(attentionRow: row),
                    fallbackAction: row.action
                )
        }

        return MenuBarGlanceModel(
            syncStatusText: syncStatusText,
            syncStatusGlyph: syncSeverity.statusSymbolName,
            metrics: metrics,
            chips: chips
        )
    }

    /// Builds a privacy-safe chip from an attention row while Privacy Mask / App
    /// Lock is on. The raw `row.title`/`row.detail`/`accessibilityLabel` can embed
    /// identifying text — institution names on degraded-item rows, transaction
    /// counts on the unusual-spending row — so under mask we replace the copy with
    /// generic, non-sensitive text. Severity is still conveyed by the glyph SHAPE
    /// and the (non-sensitive) ``AttentionQueueSeverity/statusLabel`` (never color
    /// alone), and the chip keeps its `id`, `severity`, `glyph`, `route`, and
    /// `fallbackAction` so it still deep-links / acts exactly as the unmasked chip.
    static func maskedChip(from row: AttentionQueueRow) -> Chip {
        Chip(
            id: row.id,
            title: row.severity.statusLabel,
            detail: "Hidden while VaultPeek is private.",
            severity: row.severity,
            glyph: row.severity.statusSymbolName,
            accessibilityLabel: "\(row.severity.statusLabel). Hidden while VaultPeek is private.",
            accessibilityHint: nil,
            route: Route.from(attentionRow: row),
            fallbackAction: row.action
        )
    }
}
