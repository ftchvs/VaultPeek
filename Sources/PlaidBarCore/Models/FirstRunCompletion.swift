import Foundation

public enum FirstRunCompletionStep: String, Codable, Sendable {
    case openPlaidLink
    case loadAccounts
    case syncTransactions
    case ready
    case blocked
}

public struct FirstRunCompletionState: Equatable, Sendable {
    public let step: FirstRunCompletionStep
    public let title: String
    public let detail: String
    public let isReady: Bool
    public let canRetry: Bool

    public init(
        step: FirstRunCompletionStep,
        title: String,
        detail: String,
        isReady: Bool,
        canRetry: Bool
    ) {
        self.step = step
        self.title = title
        self.detail = detail
        self.isReady = isReady
        self.canRetry = canRetry
    }

    public static func evaluate(
        isDemoMode: Bool,
        serverConnected: Bool,
        linkedItemCount: Int,
        accountCount: Int,
        transactionCount: Int,
        syncedItemCount: Int,
        errorMessage: String?
    ) -> FirstRunCompletionState {
        if isDemoMode {
            return FirstRunCompletionState(
                step: .ready,
                title: "Demo ready",
                detail: "Local demo accounts and transactions are loaded.",
                isReady: true,
                canRetry: false
            )
        }

        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FirstRunCompletionState(
                step: .blocked,
                title: "Connection needs attention",
                detail: errorMessage,
                isReady: false,
                canRetry: true
            )
        }

        guard serverConnected else {
            return FirstRunCompletionState(
                step: .blocked,
                title: "Server offline",
                detail: "Start PlaidBarServer, then check the connection again.",
                isReady: false,
                canRetry: true
            )
        }

        guard linkedItemCount > 0 else {
            return FirstRunCompletionState(
                step: .openPlaidLink,
                title: "Waiting for Plaid Link",
                detail: "Complete the bank connection in your browser, then check again.",
                isReady: false,
                canRetry: true
            )
        }

        guard accountCount > 0 else {
            return FirstRunCompletionState(
                step: .loadAccounts,
                title: "Linked item found",
                detail: "PlaidBar can see the linked item. Load accounts to finish the first run.",
                isReady: false,
                canRetry: true
            )
        }

        guard syncedItemCount >= linkedItemCount else {
            return FirstRunCompletionState(
                step: .syncTransactions,
                title: "Accounts loaded",
                detail: transactionCount > 0
                    ? "\(syncedItemCount) of \(linkedItemCount) linked item\(linkedItemCount == 1 ? "" : "s") synced. Run one more check to finish setup."
                    : "Run the first transaction sync check to finish setup.",
                isReady: false,
                canRetry: true
            )
        }

        return FirstRunCompletionState(
            step: .ready,
            title: "Dashboard ready",
            detail: transactionCount == 1
                ? "1 transaction synced. PlaidBar is ready."
                : "\(transactionCount) transactions synced. PlaidBar is ready.",
            isReady: true,
            canRetry: false
        )
    }
}
