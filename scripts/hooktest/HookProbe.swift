import AppKit
// Kullanım: HookProbe <senaryo> [n] [bekleme]
let args = CommandLine.arguments
let scenario = args.count > 1 ? args[1] : "idle"
let n = args.count > 2 ? Int(args[2])! : 1
let pause = args.count > 3 ? Double(args[3])! : 1.0
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let w = NSWindow(contentRect: NSRect(x: 600, y: 400, width: 360, height: 240),
                 styleMask: [.titled, .resizable], backing: .buffered, defer: false)
w.title = "HookProbe"
w.orderFrontRegardless()
let builtin = NSPoint(x: 600, y: 400), external = NSPoint(x: 600, y: 1900)
func say(_ s: String) { print("\(Date().timeIntervalSince1970) \(s)"); fflush(stdout) }
// Arka planda bekler, her adımı ana iş parçacığına bırakır (uygulama yanıt verir kalır).
// BUSY=1 ise bütün sürükleme ana iş parçacığını kilitler (meşgul uygulama).
let busy = ProcessInfo.processInfo.environment["BUSY"] == "1"
func drag(from a: NSPoint, to b: NSPoint, steps: Int = 30, dt: Double = 0.02) {
    func step(_ i: Int) { let t = Double(i) / Double(steps)
        w.setFrameOrigin(NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }
    if busy { DispatchQueue.main.sync { for i in 0...steps { step(i); Thread.sleep(forTimeInterval: dt) } }; return }
    for i in 0...steps { DispatchQueue.main.sync { step(i) }; Thread.sleep(forTimeInterval: dt) }
}
DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 4)          // Deskmap pencereyi görsün
    say("start \(scenario)")
    func onMain(_ f: () -> Void) { f() }
    switch scenario {
    case "cross":        // n kez gidip gel, her geçiş arası `pause` sn
        var here = builtin
        for i in 0..<n { let there = here == builtin ? external : builtin
            onMain { drag(from: here, to: there) }; say("crossed \(i + 1) to \(there == builtin ? "builtin" : "external")")
            here = there; Thread.sleep(forTimeInterval: pause) }
    case "hold":         // monitöre sürükle, `pause` sn tut, bırakmadan geri dön
        onMain { drag(from: builtin, to: external) }; say("holding on external")
        Thread.sleep(forTimeInterval: pause)
        onMain { drag(from: external, to: builtin) }; say("released on builtin")
    case "jiggle":       // n sn boyunca aynı ekranda sürekli hareket
        let end = Date().addingTimeInterval(Double(n))
        while Date() < end { onMain { drag(from: builtin, to: NSPoint(x: 900, y: 500), steps: 20, dt: 0.016)
                                      drag(from: NSPoint(x: 900, y: 500), to: builtin, steps: 20, dt: 0.016) } }
    case "virtual":      // sanal ekran görünene dek bekle, pencereyi oraya taşı, n sn izle
        var target: NSScreen?
        for _ in 0..<100 { target = DispatchQueue.main.sync { NSScreen.screens.first { $0.localizedName == "Deskmap Test Display" } }
            if target != nil { break }; Thread.sleep(forTimeInterval: 0.1) }
        guard let screen = target else { say("no virtual screen"); exit(2) }
        let center = NSPoint(x: screen.frame.midX - 180, y: screen.frame.midY - 120)
        onMain { drag(from: builtin, to: center) }; say("on virtual")
        for _ in 0..<n { Thread.sleep(forTimeInterval: 1)
            let name = DispatchQueue.main.sync { w.screen?.localizedName ?? "?" }; say("window on \(name)") }
    default:
        Thread.sleep(forTimeInterval: Double(n))
    }
    Thread.sleep(forTimeInterval: 3)
    say("end")
    exit(0)
}
app.run()
