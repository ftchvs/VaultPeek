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
}

@MainActor
private final class StubAppLockAuthenticator: AppLockAuthenticating {
    var capability: AppLockCapability
    var result: AppLockAuthenticationResult
    var authenticateCallCount = 0

    init(
        capability: AppLockCapability = .available(biometry: .none),
        result: AppLockAuthenticationResult = .success
    ) {
        self.capability = capability
        self.result = result
    }

    func authenticationCapability() -> AppLockCapability {
        capability
    }

    func authenticate(reason: String) async -> AppLockAuthenticationResult {
        authenticateCallCount += 1
        return result
    }
}

private final class InMemoryAppLockSettingsStore: AppLockSettingsStoring {
    var isLockEnabled: Bool

    init(isLockEnabled: Bool) {
        self.isLockEnabled = isLockEnabled
    }
}
