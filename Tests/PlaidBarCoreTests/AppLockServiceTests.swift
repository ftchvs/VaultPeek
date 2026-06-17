@testable import PlaidBarCore
import Foundation
import Testing

@Suite("App Lock Service Tests")
@MainActor
struct AppLockServiceTests {
    @Test("Lock enabled state persists and enabling locks the service")
    func lockEnabledStatePersists() {
        let store = InMemoryAppLockSettingsStore(isLockEnabled: false)
        let service = AppLockService(settingsStore: store, authenticator: StubAppLockAuthenticator())

        #expect(service.isLockEnabled == false)
        #expect(service.state == .unlocked)

        service.setLockEnabled(true)

        #expect(store.isLockEnabled == true)
        #expect(service.isLockEnabled == true)
        #expect(service.state == .locked)
    }

    @Test("Unavailable authentication capability does not enable app lock")
    func unavailableCapabilityDoesNotEnableLock() {
        let store = InMemoryAppLockSettingsStore(isLockEnabled: false)
        let service = AppLockService(
            settingsStore: store,
            authenticator: StubAppLockAuthenticator(capability: .unavailable(.biometryNotEnrolled))
        )

        let capability = service.setLockEnabled(true)

        #expect(capability == .unavailable(.biometryNotEnrolled))
        #expect(store.isLockEnabled == false)
        #expect(service.isLockEnabled == false)
        #expect(service.state == .unlocked)
    }

    @Test("UserDefaults settings store persists enabled state")
    func userDefaultsSettingsStorePersistsEnabledState() throws {
        let suiteName = "AppLockServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "appLock.enabled"
        let store = UserDefaultsAppLockSettingsStore(defaults: defaults, storageKey: key)

        #expect(store.isLockEnabled == false)

        store.isLockEnabled = true

        let reloadedStore = UserDefaultsAppLockSettingsStore(defaults: defaults, storageKey: key)
        #expect(reloadedStore.isLockEnabled == true)
    }

    @Test("Successful authentication unlocks the service")
    func successfulAuthenticationUnlocks() async {
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: true),
            authenticator: StubAppLockAuthenticator(
                capability: .available(biometry: .touchID),
                result: .success
            )
        )

        let result = await service.authenticate(reason: "Unlock VaultPeek")

        #expect(result == .success)
        #expect(service.state == .unlocked)
    }

    @Test("Unavailable authentication returns typed reason and remains locked")
    func unavailableAuthenticationRemainsLocked() async {
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: true),
            authenticator: StubAppLockAuthenticator(capability: .unavailable(.passcodeNotSet))
        )

        let result = await service.authenticate(reason: "Unlock VaultPeek")

        #expect(result == .unavailable(.passcodeNotSet))
        #expect(service.state == .locked)
    }

    @Test("User cancellation returns cancellation and remains locked")
    func userCancellationRemainsLocked() async {
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: true),
            authenticator: StubAppLockAuthenticator(result: .cancelled)
        )

        let result = await service.authenticate(reason: "Unlock VaultPeek")

        #expect(result == .cancelled)
        #expect(service.state == .locked)
    }

    @Test("Failed authentication returns failure and remains locked")
    func failedAuthenticationRemainsLocked() async {
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: true),
            authenticator: StubAppLockAuthenticator(result: .failure(.authenticationFailed))
        )

        let result = await service.authenticate(reason: "Unlock VaultPeek")

        #expect(result == .failure(.authenticationFailed))
        #expect(service.state == .locked)
    }

    @Test("Disabled lock treats authenticate as already unlocked")
    func disabledLockSkipsAuthentication() async {
        let authenticator = StubAppLockAuthenticator(result: .failure(.systemError("should not be called")))
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: false),
            authenticator: authenticator
        )

        let result = await service.authenticate(reason: "Unlock VaultPeek")

        #expect(result == .success)
        #expect(service.state == .unlocked)
        #expect(authenticator.authenticateCallCount == 0)
    }

    @Test("Enabling and disabling through setLockEnabled keeps the persisted flag coherent")
    func setLockEnabledIsSingleSourceOfTruth() throws {
        // Mirrors AppState.setAppLockEnabled, which routes all enabled-flag
        // writes through the service so the in-memory state and the persisted
        // UserDefaults key never desync (AND-462). A second service constructed
        // from the same store must read back exactly what the first one wrote.
        let suiteName = "AppLockServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = UserDefaultsAppLockSettingsStore.defaultStorageKey
        let store = UserDefaultsAppLockSettingsStore(defaults: defaults, storageKey: key)
        let service = AppLockService(
            settingsStore: store,
            authenticator: StubAppLockAuthenticator(capability: .available(biometry: .touchID))
        )

        service.setLockEnabled(true)

        #expect(service.isLockEnabled == true)
        #expect(service.state == .locked)
        #expect(store.isLockEnabled == true)
        #expect(defaults.bool(forKey: key) == true)
        // A fresh service derived from the same persisted store agrees.
        let reloadedEnabled = AppLockService(
            settingsStore: UserDefaultsAppLockSettingsStore(defaults: defaults, storageKey: key),
            authenticator: StubAppLockAuthenticator(capability: .available(biometry: .touchID))
        )
        #expect(reloadedEnabled.isLockEnabled == true)
        #expect(reloadedEnabled.isLocked == true)

        service.setLockEnabled(false)

        #expect(service.isLockEnabled == false)
        #expect(service.state == .unlocked)
        #expect(store.isLockEnabled == false)
        #expect(defaults.bool(forKey: key) == false)
        let reloadedDisabled = AppLockService(
            settingsStore: UserDefaultsAppLockSettingsStore(defaults: defaults, storageKey: key),
            authenticator: StubAppLockAuthenticator(capability: .available(biometry: .touchID))
        )
        #expect(reloadedDisabled.isLockEnabled == false)
        #expect(reloadedDisabled.isLocked == false)
    }

    @Test("Overlapping authentication attempts share one system prompt")
    func overlappingAuthenticationAttemptsCoalesce() async {
        let authenticator = StubAppLockAuthenticator(result: .success, delayNanoseconds: 50_000_000)
        let service = AppLockService(
            settingsStore: InMemoryAppLockSettingsStore(isLockEnabled: true),
            authenticator: authenticator
        )

        async let first = service.authenticate(reason: "Unlock VaultPeek")
        async let second = service.authenticate(reason: "Unlock VaultPeek")

        let results = await [first, second]

        #expect(results == [.success, .success])
        #expect(authenticator.authenticateCallCount == 1)
        #expect(service.state == .unlocked)
    }
}

@MainActor
private final class StubAppLockAuthenticator: AppLockAuthenticating {
    var capability: AppLockCapability
    var result: AppLockAuthenticationResult
    var authenticateCallCount = 0
    var delayNanoseconds: UInt64

    init(
        capability: AppLockCapability = .available(biometry: .none),
        result: AppLockAuthenticationResult = .success,
        delayNanoseconds: UInt64 = 0
    ) {
        self.capability = capability
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func authenticationCapability() -> AppLockCapability {
        capability
    }

    func authenticate(reason: String) async -> AppLockAuthenticationResult {
        authenticateCallCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result
    }
}

private final class InMemoryAppLockSettingsStore: AppLockSettingsStoring {
    var isLockEnabled: Bool

    init(isLockEnabled: Bool) {
        self.isLockEnabled = isLockEnabled
    }
}
