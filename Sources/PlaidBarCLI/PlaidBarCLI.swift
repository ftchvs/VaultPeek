import AppKit
import ArgumentParser
import Foundation
import PlaidBarCore

@main
struct PlaidBarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plaidbar-cli",
        abstract: "Command-line access to the local PlaidBar server.",
        discussion: "Mirrors the JSON-friendly shape of Plaid CLI while keeping Plaid secrets inside PlaidBarServer.",
        version: PlaidBarConstants.appVersion,
        subcommands: [
            Status.self,
            Item.self,
            Balance.self,
            Transactions.self,
            Link.self,
        ],
        defaultSubcommand: Status.self
    )
}

struct PlaidBarCLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Write machine-readable JSON to stdout. Diagnostics stay on stderr.")
    var json = false

    @Option(name: .long, help: "Base URL for PlaidBarServer.")
    var server: String = PlaidBarConstants.serverBaseURL

    @Option(name: .long, help: "Path to the PlaidBarServer bearer token file.")
    var authTokenPath: String = LocalDataStore.authTokenURL().path
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show local server status.")

    @OptionGroup var options: PlaidBarCLIOptions

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let status: ServerStatus = try await client.get(.status)
        try PlaidBarCLIOutput.write(status, json: options.json) {
            PlaidBarCLITableFormatter.status(status)
        }
    }
}

struct Item: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with linked Plaid items.",
        subcommands: [ItemList.self],
        defaultSubcommand: ItemList.self
    )
}

struct ItemList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List linked Plaid items.")

    @OptionGroup var options: PlaidBarCLIOptions

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let items: [ItemStatus] = try await client.get(.items)
        try PlaidBarCLIOutput.write(items, json: options.json) {
            PlaidBarCLITableFormatter.items(items)
        }
    }
}

struct Balance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "balance",
        abstract: "Fetch account balances from linked items."
    )

    @OptionGroup var options: PlaidBarCLIOptions

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let accounts: [AccountDTO] = try await client.get(.balance)
        try PlaidBarCLIOutput.write(accounts, json: options.json) {
            PlaidBarCLITableFormatter.balance(accounts)
        }
    }
}

struct Transactions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transactions",
        abstract: "Fetch transaction updates.",
        subcommands: [TransactionsList.self, TransactionsSync.self],
        defaultSubcommand: TransactionsList.self
    )
}

struct TransactionsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recently synced transaction updates.")

    @OptionGroup var options: PlaidBarCLIOptions

    @Option(name: .long, help: "Maximum number of transactions to print in table mode.")
    var count = 20

    @Option(name: .long, help: "Restrict sync to one Plaid item ID.")
    var item: String?

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let response = try await fetchSync(client: client, item: item)
        let transactions = response.added + response.modified
        if options.json {
            try PlaidBarCLIOutput.write(response, json: true) { "" }
        } else {
            print(PlaidBarCLITableFormatter.transactions(transactions, count: count))
            if response.hasMore {
                PlaidBarCLIOutput.writeError("More transactions are available; open VaultPeek to sync them.")
            }
            if !response.pendingCursors.isEmpty {
                PlaidBarCLIOutput.writeError(readOnlyCursorNote)
            }
        }
    }
}

struct TransactionsSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sync", abstract: "Sync transactions and print the raw sync response.")

    @OptionGroup var options: PlaidBarCLIOptions

    @Option(name: .long, help: "Restrict sync to one Plaid item ID.")
    var item: String?

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let response = try await fetchSync(client: client, item: item)
        try PlaidBarCLIOutput.write(response, json: options.json) {
            let transactions = response.added + response.modified
            return PlaidBarCLITableFormatter.transactions(transactions, count: transactions.count)
        }
        if response.hasMore {
            PlaidBarCLIOutput.writeError("More transactions are available; open VaultPeek to sync them.")
        }
        if !response.pendingCursors.isEmpty {
            PlaidBarCLIOutput.writeError(readOnlyCursorNote)
        }
    }
}

/// The CLI is a read-only diagnostic mirror: it fetches transactions from the
/// server's sync endpoint but does NOT persist them. Only VaultPeek stores
/// fetched transactions and advances the sync cursor, so the CLI must never
/// commit cursors — doing so would advance the shared cursor past transactions
/// the app has not stored, and the app's next sync would skip them (AND-404).
private let readOnlyCursorNote =
    "Read-only preview: VaultPeek stores these updates and advances the sync cursor when you open it. The CLI does not commit cursors."

struct Link: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Create a Hosted Link URL through PlaidBarServer."
    )

    @OptionGroup var options: PlaidBarCLIOptions

    @Option(name: .long, help: "Create update-mode Link for an existing item ID.")
    var updateItem: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Open the Link URL in the default browser.")
    var open = true

    func run() async throws {
        let client = PlaidBarCLIHTTPClient(options: options)
        let endpoint: PlaidBarCLIEndpoint = updateItem.map { .linkUpdate(itemId: $0) } ?? .linkCreate
        let response: LinkResponse = try await client.post(endpoint)
        if open, let url = URL(string: response.linkUrl) {
            NSWorkspace.shared.open(url)
            PlaidBarCLIOutput.writeError("Opened Plaid Link in the default browser.")
        }
        try PlaidBarCLIOutput.write(response, json: options.json) {
            response.linkUrl
        }
    }
}

private func fetchSync(
    client: PlaidBarCLIHTTPClient,
    item: String?
) async throws -> SyncResponse {
    try await client.get(.transactionsSync(itemId: item))
}

struct PlaidBarCLIHTTPClient: Sendable {
    let options: PlaidBarCLIOptions

    func get<T: Decodable & Sendable>(_ endpoint: PlaidBarCLIEndpoint) async throws -> T {
        var request = try request(endpoint: endpoint)
        request.httpMethod = "GET"
        return try await decode(request)
    }

    func post<T: Decodable & Sendable>(_ endpoint: PlaidBarCLIEndpoint) async throws -> T {
        var request = try request(endpoint: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await decode(request)
    }

    private func request(endpoint: PlaidBarCLIEndpoint) throws -> URLRequest {
        // Tolerate a trailing slash on --server (e.g. http://127.0.0.1:8484/)
        // so it does not collapse into a double-slashed /api path the server
        // routes will not match.
        let base = options.server.hasSuffix("/")
            ? String(options.server.dropLast())
            : options.server
        guard let url = URL(string: base + endpoint.path) else {
            throw PlaidBarCLIError.invalidServerURL(options.server)
        }
        // Never attach the local bearer token (the local API secret) to a
        // non-loopback server: that would leak it to a remote endpoint (AND-404).
        guard PlaidBarCLIServer.isLoopback(base) else {
            throw PlaidBarCLIError.nonLoopbackServer(options.server)
        }
        let token = try String(contentsOfFile: options.authTokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw PlaidBarCLIError.missingAuthToken(options.authTokenPath)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func decode<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let data = try await PlaidBarURLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

actor PlaidBarURLSession {
    static let shared = PlaidBarURLSession()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlaidBarCLIError.requestFailed("No HTTP response")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw PlaidBarCLIError.requestFailed(Self.errorMessage(from: data, statusCode: httpResponse.statusCode))
            }
            return data
        } catch let error as PlaidBarCLIError {
            throw error
        } catch {
            throw PlaidBarCLIError.requestFailed(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "reason", "error", "detail", "title"] {
                if let value = object[key] as? String, !value.isEmpty {
                    return "HTTP \(statusCode): \(value)"
                }
            }
        }
        if let body = String(data: data, encoding: .utf8), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "HTTP \(statusCode): \(body.prefix(500))"
        }
        return "HTTP \(statusCode)"
    }
}

enum PlaidBarCLIOutput {
    static func write<T: Encodable>(_ value: T, json: Bool, table: () -> String) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            print(table())
        }
    }

    static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum PlaidBarCLIError: Error, CustomStringConvertible, LocalizedError {
    case invalidServerURL(String)
    case nonLoopbackServer(String)
    case missingAuthToken(String)
    case requestFailed(String)

    var description: String {
        switch self {
        case .invalidServerURL(let value):
            "Invalid PlaidBar server URL: \(value)"
        case .nonLoopbackServer(let value):
            "Refusing to send the local auth token to a non-loopback server: \(value). PlaidBarServer binds to 127.0.0.1; use a loopback --server URL."
        case .missingAuthToken(let path):
            "PlaidBar auth token is missing at \(path). Start PlaidBarServer first."
        case .requestFailed(let message):
            "PlaidBar server request failed: \(message)"
        }
    }

    var errorDescription: String? { description }
}
