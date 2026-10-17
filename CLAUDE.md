# Deskmap: notes for Claude

## Releases always update the Homebrew tap

Deskmap is installed with `brew install --cask cnkndmr/tap/deskmap`. The cask
lives in a separate repository, **cnkndmr/homebrew-tap** (`Casks/deskmap.rb`),
and nothing updates it automatically. A release is not finished until the tap
is updated too:

1. After the new `Deskmap-<version>.zip` is attached to the GitHub release
   `v<version>`, set `version` in `Casks/deskmap.rb` to the new version and
   `sha256` to the checksum of exactly that zip (`shasum -a 256 Deskmap-<version>.zip`).
2. Update the rest of the cask whenever the app changes what it describes:
   - `depends_on macos:` when `LSMinimumSystemVersion` changes,
   - `app` when the bundle name changes,
   - `zap trash:` when the data folder (`~/Library/Application Support/Deskmap`)
     or the bundle identifier (`com.deskmap.app`) changes,
   - `desc` / `homepage` when the tagline or the website URL changes.
3. Commit and push the tap in the same task as the release, then check it:
   `brew update && brew info --cask cnkndmr/tap/deskmap` shows the new version.

Do the same when a release asset is re-uploaded: a new zip means a new sha256.
