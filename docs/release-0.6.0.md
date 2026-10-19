# Deskmap 0.6.0 — release notes (draft)

> **Status: draft, not released.** `VERSION` still says 0.5.0; nothing is
> tagged. This page is written from the `[Unreleased]` section of
> [CHANGELOG.md](../CHANGELOG.md) and the commits since `v0.5.0`. Turkish:
> [tr/surum-0.6.0.md](tr/surum-0.6.0.md). Steps to actually ship:
> [release-checklist.md](release-checklist.md).

0.5.0 (30 September 2026) was the first release with a download. 0.6.0
collects everything since: desktop names that follow their desktop, a second
external monitor with its own role, multi-step undo, automatic backups, a
scriptable CLI, and a website. Nothing here needs a new permission; the
Accessibility permission you already granted keeps working as long as the app
is signed the same way (see *Upgrading*).

## Highlights

- **A second external monitor keeps its own layout.** Each monitor is known by
  its display UUID, not by where it stands, so swapping cables or display
  arrangement no longer moves pins to the other monitor.
- **Desktop names belong to a desktop, not a number.** A name follows its
  desktop across displays, reordering and plug/unplug; pins can target a name.
- **Undo as many steps as you like** (⌘Z / ⇧⌘Z), with a change history.
- **Automatic backups** of profiles, pins and names, with restore in Settings.
- **`deskmap` command line tool**, `status.json` and `deskmap://` commands for
  scripts and agents.
- **Open or close a whole workspace** from the map with one click.
- **Desktop moves start off on macOS 15 and 26.0–26.3** until you choose
  **Try Anyway**, because they are not verified there yet.

## What's new

### Displays and monitors

- **Monitor roles by UUID.** Each external monitor keeps its role (*Extra
  monitor*, *Monitor 2*, …) by its display UUID instead of its left-to-right
  position. Rearranging displays, plugging them in another order, a virtual
  display on the left or two monitors of the same model no longer move pins to
  the other monitor. With two or more monitors the second card's title is a
  menu to swap them (asks first). `deskmap screen-role` and the URL commands
  `screen-role` / `screen-role-forget` do the same.
- **A monitor Deskmap does not remember waits.** Once a first monitor has been
  learned, a display not remembered in its role (a new monitor, a lone virtual
  display, a forgotten monitor) is on hold: no plan, pin or rule is applied to
  it and no cleanup runs there. Its card says *new monitor · layout on hold*
  and offers *Use as Extra monitor / Monitor 2 …* (asks first) and *Forget This
  Monitor* on remembered ones.
- **Ordered places for several monitors**: drop a pinned window on another
  monitor and its old place is kept below the new one; the first place whose
  monitor is connected wins, so unplugging Monitor 2 sends its windows back.
  With none connected, the first connected monitor in role order takes the
  window. Layout files take `docked: [external-2/1, external/2]`.
- **Send a desktop to another display** from its context menu; drag desktops
  across displays on the map.

### Desktop names and plans

- **Names v2.** A name belongs to one physical desktop and follows it across
  displays, reordering and plug/unplug. Each profile has a plan per setup
  (which names live where, how many desktops per display). Plugging or
  unplugging the monitor applies the plan of the new setup: named desktops
  move with all their windows, unnamed windows from a monitor desktop are
  parked on laptop desktops and come back on replug, missing desktops are
  created, and only *empty* leftover desktops beyond the plan are removed
  (each re-checked right before).
- **Names belong to a profile.** A new profile starts without names; renaming
  in one profile never touches another; export/import carries names and plans.
- **Pins can target a name.** The pin panel and **Send to** list names first.
  A pin follows the named desktop and waits (nothing moves) while the name has
  no desktop. `deskmap://pin/<window>?name=<name>` does the same.
- **Copy the Laptop only plan here** (⋯ menu) also copies the laptop desktop
  names into the Monitor connected plan.
- **Removing a desktop that has windows asks first.** A profile switch and the
  copy action move windows but never remove a desktop.
- **Desktops deleted in Mission Control** stay as restorable rows with their
  pins, also when they were deleted while Deskmap was not running.

### Map and everyday use

- **Open a workspace at once.** A desktop with closed pinned windows shows
  **Open N** next to its name; one click opens them all, each to its pinned
  place. Each app group header gets **↗** (open its closed pins) and **✕**
  (close all its pinned windows with their own close button; the app keeps
  running, unsaved documents still ask).
- **Visual map as a grid of desktop cards**, a side inspector with a plain
  rule sentence, basic/advanced editor, **Why here?** box, legend and a
  labeled top bar. A menu bar **status dot** (green/orange/red) with a one-line
  reason at the top of the map.
- **Simpler pinning**: *this window* (a stable title key: file path, stable
  title part or Safari tab group) or *all windows of the app*. Multi-select
  windows with ⌘-click and pin them where they are in one step. Move a whole
  app group to another desktop by drag or context menu.
- **Double-click** a window row to focus it and switch to its desktop;
  double-click a closed pin to reopen its window (file, folder or page).
- **Timed pins box** at the bottom of the sidebar lists windows that are free
  to move for a while, soonest end first, with **End all**. Free move gains
  2 h, 5 h and *until the screen locks* durations, `deskmap://free` and
  `deskmap free`.
- **Map window placement**: placed once per open, fixed height that fits the
  screen, top center of the built-in display, no longer pushed around after a
  resize.

### Undo and history

- **Multi-step undo / redo.** Every settings change this session is a step (up
  to 50, not saved): ⌘Z / ⇧⌘Z and permanent ↶ ↷ footer buttons replace the
  10-second *· Undo* link. **Recent moves** gets two tabs: **Changes** (newest
  first, ● NOW, **Return here**) and **Window moves**. Changes from URL
  commands, the CLI, profile switches or Mission Control become steps instead
  of cancelling undo.

### Backups

- **Automatic backups** of all profiles, pins and desktop names: hourly (kept
  24 hours), daily (kept 7 days), weekly (kept forever) under
  `~/Library/Application Support/Deskmap/Backups/`. Restore from **Settings ›
  Backups** (or **Backups…** in the profile panel) or with `deskmap backups` /
  `deskmap backup-restore <id>`; the current state is backed up first and a
  restore can be undone. Replaces the external `profile-backup.sh` script.

### Desktop moves on unverified macOS versions

- On macOS 15.x and 26.0–26.3, where moving windows between desktops has not
  been verified, desktop moves **start off** and the main window shows a card
  saying so. Displays and layouts still apply. **Try Anyway** turns moves on
  and is remembered; the circuit breaker still watches every move. If moves
  keep having no effect, **Try Again** turns them back on. `status.json`
  reports `desktopMoves`; `deskmap status` prints a line when moves are off.

### Command line, automation, hooks

- **`deskmap` CLI** (`scripts/deskmap`): `status`, `screens`, `desktops`,
  `rules`, `apply` / `check` / `undo` with layout files, `dump`, profile
  rename/export, desktop reorder, `save-layout`, `free`, `screen-role`,
  `backups`, `backup-restore`, `hooks`. `deskmap --help`
  carries an arrangement guide for agents. `make cli-test` runs its offline
  unit tests.
- **`status.json`** (names, plans, screens with `uuid`, `heldRoles`,
  `desktopMoves`, free-move state) and **URL commands** (`deskmap://pin`,
  `profile-set`, `plan-desktops`, `free`, `screen-role`,
  `quit`, …). `DESKMAP_DATA_DIR` points the app at another data folder.
- **Screen change hooks** (`hooks.json`): run a command when displays are
  connected, removed or change; waits for mouse release, times out commands.

### Documentation and website

- **Website** (`website/`, built by `make site`): home, download, compare and
  docs pages in English and Turkish; the guide, reference, architecture,
  privacy and changelog are rendered from the Markdown docs and deployed to
  GitHub Pages by `.github/workflows/pages.yml`. The one-page `docs/site/` is
  gone.
- **Demo GIF** (`docs/media/<lang>/demo.gif`, also `.mp4`) in the README and
  the guide: laptop only, monitor connected, pinned windows in place, a second
  monitor with its own role. Drawn by the shots mode with demo data; no real
  window is touched.
- **Homebrew tap**: `brew install --cask cnkndmr/tap/deskmap`; the cask is
  updated automatically when a release is published.
- **Bug tables** (`docs/bug-tables.md`): operation × state tables for the
  primary external monitor and window drift bugs, each cell a test.

## Fixed

- **Windows no longer drift to another pin after their title changes.** A
  window keeps the rule that placed it for its lifetime (sticky binding); a
  generic title (equal to the app name) gets a grace period; while a window
  whose whole title equals a one-token rule is open, other windows that only
  contain that token do not match it; unpinned windows stay put. *Send group
  to* moves the bound rule, and the map no longer shows it as shadowed.
- **Plan picker follows a single screen change** (it could stay on the previous
  plan after one plug or unplug).
- **Desktop names no longer get lost through the other setup's plan**; a name
  whose desktop still exists is never treated as deleted.
- **Primary external monitor**: a virtual display on the left, a replug in a
  different order or two monitors of the same model no longer take over the
  Extra monitor layout (table A/A′ in the bug tables).
- **Reopen**: Safari rules without a bundle id open in a new window, not a tab;
  Finder locations like Recents reopen; the reopen scan no longer blocks
  routing.
- **Idle CPU** lower: windows are scanned less often, title events filtered,
  scan budget kept under the unresponsive threshold.
- **Compiler warnings: 0.** `make concurrency-check` counts warnings again
  (the compiler's colored output had hidden them); the 14 regular compiler
  warnings and every strict concurrency warning (router, window rows, layout
  constants, RootView observers) are fixed, so both the release build and
  `-strict-concurrency=complete` report none.
- Links in the Turkish docs and changelogs that pointed to wrong relative paths
  on GitHub.

## Removed

- **Support for the pre-Deskmap name**: the old data folder is no longer
  copied on first launch, the old URL scheme is no longer registered and old
  profile export files no longer import.

## Upgrading from 0.5.0

**Permissions.** No new permission. Accessibility is still the only one. macOS
ties the grant to the code signature: with the same ad-hoc signing as 0.5.0 it
is asked again after each update (as before); if 0.6.0 is the first build
signed with a Developer ID, it is asked once more and then stays.

**First launch.** Unless the release is notarized, macOS blocks the first
launch as with 0.5.0: open the app once, then System Settings › Privacy &
Security › **Open Anyway**. See the [download page](https://cnkndmr.github.io/Deskmap/download/)
or the README.

**Data files.** `rules.json` moves from schema 4/5 to **schema 6** on first
launch. The old files are saved to `Backups/pre-migration/` (never pruned);
names are matched to desktops by where their pinned windows are; wrongly
created deleted-desktop rows are removed and their pins restored. A card
reports the result and offers **Remove N empty desktops** and **Undo
upgrade**. Nothing is moved or removed during the upgrade. **An older Deskmap
opens the new file read-only**, so keep 0.5.0 around only if you want to go
back, and go back through the pre-migration copy. Runtime desktop facts moved
to `desktop-state.json`. Profile export is version 4; version 3 files still
import. `rules.json` gets an optional `displayRoles` field (older versions
ignore it).

**New settings.**

| Setting | Where | Default | What it does |
|---|---|---|---|
| Try Anyway (desktop moves) | card in the main window, `status.json` `desktopMoves` | off on macOS 15.x and 26.0–26.3, on elsewhere | turns desktop moves on; remembered |
| Backups | Settings › Backups | on, automatic | hourly / daily / weekly copies, restore |
| Monitor roles | second monitor card menu, `deskmap screen-role` | learned from the first monitor | which physical monitor is *Extra monitor* / *Monitor 2* |

**Behaviour changes to expect.**

- *A new monitor asks once.* After your first monitor has been learned, a
  monitor Deskmap has not seen in that role is on hold: the card says *layout
  on hold* and you choose *Use as Extra monitor*. Before 0.6.0 the layout went
  there at once.
- *Windows keep their rule.* A window stays with the pin that placed it even
  when its title later matches another pin; only a strictly more specific pin
  may still take it. Before 0.6.0 the newest matching title won.
- *Desktop moves card.* On macOS 15.x and 26.0–26.3 the main window opens
  with an orange card and desktop moves off until you click **Try Anyway**.
- *Names are per profile and per desktop.* A name no longer has a number; a
  new profile starts without names; plugging or unplugging a monitor applies
  the setup's plan and may create desktops or remove empty leftover ones
  beyond the plan.
- *Undo* is no longer a 10-second link; ⌘Z steps back through this session's
  changes, URL/CLI changes included.
- *Removing a desktop with windows asks first.*
- `profile-backup.sh` is gone; backups are built in.

## Known limits

- **Not notarized** (unless the maintainer decides otherwise before release):
  Gatekeeper blocks the first launch; the Homebrew cask lives in the
  maintainer's own tap, not the official one.
- **Private API.** Moving a window to another desktop uses SkyLight calls
  resolved at run time; a macOS update can break them. On macOS 15.x and
  26.0–26.3 they are unverified and start off.
- **A lone unknown monitor waits.** macOS gives no reliable "virtual display"
  flag, so a brand-new real monitor also asks once before taking the Extra
  monitor layout.
- **Generic-title grace** (a window whose title equals the app name waits 8 s
  before it is bound) is a chosen value, not yet measured against a real new
  session window.
- **Older Deskmap reads schema 6 read-only**; downgrading means restoring the
  pre-migration copy.
- **Accessibility permission** is asked again after each update while the app
  is ad-hoc signed.
- **No update check**; Deskmap never contacts a server. Download the newer
  release and replace the app, or `brew upgrade --cask deskmap`.
- **macOS settings** still matter: *Automatically rearrange Spaces* off,
  *Displays have separate Spaces* on, the app's Dock *Assign To* → None.
