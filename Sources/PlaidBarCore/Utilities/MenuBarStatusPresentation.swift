import Foundation

/// The user-selectable healthy/default menu-bar glyph (AND-377). Only the
/// healthy state varies; the degraded ladder (error/offline/warning/login/stale)
/// is fixed and never carried by color alone. All styles are monochrome template
/// SF Symbols available on the macOS deployment target — no custom asset, so they
/// render natively in light, dark, and increased-contrast menu bars.
public enum MenuBarIconStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Classic finance dollar mark (the long-standing default).
    case classic
    /// A quiet, non-literal coin/disc mark for a subtler menu-bar presence.
    case minimal
    /// A dashboard/insight mark for users who prefer less money imagery.
    case chart
    /// The VaultPeek brand mark — a vault-dial glyph that ties the menu bar to
    /// the app icon. Unlike the other styles it has no SF Symbol equivalent, so
    /// the app renders it from a code-drawn monochrome template image (see
    /// `healthySymbolName` / `customGlyphToken`).
    case vault

    public static let defaultValue: MenuBarIconStyle = .classic

    /// Sentinel returned by `healthySymbolName` for styles that render from a
    /// custom template image rather than an SF Symbol. It is deliberately not a
    /// valid SF Symbol name; the app maps it to the drawn vault glyph and never
    /// passes it to `Image(systemName:)` / `NSImage(systemSymbolName:)`.
    public static let customGlyphToken = "vaultpeek.menubar.vault"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Dollar"
        case .minimal: return "Minimal"
        case .chart: return "Chart"
        case .vault: return "Vault"
        }
    }

    /// Whether this style renders from a code-drawn template image instead of an
    /// SF Symbol. Used by the UI to pick the right rendering path.
    public var usesCustomGlyph: Bool { self == .vault }

    /// SF Symbol used for the healthy/default state only — or `customGlyphToken`
    /// for styles drawn from a custom template image.
    public var healthySymbolName: String {
        switch self {
        case .classic: return "dollarsign.circle"
        case .minimal: return "centsign.circle"
        case .chart: return "chart.line.uptrend.xyaxis.circle"
        case .vault: return Self.customGlyphToken
        }
    }
}

/// Pure mapping for the menu-bar status chrome: the attention text shown
/// next to the glyph and the glyph itself.
///
/// The menu-bar alert treatment is reserved for `.blocking` states (server
/// offline, local auth failures, item errors). Advisory failures — a
/// transient action error while the server stays reachable — step down to
/// the warning glyph with no attention text, and are rendered inline in the
/// popover (status banner, attention queue) instead. State is always
/// carried by the glyph shape and text, never by color alone.
public struct MenuBarStatusPresentation: Equatable, Sendable {
    public let attentionText: String?
    public let symbolName: String
    public let severity: ErrorSeverity?

    public init(attentionText: String?, symbolName: String, severity: ErrorSeverity?) {
        self.attentionText = attentionText
        self.symbolName = symbolName
        self.severity = severity
    }

    public static func evaluate(
        isDemoMode: Bool,
        isInitialLoad: Bool = false,
        isLoading: Bool,
        serverConnected: Bool,
        errorMessage: String?,
        erroredItemCount: Int,
        needsLoginItemCount: Int,
        isSyncStale: Bool,
        hasEverSynced: Bool,
        financialAttentionText: String? = nil,
        iconStyle: MenuBarIconStyle = .classic
    ) -> MenuBarStatusPresentation {
        let connection = ServerConnectionPresentation.evaluate(
            isDemoMode: isDemoMode,
            isInitialLoad: isInitialLoad,
            isLoading: isLoading,
            serverConnected: serverConnected,
            errorMessage: errorMessage
        )

        return MenuBarStatusPresentation(
            attentionText: attentionText(
                isDemoMode: isDemoMode,
                connection: connection,
                erroredItemCount: erroredItemCount,
                needsLoginItemCount: needsLoginItemCount,
                isSyncStale: isSyncStale,
                hasEverSynced: hasEverSynced,
                financialAttentionText: financialAttentionText
            ),
            symbolName: symbolName(
                isDemoMode: isDemoMode,
                serverConnected: serverConnected,
                connection: connection,
                erroredItemCount: erroredItemCount,
                needsLoginItemCount: needsLoginItemCount,
                isSyncStale: isSyncStale,
                hasFinancialAttention: financialAttentionText != nil,
                iconStyle: iconStyle
            ),
            severity: severity(
                isDemoMode: isDemoMode,
                connection: connection,
                erroredItemCount: erroredItemCount,
                needsLoginItemCount: needsLoginItemCount,
                isSyncStale: isSyncStale,
                hasFinancialAttention: financialAttentionText != nil
            )
        )
    }

    private static func attentionText(
        isDemoMode: Bool,
        connection: ServerConnectionPresentation,
        erroredItemCount: Int,
        needsLoginItemCount: Int,
        isSyncStale: Bool,
        hasEverSynced: Bool,
        financialAttentionText: String?
    ) -> String? {
        if isDemoMode { return nil }
        if connection.issue == .localAuthMissing || connection.issue == .localAuthRejected {
            return "Auth"
        }
        if erroredItemCount > 0 { return "Error" }
        // Advisory failures never paint the menu bar: their attention text
        // stays inline in the popover. Blocking connection states keep
        // their text ("Offline").
        if connection.errorSeverity == .blocking, let attentionText = connection.attentionText {
            return attentionText
        }
        if needsLoginItemCount > 0 { return "Login" }
        if isSyncStale { return hasEverSynced ? "Stale" : "Never" }
        if let financialAttentionText { return financialAttentionText }
        return nil
    }

    private static func symbolName(
        isDemoMode: Bool,
        serverConnected: Bool,
        connection: ServerConnectionPresentation,
        erroredItemCount: Int,
        needsLoginItemCount: Int,
        isSyncStale: Bool,
        hasFinancialAttention: Bool,
        iconStyle: MenuBarIconStyle
    ) -> String {
        // State is carried by the symbol shape, not color: the menu bar
        // renders template-style monochrome, so degraded states swap the
        // glyph instead of tinting it. Only the healthy/default glyph below
        // honors the user's icon-style choice; the degraded ladder is fixed.
        if erroredItemCount > 0 { return "exclamationmark.octagon" }
        if !isDemoMode {
            switch connection.errorSeverity {
            case .blocking:
                // Offline keeps its distinct glyph; other blocking states
                // (local auth failures) read as hard failures.
                return connection.issue == .offline
                    ? "network.slash"
                    : "exclamationmark.octagon"
            case .advisory:
                // A recent action failed but the server is reachable: a
                // warning, not a dashboard-wide failure.
                return "exclamationmark.triangle"
            case nil:
                // Offline is checked before stale/login: when the server is
                // unreachable, isSyncStale is usually also true, so the
                // offline glyph must win to stay distinct.
                if !serverConnected { return "network.slash" }
            }
        }
        if needsLoginItemCount > 0 || isSyncStale {
            return "exclamationmark.triangle"
        }
        if hasFinancialAttention { return "exclamationmark.triangle" }
        return iconStyle.healthySymbolName
    }

    private static func severity(
        isDemoMode: Bool,
        connection: ServerConnectionPresentation,
        erroredItemCount: Int,
        needsLoginItemCount: Int,
        isSyncStale: Bool,
        hasFinancialAttention: Bool
    ) -> ErrorSeverity? {
        if isDemoMode { return erroredItemCount > 0 ? .blocking : nil }
        if erroredItemCount > 0 { return .blocking }
        if let connectionSeverity = connection.errorSeverity { return connectionSeverity }
        if needsLoginItemCount > 0 || isSyncStale || hasFinancialAttention { return .advisory }
        return nil
    }
}
