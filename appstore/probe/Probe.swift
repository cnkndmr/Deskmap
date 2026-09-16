// Deskmap App Store probe.
//
// Measures, on a real Mac, which of the things Deskmap needs still work when
// the process is App Sandboxed. The same source is packaged twice — once
// sandboxed, once not — so a failure can be told apart from a bug in the
// probe itself. Launch through LaunchServices (`open`), never from a shell:
// a binary started from Terminal inherits Terminal's Accessibility grant.
//
// Results are written to NSTemporaryDirectory()/deskmap-probe.txt
// (inside the container when sandboxed).

import AppKit
import ApplicationServices

var lines: [String] = []
func record(_ key: String, _ value: Any) {
    lines.append("\(key): \(value)")
}

let info = ProcessInfo.processInfo
let sandboxed = info.environment["APP_SANDBOX_CONTAINER_ID"] != nil
record("bundle", Bundle.main.bundleIdentifier ?? "-")
record("sandboxed", sandboxed)
record("macOS", info.operatingSystemVersionString)

// 1. Accessibility trust.
if CommandLine.arguments.contains("--prompt") || info.environment["PROBE_PROMPT"] != nil
    || FileManager.default.fileExists(atPath: NSTemporaryDirectory() + "prompt") {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    record("ax.promptedTrusted", AXIsProcessTrustedWithOptions(options))
}
let trusted = AXIsProcessTrusted()
record("ax.trusted", trusted)

// 2. Read and move another app's window: a Finder window, moved 40 pt and back.
func axValue<T>(_ element: AXUIElement, _ attribute: String) -> (AXError, T?) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return (error, value as? T)
}

if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    let (windowsError, windows): (AXError, [AXUIElement]?) = axValue(app, kAXWindowsAttribute)
    record("ax.read.windowsError", windowsError.rawValue)
    record("ax.read.windowCount", windows?.count ?? -1)

    if let window = windows?.first {
        let (_, title): (AXError, String?) = axValue(window, kAXTitleAttribute)
        record("ax.read.firstTitleVisible", title.map { !$0.isEmpty } ?? false)

        var positionRef: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        record("ax.read.positionError", positionError.rawValue)

        if positionError == .success, let positionRef {
            var origin = CGPoint.zero
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin)
            var moved = CGPoint(x: origin.x + 40, y: origin.y)
            let movedValue = AXValueCreate(.cgPoint, &moved)!
            let setError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, movedValue)
            record("ax.write.setPositionError", setError.rawValue)

            Thread.sleep(forTimeInterval: 0.3)
            var afterRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &afterRef)
            var after = CGPoint.zero
            if let afterRef { AXValueGetValue(afterRef as! AXValue, .cgPoint, &after) }
            record("ax.write.actuallyMoved", abs(after.x - moved.x) < 2)

            let back = AXValueCreate(.cgPoint, &origin)!
            record("ax.write.restoreError", AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, back).rawValue)
        }
    }
} else {
    record("finder", "not running")
}

// 3. Window list through the public CoreGraphics API, and whether titles come with it.
let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
record("cg.windowCount", normal.count)
record("cg.windowsWithTitle", normal.filter { !(($0[kCGWindowName as String] as? String) ?? "").isEmpty }.count)
record("cg.screenCapturePreflight", CGPreflightScreenCaptureAccess())

// 4. Spaces through SkyLight (private — only to learn whether the sandbox blocks it).
if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    if let mainSym = dlsym(handle, "SLSMainConnectionID"),
       let spacesSym = dlsym(handle, "SLSCopyManagedDisplaySpaces") {
        let connection = unsafeBitCast(mainSym, to: MainConnection.self)()
        let displays = unsafeBitCast(spacesSym, to: CopySpaces.self)(connection)?.takeRetainedValue() as? [[String: Any]]
        record("skylight.displays", displays?.count ?? -1)
    } else {
        record("skylight", "symbols missing")
    }
} else {
    record("skylight", "dlopen failed")
}

let output = NSTemporaryDirectory() + "deskmap-probe.txt"
try? (lines.joined(separator: "\n") + "\n").write(toFile: output, atomically: true, encoding: .utf8)
exit(0)
