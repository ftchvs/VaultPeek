# frozen_string_literal: true

# Homebrew formula for PlaidBar.
class Plaidbar < Formula
  desc "Private macOS menu bar dashboard for Plaid accounts"
  homepage "https://github.com/ftchvs/PlaidBar"
  url "https://github.com/ftchvs/PlaidBar.git", tag: "v0.3.2"
  license "MIT"
  head "https://github.com/ftchvs/PlaidBar.git", branch: "main"

  depends_on "swift" => :build
  depends_on macos: :sequoia

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    bin.install ".build/release/PlaidBar" => "plaidbar"
    bin.install ".build/release/PlaidBarServer" => "plaidbar-server"
    bin.install "Scripts/plaidbar-run"

    doc.install "README.md", "SECURITY.md", "LICENSE"
  end

  def caveats
    <<~EOS
      PlaidBar installs three commands:
        plaidbar --demo                  # launch demo menu bar UI
        plaidbar-server --sandbox        # run the local Plaid server
        plaidbar-run --sandbox           # run server + app together

      For sandbox or production data, set credentials before launching:
        export PLAID_CLIENT_ID=...
        export PLAID_SECRET=...

      If you already have Xcode 16 or a Swift 6 toolchain installed, Homebrew
      may still install its keg-only Swift build dependency for reproducible
      source builds.
    EOS
  end

  test do
    assert_match "USAGE:", shell_output("#{bin}/plaidbar-server --help")
    assert_match "Missing Plaid credentials", shell_output("#{bin}/plaidbar-run --sandbox 2>&1", 1)
  end
end
