import Foundation
#if canImport(Darwin)
import Darwin
#endif

actor PendingLinkSessionStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    private let ttl: TimeInterval
    private let completionLeaseTTL: TimeInterval
    private let storageURL: URL?
    private let now: @Sendable () -> Date
    private var sessions: [String: PendingLinkSession] = [:]
    private var completionLeases: [String: Date] = [:]

    init(
        ttl: TimeInterval = 30 * 60,
        completionLeaseTTL: TimeInterval = 60,
        storageURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.completionLeaseTTL = completionLeaseTTL
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
        completionLeases.removeValue(forKey: state)
        persist()
    }

    func beginCompletion(state: String) -> PendingLinkSession? {
        purgeExpired()
        let currentDate = now()
        guard let session = sessions[state],
              currentDate.timeIntervalSince(session.createdAt) <= ttl
        else {
            return nil
        }
        // A live lease means another handler is mid-flight: refuse, preserving
        // single-flight. The lease is reclaimable only once it is older than
        // `completionLeaseTTL`, i.e. the original handler is presumed dead (it
        // would otherwise have called releaseCompletion/consume). This bounds
        // recovery without dropping a fresh in-flight lease — unlike purging by
        // TTL, which could race a still-running handler.
        if let leaseStartedAt = completionLeases[state],
           currentDate.timeIntervalSince(leaseStartedAt) <= completionLeaseTTL {
            return nil
        }
        completionLeases[state] = currentDate
        return session
    }

    /// Records that the result with this stable `identity` has been consumed
    /// (its single-use Plaid public token exchanged), so a retry never replays
    /// it. `identity` is a token-free fingerprint (see `resultIdentity`), never
    /// the raw public token — pending-session storage holds no Plaid tokens.
    func markResultCompleted(state: String, identity: String) {
        purgeExpired()
        guard var session = sessions[state],
              now().timeIntervalSince(session.createdAt) <= ttl
        else {
            return
        }
        session.completedResultIdentities.insert(identity)
        sessions[state] = session
        persist()
    }

    func releaseCompletion(state: String) {
        completionLeases.removeValue(forKey: state)
    }

    func consume(state: String) -> PendingLinkSession? {
        purgeExpired()
        guard let session = sessions.removeValue(forKey: state),
              now().timeIntervalSince(session.createdAt) <= ttl
        else {
            return nil
        }
        completionLeases.removeValue(forKey: state)
        persist()
        return session
    }

    private func purgeExpired() {
        let currentDate = now()
        let activeSessions = sessions.filter { _, session in
            currentDate.timeIntervalSince(session.createdAt) <= ttl
        }
        let activeStates = Set(activeSessions.keys)
        // A completion lease lives as long as its session: it is cleared only by
        // `releaseCompletion`/`consume`, or when the session itself expires by
        // the (much longer) session TTL. The short `completionLeaseTTL` is NOT a
        // purge trigger — expiring a lease while the original handler is still
        // doing Plaid/Keychain/SQLite work would let a concurrent retry pass the
        // single-flight guard and double-process the same Hosted Link results.
        // It survives only as a clamp in `beginCompletion` for a presumed-dead
        // handler (process restart loses in-memory leases anyway).
        completionLeases = completionLeases.filter { state, _ in
            activeStates.contains(state)
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
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: Self.directoryPermissions],
                ofItemAtPath: directory.path
            )
            let data = try JSONEncoder().encode(sessions)
            try Self.writePrivateFile(data, to: storageURL)
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
        try? FileManager.default.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: storageURL.deletingLastPathComponent().path
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: storageURL.path
        )
        return sessions
    }

    private static func writePrivateFile(_ data: Data, to url: URL) throws {
        #if canImport(Darwin)
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var shouldRemoveTemporaryFile = true
        defer {
            close(descriptor)
            if shouldRemoveTemporaryFile {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var bytesWritten = 0
            while bytesWritten < buffer.count {
                let result = write(
                    descriptor,
                    baseAddress.advanced(by: bytesWritten),
                    buffer.count - bytesWritten
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard result > 0 else {
                    throw POSIXError(.EIO)
                }
                bytesWritten += result
            }
        }

        guard rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldRemoveTemporaryFile = false
        #else
        try data.write(to: url, options: [.atomic])
        #endif

        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: url.path
        )
    }
}

struct PendingLinkSession: Codable, Sendable {
    let linkToken: String
    let updateItemId: String?
    let createdAt: Date
    /// Stable, token-free identities of results already consumed (their
    /// single-use public token exchanged). Tracking by identity — not an ordinal
    /// count — means a retry skips exactly the already-stored results even if
    /// Plaid returns the multi-item results in a different order.
    var completedResultIdentities: Set<String>

    init(
        linkToken: String,
        updateItemId: String?,
        createdAt: Date,
        completedResultIdentities: Set<String> = []
    ) {
        self.linkToken = linkToken
        self.updateItemId = updateItemId
        self.createdAt = createdAt
        self.completedResultIdentities = completedResultIdentities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkToken = try container.decode(String.self, forKey: .linkToken)
        updateItemId = try container.decodeIfPresent(String.self, forKey: .updateItemId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Backward compatible: sessions persisted by an earlier build carry no
        // identity set (and the legacy ordinal count is intentionally dropped —
        // an in-flight migration at most re-attempts a still-pending result,
        // which is safe because a genuinely consumed token re-exchange fails
        // closed rather than duplicating).
        completedResultIdentities = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .completedResultIdentities
        ) ?? []
    }
}
