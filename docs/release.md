# Release Runbook

PlaidBar's first public release should ship as a tagged GitHub release and a
Homebrew tap formula.

## Release Shape

- GitHub release tag: `v0.3.4`
- Homebrew tap command:

```bash
brew tap ftchvs/plaidbar https://github.com/ftchvs/PlaidBar
brew install plaidbar
```

- Installed commands:

```bash
plaidbar --demo
plaidbar-server --sandbox
plaidbar-run --sandbox
```

## Checklist

1. Confirm `version.env`, `Sources/PlaidBar/Resources/Info.plist`, and
   `Formula/plaidbar.rb` all point to the same version.
2. Run local gates:

```bash
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
PLAID_CLIENT_ID=ci_smoke_client PLAID_SECRET=ci_smoke_secret ./Scripts/smoke-sandbox.sh
bash -n Scripts/*.sh Scripts/plaidbar-run
ruby -c Formula/plaidbar.rb
```

3. Merge the release-prep PR to `main`.
4. From clean `main`, publish the tag and GitHub release:

```bash
./Scripts/release.sh --publish
```

5. Verify Homebrew install from the repository tap:

```bash
brew tap ftchvs/plaidbar https://github.com/ftchvs/PlaidBar
brew install --build-from-source plaidbar
plaidbar-server --help
plaidbar-run --help
```

## Notes

The initial formula builds from source because PlaidBar is currently a SwiftPM
menu bar executable plus a local server executable, not a signed and notarized
`.app` bundle. A future cask should ship a notarized app archive once the app
bundle, code signing, notarization, Sparkle appcast, and DMG/ZIP packaging are
ready.
