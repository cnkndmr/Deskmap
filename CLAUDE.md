# Deskmap: notes for Claude

## Releases always update the Homebrew tap

Deskmap is installed with `brew install --cask cnkndmr/tap/deskmap`. The cask
lives in a separate repository, **cnkndmr/homebrew-tap** (`Casks/deskmap.rb`).
A release is not finished until the tap points at it:

1. **Automatic.** When the GitHub release `v<version>` is published, the
   workflow `.github/workflows/homebrew.yml` downloads `Deskmap-<version>.zip`
   from it, sets `version` and `sha256` in `Casks/deskmap.rb` and pushes
   "deskmap <version>" to the tap (only if something changed). Attach the zip
   before publishing the release; if it was missing or replaced later, rerun
   the workflow from the Actions tab (Run workflow, tag `v<version>`). It needs
   the secret `HOMEBREW_TAP_TOKEN` (fine-grained token, Contents read/write on
   cnkndmr/homebrew-tap only) and fails with a clear error without it.
2. **Manual.** The workflow never touches the rest of the cask. Update it by
   hand in the tap whenever the app changes what it describes:
   - `depends_on macos:` when `LSMinimumSystemVersion` changes,
   - `app` when the bundle name changes,
   - `zap trash:` when the data folder (`~/Library/Application Support/Deskmap`)
     or the bundle identifier (`com.deskmap.app`) changes,
   - `desc` / `homepage` when the tagline or the website URL changes.
3. **Check.** After the workflow run is green:
   `brew update && brew info --cask cnkndmr/tap/deskmap` shows the new version.

A re-uploaded release asset means a new sha256: rerun the workflow for that tag.
