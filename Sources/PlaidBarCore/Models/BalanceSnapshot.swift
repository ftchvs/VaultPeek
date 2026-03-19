import Foundation

/// A point-in-time record of net balance for sparkline history
public struct BalanceSnapshot: Codable, Sendable {
    public let date: Date
    public let balance: Double

    public init(date: Date, balance: Double) {
        self.date = date
        self.balance = balance
    }
}
