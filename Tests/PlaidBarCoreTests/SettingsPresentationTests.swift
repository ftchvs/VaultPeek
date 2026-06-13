import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Settings Presentation Tests")
struct SettingsPresentationTests {
    private let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    @Test("Local AI availability maps every state to a distinct icon")
    func localAIAvailabilityIconMapping() {
        #expect(LocalAIAvailabilityPresentation.iconName(for: .available) == "cpu.fill")
        #expect(LocalAIAvailabilityPresentation.iconName(for: .disabled) == "pause.circle.fill")
        #expect(LocalAIAvailabilityPresentation.iconName(for: .unavailable) == "exclamationmark.triangle.fill")
        #expect(LocalAIAvailabilityPresentation.iconName(for: .checking) == "hourglass")

        let iconNames: [String] = [.available, .disabled, .unavailable, .checking]
            .map(LocalAIAvailabilityPresentation.iconName(for:))
        #expect(Set(iconNames).count == iconNames.count, "States must stay distinguishable without color")
    }

    @Test("Local AI availability maps states to tones")
    func localAIAvailabilityToneMapping() {
        #expect(LocalAIAvailabilityPresentation.tone(for: .available) == .positive)
        #expect(LocalAIAvailabilityPresentation.tone(for: .disabled) == .secondary)
        #expect(LocalAIAvailabilityPresentation.tone(for: .unavailable) == .warning)
        #expect(LocalAIAvailabilityPresentation.tone(for: .checking) == .secondary)
    }

    @Test("Configured but unverified local AI is not presented as available")
    func configuredButUnverifiedLocalAIIsNotPresentedAsAvailable() {
        let availability = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )

        #expect(availability.state == .checking)
        #expect(availability.runtimeName == "ollama")
        #expect(availability.detail.contains("Verifying local runtime"))
        #expect(LocalAIAvailabilityPresentation.iconName(for: availability.state) == "hourglass")
        #expect(LocalAIAvailabilityPresentation.tone(for: availability.state) == .secondary)
    }

    @Test("Verified local AI uses the positive available presentation")
    func verifiedLocalAIUsesAvailablePresentation() {
        let base = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )
        let availability = LocalAIRuntimeResolution.resolved(
            base: base,
            usedModelOutput: true,
            fallbackReason: nil
        )

        #expect(availability.state == .available)
        #expect(availability.runtimeName == "ollama")
        #expect(availability.detail.contains("produced this summary on-device"))
        #expect(LocalAIAvailabilityPresentation.iconName(for: availability.state) == "cpu.fill")
        #expect(LocalAIAvailabilityPresentation.tone(for: availability.state) == .positive)
    }

    @Test("Local AI fallback remains unavailable after generation failure")
    func localAIFallbackAfterGenerationFailureIsUnavailable() {
        let base = LocalAIRuntimeResolution.configuredAvailability(
            rawValue: "ollama",
            hasWiredModel: true,
            endpointIsLocalhost: true
        )
        let availability = LocalAIRuntimeResolution.resolved(
            base: base,
            usedModelOutput: false,
            fallbackReason: .runtimeUnavailable
        )

        #expect(availability.state == .unavailable)
        #expect(availability.runtimeName == "ollama")
        #expect(availability.detail.contains("is not reachable on this Mac"))
        #expect(availability.detail.contains("did not call cloud AI"))
        #expect(LocalAIAvailabilityPresentation.tone(for: availability.state) == .warning)
    }

    @Test("Storage detail prefers the server path and abbreviates the home directory")
    func storageDetailPrefersServerPath() {
        let detail = LocalDataResetPresentation.storageDetail(
            serverStoragePath: "/Users/example/.vaultpeek",
            defaultResolvedDisplayPath: "~/.vaultpeek",
            homeDirectory: homeDirectory
        )

        #expect(detail == "Server: ~/.vaultpeek")
    }

    @Test("Storage detail keeps non-home server paths absolute")
    func storageDetailKeepsAbsoluteServerPath() {
        let detail = LocalDataResetPresentation.storageDetail(
            serverStoragePath: "/private/var/data/vaultpeek",
            defaultResolvedDisplayPath: "~/.vaultpeek",
            homeDirectory: homeDirectory
        )

        #expect(detail == "Server: /private/var/data/vaultpeek")
    }

    @Test("Storage detail falls back to the default resolved path")
    func storageDetailFallsBackToDefault() {
        let detail = LocalDataResetPresentation.storageDetail(
            serverStoragePath: nil,
            defaultResolvedDisplayPath: "~/.vaultpeek",
            homeDirectory: homeDirectory
        )

        #expect(detail == "Default: ~/.vaultpeek")
    }

    @Test("Reset message explains a no-op reset and keychain outcome")
    func resetMessageForNoRemovedEntries() {
        let result = LocalDataResetResult(
            directoryPath: "/Users/example/.vaultpeek",
            removedEntries: [],
            keychainTokensCleared: false
        )

        let message = LocalDataResetPresentation.successMessage(for: result, homeDirectory: homeDirectory)

        #expect(message == "No local data found. ~/.vaultpeek is ready. Keychain token entries were not cleared.")
    }

    @Test("Reset message pluralizes removed entries and asks for a server restart")
    func resetMessageForRemovedEntries() {
        let result = LocalDataResetResult(
            directoryPath: "/Users/example/.vaultpeek",
            removedEntries: ["plaidbar.sqlite", "transactions-cache.json"],
            keychainTokensCleared: true
        )

        let message = LocalDataResetPresentation.successMessage(for: result, homeDirectory: homeDirectory)

        #expect(message.contains("Removed 2 VaultPeek data items from ~/.vaultpeek."))
        #expect(message.contains("Keychain token entries were cleared when present."))
        #expect(message.contains("Restart the VaultPeek companion server."))
    }

    @Test("Reset message uses singular copy for one removed entry")
    func resetMessageForSingleRemovedEntry() {
        let result = LocalDataResetResult(
            directoryPath: "/Users/example/.vaultpeek",
            removedEntries: ["plaidbar.sqlite"],
            keychainTokensCleared: true
        )

        let message = LocalDataResetPresentation.successMessage(for: result, homeDirectory: homeDirectory)

        #expect(message.contains("Removed 1 VaultPeek data item from ~/.vaultpeek."))
    }

    @Test("Reset message reports preserved config entries")
    func resetMessageReportsPreservedEntries() {
        let result = LocalDataResetResult(
            directoryPath: "/Users/example/.vaultpeek",
            removedEntries: ["plaidbar.sqlite"],
            preservedEntries: ["server.conf"],
            keychainTokensCleared: true
        )

        let message = LocalDataResetPresentation.successMessage(for: result, homeDirectory: homeDirectory)

        #expect(message.contains("Left 1 config or unrelated item untouched."))
    }
}
