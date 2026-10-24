# Deskmap architecture

This document describes how the app is put together: the main types, what
happens during a sweep, the retry limits, the data files, and how
localization works. The [README](../README.md) covers usage.

## Overview

Deskmap is a SwiftUI `MenuBarExtra` app (`LSUIElement`, no Dock icon)
built as a Swift package (`app/Package.swift`, macOS 13+) and wrapped into an
`.app` by `scripts/build-app.sh`. There is no Xcode project.

```
main actor
  rules.json <-> Store ----- document -----> Views (RootView, ScreenMapView, panels)
                   ^                               |
                   +------ pins, profiles ---------+  (user actions)
                   |
                 Router <--- ScreenService (displays, settle)
                   |    <--- WindowEvents  (AX observers, NSWorkspace notifications)
                   v
background queue
  sweep: SkyLight (desktops) + AX (windows) -> Routing.select -> layout + desktop move
```

- `AppModel` creates the three core objects once (`Store`, `ScreenService`,
  `Router`). The SwiftUI `App` owns them as `StateObject`s and `AppDelegate`
  uses the same instances to run URL commands.
- `SingleInstance.exitIfAlreadyRunning()` runs before the router is created:
  if another process with the same bundle ID is running, the new one exits.

## Main types

| Type | File | Role |
|---|---|---|
| `Rule` | `Models/Rule.swift` | A pin: `appName`, `bundleID`, `tokens` (title parts), and an optional `Destination` per `Mode`. Matching and title splitting live here. |
| `Destination` | `Models/Rule.swift` | Display role (`builtin`, `external`, `external-2`, …), desktop number (1-based) and `WindowLayout`. |
| `WindowLayout` | `Models/Rule.swift` | Fractions (`x`, `y`, `w`, `h`, 0…1) of the display's usable area; presets such as `leftHalf`. |
| `Mode` | `Models/Rule.swift` | `docked` (an external display is connected) or `undocked`. |
| `Document` | `Models/Store.swift` | Contents of `rules.json`: rules of the active profile, all profiles, known displays, the on/off switch. All rule and profile operations are pure `mutating` functions on it. |
| `Store` | `Models/Store.swift` | `ObservableObject` that owns the `Document`, saves it (debounced 400 ms, flushed on quit), reports errors to the footer and records undo entries. |
| `ChangeHistory` | `Models/ChangeHistory.swift` | Session timeline of settings changes: launch state plus up to 50 entries (document before/after, optional closure for state outside the document such as temporary pins, which makes the entry undo-only) and a cursor. Undo, redo, return to any row; a new change after undo drops the redo branch but keeps it until the next change so Undo can bring it back. Changes made without a label (URL command, CLI, profile switch) become entries in `Store`'s `didSet`; noise (pause switch, screens, name caches, profile sync) does not. Not saved. |
| `Router` | `Services/Router.swift` | The engine. Sweeps, temporary pins (`sessionPins`), manual one-off moves. |
| `Routing` | `Services/Routing.swift` | Pure helpers: `select` picks a window's target (used by both the engine and the UI), plus layout and move retry accounting. |
| `AX` | `Services/Accessibility.swift` | Window enumeration, frames, `setFrame`, backoff for unresponsive apps. `AccessibilityPermission` polls the trust state. |
| `SkyLight` | `Services/SkyLight.swift` | Private Spaces API: desktops per display, spaces of a window, moving a window to a space. |
| `MoveHealth` / `MoveSupport` | `Services/MoveHealth.swift`, `Services/MoveSupport.swift` | Pure: each desktop move is checked on the next sweep and repeated failures open a circuit breaker (reduced mode); on macOS versions where moves are not verified (15.x, 26.0–26.3) moves are held until the user chooses **Try Anyway**. |
| `ScreenService` | `Services/ScreenService.swift` | Connected displays with roles; `isSettling` while displays are being rearranged. |
| `WindowEvents` | `Services/WindowEvents.swift` | AX observers per app and workspace notifications; publishes a signal that triggers a sweep. |
| `URLCommand` / `URLCommands` | `Services/URLCommands.swift` | Pure parser for `deskmap://` URLs and the code that runs them. |
| `MacSettings` | `Services/MacSettings.swift` | Reads Dock/Spaces preferences for the setup card. |
| `UIState` | `Views/UIState.swift` | View state: the single open bottom panel (`BottomPanel`), drag state, window snapshot, desktop counts. |

## The sweep

A sweep is triggered by:

- a repeating 2 s timer (0.5 s tolerance),
- window events, debounced by 80 ms: window created, focused window changed,
  window deminiaturized, title changed, app launched or activated, active
  Space changed,
- a change to the active rules (new pin, profile switch, …),
- displays settling after a change,
- ⌘R / ↻ / `deskmap://reapply`, which also clears the layout memory.

It does nothing without Accessibility permission, and it pauses while the
displays or the system sleep (resuming right after wake; a safety check in
the timer resumes it if the wake notification was missed). If a sweep is
already running, one more is queued.

Steps, on the router's background queue:

1. **Displays and desktops**: `SkyLight.displaySpaces` returns each display's
   spaces and the visible one. Space types come from this list (0 = normal
   desktop, other = full screen).
2. **Window server list**: `CGWindowListCopyWindowInfo` is read once. It
   serves two purposes: the stage-2 window list below, and the "is this
   window still alive" check for temporary pins.
3. **Windows (Accessibility)**:
   - Stage 1: each regular app's own `kAXWindows` list (reliable for the
     visible desktop).
   - Stage 2: windows the app didn't list (other desktops or displays) are
     taken from the window server list (layer 0, not transparent, at least
     50 pt) and turned into AX elements with `_AXUIElementCreateWithRemoteToken`.
   - Floating panels, system dialogs and unknown subroles are skipped.
   - Each app's AX call durations are measured. A single call of 0.5 s or
     more, or 4 s in total, puts the app on a backoff (2 s, doubling up to
     30 s); the footer lists it as not responding.
4. **Per-window state**: spaces, full-screen flag, frame and minimized state
   are read once and shared by the UI snapshot and the routing below.
5. **Routing**, for each window:
   - `Routing.select`: a temporary pin wins; otherwise the most specific
     matching rule (most title parts) **that has a target in the current
     mode**.
   - Skip if the target display isn't connected, or the window is in a
     full-screen space.
   - The desktop number is clamped to the display's desktop count.
   - **Layout** (only if the window is on a visible desktop and not
     minimized, and this window/target pair hasn't been laid out yet): set the
     frame, read it back, and accept it within 4 pt. Up to 6 attempts; the
     first 4 schedule a quick follow-up sweep (200 ms). Frame writes get a 3 s
     AX timeout; reads use the process-wide 1 s timeout.
   - **Desktop**: if the window isn't on the target space, move it with
     SkyLight. Up to 6 attempts; after that, a new round starts 60 s after the
     last attempt. The counter resets once the window arrives.
6. **Back on the main actor**: layout and attempt records of closed windows
   are pruned; temporary pins whose window has been missing from the window
   server for 3 consecutive sweeps are dropped; the UI snapshot and the
   footer status (last action, unresponsive apps) are published.

If the window server returns an empty list (a transient failure), nothing is
pruned and no temporary pin is dropped.

### Display changes

On `didChangeScreenParametersNotification`, `ScreenService` marks the
displays as settling. Sweeps keep listing windows but move nothing. After
2.5 s without further changes, or at the latest 10 s after the first change,
the displays count as settled and every window is placed again.

From the first notification until the plan has been applied, the change is a
*transition*: a desktop that disappears in it is not a deletion. After the
settle, `Succession` (R2) finds each vanished desktop's successor by the
windows it held, then `PlanApply.compute` (pure) turns the profile's plan for
the new setup into creates, moves, rebinds and removals, and the router
executes them in that order (Mission Control for creating and removing,
SkyLight for moving; each step verified, aborted when the display generation
changes, 30 s cap). Only empty leftovers beyond the plan length are removed,
re-checked right before each removal. The result and the journal are committed
to `desktop-state.json`. Spec: the schema 6 design notes (desktop-names-v2, kept outside the repository).

External display roles come from `DisplayRoles` (`Models/DisplayRoles.swift`,
pure): a display whose UUID is remembered for a role takes it (the most
recently used wins when two are remembered for the same role); the rest fill
the lowest free roles in position order (`minX`, then `minY`, then UUID).
Without any memory this is the old positional order. `AppModel` keeps both
sides in step: the document's `displayRoles` goes to `ScreenService.roles`,
and every settled display list is learned back into the document (not while
settling, never the test display). A docked pin has ordered places
(`Rule.docked` + `dockedNext`); `Routing.resolvePlace` (wrapped by
`Router.resolvePlaces`) picks the first place on a connected display that is
not on hold, else the first connected external in role order with the first
place's desktop number. The applied key uses the resolved target, so the pin
is placed again when its monitor returns. The built-in display is always `builtin`.

### Moving windows between desktops

`SkyLight.move(window:to:)` tries, in order:

1. `SLSBridgedMoveWindowsToManagedSpaceOperation` with the non-exported
   `SLSPerformAsynchronousBridgedWindowManagementOperation` (macOS 26.4+),
   found through the Mach-O symbol table (`MachOSymbols`).
2. `SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace` (macOS 12.7, 13.6,
   14.5 and later).
3. `SLSMoveWindowsToManagedSpace` (older versions).

The chosen path is logged once at launch (`skylight` category).

## Data files

All files live in `~/Library/Application Support/Deskmap/`.

### rules.json (schema version 6)

```json
{
  "version": 6,
  "enabled": true,
  "activeProfileID": "…",
  "setupNoticeDismissed": false,
  "screens": [
    { "id": "builtin",  "name": "Built-in Retina Display", "aspect": 1.54 },
    { "id": "external", "name": "External Monitor",        "aspect": 1.78 }
  ],
  "rules": [
    {
      "id": "…",
      "appName": "Code",
      "bundleID": "com.microsoft.VSCode",
      "tokens": ["Deskmap"],
      "docked":   { "nameID": "N-Nova", "screen": "external", "desktop": 2,
                    "layout": { "x": 0, "y": 0, "w": 0.5, "h": 1 } },
      "undocked": { "screen": "builtin",  "desktop": 1,
                    "layout": { "x": 0, "y": 0, "w": 1,   "h": 1 } },
      "groupID": "G-Drafts"
    }
  ],
  "profiles": [ { "id": "…", "name": "Default", "rules": [ … ],
                  "names": [ { "id": "N-Nova", "name": "Nova", "space": 1234 } ],
                  "plans": { "docked":   { "builtin": ["", "N-AI"],
                                           "external": ["N-Nova", "", ""] },
                             "undocked": { "builtin": ["", "N-AI", "N-Nova"] } },
                  "ghostDesktops": [ … ],
                  "pinGroups": [ { "id": "G-Drafts", "name": "Nova drafts" } ] } ],
  "pendingRemovals": { … }
}
```

- `rules` is the active profile's rule list; it is also written into that
  profile's entry in `profiles`.
- `names` (id, name, bound space ID or `null` = no desktop yet), `plans`
  (setup → display role → ordered name ids, `""` = unnamed desktop; the list
  length is the desktop count) and `ghostDesktops` belong to each profile
  (schema 6). A name has no mode, screen or number: it follows its space ID.
  A rule destination with `nameID` targets that name's desktop; `screen` and
  `desktop` beside it are only a cache of its last place. `pendingRemovals`
  stays at the top level and is shared. Schema 5 files (per-slot
  `desktopNames`, `desktopNameSpaces`, `plannedDesktops`) are upgraded once,
  after a backup in `Backups/pre-migration/`.
- Pin groups: `profiles[].pinGroups` (`id`, `name`; array order is drawing
  order) and `rules[].groupID` (membership; at most one group per pin). Both
  are optional, older versions ignore them and drop them if they save the
  file; empty lists and `nil` are not written. The active profile's groups
  have a working copy (`Document.pinGroups`, never written at the top level);
  every field that moves between the working copy and a profile goes through
  `writeProfileFields` / `readProfileFields`. Invariant (K7): an empty group
  is never pruned implicitly (load, `mutate`, Mission Control deletion,
  `profile-set`, restore); only explicit group actions end with
  `dropEmptyPinGroups()`, which counts members in `rules` **and** in
  `ghostDesktops[*].pins[*].rule`, so a deleted desktop's group comes back
  with its ghost. Readers treat an unknown `groupID` as ungrouped. The Router
  compares `Rule.routingProjection` (rules without `groupID`), so a group
  change never re-places windows (K11).
- `tokens: []` means "all windows of the app".
- Reading is lenient: a single broken rule is skipped (the file is copied to
  `rules.json.bak` first and the footer shows how many were skipped).
- v1 files (`app` / `match` fields) and v2 files (no profiles) are migrated
  on read; their rules become one profile.
- A file whose `version` is higher than 6 was written by a newer Deskmap:
  it is read, but never overwritten.
- The keys above are a stable format; a new UI language doesn't change them.
  Profile names are user data and are kept as typed.

### desktop-state.json

Physical facts shared by all profiles, not part of backups or exports
(replaces `desktop-spaces.json`, which is read once for the upgrade):
`displays` (role, display UUID, space IDs in order) and `contents` (window
ID, process ID, bundle ID per space; no titles) as of the last stable sweep;
`parked` (unnamed windows that left a monitor, with the desktop they came
from, dropped after the window is gone or after 14 days); `bootTime`; and
`transition`, set while a plan is being applied, so a crash can be resumed at
the next launch. `DESKMAP_DATA_DIR` moves the whole data folder.

### session-pins.json

A list of temporary pins: `windowID`, `pid`, `bundleID`, `appName`, `title`,
`destination` (which may carry a `nameID`). At launch only entries whose window ID still exists in the
window server with the same process ID are restored.

### Profile export (`<name>.deskmap.json`)

```json
{ "kind": "deskmap-profile", "version": 5, "name": "Office",
  "exportedAt": "2026-09-14T10:00:00Z", "screens": [ … ], "rules": [ … ],
  "names": [ { "id": "N-Nova", "name": "Nova" } ],
  "plans": { "docked": { "external": ["N-Nova", "", ""] } } }
```

Version 5 adds optional `pinGroups` (group ids are renewed on import and the
rules' `groupID`s remapped; an unknown `groupID` is dropped). Version 4 and
version 3 files (`desktopNames`, `plannedDesktops`) still import. Names are exported without their desktop. On import, rule IDs are regenerated, names start without a desktop (placed by plan position at the next plan application), the name is made unique (`Office (2)`),
and unknown display roles from `screens` are added to the map. A plain
`rules.json`-style file with a `rules` array is accepted too.

## URL scheme

`URLCommand.parse` is a pure function (unit-tested): the scheme must be
`deskmap`; the command comes from the host (`deskmap://reapply`) or
from the first path component (`deskmap:reapply`), case-insensitively.
`profile` takes the name from the `name` query item or from the rest of the
path (percent-decoded). The pin group commands (`group-add`, `group-rename`,
`group-remove`, `group-set`) resolve `<group>` with
`Document.resolvePinGroup` (id, then case-insensitive exact name; several
groups with that name is an error). URLs arrive through
`NSApplicationDelegate.application(_:open:)`, which works for a menu bar app
even on a cold start.

## Localization

- `Localization.swift` defines `L(_ key: String)` and
  `L(_ key: String, _ arguments: CVarArg...)`. The key is the English text.
  Lookup uses `Bundle.main`'s `Localizable` table; without a table (tests,
  `swift run`) the key itself, English, is returned.
- `app/Resources/tr.lproj/Localizable.strings` holds the Turkish text;
  `app/Resources/en.lproj/Localizable.strings` is intentionally empty so that
  the bundle declares English. `build-app.sh` copies every `*.lproj` folder
  into the app, and `Info.plist` declares `CFBundleDevelopmentRegion = en`
  and `CFBundleLocalizations = [en, tr]`.
- Rules for keys, enforced by `LocalizationTests`:
  - a key is a single string literal, with no `+` and no `\(...)`;
  - variable parts use format specifiers (`%@`, `%ld`); a translation that
    reorders them uses positional specifiers (`%1$@`, `%2$ld`);
  - every key has a Turkish entry, every Turkish entry is used, no key is
    duplicated, and the specifiers of key and translation match.
- Plurals are handled in code (`n == 1 ? L("1 pin") : L("%ld pins", n)`).
- Not localized on purpose: the names of macOS settings on the setup card
  (they must match what System Settings shows in English), log messages, and
  data keys.

To add a language, create `app/Resources/<code>.lproj/Localizable.strings`,
add the code to `CFBundleLocalizations` in `scripts/build-app.sh`, and extend
`LocalizationTests` to check the new table.

## Logging

`Log` (`Services/Log.swift`) defines four `os.Logger` categories under the
subsystem `com.deskmap.app`: `routing` (moves, give-ups, temporary pin
expiry), `skylight` (availability and move path), `ax` (unresponsive apps,
observer registration), `screens` (display changes, sleep/wake). Nothing is
logged per sweep. Window titles are logged as `.private`.

## Tests

`app/Tests/DeskmapTests` (Swift Testing):

| Suite | Covers |
|---|---|
| `RuleTests` | Matching (bundle ID vs. name, Unicode case rules incl. Turkish İ/ı and ß), specificity order, title splitting, `sameKey`, per-mode targets |
| `LayoutTests` | `WindowLayout` fractions, clamping, labels, Cocoa → AX coordinate conversion, frame tolerance |
| `DocumentCodableTests` | `rules.json` v1/v2/v3 decoding, destination defaults, skipped broken rules, newer-version detection |
| `DocumentOperationsTests` | Desktop mapping and its inverse, desktop reordering, pin/unpin, profiles, import/export |
| `RoutingTests` | `Routing.select` and layout retry accounting |
| `RouterSelectionTests`, `WindowDriftBugTests`, `WindowDriftFixTests` | The real Router's sweep selection and merge on fake screens and windows (`RouterHarness`, `Router.sweepSelection`): sticky bindings, generic-title grace, exact title owners, unpin, paused/settling routing; group moves and the shadow list with the Router's binding |
| `EngineHelperTests` | Backoff decision, AX timeouts, window server filters, move retries and cooldown, live-window merge, pause safety, settle cap, external display order, space types, `Router.placement` |
| `ChangeHistoryTests` | Multi-step undo/redo, discarded redo branch and its undo, return to a row, 50-entry limit, noise vs. untracked changes, companion entries |
| `MapLogicTests` | Shadowed pins, missing-desktop badge |
| `TokenEditingTests` | `Document.setTokens` (identity, key collisions) and token picker helpers |
| `PinGroupCodableTests`, `PinGroupModelTests`, `PinGroupStoreTests` | Pin group fields (old files byte-identical, lenient reading), document operations (K7, ghosts, profile scope, copy/import), one undo step per action |
| `PinGroupLayoutTests`, `RouterProjectionTests`, `PinGroupURLTests` | Group boxes on the map, the Router's group-blind rule key, URL commands and `status.json` |
| `LocalizationTests` | Key/translation consistency (see above) |

The tests never create a `Store` or `Router`, so they never touch
`rules.json` or real windows.
