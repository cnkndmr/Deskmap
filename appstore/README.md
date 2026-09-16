# App Store

Everything about a Mac App Store edition of Deskmap, kept in one place.
Short version: the store is closed to what Deskmap does — the sandbox stops
the Accessibility API from reaching other apps' windows, measured on a real
Mac — so the app ships as a DMG instead ([../docs/distribution.md](../docs/distribution.md)).
The material below is ready for the day that changes.

| File | What it is |
|---|---|
| [submission.md](submission.md) | What App Store Connect needs, what is ready, what blocks, and the exact submission steps |
| [listing.md](listing.md) | Name, subtitle, promotional text, description, keywords — English and Turkish |
| [make-store-shots.swift](make-store-shots.swift) | `swift appstore/make-store-shots.swift` → `screenshots/{en,tr}/`, 2880×1800 and 1280×800 (generated, not checked in) |
| [probe/](probe/README.md) | The sandbox measurement and the tool to repeat it |

The unfinished store edition itself — an `APPSTORE` compile flag that builds
without private API — waits on the `deskmap-appstore` branch.
