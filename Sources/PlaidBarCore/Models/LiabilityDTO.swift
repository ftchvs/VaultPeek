import Foundation

/// The decision-grade credit-card liability facts VaultPeek renders next to a
/// card: purchase APR and the next due date (plus overdue state). Deliberately
/// minimal — statement balance, minimum payment, and last-payment details stay
/// server-side (Plaid `/liabilities/get`) until a privacy-masked detail surface
/// exists, so balance-like values are not shipped into the SwiftUI app early.
///
/// Populated only for items linked with the `liabilities` product (new links);
/// items without the scope have no `LiabilityDTO` and keep the honest
/// utilization-only view.
public struct LiabilityDTO: Codable, Sendable, Equatable, Identifiable {
    public let accountId: String
    /// Purchase APR percentage (e.g. `24.99`), taken from Plaid's `aprs` entry
    /// where `apr_type == "purchase_apr"`. Nil when the issuer omits APR data.
    public let purchaseAprPercentage: Double?
    /// Next payment due date, `YYYY-MM-DD`.
    public let nextPaymentDueDate: String?
    public let isOverdue: Bool

    public var id: String { accountId }

    public init(
        accountId: String,
        purchaseAprPercentage: Double? = nil,
        nextPaymentDueDate: String? = nil,
        isOverdue: Bool = false
    ) {
        self.accountId = accountId
        self.purchaseAprPercentage = purchaseAprPercentage
        self.nextPaymentDueDate = nextPaymentDueDate
        self.isOverdue = isOverdue
    }
}
