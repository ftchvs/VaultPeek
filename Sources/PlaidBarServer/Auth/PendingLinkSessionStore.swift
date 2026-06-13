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
              currentDate.timeIntervalSince(session.createdAt) <= ttl,
              completionLeases[state] == nil
        else {
            return nil
        }
        completionLeases[state] = currentDate
        return session
    }

    func markPublicTokenResultStored(state: String) {
        purgeExpired()
        guard var session = sessions[state],
              now().timeIntervalSince(session.createdAt) <= ttl
        else {
            return
        }
        session.completedPublicTokenResultCount += 1
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
        completionLeases = completionLeases.filter { state, startedAt in
            activeStates.contains(state)
                && currentDate.timeIntervalSince(startedAt) <= completionLeaseTTL
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
    var completedPublicTokenResultCount: Int

    init(
        linkToken: String,
        updateItemId: String?,
        createdAt: Date,
        completedPublicTokenResultCount: Int = 0
    ) {
        self.linkToken = linkToken
        self.updateItemId = updateItemId
        self.createdAt = createdAt
        self.completedPublicTokenResultCount = completedPublicTokenResultCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkToken = try container.decode(String.self, forKey: .linkToken)
        updateItemId = try container.decodeIfPresent(String.self, forKey: .updateItemId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedPublicTokenResultCount = try container.decodeIfPresent(
            Int.self,
            forKey: .completedPublicTokenResultCount
        ) ?? 0
    }
}
