import Foundation

public struct GlanceSnapshot: Codable, Sendable, Equatable {
    public enum ChangeDirection: String, Codable, Sendable {
        case up
        case down
        case flat

        public var glyph: String {
            switch self {
            case .up: "▲"
            case .down: "▼"
            case .flat: "■"
            }
        }

        public static func evaluate(_ value: Double) -> ChangeDirection {
            if value > 0 { return .up }
            if value < 0 { return .down }
            return .flat
        }
    }

    public static let appGroupIdentifier = "group.com.ftchvs.PlaidBar"
    public static let filename = "glance-snapshot.json"
    public static let commandFilename = "glance-command.json"
    public static let deepLinkURL = "vaultpeek://dashboard"

    public let netWorth: Double
    public let todayChange: Double
    public let updatedAt: Date
    public let sparkline: [Double]
    public let isDemo: Bool

    public var changeDirection: ChangeDirection {
        ChangeDirection.evaluate(todayChange)
    }

    public var signedChangeText: String {
        if todayChange > 0 {
            return "+\(Formatters.currency(todayChange, format: .compact))"
        }
        return Formatters.currency(todayChange, format: .compact)
    }

    public var accessibilitySummary: String {
        let source = isDemo ? "Demo data. " : ""
        return "\(source)Net worth \(Formatters.currency(netWorth, format: .full)). Today's change \(changeDirection.glyph) \(signedChangeText)."
    }

    public func hasSameDisplayContent(as other: GlanceSnapshot) -> Bool {
        netWorth == other.netWorth &&
            todayChange == other.todayChange &&
            sparkline == other.sparkline &&
            isDemo == other.isDemo
    }

    public init(
        netWorth: Double,
        todayChange: Double,
        updatedAt: Date,
        sparkline: [Double],
        isDemo: Bool
    ) {
        self.netWorth = netWorth
        self.todayChange = todayChange
        self.updatedAt = updatedAt
        self.sparkline = sparkline
        self.isDemo = isDemo
    }

    public static func make(
        netWorth: Double,
        balanceHistory: [BalanceSnapshot],
        updatedAt: Date,
        isDemo: Bool,
        calendar: Calendar = .current
    ) -> GlanceSnapshot {
        GlanceSnapshot(
            netWorth: netWorth,
            todayChange: todayChange(from: balanceHistory, currentNetWorth: netWorth, now: updatedAt, calendar: calendar),
            updatedAt: updatedAt,
            sparkline: normalizedSparkline(from: balanceHistory, currentNetWorth: netWorth),
            isDemo: isDemo
        )
    }

    public static func placeholder(updatedAt: Date = Date()) -> GlanceSnapshot {
        GlanceSnapshot(
            netWorth: 0,
            todayChange: 0,
            updatedAt: updatedAt,
            sparkline: [],
            isDemo: false
        )
    }

    private static func todayChange(
        from history: [BalanceSnapshot],
        currentNetWorth: Double,
        now: Date,
        calendar: Calendar
    ) -> Double {
        let sorted = history.sorted { $0.date < $1.date }
        guard let prior = sorted.last(where: { !calendar.isDate($0.date, inSameDayAs: now) }) else {
            return 0
        }
        return currentNetWorth - prior.balance
    }

    private static func normalizedSparkline(
        from history: [BalanceSnapshot],
        currentNetWorth: Double,
        maximumPointCount: Int = 30
    ) -> [Double] {
        var values = history
            .sorted { $0.date < $1.date }
            .suffix(maximumPointCount)
            .map(\.balance)
        if values.last != currentNetWorth {
            values.append(currentNetWorth)
        }
        return AccountSparkline.normalize(values)
    }
}

public enum GlanceCommand: String, Codable, Sendable, Equatable {
    case refreshBalances
}

public struct GlanceCommandRequest: Codable, Sendable, Equatable {
    public let command: GlanceCommand
    public let requestedAt: Date

    public init(command: GlanceCommand, requestedAt: Date) {
        self.command = command
        self.requestedAt = requestedAt
    }
}

public actor GlanceSnapshotWriteDebouncer {
    private let delay: Duration
    private var pendingTask: Task<Void, Never>?

    public init(delay: Duration = .milliseconds(400)) {
        self.delay = delay
    }

    deinit {
        pendingTask?.cancel()
    }

    public func schedule(
        _ snapshot: GlanceSnapshot,
        operation: @escaping @Sendable (GlanceSnapshot) async -> Void
    ) {
        pendingTask?.cancel()
        pendingTask = Task { [delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await operation(snapshot)
        }
    }

    public func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

public enum GlanceSnapshotStore {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func snapshotDirectory(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = GlanceSnapshot.appGroupIdentifier
    ) -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }
        return LocalDataStore.storageDirectoryURL()
    }

    public static func snapshotURL(directory: URL) -> URL {
        directory.appendingPathComponent(GlanceSnapshot.filename)
    }

    public static func commandURL(directory: URL) -> URL {
        directory.appendingPathComponent(GlanceSnapshot.commandFilename)
    }

    public static func save(
        _ snapshot: GlanceSnapshot,
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        try write(snapshot, to: snapshotURL(directory: directory), fileManager: fileManager)
    }

    @discardableResult
    public static func saveIfChanged(
        _ snapshot: GlanceSnapshot,
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws -> Bool {
        let url = snapshotURL(directory: directory)
        if fileManager.fileExists(atPath: url.path),
           let existing = try? load(directory: directory, fileManager: fileManager),
           existing.hasSameDisplayContent(as: snapshot) {
            return false
        }
        try write(snapshot, to: url, fileManager: fileManager)
        return true
    }

    public static func load(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws -> GlanceSnapshot {
        let data = try Data(contentsOf: snapshotURL(directory: directory))
        return try decoder.decode(GlanceSnapshot.self, from: data)
    }

    public static func clear(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        let url = snapshotURL(directory: directory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public static func saveCommand(
        _ request: GlanceCommandRequest,
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        try write(request, to: commandURL(directory: directory), fileManager: fileManager)
    }

    public static func consumeCommand(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws -> GlanceCommandRequest? {
        let url = commandURL(directory: directory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        try fileManager.removeItem(at: url)
        return try decoder.decode(GlanceCommandRequest.self, from: data)
    }

    private static func write(_ value: some Encodable, to url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
        #if os(macOS)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}
