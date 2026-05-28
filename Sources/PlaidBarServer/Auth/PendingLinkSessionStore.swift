import Foundation
#if canImport(Darwin)
import Darwin
#endif

actor PendingLinkSessionStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

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
}
