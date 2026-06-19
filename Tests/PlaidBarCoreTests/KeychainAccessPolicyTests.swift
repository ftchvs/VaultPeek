import Foundation
@testable import PlaidBarCore
import Testing

/// Pure-decision coverage for `KeychainAccessPolicy` (AND-572). The real
/// Keychain round-trip is environment-gated and skipped in CI (see
/// `TokenStorageSafetyTests`), so this suite locks the *choice* of
/// accessibility class and synchronizability — the part that actually hardens
/// Plaid access-token storage — with no live Keychain required.
@Suite("Keychain access policy")
struct KeychainAccessPolicyTests {
    @Test("Plaid tokens use AfterFirstUnlockThisDeviceOnly")
    func usesAfterFirstUnlockThisDeviceOnly() {
        #expect(KeychainAccessPolicy.accessibility == .afterFirstUnlockThisDeviceOnly)
        // Raw value mirrors Apple's documented kSecAttrAccessible string ("cku").
        #expect(KeychainAccessPolicy.accessibility.rawValue == "cku")
    }

    @Test("Chosen class is device-only so tokens never leave the machine")
    func chosenClassIsDeviceOnly() {
        #expect(KeychainAccessPolicy.accessibility.isDeviceOnly)
    }

    @Test("Plaid tokens are never marked synchronizable")
    func tokensAreNotSynchronizable() {
        #expect(KeychainAccessPolicy.isSynchronizable == false)
    }

    @Test("Device-only accessibility and synchronizable=true are never combined")
    func deviceOnlyAndSynchronizableAreMutuallyExclusive() {
        // Apple forbids pairing a `ThisDeviceOnly` accessibility class with
        // kSecAttrSynchronizable=true; the policy must not produce that pair.
        if KeychainAccessPolicy.accessibility.isDeviceOnly {
            #expect(KeychainAccessPolicy.isSynchronizable == false)
        }
    }

    @Test("Accessibility classification stays consistent across all cases")
    func accessibilityClassificationIsConsistent() {
        for accessibility in KeychainAccessPolicy.Accessibility.allCases {
            let endsInThisDeviceOnly = String(describing: accessibility)
                .lowercased()
                .contains("thisdeviceonly")
            #expect(accessibility.isDeviceOnly == endsInThisDeviceOnly)
        }
    }

    @Test("Rejected classes are distinct from the chosen one")
    func rejectedClassesDifferFromChosen() {
        let chosen = KeychainAccessPolicy.accessibility
        let rejected: [KeychainAccessPolicy.Accessibility] = [
            .whenUnlockedThisDeviceOnly,
            .afterFirstUnlock,
            .whenUnlocked,
        ]
        for accessibility in rejected {
            #expect(accessibility != chosen)
        }
        // The two iCloud-syncable classes must not be device-only.
        #expect(!KeychainAccessPolicy.Accessibility.afterFirstUnlock.isDeviceOnly)
        #expect(!KeychainAccessPolicy.Accessibility.whenUnlocked.isDeviceOnly)
    }
}
