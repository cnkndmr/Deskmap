// Test penceresini (HookProbe) AX ile verilen çerçeveye koyar: x y w h [pid]
// (AX, sol üst tabanlı). pid verilirse o süreç; yoksa en son açılan HookProbe.
import AppKit
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
let probes = NSWorkspace.shared.runningApplications.filter { $0.localizedName == "HookProbe" }
let wanted = a.count == 5 ? probes.first { $0.processIdentifier == pid_t(a[4]) }
    : probes.max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
guard a.count >= 4, let app = wanted
else { print("usage: resize x y w h (HookProbe running)"); exit(1) }
let el = AXUIElementCreateApplication(app.processIdentifier)
var raw: CFTypeRef?
AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &raw)
guard let w = (raw as? [AXUIElement])?.first else { print("no window"); exit(1) }
var p = CGPoint(x: a[0], y: a[1]), s = CGSize(width: a[2], height: a[3])
AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
