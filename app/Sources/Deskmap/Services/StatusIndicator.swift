import CoreGraphics
import Foundation

/// Menü çubuğu simgesinin köşesindeki renkli nokta (saf karar): yeşil =
/// pinli pencerelerin hepsi yerinde; turuncu = iş sürüyor (kurulum
/// değişimi yatışıyor, pencereler yerleşiyor); kırmızı = bir şey yanlış
/// (Accessibility izni yok, kuralın hedef masaüstü yok ya da turuncu
/// `stuckAfter` saniyeden uzun sürdü). Yeni tarama yapılmaz: Router'ın son
/// anlık görüntüsünden hesaplanır.
struct StatusIndicator: Equatable {

    enum Level: Equatable { case green, orange, red }

    var level: Level
    /// Menünün en üstündeki tek satır.
    var reason: String

    /// Turuncu bundan uzun sürerse takılmış sayılır (kırmızı).
    static let stuckAfter: TimeInterval = 60

    struct Inputs {
        var trusted = true
        var settling = false
        /// Hedefinde olmayan pinli pencereler ("Uygulama başlık").
        var misplaced: [String] = []
        /// Hedef masaüstü olmayan kurallar ("Uygulama → ekran/masaüstü").
        var missingTargets: [String] = []
        /// Turuncunun başladığı an (nil = şimdi başlıyor).
        var workingSince: Date?
        var now = Date()
    }

    static func evaluate(_ input: Inputs) -> StatusIndicator {
        if !input.trusted {
            return .init(level: .red, reason: L("Accessibility permission is missing"))
        }
        if !input.missingTargets.isEmpty {
            return .init(level: .red, reason: L("Target desktop missing: %@", list(input.missingTargets)))
        }
        let working = input.settling || !input.misplaced.isEmpty
        guard working else { return .init(level: .green, reason: L("All pinned windows are in place")) }
        let text = input.misplaced.isEmpty
            ? L("Setting up after a display change…")
            : (input.misplaced.count == 1 ? L("1 window not in place: %@", list(input.misplaced))
               : L("%ld windows not in place: %@", input.misplaced.count, list(input.misplaced)))
        if let since = input.workingSince, input.now.timeIntervalSince(since) > stuckAfter {
            return .init(level: .red, reason: text)
        }
        return .init(level: .orange, reason: text)
    }

    /// İlk iki öğe, fazlası "…".
    static func list(_ items: [String]) -> String {
        items.prefix(2).joined(separator: ", ") + (items.count > 2 ? ", …" : "")
    }

    /// Pinli pencerelerin yer denetimi (saf): bu modda hedefi olan, hedef
    /// ekranı bağlı, küçültülmemiş, tam ekran olmayan, serbest hareketi
    /// olmayan pencere hedef masaüstünde değilse `misplaced`; hedef masaüstü
    /// ekranda yoksa (bilinen gerçek sayıdan büyük) `missing`.
    static func check(windows: [Router.WindowSnapshot], rules: [Rule],
                      sessionPins: [CGWindowID: Destination], mode: Mode,
                      desktopCounts: [String: Int], free: Set<CGWindowID>)
        -> (misplaced: [String], missing: [String]) {
        var misplaced: [String] = []
        var missing: [String] = []
        for window in windows where !window.isMinimized && window.fullscreen == nil
            && !free.contains(window.id) {
            guard let match = Routing.select(
                rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                bundleID: window.bundleID, appName: window.appName, title: window.title,
                document: window.document),
                  let real = desktopCounts[match.destination.screen] else { continue }
            let target = match.destination
            let name = window.title.isEmpty ? window.appName
                : "\(window.appName) \(window.title.prefix(30))"
            if target.desktop > real {
                let item = "\(window.appName) → \(target.screen)/\(target.desktop)"
                if !missing.contains(item) { missing.append(item) }
                continue
            }
            guard let placement = window.placement else { continue }
            if placement.screen != target.screen || placement.desktop != target.desktop {
                misplaced.append(name)
            }
        }
        return (misplaced, missing)
    }
}

/// Turuncunun ne zamandır sürdüğünü tutar (menü çubuğu çiziminde).
@MainActor
enum StatusIndicatorClock {
    private static var since: Date?

    /// `working`: kırmızı/yeşil eşiğinden bağımsız "iş sürüyor" durumu.
    static func workingSince(_ working: Bool, now: Date = Date()) -> Date? {
        if !working { since = nil; return nil }
        if since == nil { since = now }
        return since
    }
}

extension StatusIndicator {
    /// Uygulamanın canlı durumundan (Router'ın son taraması) gösterge.
    @MainActor static func current(store: Store, router: Router, screens: ScreenService,
                                   trusted: Bool, now: Date = Date()) -> StatusIndicator {
        let found = check(windows: router.windows, rules: store.document.rules,
                          sessionPins: router.sessionPins, mode: screens.mode,
                          desktopCounts: router.desktopCounts,
                          free: Router.activeFreeMoves(router.freeMoves, now: now))
        let working = trusted && found.missing.isEmpty
            && (screens.isSettling || !found.misplaced.isEmpty)
        return evaluate(Inputs(trusted: trusted, settling: screens.isSettling,
                               misplaced: found.misplaced, missingTargets: found.missing,
                               workingSince: StatusIndicatorClock.workingSince(working, now: now),
                               now: now))
    }
}
