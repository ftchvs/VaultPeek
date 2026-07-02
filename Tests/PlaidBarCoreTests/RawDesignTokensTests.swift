import PlaidBarCore
import Testing

@Suite("Raw design token invariants (Gate-0 doctrine, AND-979)")
struct RawDesignTokensTests {
    // MARK: Spacing

    @Test("Card gap exceeds card padding — separation comes from spacing, not chrome")
    func cardGapExceedsCardPadding() {
        #expect(RawSpacing.cardGap > RawSpacing.cardPadding)
    }

    @Test("Spacing scale is strictly ordered")
    func spacingScaleOrdered() {
        #expect(RawSpacing.xxs < RawSpacing.xs)
        #expect(RawSpacing.xs < RawSpacing.sm)
        #expect(RawSpacing.sm < RawSpacing.md)
        #expect(RawSpacing.md < RawSpacing.cardPadding)
        #expect(RawSpacing.cardPadding < RawSpacing.cardGap)
        #expect(RawSpacing.cardGap < RawSpacing.xxl)
    }

    // MARK: Radius

    @Test("Radius ladder is strictly ordered: cell < control < card")
    func radiusLadderOrdered() {
        #expect(RawRadius.cell < RawRadius.control)
        #expect(RawRadius.control < RawRadius.card)
    }

    // MARK: Sizing

    @Test("Pointer-target floor is the 28pt desktop minimum, not the 44pt touch minimum")
    func pointerTargetIsDesktopFloor() {
        #expect(RawSizing.pointerTargetMin == 28)
        #expect(RawSizing.pointerTargetMin < RawSizing.rowMinHeight)
    }

    // MARK: Motion

    @Test("Motion durations are non-negative and ordered micro < standard < chartReveal")
    func motionDurationOrdering() {
        #expect(RawMotionDurations.micro > 0)
        #expect(RawMotionDurations.micro < RawMotionDurations.standard)
        #expect(RawMotionDurations.standard < RawMotionDurations.chartReveal)
        #expect(RawMotionDurations.contentDamping > 0 && RawMotionDurations.contentDamping < 1)
    }
}

@Suite("Category color completeness + contrast (Gate-0 doctrine, AND-979)")
struct CategoryColorContrastTests {
    /// Every `SpendingCategory` case must define both a light- and dark-mode
    /// hex, and no two categories may share the exact same light-mode hex
    /// (they'd be visually indistinguishable in the donut/legend).
    @Test("Every category has a light and dark hex, and light hexes are unique")
    func categoryHexCompleteness() {
        var seenLight: Set<String> = []
        for category in SpendingCategory.allCases {
            #expect(!category.colorHex.isEmpty)
            #expect(!category.colorHexDark.isEmpty)
            let (inserted, _) = seenLight.insert(category.colorHex)
            #expect(inserted, "Duplicate light-mode hex for \(category): \(category.colorHex)")
        }
    }

    /// WCAG 2.x contrast ratio between a category's dark-mode hex and the
    /// app's dark content background (#1E1E1E, matching the documented dark
    /// chart-palette fix). Guards the specific 5-category contrast bug
    /// DESIGN.md documents as already fixed — regresses loudly if a future
    /// edit reintroduces a low-contrast dark value instead of adding a hex
    /// patch.
    @Test("Category dark-mode hex clears 3:1 contrast against the dark chart background", arguments: SpendingCategory.allCases)
    func categoryDarkContrast(category: SpendingCategory) {
        let ratio = contrastRatio(category.colorHexDark, against: "#1E1E1E")
        #expect(ratio >= 3.0, "\(category) colorHexDark contrast \(ratio) < 3:1 against dark background")
    }

    // MARK: - WCAG contrast math (pure, no SwiftUI)

    private func contrastRatio(_ hexA: String, against hexB: String) -> Double {
        let lumA = relativeLuminance(hexA)
        let lumB = relativeLuminance(hexB)
        let lighter = max(lumA, lumB)
        let darker = min(lumA, lumB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ hex: String) -> Double {
        let (r, g, b) = rgbComponents(hex)
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func rgbComponents(_ hex: String) -> (Double, Double, Double) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return (0, 0, 0)
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return (r, g, b)
    }
}
