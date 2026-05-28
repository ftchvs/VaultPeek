import Foundation

actor PendingLinkSessionStore {
    private let ttl: TimeInterval
    private let storageURL: URL?
    private let now: @Sendable () -> Date
    private var sessions: [String: PendingLinkSession] = [:]

    init(
        ttl: TimeInterval = 30 * 60,
        storageURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.storageURL = storageURL
        self.now = now
        self.sessions = Self.loadSessions(from: storageURL)
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
        persist()
    }

    func consume(state: String) -> PendingLinkSession? {
        purgeExpired()
        guard let session = sessions.removeValue(forKey: state),
              now().timeIntervalSince(session.createdAt) <= ttl
        else {
            return nil
        }
        persist()
        return session
    }

    private func purgeExpired() {
        let currentDate = now()
        let activeSessions = sessions.filter { _, session in
            currentDate.timeIntervalSince(session.createdAt) <= ttl
        }
        guard activeSessions.count != sessions.count else { return }
        sessions = activeSessions
        persist()
    }

    private func persist() {
        guard let storageURL else { return }

        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: storageURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storageURL.path
            )
        } catch {
            // Pending Link sessions are short-lived; failing closed is better
            // than failing Link token creation because persistence is unavailable.
        }
    }

    private static func loadSessions(from storageURL: URL?) -> [String: PendingLinkSession] {
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL),
              let sessions = try? JSONDecoder().decode([String: PendingLinkSession].self, from: data)
        else {
            return [:]
        }
        return sessions
    }
}

struct PendingLinkSession: Codable, Sendable {
    let linkToken: String
    let updateItemId: String?
    let createdAt: Date
}
