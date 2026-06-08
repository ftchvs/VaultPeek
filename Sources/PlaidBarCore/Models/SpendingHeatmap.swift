import Foundation

public enum SpendingHeatmapMode: String, Codable, CaseIterable, Sendable {
    case spending
    case netCashflow

    public var shortLabel: String {
        switch self {
        case .spending:
            "Spend"
        case .netCashflow:
            "Cashflow"
        }
    }

    public var summaryTitle: String {
        switch self {
        case .spending:
            "365D Spend"
        case .netCashflow:
            "365D Net Cashflow"
        }
    }

    public var semanticDescription: String {
        switch self {
        case .spending:
            "Outflows only; income and transfers are excluded"
        case .netCashflow:
            "Income minus outflows; transfers are excluded"
        }
    }
}

public struct SpendingHeatmapDay: Identifiable, Sendable, Hashable {
    public let date: String
    public let value: Double
    public let transactionCount: Int

    public var id: String { date }

    public init(date: String, value: Double, transactionCount: Int) {
        self.date = date
        self.value = value
        self.transactionCount = transactionCount
    }
}

public struct SpendingHeatmapSignal: Identifiable, Sendable, Hashable {
    public let day: SpendingHeatmapDay
    public let rank: Int
    public let label: String
    public let amountText: String
    public let accessibilitySummary: String

    public var id: String { "\(rank)-\(day.date)" }

    public init(day: SpendingHeatmapDay, rank: Int, label: String, amountText: String, accessibilitySummary: String) {
        self.day = day
        self.rank = rank
        self.label = label
        self.amountText = amountText
        self.accessibilitySummary = accessibilitySummary
    }
}

public struct SpendingHeatmapEmptyPresentation: Sendable, Hashable {
    public let title: String
    public let systemImage: String
    public let description: String

    public init(title: String, systemImage: String, description: String) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
}

public enum SpendingHeatmap {
    public static func displayCashflowAmount(_ value: Double) -> Double {
        -value
    }

    public static func emptyPresentation(transactionCount: Int, mode: SpendingHeatmapMode) -> SpendingHeatmapEmptyPresentation {
        guard transactionCount > 0 else {
            return SpendingHeatmapEmptyPresentation(
                title: "No Heatmap Data",
                systemImage: "calendar.badge.exclamationmark",
                description: "Daily activity will appear after syncing transactions."
            )
        }

        switch mode {
        case .spending:
            return SpendingHeatmapEmptyPresentation(
                title: "No Spending in This View",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "Transactions exist for this range, but none count as spend after filters, income, and transfers are excluded."
            )
        case .netCashflow:
            return SpendingHeatmapEmptyPresentation(
                title: "No Cashflow in This View",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "Transactions exist for this range, but none count toward net cashflow after filters and transfers are excluded."
            )
        }
    }

    public static func cellIntensity(for day: SpendingHeatmapDay, peakValue: Double) -> Double {
        guard day.transactionCount > 0, peakValue > 0 else { return 0 }
        return min(max(abs(day.value) / peakValue, 0), 1)
    }

    public static func days(
        from transactions: [TransactionDTO],
        startDate: Date,
        endDate: Date,
        mode: SpendingHeatmapMode,
        calendar: Calendar = .current
    ) -> [SpendingHeatmapDay] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [] }

        let relevant = transactions.compactMap { transaction -> (String, Double)? in
            guard let date = Formatters.parseTransactionDate(transaction.date) else { return nil }
            let day = calendar.startOfDay(for: date)
            guard day >= start && day <= end else { return nil }
            guard !isTransfer(transaction) else { return nil }

            switch mode {
            case .spending:
                guard !transaction.isIncome else { return nil }
                return (transaction.date, transaction.displayAmount)
            case .netCashflow:
                return (transaction.date, transaction.amount)
            }
        }

        let grouped = Dictionary(grouping: relevant) { $0.0 }
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return (0...dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dateString = Formatters.transactionDateString(day)
            let entries = grouped[dateString] ?? []
            return SpendingHeatmapDay(
                date: dateString,
                value: entries.reduce(0) { $0 + $1.1 },
                transactionCount: entries.count
            )
        }
    }

    public static func strongestSignals(
        from days: [SpendingHeatmapDay],
        mode: SpendingHeatmapMode,
        limit: Int = 2
    ) -> [SpendingHeatmapSignal] {
        guard limit > 0 else { return [] }

        let candidates = days
            .filter { $0.transactionCount > 0 && abs($0.value) > 0 }

        let rankedDays: [SpendingHeatmapDay]
        switch mode {
        case .spending:
            rankedDays = ranked(candidates)
        case .netCashflow:
            let strongestIncome = ranked(candidates.filter { displayCashflowAmount($0.value) >= 0 }).first
            let strongestOutflow = ranked(candidates.filter { displayCashflowAmount($0.value) < 0 }).first
            rankedDays = ranked([strongestIncome, strongestOutflow].compactMap(\.self))
        }

        return rankedDays
            .prefix(limit)
            .enumerated()
            .map { offset, day in
                signal(for: day, mode: mode, rank: offset + 1)
            }
    }

    private static func ranked(_ days: [SpendingHeatmapDay]) -> [SpendingHeatmapDay] {
        days
            .sorted { lhs, rhs in
                let lhsMagnitude = abs(lhs.value)
                let rhsMagnitude = abs(rhs.value)
                if lhsMagnitude == rhsMagnitude {
                    return lhs.date > rhs.date
                }
                return lhsMagnitude > rhsMagnitude
            }
    }

    private static func isTransfer(_ transaction: TransactionDTO) -> Bool {
        transaction.category == .transfer || transaction.category == .transferOut
    }

    private static func signal(for day: SpendingHeatmapDay, mode: SpendingHeatmapMode, rank: Int) -> SpendingHeatmapSignal {
        let dateText = Formatters.displayTransactionDate(day.date)
        let transactionText = "\(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"

        switch mode {
        case .spending:
            let amountText = Formatters.currency(day.value, format: .full)
            return SpendingHeatmapSignal(
                day: day,
                rank: rank,
                label: rank == 1 ? "Highest spend" : "Next highest spend",
                amountText: amountText,
                accessibilitySummary: "\(rank == 1 ? "Highest" : "Next highest") spend was \(amountText) on \(dateText) across \(transactionText)."
            )
        case .netCashflow:
            let displayAmount = displayCashflowAmount(day.value)
            let direction = displayAmount >= 0 ? "income" : "outflow"
            let amountText = Formatters.currency(abs(displayAmount), format: .full)
            return SpendingHeatmapSignal(
                day: day,
                rank: rank,
                label: rank == 1 ? "Strongest \(direction)" : "Next strongest \(direction)",
                amountText: amountText,
                accessibilitySummary: "\(rank == 1 ? "Strongest" : "Next strongest") \(direction) was \(amountText) on \(dateText) across \(transactionText)."
            )
        }
    }
}
