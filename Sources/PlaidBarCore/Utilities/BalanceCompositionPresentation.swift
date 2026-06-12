import Foundation

public struct BalanceCompositionPresentation: Sendable, Equatable {
    public struct Segment: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let value: Double
        public let share: Double

        public init(id: String, title: String, value: Double, share: Double) {
            self.id = id
            self.title = title
            self.value = value
            self.share = share
        }
    }

    public let segments: [Segment]
    public let accountCount: Int
    public let total: Double

    public init(accounts: [AccountDTO]) {
        let rawSegments: [(id: String, title: String, value: Double)] = [
            (
                id: "cash",
                title: "Cash",
                value: AccountPresentation.positiveBalanceTotal(from: accounts, type: .depository)
            ),
            (
                id: "investments",
                title: "Investments",
                value: AccountPresentation.positiveBalanceTotal(from: accounts, type: .investment)
            ),
            (
                id: "credit",
                title: "Credit",
                value: AccountPresentation.debtBalanceTotal(from: accounts, type: .credit)
            ),
            (
                id: "loans",
                title: "Loans",
                value: AccountPresentation.debtBalanceTotal(from: accounts, type: .loan)
            ),
        ]

        let activeValues = rawSegments.filter { $0.value > 0 }
        let total = activeValues.reduce(0) { $0 + $1.value }
        let denominator = max(total, 1)

        self.segments = activeValues.map { raw in
            Segment(
                id: raw.id,
                title: raw.title,
                value: raw.value,
                share: raw.value / denominator
            )
        }
        self.accountCount = accounts.count
        self.total = total
    }
}
