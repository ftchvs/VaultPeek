import Foundation
@testable import PlaidBarCore
import Testing

@Suite("Server Auto-Launch Plan Tests")
struct ServerAutoLaunchPlanTests {
    private let bundledPath = "/Applications/PlaidBar.app/Contents/MacOS/PlaidBarServer"
    private let dataDirectory = "/Users/example/.plaidbar"

    @Test("Plan launches the bundled server with the configured server.conf")
    func planLaunchesBundledServer() throws {
        let plan = try #require(ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            port: 8484,
            parentProcessId: 4242
        ))

        #expect(plan.executablePath == bundledPath)
        #expect(plan.arguments == [
            "--config", "/Users/example/.plaidbar/server.conf",
            "--port", "8484",
            "--exit-with-parent", "4242",
        ])
        #expect(plan.logFilePath == "/Users/example/.plaidbar/server.log")
    }

    @Test("Plan normalizes a trailing slash in the data directory")
    func planNormalizesTrailingSlash() throws {
        let plan = try #require(ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory + "/",
            configFileExists: true,
            port: 8484,
            parentProcessId: 4242
        ))

        #expect(plan.logFilePath == "/Users/example/.plaidbar/server.log")
        #expect(plan.arguments.contains("--config"))
        #expect(plan.arguments.contains("/Users/example/.plaidbar/server.conf"))
    }

    @Test("Plan declines when managed server config moves the data directory")
    func planDeclinesWhenConfigMovesDataDirectory() {
        let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            configFileContents: """
            PLAID_CLIENT_ID=test-client
            PLAID_SECRET=test-secret
            export PLAIDBAR_DATA_DIR=/tmp/plaidbar-other
            """,
            port: 8484,
            parentProcessId: 4242
        )

        #expect(plan == nil)
    }

    @Test("Plan keeps overriding a configured server port for managed launch")
    func planOverridesConfiguredServerPort() throws {
        let plan = try #require(ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            configFileContents: """
            PLAID_CLIENT_ID=test-client
            PLAID_SECRET=test-secret
            PLAIDBAR_SERVER_PORT=9494
            """,
            port: 8484,
            parentProcessId: 4242
        ))

        #expect(plan.arguments.contains("--port"))
        #expect(plan.arguments.contains("8484"))
        #expect(!plan.arguments.contains("9494"))
    }

    @Test("Plan declines without server.conf because the server cannot boot credential-less")
    func planDeclinesWithoutConfigFile() {
        let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: false,
            port: 8484,
            parentProcessId: 4242
        )

        #expect(plan == nil)
    }

    @Test("Plan declines outside an app bundle so swift run stays developer-managed")
    func planDeclinesOutsideAppBundle() {
        let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: false,
            isDemoMode: false,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            port: 8484,
            parentProcessId: 4242
        )

        #expect(plan == nil)
    }

    @Test("Plan declines when a server is already reachable")
    func planDeclinesWhenServerReachable() {
        let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: false,
            serverAlreadyReachable: true,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            port: 8484,
            parentProcessId: 4242
        )

        #expect(plan == nil)
    }

    @Test("Plan declines in demo mode")
    func planDeclinesInDemoMode() {
        let plan = ServerAutoLaunchPlan.evaluate(
            bundledServerPath: bundledPath,
            isAppBundle: true,
            isDemoMode: true,
            serverAlreadyReachable: false,
            dataDirectoryPath: dataDirectory,
            configFileExists: true,
            port: 8484,
            parentProcessId: 4242
        )

        #expect(plan == nil)
    }

    @Test("Plan declines when the bundle has no server executable")
    func planDeclinesWithoutBundledServer() {
        for missingPath in [nil, ""] as [String?] {
            let plan = ServerAutoLaunchPlan.evaluate(
                bundledServerPath: missingPath,
                isAppBundle: true,
                isDemoMode: false,
                serverAlreadyReachable: false,
                dataDirectoryPath: dataDirectory,
                configFileExists: true,
                port: 8484,
                parentProcessId: 4242
            )

            #expect(plan == nil)
        }
    }
}
