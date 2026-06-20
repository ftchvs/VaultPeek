import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Route deep-link contract (AND-586)")
struct RouteDeepLinkTests {
    @Test("Every destination round-trips through the typed route URL")
    func everyDestinationRoundTrips() throws {
        for destination in RouteDestination.allCases {
            let urlString = RouteDeepLink.urlString(for: destination)
            let url = try #require(URL(string: urlString))
            let route = try #require(RouteDeepLink.route(from: url))
            #expect(route.destination == destination)
            // The canonical route for the destination is what a bare deep link
            // resolves to (no per-row selection carried).
            #expect(route == Route.canonical(for: destination))
        }
    }

    @Test("Typed route URL uses the vaultpeek://route/<destination> form")
    func typedRouteURLForm() {
        #expect(RouteDeepLink.urlString(for: .transactions) == "vaultpeek://route/transactions")
        #expect(RouteDeepLink.urlString(for: .budgets) == "vaultpeek://route/budgets")
        #expect(RouteDeepLink.urlString(for: .review) == "vaultpeek://route/review")
    }

    @Test("Legacy host-only vaultpeek://dashboard still resolves to the dashboard")
    func legacyDashboardLinkResolves() throws {
        let url = try #require(URL(string: GlanceSnapshot.deepLinkURL))
        let route = try #require(RouteDeepLink.route(from: url))
        #expect(route == .dashboard)
    }

    @Test("Host-only form resolves any destination (e.g. vaultpeek://accounts)")
    func hostOnlyFormResolves() throws {
        let url = try #require(URL(string: "vaultpeek://accounts"))
        #expect(RouteDeepLink.route(from: url) == .accounts())
    }

    @Test("vaultpeek://route with no destination resolves to the dashboard")
    func bareRouteHostResolvesToDashboard() throws {
        let url = try #require(URL(string: "vaultpeek://route"))
        #expect(RouteDeepLink.route(from: url) == .dashboard)
    }

    @Test("Casing is forgiven when parsing a destination")
    func casingForgiven() throws {
        let url = try #require(URL(string: "vaultpeek://route/Transactions"))
        #expect(RouteDeepLink.route(from: url) == .transactions())
    }

    @Test("Wrong scheme returns nil")
    func wrongSchemeReturnsNil() throws {
        let url = try #require(URL(string: "https://route/dashboard"))
        #expect(RouteDeepLink.route(from: url) == nil)
    }

    @Test("Unknown destination returns nil")
    func unknownDestinationReturnsNil() throws {
        let url = try #require(URL(string: "vaultpeek://route/nonsense"))
        #expect(RouteDeepLink.route(from: url) == nil)
    }

    @Test("urlString(for: route) drops selection, keeping the destination")
    func routeURLDropsSelection() {
        let route = Route.transactions(filter: nil, focus: "abc-123")
        #expect(RouteDeepLink.urlString(for: route) == "vaultpeek://route/transactions")
    }
}
