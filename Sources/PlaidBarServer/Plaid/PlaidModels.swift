import Foundation

// MARK: - Request Models

struct PlaidLinkTokenRequest: Encodable, Sendable {
    let clientId: String
    let secret: String
    let clientName: String
    let user: PlaidUser
    let products: [String]?
    let countryCodes: [String]
    let language: String
    let redirectUri: String
    let hostedLink: PlaidHostedLink?
    let accessToken: String?

    init(
        clientId: String,
        secret: String,
        clientName: String,
        user: PlaidUser,
        products: [String]? = nil,
        countryCodes: [String],
        language: String,
        redirectUri: String,
        hostedLink: PlaidHostedLink? = nil,
        accessToken: String? = nil
    ) {
        self.clientId = clientId
        self.secret = secret
        self.clientName = clientName
        self.user = user
        self.products = products
        self.countryCodes = countryCodes
        self.language = language
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
    let urlLifetimeSeconds: Int
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
        let sessionTokens = linkSessions?
            .flatMap { $0.results?.itemAddResults ?? [] }
            .map(\.publicToken) ?? []
        if !sessionTokens.isEmpty {
            return sessionTokens
        }
        if let itemAddResults = results?.itemAddResults, !itemAddResults.isEmpty {
            return itemAddResults.map(\.publicToken)
        }
        if let publicToken = onSuccess?.publicToken {
            return [publicToken]
        }
        return []
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
