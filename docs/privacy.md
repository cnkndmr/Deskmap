# Privacy

Short version: the app collects nothing, sends nothing, and has no network
code at all.

## What it reads

To do its job it reads, through the macOS Accessibility API:

- the list of open windows, their owning app, their title, position and size
- which display and desktop each window is on (via the window server)

That is all. It does not read window *contents*, documents, keystrokes, the
clipboard, or anything about you.

## Where that goes

Nowhere. There is no network code in the app — no `URLSession`, no sockets,
no analytics SDK, no crash reporter, no update check. You can verify it:

```sh
grep -rn 'URLSession\|import Network' app/Sources     # no matches
```

What it writes stays on the Mac, in your own Application Support folder:

| File | Contents |
|---|---|
| `~/Library/Application Support/Deskmap/rules.json` | your pins, profiles and known displays |
| `~/Library/Application Support/Deskmap/session-pins.json` | temporary pins (window and process IDs) |
| `~/Library/Application Support/Deskmap/desktop-state.json` | desktops per display and their windows (IDs only, no titles) |
| `~/Library/Application Support/Deskmap/status.json` | a snapshot of the current state (displays, windows, profile) for the `deskmap` command-line tool |
| `~/Library/Application Support/Deskmap/Backups/` | automatic backups of `rules.json` (hourly for a day, daily for a week, weekly forever) |

All are plain JSON you can read, edit or delete. Deleting them resets the
app; deleting the app leaves nothing else behind.

## Logs

The app writes sparse entries to the macOS unified log (subsystem
`com.deskmap.app`): desktop moves, give-ups, unresponsive apps, display
changes, sleep and wake. App names and display names appear in the clear so
the log is useful; **window titles are never logged**. These entries stay on
your Mac like every other system log and are not collected by anyone.

## Permissions it asks for

- **Accessibility** — required, and the only one. Without it the app can
  neither see window titles nor move windows.

It does not ask for Screen Recording, Full Disk Access, Contacts, Calendar,
Microphone, Camera, or anything else. If any app claiming to be this one
asks for those, it is not this one.

---

## Türkçe özet

Uygulama hiçbir veri toplamaz, hiçbir şey göndermez; içinde ağ kodu yoktur.
Erişilebilirlik izniyle yalnızca açık pencerelerin uygulaması, başlığı,
konumu ve bulunduğu ekran/masaüstü bilgisini okur; pencere içeriğine,
belgelerine, tuş vuruşlarına bakmaz. Yazdığı tek şey kendi
`~/Library/Application Support/Deskmap/` klasöründeki JSON dosyaları
ve aynı klasördeki `Backups/` altında bunların otomatik yedekleridir. macOS sistem günlüğüne seyrek satır yazar; **pencere başlıkları
günlüğe yazılmaz**. Tek istediği izin Erişilebilirlik'tir.
