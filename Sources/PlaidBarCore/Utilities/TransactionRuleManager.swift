import Foundation

/// Pure, `Sendable` presentation + conflict logic for the rules-manager surface
/// (AND-551, DEFERRED v2 / AND-524).
///
/// `TransactionRule`s are create-only inline in v1 (the Review Inbox's
/// `createRule` / `InlineCategoryRulePrompt` path). This type is the pure half of
/// the management surface: it turns the flat rule array into sorted, human-readable
/// rows; describes each rule's *match* and *effect* in text (never color alone);
/// detects and explains conflicts between rules; and resolves which rule actually
/// governed a transaction (provenance). The app target's `RulesSettingsView` is a
/// thin renderer over these decisions, and `AppState` owns the store mutations —
/// so the meaning of "which rule wins" is defined in exactly one place and is
/// unit-testable without the SwiftUI app target (CLAUDE.md).
///
/// ## Conflict-resolution doctrine (AC #4)
/// When two rules both match a transaction and both set the *same* field
/// (category, transfer, or budget exclusion), only one can win. The winner is the
/// **most recently created** rule (`createdAt` descending; `id.uuidString` as the
/// deterministic tiebreaker for equal timestamps). This is the *exact* precedence
/// `EffectiveCategoryResolver.resolve` already applies to spend math — surfaced
/// verbatim here so the UI's "this rule wins" explanation can never drift from what
/// actually happens to a user's budgets. The losing rule is not deleted or hidden;
/// it is flagged as *shadowed* on the conflicting field so the user can see and
/// resolve it.
///
/// Privacy: every string this type produces is a rule's own matcher / category /
/// effect text — never a balance, amount, account id, or transaction id. The view
/// still suppresses the whole surface under Privacy Mask / App Lock as defense in
/// depth, but nothing here is sensitive on its own.
public enum TransactionRuleManager {
    // MARK: - Sort

    /// The canonical management ordering: newest-first by `createdAt`, with
    /// `id.uuidString` as the deterministic tiebreaker. This mirrors the precedence
    /// `EffectiveCategoryResolver` resolves by, so the first rule in the list is
    /// also the highest-precedence one — "top of the list wins" reads true.
    public static func sortedForDisplay(_ rules: [TransactionRule]) -> [TransactionRule] {
        rules.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    // MARK: - Effect description (AC #1)

    /// The fields a rule can affect. Order matches how `RuleRow.effects` lists them.
    public enum Effect: Sendable, Equatable {
        /// Recategorize matches to a fixed category.
        case category(SpendingCategory)
        /// Rename the merchant shown for matches.
        case merchant(String)
        /// Mark matches as transfers (own-account moves).
        case transfer(Bool)
        /// Exclude matches from budget aggregation.
        case excludeFromBudgets(Bool)

        /// Text+icon label for the effect chip — meaning is always carried by the
        /// text, never by the icon or any color (ACCESSIBILITY.md).
        public var label: String {
            switch self {
            case .category(let category): "Categorize as \(category.displayName)"
            case .merchant(let name): "Rename to \(name)"
            case .transfer(let isTransfer): isTransfer ? "Mark as transfer" : "Not a transfer"
            case .excludeFromBudgets(let excluded): excluded ? "Exclude from budgets" : "Include in budgets"
            }
        }

        /// SF Symbol for the chip (chrome only — the `label` always accompanies it).
        public var systemImage: String {
            switch self {
            case .category(let category): category.iconName
            case .merchant: "character.cursor.ibeam"
            case .transfer: "arrow.left.arrow.right"
            case .excludeFromBudgets: "minus.circle"
            }
        }
    }

    /// The effects a single rule applies, in a stable display order. A rule that
    /// sets no field (degenerate, e.g. carried forward from older data) yields an
    /// empty array — the row then reads "No effect" so it is visible and deletable
    /// rather than silently dead.
    public static func effects(of rule: TransactionRule) -> [Effect] {
        var result: [Effect] = []
        if let category = rule.category { result.append(.category(category)) }
        if let merchant = rule.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !merchant.isEmpty {
            result.append(.merchant(merchant))
        }
        if let isTransfer = rule.isTransfer { result.append(.transfer(isTransfer)) }
        if let excluded = rule.excludedFromBudgets { result.append(.excludeFromBudgets(excluded)) }
        return result
    }

    /// Human-readable description of what a rule *matches on*. Mirrors
    /// `TransactionRule.matches`: a merchant-contains token OR an original-name
    /// token (case-insensitive). Returns a non-empty sentence even for a degenerate
    /// rule so the row is never blank.
    public static func matchDescription(of rule: TransactionRule) -> String {
        var clauses: [String] = []
        if let merchant = trimmedNonEmpty(rule.matchMerchantContains) {
            clauses.append("merchant contains “\(merchant)”")
        }
        if let original = trimmedNonEmpty(rule.matchOriginalNameContains) {
            clauses.append("description contains “\(original)”")
        }
        guard !clauses.isEmpty else { return "Matches nothing (no match text)" }
        // The matcher is OR-combined in `TransactionRule.matches`, so describe it
        // that way.
        return "When " + clauses.joined(separator: " or ")
    }

    // MARK: - Rows (AC #1, #4)

    /// A presentation row for one rule: the rule itself, its sorted display index,
    /// its match/effect text, and any per-field shadowing caused by a
    /// higher-precedence rule (AC #4). The view renders this directly.
    public struct RuleRow: Sendable, Equatable, Identifiable {
        public var id: UUID { rule.id }
        public let rule: TransactionRule
        public let matchDescription: String
        public let effects: [Effect]
        /// Conflicts where *another* rule out-ranks this one on a shared field, so
        /// this rule's value for that field never takes effect. Empty when the rule
        /// is fully effective. Drives the row's "shadowed" warning.
        public let shadowedFields: [FieldConflict]

        public init(
            rule: TransactionRule,
            matchDescription: String,
            effects: [Effect],
            shadowedFields: [FieldConflict]
        ) {
            self.rule = rule
            self.matchDescription = matchDescription
            self.effects = effects
            self.shadowedFields = shadowedFields
        }

        /// Whether at least one of this rule's effects is overridden by a
        /// higher-precedence rule.
        public var isShadowed: Bool { !shadowedFields.isEmpty }
    }

    /// One field on which a lower-precedence rule is overridden by a winning rule.
    public struct FieldConflict: Sendable, Equatable, Identifiable {
        public enum Field: String, Sendable, Equatable {
            case category
            case transfer
            case excludeFromBudgets

            public var displayName: String {
                switch self {
                case .category: "Category"
                case .transfer: "Transfer"
                case .excludeFromBudgets: "Budget exclusion"
                }
            }
        }

        /// The field both rules try to set.
        public let field: Field
        /// The id of the rule that wins this field (most recently created).
        public let winningRuleID: UUID
        /// A short, privacy-safe label for the winning rule (its match text) so the
        /// UI can say "overridden by the ‘Starbucks’ rule" without re-deriving it.
        public let winningRuleLabel: String

        public var id: String { "\(field.rawValue):\(winningRuleID.uuidString)" }

        public init(field: Field, winningRuleID: UUID, winningRuleLabel: String) {
            self.field = field
            self.winningRuleID = winningRuleID
            self.winningRuleLabel = winningRuleLabel
        }
    }

    /// Build the full set of display rows in management order, each annotated with
    /// any fields a higher-precedence overlapping rule shadows (AC #1 + #4).
    ///
    /// Two rules *overlap* when some transaction could match both — approximated
    /// here, with no transactions in hand, by token containment between their
    /// matchers (one matcher's token is a case-insensitive substring of the
    /// other's, on the same axis). This is intentionally conservative: it catches
    /// the real-world case (two "Amazon" rules, or "Amazon" vs "Amazon Prime") that
    /// the spec calls out, without claiming certainty it can't have without the
    /// transaction set. For a *given* transaction the exact winner is always
    /// available via ``provenance(for:in:)``.
    public static func rows(for rules: [TransactionRule]) -> [RuleRow] {
        let ordered = sortedForDisplay(rules)
        return ordered.map { rule in
            RuleRow(
                rule: rule,
                matchDescription: matchDescription(of: rule),
                effects: effects(of: rule),
                shadowedFields: shadowedFields(for: rule, among: ordered)
            )
        }
    }

    /// The fields on which `rule` is overridden by a higher-precedence overlapping
    /// rule. `ordered` must be `sortedForDisplay` output (newest-first), so any rule
    /// *before* `rule` in it out-ranks `rule`.
    private static func shadowedFields(
        for rule: TransactionRule,
        among ordered: [TransactionRule]
    ) -> [FieldConflict] {
        guard let index = ordered.firstIndex(where: { $0.id == rule.id }) else { return [] }
        let higherPrecedence = ordered[..<index]
        var conflicts: [FieldConflict] = []

        func firstWinner(where setsField: (TransactionRule) -> Bool) -> TransactionRule? {
            higherPrecedence.first { setsField($0) && overlaps(rule, $0) }
        }

        if rule.category != nil, let winner = firstWinner(where: { $0.category != nil }) {
            conflicts.append(FieldConflict(
                field: .category,
                winningRuleID: winner.id,
                winningRuleLabel: shortLabel(for: winner)
            ))
        }
        if rule.isTransfer != nil, let winner = firstWinner(where: { $0.isTransfer != nil }) {
            conflicts.append(FieldConflict(
                field: .transfer,
                winningRuleID: winner.id,
                winningRuleLabel: shortLabel(for: winner)
            ))
        }
        if rule.excludedFromBudgets != nil,
           let winner = firstWinner(where: { $0.excludedFromBudgets != nil }) {
            conflicts.append(FieldConflict(
                field: .excludeFromBudgets,
                winningRuleID: winner.id,
                winningRuleLabel: shortLabel(for: winner)
            ))
        }
        return conflicts
    }

    /// Whether two rules could plausibly match the same transaction, judged by
    /// token containment on a shared matcher axis (merchant or original-name).
    /// Conservative by design (see ``rows(for:)``).
    static func overlaps(_ lhs: TransactionRule, _ rhs: TransactionRule) -> Bool {
        if tokensOverlap(lhs.matchMerchantContains, rhs.matchMerchantContains) { return true }
        if tokensOverlap(lhs.matchOriginalNameContains, rhs.matchOriginalNameContains) { return true }
        return false
    }

    private static func tokensOverlap(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = trimmedNonEmpty(lhs), let rhs = trimmedNonEmpty(rhs) else { return false }
        return lhs.localizedCaseInsensitiveContains(rhs) || rhs.localizedCaseInsensitiveContains(lhs)
    }

    // MARK: - Provenance (AC #3)

    /// Per-field provenance: which rule supplied the *effective* value of each
    /// field for a given transaction, applying the real precedence. Exactly the
    /// rule a user would point to and say "this is why my transaction is
    /// categorized this way". `nil` for a field means no matching rule set it (the
    /// value came from the user override or Plaid, not a rule).
    public struct Provenance: Sendable, Equatable {
        /// All rules that match the transaction, in precedence order (winner first).
        public let matchingRules: [TransactionRule]
        public let categoryRuleID: UUID?
        public let transferRuleID: UUID?
        public let excludeRuleID: UUID?

        public init(
            matchingRules: [TransactionRule],
            categoryRuleID: UUID?,
            transferRuleID: UUID?,
            excludeRuleID: UUID?
        ) {
            self.matchingRules = matchingRules
            self.categoryRuleID = categoryRuleID
            self.transferRuleID = transferRuleID
            self.excludeRuleID = excludeRuleID
        }

        /// Whether any rule matched the transaction at all.
        public var hasMatch: Bool { !matchingRules.isEmpty }
    }

    /// Resolve which rule governs each field of `transaction`, using the same
    /// newest-wins precedence as spend math (AC #3). The winning rule for a field
    /// is the most-recently-created matching rule that sets that field — identical
    /// to `EffectiveCategoryResolver.firstRuleValue` over the same sort.
    public static func provenance(
        for transaction: TransactionDTO,
        in rules: [TransactionRule]
    ) -> Provenance {
        let matching = sortedForDisplay(rules.filter { $0.matches(transaction) })
        return Provenance(
            matchingRules: matching,
            categoryRuleID: matching.first(where: { $0.category != nil })?.id,
            transferRuleID: matching.first(where: { $0.isTransfer != nil })?.id,
            excludeRuleID: matching.first(where: { $0.excludedFromBudgets != nil })?.id
        )
    }

    // MARK: - Editing (AC #2)

    /// Validate an edited rule before it is committed to the store. A rule must
    /// have at least one non-empty matcher (otherwise it matches nothing) and at
    /// least one effect (otherwise it does nothing). Returns the list of problems;
    /// empty means valid.
    public enum ValidationProblem: String, Sendable, Equatable {
        case noMatcher
        case noEffect

        public var message: String {
            switch self {
            case .noMatcher: "Add match text (a merchant or description fragment) so the rule can match transactions."
            case .noEffect: "Choose at least one effect (category, rename, transfer, or budget exclusion)."
            }
        }
    }

    public static func validate(_ rule: TransactionRule) -> [ValidationProblem] {
        var problems: [ValidationProblem] = []
        let hasMatcher = trimmedNonEmpty(rule.matchMerchantContains) != nil
            || trimmedNonEmpty(rule.matchOriginalNameContains) != nil
        if !hasMatcher { problems.append(.noMatcher) }
        if effects(of: rule).isEmpty { problems.append(.noEffect) }
        return problems
    }

    /// Apply an edit to a rule in `rules`, returning the new array. The edited
    /// rule's `id` and `createdAt` are preserved (identity + precedence are stable
    /// across an edit — editing must not silently re-rank a rule), and matcher /
    /// effect fields are normalized (trimmed; empty → nil) so the stored rule and
    /// what the user sees can't drift. A rule whose `id` is not present is appended,
    /// supporting "edit or add" from one path. Returns `rules` unchanged when the
    /// edit fails validation, with the problems surfaced separately by the caller.
    public static func applyingEdit(
        _ edited: TransactionRule,
        to rules: [TransactionRule]
    ) -> [TransactionRule] {
        let normalized = normalized(edited)
        var result = rules
        if let index = result.firstIndex(where: { $0.id == normalized.id }) {
            // Preserve the original creation time so an edit never silently changes
            // the rule's precedence relative to its peers.
            var carried = normalized
            carried = TransactionRule(
                id: result[index].id,
                matchMerchantContains: normalized.matchMerchantContains,
                matchOriginalNameContains: normalized.matchOriginalNameContains,
                category: normalized.category,
                merchantName: normalized.merchantName,
                isTransfer: normalized.isTransfer,
                excludedFromBudgets: normalized.excludedFromBudgets,
                createdAt: result[index].createdAt
            )
            result[index] = carried
        } else {
            result.append(normalized)
        }
        return result
    }

    /// Remove the rule with `id`. Deleting a rule must NOT retroactively
    /// un-review past transactions (AC #2): this only drops the rule from the
    /// matcher set, so already-`.reviewed` transaction metadata is untouched. The
    /// caller (`AppState`) deliberately does not mutate review metadata here.
    public static func deleting(
        ruleID id: UUID,
        from rules: [TransactionRule]
    ) -> [TransactionRule] {
        rules.filter { $0.id != id }
    }

    /// Normalize a rule's free-text fields: trim whitespace and collapse empty
    /// strings to `nil`, so a matcher of `"  "` becomes "no matcher" (caught by
    /// validation) rather than an always-failing match, and a blank rename clears
    /// rather than renaming to empty.
    public static func normalized(_ rule: TransactionRule) -> TransactionRule {
        TransactionRule(
            id: rule.id,
            matchMerchantContains: trimmedNonEmpty(rule.matchMerchantContains),
            matchOriginalNameContains: trimmedNonEmpty(rule.matchOriginalNameContains),
            category: rule.category,
            merchantName: trimmedNonEmpty(rule.merchantName),
            isTransfer: rule.isTransfer,
            excludedFromBudgets: rule.excludedFromBudgets,
            createdAt: rule.createdAt
        )
    }

    // MARK: - Helpers

    /// A short, privacy-safe label for a rule — its merchant matcher, else its
    /// original-name matcher, else a stable fallback. Used in conflict copy.
    public static func shortLabel(for rule: TransactionRule) -> String {
        trimmedNonEmpty(rule.matchMerchantContains)
            ?? trimmedNonEmpty(rule.matchOriginalNameContains)
            ?? trimmedNonEmpty(rule.merchantName)
            ?? "rule"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
