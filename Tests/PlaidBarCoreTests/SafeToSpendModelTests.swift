import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Safe-to-spend model accessors")
struct SafeToSpendModelTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func component(_ kind: SafeToSpendComponentKind, _ amount: Double) -> SafeToSpendComponent {
        SafeToSpendComponent(kind: kind, label: kind.rawValue, amount: amount)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.startOfDay(for: calendar.date(from: components) ?? Date(timeIntervalSince1970: 0))
    }

    // MARK: visibleComponents

    @Test("Visible components always keep cash and income, even at zero")
    func visibleKeepsCashAndIncomeAtZero() {
        let result = SafeToSpendResult(
            amount: 0,
            components: [component(.startingCash, 0), component(.expectedIncome, 0), component(.safetyBuffer, 0)],
            confidence: .ok,
            horizonEnd: Date()
        )
        #expect(result.visibleComponents.map(\.kind) == [.startingCash, .expectedIncome])
    }

    @Test("Visible components drop zero subtractions but keep non-zero ones")
    func visibleDropsZeroSubtractions() {
        let result = SafeToSpendResult(
            amount: -50,
            components: [component(.startingCash, 100), component(.pendingHolds, 0), component(.upcomingObligations, -150)],
            confidence: .lowConfidence,
            horizonEnd: Date()
        )
        #expect(result.visibleComponents.map(\.kind) == [.startingCash, .upcomingObligations])
    }

    // MARK: Component identity + icons

    @Test("Component id mirrors its kind")
    func componentIdentity() {
        #expect(component(.loanPayments, -10).id == .loanPayments)
    }

    @Test("Every component kind has a non-empty, distinct icon")
    func componentKindIcons() {
        let icons = SafeToSpendComponentKind.allCases.map(\.iconName)
        #expect(icons.allSatisfy { !$0.isEmpty })
        #expect(Set(icons).count == SafeToSpendComponentKind.allCases.count)
    }

    // MARK: Confidence

    @Test("Confidence is ordered least to most trustworthy")
    func confidenceOrdering() {
        #expect(SafeToSpendConfidence.insufficientData < .lowConfidence)
        #expect(SafeToSpendConfidence.lowConfidence < .ok)
        #expect(SafeToSpendConfidence.allCases.count == 3)
    }

    @Test("Confidence exposes a label and icon for every case")
    func confidenceLabelsAndIcons() {
        for confidence in SafeToSpendConfidence.allCases {
            #expect(!confidence.label.isEmpty)
            #expect(!confidence.iconName.isEmpty)
        }
        #expect(SafeToSpendConfidence.ok.label == "On track")
        #expect(SafeToSpendConfidence.insufficientData.iconName == "questionmark.circle")
    }

    @Test("Dashboard confidence cue prefixes the horizon and never duplicates 'confidence'")
    func dashboardConfidenceCueGoldenStrings() {
        // Golden strings: the cue is the horizon period text plus the label, with
        // no trailing literal " confidence" — the label already reads as a full
        // phrase, so appending the word produced "Lower confidence confidence" and
        // the ungrammatical "On track confidence" / "Estimate only confidence".
        #expect(SafeToSpendConfidence.insufficientData.dashboardDetailCue == "Through end of month · Estimate only")
        #expect(SafeToSpendConfidence.lowConfidence.dashboardDetailCue == "Through end of month · Lower confidence")
        #expect(SafeToSpendConfidence.ok.dashboardDetailCue == "Through end of month · On track")

        // No cue may contain the word "confidence" twice (the original bug).
        for confidence in SafeToSpendConfidence.allCases {
            let occurrences = confidence.dashboardDetailCue
                .lowercased()
                .components(separatedBy: "confidence")
                .count - 1
            #expect(occurrences <= 1)
        }
    }

    // MARK: Horizon

    @Test("End-of-month horizon resolves to the month's final day")
    func endOfMonthHorizon() {
        let end = SafeToSpendHorizon.endOfMonth.endDate(asOf: makeDate(2026, 6, 15), calendar: calendar)
        #expect(end == makeDate(2026, 6, 30))
    }

    @Test("Day horizon adds the count and clamps to at least one day")
    func dayHorizonClamps() {
        let start = makeDate(2026, 6, 15)
        #expect(SafeToSpendHorizon.days(5).endDate(asOf: start, calendar: calendar) == makeDate(2026, 6, 20))
        #expect(SafeToSpendHorizon.days(0).endDate(asOf: start, calendar: calendar) == makeDate(2026, 6, 16))
        #expect(SafeToSpendHorizon.days(-4).endDate(asOf: start, calendar: calendar) == makeDate(2026, 6, 16))
    }

    // MARK: Inputs

    @Test("Inputs clamp negative buffer, reservations, and income to safe values")
    func inputsClampNegatives() {
        let inputs = SafeToSpendInputs(safetyBuffer: -100, budgetReservations: -50, manualExpectedIncome: -25)
        #expect(inputs.safetyBuffer == 0)
        #expect(inputs.budgetReservations == 0)
        #expect(inputs.manualExpectedIncome == 0)
    }

    @Test("Default inputs are depository-only with an end-of-month horizon")
    func defaultInputs() {
        #expect(SafeToSpendInputs.default.includedCashAccountTypes == [.depository])
        #expect(SafeToSpendInputs.default.safetyBuffer == 0)
        #expect(SafeToSpendInputs.default.manualExpectedIncome == nil)
        #expect(SafeToSpendInputs.default.horizon == .endOfMonth)
    }
}
