# Bug tables: primary external monitor, window drift, map reveal, ordered places

Three open bugs, each written as an operation × state table. Every cell names
the test that reproduces it (`app/Tests/DeskmapTests/`). On `main` the bug
cells are marked `withKnownIssue`; the suite stays green and each known issue
is listed in the test output. Nothing in these tests moves a real window:
screens, desktops and windows are fake. Section D is not a bug: it is the
operation × state table of the ordered places design.

Legend: **OK** works as intended · **BUG** reproduced · **FIX** fixed on the
proposal branch (`gece/1910-deskmap-b-oneri`), not on `main`.

## A. Primary external monitor (phase 1, `primaryExternalUUID`)

Setup seen in the October trial (from the system log, neutral names):
built-in display at (0, 0); a wide monitor ("Wide") above and to the left
(minX −1686); a virtual display ("Virtual") to the right of the built-in
display (minX 1710). The virtual display was closed and reopened twice during
the trial. The phase 1 work is uncommitted in another worktree; the proposal
branch carries it over unchanged and fixes it on top.

### Root causes

1. **Choosing a monitor is a full layout migration.** Roles (`external`,
   `external-2`) carry everything: rules, desktop plans, names. A role change
   publishes new `screens`, the router starts a display transition and
   `PlanApply` applies the `external` plan to whichever monitor now holds the
   role: every named desktop's windows move, desktops are created on the other
   monitor. The picker did this without asking.
2. **A lone external display always becomes `external`**, even when it is not
   the remembered monitor (phase 1 kept this from `main`). Unplug the wide
   monitor while the virtual display is open and the whole monitor layout lands
   on the virtual display.
3. **Requested labels were not built.** The request was "no monitor model
   names: one extra monitor is *Extra monitor*, the other *Monitor 2*, a
   dropdown next to the second one". Phase 1 kept model names on the cards and
   showed the dropdown on both cards; with one external display nothing changed.
4. Not caused by phase 1: the desktop that slid from 13 to 10 on the built-in
   display. The hourly backup taken after the trial build was removed (old
   version running again) still had it at 13; the slide happened later under
   the old version. Separate bug, not in this table.

### Table

| Operation \ State | One external | Two, nothing remembered | Two, remembered = position-first | Two, remembered = the other | Remembered not connected, other one alone |
| --- | --- | --- | --- | --- | --- |
| Plug the virtual display in, right of the monitor | — | OK `virtualRightOfMonitorKeepsMonitorExternal` | OK (same) | BUG → FIX: stays as chosen, `rememberedSurvivesReplug` | — |
| Plug the virtual display in, left of the monitor | — | BUG `virtualLeftOfMonitorStealsExternalRole` → FIX `rememberedMonitorKeepsRoleWhereverOthersAre` | FIX (same) | FIX (same) | — |
| Steady state, roles unchanged | OK `correctRolesNeedNoWork` | OK | OK | OK | — |
| Choose the other monitor in the picker | — | BUG `roleSwapMigratesWholeLayoutWithoutConsent` → FIX `switchNeedsConfirmation` | BUG → FIX (same) | BUG → FIX (same) | — |
| Unplug the remembered monitor | — | — | — | — | BUG `loneVirtualDisplayTakesMonitorPlan` → FIX `loneOtherDisplayDoesNotTakeRememberedRole` |
| Card title | BUG (model name) → FIX `cardTitlesUseRoleNames` | BUG → FIX (same) | BUG → FIX (same) | BUG → FIX (same) | BUG → FIX (same) |
| Picker visibility | OK hidden `pickerOnlyOnSecondCard` | BUG on both cards → FIX (same) | FIX | FIX | FIX hidden |

Open decisions (proposal branch): see "Decisions" at the end.

On `gece/1910-deskmap-d` the bug tests above are rewritten on `DisplayRoles`
(table A′): `virtualLeftOfMonitorStealsExternalRole` →
`virtualLeftOfMonitorDoesNotStealExternalRole`, `roleSwapMigratesWholeLayoutWithoutConsent` →
`automaticRoleChangeIsHeldUntilConfirmed` + `menuChoiceIsConfirmedAndApplied`,
`loneVirtualDisplayTakesMonitorPlan` → `loneUnknownDisplayDoesNotTakeMonitorPlan`. No
`withKnownIssue` is left in `PrimaryExternalBugTests`.

## A′. Primary external monitor on the combined branch (`gece/1910-deskmap-d`)

The combined branch takes the second-monitor model (`DisplayRoles`: roles kept
by display UUID) instead of phase 1's single `primaryExternalUUID`. Roles no
longer slide by position, but two cells of table A stayed open there:
**A3** (a role change that Deskmap made by itself still let `PlanApply` move the
whole `external` layout to the other display; the confirmation only covered a
swap picked on the card) and **A4** (a lone display Deskmap did not remember
took the `external` role and its plan, with no menu to say otherwise). This
branch closes both with one rule:

> **A role held by a display that is not remembered in that role waits.**
> It is treated as not connected: no plan is applied to it (no moves to it or
> from it, no desktops opened or removed there, no leftover cleanup), and no
> rule or pin is routed to it (nor falls back to it). Its card says *new
> monitor · layout on hold* and its title menu offers *Use as Extra monitor /
> Monitor 2 …*; after a confirmation the choice is remembered and the plan is
> applied at once. `deskmap screen-role DISPLAY ROLE` does the same.

Before the first monitor was ever learned (fresh install, upgrade from a
version without `displayRoles`, or after Settings › *Forget*) nothing waits:
roles come from left-to-right order and are learned, as before.
`displayRoles.learnedOnce` records that this first step is behind
(older files: set when something is remembered). The test display
("Deskmap Test Display") never waits.

Tests: `PrimaryExternalBugTests`, `PrimaryExternalServiceTests`,
`DisplayRolesTests`, `PlanPickerFollowTests`, `scripts/clitest` (`ScreenRoleTest`).

| Operation \ State | Nothing learned yet | Remembered monitor alone | Remembered monitor + unknown display | Remembered monitor away, unknown display alone | Two remembered for one role, both connected | One monitor forgotten, connected |
| --- | --- | --- | --- | --- | --- | --- |
| Plug in, displays settle | OK: position order, learned `firstConnectionIsNotHeld` | OK `virtualRightOfMonitorKeepsMonitorExternal` | OK: unknown gets `external-2`, on hold `virtualLeftOfMonitorDoesNotStealExternalRole` | FIX: gets `external`, on hold, not learned `loneUnknownDisplayDoesNotTakeMonitorPlan`, `loneVirtualIsHeldUntilChosen` | FIX: the older one drops to `external-2`, on hold `automaticRoleChangeIsHeldUntilConfirmed` | FIX: on hold, not learned again `forgettingOneMonitorPutsItOnHold` |
| Plan picker follows the change (a single screen change, one `$screens` publish) | BUG: the picker stayed one step behind (it read `screens.mode` while `@Published` was still in willSet) → FIX: follows the published list `pickerFollowsPublishedScreens`, `publishIsWillSet` | FIX (same) | FIX (same) | FIX (same) | FIX (same) | FIX (same) |
| Rearrange (virtual display to the left) | OK (learned after first settle) | — | OK `virtualLeftOfMonitorDoesNotStealExternalRole` | — | OK | — |
| Apply plan (transition, *Apply plan now*) | OK `correctRolesNeedNoWork` | OK | FIX: held role left out `holdingKeepsOtherRoles` | FIX: no desktops, moves or rebinds `loneUnknownDisplayDoesNotTakeMonitorPlan` | FIX: monitor's named desktops stay `automaticRoleChangeIsHeldUntilConfirmed` (without the gate: `withoutTheGateTheWholeLayoutWouldMove`) | FIX (same) |
| Pins and rules | OK | OK | FIX: no rule or fallback to the held role `heldRoleIsNotAFallbackTarget` | FIX (same) | FIX (same) | FIX (same) |
| Leftover cleanup | OK | OK | FIX `cleanupLeavesHeldDisplayAlone` | FIX (same) | FIX (same) | FIX (same) |
| Card menu: *Use as …* (confirmation) | — | — | FIX: remembered, plan applied `loneVirtualIsHeldUntilChosen` | FIX: *Extra monitor* `loneUnknownDisplayConfirmedAsExtraMonitor` or *Monitor 2* (Extra monitor stays empty) `loneUnknownDisplayCanBecomeMonitor2` | FIX `menuChoiceIsConfirmedAndApplied` | FIX (same) |
| Card menu: swap with the other monitor (confirmation) | — | — | OK `choosingTheOtherMonitorSwapsRoles` | — | OK | — |
| Card menu: *Forget This Monitor* | — | FIX: new; role waits `forgetOneHoldsForgetAllStartsOver` | FIX (same) | — | FIX (same) | — |
| Settings › *Forget* (all) | OK | OK: starts over, learned again `forgetOneHoldsForgetAllStartsOver` | OK | OK | OK | OK |
| `deskmap screen-role DISPLAY ROLE` / `DISPLAY --forget` / `--forget` | OK | OK | FIX: same as the menu `ScreenRoleTest`, `forgetOneURLParses` | FIX: `ROLE` may be beyond the connected count when a remembered monitor is away (`choosableRoles`) | FIX | FIX |
| `deskmap screens` | OK | OK *role kept* | FIX: *role on hold* with the command to confirm `test_held_role_is_shown_with_how_to_confirm` | FIX (same) | FIX (same) | FIX (same) |
| Older file (no `learnedOnce`) | OK `olderFileWithoutFlag` | OK | OK | OK | OK | OK |

Not tested here (needs a real display): the alert texts on screen, that
`applyPlanNow` after a confirmation runs once (not twice with the settle
transition of a swap), and an actual unplug/plug of the wide monitor.

## B. Window drift (Claude windows)

Selection is stateless: every sweep `Routing.select` matches each window by its
**current** title. Claude titles move (a new session window starts as
"Claude" and gets its name a few seconds later; the main window may show the
open chat; forks add " (fork)"), and title tokens match as substrings.

### Root causes

1. **No memory per window.** A window that a rule or a pin has placed falls to
   another rule as soon as the title changes or the pin goes away.
2. **Transient titles are routed at once.** A new session window titled
   "Claude" matches the main window's rule and is moved to the main desktop
   before it gets its name.
3. **Substring match without an owner.** A rule made from one window's title
   also matches every title that contains it ("X" and "X (fork)", "Claude" and
   "Claude Code notes").

### Table

| Operation \ State | Main window ("Claude") | New session window, first seconds | Session window with its own rule | Fork of a session window | Window with a temporary pin |
| --- | --- | --- | --- | --- | --- |
| Open / first sweep | OK `mostSpecificRuleTakesOver` | BUG `newWindowWithTransientTitleWaits` → FIX `transientTitleIsHeld` | OK | BUG `forkWindowDoesNotShareOriginalRule` → FIX `exactOwnerKeepsRule` | OK `sessionPinBeatsEveryRule` |
| Title becomes longer, contains the token | BUG `mainWindowTokenSkipsLongerTitlesWhileOwned` → FIX `exactOwnerKeepsRule` | — | — | — | — |
| Title changes to something else | BUG `titleChangeKeepsWindowOnItsRule` → FIX `bindingSurvivesTitleChange` | FIX: not bound yet, routed by its new name | BUG `renamedSessionKeepsItsRule` → FIX `bindingSurvivesTitleChange` | — | — |
| Pin removed | — | — | — | — | BUG `unpinLeavesWindowInPlace` → FIX `unpinnedWindowStays` |
| A more specific rule starts to match | OK `moreSpecificRuleTakesOver` | OK | OK (upgrade) `moreSpecificRuleUpgradesBinding` | OK | OK |
| Rule deleted | OK `deletedRuleReleasesWindow` | OK | BUG (map unpin deletes the rule; same as B1) → FIX `deletedRuleLeavesWindowInPlace` | OK | OK |
| Rule edited in place (tokens change) | FIX: binding dropped, chosen by the new tokens `editedRuleRebindsByNewTokens` | — | FIX (same) | — | — |
| Window closed | OK: binding pruned `bindingsPrunedWithWindows` | OK | OK | OK | OK |

On `gece/1910-deskmap-e` each bug cell is one test in `WindowDriftBugTests` that
pins both layers: the stateless `Routing.select` (no context) still reproduces
the drift (diagnosis, marked `// teşhis`) and the real Router fixes it. The
real Router runs on fake screens and windows (`RouterHarness`,
`Router.sweepSelection`: the sweep's own inputs, `Router.select` and merge;
no AX, no window moves); `WindowDriftFixTests` and `RouterSelectionTests` use it
too. Renamed: `unpinFallsBackToAppWideRule` → `unpinLeavesWindowInPlace`,
`newWindowWithTransientTitleTakesMainWindowRule` → `newWindowWithTransientTitleWaits`,
`mainWindowTokenMatchesLongerTitles` → `mainWindowTokenSkipsLongerTitlesWhileOwned`,
`forkWindowSharesOriginalRule` → `forkWindowDoesNotShareOriginalRule`,
`titleChangeMovesWindowToAnotherRule` → `titleChangeKeepsWindowOnItsRule`,
`renamedSessionFallsToAppWideRule` → `renamedSessionKeepsItsRule`. No
`withKnownIssue` is left in the suite. Group moves (`GroupMovePlan.make`) and
the map's shadow list (`ScreenMapView.shadows`) now take the Router's binding
(`router.context(for:)`): `groupMoveMovesBoundRule`, `shadowsFollowBinding`.

## C. Map does not scroll to a revealed window (`ui.reveal`)

Opening the map selects the front window and scrolls the map to its row
(`showFrontWindow` → `ui.reveal`). On macOS 27.0 (26A428) the map never moved.

### Root cause

`RootView` called `proxy.scrollTo` inside `withAnimation(.easeInOut)`. On this
macOS an animated `ScrollViewReader.scrollTo` is a no-op: the same call without
animation scrolls. Measured in a standalone SwiftUI app under
`NSApplication.run` (plain, `.default`, `.linear`, `.spring`, `.top` anchor and
a deferred call: only the plain call moves), in the `--shots` mode and in the
test below. Not the cause: the anchor ids (`WindowAnchor` matches both list
rows and grid boxes), lazy stacks (none on the map), the reader (the map's own
`ScrollViewReader`), timing (the deferred call runs). Older macOS versions
(13 to 26) were not measured. The `--shots` crowded frames depended on this
call too; `scrollMap(ui:toBottom:)` in `Shots.swift` worked around it and is
gone now.

### Table

| Operation \ State | Map list, row present | Visual grid, box present | Window hidden behind "+N more" |
| --- | --- | --- | --- |
| Open the map on the front window | BUG `animatedScrollToDoesNotMove` → FIX `revealScrollsToWindowRow` | BUG (same call) → FIX (same) | not measured: no anchor, the map should stay |
| Shots frames `g01b`, `g01c`, `g02`, `g03`, `d4` | BUG: frames stayed at the top → FIX: frames scroll to the window | BUG → FIX | — |

`animatedScrollToDoesNotMove` keeps the old call under `withKnownIssue`
(intermittent: another macOS version may scroll). The fix
(`gece/1910-deskmap-i18n`) scrolls without animation (`MapReveal.scroll`): the
map jumps to the row instead of sliding. A grid box carries its id after
`.offset`, so the scroll target is the desktop card's top left, not the box
itself; the card is still in view, left as is.

## D. Ordered places for several monitors

Not a bug: the design table for ordered places (`Rule.docked` + `dockedNext`,
`Routing.resolvePlace`). Every row is a test in
`app/Tests/DeskmapTests/DockedPlacesTests.swift` (`d1_1_…` = row D1.1) or
`scripts/clitest/test_deskmap.py` (`DockedListTests`).

Example desk: role order 1. Dell, 2. LG, 3. Samsung (Samsung has 2 desktops);
the built-in display is always there. Safari: `LG · 1`, `Dell · 2`, laptop
`Laptop · 1`. Mail: `Dell · 3`, laptop `Laptop · 2`. Notes: `Samsung · 2`, no
laptop place. Music: no monitor place, laptop `Laptop · 3`. "Untouched" means
Deskmap does not move the window.

| Row | State | Operation | Expected |
| --- | --- | --- | --- |
| D1.1 | laptop only | — | Safari Laptop · 1, Mail Laptop · 2, Music Laptop · 3, Notes untouched |
| D1.2 | laptop only | plug Dell | Safari Dell · 2, Mail Dell · 3, Notes Dell · 2 (fallback), Music untouched |
| D1.3 | Dell | plug LG | Safari LG · 1, Mail Dell · 3, Notes Dell · 2 |
| D1.4 | Dell + LG | plug Samsung | Notes Samsung · 2, the others stay |
| D1.5 | all three | unplug LG | Safari back to Dell · 2 |
| D1.6 | Dell + LG | unplug Dell | Safari LG · 1, Mail LG · 3 (fallback), Notes LG · 2 |
| D1.7 | LG | plug Dell again | Mail back to Dell · 3, Safari stays on LG · 1 |
| D1.8 | Dell + LG | unplug all | laptop places; Notes untouched |
| D1.9 | Dell + LG | move LG left of Dell in System Settings | nothing moves (roles follow the UUID) |
| D1.10 | Samsung only | — | Mail Samsung · 2 (desktop 3 missing → last), Safari Samsung · 1 (number of the first place) |
| D2.1 | Dell | plug an unknown BenQ | BenQ on hold, nothing goes there |
| D2.2 | after D2.1 | add BenQ to the end (Monitor 4) | nothing moves; BenQ is in the fallback order |
| D2.3 | after D2.1 | BenQ takes LG's place | Safari BenQ · 1 (LG's layout) |
| D2.4 | only BenQ (on hold) | — | nothing moves, laptop places are not used |
| D3.1 | Dell + LG | Dell card: choose LG | roles and layouts swap: Mail LG · 3, Safari Dell · 1; no pin lost |
| D3.2 | after D3.1 | swap back | as before |
| D3.3 | Dell | LG card (not connected): choose Samsung | order Dell, Samsung, LG; plug Samsung → Safari Samsung · 1 |
| D3.4 | — | card menu | only monitors Deskmap has seen (map turn, not tested here) |
| D3.5 | after D3.1 | unplug Dell | Safari LG · 2, Mail LG · 3 |
| D4.1 | Dell + LG | drop Safari on LG · 2 | `LG · 2`, `Dell · 2` (same monitor: replaced) |
| D4.2 | Dell + LG | drop Safari on Dell · 3 | `Dell · 3`, `LG · 1` (before the first connected place, LG · 1; Dell's old place gone) |
| D4.3 | Dell | drop Safari on Samsung · 1 (not connected) | `Samsung · 1`, `LG · 1`, `Dell · 2`; Safari stays on Dell · 2 |
| D4.4 | Dell | ↑ on `Dell · 2` | `Dell · 2`, `LG · 1` |
| D4.5 | Dell | × on `Dell · 2` | `LG · 1` → fallback Dell · 1 |
| D4.6 | Dell | × on Mail's only place | empty list, Mail untouched |
| D4.7 | laptop only | drop Music on Laptop · 2 | laptop place changes, no monitor list |
| D4.8 | Dell | drop Music on Dell · 1 | `Dell · 1`; laptop place stays Laptop · 3 |
| D4.9 | Dell | drop Safari on Dell · 3 | `LG · 1`, `Dell · 3` (a connected monitor's place goes just before the first connected place: it does not jump ahead of LG); plug LG → Safari LG · 1 |
| D4.10 | Dell, Safari only `LG · 1` (on fallback) | drop Safari on Dell · 3 | `LG · 1`, `Dell · 3` (no connected place: added last) |
| D5.1 | Dell + LG | first place is desktop "Reading" on LG | Safari goes to "Reading" |
| D5.2 | D5.1, "Reading" moved to Dell | — | Safari follows it to Dell |
| D5.3 | D5.1 | unplug LG | next place, Dell · 2; a name with no known place alone holds the window |
| D5.4 | Dell + LG | switch profile | each profile keeps its own lists |
| D5.5 | Dell + LG | forget LG | LG on hold; its places are kept but skipped: Safari Dell · 2 |
| D5.6 | after D5.5 | confirm LG again | Safari LG · 1 |
| D5.7 | — | duplicate the profile | same order, new rule ids |
| D6.1 | Safari, two places | save | `docked` = LG · 1, `dockedNext` = [Dell · 2] |
| D6.2 | 0.5.0 file | open | one-place lists, same behaviour |
| D6.3 | D6.1 file | open with an older version | it reads `docked` only |
| D6.4 | older version saved D6.1 | open | `dockedNext` dropped: one place |
| D6.5 | backup / round trip | — | lists and roles kept |
| D7.1 | layout file `docked: [external-2/1, external/2]` | `deskmap apply` | two-place list |
| D7.2 | layout file `docked: external/2` | `deskmap apply` | one place (as before) |
| D7.3 | — | `deskmap dump` / `rules` | the list in order |
| D7.4 | — | `status.json` | window `place`: `"1"`, `"2"` …, `"fallback"` or `"untouched"` |

Also covered: deleting a desktop shifts every place on that display, a deleted
second place goes to the ghost desktop with its position and comes back as the
second place; deleting the first place's desktop makes the next place first.

## E. Desktop dragged to another display in Mission Control

Not a bug: the design table for moving such a desktop back
(`Services/DesktopRevert.swift`, `Router.handleCrossings` / `runReverts`).
Pure rows are tests in `app/Tests/DeskmapTests/MissionControlRevertTests.swift`
(`e1_1_…` = row E1.1); rows marked *manual* need a real Mission Control drag.

macOS has no SIP-free call that moves a space to another display, so the move
back is a plan: add a desktop at the end of the old display (Mission Control
**+**), shift the contents from the old position on by one, move the dragged
desktop's windows into the old position, remove the dragged desktop if it is
empty. Names follow the content (R5); number pins and temporary pins do not
change (the Mission Control drag did not shift them either); the plan entry
that following (P3) moved goes back.

Example desk: Dell and LG; LG has "Reading" (LG · 1, named), LG · 2, LG · 3.
Safari is pinned to "Reading", Notes to `LG · 2`, Mail to `Dell · 3`. The drag:
"Reading" to Dell · 2.

| Row | State | Operation | Expected | Test |
| --- | --- | --- | --- | --- |
| E1.1 | Dell + LG, stable | drag "Reading" to Dell · 2 | seen twice 1.5 s apart, same display set, space changed role: moved back (setting **Move back**, the default) | `e1_1_crossingDetected`, `e1_1_revertsByDefault`; *manual* |
| E1.2 | E1.1, Mission Control still open | — | waits until it closes (opening it while open would close it) | *manual* |
| E1.3 | Dell + LG | two desktops dragged in one session | each moved back, one card | `e1_3_twoCrossingsInOneSession` |
| E1.4 | Dell + LG | drag one, delete another | the deletion is handled as before (ghost row); the drag is moved back | `e1_4_deletionIsNotACrossing` |
| E1.6 | dragged while Deskmap was not running | launch | not moved back on its own: card with **Move back** | `e1_6_catchUpAsks` |
| E1.7 | after a restart | launch | no evidence (R4): nothing | (restart branch, unchanged) |
| E1.8 | laptop + Dell | drag a laptop desktop to Dell | same rule | `e1_8_builtinCrossing` |
| E2.1 | E1.1 | move back | LG · 1 is a new desktop named "Reading" with Safari; LG 3 desktops, Dell 3; Notes and Mail stay | `e2_1_planShiftsAndRemoves`, `e2_1_executesRevert` |
| E2.2 | the last desktop was dragged | move back | no shift | `e2_2_lastDesktopNoShift` |
| E2.3 | the middle desktop was dragged | move back | that position and later ones shift by one; earlier ones stay | `e2_3_middleDesktopShiftsOnlyLater` |
| E2.4 | — | drag a full-screen space | untouched (full-screen spaces are not in the desktop lists) | (by construction) |
| E2.5 | an "All Desktops" window on "Reading" | move back | not moved, does not block the removal | `e2_5_allDesktopsWindowIgnored` |
| E2.6 | a window could not leave the dragged desktop | move back | that desktop is kept; the card says so | `e2_6_windowLeftKeepsDesktop` |
| E2.7 | the desktop could not be added (or did not land last) | move back | nothing changes; card "Could not move … back" | `e2_7_addFailsChangesNothing`, `e2_7_addNotAtEndMovesNothing` |
| E2.8 | desktop moves off (macOS 15.x, 26.0–26.3, reduced mode) | drag | nothing is done; card says moves are off | `e2_8_movesOffShowsCard` |
| E2.9 | between the drag and the end of the move back | — | routing holds (number-pinned windows do not move twice) | *manual* |
| E2.10 | interrupted (display change) | — | stops at a step boundary; nothing removed | `e2_10_abortKeepsSource` |
| E3.1 | Dell + LG | unplug LG | display set changed: transition, not moved back | `e3_1_vanishedRoleIsNotACrossing` |
| E3.4 | woke from sleep | — | no move back for 60 s after waking | `e3_4_recentWakeLeaves` |
| E3.5 | display arrangement changed | — | no move back for 15 s after a display notification | `e3_5_recentScreenChangeLeaves`; *manual* |
| E3.7 | a monitor waiting for confirmation | drag to or from it | followed, not moved back | `e3_7_heldRoleLeaves` |
| E4.2 | — | move a desktop across in Deskmap | not detected (new spaces, no space changes display) | `e4_2_newSpacesAreNotCrossings` |
| E4.3 | moved back less than 60 s ago | drag it again | taken as intended: followed | `e4_3_repeatWithinAMinuteLeaves` |
| E4.4 | E2.1 card | **Keep it there** | the same pin-free path puts it where it was dragged | `e4_4_keepIsTheReverseCrossing` |
| E5.1–E5.3 | E2.1 | — | name on the new space; plans as before the drag; pins unchanged | `e5_followThenRevertRestoresPlansAndPins`, `e5_returnPlanEntryAllProfiles` |
| E5.4 | E2.3 | — | names of shifted desktops follow their content | `e5_4_shiftedNamesFollowContent` |
| E6.1 | Settings | **Move back** / **Ask** / **Leave** | Ask: card with **Move back**; Leave: D5.2 (the name follows) | `e6_1_askAndLeaveSettings`, `settingCodable` |

## Decisions (for the maintainer)

A. Primary external monitor
1. Lone non-remembered external display: keep it out of the `external` role
   (proposal) or give it the layout (as today)? The proposal applies only when a
   monitor has been remembered; with nothing remembered behaviour is unchanged.
2. Switching the remembered monitor moves the whole layout: confirm first
   (proposal) or switch silently?
3. Card names: "Extra monitor" / "Monitor 2" / "Monitor 3" (proposal).

A′. Combined branch (`gece/1910-deskmap-d`)
1. A display not remembered in its role waits (no plan, no rules) until it is
   chosen on its card or with `deskmap screen-role` (proposal), instead of
   taking the layout at once.
2. A new office monitor therefore asks once (*Use as Extra monitor*) before the
   Extra monitor layout goes there; after that it is remembered. Acceptable, or
   should a lone display with nothing else connected take `external` without
   asking (only virtual displays wait)? macOS gives no reliable "virtual" flag.
3. *Forget This Monitor* on a card forgets one monitor (its role waits again);
   Settings › *Forget* forgets all and starts over (learned again by position).

B. Window drift
1. Sticky binding lives for the window's lifetime (proposal); a strictly more
   specific rule may still take the window; a less specific one never does.
2. A removed temporary pin leaves the window where it is (proposal).
3. Grace for generic titles (title equals the app name): 8 seconds (proposal);
   needs one measurement with a real new session window.
4. Exact owner: while a window whose whole title equals a one-token rule is
   open, other windows that only contain that token do not match the rule.

C. Map reveal
1. Jump without animation (fix on this branch) or keep looking for an animated
   scroll that works on macOS 27 (for example animating the `NSClipView`)?
