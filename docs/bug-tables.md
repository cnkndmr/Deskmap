# Bug tables: primary external monitor, window drift

Two open bugs, each written as an operation × state table. Every cell names
the test that reproduces it (`app/Tests/DeskmapTests/`). On `main` the bug
cells are marked `withKnownIssue`; the suite stays green and each known issue
is listed in the test output. Nothing in these tests moves a real window:
screens, desktops and windows are fake.

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
| Open / first sweep | OK `mostSpecificRuleTakesOver` | BUG `newWindowWithTransientTitleTakesMainWindowRule` → FIX `transientTitleIsHeld` | OK | BUG `forkWindowSharesOriginalRule` → FIX `exactOwnerKeepsRule` | OK `sessionPinBeatsEveryRule` |
| Title becomes longer, contains the token | BUG `mainWindowTokenMatchesLongerTitles` → FIX `exactOwnerKeepsRule` | — | — | — | — |
| Title changes to something else | BUG `titleChangeMovesWindowToAnotherRule` → FIX `bindingSurvivesTitleChange` | FIX: not bound yet, routed by its new name | BUG `renamedSessionFallsToAppWideRule` → FIX `bindingSurvivesTitleChange` | — | — |
| Pin removed | — | — | — | — | BUG `unpinFallsBackToAppWideRule` → FIX `unpinnedWindowStays` |
| A more specific rule starts to match | OK `moreSpecificRuleTakesOver` | OK | OK (upgrade) `moreSpecificRuleUpgradesBinding` | OK | OK |
| Rule deleted | OK `deletedRuleReleasesWindow` | OK | OK `deletedRuleDropsBinding` | OK | OK |
| Window closed | OK: binding pruned `bindingsPrunedWithWindows` | OK | OK | OK | OK |

## Decisions (for the maintainer)

A. Primary external monitor
1. Lone non-remembered external display: keep it out of the `external` role
   (proposal) or give it the layout (as today)? The proposal applies only when a
   monitor has been remembered; with nothing remembered behaviour is unchanged.
2. Switching the remembered monitor moves the whole layout: confirm first
   (proposal) or switch silently?
3. Card names: "Extra monitor" / "Monitor 2" / "Monitor 3" (proposal).

B. Window drift
1. Sticky binding lives for the window's lifetime (proposal); a strictly more
   specific rule may still take the window; a less specific one never does.
2. A removed temporary pin leaves the window where it is (proposal).
3. Grace for generic titles (title equals the app name): 8 seconds (proposal);
   needs one measurement with a real new session window.
4. Exact owner: while a window whose whole title equals a one-token rule is
   open, other windows that only contain that token do not match the rule.
