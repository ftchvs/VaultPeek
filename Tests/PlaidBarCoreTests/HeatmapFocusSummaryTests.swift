import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Heatmap Focused Day Summary")
struct HeatmapFocusSummaryTests {
    private func layout(mode: SpendingHeatmapMode) -> SpendingHeatmapLayout {
        let days = [
            SpendingHeatmapDay(date: "2026-01-01", value: 120, transactionCount: 3),
            SpendingHeatmapDay(date: "2026-01-02", value: -300, transactionCount: 1),
            SpendingHeatmapDay(date: "2026-01-03", value: 0, transactionCount: 0),
        ]
        var peak = 0.0
        var total = 0.0
        var active = 0
        for day in days {
            peak = max(peak, abs(day.value))
            total += day.value
            if day.transactionCount > 0 { active += 1 }
        }
        return SpendingHeatmapLayout(
            mode: mode,
            days: days,
            peakValue: max(peak, 1),
            totalValue: total,
            activeDayCount: active,
            weekColumns: [days.map(Optional.some)],
            monthMarkers: []
        )
    }

    @Test("Selected spend day summarizes that day's amount and count")
    func selectedSpendDaySummary() {
        let summary = SpendingHeatmap.focusedDaySummary(for: "2026-01-01", in: layout(mode: .spending))

        #expect(summary != nil)
        #expect(summary?.transactionText == "3 transactions")
        #expect(summary?.captionText.contains("transaction") == true)
        #expect(summary?.accessibilityLabel.contains("3 transactions") == true)
    }

    @Test("Selected net-cashflow day reports outflow direction")
    func selectedNetCashflowDaySummary() {
        // Stored value -300 is income (negative outflow). Stored value 120 is an
        // outflow under net mode (displayCashflowAmount flips the sign).
        let summary = SpendingHeatmap.focusedDaySummary(for: "2026-01-02", in: layout(mode: .netCashflow))

        #expect(summary?.transactionText == "1 transaction")
        // displayCashflowAmount(-300) == 300 → positive → "+" prefix.
        #expect(summary?.amountText.hasPrefix("+") == true)
    }

    @Test("No selection yields no focused summary (caller shows the total)")
    func noSelectionYieldsNil() {
        #expect(SpendingHeatmap.focusedDaySummary(for: nil, in: layout(mode: .spending)) == nil)
    }

    @Test("Out-of-range selected date yields no focused summary")
    func outOfRangeSelectionYieldsNil() {
        #expect(SpendingHeatmap.focusedDaySummary(for: "1999-12-31", in: layout(mode: .spending)) == nil)
    }

    @Test("Zero-activity selected day still summarizes with a zero count")
    func zeroActivityDaySummary() {
        let summary = SpendingHeatmap.focusedDaySummary(for: "2026-01-03", in: layout(mode: .spending))

        #expect(summary != nil)
        #expect(summary?.transactionText == "0 transactions")
    }

    @Test("Caption composes 'date · amount · count'; spend amount carries no sign prefix")
    func captionFormatAndUnsignedSpend() {
        let summary = SpendingHeatmap.focusedDaySummary(for: "2026-01-01", in: layout(mode: .spending))

        // Spend-mode amounts are unsigned (sign prefixes are net-cashflow only).
        #expect(summary?.amountText.hasPrefix("+") == false)
        #expect(summary?.amountText.hasPrefix("-") == false)

        // Caption is exactly "{date} · {amount} · {count}" — assert the structure
        // (not the locale-dependent date string) so it stays robust.
        let parts = summary?.captionText.components(separatedBy: " · ")
        #expect(parts?.count == 3)
        #expect(parts?[1] == summary?.amountText)
        #expect(parts?[2] == summary?.transactionText)
    }

    // MARK: - Per-cell label masking (AND-671)

    private let spendDay = SpendingHeatmapDay(date: "2026-01-01", value: 120, transactionCount: 3)
    private let zeroDay = SpendingHeatmapDay(date: "2026-01-03", value: 0, transactionCount: 0)

    @Test("Unmasked cell label shows the date, real amount, and count")
    func cellLabelUnmaskedShowsValue() {
        let label = SpendingHeatmap.cellLabel(for: spendDay, mode: .spending)

        #expect(label.contains("3 transactions"))
        #expect(label.contains(SpendingHeatmap.amountText(for: spendDay, mode: .spending)))
        // The real currency amount is present, not the mask token.
        #expect(label.contains("$"))
        #expect(!label.contains(PrivacyMaskPresentation.compactValue))
    }

    @Test("Masked cell label hides the amount but keeps the date and count")
    func cellLabelMaskedHidesAmountOnly() {
        let label = SpendingHeatmap.cellLabel(for: spendDay, mode: .spending, isPrivacyMasked: true)

        // Amount is withheld …
        #expect(label.contains(PrivacyMaskPresentation.compactValue))
        #expect(!label.contains("$"))
        #expect(!label.contains("120"))
        // … but the structural date and the (non-financial) transaction count remain,
        // so the cell still carries meaning textually for hover / VoiceOver.
        #expect(label.contains("3 transactions"))
        let datePrefix = Formatters.displayTransactionDate(spendDay.date)
        #expect(label.contains(datePrefix))
    }

    @Test("Masked net-cashflow amount drops the sign prefix entirely (no +/- leak)")
    func cellLabelMaskedNetCashflowDropsSignPrefix() {
        // -300 stored → income → would render with a "+" prefix unmasked. Masked,
        // the whole token (prefix included) must collapse to the mask glyph.
        let incomeDay = SpendingHeatmapDay(date: "2026-01-02", value: -300, transactionCount: 1)
        let masked = SpendingHeatmap.amountText(for: incomeDay, mode: .netCashflow, isPrivacyMasked: true)

        #expect(masked == PrivacyMaskPresentation.compactValue)
        #expect(!masked.contains("+"))
        #expect(!masked.contains("-"))
    }

    @Test("Masked zero/empty day still hides the $0 amount and keeps a zero count")
    func cellLabelMaskedZeroDay() {
        let label = SpendingHeatmap.cellLabel(for: zeroDay, mode: .spending, isPrivacyMasked: true)

        #expect(label.contains(PrivacyMaskPresentation.compactValue))
        #expect(!label.contains("$"))
        #expect(label.contains("0 transactions"))
    }
}
