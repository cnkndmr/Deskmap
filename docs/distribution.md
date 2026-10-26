# Distribution

How this app can reach other people, and why the Mac App Store is not the
route. Written 2026-09-16 for version 0.3.0.

## Short answer

| Route | Possible? | What it costs |
|---|---|---|
| Mac App Store | **No**, not without gutting the app | — |
| Developer ID + notarization (direct download) | **Yes**, recommended | Apple Developer Program, 99 USD/year |
| Unsigned / ad-hoc zip (today) | Works, but every user has to bypass Gatekeeper | free |

## Why the Mac App Store does not work

Two hard blockers, both about what the app does for a living.

**1. The App Sandbox blocks moving other apps' windows.** Every app
submitted to the Mac App Store today must be sandboxed. Inside the sandbox
the Accessibility *write* API — `AXUIElementSetAttributeValue`, which is
how this app sets a window's position and size — does not work even after
the user grants Accessibility permission. Without it there is no layout,
no "put this window on the left half".

Measured, not assumed: on 16 September 2026 (macOS 26.6.2) a sandboxed probe
app with the Accessibility permission granted — `AXIsProcessTrusted()`
returned true — could not even *read* Finder's windows
(`kAXErrorCannotComplete`, −25204), while the same binary without the sandbox
read, moved and restored the window. (The probe lived in `appstore/probe/`
until 0.6.0; it is no longer in the repository.)

Magnet, Moom and BetterSnapTool are on the store while doing similar work
because they shipped before sandboxing became mandatory and kept a legacy
exemption. A new submission does not get that exemption, so their presence
is not a precedent.

**2. Moving a window to another Space needs private API.** macOS has no
public API for it. `Services/SkyLight.swift` resolves
`SLSMoveWindowsToManagedSpace`, `SLSSpaceSetCompatID` +
`SLSSetWindowListWorkspace` and, on macOS 26.4+,
`SLSBridgedMoveWindowsToManagedSpaceOperation` at runtime through `dlsym`.
App Review guideline 2.5.1 allows public APIs only. Resolving the symbols
dynamically hides nothing: it is the same rejection, and trying to slip it
past review is not a plan, it is a timer.

Strip both and what is left is a list of window titles — the two features
the app exists for are gone. So: no store build.

## The route that does work: Developer ID + notarization

Users download a `.dmg`, drag the app to `/Applications`, and macOS opens
it with no warning. This is how Rectangle, AeroSpace, Hammerspoon and
yabai ship.

What the maintainer needs to do once:

1. Join the Apple Developer Program (99 USD/year, personal account is fine).
2. In Xcode or the developer portal, create a **Developer ID Application**
   certificate and install it in the login keychain.
3. Create an app-specific password at appleid.apple.com, then store a
   notary profile:

   ```
   xcrun notarytool store-credentials notary \
     --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```

Then every release is one command:

```
SIGN_IDENTITY="Developer ID Application: <Name> (TEAMID)" \
NOTARY_PROFILE=notary FORMAT=dmg make dist
```

`scripts/make-dist.sh` already builds universal (arm64 + x86_64), signs
with the hardened runtime and a secure timestamp, submits to notarization,
staples the ticket and verifies the result.

Until then `make dist` produces an ad-hoc signed zip: the receiver must
right-click › Open once, or run
`xattr -dr com.apple.quarantine /Applications/Deskmap.app`.

### One caveat about Accessibility permission

macOS ties the Accessibility grant to the code signature. Moving from
ad-hoc signing to Developer ID changes the signature, so the permission
must be granted again after the first signed build — once, not on every
release, as long as the identity stays the same.

## Release checklist

- [ ] `VERSION` bumped, `CHANGELOG.md` has the release section
- [ ] `make test` green
- [ ] `FORMAT=dmg make dist` with Developer ID + notary profile
- [ ] Verify on a second Mac (or a fresh user account): download, open, no
      Gatekeeper warning, Accessibility prompt appears, pins apply
- [ ] GitHub release with the `.dmg` and the changelog section
- [ ] Optionally a Homebrew cask (`brew install --cask <name>`), which is
      how most users of this kind of app expect to install it
- [ ] Support page reachable from the app (the user guide in `docs/`)

## If a store listing is still wanted later

The only honest store build is a reduced edition: layouts and per-display
placement without Spaces, and without moving windows at all — meaning it
could only *suggest* placements or work through a separate unsandboxed
helper the user installs themselves. Both are worse products than the
direct download. Recommendation: don't.
