import Testing
@testable import PlaidBarCore

/// Pins the pure provenance-line composition consolidated into
/// ``LocalAIInsightReceipt`` from three byte-identical/near-identical inline
/// copies (Dashboard insight card, menu-bar popover, Insights AI surface).
///
/// `detailLines` and `secondaryProvenanceLines` are deliberately distinct: the
/// three-line cap on `detailLines` *includes* the leading confidence cue, while
/// the cap on `secondaryProvenanceLines` applies to the secondary lines alone —
/// so the two are **not** related by simply prepending `confidence`.
@Suite struct LocalAIInsightReceiptDetailLinesTests {
    /// Builds a receipt whose only fields that matter to line composition are
    /// `confidence`, `limitations`, and `unavailableState`. The rest are inert.
    private func receipt(
        confidence: String = "High confidence",
        limitations: [String] = [],
        unavailableState: String? = nil
    ) -> LocalAIInsightReceipt {
        LocalAIInsightReceipt(
            title: "Title",
            headline: "Headline",
            evidenceChips: [],
            timeWindow: "Last 30 days",
            localOnlyBadge: "On-device",
            confidence: confidence,
            limitations: limitations,
            unavailableState: unavailableState,
            reversibleActionCopy: "Reversible",
            accessibilitySummary: "Summary"
        )
    }

    // The verbatim original inline expressions, used as behavior-preservation
    // oracles so the extraction is proven identical, not merely plausible.
    private func detailLinesOracle(_ r: LocalAIInsightReceipt) -> [String] {
        var lines = [r.confidence]
        if let unavailableState = r.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: r.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    private func secondaryOracle(_ r: LocalAIInsightReceipt) -> [String] {
        var lines: [String] = []
        if let unavailableState = r.unavailableState {
            lines.append(unavailableState)
        }
        lines.append(contentsOf: r.limitations.prefix(2))
        return Array(lines.prefix(3))
    }

    // MARK: - detailLines (confidence-prepended, whole list capped at 3)

    @Test func detailLinesConfidenceOnly() {
        #expect(receipt().detailLines == ["High confidence"])
    }

    @Test func detailLinesConfidencePlusLimitations() {
        let r = receipt(limitations: ["lim1", "lim2"])
        #expect(r.detailLines == ["High confidence", "lim1", "lim2"])
    }

    @Test func detailLinesCapsLimitationsAtTwo() {
        // Three limitations: prefix(2) keeps two, then the overall prefix(3)
        // keeps confidence + those two.
        let r = receipt(limitations: ["lim1", "lim2", "lim3"])
        #expect(r.detailLines == ["High confidence", "lim1", "lim2"])
    }

    @Test func detailLinesUnavailableDropsSecondLimitation() {
        // Differentiator: confidence + unavailable + two limitations is four
        // entries; the three-line cap drops the *last* limitation.
        let r = receipt(limitations: ["lim1", "lim2"], unavailableState: "Model offline")
        #expect(r.detailLines == ["High confidence", "Model offline", "lim1"])
    }

    @Test func detailLinesUnavailableNoLimitations() {
        let r = receipt(unavailableState: "Model offline")
        #expect(r.detailLines == ["High confidence", "Model offline"])
    }

    // MARK: - secondaryProvenanceLines (no confidence, capped at 3)

    @Test func secondaryEmptyWhenNothingSecondary() {
        #expect(receipt().secondaryProvenanceLines == [])
    }

    @Test func secondaryUnavailablePlusTwoLimitations() {
        let r = receipt(limitations: ["lim1", "lim2"], unavailableState: "Model offline")
        #expect(r.secondaryProvenanceLines == ["Model offline", "lim1", "lim2"])
    }

    @Test func secondaryCapsLimitationsAtTwo() {
        let r = receipt(limitations: ["lim1", "lim2", "lim3"])
        #expect(r.secondaryProvenanceLines == ["lim1", "lim2"])
    }

    @Test func secondaryUnavailableOnly() {
        let r = receipt(unavailableState: "Model offline")
        #expect(r.secondaryProvenanceLines == ["Model offline"])
    }

    // MARK: - The two are genuinely distinct (cap interaction)

    @Test func detailLinesAreNotConfidencePlusSecondary() {
        // With unavailable + two limitations, detailLines has three entries but
        // [confidence] + secondaryProvenanceLines would have four — proving the
        // caps interact differently and both members are needed.
        let r = receipt(limitations: ["lim1", "lim2"], unavailableState: "Model offline")
        #expect(r.detailLines != [r.confidence] + r.secondaryProvenanceLines)
    }

    // MARK: - Behavior-preservation oracle sweep

    @Test func matchesVerbatimOriginalsAcrossCombinations() {
        let confidences = ["High confidence", ""]
        let limitationSets: [[String]] = [[], ["a"], ["a", "b"], ["a", "b", "c"]]
        let unavailables: [String?] = [nil, "Offline"]
        for c in confidences {
            for lims in limitationSets {
                for u in unavailables {
                    let r = receipt(confidence: c, limitations: lims, unavailableState: u)
                    #expect(r.detailLines == detailLinesOracle(r))
                    #expect(r.secondaryProvenanceLines == secondaryOracle(r))
                }
            }
        }
    }
}
