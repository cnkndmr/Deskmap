import AppKit
import CoreGraphics
// Çok monitör ölçümü (multimon.sh). Salt okur; yalnız kendi penceresini taşır.
// MonProbe list               bağlı ekranlar: kimlik, UUID, satıcı/model/seri, ad, çerçeve
// MonProbe watch <sn>         CGDisplayRegisterReconfigurationCallback olayları (zaman damgalı)
// MonProbe window <sn> <k>    kendi penceresini k. "Deskmap Test Display"e koyar, her saniye
//                             hangi ekranda olduğunu yazar
let a = CommandLine.arguments
let mode = a.count > 1 ? a[1] : "list"
func now() -> String { String(format: "%.2f", Date().timeIntervalSince1970) }
func uuid(_ id: CGDirectDisplayID) -> String {
    CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "-"
}
func displays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n)))
}
func name(_ id: CGDirectDisplayID) -> String {
    NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?.localizedName ?? "-"
}
switch mode {
case "list":
    for id in displays() {
        let b = CGDisplayBounds(id)
        print("display id=\(id) uuid=\(uuid(id)) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id)) serial=\(CGDisplaySerialNumber(id)) builtin=\(CGDisplayIsBuiltin(id)) name=\"\(name(id))\" frame=\(Int(b.minX)),\(Int(b.minY)),\(Int(b.width))x\(Int(b.height))")
    }
case "watch":
    let seconds = a.count > 2 ? Double(a[2])! : 60
    CGDisplayRegisterReconfigurationCallback({ id, flags, _ in
        var f: [String] = []
        if flags.contains(.beginConfigurationFlag) { f.append("begin") }
        if flags.contains(.addFlag) { f.append("add") }
        if flags.contains(.removeFlag) { f.append("remove") }
        if flags.contains(.movedFlag) { f.append("moved") }
        if flags.contains(.setMainFlag) { f.append("setMain") }
        if flags.contains(.setModeFlag) { f.append("setMode") }
        if flags.contains(.mirrorFlag) { f.append("mirror") }
        if flags.contains(.desktopShapeChangedFlag) { f.append("shape") }
        print("\(now()) reconfig id=\(id) uuid=\(uuid(id).prefix(8)) \(f.joined(separator: ","))"); fflush(stdout)
    }, nil)
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
case "window":
    let seconds = a.count > 2 ? Double(a[2])! : 30
    let k = a.count > 3 ? Int(a[3])! : 1
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 240),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.title = "MonProbe"; w.orderFrontRegardless()
    var placed = false
    let end = Date().addingTimeInterval(seconds)
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        // macOS aynı adlı ikinci ekranı "Deskmap Test Display (1)" diye adlandırır.
        let tests = NSScreen.screens.filter { $0.localizedName.hasPrefix("Deskmap Test Display") }
            .sorted { $0.frame.minX < $1.frame.minX }
        if !placed, tests.count >= k {
            let s = tests[k - 1]
            w.setFrameOrigin(NSPoint(x: s.frame.midX - 180, y: s.frame.midY - 120)); placed = true
            print("\(now()) placed on test display \(k)")
        }
        let id = (w.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        print("\(now()) window on id=\(id) uuid=\(uuid(id).prefix(8)) name=\"\(w.screen?.localizedName ?? "-")\" frame=\(Int(w.frame.minX)),\(Int(w.frame.minY))"); fflush(stdout)
        if Date() > end { exit(0) }
    }
    app.run()
default:
    print("usage: MonProbe list | watch <s> | window <s> <k>")
}
