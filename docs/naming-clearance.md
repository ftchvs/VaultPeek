# VaultPeek Naming Clearance Pass

Lightweight naming clearance for the PlaidBar → VaultPeek rename, run before
public release. All findings were retrieved on **2026-06-12**. Queries covered
`VaultPeek`, `vaultpeek`, and `Vault Peek` across general web search, GitHub,
the Apple App Store (iOS and macOS storefronts via the iTunes Search API),
Homebrew, and common package indexes.

> **This is not formal trademark legal advice.** This pass is a collision and
> confusion check using public search surfaces only. No USPTO/EUIPO or other
> trademark-register search was performed. Consult a trademark professional
> before relying on the name for broad commercial distribution.

## Findings

| Surface | Query / endpoint | Result (retrieved 2026-06-12) | Reference |
|---------|------------------|-------------------------------|-----------|
| Web search | `"VaultPeek"` | No shipped product named VaultPeek. One idea-stage mention: "VaultPeek – View secrets in Vault without revealing full value" in a DevOps tool-ideas listicle (Apr 2025); concept only, HashiCorp Vault context | <https://dev.to/francescobianco/101-ideas-for-smart-devops-tools-27hp> |
| GitHub repositories | `search/repositories?q=vaultpeek` | 1 repo: `gmachinesh/vaultpeek` — "A CLI tool to inspect and diff HashiCorp Vault secrets across environments". Go, 0 stars, 0 forks, no license, created 2026-04-16, last push 2026-04-29 | <https://github.com/gmachinesh/vaultpeek> |
| GitHub users/orgs | `search/users?q=vaultpeek` | 0 results | — |
| GitHub code | `search/code?q=vaultpeek` | 154 raw string hits, dominated by the repo above and incidental strings; no additional product | — |
| App Store (iOS) | iTunes Search API, `term=vaultpeek` / `vault peek`, `entity=software` | No app named VaultPeek or Vault Peek. Nearby names are photo/privacy "vault" apps and separate finance apps: "Peek – AI Personal Finance App", "Vault Finance: Money Coach", "Finance Vault", "Vault: Private Wealth", "Vault – Borderless Banking" | <https://apps.apple.com/us/app/peek-ai-personal-finance-app/id6742875016> |
| Mac App Store | iTunes Search API, `entity=macSoftware` | No VaultPeek; results are unrelated password/photo vault utilities | — |
| Homebrew | `formulae.brew.sh/api/formula/vaultpeek.json`, `/api/cask/vaultpeek.json` | 404 / 404 — no formula or cask | <https://formulae.brew.sh> |
| npm | `registry.npmjs.org/vaultpeek`, `/vault-peek` | 404 / 404 — names unclaimed | <https://www.npmjs.com> |
| PyPI | `pypi.org/pypi/vaultpeek/json`, `/vault-peek/json` | 404 / 404 — names unclaimed | <https://pypi.org> |
| crates.io | `crates.io/api/v1/crates/vaultpeek` | 404 — name unclaimed | <https://crates.io> |
| RubyGems | `rubygems.org/api/v1/gems/vaultpeek.json` | 404 — name unclaimed | <https://rubygems.org> |
| Domains | DNS + WHOIS | `vaultpeek.com` registered 2026-01-31 (NameCheap), resolves but serves no content (parked). `vaultpeek.app`, `vaultpeek.dev`, `vaultpeek.io` do not resolve (likely unregistered) | — |

## Collisions and Nearby Uses

1. **`gmachinesh/vaultpeek` (GitHub, Go CLI).** The only live use of the exact
   string. It is a HashiCorp Vault secrets inspection CLI with zero stars,
   zero forks, no license, and no releases — a different category (DevOps
   secrets tooling) and a different audience from a consumer macOS finance
   app. Low confusion risk today; worth re-checking before any CLI of ours is
   published under a `vaultpeek` binary name, since a future
   `brew install vaultpeek` or `vaultpeek` PATH binary would be where the two
   could actually collide.
2. **DEV Community idea listicle (2025).** Same HashiCorp Vault connotation as
   above, idea-stage only. No product shipped from it that we could find.
3. **"Vault"-prefixed finance apps on the App Store.** "Vault Finance",
   "Finance Vault", "Vault: Private Wealth", and "Vault – Borderless Banking"
   exist, and a finance app named "Peek" exists, but none combine the two
   words. "Vault" alone is a crowded generic in both fintech and
   privacy-utility categories, which cuts both ways: VaultPeek is unlikely to
   be confused with any single one of them, and equally cannot expect to own
   "Vault" as a distinctive element. The compound "VaultPeek" appears
   distinctive.
4. **`vaultpeek.com` registration.** Registered January 2026 and parked. If
   this registration is not already owned by the project, decide before launch
   whether to acquire it or standardize on an available alternative
   (`vaultpeek.app` / `vaultpeek.dev` appeared unregistered at retrieval
   time).

## Plaid / Financial-Provider Confusion Assessment

- **Plaid:** "VaultPeek" contains no part of the Plaid name and does not imply
  sponsorship, partnership, or an official Plaid product. This is a clear
  improvement over "PlaidBar", which embedded the Plaid trademark. Docs and
  marketing should keep describing Plaid factually ("dashboard for Plaid
  data", "uses the Plaid API") and avoid implying endorsement.
- **Other financial providers:** No bank, fintech, or data aggregator named
  VaultPeek was found. The name does not resemble any specific institution.
  The "vault" metaphor is generically associated with banking and security
  rather than with any provider, and "peek" signals read-only glanceability,
  which matches the product's actual behavior (read-only local dashboard).
- **HashiCorp Vault:** the only recurring association of the literal string is
  with HashiCorp Vault tooling in developer circles. Our positioning, visuals,
  and copy should stay clearly in personal finance (no terminal/secrets-vault
  imagery) to keep that association from sticking.

## Conclusion

No direct collision blocks the rename. The exact-match uses are tiny,
unlicensed, idea-stage, or in an unrelated developer-tools category. The name
does not imply a Plaid or financial-provider relationship. Proceed, with two
follow-ups: resolve `vaultpeek.com` ownership (or claim `.app`/`.dev`), and
re-run this pass plus a professional trademark search before wide public
distribution or paid licensing at scale.
