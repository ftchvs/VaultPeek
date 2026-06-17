import Foundation

/// Pure presentation policy for the Privacy & Security settings controls.
///
/// Keeps the App Lock toggle's availability, biometry wording, and explanatory
/// copy out of the SwiftUI view so the rules are `Sendable` and unit-testable.
/// The view passes in the live `AppLockCapability` (from `AppLockService`) and
/// renders the returned control state verbatim.
public struct AppLockSettingsControl: Sendable, Equatable {
    /// Whether the App Lock toggle should accept user input. When biometric /
    /// device authentication is unavailable, the toggle is disabled and the
    /// explanatory caption tells the user why.
    public let isToggleEnabled: Bool
    /// Caption shown beneath the App Lock toggle explaining the current state.
    public let explanation: String

    public init(isToggleEnabled: Bool, explanation: String) {
        self.isToggleEnabled = isToggleEnabled
        self.explanation = explanation
    }

    /// Human-readable name for a biometry type, used in the toggle caption.
    public static func biometryName(_ biometry: AppLockBiometryType) -> String {
        switch biometry {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        case .none, .unknown: return "your Mac password"
        }
    }

    /// Short reason string for why authentication is unavailable.
    public static func unavailableReason(_ reason: AppLockUnavailableReason) -> String {
        switch reason {
        case .passcodeNotSet:
            return "Set a login password or Touch ID in System Settings to use App Lock."
        case .biometryNotAvailable:
            return "This Mac does not support biometric unlock. Set a login password to use App Lock."
        case .biometryNotEnrolled:
            return "No biometric identities are enrolled. Add Touch ID in System Settings to use App Lock."
        case .biometryLockout:
            return "Biometric unlock is temporarily locked. Use your Mac password, then try again."
        case .notInteractive:
            return "Authentication is not available right now. Try again in a moment."
        case .unknown(let description):
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Authentication is unavailable right now."
                : trimmed
        }
    }

    /// Resolves the toggle's enabled state and caption from the live capability.
    /// `isEnabled` is the current persisted App Lock preference, which still
    /// controls the explanatory copy when authentication is available.
    public static func resolve(
        capability: AppLockCapability,
        isEnabled: Bool
    ) -> AppLockSettingsControl {
        switch capability {
        case .available(let biometry):
            let name = biometryName(biometry)
            let explanation = isEnabled
                ? "VaultPeek locks and requires \(name) to reveal balances. Locks on launch and when VaultPeek loses focus."
                : "Require \(name) to reveal balances. VaultPeek locks on launch and when it loses focus."
            return AppLockSettingsControl(isToggleEnabled: true, explanation: explanation)
        case .unavailable(let reason):
            return AppLockSettingsControl(
                isToggleEnabled: false,
                explanation: unavailableReason(reason)
            )
        }
    }
}
