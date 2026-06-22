import Foundation

/// A smarter sub-classification for *income* (money-in) transactions (priority
/// #5).
///
/// Plaid collapses every inflow into a single `INCOME` primary, so the app cannot
/// tell salary from a refund from interest. This enum is the income analogue of
/// `SpendingCategory`: a small, fixed taxonomy the on-device tiers can suggest and
/// the user can confirm. Like every AI tier in VaultPeek it is *display/review*
/// only — it never re-writes the raw Plaid category and never silently becomes
/// budget spend (income is not spend at all).
///
/// `Sendable`/`Codable` so it can be persisted alongside review metadata and
/// crossed across the app→server boundary if ever needed.
public enum IncomeCategory: String, Codable, Sendable, CaseIterable, Hashable {
    /// Regular employment pay (paycheck, payroll, direct deposit wages).
    case salary = "SALARY"
    /// Interest earned (savings, checking APY, CDs).
    case interest = "INTEREST"
    /// Investment distributions (dividends, capital gains).
    case dividend = "DIVIDEND"
    /// A merchant/vendor refund or return credit.
    case refund = "REFUND"
    /// A reimbursement (expense report, peer payback).
    case reimbursement = "REIMBURSEMENT"
    /// Government payments (tax refund, benefits, stimulus).
    case government = "GOVERNMENT"
    /// Any other income that doesn't fit the cases above — the honest fallback.
    case otherIncome = "OTHER_INCOME"

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .salary: "Salary"
        case .interest: "Interest"
        case .dividend: "Dividend"
        case .refund: "Refund"
        case .reimbursement: "Reimbursement"
        case .government: "Government"
        case .otherIncome: "Other Income"
        }
    }

    /// SF Symbol name for the income subtype icon. Color is never the sole channel
    /// (ACCESSIBILITY.md): every subtype carries a distinct glyph + label.
    public var iconName: String {
        switch self {
        case .salary: "banknote.fill"
        case .interest: "percent"
        case .dividend: "chart.line.uptrend.xyaxis"
        case .refund: "arrow.uturn.backward.circle.fill"
        case .reimbursement: "arrow.left.arrow.right.circle.fill"
        case .government: "building.columns.fill"
        case .otherIncome: "arrow.down.circle.fill"
        }
    }
}
