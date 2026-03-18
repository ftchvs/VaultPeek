<p align="center">
  <img src="https://img.icons8.com/sf-regular-filled/96/228BE6/money-bag.png" width="80" alt="PlaidBar icon"/>
</p>

<h1 align="center">PlaidBar</h1>

<p align="center">
  <strong>Your bank accounts, credit cards, and spending — always one click away in the macOS menu bar.</strong>
</p>

<p align="center">
  <a href="https://github.com/ftchvs/PlaidBar/actions/workflows/ci.yml"><img src="https://github.com/ftchvs/PlaidBar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/ftchvs/PlaidBar/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-6.0%2B-F05138.svg" alt="Swift 6.0+">
</p>

---

PlaidBar is an open-source macOS menu bar app that integrates with [Plaid](https://plaid.com) to display bank account balances, credit card utilization, recent transactions, and spending breakdowns — all from your status bar.

**No cloud. No telemetry. All data stays local.**

## Why PlaidBar?

Personal finance data lives behind bank website logins. The closest thing to a menu bar finance app was [Balance](https://balancemy.money/) — commercial and now defunct. PlaidBar fills that gap as an open-source, privacy-first alternative.

- **Glanceable** — Net balance visible right in the menu bar
- **Account Balances** — All bank accounts and credit cards at a glance
- **Recent Transactions** — Searchable list grouped by day with category icons
- **Spending Breakdown** — Donut chart by category with time period filters
- **Credit Utilization** — Progress bars with configurable warning thresholds
- **Sandbox Mode** — Try with demo data, no Plaid credentials needed
- **Private** — Everything stored locally on your Mac, period

## Screenshots

> *Coming soon — the app compiles and runs but screenshots will be added after visual polish.*

## Quick Start

### 1. Clone and build

```bash
git clone https://github.com/ftchvs/PlaidBar.git
cd PlaidBar
swift build
```

### 2. Run in sandbox mode (no credentials needed)

```bash
./Scripts/run.sh --sandbox
```

This starts both the local server and the menu bar app with Plaid's sandbox environment (demo bank data).

### 3. Click the PlaidBar icon in your menu bar

Select **"Try with sandbox"** → **Add Account** → complete the demo bank login in your browser → data appears instantly.

### 4. Use with real bank data (optional)

```bash
export PLAID_CLIENT_ID=your_client_id
export PLAID_SECRET=your_secret
./Scripts/run.sh
```

Get credentials free at [dashboard.plaid.com](https://dashboard.plaid.com). Sandbox works immediately; production requires Plaid approval.

## Requirements

| Requirement | Version |
|------------|---------|
| macOS | 15.0 (Sequoia)+ |
| Swift | 6.0+ |
| Xcode | 16+ (or Swift toolchain) |
| Plaid account | Free for sandbox |

## Architecture

PlaidBar uses a **two-process architecture** — a SwiftUI menu bar app talks to a local companion server that proxies all Plaid API calls.

```
┌─────────────────────────────────────┐
│  PlaidBar.app (SwiftUI)             │
│  MenuBarExtra · Swift Charts        │
│  Accounts · Transactions · Spending │
└──────────────┬──────────────────────┘
               │ HTTP (localhost:8484)
┌──────────────▼──────────────────────┐
│  PlaidBarServer (Hummingbird 2)     │
│  Plaid API proxy · Fluent/SQLite    │
│  Token storage · OAuth callback     │
└──────────────┬──────────────────────┘
               │ HTTPS
┌──────────────▼──────────────────────┐
│  Plaid API                          │
│  /accounts · /transactions/sync     │
└─────────────────────────────────────┘
```

**Why a companion server?** Plaid requires that `client_secret` and `access_token` never exist in client code. The server:
1. Holds all secrets in a local SQLite database
2. Binds to `127.0.0.1` only — zero network exposure
3. Can be restarted independently of the UI
4. Opens the door for future CLI tools or iOS companion

### Technology Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Menu bar app | SwiftUI `MenuBarExtra` (.window) | Native macOS, modern API |
| Charts | Swift Charts | Built-in, no dependencies |
| Local server | [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) | Lightweight, SwiftNIO-based, same language as app |
| Database | SQLite via [Fluent ORM](https://github.com/vapor/fluent-kit) | Migrations, queries, Hummingbird-native |
| Secrets (app) | macOS Keychain | OS-level secure storage |
| Auto-updates | [Sparkle 2](https://github.com/sparkle-project/Sparkle) | Standard for open-source macOS apps |

### Project Structure

```
PlaidBar/
├── Sources/
│   ├── PlaidBar/                    # macOS menu bar app
│   │   ├── App/                     # @main entry, AppState
│   │   ├── Views/                   # SwiftUI views (5 tabs)
│   │   │   ├── AccountsView.swift   # Balance list by account type
│   │   │   ├── TransactionsView.swift # Searchable grouped list
│   │   │   ├── SpendingView.swift   # Donut chart + breakdown
│   │   │   ├── CreditView.swift     # Utilization progress bars
│   │   │   └── SetupView.swift      # Onboarding flow
│   │   ├── Models/                  # Local cache models
│   │   ├── Services/                # HTTP client, refresh, sync
│   │   └── Settings/                # Preferences window
│   ├── PlaidBarServer/              # Local companion server
│   │   ├── Routes/                  # REST endpoints
│   │   ├── Plaid/                   # Plaid API client + models
│   │   ├── Storage/                 # Fluent models + migrations
│   │   └── Config/                  # Server configuration
│   └── PlaidBarCore/                # Shared library
│       ├── Models/                  # DTOs (Account, Transaction, etc.)
│       └── Utilities/               # Currency formatters, constants
├── Tests/                           # 61 tests across 3 suites
├── Scripts/                         # build.sh, run.sh, setup.sh
├── .github/workflows/ci.yml        # GitHub Actions CI
├── Package.swift                    # SPM with 3 targets
└── LICENSE                          # MIT
```

## Plaid API Usage

PlaidBar uses these Plaid endpoints:

| Endpoint | Feature | Cost | Frequency |
|----------|---------|------|-----------|
| `/link/token/create` | Account setup | Free | On-demand |
| `/item/public_token/exchange` | Account setup | Free | Once per bank |
| `/accounts/get` | Cached balances | Free | Every 15 min |
| `/accounts/balance/get` | Real-time balances | Per-request | Manual refresh |
| `/transactions/sync` | Transactions | Per-item | Every 30 min |

Rate limits are well within Plaid's allowances for personal use (~2-4 requests/hour/item).

## Security

| Concern | How PlaidBar handles it |
|---------|------------------------|
| Plaid secrets | Stored in server SQLite, never in app binary |
| Access tokens | Encrypted at rest, localhost-only server |
| Network exposure | Server binds to `127.0.0.1` only |
| App ↔ Server auth | Shared token generated at first run |
| Data at rest | macOS encrypted APFS volume |
| Distribution | Hardened runtime + notarized DMG (planned) |

**PlaidBar has no cloud backend, no analytics, no telemetry, and no tracking.** Your financial data never leaves your machine.

## Development

```bash
# Build all targets
swift build

# Build release
swift build -c release

# Run tests (61 tests)
swift test

# Run server standalone
swift run PlaidBarServer --sandbox

# Run both (server + app)
./Scripts/run.sh --sandbox

# First-time setup helper
./Scripts/setup.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for code style, PR process, and architecture guidelines.

## Server API Reference

The companion server exposes these localhost endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/api/status` | Server version, environment, item count |
| `GET` | `/api/items` | List connected bank items |
| `POST` | `/api/link/create` | Create Plaid Link token + URL |
| `GET` | `/oauth/callback` | Plaid OAuth redirect handler |
| `GET` | `/api/accounts` | List all accounts (cached) |
| `GET` | `/api/accounts/balances` | Real-time balances |
| `DELETE` | `/api/accounts/:itemId` | Remove a bank connection |
| `GET` | `/api/transactions/sync` | Incremental transaction sync |

## Roadmap

- [ ] Budget alerts per category
- [ ] Multi-currency support
- [ ] Investment account tracking (Plaid Investments)
- [ ] CSV/JSON export for tax/accounting
- [ ] Webhook support for real-time updates
- [ ] macOS notifications for large transactions
- [ ] Homebrew cask distribution
- [ ] Dark/light theme customization
- [ ] [Teller](https://teller.io/) as alternative provider (free tier)
- [ ] Recurring transaction detection

## Inspiration

- [RepoBar](https://github.com/nicklama/RepoBar) — GitHub stats in the macOS menu bar
- [Balance](https://balancemy.money/) — Commercial macOS finance app (defunct)
- [Cashculator](https://cashculator.app/) — Personal finance for Mac

## License

[MIT](LICENSE) — [Felipe Tavares Chaves](https://github.com/ftchvs)
