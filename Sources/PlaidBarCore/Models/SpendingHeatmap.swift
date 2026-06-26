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

/// Presentation for the heatmap's focused-day caption (AND-380). The same
/// composition backs the per-cell `.help()` / VoiceOver label and the inline
/// caption shown when a cell is selected, so both stay in lockstep.
public struct SpendingHeatmapFocusSummary: Sendable, Hashable {
    /// Localized day, e.g. "Jan 1, 2026".
    public let dateText: String
    /// Signed amount in the active mode, e.g. "$120.00" or "+$300.00".
    public let amountText: String
    /// Transaction count phrase, e.g. "3 transactions" / "1 transaction".
    public let transactionText: String
    /// Compact caption shown inline next to the date.
    public let captionText: String
    /// Full sentence for the cell's accessibility label / pointer help.
    public let accessibilityLabel: String

    public init(
        dateText: String,
        amountText: String,
        transactionText: String,
        captionText: String,
        accessibilityLabel: String
    ) {
        self.dateText = dateText
        self.amountText = amountText
        self.transactionText = transactionText
        self.captionText = captionText
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct SpendingHeatmapMonthMarker: Identifiable, Sendable, Hashable {
    public let id: String
    public let weekIndex: Int
    public let label: String

    public init(id: String, weekIndex: Int, label: String) {
        self.id = id
        self.weekIndex = weekIndex
        self.label = label
    }
}

/// One-pass derivation of everything a heatmap render needs. SwiftUI bodies
/// should compute this once per render instead of re-deriving days, peak,
/// totals, and week columns from separate computed properties — each of those
/// re-aggregated every transaction on every access.
public struct SpendingHeatmapLayout: Sendable {
    public let mode: SpendingHeatmapMode
    public let days: [SpendingHeatmapDay]
    /// Largest absolute day value, floored at 1 so intensity division is safe.
    public let peakValue: Double
    public let totalValue: Double
    public let activeDayCount: Int
    /// Days grouped into 7-row week columns, padded with nil so the first
    /// column aligns to the calendar's first weekday.
    public let weekColumns: [[SpendingHeatmapDay?]]
    /// First week column of each month (anchored on days 1-7), deduplicated.
    public let monthMarkers: [SpendingHeatmapMonthMarker]

    public static func compute(
        from transactions: [TransactionDTO],
        startDate: Date,
        endDate: Date,
        mode: SpendingHeatmapMode,
        calendar: Calendar = .current
    ) -> SpendingHeatmapLayout {
        let days = SpendingHeatmap.days(
            from: transactions,
            startDate: startDate,
            endDate: endDate,
            mode: mode,
            calendar: calendar
        )

        var peak = 0.0
        var total = 0.0
        var activeCount = 0
        for day in days {
            peak = max(peak, abs(day.value))
            total += day.value
            if day.transactionCount > 0 { activeCount += 1 }
        }

        let weekColumns = Self.weekColumns(from: days, calendar: calendar)

        return SpendingHeatmapLayout(
            mode: mode,
            days: days,
            peakValue: max(peak, 1),
            totalValue: total,
            activeDayCount: activeCount,
            weekColumns: weekColumns,
            monthMarkers: Self.monthMarkers(from: weekColumns, calendar: calendar)
        )
    }

    private static func weekColumns(
        from days: [SpendingHeatmapDay],
        calendar: Calendar
    ) -> [[SpendingHeatmapDay?]] {
        guard let firstDay = days.first,
              let firstDate = Formatters.parseTransactionDate(firstDay.date) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let padded: [SpendingHeatmapDay?] = Array(repeating: nil, count: leadingEmptyDays) + days.map(Optional.some)
        return stride(from: 0, to: padded.count, by: 7).map { start in
            let week = Array(padded[start ..< min(start + 7, padded.count)])
            return week + Array(repeating: nil, count: max(0, 7 - week.count))
        }
    }

    private static func monthMarkers(
        from weekColumns: [[SpendingHeatmapDay?]],
        calendar: Calendar
    ) -> [SpendingHeatmapMonthMarker] {
        var seenMonths = Set<String>()

        return weekColumns.enumerated().compactMap { weekIndex, week in
            for day in week.compactMap(\.self) {
                guard let date = Formatters.parseTransactionDate(day.date),
                      calendar.component(.day, from: date) <= 7
                else {
                    continue
                }

                let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
                guard !seenMonths.contains(monthKey) else { continue }
                seenMonths.insert(monthKey)

                return SpendingHeatmapMonthMarker(
                    id: "\(weekIndex)-\(day.date)",
                    weekIndex: weekIndex,
                    label: calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
                )
            }
            return nil
        }
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

    /// Signed, mode-aware amount string for a single day (e.g. "$120.00" for
    /// spend, "+$300.00" / "-$75.00" for net cashflow). Single source of truth
    /// for both the cell label and the focused-day caption.
    ///
    /// When `isPrivacyMasked` is `true` the whole amount token — sign prefix
    /// included — collapses to `••••` so a per-cell label/help never leaks the
    /// day's value while Privacy Mask is on (ACCESSIBILITY.md / SECURITY.md).
    public static func amountText(
        for day: SpendingHeatmapDay,
        mode: SpendingHeatmapMode,
        isPrivacyMasked: Bool = false
    ) -> String {
        guard !isPrivacyMasked else { return PrivacyMaskPresentation.compactValue }
        switch mode {
        case .spending:
            return Formatters.currency(day.value, format: .full)
        case .netCashflow:
            let displayAmount = displayCashflowAmount(day.value)
            let prefix = displayAmount > 0 ? "+" : displayAmount < 0 ? "-" : ""
            return "\(prefix)\(Formatters.currency(abs(displayAmount), format: .full))"
        }
    }

    /// Transaction-count phrase with correct pluralization.
    public static func transactionText(for day: SpendingHeatmapDay) -> String {
        "\(day.transactionCount) transaction\(day.transactionCount == 1 ? "" : "s")"
    }

    /// Full cell label / pointer-help sentence for a single day. The date and
    /// transaction count are always present; the amount honors `isPrivacyMasked`
    /// (shown as `••••` when masked) so the per-cell `.help`/`.accessibilityLabel`
    /// affordance carries the cell's meaning textually without leaking the value
    /// while Privacy Mask is on. Single source of truth for every heatmap surface.
    public static func cellLabel(
        for day: SpendingHeatmapDay,
        mode: SpendingHeatmapMode,
        isPrivacyMasked: Bool = false
    ) -> String {
        "\(Formatters.displayTransactionDate(day.date)): \(amountText(for: day, mode: mode, isPrivacyMasked: isPrivacyMasked)) across \(transactionText(for: day))"
    }

    /// Summary for the focused-day caption. Returns `nil` when nothing is
    /// selected (the caller shows the range total instead) or when the selected
    /// day key is not present in the layout (stale selection after a data or
    /// range change). Reuses the layout's already-derived `days`.
    public static func focusedDaySummary(
        for selectedDay: String?,
        in layout: SpendingHeatmapLayout
    ) -> SpendingHeatmapFocusSummary? {
        guard let selectedDay,
              let day = layout.days.first(where: { $0.date == selectedDay })
        else {
            return nil
        }

        let dateText = Formatters.displayTransactionDate(day.date)
        let amount = amountText(for: day, mode: layout.mode)
        let count = transactionText(for: day)
        return SpendingHeatmapFocusSummary(
            dateText: dateText,
            amountText: amount,
            transactionText: count,
            captionText: "\(dateText) · \(amount) · \(count)",
            accessibilityLabel: cellLabel(for: day, mode: layout.mode)
        )
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

        // Canonical yyyy-MM-dd keys sort lexicographically in date order, so the
        // range filter is a string comparison instead of a DateFormatter parse
        // per transaction. Non-canonical date strings never matched a bucket key
        // before either; they are excluded up front.
        let startKey = Formatters.transactionDateString(start)
        let endKey = Formatters.transactionDateString(end)

        var totals: [String: (value: Double, count: Int)] = [:]
        totals.reserveCapacity(min(transactions.count, 366))
        for transaction in transactions {
            let key = transaction.date
            guard Formatters.isCanonicalTransactionDateKey(key),
                  key >= startKey, key <= endKey,
                  !isTransfer(transaction) else { continue }

            let value: Double
            switch mode {
            case .spending:
                guard !transaction.isIncome else { continue }
                value = transaction.displayAmount
            case .netCashflow:
                value = transaction.amount
            }
            let entry = totals[key] ?? (0, 0)
            totals[key] = (entry.value + value, entry.count + 1)
        }

        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return (0...dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dateString = Formatters.transactionDateString(day)
            let entry = totals[dateString] ?? (0, 0)
            return SpendingHeatmapDay(
                date: dateString,
                value: entry.value,
                transactionCount: entry.count
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
