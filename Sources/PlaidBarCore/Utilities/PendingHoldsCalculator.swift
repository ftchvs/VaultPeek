import Foundation

/// Sums pending outflow holds on spendable cash accounts (AND-499).
///
/// A "pending hold" is money already authorized but not yet posted — a charge
/// Plaid reports with `pending == true` and a positive (money-out) amount.
/// Pure, Sendable, deterministic (no `Date()`).
///
/// IMPORTANT — double-subtraction risk: Plaid's `available` balance (used by
/// `SafeToSpendCalculator.startingCash` via `BalanceDTO.effectiveBalance`)
/// already nets *some* pending holds. Subtracting this total as a new
/// safe-to-spend component on top of an `available`-based starting cash would
/// double-count those holds. The total is only safe to subtract when starting
/// cash uses `current` (safe-to-spend model B). The calculator therefore takes
/// `pendingHolds` as an explicit caller-supplied parameter (default 0) rather
/// than computing it itself, so the headline number does not silently shift.
public enum PendingHoldsCalculator {
    /// Total absolute pending outflow hold amount for the included cash accounts.
    ///
    /// - Parameters:
    ///   - transactions: all known transactions.
    ///   - accounts: all accounts (used to resolve each transaction's account type).
    ///   - includedCashAccountTypes: account types treated as spendable cash.
    ///     Defaults to depository only, matching `SafeToSpendInputs`.
    /// - Returns: the summed absolute amount of pending outflows on those
    ///   accounts (>= 0). Posted transactions, inflows, own-account transfers,
    ///   and transactions on excluded accounts contribute nothing.
    public static func pendingHolds(
        from transactions: [TransactionDTO],
        accounts: [AccountDTO],
        includedCashAccountTypes: Set<AccountType> = [.depository]
    ) -> Double {
        // Resolve which account ids are spendable cash.
        let cashAccountIDs = Set(
            accounts
                .filter { includedCashAccountTypes.contains($0.type) }
                .map(\.id)
        )

        return transactions.reduce(0) { total, transaction in
            guard transaction.pending,
                  cashAccountIDs.contains(transaction.accountId),
                  isOutflowHold(transaction)
            else { return total }
            return total + transaction.displayAmount
        }
    }

    /// Whether a pending transaction is a real outflow hold (not an inflow or an
    /// own-account transfer). Mirrors `SafeToSpendCalculator.isOutflowObligation`.
    static func isOutflowHold(_ transaction: TransactionDTO) -> Bool {
        // Plaid: positive amount = money out. A pending credit/refund is an
        // inflow and must not reduce spendable cash.
        guard transaction.amount > 0 else { return false }
        switch transaction.category {
        case .income, .transfer, .transferOut:
            return false
        default:
            return true
        }
    }
}
