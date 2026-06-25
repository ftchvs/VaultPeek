import Foundation

/// Pure, headless copy model for the one-time **window-first orientation moment**
/// (AND-640): the first-launch sheet shown on the primary `Window` to users
/// arriving from the menu-bar era.
///
/// The model is intentionally pure and `Sendable` so it lives in `PlaidBarCore`,
/// is unit-testable without launching the app, and can be rendered headlessly. It
/// carries **only orientation copy** — never any financial value, account, or
/// institution detail — so it is safe to show regardless of Privacy Mask / App
/// Lock state (the orientation sheet has nothing to mask).
///
/// The three points map to the orientation's job: the menu bar is the calm
/// glance, the window is the deeper workspace, and the privacy controls
/// (App Lock / Privacy Mask) apply to **both** surfaces.
public struct WindowFirstOrientationCopy: Equatable, Sendable {
    /// A single orientation point: an SF Symbol name, a short title, and one
    /// explanatory line. `accessibilityLabel` is the pre-composed VoiceOver string
    /// so the rendering view announces one coherent phrase per point rather than
    /// reading the glyph + title + body as three fragments.
    public struct Point: Equatable, Sendable, Identifiable {
        public let id: String
        public let systemImage: String
        public let title: String
        public let body: String

        public init(id: String, systemImage: String, title: String, body: String) {
            self.id = id
            self.systemImage = systemImage
            self.title = title
            self.body = body
        }

        /// "Menu bar — the calm glance. Quick status…" — title and body joined
        /// into one announced phrase. The glyph is decorative and is hidden from
        /// VoiceOver by the view, so it is intentionally not spoken here.
        public var accessibilityLabel: String {
            "\(title). \(body)"
        }
    }

    public let title: String
    public let subtitle: String
    public let points: [Point]
    public let dismissButtonTitle: String
    public let dismissAccessibilityLabel: String
    public let dismissAccessibilityHint: String

    public init(
        title: String,
        subtitle: String,
        points: [Point],
        dismissButtonTitle: String,
        dismissAccessibilityLabel: String,
        dismissAccessibilityHint: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.points = points
        self.dismissButtonTitle = dismissButtonTitle
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.dismissAccessibilityHint = dismissAccessibilityHint
    }

    /// The shipped orientation copy. Static (no inputs) because the moment is a
    /// fixed welcome — it explains the surfaces, it does not report state. Factored
    /// as a `default` so the same canonical copy is exercised by tests and the view.
    public static let standard = WindowFirstOrientationCopy(
        title: "Welcome to the VaultPeek window",
        subtitle: "VaultPeek now opens in a full window. Here is how the two surfaces work together.",
        points: [
            Point(
                id: "menuBar",
                systemImage: "menubar.arrow.up.rectangle",
                title: "The menu bar is your calm glance",
                body: "It keeps a quick read on status and a few key numbers, one click away — without opening anything."
            ),
            Point(
                id: "window",
                systemImage: "macwindow",
                title: "The window is your deeper workspace",
                body: "Open it for the full dashboard, transactions, budgets, planning, and review — everything in one place."
            ),
            Point(
                id: "privacy",
                systemImage: "lock.shield",
                title: "Privacy controls cover both",
                body: "App Lock and Privacy Mask apply everywhere — when balances are hidden or the app is locked, both the glance and the window stay private."
            ),
        ],
        dismissButtonTitle: "Got it",
        dismissAccessibilityLabel: "Dismiss orientation",
        dismissAccessibilityHint: "Closes this welcome and does not show it again."
    )

    /// The full VoiceOver summary for the whole sheet (announced when the sheet's
    /// container element gains focus): the title, subtitle, and each point's
    /// announced phrase, joined into one coherent read.
    public var accessibilitySummary: String {
        ([title, subtitle] + points.map(\.accessibilityLabel)).joined(separator: " ")
    }
}
