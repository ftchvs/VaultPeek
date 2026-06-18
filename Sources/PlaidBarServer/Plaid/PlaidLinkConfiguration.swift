import Foundation
import PlaidBarCore

struct PlaidLinkConfiguration: Equatable, Sendable {
    static let defaultHostedLinkLifetimeSeconds = 30 * 60

    let clientName: String
    let products: [String]
    let countryCodes: [String]
    let language: String
    let webhookURL: String?
    let redirectURI: String?
    let hostedLinkLifetimeSeconds: Int
    let hostedLinkIsMobileApp: Bool

    static func resolved(from environment: [String: String]) throws -> PlaidLinkConfiguration {
        let config = PlaidLinkConfiguration(
            clientName: PlaidBarConstants.appName,
            // New links request `liabilities` so credit cards return real APR /
            // statement / due-date data. Existing items keep whatever scope they
            // were linked under (new-links-only rollout — AND-493); the server
            // tolerates the missing scope per item. Override via PLAID_LINK_PRODUCTS.
            products: listValue(environment["PLAID_LINK_PRODUCTS"]) ?? ["transactions", "liabilities"],
            countryCodes: listValue(environment["PLAID_LINK_COUNTRY_CODES"]) ?? ["US"],
            language: environment["PLAID_LINK_LANGUAGE"]?.trimmedLinkConfigValue ?? "en",
            webhookURL: environment["PLAID_LINK_WEBHOOK_URL"]?.trimmedLinkConfigValue,
            redirectURI: environment["PLAID_LINK_REDIRECT_URI"]?.trimmedLinkConfigValue,
            hostedLinkLifetimeSeconds: try intValue(
                environment["PLAID_HOSTED_LINK_LIFETIME_SECONDS"],
                name: "PLAID_HOSTED_LINK_LIFETIME_SECONDS"
            ) ?? defaultHostedLinkLifetimeSeconds,
            hostedLinkIsMobileApp: try boolValue(
                environment["PLAID_HOSTED_LINK_IS_MOBILE_APP"],
                name: "PLAID_HOSTED_LINK_IS_MOBILE_APP"
            ) ?? false
        )
        try config.validate()
        return config
    }

    func createRequest(
        clientId: String,
        secret: String,
        clientUserId: String,
        completionRedirectURI: String
    ) throws -> PlaidLinkTokenRequest {
        try validate()
        return PlaidLinkTokenRequest(
            clientId: clientId,
            secret: secret,
            clientName: clientName,
            user: .init(clientUserId: clientUserId),
            products: products,
            countryCodes: countryCodes,
            language: language,
            webhook: webhookURL,
            redirectUri: redirectURI,
            hostedLink: hostedLink(completionRedirectURI: completionRedirectURI)
        )
    }

    func updateRequest(
        clientId: String,
        secret: String,
        clientUserId: String,
        accessToken: String,
        completionRedirectURI: String
    ) throws -> PlaidLinkTokenRequest {
        try validate()
        return PlaidLinkTokenRequest(
            clientId: clientId,
            secret: secret,
            clientName: clientName,
            user: .init(clientUserId: clientUserId),
            countryCodes: countryCodes,
            language: language,
            webhook: webhookURL,
            redirectUri: redirectURI,
            hostedLink: hostedLink(completionRedirectURI: completionRedirectURI),
            accessToken: accessToken
        )
    }

    func validate() throws {
        let trimmedClientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientName.isEmpty else {
            throw PlaidLinkConfigurationError.invalidClientName("client_name must not be empty")
        }
        guard trimmedClientName.count <= 30 else {
            throw PlaidLinkConfigurationError.invalidClientName("client_name must be 30 characters or fewer")
        }
        guard !products.isEmpty else {
            throw PlaidLinkConfigurationError.invalidProducts("products must contain at least one Plaid product")
        }
        guard !countryCodes.isEmpty else {
            throw PlaidLinkConfigurationError.invalidCountryCodes("country_codes must contain at least one country")
        }
        guard supportedLanguages.contains(language) else {
            throw PlaidLinkConfigurationError.invalidLanguage(language)
        }
        guard hostedLinkLifetimeSeconds > 0 else {
            throw PlaidLinkConfigurationError.invalidHostedLinkLifetime(hostedLinkLifetimeSeconds)
        }
        try validateProducts()
        try validateCountryCodes()
    }

    private func hostedLink(completionRedirectURI: String) -> PlaidHostedLink {
        PlaidHostedLink(
            completionRedirectUri: completionRedirectURI,
            isMobileApp: hostedLinkIsMobileApp ? true : nil,
            urlLifetimeSeconds: hostedLinkLifetimeSeconds
        )
    }

    private func validateProducts() throws {
        let unsupported = products.filter { !supportedProducts.contains($0) }
        guard unsupported.isEmpty else {
            throw PlaidLinkConfigurationError.invalidProducts(
                "Unsupported Plaid products: \(unsupported.joined(separator: ", "))"
            )
        }
        // The refresh path unconditionally calls /transactions/sync, so an Item
        // linked without the transactions product would error on every sync and
        // surface as a broken dashboard. Require it rather than silently linking
        // Items the app cannot use.
        guard products.contains("transactions") else {
            throw PlaidLinkConfigurationError.invalidProducts(
                "products must include \"transactions\"; VaultPeek syncs transactions for every linked Item"
            )
        }
    }

    private func validateCountryCodes() throws {
        let unsupportedCountries = countryCodes.filter { !supportedCountryCodes.contains($0) }
        guard unsupportedCountries.isEmpty else {
            throw PlaidLinkConfigurationError.invalidCountryCodes(
                "Unsupported Plaid country_codes: \(unsupportedCountries.joined(separator: ", "))"
            )
        }
    }

    private static func listValue(_ rawValue: String?) -> [String]? {
        guard let rawValue = rawValue?.trimmedLinkConfigValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private static func intValue(_ rawValue: String?, name: String) throws -> Int? {
        guard let rawValue = rawValue?.trimmedLinkConfigValue else { return nil }
        guard let value = Int(rawValue) else {
            throw PlaidLinkConfigurationError.invalidEnvironmentValue(name, rawValue)
        }
        return value
    }

    private static func boolValue(_ rawValue: String?, name: String) throws -> Bool? {
        guard let rawValue = rawValue?.trimmedLinkConfigValue else { return nil }
        switch rawValue.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default:
            throw PlaidLinkConfigurationError.invalidEnvironmentValue(name, rawValue)
        }
    }
}

enum PlaidLinkConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidClientName(String)
    case invalidProducts(String)
    case invalidCountryCodes(String)
    case invalidLanguage(String)
    case invalidHostedLinkLifetime(Int)
    case invalidEnvironmentValue(String, String)

    var errorDescription: String? {
        switch self {
        case let .invalidClientName(message),
             let .invalidProducts(message),
             let .invalidCountryCodes(message):
            message
        case let .invalidLanguage(language):
            "Unsupported Plaid Link language: \(language)"
        case let .invalidHostedLinkLifetime(seconds):
            "Invalid Hosted Link lifetime \(seconds): must be greater than zero"
        case let .invalidEnvironmentValue(name, value):
            "Invalid value for \(name): \(value)"
        }
    }
}

private let supportedLanguages: Set<String> = [
    "da", "nl", "en", "et", "fr", "de", "hi", "it", "lv", "lt", "no", "pl", "pt", "ro", "es", "sv", "vi",
]

private let supportedCountryCodes: Set<String> = [
    "US", "GB", "ES", "NL", "FR", "IE", "CA", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT",
    "BE", "AT", "FI",
]

private let supportedProducts: Set<String> = [
    "assets", "auth", "beacon", "employment", "identity", "income_verification", "identity_verification",
    "investments", "investments_auth", "liabilities", "payment_initiation", "protect_transactions",
    "standing_orders", "signal", "statements", "transactions", "transfer", "cra_base_report",
    "cra_income_insights", "cra_cashflow_insights", "cra_lend_score", "cra_partner_insights",
    "cra_network_insights", "cra_monitoring", "layer", "protect_linked_bank",
]

private extension String {
    var trimmedLinkConfigValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
