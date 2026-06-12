import Foundation
import PlaidBarCore

/// Names exactly which Plaid credential is missing so the setup-state 503
/// body and the server boot log can say "add PLAID_SECRET" instead of a
/// generic "credentials are not configured" (PR-016 T077).
///
/// Partial configuration is the confusing failure: one variable was exported
/// or written to `server.conf` and the other was forgotten, but a single
/// `credentialsConfigured` bool reports it identically to a fresh install.
/// The diagnosis carries variable *names* only — never credential values —
/// so its guidance is always safe to log and to return to the local client.
enum CredentialSetupDiagnosis: Sendable, Equatable, CaseIterable {
    case configured
    case missingClientId
    case missingSecret
    case missingBoth

    static func diagnose(clientId: String, secret: String) -> CredentialSetupDiagnosis {
        switch (clientId.isEmpty, secret.isEmpty) {
        case (false, false): .configured
        case (true, false): .missingClientId
        case (false, true): .missingSecret
        case (true, true): .missingBoth
        }
    }

    var isConfigured: Bool {
        self == .configured
    }

    var missingVariableNames: [String] {
        switch self {
        case .configured: []
        case .missingClientId: ["PLAID_CLIENT_ID"]
        case .missingSecret: ["PLAID_SECRET"]
        case .missingBoth: ["PLAID_CLIENT_ID", "PLAID_SECRET"]
        }
    }

    /// User-facing setup guidance for the 503 body and the boot log. `nil`
    /// once both credentials are present.
    ///
    /// The guidance is environment-scoped on purpose (PR-017 T081): sandbox
    /// copy never implies production readiness, and production copy is
    /// explicit that it connects real financial accounts and requires Plaid
    /// production approval.
    func setupGuidance(environment: PlaidEnvironment) -> String? {
        guard !isConfigured else { return nil }

        let missing = missingVariableNames.joined(separator: " and ")
        let lead = switch self {
        case .configured, .missingBoth:
            "Plaid \(environment.rawValue) credentials are not configured "
                + "on the VaultPeek companion server."
        case .missingClientId, .missingSecret:
            "The VaultPeek companion server is missing \(missing); "
                + "the other Plaid \(environment.rawValue) credential is set."
        }
        let fix = "Add \(missing) to server.conf; "
            + "the menu bar app restarts its bundled server automatically."
        let boundary = switch environment {
        case .sandbox:
            "Sandbox uses Plaid test institutions only and never touches real financial data."
        case .production:
            "Production connects real financial accounts and requires Plaid "
                + "production approval; sandbox credentials will not work."
        }
        return "\(lead) \(fix) \(boundary)"
    }
}
