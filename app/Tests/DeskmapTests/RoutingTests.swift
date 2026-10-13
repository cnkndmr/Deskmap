import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Hedef seçimi ve düzen denemesi sayımı (Router ile arayüzün ortak dilimi).
struct RoutingTests {

    private let external = Destination(screen: "external", desktop: 2)
    private let builtin = Destination(screen: "builtin", desktop: 1)

    private func select(_ rules: [Rule], pins: [CGWindowID: Destination] = [:],
                        mode: Mode = .docked, title: String = "Store.swift — Atlas") -> Routing.Match? {
        Routing.select(rules: rules, sessionPins: pins, mode: mode, windowID: 7,
                       bundleID: "com.microsoft.VSCode", appName: "Code", title: title)
    }

    @Test func mostSpecificMatchingRuleWins() {
        let appWide = Rule(id: "wide", appName: "Code", bundleID: "com.microsoft.VSCode",
                           tokens: [], docked: builtin)
        let specific = Rule(id: "atlas", appName: "Code", bundleID: "com.microsoft.VSCode",
                            tokens: ["atlas"], docked: external)
        // Liste sırası önemsiz; parça sayısı çok olan önce denenir.
        let match = select([appWide, specific])
        #expect(match?.ruleID == "atlas")
        #expect(match?.destination == external)
        #expect(match?.rule == specific)
        #expect(select([appWide, specific], title: "Other.swift")?.ruleID == "wide")
    }

    @Test func specificRuleWithoutTargetDoesNotBlockAppWide() {
        let appWide = Rule(id: "wide", appName: "Code", bundleID: "com.microsoft.VSCode",
                           tokens: [], docked: builtin)
        let specific = Rule(id: "atlas", appName: "Code", bundleID: "com.microsoft.VSCode",
                            tokens: ["atlas"], undocked: external)   // bu modda hedefi yok
        let match = select([specific, appWide], mode: .docked)
        #expect(match?.ruleID == "wide")
        #expect(select([specific, appWide], mode: .undocked)?.ruleID == "atlas")
    }

    @Test func sessionPinBeatsRules() {
        let appWide = Rule(id: "wide", appName: "Code", bundleID: "com.microsoft.VSCode",
                           tokens: [], docked: builtin)
        let pinned = Destination(screen: "external", desktop: 4, layout: .center)
        let match = select([appWide], pins: [7: pinned])
        #expect(match?.ruleID == Routing.sessionRuleID)
        #expect(match?.destination == pinned)
        #expect(match?.rule == nil)
        // Başka pencerenin pini bu pencereyi etkilemez.
        #expect(select([appWide], pins: [8: pinned])?.ruleID == "wide")
    }

    @Test func noMatchReturnsNil() {
        let other = Rule(id: "safari", appName: "Safari", bundleID: "com.apple.Safari",
                         tokens: [], docked: builtin)
        let wrongTitle = Rule(id: "t", appName: "Code", bundleID: "com.microsoft.VSCode",
                              tokens: ["Comet_notes"], docked: builtin)
        #expect(select([other, wrongTitle]) == nil)
        #expect(select([]) == nil)
    }

    // MARK: Düzen denemeleri

    @Test func attemptConstantsUnchanged() {
        #expect(Routing.maxAttempts == 6)
        #expect(Routing.quickAttempts == 4)
    }

    @Test func layoutAttemptsGiveUpAtLimitWithQuickFollowUpsFirst() {
        var applied: Set<String> = []
        var attempts: [String: Int] = [:]
        var followUps: [Bool] = []
        for _ in 1...Routing.maxAttempts {
            followUps.append(Routing.recordLayoutAttempt(
                key: "k", placed: false, applied: &applied, attempts: &attempts))
        }
        // İlk 4 deneme hızlı tekrar ister; 5. ister, 6.'da vazgeçilir.
        #expect(followUps == [true, true, true, true, false, false])
        #expect(applied.contains("k"))
        #expect(attempts["k"] == nil)
    }

    @Test func layoutAttemptCounterGrowsUntilLimit() {
        var applied: Set<String> = []
        var attempts: [String: Int] = [:]
        for expected in 1..<Routing.maxAttempts {
            _ = Routing.recordLayoutAttempt(key: "k", placed: false,
                                            applied: &applied, attempts: &attempts)
            #expect(attempts["k"] == expected)
            #expect(!applied.contains("k"))
        }
    }

    @Test func successfulPlacementResetsCounter() {
        var applied: Set<String> = []
        var attempts: [String: Int] = ["k": 3, "other": 2]
        let followUp = Routing.recordLayoutAttempt(key: "k", placed: true,
                                                   applied: &applied, attempts: &attempts)
        #expect(!followUp)
        #expect(applied == ["k"])
        #expect(attempts == ["other": 2])
    }
}

struct FreeMoveTests {

    @Test func activeOnlyBeforeDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        let until: [CGWindowID: Date] = [1: now.addingTimeInterval(30), 2: now, 3: now.addingTimeInterval(-5)]
        #expect(Router.activeFreeMoves(until, now: now) == [1])
    }

    @Test func grantHoldsOnlyWhileItsPinGovernsTheWindow() {
        let d2 = Destination(screen: "builtin", desktop: 2, layout: .full)
        var d3 = d2
        d3.desktop = 3
        let safari = "com.apple.Safari"
        let wide = Rule(id: "wide", appName: "Safari", bundleID: safari, tokens: [], docked: d2)
        let grant = Router.FreeGrant(ruleID: "wide", destination: d2, bundleID: safari,
                                     appName: "Safari", title: "GitHub – PR")
        func holds(_ rules: [Rule], _ pins: [CGWindowID: Destination] = [:]) -> Bool {
            Router.freeMoveHolds(grant, windowID: 7, rules: rules, sessionPins: pins, mode: .docked)
        }
        // Aynı pin: sürer (canlı başlığa bakılmaz, saklanan başlıkla seçilir).
        #expect(holds([wide]))
        // Pin taşındı / silindi / bu modda hedefi yok: biter.
        var moved = wide
        moved.docked = d3
        #expect(!holds([moved]))
        #expect(!holds([]))
        var otherMode = wide
        otherMode.docked = nil
        otherMode.undocked = d2
        #expect(!holds([otherMode]))
        // Daha özgül yeni pin pencereyi aldı: biter.
        let specific = Rule(id: "gh", appName: "Safari", bundleID: safari, tokens: ["GitHub"], docked: d3)
        #expect(!holds([wide, specific]))
        // Başlığa uymayan yeni pin: sürer.
        let mail = Rule(id: "mail", appName: "Safari", bundleID: safari, tokens: ["Mail"], docked: d3)
        #expect(holds([wide, mail]))
        // Pencereye oturum pini kondu: biter.
        #expect(!holds([wide], [7: d2]))
        // Kurulum değişti, hedef iki modda aynı olsa da: biter.
        var both = wide
        both.undocked = d2
        #expect(!Router.freeMoveHolds(grant, windowID: 7, rules: [both], sessionPins: [:], mode: .undocked))

        let session = Router.FreeGrant(ruleID: Routing.sessionRuleID, destination: d2,
                                       bundleID: safari, appName: "Safari", title: "x")
        #expect(Router.freeMoveHolds(session, windowID: 7, rules: [], sessionPins: [7: d2], mode: .docked))
        #expect(!Router.freeMoveHolds(session, windowID: 7, rules: [], sessionPins: [7: d3], mode: .docked))
        #expect(!Router.freeMoveHolds(session, windowID: 7, rules: [wide], sessionPins: [:], mode: .docked))
    }

    @Test func remainingText() {
        #expect(Router.freeMoveRemaining(0) == "0:00")
        #expect(Router.freeMoveRemaining(4.2) == "0:05")
        #expect(Router.freeMoveRemaining(245) == "4:05")
        #expect(Router.freeMoveRemaining(3600) == "1:00:00")
        #expect(Router.freeMoveRemaining(-3) == "0:00")
    }

    @Test func untilLockAndHourDurations() {
        #expect(Router.freeMoveDurations.contains(2 * 3600))
        #expect(Router.freeMoveDurations.contains(5 * 3600))
        #expect(Router.freeMoveDurations.last == Router.freeMoveUntilLock)
        #expect(Router.isUntilLock(.distantFuture))
        #expect(!Router.isUntilLock(Date().addingTimeInterval(5 * 3600)))
        // Kilide kadar izin turda süresi dolmuş sayılmaz.
        #expect(Router.activeFreeMoves([1: .distantFuture], now: Date()) == [1])
    }

    @Test func mixedGrantStatus() {
        let now = Date()
        let lockOnly = Router.freeMoveStatus([.distantFuture], now: now)
        #expect(lockOnly.timedRemaining == nil)
        let timed = Router.freeMoveStatus([now.addingTimeInterval(120)], now: now)
        #expect(timed.timedRemaining == 120)
        #expect(timed.label.contains("2:00"))
        // Karışık: sayaç süreli izinden gelir, distantFuture'dan değil.
        let mixed = Router.freeMoveStatus([.distantFuture, now.addingTimeInterval(300)], now: now)
        #expect(mixed.timedRemaining == 300)
        #expect(mixed.label.contains("5:00"))
    }
}
