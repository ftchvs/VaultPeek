import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Privacy mask presentation helpers")
struct PrivacyMaskPresentationHelpersTests {
    @Test("value applies the style-specific mask token when enabled")
    func valueStyles() {
        #expect(PrivacyMaskPresentation.value("$42", isEnabled: true, style: .compact) == PrivacyMaskPresentation.compactValue)
        #expect(PrivacyMaskPresentation.value("$42", isEnabled: true, style: .hero) == PrivacyMaskPresentation.heroValue)
        #expect(PrivacyMaskPresentation.value("$42", isEnabled: true, style: .detail) == PrivacyMaskPresentation.detailValue)
    }

    @Test("value passes through unmasked text when disabled")
    func valueDisabled() {
        #expect(PrivacyMaskPresentation.value("$42", isEnabled: false, style: .hero) == "$42")
    }

    @Test("Masked help text is present only while masking is enabled")
    func maskedHelpText() {
        #expect(PrivacyMaskPresentation.maskedHelpText(isEnabled: true) == PrivacyMaskPresentation.detailValue)
        #expect(PrivacyMaskPresentation.maskedHelpText(isEnabled: false) == nil)
    }

    @Test("Currency and percent helpers mask through the shared value path")
    func currencyAndPercent() {
        #expect(PrivacyMaskPresentation.currency(1_000, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        #expect(PrivacyMaskPresentation.percent(50, isEnabled: true) == PrivacyMaskPresentation.compactValue)
        // Disabled passes through a real formatted value.
        #expect(PrivacyMaskPresentation.currency(1_000, isEnabled: false) != PrivacyMaskPresentation.compactValue)
    }

    @Test("Toggle affordance carries state through glyph shape and verb, not color")
    func toggleAffordance() {
        #expect(PrivacyMaskPresentation.toggleSymbolName(isMasked: true) == "eye.slash")
        #expect(PrivacyMaskPresentation.toggleSymbolName(isMasked: false) == "eye")
        #expect(PrivacyMaskPresentation.toggleActionLabel(isMasked: true) == "Show amounts")
        #expect(PrivacyMaskPresentation.toggleActionLabel(isMasked: false) == "Hide amounts")
    }

    @Test("Currency tokens in free text are masked only when enabled")
    func maskCurrencyTokens() {
        let text = "Spent $4,545 and refunded -$1,707.50 across 12 charges."
        let masked = PrivacyMaskPresentation.maskCurrencyTokens(in: text, isEnabled: true)
        #expect(!masked.contains("$4,545"))
        #expect(!masked.contains("$1,707.50"))
        #expect(masked.contains("12 charges"))
        #expect(masked.contains(PrivacyMaskPresentation.compactValue))
        // Disabled leaves the text untouched.
        #expect(PrivacyMaskPresentation.maskCurrencyTokens(in: text, isEnabled: false) == text)
    }
}
