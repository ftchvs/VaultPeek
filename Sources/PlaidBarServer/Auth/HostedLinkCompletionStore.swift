import Foundation

actor HostedLinkCompletionStore {
    private var recordsById: [String: HostedLinkCompletionRecord] = [:]
    private var idByState: [String: String] = [:]
    private var idByLinkToken: [String: String] = [:]
    private var idByLinkSessionId: [String: String] = [:]

    @discardableResult
    func record(_ record: HostedLinkCompletionRecord) -> HostedLinkCompletionRecord {
        purgeEmptyIndexes()
        if let existing = existingRecord(for: record) {
            return existing
        }

        let id = record.identity
        recordsById[id] = record
        if let state = record.state {
            idByState[state] = id
        }
        if let linkToken = record.linkToken {
            idByLinkToken[linkToken] = id
        }
        if let linkSessionId = record.linkSessionId {
            idByLinkSessionId[linkSessionId] = id
        }
        return record
    }

    func completion(
        state: String?,
        linkToken: String?,
        linkSessionId: String? = nil
    ) -> HostedLinkCompletionRecord? {
        if let state, let id = idByState[state] {
            return recordsById[id]
        }
        if let linkToken, let id = idByLinkToken[linkToken] {
            return recordsById[id]
        }
        if let linkSessionId, let id = idByLinkSessionId[linkSessionId] {
            return recordsById[id]
        }
        return nil
    }

    private func existingRecord(for record: HostedLinkCompletionRecord) -> HostedLinkCompletionRecord? {
        completion(
            state: record.state,
            linkToken: record.linkToken,
            linkSessionId: record.linkSessionId
        )
    }

    private func purgeEmptyIndexes() {
        idByState = idByState.filter { recordsById[$0.value] != nil }
        idByLinkToken = idByLinkToken.filter { recordsById[$0.value] != nil }
        idByLinkSessionId = idByLinkSessionId.filter { recordsById[$0.value] != nil }
    }
}

struct HostedLinkCompletionRecord: Equatable, Sendable {
    let state: String?
    let linkToken: String?
    let linkSessionId: String?
    let status: HostedLinkCompletionStatus
    let receivedAt: Date

    init(
        state: String?,
        linkToken: String?,
        linkSessionId: String?,
        status: HostedLinkCompletionStatus,
        receivedAt: Date = Date()
    ) {
        self.state = state?.trimmedCompletionIdentifier
        self.linkToken = linkToken?.trimmedCompletionIdentifier
        self.linkSessionId = linkSessionId?.trimmedCompletionIdentifier
        self.status = status
        self.receivedAt = receivedAt
    }

    var identity: String {
        if let linkSessionId {
            return "link-session:\(linkSessionId)"
        }
        if let linkToken {
            return "link-token:\(linkToken)"
        }
        if let state {
            return "state:\(state)"
        }
        return "received:\(receivedAt.timeIntervalSince1970)"
    }
}

enum HostedLinkCompletionStatus: String, Codable, Equatable, Sendable {
    case success
    case userExit
    case expired
    case retryableProviderFailure
    case providerFailure
}

private extension String {
    var trimmedCompletionIdentifier: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
