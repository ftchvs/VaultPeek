import Foundation

public struct BalanceDTO: Codable, Sendable, Hashable {
    public let available: Double?
    public let current: Double?
    public let limit: Double?
    public let isoCurrencyCode: String?

    public init(
        available: Double? = nil,
        current: Double? = nil,
        limit: Double? = nil,
        isoCurrencyCode: String? = nil
    ) {
        self.available = available
        self.current = current
        self.limit = limit
        self.isoCurrencyCode = isoCurrencyCode
    }

    /// Effective balance: available if present, otherwise current
    public var effectiveBalance: Double {
        available ?? current ?? 0
    }

    /// Credit utilization percentage (0-100), nil if not a credit account
    public var utilizationPercent: Double? {
        guard let limit, limit > 0, let current else { return nil }
        return (abs(current) / limit) * 100
    }
}
