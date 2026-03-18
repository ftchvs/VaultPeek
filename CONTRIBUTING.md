# Contributing to PlaidBar

Thank you for your interest in contributing to PlaidBar!

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

## Pull Request Process

1. Fork the repo and create a branch from `main`
2. Make your changes with clear, descriptive commits
3. Add tests for new functionality
4. Ensure `swift test` passes
5. Submit a PR with a clear description of changes

## Architecture Notes

- **PlaidBarCore** is the shared library — put DTOs and utilities here
- **PlaidBarServer** handles all Plaid API communication
- **PlaidBar** is the UI layer — it only talks to the local server
- All types must be `Sendable` (Swift 6 strict concurrency)
- Use `@Observable` for state management (not ObservableObject)

## Reporting Issues

- Use the [bug report template](https://github.com/ftchvs/PlaidBar/issues/new?template=bug_report.yml) for bugs
- Use the [feature request template](https://github.com/ftchvs/PlaidBar/issues/new?template=feature_request.yml) for ideas

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
