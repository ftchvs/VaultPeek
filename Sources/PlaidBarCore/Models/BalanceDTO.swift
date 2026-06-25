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

    /// Normalized currency identity for this balance. Wraps the raw Plaid
    /// `iso_currency_code`; an absent/empty code resolves to
    /// ``CurrencyCode/unknown`` (never silently assumed to be USD).
    public var currency: CurrencyCode {
        CurrencyCode(isoCurrencyCode)
    }

    /// Credit utilization percentage (0-100), nil if not a credit account
    public var utilizationPercent: Double? {
        guard let limit, limit > 0, let current else { return nil }
        return (abs(current) / limit) * 100
    }
}
