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
2. Click the menu bar icon. The first thing you see is **Accessibility
   permission required** → click **Grant Access**.
3. macOS opens System Settings › Privacy & Security › Accessibility. Turn
   **Deskmap** on.

   The app needs this to see window titles and to move windows. It reads
   nothing else: no network, no files of yours, no window contents.
4. Back in the app, turn on **Launch at login** in the footer so it is there
   after every restart.

![The map: displays, desktops and the windows on them](images/en/01-map.png)

## 2. Fix four macOS settings (once)

The app checks these live and shows an orange card until they are right.
Click **Open Desktop & Dock** on the card and set:

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
3. Find your window in the list and click its **pin** button. A panel opens
   at the bottom.

![Choosing which part of the title identifies the window](images/en/02-pin.png)

4. The panel offers two choices:
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

That's a pin. Tomorrow's window with the same file or project, the one after
a restart — same place.

## 4. Move it where it belongs

Drag the row (or the chip) onto another desktop row — on any display. That
is how you say "no, this one lives on the monitor, desktop 3".

- Desktops that don't exist yet are drawn with a dashed line. macOS only
  lets *you* create desktops: open Mission Control and add them, then the
  row becomes solid.
- An orange **D5→3** badge means the pin wants desktop 5 but the display has
  only 3, so the window went to the last one.
- Dragging an **unpinned** window moves it once and saves nothing.

## 5. Give it a size

Click a pinned row or chip and pick a layout: **Full**, **Left half**,
**Right half**, **Left 70%** / **Right 30%**, **Top half**, **Bottom half**
or **Center**. The default is "wherever the window is now", and you can set
a gap to leave from the edges.

![Layouts: full, halves, 70/30, centred](images/en/03-layout.png)

The layout is applied once per window. After that, resize it however you
like — the app won't keep snapping it back. Press **⌘R** (or the ↻ button)
when you want everything placed again from scratch.

Found a size you like by hand? Click the pinned row and press **Use current
size and position** under the layout editor: the window's current place and
size become the pin's layout. The pin stays on its display and desktop.
Undo with ⌘Z if you change your mind.

## 6. Two setups: with monitor, without

Your windows can't live on desktop 3 of a monitor that isn't plugged in. So
every pin has two targets, and the buttons at the top (**⌘1 / ⌘2**) switch
between them:

- **Monitor connected** — at least one external display is attached.
- **Laptop only** — just the built-in screen.

Set up one, switch, set up the other. When you plug the monitor in or pull
it out, the app waits a couple of seconds for the displays to settle and
then puts every pinned window where that setup says.

A pin you don't want in one of the setups: drag it to the *Different between
setups* box in the left sidebar. It stays in the other setup.

## 7. Profiles: desk, café, presentation

A profile is a whole set of pins with a name. The chips under the toolbar
switch between them instantly.

![Profiles with their pin counts](images/en/04-profiles.png)

- **+** makes an empty profile; click the active one to rename, duplicate,
  export or delete it.
- Export writes a `.deskmap.json` file — that's how you carry your setup
  to another Mac, or share it.
- **Backups** (in the same panel): Deskmap backs up all profiles, pins and
  desktop names by itself — one copy per hour for the last day, one per day
  for the last week, one per week forever. Pick one and click **Restore**
  twice; your current state is backed up first, and the footer offers
  *Undo*.

## 8. When you change your mind

- **Undo**: after unpinning, dragging a pin, or reordering desktops, the
  footer shows *"Pin removed · Undo"* for ten seconds. Click it or press
  **⌘Z**. There are no confirmation dialogs anywhere in the app; this is why.
- **Pause**: the switch at the top left. Nothing is moved while it is off,
  and the menu bar icon shows a pause sign. It survives restarts, so if the
  app ever seems asleep, look there first.

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
| Window doesn't move at all | Routing is paused (top left), or the Accessibility permission was lost after an app update — grant it again. |
| Window lands on the wrong desktop | "Automatically rearrange Spaces" is on, or the app's Dock **Assign To** isn't **None**. |
| A pin's chip looks faded | Another, more specific pin matches that window first. Hover it to see which. |
| Orange **D5→3** badge | That desktop doesn't exist; add desktops in Mission Control. |
| Nothing moves between desktops, but sizes work | This macOS version didn't expose the private calls the app uses for desktops. Displays and layouts still work. |

Longer troubleshooting, the full rules of matching, and the data file
formats are in the [README](../README.md).

---

### The two sentences to remember

**A pin is a promise about a title**: any window whose title contains this
part, from now on, belongs here. **Everything else is drag and drop** — the
map is the app.
