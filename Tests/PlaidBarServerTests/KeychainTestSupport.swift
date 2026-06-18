import Foundation
import PlaidBarCore
@testable import PlaidBarServer

// Shared isolation for the Keychain-backed server tests.
//
// `swift test` exercises `PlaidTokenVault`, which writes real generic-password
// items to the macOS **login keychain**. On an ad-hoc-signed dev build the
// signature changes every build, so each run re-triggers the "PlaidBarServer
// wants to use … in your keychain" auth prompt, and interrupted runs leave
// stale items behind (AND-481).
//
// Two guards remove that friction without weakening the safety invariants:
//   1. Env gate — the writes only happen when `PLAIDBAR_TEST_KEYCHAIN` is set,
//      so the default local loop never touches the keychain. CI sets it (the
//      notarized/stable CI signature does not prompt) to keep the coverage.
//   2. Isolated service — when they do run, items live under a dedicated test
//      service, never the production `PlaidBar.PlaidAccessToken` service, and a
//      sweep purges that service so leftovers from an interrupted run self-heal.

/// True only when `PLAIDBAR_TEST_KEYCHAIN` is present in the environment.
let keychainTestsEnabled = ProcessInfo.processInfo.environment["PLAIDBAR_TEST_KEYCHAIN"] != nil

/// Dedicated, stable Keychain service for tests. Stable (not per-run) so the
/// sweep below can find and delete items orphaned by an earlier interrupted run.
let keychainTestService = "\(LocalDataStore.plaidAccessTokenKeychainService).test"

/// Deletes every item stored under the test service. Idempotent and cheap; safe
/// to call when the keychain holds no test items. Never touches the production
/// service, so a developer's real linked-item tokens are never affected.
func purgeTestKeychain() {
    try? PlaidTokenVault.deleteOrphanedTokens(referencedItemIds: [], service: keychainTestService)
}

/// Gate for `.enabled(if:)` on every Keychain-backed test. Returns `false`
/// **without writing anything** when the env gate is off, so the default
/// `swift test` run skips these tests entirely. When the gate is on, it first
/// sweeps stale test items, then verifies the keychain accepts a write under
/// the isolated test service.
let keychainTestSupportAvailable: Bool = {
    guard keychainTestsEnabled else { return false }
    purgeTestKeychain()
    let itemId = "keychain_probe_\(UUID().uuidString)"
    do {
        let stored = try PlaidTokenVault.store(
            accessToken: "probe-token",
            itemId: itemId,
            service: keychainTestService
        )
        try PlaidTokenVault.delete(storedToken: stored, fallbackItemId: itemId, service: keychainTestService)
        return true
    } catch {
        return false
    }
}()
