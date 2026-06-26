import Foundation

/// Display-safe "where from / how fresh / what excluded" provenance for a single
/// high-trust derived finance figure (AND-641).
///
/// This generalizes the receipt pattern already used by ``LocalAIInsightReceipt``
/// and ``DashboardChangeReceipt``: a pure, `Sendable`, deterministic value built
/// by a `static` factory from data the figure was *already* derived from. It
/// answers the three questions a number-provenance affordance must answer:
///
/// - **Sources** — which accounts (by display name + type) fed the figure, as
///   user-facing rows. Never raw `account_id`/`item_id` values.
/// - **Freshness** — when the underlying data was last produced (`generatedAt`),
///   rendered relative ("2 min ago") so the user knows how stale the figure is.
/// - **Exclusions** — what was deliberately left out (hidden categories, pending
///   holds, a date range, account types that don't count as spendable cash, etc.),
///   so the number is honest about its boundaries.
///
/// Privacy: like every value surface, provenance honors Privacy Mask / App Lock.
/// When `privacyMaskEnabled` is passed to a factory the source rows carry the
/// dotted placeholder instead of real balances, and exclusion copy never bakes in
/// a real amount. The model itself carries no identifiers, tokens, or Plaid
/// payloads — only display-safe names, counts, and pre-formatted strings.
public struct FigureProvenance: Equatable, Sendable {
    /// One contributing source row — a single account (or an aggregate "row") that
    /// fed the figure, reduced to a display-safe label, an optional value string
    /// (already privacy-mask-aware), and an SF Symbol that pairs with the text so
    /// the row never relies on color alone (ACCESSIBILITY.md).
    public struct Source: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        /// Pre-formatted, privacy-mask-aware value (e.g. a balance or "••••"). Nil
        /// when the row contributes no displayable amount.
        public let value: String?
        public let systemImage: String
        /// Spoken description — never an abbreviation, so VoiceOver reads the row
        /// in full and meaning is never carried by glyph alone.
        public let accessibilityLabel: String

        public init(
            id: String,
            label: String,
            value: String?,
            systemImage: String,
            accessibilityLabel: String
        ) {
            self.id = id
            self.label = label
            self.value = value
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
        }
    }

    /// The figure this provenance describes (e.g. "Net worth"). Used as the popover
    /// title.
    public let figureTitle: String
    /// One-line explanation of how the figure is derived, in plain language.
    public let derivation: String
    /// Contributing source rows (accounts), display-safe.
    public let sources: [Source]
    /// When the underlying data was produced. The UI renders this relative.
    public let freshness: Date?
    /// Pre-rendered relative freshness string (e.g. "Updated 2 min ago"). Falls
    /// back to a "not yet synced" phrasing when `freshness` is nil.
    public let freshnessText: String
    /// What was deliberately excluded from the figure (date range, hidden
    /// categories, pending holds, non-cash account types …). Display-safe copy.
    public let exclusions: [String]
    /// Local-only reassurance badge copy, mirroring the receipt pattern.
    public let localOnlyBadge: String
    /// Flattened VoiceOver summary of the whole popover.
    public let accessibilitySummary: String

    public init(
        figureTitle: String,
        derivation: String,
        sources: [Source],
        freshness: Date?,
        freshnessText: String,
        exclusions: [String],
        localOnlyBadge: String = "Local-only",
        accessibilitySummary: String
    ) {
        self.figureTitle = figureTitle
        self.derivation = derivation
        self.sources = sources
        self.freshness = freshness
        self.freshnessText = freshnessText
        self.exclusions = exclusions
        self.localOnlyBadge = localOnlyBadge
        self.accessibilitySummary = accessibilitySummary
    }

    // MARK: - Net worth

    /// Provenance for the net-worth headline (`WealthSummaryPresentation.netWorth`).
    ///
    /// Net worth mirrors ``MenuBarSummary.netCash(from:)``: depository,
    /// investment, and other accounts contribute their effective balances, while
    /// credit and loan accounts subtract their latest current balance. Every
    /// non-zero account is listed as a source row; debt accounts are shown as
    /// negative contributions.
    public static func netWorth(
        accounts: [AccountDTO],
        freshness: Date?,
        privacyMaskEnabled: Bool = false,
        now: Date = Date()
    ) -> FigureProvenance {
        let contributing = accounts
            .map { account in (account, netWorthContribution(for: account)) }
            .filter { $0.1 != 0 }
        let sources = contributing
            .sorted { abs($0.1) > abs($1.1) }
            .prefix(maxSourceRows)
            .enumerated()
            .map { index, row -> Source in
                sourceRow(
                    id: "net-worth-source-\(index)",
                    for: row.0,
                    amount: row.1,
                    currency: row.0.balances.currency,
                    privacyMaskEnabled: privacyMaskEnabled
                )
            }

        var exclusions: [String] = []
        if contributing.count > maxSourceRows {
            exclusions.append("Showing the \(maxSourceRows) largest of \(contributing.count) contributing accounts.")
        }
        exclusions.append("Reflects the latest balance each bank reported, not pending authorizations.")

        return make(
            figureTitle: "Net worth",
            derivation: "Assets minus debts across your linked accounts.",
            sources: Array(sources),
            freshness: freshness,
            exclusions: exclusions,
            now: now
        )
    }

    // MARK: - Safe to spend

    /// Provenance for the safe-to-spend headline (`SafeToSpendResult.amount`).
    ///
    /// The component breakdown already lives in ``SafeToSpendResult``; this surfaces
    /// the *boundary* of the number: which signed components fed it (as source
    /// rows), the confidence caveat, and what it deliberately leaves out (estimated
    /// income, the horizon date range, the safety buffer).
    public static func safeToSpend(
        result: SafeToSpendResult,
        freshness: Date?,
        privacyMaskEnabled: Bool = false,
        now: Date = Date()
    ) -> FigureProvenance {
        let sources = result.visibleComponents.map { component -> Source in
            let value = privacyMaskEnabled
                ? PrivacyMaskPresentation.compactValue
                : signedCurrency(component.amount)
            let spoken = privacyMaskEnabled
                ? "hidden while Privacy Mask is on"
                : signedSpokenCurrency(component.amount)
            return Source(
                id: component.kind.rawValue,
                label: component.label,
                value: value,
                systemImage: component.kind.iconName,
                accessibilityLabel: "\(component.label), \(spoken)."
            )
        }

        var exclusions: [String] = [
            "Looks ahead through \(Formatters.displayDate(result.horizonEnd)) only.",
        ]
        switch result.confidence {
        case .insufficientData:
            exclusions.append("Income and obligations are too thin to stand behind — treat this as indicative only.")
        case .lowConfidence:
            exclusions.append("Expected income is estimated, not a confirmed pay schedule, so the upside is softer.")
        case .ok:
            break
        }
        exclusions.append("Excludes anything past the horizon and any buffer you've set aside.")

        return make(
            figureTitle: "Safe to spend",
            derivation: "Spendable cash and expected income, minus upcoming bills, holds, and reserves.",
            sources: sources,
            freshness: freshness,
            exclusions: exclusions,
            now: now
        )
    }

    // MARK: - Credit utilization

    /// Provenance for the credit-utilization figure
    /// (`WealthSummaryPresentation.CreditUtilizationSummary`).
    ///
    /// Utilization is used credit over total limit for one credit-card currency.
    /// This lists the scoped credit accounts as sources and notes that accounts
    /// without a known limit contribute used balance but cannot contribute a
    /// denominator.
    public static func creditUtilization(
        summary: WealthSummaryPresentation.CreditUtilizationSummary,
        creditAccounts: [AccountDTO],
        freshness: Date?,
        privacyMaskEnabled: Bool = false,
        now: Date = Date()
    ) -> FigureProvenance {
        let scopedCreditAccounts = creditAccounts.filter {
            $0.balances.currency == summary.currency
        }
        let withoutLimit = scopedCreditAccounts.count { ($0.balances.limit ?? 0) <= 0 }

        let sources = scopedCreditAccounts
            .sorted { abs($0.balances.current ?? 0) > abs($1.balances.current ?? 0) }
            .prefix(maxSourceRows)
            .enumerated()
            .map { index, account -> Source in
                sourceRow(
                    id: "credit-utilization-source-\(index)",
                    for: account,
                    amount: abs(account.balances.current ?? 0),
                    currency: summary.currency,
                    privacyMaskEnabled: privacyMaskEnabled,
                    forceCreditGlyph: true
                )
            }

        var exclusions: [String] = []
        if withoutLimit > 0 {
            exclusions.append("\(withoutLimit) card\(withoutLimit == 1 ? "" : "s") without a reported limit contribute used balance but not total limit.")
        }
        if summary.isMultiCurrency {
            exclusions.append("Reports the highest-utilization \(summary.currency.rawValue) credit group; other credit currencies are tracked separately, not pooled into this ratio.")
        }
        if scopedCreditAccounts.count > maxSourceRows {
            exclusions.append("Showing the \(maxSourceRows) largest of \(scopedCreditAccounts.count) \(summary.currency.rawValue) credit cards.")
        }
        exclusions.append("Based on the balance and limit each bank last reported.")

        let derivation = privacyMaskEnabled
            ? "Balance used divided by total limit for your \(summary.currency.rawValue) credit cards."
            : "Balance used divided by total limit for your \(summary.currency.rawValue) credit cards (\(summary.statusLabel))."

        return make(
            figureTitle: "Credit utilization",
            derivation: derivation,
            sources: Array(sources),
            freshness: freshness,
            exclusions: exclusions,
            now: now
        )
    }

    // MARK: - Shared builders

    /// Cap on rendered source rows so the popover stays a glance, not a ledger.
    private static let maxSourceRows = 6

    private static func netWorthContribution(for account: AccountDTO) -> Double {
        switch account.type {
        case .depository, .investment:
            return account.balances.effectiveBalance
        case .credit, .loan:
            return -abs(account.balances.current ?? 0)
        case .other:
            return account.balances.effectiveBalance
        }
    }

    private static func make(
        figureTitle: String,
        derivation: String,
        sources: [Source],
        freshness: Date?,
        exclusions: [String],
        now: Date
    ) -> FigureProvenance {
        let freshnessText = freshnessText(for: freshness, now: now)
        let sourceSummary = sources.isEmpty
            ? "No contributing accounts."
            : sources.map(\.accessibilityLabel).joined(separator: " ")
        let accessibility = [
            "\(figureTitle) provenance.",
            derivation,
            freshnessText + ".",
            "Sources: " + sourceSummary,
            "Excluded: " + exclusions.joined(separator: " "),
            "Computed on this device.",
        ].joined(separator: " ")

        return FigureProvenance(
            figureTitle: figureTitle,
            derivation: derivation,
            sources: sources,
            freshness: freshness,
            freshnessText: freshnessText,
            exclusions: exclusions,
            accessibilitySummary: accessibility
        )
    }

    /// Builds one account source row. The label is the display name plus the masked
    /// last-4 when present; the value is the privacy-mask-aware balance. No raw
    /// account/item IDs ever appear.
    private static func sourceRow(
        id: String,
        for account: AccountDTO,
        amount: Double,
        currency: CurrencyCode,
        privacyMaskEnabled: Bool,
        forceCreditGlyph: Bool = false
    ) -> Source {
        let suffix = account.mask.map { privacyMaskEnabled ? " ••••" : " ••\($0)" } ?? ""
        let label = account.name + suffix
        let value = privacyMaskEnabled
            ? PrivacyMaskPresentation.compactValue
            : Formatters.currency(amount, in: currency, format: .compact)
        let spokenValue = privacyMaskEnabled
            ? "balance hidden while Privacy Mask is on"
            : "balance \(Formatters.currency(amount, in: currency, format: .full))"
        let glyph = forceCreditGlyph ? "creditcard" : account.type.provenanceGlyph
        return Source(
            id: id,
            label: label,
            value: value,
            systemImage: glyph,
            accessibilityLabel: "\(account.name), \(spokenValue)."
        )
    }

    private static func freshnessText(for freshness: Date?, now: Date) -> String {
        guard let freshness else { return "Not yet synced" }
        return "Updated \(Formatters.relativeDate(freshness))"
    }

    private static func signedCurrency(_ amount: Double) -> String {
        Formatters.signedCurrency(amount, format: .compact)
    }

    private static func signedSpokenCurrency(_ amount: Double) -> String {
        let magnitude = Formatters.currency(abs(amount), format: .full)
        if amount > 0 { return "plus \(magnitude)" }
        if amount < 0 { return "minus \(magnitude)" }
        return magnitude
    }
}

private extension AccountType {
    /// SF Symbol that pairs a shape with the source-row text so the account kind is
    /// distinguishable without relying on color (ACCESSIBILITY.md).
    var provenanceGlyph: String {
        switch self {
        case .depository: "banknote"
        case .credit: "creditcard"
        case .loan: "building.columns"
        case .investment: "chart.line.uptrend.xyaxis"
        case .other: "square.stack.3d.up"
        }
    }
}
