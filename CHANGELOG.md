# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The version
number comes from the `VERSION` file.

## [Unreleased]

### Changed

- **Desktop names v2 (`rules.json` schema 6)**: a name now belongs to one
  physical desktop and follows it across displays, reordering and
  plug/unplug; it no longer has a mode, screen or number. Each profile has a
  plan per setup (which names live where, how many desktops per display).
  Plugging or unplugging the monitor applies the plan of the new setup: named
  desktops move with all their windows, unnamed windows from a monitor
  desktop are parked on laptop desktops and return on replug (also with
  another monitor), missing desktops are created, and only empty leftover
  desktops beyond the plan are removed (each re-checked empty right before).
  A desktop that vanishes because of a display change is no longer a
  deleted-desktop row; rows come only from real deletions. A profile switch
  and **Copy the Laptop only plan here** move windows to match the plan but
  never remove a desktop. Removing a desktop that has windows now asks first.
- **Pins can target a name**: the pin panel and **Send to** list names first;
  a pin follows the named desktop and waits (nothing moves) while the name has
  no desktop. `deskmap://pin/<window>?name=<name>` does the same.
- **Upgrade from schema 5** on first launch: the old files are saved to
  `Backups/pre-migration/` (never pruned), names are matched to desktops by
  where their pinned windows are, wrongly created deleted-desktop rows are
  removed and their pins restored. A card reports the result and offers
  **Remove N empty desktops** and **Undo upgrade**. Nothing is moved or
  removed during the upgrade; an older Deskmap opens the new file read-only.
- `deskmap desktops` lists names with their live place and planned place per
  setup, and the plans; `status.json` gains `names` and `plans`. Profile
  export is version 4 (names and plans without desktop IDs); version 3 files
  still import. Runtime desktop facts move to `desktop-state.json`.
- `deskmap://quit` quits the app and `DESKMAP_DATA_DIR` points it at another
  data folder, for scripts and tests.

- **Desktop names belong to a profile**: names, their desktop bindings,
  deleted-desktop rows and planned desktops are now kept per profile. A new
  profile starts without names, renaming in one profile never changes
  another, switching shows the target profile's names immediately and only
  creates missing planned desktops. Duplicate copies them; export/import
  carries names and planned desktops. Mission Control moves and deletions
  update every profile, and each profile that named a deleted desktop gets its
  own deleted-desktop row. `rules.json` schema 5: older files are split by use
  (a name goes only to profiles with a pin on that desktop); an older Deskmap
  opens the new file read-only.
- **Copy the Laptop only plan here** (⋯ menu) also copies the laptop desktop
  names into the Monitor connected plan (the same name elsewhere in that plan
  is removed), keeps laptop desktop bindings, grows the plan, and works when
  the laptop setup has only desktop names or planned desktops. Queued desktop
  removals of the active profile on the copied screens are cleared; other
  profiles' queued removals stay.
- A name that cannot find a free desktop number (its desktop still exists)
  now stays on a name-only deleted-desktop row in its own profile instead of
  disappearing; no pins move.

### Fixed

- **Desktop names no longer get lost through the other setup's plan.** Removing
  a laptop desktop row from the setup that is not active used to drop the
  active setup's names on the same and later numbers right away (their pins
  stayed); now names shift together with their pins when the removal actually
  runs. A laptop desktop that is named elsewhere (in the other setup or on the
  monitor) can no longer be queued for removal from a plan where it looks
  empty. Queued removals of the other setup no longer make live named desktops
  look deleted (which turned them into deleted-desktop rows and took their pins
  and their other-setup counterparts along), and a name whose desktop still
  exists is never treated as deleted.

### Added

- **Automatic backups**: the app backs up all profiles, pins and desktop
  names hourly (kept 24 hours), daily (kept 7 days) and weekly (kept
  forever) under `Application Support/Deskmap/Backups/`. Restore from
  **Settings › Backups** (also **Backups…** in the profile panel) or with `deskmap backups` /
  `deskmap backup-restore <id>`; the current state is backed up first and the
  restore can be undone. Replaces the external `profile-backup.sh` script.

## [0.5.0] — 2026-09-30

The first release with a download: a universal `Deskmap.app` on the
[releases page](https://github.com/cnkndmr/Deskmap/releases). The map grew a
sidebar and a layout grid, pinned windows can be set free for a while, desktops
can be added, removed and reordered from the map, and the menu bar icon opens
on the window you were using.

### Added

- **Right-click menu**: right-click the menu bar icon while a pinned window
  is in front to give it free movement without opening the map: *Free move*
  lists the same durations as the panel. While the window is free the menu
  shows the time left and *End now*. With no pinned window in front the
  right-click does nothing, as before.
- **Opens on the window you were using**: clicking the menu bar icon selects
  the window you last clicked, as if you had clicked its row: the map scrolls
  to it and its panel opens (pin settings, or a pin draft if it has no pin).
  A panel left open from last time no longer stays on an unrelated window.
  The draft follows the window's size and position while it is open, until
  you choose a layout yourself.
- **Menu bar badge**: the menu bar icon shows how many open windows have no
  pin in either setup (the *Unassigned windows* count; 9+ above nine, none
  at zero). The badge is cut into the template icon, so it follows light and
  dark menu bars; VoiceOver reads the count. Full-screen windows are not
  counted.
- **Layout grid**: the layout editor draws the target display at its real
  shape as a grid (12 × 8 cells, 24 × 6 on ultrawide displays); drag across
  it to choose an area. The percent fields stay for fine tuning.
- **Presets per display shape**: ultrawide displays get thirds, two thirds,
  quarters and a centered half; other displays get halves, 70 / 30 and
  30 / 70 on both sides, top and bottom halves, corners and center. Every
  preset list is mirror-symmetric (checked by a test).
- **Fixed size**: a layout can be a size in points (e.g. 1400 × 900) at one
  of nine anchor points, the same on every display and fitted to the usable
  area when larger. Turning it on keeps the current area (edge-to-edge sizes
  exactly) and picks the anchor from the edges it touches. If an app refuses
  the size, the window is still placed at the anchor with the size it
  accepts. *Use current size and position* keeps a fixed layout fixed.
  Older rule files read unchanged; rules.json is now schema 4, so an older
  Deskmap opens it read-only instead of dropping fixed sizes, and every
  fixed layout also stores its proportional equivalent for older readers.
- **The window grows for the pin panel**: clicking a window or pin opens its
  panel below the map and the window grows downward; the map keeps its
  height. Only when the screen is too short does the map give up the
  difference.
- **Wider map with a sidebar**, sized relative to the screen it opens on
  (53 % × 70 % of the usable area, 660–1100 × 480–900 pt, never larger than
  the screen; about 900 × 750 on a display with 1710 × 1074 pt usable). *Different between setups* and
  *Unassigned windows* sit in a left sidebar that is always visible, so a
  window is dragged sideways onto a desktop instead of up the whole map.
- **Auto-scroll while dragging**: holding a dragged item near the top or
  bottom edge of the map scrolls it, faster the closer to the edge; the
  desktop under the cursor is highlighted even while the map scrolls. A drag
  that starts inside the edge band scrolls only after leaving it once.
- **Two sidebar boxes.** *Different between setups* lists pins that are
  pinned only in the other setup, only in this one, or sent to another display
  or desktop in the other setup (with that place shown). *Unassigned windows*
  (both setup tabs, collapsible) lists open windows with no pin in either
  setup; in the current setup's tab dragging one moves it once, in the other
  setup's tab dropping it (or pressing its pin) opens a pin for that setup
  and does not move the window.
- **Free move**: a pinned window's panel has a timer button (1, 5, 15, 30 or
  60 minutes). For that time Deskmap does not put the window back, so it can
  be moved and resized freely; the row shows the time left, "+5 min" extends
  it, "End now" stops it. When the time is up the pin applies again (desktop
  and layout). Not saved; ends when the window closes, and ends early when the
  window's pin is removed or changed (moved, new layout, other profile or
  setup), so the new pin applies at once.
- The "+ Desktop N" row under each connected display now adds a real desktop
  when clicked: Mission Control opens for a moment, Deskmap presses that
  display's **+** button through Accessibility and closes it again. The same
  is available as `deskmap://add-desktop/<screen>`. On macOS 26 Mission
  Control's tree lives in `WindowManager`, not the Dock (measured); both are
  searched.
- "+ Desktop N" also works in the setup that is not active (e.g. Laptop only
  while a monitor is connected): the desktop is planned (shown as "doesn't
  exist yet", can take pins, ⌘Z undoes, right-click removes the last empty
  one) and Deskmap creates the missing desktops through Mission Control when
  that setup becomes active. Plans are stored per setup and display in
  `rules.json` (`plannedDesktops`).
- Desktops can be removed: right-click a desktop row in the active setup →
  "Remove Desktop N" (or `deskmap://remove-desktop/<screen>/<n>`). Mission
  Control removes it (`AXRemoveDesktop`); pins on later desktops move up by
  one and pins on the removed one move to the previous desktop, session pins
  included. The last desktop of a display is never removed, nothing is
  touched if Mission Control's list does not match SkyLight's, and there is
  no ⌘Z (the desktop itself cannot be brought back).
- Every desktop row now has "Remove Desktop N", in either setup, with no
  other limits. In the setup that is not active the removal is queued
  (`pendingRemovals` in `rules.json`, with the space ID when the display is
  connected) and done through Mission Control when that setup becomes
  active; pins shift at once and ⌘Z undoes it. The laptop display's desktops
  are shared by both setups, so removing one at once would also remove it
  from the active setup. Rows that exist only as a plan or pin just
  renumber. The separate "Remove this planned desktop" item is gone.
- Dragging a desktop row in the active setup now reorders the desktops for
  real: every window on that display moves to its desktop's new position
  (pinned or not; "All Desktops" windows stay). macOS offers no way to
  reorder spaces from outside (no Mission Control action, the SkyLight call
  needs SIP off), so the contents move instead. ⌘Z moves them back.
- Full-screen and Split View spaces now appear on the map as read-only purple
  rows, in their real Mission Control position between the desktops. Before,
  a window in a full-screen space vanished from the map entirely.
- `appstore/probe/`: a two-build probe (sandboxed and not) that measures
  whether the Accessibility API works inside the App Sandbox. Result on
  macOS 26.6.2: with the permission granted, the sandboxed build still cannot
  read another app's windows (−25204), so a Mac App Store edition of Deskmap
  cannot place windows. `docs/distribution.md` and
  `appstore/submission.md` now cite the measurement. The unfinished
  store edition (an `APPSTORE` compile flag without private API) waits on the
  `deskmap-appstore` branch.

### Changed

- App Store material lives in one folder, `appstore/`: the submission
  checklist (was `docs/app-store-submission.md`), the listing copy (was
  `docs/listing.md`), the screenshot script (was
  `scripts/make-store-shots.swift`) with its output in
  `appstore/screenshots/`, and the sandbox probe.

### Fixed

- The map no longer closes when you drag the row of the window you were
  just using to a desktop on another display. macOS handed focus back to that
  window as it changed displays; Deskmap now comes to the front while a row
  or chip is dragged and returns focus when the map closes.
- Starting to drag a window no longer pushes the map down by a line: the drag
  hint moved to the footer, so a click with a slight slip cannot drop the
  window (or its pin) on the desktop above.
- An open pin draft now follows its window when the window moves to another
  desktop (dragged on the live map or moved outside Deskmap); *Pin* used to
  save the old desktop and pull the window back.
- A window opened shortly after its app was last scanned no longer drops out
  of the map and sidebar for up to 30 seconds when it moves to another
  desktop; only windows the scan could not find wait for the next rescan.
- A proportional layout whose size the app refuses (minimum size larger than
  e.g. *Right 30%* or *Bottom half*) left the window hanging off the right or
  bottom edge of the display; it is now pulled back inside the usable area
  with the size the app accepts, as fixed sizes already were.
- Layouts touching the top edge of an external display were given up after
  every launch ("did not take layout … in 6 attempts"), and centered fixed
  sizes sat half a menu bar too high: the first screen measurement ran before
  the app had finished launching, when an external display's usable area
  still comes back as the full frame (menu bar not subtracted), and nothing
  re-measured it until the next display change. The usable area is now
  measured again once launch has finished and shortly after; a change
  re-applies all pins. Found by trying fixed-size pins on a real 5120 × 1440
  display.
- A queued desktop removal or a desktop plan ran only once per session for
  the same setup, display and count: after it succeeded, or was cut short by
  a display change, the same request was silently skipped until the next
  launch. Only a real failure now blocks a retry.
- Review fixes for today's desktop features (multi-agent review, each
  finding checked by two skeptics):
  - Add/remove through Mission Control failed when "Displays have separate
    Spaces" is off (the display is reported as "Main"); the primary display
    UUID is now passed through.
  - Escape was posted even when Mission Control never opened, reaching the
    frontmost app; it is now sent only while Mission Control's tree is up.
  - A queued removal that failed cleared the whole queue although pins had
    already shifted; now only done (or vanished) entries leave the queue,
    a failure is reported and retried on the next launch. Executing a queued
    removal now also shifts session pins and the other setup's pins.
  - Removing a desktop renumbered only the active profile and setup; it now
    renumbers every profile, and a live removal every setup of that display
    (the laptop display's desktops are shared).
  - A plan stayed as a permanent minimum and re-created desktops the user
    deleted later; it is cleared once met, and creation re-reads the live
    count instead of a pre-settle snapshot.
  - Dragging a desktop onto plan/pin rows beyond the real desktops merged
    two desktops' windows; windows now move only between real desktops,
    read their current desktop live (fast second drag or ⌘Z), and ⌘Z is
    only registered when windows really moved.
  - The remote-window scan could stall a sweep on a hung app and repeat 1000
    IPC calls per helper window: it now runs once per app per 30 s (one pass
    caches every window, ~60–100 ms measured), stops on a timeout or a
    0.3 s budget, and skips apps already slow in that sweep. Apps do not
    always keep AX elements for windows on other desktops, so some windows
    may still be missed (same limit as alt-tab-macos).
  - Add/remove/plan operations are serialised; a failed "+" is reported.
- Many windows on desktops that are not visible were missing from the map
  and could not be routed (Claude, ChatGPT, Finder…; their pins showed as
  "no open window"). The AX remote token carried the window number where an
  AX element ID belongs; it now scans element IDs (alt-tab-macos method),
  accepts only `AXWindow` elements (children return the same window
  number), caches the IDs and retries a window that was not found every
  30 s (~20 ms per scan, measured).
- Ghost windows on Desktop 1: a helper window that sits on no space at all
  (cmux keeps an invisible 64 pt one) was placed on "Desktop 1" by the
  frame fallback, so the app looked open there although its real window was
  on another desktop. Windows whose space list reads empty are now left out
  of the map and routing; hidden (⌘H) and minimized windows keep their space
  and still show (measured on macOS 26).
- A window on several desktops ("All Desktops") now shows on the desktop
  currently visible on that screen, not always on the first one.
- A window whose spaces are known but match no desktop is no longer guessed
  onto Desktop 1 by its frame.

## [0.4.0] — 2026-09-16

The release that made the app something you can hand to someone else: it
speaks English, it has a guide and screenshots, and it has a name that says
what it does.

### Added

- English user interface with a Turkish translation. All user-facing text
  (window, cards, panels, tooltips, VoiceOver labels, footer errors, undo
  labels, file dialogs) goes through `L("…")` with English keys; the Turkish
  table is `app/Resources/tr.lproj/Localizable.strings`. The app follows the
  macOS language order and falls back to English. `build-app.sh` copies the
  `.lproj` folders and declares `CFBundleDevelopmentRegion = en` and
  `CFBundleLocalizations = [en, tr]`. `LocalizationTests` check that every
  key is translated, no translation is stale or duplicated, and format
  specifiers match.
- Documentation: README rewritten in English (install, required macOS
  settings, quick start, pins/profiles/modes, URL scheme, shortcuts,
  troubleshooting, architecture, development, limitations) and
  `docs/architecture.md` (sweep steps, retry limits, data formats,
  localization, tests).
- User guide in both languages: `docs/guide.md` and `docs/kilavuz.md` take a
  new user from install to the first pin in ten minutes, with screenshots;
  `docs/site/index.html` is the same guide as one page with an EN/TR switch
  that also swaps the screenshots.
- `docs/privacy.md` (nothing is collected, sent or logged — window titles
  never reach the log), `docs/distribution.md` (why the Mac App Store is
  closed to this app: the sandbox blocks the Accessibility write API and
  moving windows between Spaces needs private SkyLight calls; Developer ID
  and notarization instead) and `docs/naming.md` (the name is taken by an
  unrelated macOS product; candidates checked against the store catalogue).
- Screenshot mode: `Deskmap --shots <dir>` renders the real interface with
  demo data — fabricated displays, profiles, pins and windows — and writes
  PNGs, without touching `rules.json`, the Accessibility permission or a
  running copy (`app/Sources/Deskmap/Demo/`). Run it with
  `-AppleLanguages "(tr)"` for the Turkish set.
- Bundle metadata for distribution: `LSApplicationCategoryType`
  (productivity) and `NSHumanReadableCopyright`. The displayed name is the
  `DISPLAY_NAME` variable in `build-app.sh`, and `BUILD_ROOT` can point the
  build somewhere other than `build/` (useful while a copy is running from
  there).
- One-level undo. After unpinning, deleting a profile, reordering desktops,
  dragging a pin to another target, re-pinning over an existing target ("Pin
  updated"), or editing title parts, the footer shows "*action* · Undo" for
  10 s; ⌘Z works too. Dragging a temporary pin, and temporary pins shifted by
  a desktop reorder, are undone as well (the entry carries a closure for
  state outside the document). The entry also stores the document after the
  action: if anything else changes it in between (a new pin, a layout step, a
  profile switch, a URL command), the entry is dropped so undo can't erase
  that change. Layout steps and profile switches are not recorded
  (`Models/UndoBuffer.swift`, `Store.undo()`).
- Accessibility labels for icon buttons and switches, using the same words as
  their tooltips: on/off switch, mode selector, re-apply, quit, pin button,
  close buttons, add/import profile, layout presets.
- Title parts can be edited in the pin panel without typing: if a window
  matching the pin is open, its title is split, the current parts are
  preselected, "All windows" can be chosen, and the number of matching
  windows updates live; **Apply** saves. A selection that would give the same
  key as another pin is refused with an orange explanation. Without a
  matching window the parts are read-only (`TokenPicker`, `Document.setTokens`).
- Shadowed pins: a pin that matches a window but loses to a more specific pin
  or a temporary pin is shown as a faded chip on its target desktop; the
  tooltip says which pin matches first (`ScreenMapView.shadows`).
- Missing-desktop badge: if a pin's target desktop doesn't exist on the
  connected display (the router clamps to the last one), the row and chip
  show an orange "D5→3" badge ("M5→3" in Turkish); the tooltip suggests adding
  a desktop in Mission Control or dragging the pin.
- Keyboard shortcuts while the window is focused: ⌘R re-apply, ⌘1 / ⌘2 mode
  selector (Monitor connected / Laptop only), ⌘Z undo, Esc closes the open
  bottom panel. Tooltips mention the shortcut.
- Getting Started card: three steps above the map while Accessibility is
  granted and the active profile has no pins or temporary pins; disappears
  with the first pin.
- Footer: if the SkyLight calls are missing, an orange "Moving windows between
  desktops is not available on this macOS; only display and layout are
  applied" (below errors and unresponsive-app messages). The router's last
  action fades after 30 s.
- `deskmap://` URL scheme: `reapply`, `pause`, `resume`, `toggle`,
  `profile/<name>` (or `profile?name=<name>`), `next-profile`. Works with
  Shortcuts "Open URLs", Raycast, Hammerspoon `hs.urlevent.openURL` and `open`
  in a terminal. URLs arrive through the AppKit delegate
  (`application(_:open:)`); parsing is the pure `URLCommand.parse`
  (`Services/URLCommands.swift`). Unknown commands or profiles show an error
  in the footer.
- Single-instance guard: if another Deskmap with the same bundle ID is
  running, the new one quits before creating a router, so two routers never
  fight over the same windows.
- macOS settings card: "Automatically rearrange Spaces", "switch to a Space
  with open windows", "Group windows by application" and "Displays have
  separate Spaces" are checked live; while one is wrong the card can't be
  dismissed, and "Open Desktop & Dock" opens the right pane. The Dock "Assign
  To: None" reminder is hidden with "Got It" (`setupNoticeDismissed`).
- Unit tests (`make test`, Swift Testing): rule matching and title
  splitting (Turkish İ/ı/I/i, ß–SS and ligature pairs don't match:
  `lowercased()` semantics), `WindowLayout`, coordinate conversion,
  `rules.json` schema migrations (v1/v2/v3), document operations on pins and
  profiles, export/import, `Routing` target selection, engine helpers
  (backoff decision, move cooldown, external display order, space-type map,
  `Router.placement`, window server filters `AX.serverWindow` /
  `AX.liveEntry`, `Router.liveWindows`, `Router.shouldResumeFromPause`,
  `ScreenService.settleDelay`), undo, map logic and localization. 122 tests.
  CI and `.githooks/pre-commit` run them.
- `VERSION` file at the repository root; `build-app.sh` and `make-dist.sh`
  read it (the `VERSION` environment variable still wins).
- `make dist`: universal (arm64 + x86_64) build, signing, optional
  notarization and a `build/dist/*.zip` / `.dmg` package
  (`scripts/make-dist.sh`, `scripts/make-dist.command` for Finder).
  `build-app.sh` accepts `VERSION`, `UNIVERSAL` and `SIGN_IDENTITY`.
- Unified logging (`Services/Log.swift`, `os.Logger`, subsystem
  `com.deskmap.app`, categories `routing`, `skylight`, `ax`, `screens`):
  SkyLight status and move path at launch; every desktop move, layout/move
  give-ups, unresponsive-app backoff start/end, display settling, sleep
  pause/resume and temporary-pin expiry. Window titles are private; nothing
  is logged per sweep. Watch with
  `log stream --predicate 'subsystem == "com.deskmap.app"' --level info`.
- `make concurrency-check`: a clean build with `-strict-concurrency=complete`
  that lists the warnings (Swift 6 preparation; package settings unchanged,
  separate build directory `app/.build/strict`).
- `scripts/build-and-run.command`: double-click in Finder to quit the running
  Deskmap, build and reopen it; output goes to `build/last-build.log`.

### Changed

- **The app is now called Deskmap.** The old name described the mechanism,
  not the job, and it belonged to an unrelated macOS product already
  (spacerouter.org ships a "SpaceRouter Proxy.app"). The rename goes all the
  way down: Swift module and target, bundle identifier `com.deskmap.app`,
  logger subsystem, `Deskmap.app`, the `deskmap://` URL scheme, the
  `~/Library/Application Support/Deskmap/` folder and `.deskmap.json`
  profile exports. Nothing an existing user set up breaks:
  `spacerouter://` URLs are still accepted, old `.spacerouter.json` exports
  and `spacerouter-profile` files still import, and on first launch
  `rules.json`, `rules.json.bak` and `session-pins.json` are copied out of
  the old folder — copied, not moved, so the old one is left untouched.
  Two things do need a hand: the Accessibility permission has to be granted
  again (new identifier, new signature) and **Launch at login** has to be
  switched back on. See [docs/naming.md](docs/naming.md).
- Store and landing-page screenshots: `swift scripts/make-store-shots.swift`
  puts the real captures on a backdrop with one line of copy and writes
  2880×1800 and 1280×800 frames in both languages (`docs/store/`, generated,
  not checked in). The raw captures are 1120×1280, which App Store Connect
  does not accept.
- `app/Resources/PrivacyInfo.xcprivacy`: no data collected, no tracking, one
  required-reason API (user defaults). Copied into the bundle by
  `build-app.sh`, and [docs/app-store-submission.md](docs/app-store-submission.md)
  lists what else a submission would need.
- New icon: a map marker whose head is a window. It is drawn in code
  (`scripts/make-icons.swift`, one command to regenerate every size and the
  `.icns`), and the sizes below 64 px drop the title bar and its dots, which
  at that size are only smudges. The menu bar template is the same marker as
  a single silhouette with the window cut out of it.
- Log messages, `make help`, build script output and CI step names are in
  English. Code comments stay in Turkish. The CI job is now called "Swift
  build and tests".
- The layout editor's margin labels column is wider (24 → 42 pt) so the
  English labels fit.
- A new document's first profile is named after the UI language ("Default" /
  "Varsayılan"); existing profile names are user data and never change.
- Bottom panel state is a single value (`UIState.panel: BottomPanel?`: pin
  draft, pin info, temporary pin, profile), so only one panel is open at a
  time. `RootView.swift` (894 lines) was split into UIState / RootView /
  PinPanel / RulePanels / LayoutEditor / StatusCards / TokenPicker; four
  copies of the panel frame became one `bottomPanelChrome()`. Same behaviour.
- The "N pins" counter in the toolbar counts the selected mode; "· M
  temporary" is shown only when the selected mode is the current one
  (temporary pins are only listed there).
- Rule and profile logic (`pin`, `unpin`, `moveDesktop`, profile switch /
  copy / delete, export/import) are pure operations on `Document`; `Store`
  only calls them, publishes and saves. Same behaviour.
- Target selection lives in one place (`Routing.select`): the router, the
  window rows and the map pick the same rule (temporary pin, otherwise the
  most specific rule with a target in this mode). Layout attempt counting
  moved to `Routing` too.
- Fewer IPC calls per sweep, with the same window set and decisions: the
  window server (`CGWindowListCopyWindowInfo`) is read once per sweep (the
  stage-2 list and the liveness check share it); space types come from the
  `displaySpaces` result (instead of `SLSSpaceGetType` per window, falling
  back to IPC for unknown IDs); each window's spaces, frame and minimized
  state are read once and shared by the snapshot, placement and routing
  (previously 2–3 times for routed windows).
- The sweep timer has a 0.5 s tolerance (lets the system coalesce timers).
- Sweeps stop while the displays or the system sleep (`screensDidSleep` /
  `willSleep`) and run once right after waking.
- While a display change settles (2.5 s), windows are listed but not moved
  (`ScreenService.isSettling`); after settling, everything is placed again.
- A manual move (dragging on the map) builds the AX element directly from the
  last sweep's pid; rescanning all apps happens only if that fails.
- The desktop move limit and cooldown are `Routing.maxMoveAttempts` /
  `Routing.moveRetryInterval` (pure `recordMoveAttempt`).
- Strict concurrency (`-strict-concurrency=complete`) warnings fixed: 16 → 0.
  `SkyLight` is `Sendable` (all stored properties are `let`);
  `DropTargetPreference.defaultValue` is `static let`; the AX backoff table is
  `nonisolated(unsafe)` behind a lock; a constant key replaces
  `kAXTrustedCheckOptionPrompt`; timers and observer tokens released in
  `deinit` (Router, ScreenService, WindowEvents, AccessibilityPermission,
  Store) are `nonisolated(unsafe)`; only the notification name crosses to the
  main actor from sleep notifications. Same behaviour.
- `Rule.split` compiles its separator pattern once (previously on every
  call); `Rule.matches` keeps a lowercased copy of the tokens (refreshed when
  `tokens` changes) and `Routing.select` lowercases a title at most once per
  window. Matching decisions are unchanged: `lowercased()` semantics are kept;
  `.caseInsensitive` search was not used because it would also match ß/SS and
  ligature pairs.
- External displays with the same `minX` are ordered by `minY`, then UUID.
  With such an arrangement the `external` / `external-2` roles may swap once
  after updating; dragging the affected pins once fixes it, and the order
  stays stable afterwards.
- Display settling now ends after at most 10 s: if changes never stopped
  (flaky cable, constant notifications), the 2.5 s wait kept restarting and
  routing could stay off forever. 10 s after the first change settling is
  forced (logged as "hard cap") and windows are placed again
  (`ScreenService.settleDelay`).
- Frame writes (`AX.setFrame`) give the window element a 3 s timeout, so slow
  but working apps (large documents, busy browsers) still get resized. Reads
  keep the process-wide 1 s timeout; a frozen app is put on backoff before it
  reaches `setFrame`. The verification read after the write is unchanged.

### Fixed

- Clicking the active profile chip while the temporary pin panel was open did
  nothing (`closePanels()` didn't clear the session selection and an if-else
  chain hid the profile panel); gone with the single panel value. A pin panel
  whose rule was deleted, or disappeared with a profile switch, closes itself.
- A pin that matched a window but lost to a more specific rule was not shown
  on the map at all (the row showed the winner and the chip was hidden).
- "Launch at login" reads the real `SMAppService` status: it refreshes when
  the registration changes and on every sweep (turning it off in System
  Settings unchecks the box); `.requiresApproval` shows an orange "Approval
  needed" link that opens Login Items; register/unregister errors appear in
  the footer (previously swallowed by `try?`). When the app runs outside
  /Applications, the tooltip says which copy will be registered.
- A single broken rule in `rules.json` (e.g. `"desktop": "x"`) made the whole
  file unreadable; now only that rule is skipped, the footer shows "N rules
  could not be read", and the file is first backed up to `rules.json.bak`.
  Profile import is equally lenient.
- A `rules.json` written by a newer Deskmap (`version` > 3) is no longer
  overwritten by an older one: the file is read, saving is disabled and the
  footer shows a warning.
- The router skipped a window because of a more specific rule that had no
  target in this mode; it now makes the same choice as the UI (the first
  matching rule with a target in this mode).
- "Re-apply" (and other actions that clear the layout memory) had no effect
  when pressed during a sweep.
- Endless 200 ms loop for a window whose desktop move didn't stick; it now
  gives up after 6 attempts, and the counter resets when the window arrives.
- With a full-screen app visible on the target display, windows are no longer
  "hopped" into the full-screen space.
- A pending (400 ms delayed) save is written on quit.
- An unreadable `rules.json` is backed up to `rules.json.bak` before it is
  overwritten.
- Layout and attempt records of closed windows are pruned every sweep (memory
  no longer grows over long sessions).
- After plugging or unplugging a monitor the mode selector follows the real
  mode; desktops added or removed in Mission Control show up on the map
  immediately.
- An app that doesn't answer Accessibility (frozen) is skipped for increasing
  periods (2–30 s) and the footer shows "X not responding", so one app can't
  stall the whole sweep.
- If the active profile can't be found in a broken file, the generated default
  profile gets a unique name ("Default (2)").
- The "hop" was removed: a pinned window on a hidden desktop is no longer
  brought through the current desktop to get its layout (a foreign window
  flashed on the current desktop, and switching to the app from the Dock went
  to the wrong Space). The layout is applied the first time you visit that
  desktop.
- The unresponsive-app backoff triggered wrongly: responsive apps with many
  windows (VS Code, Chrome and other Electron apps and browsers) were skipped
  once their total AX time exceeded 0.7 s. The criterion is now a single AX
  call of ≥ 0.5 s (a frozen app hits the 1 s timeout on its first call), or a
  total of ≥ 4 s as a safety net. The process-wide AX timeout is set to 1 s
  at launch, so window elements from `kAXWindows` no longer use the ~6 s
  default.
- The window event observer could block the main thread: the app element gets
  a 1 s timeout, apps that haven't finished launching are skipped, and an app
  whose registration fails is retried with increasing intervals (2 → 30 s);
  the wait is cleared when the app launches, activates or quits.
- Giving up on a desktop move was permanent (after 6 attempts it was never
  tried again until "Re-apply"); now a new round starts 60 s after the last
  attempt.
- Temporary pins are not dropped when the window server returns an empty list
  (a transient failure).
- The external display role order (`external`, `external-2`) was ambiguous
  for the same `minX`; it is now determined by (minX, minY, UUID).
- Undo erased changes made in between: the entry restored the whole document,
  so unrecorded actions within the 10 s (a new pin, a layout step, profile
  switch/add/rename/import, "Got It", URL commands) were silently lost with
  ⌘Z. The entry is dropped if the document changes after it was recorded (the
  on/off switch and recognized displays don't count).
- Undoing a desktop reorder left temporary pins on their new numbers; they now
  move back with the reverse mapping.
- The missing-desktop badge showed up wrongly on the other mode's map (desktop
  counts belong to the connected displays and the router only clamps in the
  current mode); the badge is shown only while the map shows the current mode.
- ⌘Z in the profile name or percent fields undid the document; with the
  focus in a text field, the text field's own undo runs.
- The "Undo" link was hidden behind error and unresponsive-app messages (and
  ⌘Z was not bound); it is now a separate item on the right of the footer.
  When space is short, the status text is truncated first.
- The "don't drop pins if the window server is empty" guard didn't work: the
  windows seen by AX were always added to the live window list, so it was
  never empty and temporary pins and layout/attempt records could be pruned.
  Now the list stays empty if the server returned nothing
  (`Router.liveWindows`); AX windows are only added to a non-empty list.
- If the wake notification was missed (e.g. sleep was cancelled after
  `willSleep`), sweeps could stay paused forever. The timer now checks every
  round: if the main display is awake and the pause is older than 5 s,
  sweeping resumes (logged with reason "timer"). It doesn't race the
  notification order when going to sleep.
- The process-wide 1 s AX timeout was set after `WindowEvents` was created, so
  the first observer registration round asked window elements with the ~6 s
  default. It is now set first.

## [0.2.0] — 2026-09-02

A rewrite for simplicity: one app, a visual interface.

### Changed

- The Hammerspoon engine was removed. Windows are read and moved through the
  Accessibility API, and Spaces are handled with SkyLight's private calls
  (the same ones Hammerspoon and yabai use), directly inside the app.
  Differences between macOS 12.7 and 26.x are handled per version.
- Instead of a rule editor, settings and display tabs: a single display map.
  Displays and desktops are drawn as boxes and rules are dragged as chips. A
  layout is picked visually by clicking a chip.
- Adding a rule: pick from the list of open windows, then mark parts of the
  title by clicking them. No text entry.
- Settings were removed: delays, log level, pinning, notifications, follow
  mode. Only the on/off switch and "Launch at login" remain.
- `rules.json` schema v2 (`appName`, `bundleID`, `tokens`, `docked`,
  `undocked`). v1 files are read automatically.
- Displays are identified by role instead of UUID: `builtin`, `external`,
  `external-2`, …

### Removed

- `engine/`, `install.sh`, `uninstall.sh`, `check.sh`, Lua tests, `config/`,
  `docs/`.

## [0.1.2] — 2026-09-02

### Added

- The engine watches its own source directory; Hammerspoon reloads itself
  when a `.lua` file changes.

## [0.1.1] — 2026-09-02

### Fixed

- `hs.urlevent` callback, window filter lock-up, placeholder display UUIDs.

### Added

- Desktop pinning, UUID normalization, display registry repair.

## [0.1.0] — 2026-09-02

First release: Hammerspoon engine + SwiftUI rule editor.
