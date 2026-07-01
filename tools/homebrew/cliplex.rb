# Homebrew cask for Cliplex.
#
# Casks live in a *tap* repository, not in the app repo. To publish:
#   1. Create a tap repo named `homebrew-cliplex` (e.g. github.com/Ron537/homebrew-cliplex).
#   2. Put this file at `Casks/cliplex.rb` in that tap.
#   3. After each release, bump `version` and `sha256`
#      (`shasum -a 256 dist/Cliplex-<version>.dmg`).
#
# Users then install with:
#   brew install --cask Ron537/cliplex/cliplex
# or, after `brew tap Ron537/cliplex`:
#   brew install --cask cliplex
cask "cliplex" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Ron537/Cliplex/releases/download/v#{version}/Cliplex-#{version}.dmg"
  name "Cliplex"
  desc "Fast, private, native clipboard manager — history, snippets & quick actions"
  homepage "https://github.com/Ron537/Cliplex"

  depends_on macos: ">= :sonoma"

  app "Cliplex.app"

  # Release builds are ad-hoc signed (not notarized), so macOS quarantines the
  # downloaded app. Users approve it once via System Settings → Privacy &
  # Security → "Open Anyway" (see the README "First launch" section).

  zap trash: [
    "~/Library/Application Support/com.ron537.cliplex",
    "~/Library/Preferences/com.ron537.cliplex.plist",
  ]
end
