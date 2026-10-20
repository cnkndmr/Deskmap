import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya: sıralı yerlerin çözümlenmesi (Routing.resolvePlace /
/// Router.resolvePlaces), K1/K3/K4, D2.4, bağ, "Neden burada?", status.json
/// yer durumu, oturum pinleri, 3-4 harici ekran ve clamshell. Mevcut
/// DockedPlacesTests'in kapsamadığı kenarlar.
private func dest(_ screen: String, _ desktop: Int = 1, _ layout: WindowLayout = .full,
                  name: String? = nil) -> Destination {
    Destination(screen: screen, desktop: desktop, layout: layout, nameID: name)
}

private func info(_ id: String, uuid: String? = nil, name: String? = nil) -> ScreenInfo {
    ScreenInfo(id: id, uuid: uuid ?? id.uppercased(), name: name ?? id, isBuiltin: id == "builtin",
               frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
               visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050))
}

// MARK: - Saf çözümleme

struct CampaignResolveTests {

    private let all = ["builtin", "external", "external-2", "external-3", "external-4"]

    @Test func firstConnectedPlaceWinsOverLaterOnes() {
        let r = Routing.resolvePlace([dest("external-2", 1), dest("external", 2), dest("external-3", 3)],
                                     connected: all, held: [])
        #expect(r?.choice == .place(0))
        #expect(r?.destination.screen == "external-2")
    }

    @Test func listOrderBeatsRoleOrder() {
        // Liste sırası (priorities) rol sırasından önce gelir.
        let r = Routing.resolvePlace([dest("external-3", 1), dest("external", 1)],
                                     connected: all, held: [])
        #expect(r?.choice == .place(0))
        #expect(r?.destination.screen == "external-3")
    }

    @Test func disconnectedFirstFallsToSecondWithItsOwnDesktopAndLayout() {
        let r = Routing.resolvePlace([dest("external-4", 1, .leftHalf), dest("external-2", 5, .rightHalf)],
                                     connected: ["builtin", "external", "external-2"], held: [])
        #expect(r?.choice == .place(1))
        #expect(r?.destination == dest("external-2", 5, .rightHalf))
    }

    @Test func heldRoleIsSkippedLikeDisconnected() {
        let r = Routing.resolvePlace([dest("external-2", 1), dest("external", 2)],
                                     connected: all, held: ["external-2"])
        #expect(r?.choice == .place(1))
        #expect(r?.destination.screen == "external")
    }

    @Test func k4_fallbackTakesLowestUsableExternalRoleNotNumericListOrder() {
        // external held, external-3 ve external-2 bağlı: rol sırasında external-2.
        let r = Routing.resolvePlace([dest("external-4", 3, .leftHalf)],
                                     connected: ["builtin", "external-3", "external-2", "external"],
                                     held: ["external"])
        #expect(r?.choice == .fallback)
        #expect(r?.destination == dest("external-2", 3, .leftHalf))
    }

    @Test func k4_fallbackUsesFirstPlacesDesktopAndLayoutNotTheLaterOnes() {
        let r = Routing.resolvePlace([dest("external-3", 2, .topHalf), dest("external-4", 7, .full)],
                                     connected: ["builtin", "external"], held: [])
        #expect(r?.choice == .fallback)
        #expect(r?.destination == dest("external", 2, .topHalf))
    }

    @Test func k4_fallbackNeverPicksTheBuiltinScreen() {
        #expect(Routing.resolvePlace([dest("external-2")], connected: ["builtin"], held: []) == nil)
    }

    @Test func d2_4_everyConnectedExternalHeldMeansNil() {
        #expect(Routing.resolvePlace([dest("external"), dest("external-2")],
                                     connected: ["builtin", "external", "external-2"],
                                     held: ["external", "external-2"]) == nil)
    }

    @Test func builtinPlaceInTheDockedListIsAnOrdinaryPlace() {
        let r = Routing.resolvePlace([dest("external-2"), dest("builtin", 2)],
                                     connected: ["builtin", "external"], held: [])
        #expect(r?.choice == .place(1))
        #expect(r?.destination.screen == "builtin")
    }

    // MARK: Adlı hedefler

    @Test func nameOnConnectedUsableScreenResolvesToItsLiveSpot() {
        let r = Routing.resolvePlace([dest("external-2", 1, name: "N1"), dest("external", 2)],
                                     connected: all, held: []) { _ in ("external-3", 4) }
        #expect(r?.choice == .place(0))
        #expect(r?.destination == dest("external-3", 4, name: "N1"))
    }

    @Test func nameOnHeldScreenIsSkipped() {
        let r = Routing.resolvePlace([dest("external-2", 1, name: "N1"), dest("external", 2)],
                                     connected: all, held: ["external-3"]) { _ in ("external-3", 1) }
        #expect(r?.choice == .place(1))
        #expect(r?.destination == dest("external", 2))
    }

    @Test func nameOnDisconnectedScreenIsSkipped() {
        let r = Routing.resolvePlace([dest("external-2", 1, name: "N1"), dest("external", 2)],
                                     connected: ["builtin", "external"], held: []) { _ in ("external-4", 1) }
        #expect(r?.choice == .place(1))
    }

    @Test func nameKnownButAwayFallsBackToExternalWithTheNamePlacesDesktop() {
        // Ad biliniyor ama bağlı olmayan ekranda: yerleşmemiş sayılmaz, K4 yedeği çalışır.
        let r = Routing.resolvePlace([dest("external-2", 6, name: "N1")],
                                     connected: ["builtin", "external-3"], held: []) { _ in ("external-4", 1) }
        #expect(r?.choice == .fallback)
        #expect(r?.destination == dest("external-3", 6))
    }

    @Test func unplacedNameDoesNotBlockLaterConnectedPlace() {
        let r = Routing.resolvePlace([dest("external-2", 1, name: "N1"), dest("external", 2)],
                                     connected: ["builtin", "external"], held: []) { _ in nil }
        #expect(r?.choice == .place(1))
    }

    @Test func unplacedNameBlocksFallbackEvenWithManyExternalsConnected() {
        let r = Routing.resolvePlace([dest("external-4", 1), dest("external-2", 1, name: "N1")],
                                     connected: all, held: [], namePlace: { _ in nil })
        // external-4 bağlı: ilk plain yer kazanır; ad ona gelmez.
        #expect(r?.choice == .place(0))
        let blocked = Routing.resolvePlace([dest("external-9", 1), dest("external-2", 1, name: "N1")],
                                           connected: all, held: []) { _ in nil }
        #expect(blocked == nil)
    }

    @Test func holdNamesHoldsWhenANameComesBeforeAnyConnectedPlace() {
        let r = Routing.resolvePlace([dest("external-9", 1), dest("external-2", 1, name: "N1"), dest("external")],
                                     connected: all, held: [], holdNames: true) { _ in ("external-2", 1) }
        #expect(r == nil)
    }

    @Test func holdNamesDoesNotHoldWhenAPlainConnectedPlaceComesFirst() {
        let r = Routing.resolvePlace([dest("external"), dest("external-2", 1, name: "N1")],
                                     connected: all, held: [], holdNames: true) { _ in nil }
        #expect(r?.choice == .place(0))
    }

    // MARK: Router.resolvePlaces ve harici ekran sayısı

    @Test func fourExternalsOnlyTheLastListedOneConnected() {
        let places = [dest("external", 1), dest("external-2", 2), dest("external-3", 3), dest("external-4", 4)]
        let screens = [info("builtin"), info("external-4")]
        let r = Router.resolvePlaces(places, nameSpaces: [:], holdNames: false, displays: [], screens: screens)
        #expect(r?.choice == .place(3))
        #expect(r?.destination.desktop == 4)
    }

    @Test func fourExternalsWithTwoHeldFallbackIsLowestUsable() {
        let screens = ["builtin", "external", "external-2", "external-3", "external-4"].map { info($0) }
        let r = Router.resolvePlaces([dest("external-9", 2)], nameSpaces: [:], holdNames: false, displays: [],
                                     screens: screens, heldRoles: ["external", "external-2"])
        #expect(r?.choice == .fallback)
        #expect(r?.destination.screen == "external-3")
    }

    @Test func clamshellExternalsOnlyWithoutBuiltinStillResolves() {
        let screens = [info("external"), info("external-2")]
        let r = Router.resolvePlaces([dest("external-3", 1), dest("external-2", 2)],
                                     nameSpaces: [:], holdNames: false, displays: [], screens: screens)
        #expect(r?.choice == .place(1))
        let fallback = Router.resolvePlaces([dest("external-3", 5)], nameSpaces: [:], holdNames: false,
                                            displays: [], screens: screens)
        #expect(fallback?.choice == .fallback)
        #expect(fallback?.destination.screen == "external")
        #expect(ScreenService.mode(of: screens) == .docked)
    }

    @Test func namedPlaceUsesLiveSpaceOfTheNameThroughDisplaySpaces() {
        let space = SkyLight.Space(id: 77, type: 0)
        let other = SkyLight.Space(id: 78, type: 0)
        let displays = [SkyLight.DisplaySpaces(displayUUID: "EXTERNAL-3", current: 78, spaces: [other, space])]
        let screens = [info("builtin"), info("external-3")]
        let r = Router.resolvePlaces([dest("external", 1, name: "N"), dest("builtin", 1)],
                                     nameSpaces: ["N": 77], holdNames: false, displays: displays, screens: screens)
        #expect(r?.choice == .place(0))
        #expect(r?.destination.screen == "external-3")
        #expect(r?.destination.desktop == 2)
        // Space hiçbir ekranda yoksa ad yerleşmemiş: sıradaki yer.
        let missing = Router.resolvePlaces([dest("external", 1, name: "N"), dest("builtin", 1)],
                                           nameSpaces: ["N": 999], holdNames: false, displays: displays,
                                           screens: screens)
        #expect(missing?.choice == .place(1))
    }

    // MARK: Harita ile tarama aynı listeyi görür

    @Test func mapWinnerEqualsSweepResolutionForEverySubsetOfFourExternals() {
        let rule = Rule(id: "r", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                        docked: dest("external-3", 2, .leftHalf),
                        dockedNext: [dest("external", 1), dest("external-4", 3, .rightHalf), dest("builtin", 1)])
        let roles = ["external", "external-2", "external-3", "external-4"]
        for mask in 0..<(1 << roles.count) {
            for heldMask in 0..<(1 << roles.count) {
                let connected = roles.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
                let held = Set(roles.enumerated().filter { heldMask & (1 << $0.offset) != 0 }.map(\.element))
                    .intersection(connected)
                let screens = (["builtin"] + connected).map { info($0) }
                let sweep = Router.resolvePlaces(rule.places(.docked), nameSpaces: [:], holdNames: false,
                                                 displays: [], screens: screens, heldRoles: held)
                let usable = Set(screens.map(\.id)).subtracting(held)
                let map = MapPlaces.winner(rule, mode: .docked, live: true, usable: usable)
                #expect(sweep == map, "connected=\(connected) held=\(held.sorted())")
            }
        }
    }

}

// MARK: - Neden burada? ve status.json

struct CampaignReasonStatusTests {

    private let rule = Rule(id: "r", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                            docked: dest("external-2", 1),
                            dockedNext: [dest("external", 2), dest("external-3", 3)])

    private var match: Routing.Match { Routing.Match(destination: rule.docked!, ruleID: rule.id, rule: rule) }

    @Test func reasonNamesFirstPlaceOfThreeWhenFirstWins() {
        let r = Routing.ResolvedPlace(destination: dest("external-2", 1), choice: .place(0))
        let text = Routing.reason(for: match, screenName: "LG", resolved: r) ?? ""
        #expect(text.contains(L("place %ld of %ld in its list", 1, 3)))
    }

    @Test func reasonCountsAllPlacesNotJustTheConnectedOnes() {
        let r = Routing.ResolvedPlace(destination: dest("external-3", 3), choice: .place(2))
        let text = Routing.reason(for: match, screenName: "Samsung", resolved: r) ?? ""
        #expect(text.contains(L("place %ld of %ld in its list", 3, 3)))
        #expect(text.contains(L("%@ · Desktop %ld", DisplayRoles.displayName(role: "external-3", name: "Samsung"), 3)))
    }

    @Test func reasonTargetIsTheResolvedPlaceNotTheRulesFirstPlace() {
        let r = Routing.ResolvedPlace(destination: dest("external", 2), choice: .place(1))
        let text = Routing.reason(for: match, screenName: "Dell", resolved: r) ?? ""
        #expect(text.contains(DisplayRoles.displayName(role: "external", name: "Dell")))
        #expect(!text.contains(DisplayRoles.displayName(role: "external-2", name: "Dell")))
    }

    @Test func reasonFallbackNoteAppearsEvenForSinglePlacePin() {
        let single = Rule(id: "s", appName: "Mail", bundleID: "com.apple.mail", tokens: [],
                          docked: dest("external", 3))
        let m = Routing.Match(destination: single.docked!, ruleID: single.id, rule: single)
        let r = Routing.ResolvedPlace(destination: dest("external-2", 3), choice: .fallback)
        let text = Routing.reason(for: m, screenName: "LG", resolved: r) ?? ""
        #expect(text.contains(L("fallback: none of its monitors is connected")))
    }

    @Test func reasonWithFallbackDoesNotAlsoSayPlaceN() {
        let r = Routing.ResolvedPlace(destination: dest("external", 1), choice: .fallback)
        let text = Routing.reason(for: match, screenName: "Dell", resolved: r) ?? ""
        #expect(text.contains(L("fallback: none of its monitors is connected")))
        #expect(!text.contains(L("place %ld of %ld in its list", 1, 3)))
    }

    @Test func reasonOfSessionPinIgnoresPlaceAndFallbackNotes() {
        let pin = Routing.Match(destination: dest("external", 2), ruleID: Routing.sessionRuleID, rule: nil)
        let r = Routing.ResolvedPlace(destination: dest("external", 2), choice: .fallback)
        let text = Routing.reason(for: pin, screenName: "Dell", resolved: r) ?? ""
        #expect(text.contains("temporary pin"))
        #expect(!text.contains(L("fallback: none of its monitors is connected")))
    }

    @Test func placeStatusTenthPlaceIsTenNotAnIndex() {
        #expect(Router.placeStatus(choices: [1: .place(9)], unplaced: []) == [1: "10"])
    }

    @Test func placeStatusChoiceWinsOverUnplacedFlag() {
        #expect(Router.placeStatus(choices: [1: .fallback], unplaced: [1]) == [1: "fallback"])
    }

}

// MARK: - Masa üzerinde: K1, D2.4, oturum pinleri, bağ

@MainActor
struct CampaignDeskTests {

    @Test func k1_laptopOnlyWindowIsUntouchedWhileMonitorsAreConnected() {
        let desk = MultiMonitorDesk()
        desk.connect(["Dell"])
        #expect(desk.screens.mode == .docked)
        #expect(desk.resolved("music") == nil)
        // Ve laptop yeri pencerenin kendi yeridir: kapatınca geri döner.
        desk.connect([])
        #expect(desk.place("music") == "Laptop · 3")
    }

    @Test func d2_4_twoNewMonitorsHeldTouchesNothingAndMarksAllUntouched() {
        let desk = MultiMonitorDesk()
        desk.monitors["BenQ"] = MultiMonitorDesk.external("BENQ", "BenQ", x: 3630)
        desk.monitors["Acme"] = MultiMonitorDesk.external("ACME", "Acme", x: 5550)
        desk.connect(["Dell"])
        desk.connect(["Dell", "BenQ", "Acme"])
        #expect(desk.screens.heldRoles.count == 2)
        desk.connect(["BenQ", "Acme"])
        #expect(desk.screens.mode == .docked)
        let unplaced = Set(MultiMonitorDesk.rules.compactMap { rule in
            desk.resolved(rule.id) == nil ? rule.id : nil
        })
        #expect(unplaced == ["safari", "mail", "notes", "music"])
        let status = Router.placeStatus(choices: [:], unplaced: [1, 2, 3, 4])
        #expect(Set(status.values) == ["untouched"])
    }

    @Test func d2_4_oneHeldOneKnownMonitorUsesTheKnownOneAsFallback() {
        let desk = MultiMonitorDesk()
        desk.monitors["BenQ"] = MultiMonitorDesk.external("BENQ", "BenQ", x: 3630)
        desk.connect(["Dell"])
        desk.connect(["Dell", "BenQ"])
        desk.connect(["BenQ", "LG"])
        // LG kayıtlı (external-2), BenQ yeni ve onay bekliyor.
        #expect(desk.place("safari") == "LG · 1")
        #expect(desk.place("mail") == "LG · 3")
        #expect(desk.resolved("mail")?.choice == .fallback)
    }

    @Test func fourExternalsEveryPinFollowsTheLowestRoleThatIsConnectedForFallback() {
        let desk = MultiMonitorDesk()
        desk.monitors["BenQ"] = MultiMonitorDesk.external("BENQ", "BenQ", x: 7470)
        desk.connect(["Dell", "LG", "Samsung", "BenQ"])
        desk.choose("BenQ", for: "external-4")
        #expect(desk.role(of: "BenQ") == "external-4")
        desk.connect(["BenQ", "Samsung"])
        // Dell ve LG yok: notes kendi yeri Samsung, mail yedekte rol sırasındaki ilk bağlı: Samsung (external-3).
        #expect(desk.place("notes") == "Samsung · 2")
        #expect(desk.resolved("mail")?.destination.screen == "external-3")
        #expect(desk.resolved("mail")?.choice == .fallback)
        #expect(desk.resolved("safari")?.choice == .fallback)
    }

    @Test func sessionPinToConnectedScreenIgnoresTheRulesOwnList() {
        let pin = dest("builtin", 4)
        let resolved = Routing.resolve(rules: MultiMonitorDesk.rules, sessionPins: [1: pin], mode: .docked,
                                       windowID: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "x")
        #expect(resolved.match?.rule == nil)
        let r = Router.resolvePlaces(resolved.match.map { [$0.destination] } ?? [], nameSpaces: [:],
                                     holdNames: false, displays: [],
                                     screens: [info("builtin"), info("external")])
        #expect(r?.destination == pin)
        #expect(r?.choice == .place(0))
    }

    @Test func sessionPinToMissingMonitorTakesTheKFourFallbackWithPinsDesktop() {
        let pin = dest("external-3", 2, .rightHalf)
        let r = Router.resolvePlaces([pin], nameSpaces: [:], holdNames: false, displays: [],
                                     screens: [info("builtin"), info("external")])
        #expect(r?.choice == .fallback)
        #expect(r?.destination == dest("external", 2, .rightHalf))
    }

    @Test func sessionPinRemovedReturnsToTheRulesListViaResolve() {
        let rules = MultiMonitorDesk.rules
        let with = Routing.resolve(rules: rules, sessionPins: [1: dest("builtin")], mode: .docked, windowID: 1,
                                   bundleID: "com.apple.Safari", appName: "Safari", title: "x")
        #expect(with.match?.ruleID == Routing.sessionRuleID)
        let without = Routing.resolve(rules: rules, sessionPins: [:], mode: .docked, windowID: 1,
                                      bundleID: "com.apple.Safari", appName: "Safari", title: "x")
        #expect(without.match?.ruleID == "safari")
        #expect(without.match?.rule?.places(.docked).count == 2)
    }

    @Test func bindingFollowsInPlaceReorderOfTheListAndKeepsTheSameRule() {
        let rule = Rule(id: "app", appName: "Claude", bundleID: "com.anthropic.claudefordesktop", tokens: [],
                        docked: dest("external", 1), undocked: dest("builtin", 1),
                        dockedNext: [dest("external-2", 2)])
        let h = RouterHarness(rules: [rule])
        h.titles = [1: "Draft"]
        let first = h.router.sweepSelection(windows: h.windows, now: h.now)[1]
        #expect(first?.rule?.places(.docked).map(\.screen) == ["external", "external-2"])
        let bound = h.bindings[1]
        // Liste yerinde sıra değiştirir: bağ aynı kalmalı, yeni sıra görülmeli.
        var edited = h.rules[0]
        edited.setPlaces([dest("external-2", 2), dest("external", 1)], mode: .docked)
        h.rules = [edited]
        let second = h.router.sweepSelection(windows: h.windows, now: h.now)[1]
        #expect(second?.ruleID == "app")
        #expect(second?.rule?.places(.docked).map(\.screen) == ["external-2", "external"])
        #expect(h.bindings[1] == bound)
    }

    @Test func bindingAfterRemovingTheLastDockedPlaceKeepsTheWindowWhereItIs() {
        let rule = Rule(id: "app", appName: "Claude", bundleID: "com.anthropic.claudefordesktop", tokens: [],
                        docked: dest("external", 1), undocked: dest("builtin", 1))
        let h = RouterHarness(rules: [rule])
        h.titles = [1: "Draft"]
        #expect(h.sweepRules()[1] == .some("app"))
        var edited = h.rules[0]
        edited.setPlaces([], mode: .docked)
        h.rules = [edited]
        // Monitörlü modda hedefi kalmayan kural eşleşmez; pencere dokunulmadan kalır.
        #expect(h.sweep()[1] == .some(nil))
    }

}
