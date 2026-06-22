import Foundation

/// The shared `vaultpeek://` deep-link contract that maps a URL to a ``Route`` and
/// back (AND-586).
///
/// App Intents (Spotlight / Siri / Shortcuts), widgets, and Control Center
/// controls cannot reach into the app's window directly — they hand the app a URL.
/// This is the single, pure, `Sendable` place that decides what URL a deep link
/// uses and how the app parses it back into a ``Route`` so it can call
/// `AppState.route(to:)`. Keeping it in ``PlaidBarCore`` means both the producing
/// side (intents in the widget/Core target) and the consuming side (`onOpenURL`
/// in the app target) agree on one contract, unit-testable without the app.
///
/// Form: `vaultpeek://route/<destination>` where `<destination>` is the
/// ``RouteDestination`` raw value (e.g. `vaultpeek://route/transactions`). The
/// legacy `vaultpeek://dashboard` link (``GlanceSnapshot/deepLinkURL``) still
/// resolves to the dashboard for backward compatibility with already-installed
/// widgets and Spotlight items.
///
/// Only the *bare destination* travels in the URL — not per-row selection. A
/// deep link lands the window on the right destination's canonical route; the
/// inspector then shows its "Select a …" empty state. This keeps the contract
/// small and avoids leaking identifiers (account ids, transaction ids) into a URL
/// the system may log.
public enum RouteDeepLink {
    /// The custom URL scheme registered in the app's `Info.plist`.
    public static let scheme = "vaultpeek"

    /// The host segment that marks a typed route link, distinguishing it from the
    /// legacy `vaultpeek://dashboard` form (which uses the destination as the host).
    public static let routeHost = "route"

    /// Builds the deep-link URL string for a bare destination.
    /// e.g. `.transactions` → `"vaultpeek://route/transactions"`.
    public static func urlString(for destination: RouteDestination) -> String {
        "\(scheme)://\(routeHost)/\(destination.rawValue)"
    }

    /// Builds the deep-link URL for a bare destination, or `nil` if the string
    /// cannot form a URL (unreachable in practice — the components are URL-safe).
    public static func url(for destination: RouteDestination) -> URL? {
        URL(string: urlString(for: destination))
    }

    /// The deep-link URL string for the destination a ``Route`` resolves to.
    /// Selection is intentionally dropped (see type docs).
    public static func urlString(for route: Route) -> String {
        urlString(for: route.destination)
    }

    /// Parses a `vaultpeek://` URL into the destination's canonical ``Route``.
    ///
    /// Accepts three forms, returning `nil` for anything else (wrong scheme,
    /// unknown destination):
    /// - `vaultpeek://route/<destination>` — the typed route form.
    /// - `vaultpeek://<destination>` — host-only form (e.g. the legacy
    ///   `vaultpeek://dashboard`), so existing widget/Spotlight links keep working.
    /// - `vaultpeek://route` with no path — resolves to the dashboard.
    public static func route(from url: URL) -> Route? {
        guard url.scheme == scheme else { return nil }

        // `vaultpeek://route/<destination>`: host == "route", first path segment
        // is the destination.
        if url.host == routeHost {
            let segments = url.pathComponents.filter { $0 != "/" }
            guard let first = segments.first else {
                // `vaultpeek://route` with no destination → dashboard.
                return .dashboard
            }
            return destination(forRawValue: first).map(Route.canonical(for:))
        }

        // Legacy / host-only form `vaultpeek://<destination>` (covers
        // `vaultpeek://dashboard`).
        if let host = url.host, let destination = destination(forRawValue: host) {
            return Route.canonical(for: destination)
        }

        return nil
    }

    /// Resolves a ``RouteDestination`` from its raw value, case-insensitively, so a
    /// link is forgiving of casing differences across surfaces.
    private static func destination(forRawValue raw: String) -> RouteDestination? {
        let lowered = raw.lowercased()
        return RouteDestination.allCases.first { $0.rawValue.lowercased() == lowered }
    }
}
