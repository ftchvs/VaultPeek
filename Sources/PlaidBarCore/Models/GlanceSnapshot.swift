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
    /// True when App Lock / Privacy Mask was active at build time, so the figures
    /// above were zeroed/cleared before they ever reached disk. Mirrors
    /// ``FinanceSnapshot/isMasked``: defense in depth so a masked snapshot is
    /// value-free *in the file*, not merely dotted at read time. The widget reads
    /// this so it can self-mask even if the sibling ``FinanceSnapshot`` is missing
    /// or stale (AND-517).
    public let isRedacted: Bool

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
            updatedAt == other.updatedAt &&
            sparkline == other.sparkline &&
            isDemo == other.isDemo &&
            isRedacted == other.isRedacted
    }

    public init(
        netWorth: Double,
        todayChange: Double,
        updatedAt: Date,
        sparkline: [Double],
        isDemo: Bool,
        isRedacted: Bool = false
    ) {
        self.netWorth = netWorth
        self.todayChange = todayChange
        self.updatedAt = updatedAt
        self.sparkline = sparkline
        self.isDemo = isDemo
        self.isRedacted = isRedacted
    }

    // Decode `isRedacted` defensively: a snapshot written by an older build (no
    // `isRedacted` key) decodes as `false`, so upgrades never spuriously treat a
    // real snapshot as redacted.
    private enum CodingKeys: String, CodingKey {
        case netWorth, todayChange, updatedAt, sparkline, isDemo, isRedacted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        netWorth = try container.decode(Double.self, forKey: .netWorth)
        todayChange = try container.decode(Double.self, forKey: .todayChange)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sparkline = try container.decode([Double].self, forKey: .sparkline)
        isDemo = try container.decode(Bool.self, forKey: .isDemo)
        isRedacted = try container.decodeIfPresent(Bool.self, forKey: .isRedacted) ?? false
    }

    public static func make(
        netWorth: Double,
        balanceHistory: [BalanceSnapshot],
        updatedAt: Date,
        isDemo: Bool,
        isMasked: Bool = false,
        calendar: Calendar = .current
    ) -> GlanceSnapshot {
        let snapshot = GlanceSnapshot(
            netWorth: netWorth,
            todayChange: todayChange(from: balanceHistory, currentNetWorth: netWorth, now: updatedAt, calendar: calendar),
            updatedAt: updatedAt,
            sparkline: normalizedSparkline(from: balanceHistory, currentNetWorth: netWorth),
            isDemo: isDemo
        )
        return isMasked ? snapshot.redacted() : snapshot
    }

    /// Returns a copy with every real financial value cleared — net worth, today's
    /// change, and the sparkline are zeroed/emptied and `isRedacted` is set — while
    /// preserving the non-sensitive `updatedAt`/`isDemo` metadata. Used when App
    /// Lock or Privacy Mask is active so the on-disk `glance-snapshot.json` carries
    /// no balances for a widget or Control Center surface to leak (AND-517).
    public func redacted() -> GlanceSnapshot {
        GlanceSnapshot(
            netWorth: 0,
            todayChange: 0,
            updatedAt: updatedAt,
            sparkline: [],
            isDemo: isDemo,
            isRedacted: true
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

/// Abstracts the delay step of ``GlanceSnapshotWriteDebouncer`` so tests can
/// drive coalescing deterministically instead of racing a real debounce window.
/// Production uses ``SystemDebounceScheduler``, a thin `Task.sleep` wrapper, so
/// the live debounce behavior is unchanged.
public protocol DebounceScheduler: Sendable {
    /// Suspends for `duration`, throwing `CancellationError` if the surrounding
    /// task is cancelled while waiting.
    func sleep(for duration: Duration) async throws
}

/// The production scheduler: waits on the real clock via `Task.sleep`.
public struct SystemDebounceScheduler: DebounceScheduler {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public actor GlanceSnapshotWriteDebouncer {
    private let delay: Duration
    private let scheduler: any DebounceScheduler
    private var pendingTask: Task<Void, Never>?

    public init(
        delay: Duration = .milliseconds(400),
        scheduler: any DebounceScheduler = SystemDebounceScheduler()
    ) {
        self.delay = delay
        self.scheduler = scheduler
    }

    deinit {
        pendingTask?.cancel()
    }

    public func schedule(
        _ snapshot: GlanceSnapshot,
        operation: @escaping @Sendable (GlanceSnapshot) async -> Void
    ) {
        pendingTask?.cancel()
        pendingTask = Task { [delay, scheduler] in
            do {
                try await scheduler.sleep(for: delay)
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

    /// Rewrites an already-persisted glance snapshot into its value-free form.
    ///
    /// Control Center / Focus-filter privacy-mask intents can run while the app is
    /// backgrounded, so they cannot rebuild the real widget snapshot from app
    /// state. They can, however, make the existing on-disk snapshot safe by
    /// zeroing every figure before WidgetKit reloads its timelines. Missing files
    /// are a no-op so first-run/setup systems can call this defensively.
    public static func redactIfAvailable(
        directory: URL = snapshotDirectory(),
        fileManager: FileManager = .default
    ) throws {
        let url = snapshotURL(directory: directory)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let snapshot = try load(directory: directory, fileManager: fileManager)
        guard !snapshot.isRedacted else { return }
        try save(snapshot.redacted(), directory: directory, fileManager: fileManager)
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
