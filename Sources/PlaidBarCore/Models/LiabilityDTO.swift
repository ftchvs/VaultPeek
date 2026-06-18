import Foundation

/// A credit-card liability snapshot from Plaid `/liabilities/get`, reduced to
/// the decision-grade fields VaultPeek surfaces next to a card: purchase APR,
/// statement balance, minimum payment, and the next due date. This is a glance,
/// never a bill-pay workflow (explicit non-goal).
///
/// Populated only for items linked with the `liabilities` product (new links);
/// items without the scope simply have no `LiabilityDTO`, and the UI keeps its
/// honest utilization-only view.
public struct LiabilityDTO: Codable, Sendable, Equatable, Identifiable {
    public let accountId: String
    /// Purchase APR percentage (e.g. `24.99`), taken from Plaid's `aprs` entry
    /// where `apr_type == "purchase_apr"`. Nil when the issuer omits APR data
    /// (Plaid returns an empty `aprs` array in that case).
    public let purchaseAprPercentage: Double?
    public let lastStatementBalance: Double?
    /// Statement issue date, `YYYY-MM-DD`.
    public let lastStatementIssueDate: String?
    public let minimumPaymentAmount: Double?
    /// Next payment due date, `YYYY-MM-DD`.
    public let nextPaymentDueDate: String?
    public let lastPaymentAmount: Double?
    /// Last payment date, `YYYY-MM-DD`.
    public let lastPaymentDate: String?
    public let isOverdue: Bool

    public var id: String { accountId }

    public init(
        accountId: String,
        purchaseAprPercentage: Double? = nil,
        lastStatementBalance: Double? = nil,
        lastStatementIssueDate: String? = nil,
        minimumPaymentAmount: Double? = nil,
        nextPaymentDueDate: String? = nil,
        lastPaymentAmount: Double? = nil,
        lastPaymentDate: String? = nil,
        isOverdue: Bool = false
    ) {
        self.accountId = accountId
        self.purchaseAprPercentage = purchaseAprPercentage
        self.lastStatementBalance = lastStatementBalance
        self.lastStatementIssueDate = lastStatementIssueDate
        self.minimumPaymentAmount = minimumPaymentAmount
        self.nextPaymentDueDate = nextPaymentDueDate
        self.lastPaymentAmount = lastPaymentAmount
        self.lastPaymentDate = lastPaymentDate
        self.isOverdue = isOverdue
    }
}
