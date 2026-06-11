import Foundation

public enum OnboardingPreflightRowState: Sendable, Equatable {
    case ready
    case blocked
    case unknown
    case informational
}

public struct OnboardingPreflightRow: Sendable, Equatable, Identifiable {
    public let title: String
    public let value: String
    public let iconName: String
    public let state: OnboardingPreflightRowState
    public let accessibilityHint: String

    public var id: String { title }

    public init(
        title: String,
        value: String,
        iconName: String,
        state: OnboardingPreflightRowState,
        accessibilityHint: String
    ) {
        self.title = title
        self.value = value
        self.iconName = iconName
        self.state = state
        self.accessibilityHint = accessibilityHint
    }
}

/// Display-safe readiness evaluation for the setup preflight panel: whether
/// Plaid Link may open for the chosen environment, the recovery hint when it
/// may not, and the per-row readiness states. Plaid Link must stay blocked
/// (fail fast) while the server is offline, running in a different mode than
/// the one being set up, or missing Plaid credentials.
public struct OnboardingPreflight: Sendable, Equatable {
    public let isReady: Bool
    public let hint: String
    public let rows: [OnboardingPreflightRow]

    public static func evaluate(
        expectedEnvironment: PlaidEnvironment,
        serverConnected: Bool,
        serverEnvironment: PlaidEnvironment?,
        credentialsConfigured: Bool?,
        modeText: String,
        credentialsText: String,
        storageText: String,
        linkedItemCount: Int
    ) -> OnboardingPreflight {
        let modeMatches = serverEnvironment == expectedEnvironment
        let credentialsReady = credentialsConfigured == true
        let isReady = serverConnected && modeMatches && credentialsReady

        let serverRow = OnboardingPreflightRow(
            title: "Server",
            value: serverConnected ? "Connected" : "Offline",
            iconName: "server.rack",
            state: serverConnected ? .ready : .blocked,
            accessibilityHint: serverConnected
                ? "Server is ready."
                : "Start PlaidBarServer, then check again."
        )

        let modeState: OnboardingPreflightRowState = serverConnected
            ? (modeMatches ? .ready : .blocked)
            : .unknown
        let modeRow = OnboardingPreflightRow(
            title: "Mode",
            value: serverConnected ? modeText : "Unknown",
            iconName: expectedEnvironment == .production ? "lock.shield" : "testtube.2",
            state: modeState,
            accessibilityHint: accessibilityHint(
                for: modeState,
                title: "Mode",
                blockedHint: "Restart PlaidBarServer in \(expectedEnvironment.rawValue) mode."
            )
        )

        let credentialsState: OnboardingPreflightRowState = serverConnected
            ? (credentialsReady ? .ready : .blocked)
            : .unknown
        let credentialsRow = OnboardingPreflightRow(
            title: "Credentials",
            value: credentialsText,
            iconName: "key",
            state: credentialsState,
            accessibilityHint: accessibilityHint(
                for: credentialsState,
                title: "Credentials",
                blockedHint: "Add Plaid credentials to the local server environment."
            )
        )

        let storageState: OnboardingPreflightRowState = serverConnected ? .ready : .unknown
        let storageRow = OnboardingPreflightRow(
            title: "Storage",
            value: storageText,
            iconName: "internaldrive",
            state: storageState,
            accessibilityHint: accessibilityHint(
                for: storageState,
                title: "Storage",
                blockedHint: "Storage needs attention before Plaid Link can open."
            )
        )

        let linkedItemsRow = OnboardingPreflightRow(
            title: "Linked items",
            value: "\(linkedItemCount)",
            iconName: "link",
            state: .informational,
            accessibilityHint: "Linked items is informational."
        )

        return OnboardingPreflight(
            isReady: isReady,
            hint: hint(
                expectedEnvironment: expectedEnvironment,
                serverConnected: serverConnected,
                modeMatches: modeMatches,
                credentialsReady: credentialsReady
            ),
            rows: [serverRow, modeRow, credentialsRow, storageRow, linkedItemsRow]
        )
    }

    private static func hint(
        expectedEnvironment: PlaidEnvironment,
        serverConnected: Bool,
        modeMatches: Bool,
        credentialsReady: Bool
    ) -> String {
        guard serverConnected else {
            return expectedEnvironment == .sandbox
                ? "Start PlaidBarServer with --sandbox, then Check Again."
                : "Start PlaidBarServer with production credentials, then Check Again."
        }

        guard modeMatches else {
            return expectedEnvironment == .sandbox
                ? "The running server is not in sandbox mode."
                : "The running server is not in production mode."
        }

        guard credentialsReady else {
            return "Add Plaid credentials to the local server environment before connecting."
        }

        return "Ready to open Plaid Link in your browser."
    }

    private static func accessibilityHint(
        for state: OnboardingPreflightRowState,
        title: String,
        blockedHint: String
    ) -> String {
        switch state {
        case .ready:
            "\(title) is ready."
        case .blocked:
            blockedHint
        case .unknown:
            "Start PlaidBarServer, then check again."
        case .informational:
            "\(title) is informational."
        }
    }
}
