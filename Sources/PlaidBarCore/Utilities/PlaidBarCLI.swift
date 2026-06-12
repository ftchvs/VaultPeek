import Foundation

public enum PlaidBarCLIEndpoint: Sendable, Equatable {
    case status
    case items
    case balance
    case transactionsSync(itemId: String?)
    case commitCursors
    case linkCreate
    case linkUpdate(itemId: String)

    public var path: String {
        switch self {
        case .status:
            return "/api/status"
        case .items:
            return "/api/items"
        case .balance:
            return "/api/accounts/balances"
        case .transactionsSync(let itemId):
            if let itemId, !itemId.isEmpty {
                return "/api/transactions/sync?item_id=\(Self.percentEncode(itemId))"
            }
            return "/api/transactions/sync"
        case .commitCursors:
            return "/api/transactions/sync/cursors"
        case .linkCreate:
            return "/api/link/create"
        case .linkUpdate(let itemId):
            return "/api/link/update/\(Self.percentEncode(itemId))"
        }
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum PlaidBarCLITableFormatter {
    public static func status(_ status: ServerStatus) -> String {
        rows([
            ["VERSION", status.version],
            ["ENVIRONMENT", status.environment.rawValue],
            ["ITEMS", String(status.itemCount)],
            ["SYNC READY", yesNo(status.syncReady)],
            ["SYNCED ITEMS", String(status.syncedItemCount)],
            ["CREDENTIALS", yesNo(status.credentialsConfigured)],
            ["STORAGE", status.storagePath],
        ])
    }

    public static func items(_ items: [ItemStatus]) -> String {
        guard !items.isEmpty else { return "No linked items." }
        return rows(
            [["ITEM", "INSTITUTION", "STATUS", "LAST SYNC"]] + items.map { item in
                [
                    item.id,
                    item.institutionName ?? "--",
                    item.status.rawValue,
                    item.lastSync.map(Self.isoDate) ?? "--",
                ]
            }
        )
    }

    public static func balance(_ accounts: [AccountDTO]) -> String {
        guard !accounts.isEmpty else { return "No accounts returned." }
        return rows(
            [["ACCOUNT", "AVAILABLE", "CURRENT", "CURRENCY", "ITEM"]] + accounts.map { account in
                [
                    accountDisplayName(account),
                    money(account.balances.available),
                    money(account.balances.current),
                    account.balances.isoCurrencyCode ?? "--",
                    account.itemId,
                ]
            }
        )
    }

    public static func transactions(_ transactions: [TransactionDTO], count: Int) -> String {
        let limited = transactions
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.displayName < rhs.displayName
            }
            .prefix(max(0, count))
        guard !limited.isEmpty else { return "No transactions returned." }
        return rows(
            [["DATE", "MERCHANT", "AMOUNT", "CATEGORY", "ACCOUNT"]] + limited.map { transaction in
                [
                    transaction.date,
                    transaction.displayName,
                    money(transaction.amount),
                    transaction.category?.rawValue ?? "--",
                    transaction.accountId,
                ]
            }
        )
    }

    private static func accountDisplayName(_ account: AccountDTO) -> String {
        if let mask = account.mask, !mask.isEmpty {
            return "\(account.name) (\(mask))"
        }
        return account.name
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func money(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f", value)
    }

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func rows(_ rows: [[String]]) -> String {
        guard let first = rows.first else { return "" }
        let columnCount = first.count
        let widths = (0..<columnCount).map { column in
            rows.map { row in row.indices.contains(column) ? row[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            (0..<columnCount).map { column in
                let value = row.indices.contains(column) ? row[column] : ""
                if column == columnCount - 1 { return value }
                return value.padding(toLength: widths[column] + 2, withPad: " ", startingAt: 0)
            }.joined()
        }.joined(separator: "\n")
    }
}
