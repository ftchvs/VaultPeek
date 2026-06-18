import PlaidBarCore
import Testing

@Suite("Menu bar icon style")
struct MenuBarIconStyleTests {
    private func healthyDemo(_ style: MenuBarIconStyle) -> MenuBarStatusPresentation {
        // A healthy demo state exercises the default/healthy glyph path.
        MenuBarStatusPresentation.evaluate(
            isDemoMode: true,
            isLoading: false,
            serverConnected: true,
            errorMessage: nil,
            erroredItemCount: 0,
            needsLoginItemCount: 0,
            isSyncStale: false,
            hasEverSynced: true,
            iconStyle: style
        )
    }

    @Test("Healthy glyph follows the chosen icon style")
    func healthyGlyphVariesByStyle() {
        #expect(healthyDemo(.classic).symbolName == "dollarsign.circle")
        #expect(healthyDemo(.minimal).symbolName == "centsign.circle")
        #expect(healthyDemo(.chart).symbolName == "chart.line.uptrend.xyaxis.circle")
        // Vault renders from a code-drawn template image, so its healthy glyph
        // is the custom token, not an SF Symbol.
        #expect(healthyDemo(.vault).symbolName == MenuBarIconStyle.customGlyphToken)
        // Healthy never carries a severity (no color-only alert).
        #expect(healthyDemo(.minimal).severity == nil)
        #expect(healthyDemo(.vault).severity == nil)
    }

    @Test("healthySymbolName mapping and metadata are stable")
    func styleMetadata() {
        #expect(MenuBarIconStyle.allCases.count == 4)
        #expect(MenuBarIconStyle.defaultValue == .classic)
        #expect(MenuBarIconStyle.classic.healthySymbolName == "dollarsign.circle")
        #expect(MenuBarIconStyle.minimal.healthySymbolName == "centsign.circle")
        #expect(MenuBarIconStyle.chart.healthySymbolName == "chart.line.uptrend.xyaxis.circle")
        // Only the Vault style uses a custom glyph token (not a real SF Symbol).
        #expect(MenuBarIconStyle.vault.healthySymbolName == MenuBarIconStyle.customGlyphToken)
        #expect(MenuBarIconStyle.vault.usesCustomGlyph)
        #expect(!MenuBarIconStyle.classic.usesCustomGlyph)
        for style in MenuBarIconStyle.allCases {
            #expect(!style.displayName.isEmpty)
            // Round-trips through its raw value (used for persistence).
            #expect(MenuBarIconStyle(rawValue: style.rawValue) == style)
        }
    }

    @Test("Item errors keep the fixed error glyph regardless of icon style")
    func errorLadderIgnoresStyle() {
        for style in MenuBarIconStyle.allCases {
            let presentation = MenuBarStatusPresentation.evaluate(
                isDemoMode: false,
                isLoading: false,
                serverConnected: true,
                errorMessage: nil,
                erroredItemCount: 1,
                needsLoginItemCount: 0,
                isSyncStale: false,
                hasEverSynced: true,
                iconStyle: style
            )
            #expect(presentation.symbolName == "exclamationmark.octagon")
            #expect(presentation.severity == .blocking) // meaning carried beyond color
            #expect(presentation.symbolName != style.healthySymbolName)
        }
    }

    @Test("Offline keeps its distinct glyph regardless of icon style")
    func offlineLadderIgnoresStyle() {
        for style in MenuBarIconStyle.allCases {
            let presentation = MenuBarStatusPresentation.evaluate(
                isDemoMode: false,
                isLoading: false,
                serverConnected: false,
                errorMessage: nil,
                erroredItemCount: 0,
                needsLoginItemCount: 0,
                isSyncStale: true,
                hasEverSynced: true,
                iconStyle: style
            )
            #expect(presentation.symbolName == "network.slash")
            #expect(presentation.severity != nil)
            #expect(presentation.symbolName != style.healthySymbolName)
        }
    }

    @Test("Needs-login / stale keeps the warning glyph regardless of icon style")
    func warningLadderIgnoresStyle() {
        for style in MenuBarIconStyle.allCases {
            // Server reachable but an item needs login: the third degraded path.
            let presentation = MenuBarStatusPresentation.evaluate(
                isDemoMode: false,
                isLoading: false,
                serverConnected: true,
                errorMessage: nil,
                erroredItemCount: 0,
                needsLoginItemCount: 1,
                isSyncStale: false,
                hasEverSynced: true,
                iconStyle: style
            )
            #expect(presentation.symbolName == "exclamationmark.triangle")
            #expect(presentation.severity != nil)
            #expect(presentation.symbolName != style.healthySymbolName)
        }
    }
}
