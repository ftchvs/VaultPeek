import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Goal editor input validation (AND-606)")
struct GoalEditorInputTests {
    private let future = Date().addingTimeInterval(86_400 * 30)
    private let past = Date().addingTimeInterval(-86_400 * 30)

    // MARK: - parseAmount

    @Test("parseAmount tolerates symbols, grouping, and whitespace")
    func parseAmount() {
        #expect(GoalEditorInput.parseAmount("1250") == 1250)
        #expect(GoalEditorInput.parseAmount("$1,250.50") == 1250.50)
        #expect(GoalEditorInput.parseAmount("  2000  ") == 2000)
        #expect(GoalEditorInput.parseAmount("") == nil)
        #expect(GoalEditorInput.parseAmount("abc") == nil)
    }

    @Test("parseAmount handles European grouping/decimal, US cases unchanged")
    func parseAmountLocaleAware() {
        // European: '.' grouping, ',' decimal — last separator wins.
        #expect(GoalEditorInput.parseAmount("1.250,50") == 1250.50)
        // Existing US cases must still pass.
        #expect(GoalEditorInput.parseAmount("1,250.50") == 1250.50)
        #expect(GoalEditorInput.parseAmount("5,000") == 5000)
        #expect(GoalEditorInput.parseAmount("1250") == 1250)
    }

    @Test("validate accepts a European-formatted target amount")
    func validateEuropeanTarget() {
        let outcome = GoalEditorInput.validate(
            nameText: "Fund",
            targetText: "1.250,50",
            contributedText: "",
            targetDate: nil,
            linkedCategory: nil
        )
        #expect(outcome.draft?.targetAmount == 1250.50)
    }

    // MARK: - Name

    @Test("A blank name is invalid")
    func blankName() {
        let outcome = GoalEditorInput.validate(
            nameText: "   ",
            targetText: "1000",
            contributedText: "",
            targetDate: nil,
            linkedCategory: nil
        )
        #expect(!outcome.isCommittable)
        #expect(outcome.message != nil)
    }

    // MARK: - Target

    @Test("A zero or missing target is invalid")
    func badTarget() {
        for target in ["", "0", "-5"] {
            let outcome = GoalEditorInput.validate(
                nameText: "Fund",
                targetText: target,
                contributedText: "",
                targetDate: nil,
                linkedCategory: nil
            )
            #expect(!outcome.isCommittable, "target \"\(target)\" should be invalid")
        }
    }

    // MARK: - Contributed

    @Test("Empty saved amount defaults to zero")
    func emptyContributedIsZero() {
        let outcome = GoalEditorInput.validate(
            nameText: "Fund",
            targetText: "1000",
            contributedText: "",
            targetDate: nil,
            linkedCategory: nil
        )
        #expect(outcome.draft?.contributedAmount == 0)
    }

    @Test("Saved amount above the target is invalid")
    func contributedAboveTarget() {
        let outcome = GoalEditorInput.validate(
            nameText: "Fund",
            targetText: "1000",
            contributedText: "1500",
            targetDate: nil,
            linkedCategory: nil
        )
        #expect(!outcome.isCommittable)
    }

    @Test("Saved amount equal to the target is valid (a funded goal)")
    func contributedEqualsTarget() {
        let outcome = GoalEditorInput.validate(
            nameText: "Fund",
            targetText: "1000",
            contributedText: "1000",
            targetDate: nil,
            linkedCategory: nil
        )
        #expect(outcome.isCommittable)
        #expect(outcome.draft?.contributedAmount == 1000)
    }

    // MARK: - Target date

    @Test("A past target date is invalid")
    func pastDate() {
        let outcome = GoalEditorInput.validate(
            nameText: "Fund",
            targetText: "1000",
            contributedText: "",
            targetDate: past,
            linkedCategory: nil
        )
        #expect(!outcome.isCommittable)
    }

    @Test("A valid draft trims the name and carries all fields")
    func validDraft() {
        let outcome = GoalEditorInput.validate(
            nameText: "  Emergency fund  ",
            targetText: "5,000",
            contributedText: "1200",
            targetDate: future,
            linkedCategory: .travel
        )
        let draft = outcome.draft
        #expect(draft?.name == "Emergency fund")
        #expect(draft?.targetAmount == 5000)
        #expect(draft?.contributedAmount == 1200)
        #expect(draft?.targetDate == future)
        #expect(draft?.linkedCategory == .travel)
    }
}
