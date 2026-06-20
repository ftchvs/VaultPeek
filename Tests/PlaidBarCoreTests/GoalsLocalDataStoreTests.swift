import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Goals local-first persistence (AND-606)")
struct GoalsLocalDataStoreTests {
    private func tempDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".vaultpeek", isDirectory: true)
    }

    @Test("Loading goals from a missing file returns empty (first run)")
    func loadMissingReturnsEmpty() throws {
        let directory = tempDirectory()
        let goals = try LocalDataStore.loadGoals(from: directory)
        #expect(goals.isEmpty)
    }

    @Test("Saved goals round-trip and survive a reload (relaunch)")
    func saveLoadRoundTrip() throws {
        let directory = tempDirectory()
        let goals = [
            Goal(name: "Emergency", targetAmount: 5000, contributedAmount: 1200, createdAt: Date(timeIntervalSince1970: 1_000)),
            Goal(name: "Vacation", targetAmount: 2500, targetDate: Date(timeIntervalSince1970: 2_000_000), linkedCategory: .travel, contributedAmount: 600, createdAt: Date(timeIntervalSince1970: 2_000)),
        ]

        try LocalDataStore.saveGoals(goals, to: directory)
        let reloaded = try LocalDataStore.loadGoals(from: directory)

        #expect(Set(reloaded) == Set(goals), "Every saved goal must survive a relaunch")
    }

    @Test("Saving sorts goals by creation date on disk for stable diffs")
    func savedOrderIsStable() throws {
        let directory = tempDirectory()
        let later = Goal(name: "Later", targetAmount: 100, createdAt: Date(timeIntervalSince1970: 9_000))
        let earlier = Goal(name: "Earlier", targetAmount: 100, createdAt: Date(timeIntervalSince1970: 1_000))

        try LocalDataStore.saveGoals([later, earlier], to: directory)
        let reloaded = try LocalDataStore.loadGoals(from: directory)

        #expect(reloaded.map(\.name) == ["Earlier", "Later"])
    }

    @Test("The goals file is written with private (0600) permissions")
    func privatePermissions() throws {
        let directory = tempDirectory()
        try LocalDataStore.saveGoals([Goal(name: "X", targetAmount: 100)], to: directory)

        let url = LocalDataStore.goalsURL(in: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)
    }

    @Test("Resetting local data removes the goals file")
    func resetRemovesGoals() throws {
        let directory = tempDirectory()
        try LocalDataStore.saveGoals([Goal(name: "X", targetAmount: 100)], to: directory)
        #expect(FileManager.default.fileExists(atPath: LocalDataStore.goalsURL(in: directory).path))

        _ = try LocalDataStore.resetLocalData(at: directory, resetKeychainTokens: false)
        #expect(!FileManager.default.fileExists(atPath: LocalDataStore.goalsURL(in: directory).path))
    }
}
