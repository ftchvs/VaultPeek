import Foundation

/// Pure presenter for the Attention Queue's visible and spoken count copy.
///
/// The queue count is behavioral financial metadata: it can disclose how many
/// accounts, alerts, or recovery states are active. When Privacy Mask / App Lock
/// is engaged, preserve the qualitative state while withholding exact counts
/// from both visible text and VoiceOver.
public enum AttentionQueueCountPresentation {
    public struct Result: Equatable, Sendable {
        public let visibleText: String
        public let accessibilityLabel: String

        public init(visibleText: String, accessibilityLabel: String) {
            self.visibleText = visibleText
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public static func evaluate(
        title: String,
        rowCount: Int,
        maximumRowCount: Int,
        isMasked: Bool
    ) -> Result {
        if isMasked {
            // Only the *count* is withheld — the rows themselves stay visible
            // and VoiceOver-readable, so the copy must not claim the items are
            // hidden.
            return Result(
                visibleText: "Active",
                accessibilityLabel: "\(title), item count hidden while Privacy Mask is on"
            )
        }

        return Result(
            visibleText: "\(rowCount)/\(maximumRowCount)",
            accessibilityLabel: "\(title), \(rowCount) item\(rowCount == 1 ? "" : "s")"
        )
    }
}
