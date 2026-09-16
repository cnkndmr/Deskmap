# App Store probe

Answers one question by measurement instead of by forum posts: **can a
sandboxed app use the Accessibility API to read and move other apps'
windows?** Deskmap's whole engine depends on it, and the Mac App Store
requires the sandbox.

`Probe.swift` is packaged twice by `build.sh` into `/tmp/deskmap-probe/`:
`ProbePlain.app` (no sandbox, the control) and `ProbeSandbox.app`
(`com.apple.security.app-sandbox`). Each one reads a Finder window through
AX, moves it 40 pt and back, lists windows through `CGWindowListCopyWindowInfo`
and reads Spaces through SkyLight, then writes the results to
`NSTemporaryDirectory()/deskmap-probe.txt` (inside the container when
sandboxed).

```sh
appstore/probe/build.sh
open -W /tmp/deskmap-probe/ProbePlain.app
open -W /tmp/deskmap-probe/ProbeSandbox.app
cat "$(getconf DARWIN_USER_TEMP_DIR)deskmap-probe.txt"
cat ~/Library/Containers/com.deskmap.probe.sandbox/Data/tmp/deskmap-probe.txt
```

Launch with `open`, never from a shell: a binary started from Terminal
inherits Terminal's Accessibility grant and the result is meaningless. Both
apps need the Accessibility permission; they live in `/tmp`, so System
Settings accepts them but does not show them in the list.

## Result — 16 September 2026, macOS 26.6.2, both apps granted Accessibility

| | Plain | Sandboxed |
|---|---|---|
| `AXIsProcessTrusted()` | true | **true** |
| Read another app's windows (`kAXWindows`) | ok, 2 windows | **fails: −25204 `kAXErrorCannotComplete`** |
| Move a window and read it back | moved | not reachable |
| `CGWindowListCopyWindowInfo` | 11 windows, no titles | 11 windows, no titles |
| SkyLight `SLSCopyManagedDisplaySpaces` | 1 display | 1 display (private API — rejected anyway) |

Before the permission was granted the plain probe failed with −25211
(`kAXErrorAPIDisabled`) and the sandboxed one already with −25204: the
sandbox refusal is a separate wall that the permission does not open.

**Conclusion:** a sandboxed Deskmap cannot see other apps' windows, let alone
place them, even when the user grants Accessibility. A Mac App Store edition
can therefore not do what Deskmap does. The unfinished attempt at one (an
`APPSTORE` compile flag without private API) is kept on the
`deskmap-appstore` branch.
