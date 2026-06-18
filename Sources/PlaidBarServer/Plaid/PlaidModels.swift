import Foundation

// MARK: - Request Models

struct PlaidLinkTokenRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let clientName: String
    let user: PlaidUser
    let products: [String]?
    /// Products initialized at Link only when the chosen institution supports
    /// them — unlike `products`, these never filter institutions out of Link.
    let optionalProducts: [String]?
    let countryCodes: [String]
    let language: String
    let webhook: String?
    /// Top-level OAuth `redirect_uri`. Deliberately omitted (left `nil`) for the
    /// Hosted Link flow: Hosted Link uses `hosted_link.completion_redirect_uri`
    /// instead, and sending both makes Plaid reject the request with
    /// `INVALID_FIELD` ("OAuth redirect URI must be configured in the developer
    /// dashboard"). The synthesized encoder omits this key entirely when `nil`.
    let redirectUri: String?
    let hostedLink: PlaidHostedLink?
    let accessToken: String?

    init(
        clientId: String,
        secret: String,
        clientName: String,
        user: PlaidUser,
        products: [String]? = nil,
        optionalProducts: [String]? = nil,
        countryCodes: [String],
        language: String,
        webhook: String? = nil,
        redirectUri: String? = nil,
        hostedLink: PlaidHostedLink? = nil,
        accessToken: String? = nil
    ) {
        self.clientId = clientId
        self.secret = secret
        self.clientName = clientName
        self.user = user
        self.products = products
        self.optionalProducts = optionalProducts
        self.countryCodes = countryCodes
        self.language = language
        self.webhook = webhook
        self.redirectUri = redirectUri
        self.hostedLink = hostedLink
        self.accessToken = accessToken
    }

    struct PlaidUser: Encodable, Sendable {
        let clientUserId: String
    }
}

struct PlaidHostedLink: Encodable, Sendable {
    let completionRedirectUri: String
    let isMobileApp: Bool?
    let urlLifetimeSeconds: Int

    init(
        completionRedirectUri: String,
        isMobileApp: Bool? = nil,
        urlLifetimeSeconds: Int
    ) {
        self.completionRedirectUri = completionRedirectUri
        self.isMobileApp = isMobileApp
        self.urlLifetimeSeconds = urlLifetimeSeconds
    }
}

struct PlaidLinkTokenGetRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let linkToken: String
}

struct PlaidTokenExchangeRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let publicToken: String
}

struct PlaidAuthenticatedRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let accessToken: String
}

struct PlaidTransactionsSyncRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let accessToken: String
    let cursor: String
    let count: Int
}

// MARK: - Response Models

struct PlaidBaseResponse: Decodable, Sendable {
    let requestId: String?
}

struct PlaidErrorResponse: Decodable, Sendable {
    let errorType: String?
    let errorCode: String?
    let errorMessage: String?
    let displayMessage: String?
}

struct PlaidLinkTokenResponse: Decodable, Sendable {
    let linkToken: String
    let expiration: String?
    let requestId: String?
    let hostedLinkUrl: String?
}

struct PlaidLinkTokenGetResponse: Decodable, Sendable {
    let linkToken: String?
    let linkSessions: [PlaidLinkSession]?
    let onSuccess: PlaidLinkSuccess?
    let results: PlaidLinkResults?

    var publicTokens: [String] {
        publicTokenResults.map(\.publicToken)
    }

    var publicTokenResults: [PlaidPublicTokenResult] {
        let sessionTokens = linkSessions?
            .flatMap { $0.results?.itemAddResults ?? [] }
            .map(PlaidPublicTokenResult.init) ?? []
        if !sessionTokens.isEmpty {
            return sessionTokens
        }
        if let itemAddResults = results?.itemAddResults, !itemAddResults.isEmpty {
            return itemAddResults.map(PlaidPublicTokenResult.init)
        }
        if let publicToken = onSuccess?.publicToken {
            return [
                PlaidPublicTokenResult(
                    publicToken: publicToken,
                    institution: onSuccess?.metadata?.institution
                ),
            ]
        }
        return []
    }
}

struct PlaidPublicTokenResult: Sendable {
    let publicToken: String
    let institution: PlaidLinkInstitution?

    init(publicToken: String, institution: PlaidLinkInstitution?) {
        self.publicToken = publicToken
        self.institution = institution
    }

    init(itemAddResult: PlaidLinkItemAddResult) {
        publicToken = itemAddResult.publicToken
        institution = itemAddResult.institution
    }
}

struct PlaidLinkSession: Decodable, Sendable {
    let linkSessionId: String?
    let results: PlaidLinkResults?
}

struct PlaidLinkResults: Decodable, Sendable {
    let itemAddResults: [PlaidLinkItemAddResult]?
}

struct PlaidLinkItemAddResult: Decodable, Sendable {
    let publicToken: String
    let institution: PlaidLinkInstitution?
}

struct PlaidLinkSuccess: Decodable, Sendable {
    let publicToken: String?
    let metadata: PlaidLinkSuccessMetadata?
}

struct PlaidLinkSuccessMetadata: Decodable, Sendable {
    let institution: PlaidLinkInstitution?
}

struct PlaidLinkInstitution: Decodable, Sendable {
    let name: String?
    let institutionId: String?
}

struct PlaidTokenExchangeResponse: Decodable, Sendable {
    let accessToken: String
    let itemId: String
    let requestId: String?
}

struct PlaidAccountsResponse: Decodable, Sendable {
    let accounts: [PlaidAccount]
    let item: PlaidItem?
    let requestId: String?
}

struct PlaidAccount: Decodable, Sendable {
    let accountId: String
    let balances: PlaidBalances
    let mask: String?
    let name: String
    let officialName: String?
    let type: String
    let subtype: String?
}

struct PlaidBalances: Decodable, Sendable {
    let available: Double?
    let current: Double?
    let limit: Double?
    let isoCurrencyCode: String?
    let unofficialCurrencyCode: String?
}

struct PlaidItem: Decodable, Sendable {
    let itemId: String
    let institutionId: String?
    let availableProducts: [String]?
    let billedProducts: [String]?
}

// MARK: - Liabilities (/liabilities/get)

struct PlaidLiabilitiesResponse: Decodable, Sendable {
    let liabilities: PlaidLiabilities?
    let requestId: String?
}

struct PlaidLiabilities: Decodable, Sendable {
    let credit: [PlaidCreditLiability]?
}

struct PlaidCreditLiability: Decodable, Sendable {
    let accountId: String?
    let aprs: [PlaidApr]?
    let isOverdue: Bool?
    let lastPaymentAmount: Double?
    let lastPaymentDate: String?
    let lastStatementIssueDate: String?
    let lastStatementBalance: Double?
    let minimumPaymentAmount: Double?
    let nextPaymentDueDate: String?
}

struct PlaidApr: Decodable, Sendable {
    let aprPercentage: Double?
    let aprType: String?
    let balanceSubjectToApr: Double?
    let interestChargeAmount: Double?
}

struct PlaidTransactionsSyncResponse: Decodable, Sendable {
    let added: [PlaidTransaction]
    let modified: [PlaidTransaction]
    let removed: [PlaidRemovedTransaction]
    let nextCursor: String
    let hasMore: Bool
    let requestId: String?
}

struct PlaidTransaction: Decodable, Sendable {
    let transactionId: String
    let accountId: String
    let amount: Double
    let date: String
    let name: String
    let merchantName: String?
    let pending: Bool
    // Present only on posted transactions that were previously pending; links
    // back to the now-removed pending transaction id. Decoded from
    // `pending_transaction_id` via the client's convertFromSnakeCase strategy.
    // `var … = nil` (not `let`) so it stays in Decodable synthesis while the
    // synthesized memberwise init keeps it optional for call sites that omit it.
    var pendingTransactionId: String? = nil
    let isoCurrencyCode: String?
    let personalFinanceCategory: PlaidCategory?
}

struct PlaidCategory: Decodable, Sendable {
    let primary: String
    let detailed: String?
    let confidenceLevel: String?
}

struct PlaidRemovedTransaction: Decodable, Sendable {
    let transactionId: String
}
