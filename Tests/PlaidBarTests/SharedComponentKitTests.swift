import Foundation
import Testing

/// Source-invariant guards for the shared design-elevation component kit
/// (`Sources/PlaidBar/Views/Shared/`). These pin the accessibility contracts
/// that a refactor could silently drop without breaking the build.
@Suite("Shared component kit source invariants")
struct SharedComponentKitTests {
    private func source(atRepoPath path: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    /// The chart scrub is a pointer affordance: it must stay a NO-OP while
    /// VoiceOver runs, leaving audio graphs as the accessibility path.
    @Test func chartScrubStaysNoOpUnderVoiceOver() throws {
        let scrub = try source(atRepoPath: "Sources/PlaidBar/Views/Shared/ChartScrub.swift")

        #expect(scrub.contains(#"@Environment(\.accessibilityVoiceOverEnabled)"#))
        #expect(scrub.contains("if voiceOverEnabled {"))
        // The selection binding must live on the non-VoiceOver branch only.
        #expect(scrub.contains(".chartXSelection(value: $selectedDate)"))
    }

    /// `BudgetBarRow` must delegate the verdict's tint AND glyph to the single
    /// shared mappings (`CategoryBudgetStatus.verdictTint` / `.iconName`,
    /// AND-664 #4) rather than re-declaring its own status → color/symbol
    /// switches — the glyph is the non-color half of the verdict cue, so a
    /// forked vocabulary would contradict every other budget surface.
    @Test func budgetBarRowDelegatesVerdictTintAndGlyph() throws {
        let row = try source(atRepoPath: "Sources/PlaidBar/Views/Shared/BudgetBarRow.swift")

        #expect(row.contains("status.verdictTint"))
        // The verdict Label's tint comes from the delegated mapping.
        #expect(row.contains(".foregroundStyle(status.verdictTint)"))
        // The verdict glyph comes from the shared vocabulary, with the same
        // neutral no-budget fallback as `statusIconName` elsewhere.
        #expect(row.contains(#"status?.iconName ?? "minus.circle""#))
    }
}
