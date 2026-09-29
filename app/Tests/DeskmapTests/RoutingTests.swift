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

    @Test func grantHoldsOnlyForItsTarget() {
        let d2 = Destination(screen: "builtin", desktop: 2, layout: .full)
        var moved = d2
        moved.desktop = 3
        var resized = d2
        resized.layout = WindowLayout(x: 0, y: 0, w: 0.5, h: 1)
        #expect(Router.freeMoveHolds(grantedFor: d2, current: d2))
        #expect(!Router.freeMoveHolds(grantedFor: d2, current: moved))
        #expect(!Router.freeMoveHolds(grantedFor: d2, current: resized))
    }

    @Test func remainingText() {
        #expect(Router.freeMoveRemaining(0) == "0:00")
        #expect(Router.freeMoveRemaining(4.2) == "0:05")
        #expect(Router.freeMoveRemaining(245) == "4:05")
        #expect(Router.freeMoveRemaining(3600) == "1:00:00")
        #expect(Router.freeMoveRemaining(-3) == "0:00")
    }
}
