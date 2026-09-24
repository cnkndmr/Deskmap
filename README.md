<p align="center">
  <img src="app/Resources/AppIcon-1024.png" width="128" alt="Deskmap icon">
</p>

<h1 align="center">Deskmap</h1>

<p align="center">
  <b>Every window on the right display, the right desktop, in the right layout, every time.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-menu%20bar%20app-0A84FF" alt="SwiftUI menu bar app">
  <img src="https://img.shields.io/badge/version-0.4.0-5E5CE6" alt="Version 0.4.0">
  <img src="https://img.shields.io/badge/dependencies-none-30D158" alt="No dependencies">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license">
</p>

---

A macOS menu bar app that keeps windows on the right display, the right
desktop (Space) and in the right layout, based on what their **window title**
says. Pin a VS Code workspace to desktop 2 of your external monitor, a Safari
tab group to the left half of desktop 1, an Obsidian vault to the laptop
screen: Deskmap puts each window back where it belongs whenever it
opens, and again when you plug in or unplug a monitor.

It is a single `.app` with no helper program (no Hammerspoon, no yabai). It
works with any app that shows a workspace, project or document name in its
window title: Safari tab groups, VS Code workspaces, Obsidian vaults, terminal
profiles, and so on.

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/images/en/01-map.png" alt="The map: one card per display, one row per desktop, pinned windows in place"></td>
    <td width="50%" align="center"><img src="docs/images/en/02-pin.png" alt="Pinning a window by the part of its title that names the workspace"></td>
  </tr>
  <tr>
    <td align="center"><b>The map</b><br><sub>One card per display, one row per desktop, every window where it lives.</sub></td>
    <td align="center"><b>Pin by title</b><br><sub>Pick the part of the title that names the workspace; choose a layout.</sub></td>
  </tr>
</table>

|  | What you get |
|---|---|
| 🎯 | **Title-based pins**: match on the workspace, project or document name in the window title, not just the app. |
| 🖥️ | **Two setups**: separate targets for *monitor connected* and *laptop only*; everything is re-placed when you plug in or unplug. |
| 📐 | **Layouts**: full, halves, 70 / 30, centered, or any inset in percent, per pin. |
| 🗂️ | **Profiles**: named pin sets, switchable from the menu, Shortcuts or Raycast (`deskmap://`). |
| ↩️ | **No dialogs, just undo**: every destructive action shows *Undo* for 10 seconds (⌘Z). |
| 🪶 | **Light**: one `.app`, no Hammerspoon, no yabai, ~0.2 % CPU at idle. |

*The screenshots come from the app itself, rendered with demo data:
`Deskmap --shots <dir>` (see `app/Sources/Deskmap/Demo/`).*

**New here?** The [user guide](docs/guide.md) — [Türkçe kılavuz](docs/kilavuz.md),
or [both on one page](https://example.com) —
walks through setup and your first pin in ten minutes. This README is the
reference: every rule, every setting, every failure mode. See also
[privacy](docs/privacy.md) (nothing is collected or sent),
[distribution](docs/distribution.md) (how signed builds are made, and why
the Mac App Store isn't an option) and
[the App Store folder](appstore/submission.md) (what is ready anyway,
and what a submission would need).

- [Requirements](#requirements)
- [Install](#install)
- [Required macOS settings](#required-macos-settings)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Automation (URL scheme)](#automation-url-scheme)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Development](#development)
- [Limitations](#limitations)

## Requirements

- macOS 13 Ventura or later.
- To build: Xcode Command Line Tools (`xcode-select --install`) with Swift 5.9
  or later. Xcode itself is not required.
- To run the tests: a Swift 6 toolchain (Xcode 16 or its Command Line Tools),
  because the tests use Swift Testing.

## Install

```sh
git clone https://github.com/cnkndmr/Deskmap.git Deskmap
cd Deskmap
make app                      # release build → build/Deskmap.app
open build/Deskmap.app    # or: make run (builds and opens)
```

For a permanent install, copy the app to `/Applications` and turn on
**Launch at login** in the app's footer:

```sh
cp -R build/Deskmap.app /Applications/
```

**Launch at login** registers whichever copy is running. If you run it from
`build/`, the checkbox tooltip shows that path; move the app to
`/Applications` first if you want a stable login item. If macOS wants you to
confirm the login item, an orange **Approval needed** link appears next to
the checkbox and opens System Settings › General › Login Items.

### Coming from Space Router

Deskmap is the same app under a new name (see
[docs/naming.md](docs/naming.md)). Your pins come with you: on first launch
`rules.json`, `rules.json.bak` and `session-pins.json` are copied from
`~/Library/Application Support/SpaceRouter/` into the new folder — copied, so
the old one stays where it is. `spacerouter://` URLs still work, and so do
`.spacerouter.json` profile exports.

Two things macOS ties to the old identity, so each needs doing once: grant the
**Accessibility** permission again, and switch **Launch at login** back on.

### Accessibility permission

Deskmap reads and moves other apps' windows through the Accessibility
API, so it needs permission once:

1. On first launch the window shows **Accessibility permission required**.
   Click **Grant Access**.
2. macOS shows its prompt and opens System Settings › Privacy & Security ›
   Accessibility. Turn on **Deskmap**.
3. The app checks the permission every 2 seconds and starts routing on its
   own. If it doesn't, quit it (✕ in the footer) and open it again.

The app is ad-hoc signed by default. macOS ties the permission to the code
signature, so **every rebuild needs the permission granted again**; see
[Troubleshooting](#accessibility-stops-working-after-a-rebuild).

Only one copy runs at a time: if a second Deskmap starts (for example a
`build/` copy while the `/Applications` copy is running), it quits right
away, so two routers never fight over the same windows.

### Language

The interface is in English and has a Turkish translation. The app uses the
first language in your preferred-language list (System Settings › General ›
Language & Region) that it supports, so Turkish appears only when Turkish is
listed before English (or English isn't listed at all). To force a language
for Deskmap alone:

```sh
defaults write com.deskmap.app AppleLanguages -array en   # or: tr
defaults delete com.deskmap.app AppleLanguages            # back to the system order
```

Quit and reopen the app after changing it.

## Required macOS settings

<img src="docs/images/en/05-setup.png" align="right" width="300" alt="The macOS settings card with all checks passing">

Deskmap checks these settings live and shows an orange **macOS settings
need fixing** card until they are right. The card has an **Open Desktop &
Dock** button.

**System Settings › Desktop & Dock › Mission Control:**

| Setting | Must be | Why |
|---|---|---|
| Automatically rearrange Spaces based on most recent use | **Off** | When on, macOS reorders your desktops: switching to an app from the Dock lands on a neighbouring Space, the window flashes and disappears, and pins end up on the wrong desktop numbers. |
| When switching to an application, switch to a Space with open windows | **On** | When off, clicking an app in the Dock does not switch desktops. |
| Group windows by application | Off (recommended) | When on, the Mission Control order may not match desktop numbers. |
| Displays have separate Spaces | **On** | When off, Deskmap cannot see the external display's desktops. |

**Dock icon › right-click › Options › Assign To → None** for every app you
pin. With "This Desktop" or "All Desktops", macOS pulls the window to the
Space it assigned, which conflicts with Deskmap's moves. This one cannot
be checked automatically; the card reminds you, and **Got It** hides the
reminder (the card comes back if one of the live-checked settings changes).

<br clear="right">

## Quick start

1. Click the menu bar icon. The window shows a **map**: one card per display,
   one row per desktop, with the windows currently on each desktop.
2. On a window row, click the **pin** button. A panel opens at the bottom.
3. Choose which part of the title identifies the window, for example the
   project name rather than the file name. The panel shows how many open
   windows match right now. Pick a layout if you want one (the default is
   the window's current position and size).
4. Click **Pin** (or press Return). From now on, every window of that app
   whose title contains that part goes to this desktop, in this layout.
5. To pin the window to a different desktop, drag its row or chip onto
   another desktop row on the map.
6. Switch the mode selector at the top (laptop / monitor, ⌘1 / ⌘2) and repeat
   for the other setup. The two setups are independent.

A **Getting Started** card with these steps is shown while the active profile
has no pins.

## How it works

```mermaid
flowchart LR
    W["🪟 Window opens,<br>title changes,<br>or a monitor is plugged in"] --> M{"Matches a pin?<br><sub>app + title parts</sub>"}
    M -- no --> L["Left alone"]
    M -- "several" --> S["Most specific wins<br><sub>temporary pin &gt; more title parts</sub>"]
    M -- one --> T
    S --> T["Target for the current mode<br><sub>monitor connected / laptop only</sub>"]
    T --> D["🖥️ Display<br><sub>builtin · external · external-2</sub>"]
    D --> SP["🗂️ Desktop (Space)"]
    SP --> LY["📐 Layout<br><sub>applied once per target</sub>"]

    classDef start fill:#0A84FF,stroke:#0A84FF,color:#fff
    classDef decide fill:#FF9F0A,stroke:#FF9F0A,color:#000
    classDef place fill:#30D158,stroke:#30D158,color:#000
    classDef skip fill:#8E8E93,stroke:#8E8E93,color:#fff
    class W start
    class M,S decide
    class T,D,SP,LY place
    class L skip
```

### Pins (rules)

<img src="docs/images/en/03-layout.png" align="right" width="300" alt="A pin's panel: title parts and a right-half layout">

A pin says: *windows of this app whose title contains these parts go to this
display, this desktop, in this layout*.

- **App**: matched by bundle identifier (or by app name for old rules without
  one).
- **Title parts**: the title is split at common separators (` — `, ` – `,
  ` | `, ` · `, ` • `, and ` - ` / ` : ` with spaces around them; a leading
  "unsaved" dot is ignored). A window matches when its title contains **all**
  selected parts, ignoring case. By default the last part that isn't the app
  name is selected, because the workspace name is usually at the end.
- **All windows**: pins every window of the app, regardless of title (also
  used automatically for windows without a title).
- **More specific wins**: when several pins match a window, the one with more
  title parts is used. A pin that matches an open window but loses to a more
  specific pin (or to a temporary pin) is shown as a faded chip; its tooltip
  says which pin matches first.
- If you pin with the same app and the same parts as an existing pin, the
  existing pin is updated instead of creating a second one.

What Deskmap enforces:

- **Desktop**: a pinned window is kept on its desktop. If it ends up
  elsewhere, it is moved back.
- **Layout**: applied once per window and target. After that you can resize
  the window freely; the layout is applied again when you press ⌘R (↻), when
  pins change, or after a display change. Windows on a desktop you are not
  looking at get their layout when you switch to that desktop.
- **Use current size and position**: after resizing or moving a pinned window
  by hand, click its row and press this button under the layout editor. The
  window's current position and size (relative to its display's usable area)
  replace the pin's saved layout. Only the layout changes: the pin keeps its
  display and desktop, and no new pin is written. Works for temporary pins too.
- Windows of full-screen apps are never touched. Windows without a pin are
  never moved by the engine.

Click a pinned row or a chip to open its panel: change the layout, **Unpin**,
or change the title parts (this needs a window matching the pin to be open;
**Apply** refuses a selection that would duplicate another pin's app and
parts).

<br clear="right">

### Temporary pins

In the pin panel, **This window only** pins one specific window instead of a
title. Use it for apps whose windows all have the same title. A temporary pin
follows the window's ID: it ends when the window closes or its app restarts,
and it is not saved to the profile. It survives a Deskmap restart as long
as the window is still open. Temporary pins have an orange icon and take
precedence over normal pins.

### Two modes: monitor connected / laptop only

Each pin has a separate target for each mode:

- **Monitor connected**: at least one external display is attached.
- **Laptop only**: only the built-in display.

The mode selector shows the current mode ("now") by default; you can switch it
to edit the other setup. Live windows are listed only for the current mode;
the other mode shows its pins as chips. When a monitor is plugged in or
unplugged, Deskmap waits for the displays to settle (2.5 s, at most
10 s) and then places every pinned window again.

Displays are identified by role, not by serial number: `builtin`, `external`,
`external-2`, … External displays are numbered left to right; displays stacked
in the same column are ordered by vertical position (the lower one first),
then by UUID. A pin whose display isn't connected is skipped.

### Desktops

- **Missing desktops**: macOS has no public way to create desktops, so pins
  can only use desktops that exist in Mission Control. If a pin targets
  desktop 5 but the display has only 3, the window goes to the last one and
  the row shows an orange **D5→3** badge (**M5→3** in Turkish). Add desktops
  in Mission Control or drag the pin elsewhere. Rows for desktops that don't
  exist yet are drawn dashed; the **+ Desktop N** row at the bottom of each
  display lets you pin to the next number.
- **Reordering**: drag a desktop's label ("Desktop 2") up or down. All pins
  on that display in this mode (and temporary pins) are renumbered to match,
  and the windows are moved.
- **Unpinned windows**: dragging an unpinned row to another desktop moves the
  window once; nothing is saved.
- **Tray**: the dashed area at the bottom lists pins that have no target in
  this mode. Dropping a chip or pinned row there removes its target for this
  mode (a pin with no target in either mode is deleted).

### Profiles

<img src="docs/images/en/04-profiles.png" align="right" width="300" alt="Profiles: Desk and Café, with Duplicate, Export and Delete">

A profile is a named set of pins; the chips under the toolbar list them with
their pin count.

- Click a profile to switch to it. Windows are placed again right away.
- Click the active profile to rename, **Duplicate**, **Export** or **Delete**
  it (the last profile cannot be deleted).
- **+** creates an empty profile. The import button reads a
  `.deskmap.json` file exported earlier; a plain `rules.json` also works.
- Profiles can be switched from Shortcuts, Raycast and others via the
  [URL scheme](#automation-url-scheme).

<br clear="right">

### Undo

There are no confirmation dialogs. After these actions the footer shows
"*action* · Undo" for 10 seconds; click it or press ⌘Z:

- unpinning (**Pin removed**), dragging a pin to another desktop (**Pin
  moved**), re-pinning over an existing target (**Pin updated**), saving the
  window's current size as the layout (**Layout saved**), editing title
  parts, reordering desktops, deleting a profile, dragging a temporary pin.

Undo is one level deep and restores only that action. Any other change in
between (a new pin, a layout step, a profile switch, a URL command) cancels
the pending undo so it can't wipe that change. Not undoable: adding a pin,
layout edits, adding, renaming, importing or switching profiles, and adding or
removing temporary pins. While the cursor is in a text field, ⌘Z undoes the
text edit.

### Pausing

The switch at the top left pauses routing (the menu bar icon changes to a
pause symbol). Windows are still listed, but nothing is moved. Pausing is
saved and survives restarts.

### Where data lives

| File | Contents |
|---|---|
| `~/Library/Application Support/Deskmap/rules.json` | Pins, profiles, known displays, the on/off switch. Written 0.4 s after a change and on quit. |
| `~/Library/Application Support/Deskmap/rules.json.bak` | Copy of an unreadable or partly unreadable `rules.json`, made before it is overwritten. |
| `~/Library/Application Support/Deskmap/session-pins.json` | Temporary pins (window ID + process ID). |
| `<name>.deskmap.json` | An exported profile. |

See [docs/architecture.md](docs/architecture.md#data-files) for the formats.

## Automation (URL scheme)

Deskmap handles `deskmap://` URLs, so Shortcuts, Raycast,
Hammerspoon, Keyboard Maestro or a terminal can control it. If the app isn't
running, macOS starts it first.

| URL | Effect |
|---|---|
| `deskmap://reapply` | Place pinned windows now (same as ↻ / ⌘R) |
| `deskmap://pause` | Pause routing |
| `deskmap://resume` | Resume routing |
| `deskmap://toggle` | Pause / resume |
| `deskmap://profile/<name>` | Switch to the named profile (exact match first, then case-insensitive) |
| `deskmap://profile?name=<name>` | Same; use this for names containing `/` |
| `deskmap://next-profile` | Switch to the next profile, wrapping around (`next` and `nextprofile` also work) |

Command names are case-insensitive, and `deskmap:reapply` (without `//`)
works too. Spaces and non-ASCII characters must be percent-encoded:
`Office Desk` → `deskmap://profile/Office%20Desk`. An unknown command or
profile shows a red error in the app's footer; there is no other
notification.

```sh
open "deskmap://profile/Office"
open "deskmap://reapply"
```

- **Shortcuts**: add an **Open URLs** action with `deskmap://profile/Home`,
  then attach a keyboard shortcut or a Focus automation.
- **Raycast**: create a **Quicklink** such as `deskmap://toggle`.
- **Hammerspoon**:

  ```lua
  hs.hotkey.bind({"cmd", "alt"}, "1", function()
    hs.urlevent.openURL("deskmap://profile/Office")
  end)
  ```

## Keyboard shortcuts

These work while the Deskmap window is open and focused.

| Keys | Action |
|---|---|
| ⌘R | Place pinned windows now |
| ⌘1 / ⌘2 | Show the *Monitor connected* / *Laptop only* setup |
| ⌘Z | Undo the last action (while the "· Undo" link is visible) |
| Return | Confirm the pin panel (**Pin**) |
| Esc | Close the open panel at the bottom |

## Troubleshooting

### Accessibility stops working after a rebuild

Symptoms: the permission card keeps coming back, or Deskmap looks enabled
in System Settings but nothing moves. Each build is ad-hoc signed with a new
signature, and macOS keeps the permission for the old one.

1. Quit Deskmap.
2. In System Settings › Privacy & Security › Accessibility, select
   **Deskmap** and remove it with **−** (turning it off and on again is
   often not enough). Alternatively, from a terminal:
   `tccutil reset Accessibility com.deskmap.app`.
3. Open the new build and grant the permission again.

Signing with a stable identity (`SIGN_IDENTITY=... make app`, see
[Distribution](#distribution)) avoids this.

### Windows land on the wrong desktop or flash and disappear

Check the macOS settings card: "Automatically rearrange Spaces based on most
recent use" must be off, and the app's Dock **Assign To** must be **None**.
See [Required macOS settings](#required-macos-settings).

### A pin doesn't take effect

- Faded chip: another, more specific pin (or a temporary pin) matches the
  window first; hover over the chip to see which one.
- The pin's display isn't connected in the current mode, or the pin has no
  target in this mode (it's in the tray).
- **D5→3** badge: the target desktop doesn't exist; add desktops in Mission
  Control.
- The window belongs to a full-screen app.
- Routing is paused (switch at the top left, pause icon in the menu bar).

### "Moving windows between desktops is not available on this macOS"

The private SkyLight functions for moving windows between Spaces were not
found on this macOS version. Windows are still placed on the right display and
in the right layout, but not moved between desktops.

### "*App* not responding; skipped for now"

An app did not answer Accessibility requests (it is frozen or stopped in a
debugger). Deskmap skips it for 2 s, doubling up to 30 s, so one app
can't stall the others. It is picked up again automatically once it responds.

### Errors about rules.json

- "*N* rules could not be read": broken entries were skipped; the original
  file was saved as `rules.json.bak` first.
- "rules.json belongs to a newer version of Deskmap": a newer version
  wrote this file. The older version reads it but won't overwrite it; changes
  are not saved.

### External display roles swapped

If two external displays share the same left edge, their roles (`external`,
`external-2`) are ordered by vertical position (the lower display first).
After an update that changed this order, drag the affected pins once; the
order stays the same afterwards.

### Reading the log

The engine logs sparingly (moves, give-ups, unresponsive apps, display
changes, sleep/wake) to the unified log. Window titles are redacted.

```sh
log stream --predicate 'subsystem == "com.deskmap.app"' --level info
```

Categories: `routing`, `skylight`, `ax`, `screens`. At launch the `skylight`
category reports whether SkyLight is available and which desktop move method
this macOS uses.

## Architecture

```
app/Sources/Deskmap/
├── DeskmapApp.swift      App entry: MenuBarExtra, AppModel, URL delegate, single instance
├── Localization.swift        L(): English keys, Turkish table in app/Resources/tr.lproj
├── Models/
│   ├── Rule.swift            Rule (pin), Destination, WindowLayout, Mode, title splitting
│   ├── Store.swift           Document (rules.json, pure operations), Profile, Store (publishes, saves)
│   └── UndoBuffer.swift      One-level undo
├── Services/
│   ├── Router.swift          The engine: sweeps, moves, layouts, temporary pins
│   ├── Routing.swift         Pure target selection and retry accounting
│   ├── Accessibility.swift   Window list, titles, frames (AX API), unresponsive-app backoff
│   ├── SkyLight.swift        Reading and moving Spaces (private SkyLight calls)
│   ├── ScreenService.swift   Connected displays, roles, settle delay
│   ├── WindowEvents.swift    AX observers and workspace notifications that trigger sweeps
│   ├── URLCommands.swift     deskmap:// parsing and execution
│   ├── MacSettings.swift     Live check of the required macOS settings
│   └── Log.swift             os.Logger categories
└── Views/                    Map, window rows, chips, pin/profile panels, status cards
```

```mermaid
flowchart LR
    T["⚡ Triggers<br><sub>AX events · desktop switch<br>display change · 2 s timer</sub>"] --> R1
    subgraph Sweep["🔄 Router sweep · background queue"]
        R1["SkyLight<br><sub>desktops per display</sub>"] --> R2["Accessibility<br><sub>windows, titles, frames</sub>"]
        R2 --> R3["Routing.select<br><sub>pure target choice</sub>"]
        R3 --> R4["Apply layout,<br>move to desktop"]
    end
    ST[("📄 rules.json")] --> R3
    R4 --> UI["🧭 SwiftUI map<br><sub>main actor</sub>"]
    UI -. "pin, drag, undo" .-> ST

    classDef trig fill:#0A84FF,stroke:#0A84FF,color:#fff
    classDef step fill:#30D158,stroke:#30D158,color:#000
    classDef data fill:#FF9F0A,stroke:#FF9F0A,color:#000
    classDef ui fill:#5E5CE6,stroke:#5E5CE6,color:#fff
    class T trig
    class R1,R2,R3,R4 step
    class ST data
    class UI ui
    style Sweep fill:#30D15815,stroke:#30D158
```

The **Router** sweeps every 2 seconds and right after window events (new
window, title change, focus change, desktop switch). A sweep runs on a
background queue: it reads the displays' desktops (SkyLight), the window
server list and each app's windows (Accessibility), picks each window's
target with `Routing.select` (the same function the UI uses), then applies the
layout and moves the window to its desktop. The results go back to the main
actor, where SwiftUI shows them.

There is no public API for moving a window to another Space.
`SkyLight.swift` resolves the private calls also used by Hammerspoon and
yabai at runtime with `dlsym` (`SLSMoveWindowsToManagedSpace`,
`SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace`, and
`SLSBridgedMoveWindowsToManagedSpaceOperation` on macOS 26.4+) and picks the
one that fits the macOS version. If a symbol is missing, the app doesn't
crash: it skips the desktop move and still places the window on the right
display and in the right layout.

More detail (sweep steps, retry limits, data formats, localization):
[docs/architecture.md](docs/architecture.md).

## Development

```sh
make check              # debug build
make test               # unit tests (Swift Testing)
make concurrency-check  # build with -strict-concurrency=complete and list warnings (report only)
make app                # release build + .app bundle in build/
make run                # make app, then open it
make dist               # distributable package (see below)
make clean              # delete build/ and app/.build/
```

The tests (`app/Tests/DeskmapTests`, 122 tests in 10 suites) cover pure
logic only: rule matching (including Turkish İ/ı case rules) and title
splitting, layouts and coordinates, `rules.json` schema migrations, document
operations on pins and profiles, import/export, target selection, retry and
backoff helpers, undo validity, map logic, and localization consistency.
They never touch the disk or real windows.

Enable the pre-commit hook to build and test before every commit that
touches Swift files:

```sh
git config core.hooksPath .githooks
```

CI (`.github/workflows/ci.yml`) builds, tests and packages the app on every
push to `main` and on pull requests. The version number comes from the
`VERSION` file.

`scripts/build-and-run.command` (double-click in Finder) quits the running
Deskmap, builds and opens the new copy, and writes the output to
`build/last-build.log`.

### Localization

User-facing text goes through `L("English text")` or
`L("Format %@ with %ld", value, count)`. The English string is the key; the
Turkish translation lives in `app/Resources/tr.lproj/Localizable.strings`.
`LocalizationTests` fails if a key has no Turkish entry, if a Turkish entry is
unused, or if format specifiers don't match. See
[docs/architecture.md](docs/architecture.md#localization).

### Distribution

`make dist` builds a universal (arm64 + x86_64) `Deskmap.app` and packs it
as `build/dist/Deskmap-<version>.zip` (`FORMAT=dmg` or `FORMAT=both` for
a DMG; `VERSION=0.3.1` overrides the version). The default signature is
ad-hoc: recipients must open the app the first time with **right-click ›
Open**, or run `xattr -dr com.apple.quarantine /Applications/Deskmap.app`.
To distribute without Gatekeeper warnings, use a Developer ID and notarize:

```sh
xcrun notarytool store-credentials notary --apple-id ... --team-id ... --password <app-specific>
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=notary make dist
```

`scripts/make-dist.command` runs `make dist` from Finder.

## Limitations

- **Private APIs.** Moving windows between Spaces and finding windows on
  other desktops rely on private SkyLight and Accessibility functions. A macOS
  update can break them. Every desktop move is checked on the next scan; if
  moves keep having no effect, Deskmap switches to a reduced mode (display and
  layout only, desktop moves off) and shows a card with a **Try Again** button.
- **Unknown state means hands off.** If macOS doesn't say which desktop a
  window is on, the window is only listed: it is neither moved nor resized.
- **Desktops must exist.** Deskmap can't create desktops; add them in
  Mission Control. Pins beyond the last desktop go to the last one.
- **Titles must identify the window.** Apps that don't show a workspace or
  document name in the title can only be pinned app-wide or with temporary
  pins.
- **Full-screen windows** are left alone.
- **Two setups only**: monitor connected / laptop only. External displays are
  identified by position (left to right), not by model or serial number.
- **Not instant.** Placement happens on window events. A light check every
  5 seconds catches what events miss (a full scan only when something
  changed, plus one every two minutes); title changes are grouped for a
  second and only count for apps with title-based pins. Apps
  that resize slowly get a few retries.
- **One-level undo**, visible for 10 seconds.
- **Ad-hoc signing** by default, so the Accessibility permission must be
  granted again after each rebuild.
- **Languages**: English and Turkish.

## License

MIT; see [LICENSE](LICENSE).
