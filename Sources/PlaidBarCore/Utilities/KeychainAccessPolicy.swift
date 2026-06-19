import Foundation

/// Pure, framework-free description of how Plaid access-token Keychain items
/// must be protected. Extracting the decision here keeps it unit-testable in CI
/// (no live Keychain, no Security framework) while the server's
/// `PlaidTokenVault` maps these values onto the concrete `kSecAttr*` CFString
/// constants when it talks to the Keychain.
///
/// Hardening rationale (AND-572):
/// - **Device-only.** The token bytes must never leave this machine via iCloud
///   Keychain, so the accessibility class is one of the `ThisDeviceOnly`
///   variants and the item is explicitly **not** synchronizable.
/// - **Readable by a background daemon after first unlock.** `PlaidBarServer`
///   runs headless and must resolve the token to refresh data even while the
///   screen is locked, as long as the device has been unlocked once since boot.
///   `AfterFirstUnlockThisDeviceOnly` satisfies that; `WhenUnlockedThisDeviceOnly`
///   would fail reads on a locked screen and break background refresh.
public enum KeychainAccessPolicy: Sendable {
    /// Accessibility classes VaultPeek can choose between. The associated raw
    /// value mirrors Apple's documented `kSecAttrAccessible` string constants
    /// (see `Security/SecItemConstants.c`) so the decision can be asserted in a
    /// test without importing the Security framework.
    public enum Accessibility: String, Sendable, CaseIterable {
        /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — device-only,
        /// readable after the first post-boot unlock. The chosen policy.
        case afterFirstUnlockThisDeviceOnly = "cku"
        /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — device-only but
        /// unreadable while the screen is locked. Rejected: breaks headless
        /// background reads.
        case whenUnlockedThisDeviceOnly = "aku"
        /// `kSecAttrAccessibleAfterFirstUnlock` — readable after first unlock
        /// but **iCloud-syncable**. Rejected: tokens must stay on-device.
        case afterFirstUnlock = "ck"
        /// `kSecAttrAccessibleWhenUnlocked` — the Keychain default and
        /// iCloud-syncable. Rejected for the same reasons.
        case whenUnlocked = "ak"

        /// Whether this class keeps the item pinned to a single device (its
        /// name ends in `ThisDeviceOnly`). Apple forbids pairing a
        /// `ThisDeviceOnly` class with `kSecAttrSynchronizable = true`.
        public var isDeviceOnly: Bool {
            switch self {
            case .afterFirstUnlockThisDeviceOnly, .whenUnlockedThisDeviceOnly:
                true
            case .afterFirstUnlock, .whenUnlocked:
                false
            }
        }
    }

    /// The accessibility class applied to every Plaid access-token Keychain
    /// item, on both create and update.
    public static let accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly

    /// Plaid access-token items are never synchronized to iCloud Keychain. The
    /// item is added with `kSecAttrSynchronizable = false`; combined with a
    /// `ThisDeviceOnly` accessibility class this guarantees on-device storage.
    public static let isSynchronizable: Bool = false
}
