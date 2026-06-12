# Internal Development Guide

VaultPeek (formerly PlaidBar) is proprietary software. This document covers
internal development conventions for authorized collaborators working under a
written agreement with the owner. **VaultPeek does not accept public/external
contributions, forks, or pull requests.** Access to this repository does not grant any license to the
code (see [LICENSE](LICENSE)).

## Development Setup

1. **Clone the repo:**
   ```bash
   git clone https://github.com/ftchvs/PlaidBar.git
   cd PlaidBar
   ```

2. **Build:**
   ```bash
   swift build
   ```

3. **Run tests:**
   ```bash
   swift test
   ```

4. **Run in sandbox mode:**
   ```bash
   ./Scripts/run.sh --sandbox
   ```

## Code Style

We use SwiftFormat and SwiftLint for consistent code style:

```bash
# Format code
swiftformat Sources/ Tests/

# Lint
swiftlint
```

Configuration files: `.swiftformat` and `.swiftlint.yml` in the repo root.

## Pull Request Process (internal)

1. Create a branch from `main` (do not fork)
2. Make your changes with clear, descriptive commits
3. Add tests for new functionality
4. Ensure `swift test` passes
5. Open a PR with a clear description of changes for internal review

## Architecture Notes

- **PlaidBarCore** is the shared library — put DTOs and utilities here
- **PlaidBarServer** handles all Plaid API communication
- **PlaidBar** is the UI layer — it only talks to the local server
- All types must be `Sendable` (Swift 6 strict concurrency)
- Use `@Observable` for state management (not ObservableObject)

## Reporting Issues

Internal collaborators track work in Linear (Andeslab → PlaidBar project). When
attaching logs, screenshots, or setup details, use sandbox or synthetic data
only — never real Plaid credentials, account IDs, or balances.

## Accessibility Expectations

- Keep controls reachable by keyboard.
- Add useful labels for VoiceOver.
- Preserve visible focus states.
- Do not communicate balance, risk, utilization, errors, or chart meaning through color alone.
- Use sandbox or synthetic financial data in screenshots, tests, and examples.

## Pull Request Checklist

- [ ] I ran `swift test` or documented why not.
- [ ] I checked relevant accessibility expectations from [ACCESSIBILITY.md](ACCESSIBILITY.md).
- [ ] I used sandbox or synthetic financial data in screenshots, tests, and examples.
- [ ] I updated docs if user-facing behavior changed.

## Intellectual Property

VaultPeek is proprietary and confidential. All work contributed by authorized
collaborators is a work made for hire and/or assigned to the owner, and becomes
the exclusive property of Felipe Tavares Chaves. Do not copy, redistribute, or
reuse any portion of this codebase outside the scope of your written agreement.
See [LICENSE](LICENSE).
