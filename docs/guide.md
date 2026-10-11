# User guide

Deskmap puts each of your windows on the right display, on the right
desktop, in the right size — and keeps putting it back, without you asking
again.

You tell it once: *"the window with `acme-web` in its title belongs on the
monitor, desktop 2, left half."* From then on it happens by itself: when you
open the app, when you plug the monitor in, when you come back from lunch.

This guide takes about ten minutes. You need macOS 13 or later.

---

## 1. Install and give permission

1. Copy **Deskmap.app** to your Applications folder and open it. It has
   no Dock icon; it lives in the menu bar.
2. The **welcome guide** opens on first launch and walks through three steps.
   Step 1 is the permission: click **Open System Settings and allow**.
3. macOS opens System Settings › Privacy & Security › Accessibility. Turn
   **Deskmap** on; the guide notices it by itself.

   The app needs this to see window titles and to move windows. It reads
   nothing else: no network, no files of yours, no window contents.
4. Step 2 checks the macOS settings below, step 3 asks how to start: **Pin my
   windows where they are** (recommended) or **Start empty**. You can open the
   guide again from **Settings › General**.
5. Open **Settings** (⚙ in the toolbar, or ⌘,) › **General** and turn on
   **Launch at login** so Deskmap is there after every restart.

![The map: displays, desktops and the windows on them](images/en/01-map.png)

## 2. Fix four macOS settings (once)

The app checks these live: the welcome guide's second step, the
**Settings › macOS Settings** tab and, if one of them goes wrong later, an
orange card on the map. Click **Open Desktop & Dock** and set:

| Setting | Must be |
|---|---|
| Automatically rearrange Spaces based on most recent use | **Off** |
| When switching to an application, switch to a Space with open windows | **On** |
| Displays have separate Spaces | **On** |
| Group windows by application | Off (recommended) |

One more, which macOS won't let any app check: for every app you are going
to pin, right-click its Dock icon › **Options › Assign To → None**. If macOS
has assigned the app to a desktop itself, it will fight over the window.

![The settings card tells you exactly which setting is wrong](images/en/05-setup.png)

## 3. Pin your first window

1. Open the window you care about — say a project in VS Code.
2. Click the menu bar icon. The **map** shows one card per display and one
   row per desktop, with the windows that are on each of them right now.
   Next to each desktop, a small **preview** draws its windows where they sit
   (turn it off with **Visual | List**). Looking for one window? Press **⌘F**
   and type part of its name.
3. Find your window and click its **pin** button (or right-click the row ›
   **Pin to this desktop…**). Its details open in the column on the right.

![Choosing which part of the title identifies the window](images/en/02-pin.png)

4. The panel starts with one sentence, for example *Messages · this window
   (general) → Built-in Display · Desktop 2 · Full*. Each underlined part is a
   menu. The first one offers two choices:
   - **This window (key)** — Deskmap works out a stable key for the window
     and shows it in brackets. In order: the file the window shows (Preview,
     Pages, Word, Excel, TextEdit… — two different `main.pdf` files stay
     apart); otherwise the part of the title that has stayed the same while
     the title changed (VS Code's project folder, Terminal's `user@host`,
     Safari's tab group); before any title change has been seen, a cleaned
     title (page numbers, "Edited", unread counts dropped). The panel tells
     you how many open windows match right now.
   - **All windows of the app**, whatever the title. Good for Mail or Slack.

   If the window has no stable key (every part of its title changes, like a
   Safari window without a tab group) or the key would also match another
   open window, only **All windows** is offered.
5. Click **Pin** (or press Return).

Several windows at once: **Pin all … where they are** in the *Unassigned
windows* box (or ⌘-click rows) selects them; confirm in the right-hand
column. Each one keeps its current desktop, size and position.

That's a pin. Tomorrow's window with the same file or project, the one after
a restart — same place.

## 4. Move it where it belongs

Drag the row (or the chip) onto another desktop row — on any display. That
is how you say "no, this one lives on the monitor, desktop 3". You can also
click **Desktop 2** or the display's name in the panel's sentence and pick
another one, or right-click the row › **Send to**.

- Desktops that don't exist yet are drawn with a dashed line. macOS only
  lets *you* create desktops: open Mission Control and add them, then the
  row becomes solid.
- An orange **Desktop 5 missing** badge means the pin wants desktop 5 but the
  display has only 3, so the window waits on the last one (hover it for the
  details).
- Dragging an **unpinned** window moves it once and saves nothing.

## 5. Give it a size

Click a pinned row or chip. Under the sentence are four layouts: **Full**,
**Left half**, **Right half** and **As it is** (only the desktop is kept;
Deskmap never moves or resizes the window there). Everything else is under
**Advanced ▸**: the title parts, a grid to drag across, all presets (70/30,
thirds, quarters, top/bottom half, center), a gap to leave from the edges and
a fixed size. Advanced stays open for the next window once you open it.

![Layouts: full, halves, 70/30, centred](images/en/03-layout.png)

The layout is applied once per window. After that, resize it however you
like — the app won't keep snapping it back. Press **⌘R** (or **⋯ › Place
pinned windows now**) when you want everything placed again from scratch.

Need to move a pinned window by hand for a while? **Free move** in the panel,
or right-click its row › **Free move** › 5, 15, 30… minutes. Deskmap leaves it
alone until the time is up, then puts it back.

Found a size you like by hand? Click the pinned row, open **Advanced** and
press **Use current size and position**: the window's current place and
size become the pin's layout. The pin stays on its display and desktop.
Undo with ⌘Z if you change your mind.

## 6. Two plans: with monitor, without

Your windows can't live on desktop 3 of a monitor that isn't plugged in. So
every pin has two targets, and the **Plan** switch at the top (**⌘1 / ⌘2**)
shows one or the other. The plan in effect right now is marked **active
now**; the other one says when it applies.

- **Monitor connected** — at least one external display is attached.
- **Laptop only** — just the built-in screen.

Set up one, switch, set up the other. When you plug the monitor in or pull
it out, the app waits a couple of seconds for the displays to settle and
then puts every pinned window where that plan says.

A pin you don't want in one of the plans: drag it to the *Placed in one plan
only* box in the left sidebar. It stays in the other plan.

## 7. Profiles: desk, café, presentation

A profile is a whole set of pins with a name. **Profile: … ▾** in the toolbar
switches between them instantly.

![Settings › Profiles](images/en/07-settings-profiles.png)

- **Settings › Profiles** lists them: **Use** switches, **⋯** renames,
  duplicates, exports or deletes; **New empty profile** and **Import…** below.
  A new or duplicated profile does not switch on by itself: press **Use**.
- Export writes a `.deskmap.json` file — that's how you carry your setup
  to another Mac, or share it.

## 8. When you change your mind

- **Undo**: after unpinning, dragging a pin, or reordering desktops, the
  footer shows *"Pin deleted · Undo"* for ten seconds. Click it or press
  **⌘Z**. There are no confirmation dialogs anywhere in the app; this is why.
- **Recent moves** (toolbar): which pinned window Deskmap sent where, and
  when — the answer to "why did my window jump?".
- **Pause**: the **Deskmap on** switch at the top left, or right-click the
  menu bar icon › **Pause for 15 minutes**. Nothing is moved while it is off,
  and the menu bar icon shows a pause sign. A switched-off Deskmap stays off
  after restarts, so if the app ever seems asleep, look there first.
- **?** in the toolbar explains every color and badge on the map.

Right-clicking the menu bar icon also offers **Pin it where it is** for the
front window, the free-move times for a pinned one, the profiles, Settings
and Quit. A left click opens the map.

## 9. One-key setups (optional)

The app answers `deskmap://` links, so anything that can open a URL can
drive it:

```sh
open "deskmap://profile/Café"   # switch profile
open "deskmap://reapply"        # place everything now
open "deskmap://toggle"         # pause / resume
```

Put one in a Shortcut and give it a keyboard shortcut, or trigger it from a
macOS Focus automation: "when Work Focus turns on, switch to the Desk
profile".

## 10. If something doesn't happen

| What you see | What it means |
|---|---|
| Window doesn't move at all | Deskmap is paused (top left), or the Accessibility permission was lost after an app update — grant it again. |
| Window lands on the wrong desktop | "Automatically rearrange Spaces" is on, or the app's Dock **Assign To** isn't **None**. |
| A pin's chip looks faded | Another, more specific pin matches that window first. Hover it to see which. |
| Orange **Desktop 5 missing** badge | That desktop doesn't exist; add desktops in Mission Control. |
| A window jumped and you don't know why | **Recent moves** in the toolbar lists each move and its target. |
| Nothing moves between desktops, but sizes work | This macOS version didn't expose the private calls the app uses for desktops. Displays and layouts still work. |

Longer troubleshooting, the full rules of matching, and the data file
formats are in the [README](../README.md).

---

### The two sentences to remember

**A pin is a promise about a title**: any window whose title contains this
part, from now on, belongs here. **Everything else is drag and drop** — the
map is the app.
