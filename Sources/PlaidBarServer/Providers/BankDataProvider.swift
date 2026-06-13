import Foundation
import PlaidBarCore

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case plaid
    case teller
    case fixture
}

enum ProviderSyncStrategy: String, Codable, Sendable {
    case cursor
    case windowedRescan
}

enum ProviderBalanceCost: String, Codable, Sendable {
    case includedWithSync
    case billedPerCall
}

struct ProviderCapabilities: Equatable, Sendable {
    let accountTypes: [AccountType]
    let syncStrategy: ProviderSyncStrategy
    let balanceCost: ProviderBalanceCost
    let providesCreditLimit: Bool
    let supportsHostedLink: Bool
    let supportsUpdateModeRepair: Bool
    let multipleConnectionsPerLinkSession: Bool
    let geography: Set<String>

    static let plaid = ProviderCapabilities(
        accountTypes: [.depository, .credit, .loan, .investment, .other],
        syncStrategy: .cursor,
        balanceCost: .includedWithSync,
        providesCreditLimit: true,
        supportsHostedLink: true,
        supportsUpdateModeRepair: true,
        multipleConnectionsPerLinkSession: true,
        geography: ["US"]
    )

    static let teller = ProviderCapabilities(
        accountTypes: [.depository, .credit],
        syncStrategy: .windowedRescan,
        balanceCost: .billedPerCall,
        providesCreditLimit: false,
        supportsHostedLink: false,
        supportsUpdateModeRepair: true,
        multipleConnectionsPerLinkSession: false,
        geography: ["US"]
    )

    static let fixture = ProviderCapabilities(
        accountTypes: [.depository, .credit, .loan, .investment, .other],
        syncStrategy: .cursor,
        balanceCost: .includedWithSync,
        providesCreditLimit: true,
        supportsHostedLink: false,
        supportsUpdateModeRepair: false,
        multipleConnectionsPerLinkSession: false,
        geography: ["US"]
    )
}

struct ProviderLinkRequest: Sendable {
    let completionRedirectURI: String
    let products: [String]
}

struct ProviderLinkSession: Sendable {
    let sessionID: String
    let url: String
}

struct ProviderLinkCompletion: Sendable {
    let sessionID: String
    let verifier: String
}

struct ProviderConnectionCredential: Sendable {
    let storedToken: String
}

struct ProviderNewConnection: Sendable {
    let providerConnectionID: String
    let credential: ProviderConnectionCredential
    let institutionID: String?
    let institutionName: String?
}

struct ProviderSyncState: Sendable {
    let rawValue: String?
}

struct ProviderSyncDelta: Sendable {
    let added: [TransactionDTO]
    let modified: [TransactionDTO]
    let removed: [String]
    let hasMore: Bool
    let nextState: ProviderSyncState
}

protocol BankDataProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }

    func connectInstitution(_ request: ProviderLinkRequest) async throws -> ProviderLinkSession
    func completeConnect(_ completion: ProviderLinkCompletion) async throws -> [ProviderNewConnection]
    func listAccounts(credential: ProviderConnectionCredential) async throws -> [AccountDTO]
    func getBalances(credential: ProviderConnectionCredential) async throws -> [AccountDTO]
    func syncTransactions(
        credential: ProviderConnectionCredential,
        state: ProviderSyncState
    ) async throws -> ProviderSyncDelta
    func refreshConnection(
        credential: ProviderConnectionCredential,
        request: ProviderLinkRequest
    ) async throws -> ProviderLinkSession
    func disconnectInstitution(credential: ProviderConnectionCredential) async throws
}
