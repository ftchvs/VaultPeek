import Foundation

actor PendingLinkSessionStore {
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var sessions: [String: PendingLinkSession] = [:]

    init(ttl: TimeInterval = 30 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    func issueState() -> String {
        purgeExpired()
        return UUID().uuidString.lowercased()
    }

    func save(state: String, linkToken: String, updateItemId: String? = nil) {
        purgeExpired()
        sessions[state] = PendingLinkSession(
            linkToken: linkToken,
            updateItemId: updateItemId,
            createdAt: now()
        )
    }

    func consume(state: String) -> PendingLinkSession? {
        purgeExpired()
        guard let session = sessions.removeValue(forKey: state),
              now().timeIntervalSince(session.createdAt) <= ttl
        else {
            return nil
        }
        return session
    }

    private func purgeExpired() {
        let currentDate = now()
        sessions = sessions.filter { _, session in
            currentDate.timeIntervalSince(session.createdAt) <= ttl
        }
    }
}

struct PendingLinkSession: Sendable {
    let linkToken: String
    let updateItemId: String?
    let createdAt: Date
}
