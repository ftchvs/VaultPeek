import Foundation

/// Pure, Sendable presenter that groups per-item connection statuses into three
/// buckets — Connected / Reconnect-needed / Provider-outage (AND-488). Each
/// bucket carries an SF Symbol + text label so meaning is never color-alone, and
/// whether a reconnect action applies (outage rows are non-actionable).
public enum ConnectionHealthStrip {
    public enum State: String, Sendable, Equatable {
        case connected
        case reconnectNeeded
        case providerOutage
    }

    public struct Bucket: Sendable, Equatable, Identifiable {
        public let state: State
        public let count: Int
        public let label: String
        public let detail: String
        public let iconName: String
        public let isActionable: Bool

        public var id: String { state.rawValue }

        public init(
            state: State,
            count: Int,
            label: String,
            detail: String,
            iconName: String,
            isActionable: Bool
        ) {
            self.state = state
            self.count = count
            self.label = label
            self.detail = detail
            self.iconName = iconName
            self.isActionable = isActionable
        }
    }

    public struct Result: Sendable, Equatable {
        public let buckets: [Bucket]

        public init(buckets: [Bucket]) {
            self.buckets = buckets
        }

        /// True when any non-outage degraded item exists (a real reconnect target).
        public var hasActionableWork: Bool {
            buckets.contains { $0.state == .reconnectNeeded && $0.count > 0 }
        }

        public var hasProviderOutage: Bool {
            buckets.contains { $0.state == .providerOutage && $0.count > 0 }
        }
    }

    /// Classifies a single status into one of the three buckets.
    private static func bucketState(for status: ItemConnectionStatus) -> State {
        if status.isProviderOutage { return .providerOutage }
        if status.isDegraded { return .reconnectNeeded }
        return .connected
    }

    /// Groups statuses into the three buckets, omitting empty buckets. The result
    /// preserves a stable Connected → Reconnect-needed → Provider-outage order.
    ///
    /// - Parameter isMasked: when Privacy Mask / App Lock is active, the bucket
    ///   labels drop the exact count and read as the status word alone
    ///   ("Connected" / "Needs attention" / "Temporarily unavailable"). The
    ///   recovery *status* (and its reconnect affordance) is preserved — never
    ///   hidden — while the exact item count, which is behavioral metadata gated
    ///   like the sidebar badges (AND-483), is withheld.
    public static func evaluate(_ statuses: [ItemStatus], isMasked: Bool = false) -> Result {
        let counts = statuses.reduce(into: [State: Int]()) { partial, item in
            partial[bucketState(for: item.status), default: 0] += 1
        }

        var buckets: [Bucket] = []
        if let connected = counts[.connected], connected > 0 {
            buckets.append(
                Bucket(
                    state: .connected,
                    count: connected,
                    label: isMasked ? "Connected" : "\(connected) connected",
                    detail: "Syncing normally.",
                    iconName: "checkmark.circle",
                    isActionable: false
                )
            )
        }
        if let reconnect = counts[.reconnectNeeded], reconnect > 0 {
            buckets.append(
                Bucket(
                    state: .reconnectNeeded,
                    count: reconnect,
                    label: isMasked ? "Needs attention" : "\(reconnect) need\(reconnect == 1 ? "s" : "") attention",
                    detail: "Reconnect to keep these accounts in sync.",
                    iconName: "exclamationmark.triangle",
                    isActionable: true
                )
            )
        }
        if let outage = counts[.providerOutage], outage > 0 {
            buckets.append(
                Bucket(
                    state: .providerOutage,
                    count: outage,
                    label: isMasked ? "Temporarily unavailable" : "\(outage) temporarily unavailable",
                    detail: "Your bank or Plaid is down. We'll retry automatically — no action needed.",
                    iconName: "wifi.exclamationmark",
                    isActionable: false
                )
            )
        }
        return Result(buckets: buckets)
    }
}
