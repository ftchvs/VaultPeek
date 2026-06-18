import Foundation
import Testing
@testable import PlaidBarCore

@Suite("DashboardCardOrder (AND-487)")
struct DashboardCardOrderTests {

    @Test("Empty saved order resolves to the canonical default order")
    func emptySavedOrderUsesDefault() {
        let resolved = DashboardCardOrder.resolve(savedOrder: [])
        #expect(resolved == DashboardCardOrder.default)
        #expect(resolved == DashboardCardKind.allCases)
    }

    @Test("A saved order missing a newer kind appends it at its default position")
    func forwardCompatAppendsNewKind() {
        // Simulate an old saved order that predates `.insights` shipping.
        let saved: [DashboardCardKind] = [.changeReceipt, .weeklyReview, .overview, .recentSpend]
        let resolved = DashboardCardOrder.resolve(savedOrder: saved)
        // The new kind is present and lands at its default trailing position.
        #expect(resolved.contains(.insights))
        #expect(resolved.last == .insights)
        #expect(resolved.count == DashboardCardKind.allCases.count)
    }

    @Test("A newer middle kind slots into the middle, not the end")
    func forwardCompatInsertsMiddleKind() {
        // Saved order is missing `.overview` (a middle kind in the default).
        let saved: [DashboardCardKind] = [.changeReceipt, .weeklyReview, .recentSpend, .insights]
        let resolved = DashboardCardOrder.resolve(savedOrder: saved)
        let overviewIndex = resolved.firstIndex(of: .overview)
        let weeklyIndex = resolved.firstIndex(of: .weeklyReview)
        let recentIndex = resolved.firstIndex(of: .recentSpend)
        #expect(overviewIndex != nil)
        // .overview should sit after .weeklyReview and before .recentSpend.
        #expect((overviewIndex ?? 0) > (weeklyIndex ?? 0))
        #expect((overviewIndex ?? 0) < (recentIndex ?? 0))
    }

    @Test("Decode drops unknown/removed raw values")
    func decodeDropsUnknownKinds() {
        let raw = ["changeReceipt", "someRemovedCard", "overview", "garbage"]
        let decoded = DashboardCardOrder.decode(rawOrder: raw)
        #expect(decoded == [.changeReceipt, .overview])
    }

    @Test("Pinning a kind floats it to the front, preserving the rest's order")
    func pinningFloatsToFront() {
        let resolved = DashboardCardOrder.resolve(
            savedOrder: DashboardCardKind.allCases,
            pinned: [.recentSpend]
        )
        #expect(resolved.first == .recentSpend)
        // The non-pinned kinds keep their relative order.
        let rest = resolved.filter { $0 != .recentSpend }
        let expectedRest = DashboardCardKind.allCases.filter { $0 != .recentSpend }
        #expect(rest == expectedRest)
    }

    @Test("Pinning multiple kinds preserves their relative order")
    func pinningMultiplePreservesRelativeOrder() {
        let resolved = DashboardCardOrder.resolve(
            savedOrder: DashboardCardKind.allCases,
            pinned: [.insights, .changeReceipt]
        )
        // Both float to the front; relative order matches the base (changeReceipt
        // before insights in the default order).
        #expect(Array(resolved.prefix(2)) == [.changeReceipt, .insights])
    }

    @Test("Persisted JSON round-trips stably through encode/decode")
    func encodeDecodeRoundTrip() {
        let order = DashboardCardOrder.resolve(savedOrder: [], pinned: [.overview])
        let raw = DashboardCardOrder.encode(order)
        let decoded = DashboardCardOrder.decode(rawOrder: raw)
        #expect(decoded == order)

        // And through a JSON encode/decode of the raw strings.
        let data = try! JSONEncoder().encode(raw)
        let restored = try! JSONDecoder().decode([String].self, from: data)
        #expect(DashboardCardOrder.decode(rawOrder: restored) == order)
    }
}
