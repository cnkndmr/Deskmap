import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya (ui): haritanın saf kararları (MapPlaces), K6 düğmelerinin
/// koşulu, yeni metinlerin Türkçesi ve demo senaryoları.
/// Sözleşme: docs/bug-tables.md §D, design/coklu-monitor/Tablo-D.md.
@MainActor
struct CampaignUiTests {

    // MARK: - Kurulum

    private func known(_ id: String, _ name: String = "Acme") -> KnownScreen {
        KnownScreen(id: id, name: name, aspect: 1.6)
    }

    private let builtin = KnownScreen(id: "builtin", name: "Laptop", aspect: 1.6)

    private func rule(_ id: String, _ app: String, tokens: [String] = [],
                      _ places: [Destination]) -> Rule {
        Rule(id: id, appName: app, bundleID: "test.\(id)", tokens: tokens,
             docked: places.first, dockedNext: Array(places.dropFirst()))
    }

    private func place(_ screen: String, _ desktop: Int = 1) -> Destination {
        Destination(screen: screen, desktop: desktop)
    }

    // MARK: - Kart sırası (K8)

    @Test func k8_builtinStaysOnTopEvenIfNotListedAsConnected() {
        let rows = MapPlaces.cardRows([known("external"), builtin], connected: [], live: true)
        #expect(rows.main.map(\.id) == ["builtin"])
        #expect(rows.away.map(\.id) == ["external"])
    }

    @Test func k8_connectedKeepTheirOriginalOrderAndAwayKeepTheirs() {
        let screens = [known("external-3"), known("external"), builtin, known("external-2"), known("external-4")]
        let rows = MapPlaces.cardRows(screens, connected: ["external", "external-4"], live: true)
        #expect(rows.main.map(\.id) == ["external", "builtin", "external-4"])
        #expect(rows.away.map(\.id) == ["external-3", "external-2"])
    }

    @Test func k8_otherPlanNeverSplitsCardsEvenWhenNothingIsConnected() {
        let screens = [known("external"), builtin, known("external-2")]
        let rows = MapPlaces.cardRows(screens, connected: [], live: false)
        #expect(rows.main.map(\.id) == ["external", "builtin", "external-2"])
        #expect(rows.away.isEmpty)
    }

    @Test func k8_everythingConnectedLeavesNoAwayCard() {
        let rows = MapPlaces.cardRows([builtin, known("external")], connected: ["builtin", "external"], live: true)
        #expect(rows.away.isEmpty)
    }

    // MARK: - Soluk kartlar (monitör kimliğinden)

    @Test func k8_awayCardHidesWhenUUIDIsConnectedWithBracesAndLowercase() {
        let roles = DisplayRoles(remembered: ["external": ["AAAA-1111"]])
        let cards = MapPlaces.awayCards(known: [builtin, known("external")],
                                        monitors: roles.knownMonitors(connected: []),
                                        connectedUUIDs: ["{aaaa-1111}"], connectedRoles: ["builtin"],
                                        names: [:])
        #expect(cards.isEmpty)
    }

    @Test func k8_awayCardsAreOrderedByRoleNotByInputOrder() {
        let monitors: [(role: String, uuid: String)] = [("external-3", "C"), ("external", "A"), ("external-2", "B")]
        let screens = ["external", "external-2", "external-3"].map { known($0) }
        let cards = MapPlaces.awayCards(known: screens, monitors: monitors, connectedUUIDs: [],
                                        connectedRoles: ["builtin"], names: [:])
        #expect(cards.map(\.screen.id) == ["external", "external-2", "external-3"])
        #expect(cards.map(\.id) == ["A", "B", "C"])
    }

    @Test func k8_awayCardNameComesFromMonitorNamesThenKnownScreenThenRoleLabel() {
        let monitors: [(role: String, uuid: String)] = [("external", "{aa}"), ("external-2", "BB"), ("external-3", "CC")]
        let cards = MapPlaces.awayCards(
            known: [known("external", "Stored"), known("external-2", "Stored 2")],
            monitors: monitors, connectedUUIDs: [], connectedRoles: [],
            names: ["AA": "Acme 27Q"])
        #expect(cards[0].screen.name == "Acme 27Q")           // normalleşmiş anahtar
        #expect(cards[1].screen.name == "Stored 2")           // kayıtlı ekran adı
        #expect(cards[2].screen.name == DisplayRoles.roleLabel("external-3"))   // hiç kayıt yok
        #expect(cards[2].screen.id == "external-3")
    }

    @Test func k8_cardOfAMonitorWhoseRoleIsHeldByAnotherDoesNotAcceptDrops() {
        let cards = MapPlaces.awayCards(known: [known("external")],
                                        monitors: [("external", "OLD")],
                                        connectedUUIDs: ["NEW"], connectedRoles: ["external"], names: [:])
        #expect(cards.count == 1)
        #expect(cards[0].sharesRole)    // ScreenCard.acceptsDrops = !sharesRole
        #expect(cards[0].uuid == "OLD")
    }

    @Test func k8_plainAwayCardAcceptsDrops() {
        let cards = MapPlaces.awayCards(known: [known("external")], monitors: [("external", "OLD")],
                                        connectedUUIDs: [], connectedRoles: ["builtin"], names: [:])
        #expect(!cards[0].sharesRole)
    }

    @Test func k8_legacyRoleCardOnlyWhenNoMonitorRemembersItAndRoleIsFree() {
        let screens = [builtin, known("external"), known("external-2"), known("external-3")]
        let cards = MapPlaces.awayCards(known: screens, monitors: [("external", "A")],
                                        connectedUUIDs: [], connectedRoles: ["builtin", "external-2"],
                                        names: [:])
        // external: monitörü hatırlanıyor (kimlikli kart); external-2: rol takılı;
        // external-3: serbest eski rol kartı; builtin hiç kart olmaz.
        #expect(cards.map(\.screen.id) == ["external", "external-3"])
        #expect(cards[0].uuid == "A")
        #expect(cards[1].uuid == nil)
        #expect(cards[1].id == "external-3")
    }

    @Test func k8_builtinNeverBecomesAnAwayCard() {
        let cards = MapPlaces.awayCards(known: [builtin], monitors: [], connectedUUIDs: [],
                                        connectedRoles: [], names: [:])
        #expect(cards.isEmpty)
    }

    @Test func k8_oneCardPerRoleEvenWithMonitorHistory() {
        let roles = DisplayRoles(remembered: ["external": ["NEW", "OLDER"]])
        let cards = MapPlaces.awayCards(known: [known("external")],
                                        monitors: roles.knownMonitors(connected: []),
                                        connectedUUIDs: [], connectedRoles: [], names: [:])
        #expect(cards.map(\.id) == ["NEW"])
    }

    // MARK: - Masaüstü sayısı kaynağı

    @Test func k8_desktopCountPrefersPlanThenLastSeenThenOne() {
        #expect(MapPlaces.awayDesktopCount(planned: 3, lastSeen: 5, used: 0) == 3)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: 5, used: 0) == 5)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: nil, used: 0) == 1)
    }

    @Test func k8_desktopCountGrowsToTheBiggestPinnedDesktopButNeverShrinksBelowPlan() {
        #expect(MapPlaces.awayDesktopCount(planned: 2, lastSeen: nil, used: 6) == 6)
        #expect(MapPlaces.awayDesktopCount(planned: 4, lastSeen: nil, used: 2) == 4)
        #expect(MapPlaces.awayDesktopCount(planned: 0, lastSeen: 0, used: 0) == 1)
        #expect(MapPlaces.awayDesktopCount(planned: -2, lastSeen: nil, used: 0) == 1)
    }

    // MARK: - Kazanan ve kapalı pin çipleri

    @Test func winner_ruleWithoutPlacesHasNoWinner() {
        let none = Rule(id: "x", appName: "X", bundleID: "x", tokens: [], undocked: place("builtin"))
        #expect(MapPlaces.winner(none, mode: .docked, live: true, usable: ["builtin", "external"]) == nil)
        #expect(MapPlaces.winner(none, mode: .docked, live: false, usable: []) == nil)
    }

    @Test func winner_fallbackNeedsAnExternalMonitor() {
        let r = rule("a", "A", [place("external-2", 3)])
        #expect(MapPlaces.winner(r, mode: .docked, live: true, usable: ["builtin"]) == nil)
    }

    @Test func winner_fallbackPicksLowestExternalAndKeepsFirstPlacesDesktop() {
        var first = place("external-3", 4)
        first.layout = .leftHalf
        let r = rule("a", "A", [first, place("external-2", 2)])
        let won = MapPlaces.winner(r, mode: .docked, live: true, usable: ["builtin", "external-4", "external"])
        #expect(won?.choice == .fallback)
        #expect(won?.destination.screen == "external")
        #expect(won?.destination.desktop == 4)
        #expect(won?.destination.layout == .leftHalf)
    }

    @Test func winner_firstConnectedPlaceInListOrderWinsOverLaterOnes() {
        let r = rule("a", "A", [place("external-3", 1), place("external", 2), place("external-2", 3)])
        let won = MapPlaces.winner(r, mode: .docked, live: true, usable: ["builtin", "external", "external-2"])
        #expect(won?.choice == .place(1))
        #expect(won?.destination == place("external", 2))
    }

    @Test func winner_laptopModeUsesTheUndockedPlace() {
        let r = Rule(id: "m", appName: "M", bundleID: "m", tokens: [],
                     docked: place("external"), undocked: place("builtin", 2))
        #expect(MapPlaces.winner(r, mode: .undocked, live: true, usable: ["builtin"])?.destination
            == place("builtin", 2))
        #expect(MapPlaces.winner(r, mode: .undocked, live: false, usable: [])?.choice == .place(0))
    }

    @Test func pinned_fallbackPinShowsAtTheFallbackScreenAndNotAtItsOwnPlace() {
        let r = rule("n", "N", [place("external-3", 2)])
        let usable: Set<String> = ["builtin", "external"]
        #expect(MapPlaces.pinned([r], mode: .docked, live: true, usable: usable, screen: "external", desktop: 2).count == 1)
        #expect(MapPlaces.pinned([r], mode: .docked, live: true, usable: usable, screen: "external-3", desktop: 2).isEmpty)
    }

    @Test func pinned_otherPlanAlwaysUsesTheFirstPlaceRegardlessOfConnection() {
        let r = rule("n", "N", [place("external-2", 1), place("external", 1)])
        #expect(MapPlaces.pinned([r], mode: .docked, live: false, usable: ["external"],
                                 screen: "external-2", desktop: 1).count == 1)
        #expect(MapPlaces.pinned([r], mode: .docked, live: false, usable: ["external"],
                                 screen: "external", desktop: 1).isEmpty)
    }

    @Test func pinned_keepsRuleOrderWhenSeveralPinsShareADesktop() {
        let rules = [rule("b", "B", [place("external")]), rule("a", "A", [place("external")]),
                     rule("c", "C", [place("external", 2)])]
        let list = MapPlaces.pinned(rules, mode: .docked, live: true, usable: ["external"],
                                    screen: "external", desktop: 1)
        #expect(list.map(\.id) == ["b", "a"])
    }

    // MARK: - Hayalet çipler

    @Test func ghost_orderNumbersFollowTheListNotTheCardAndLabelUsesTitleForTokenRules() {
        let r = rule("w", "Docs", tokens: ["Plan", "Atlas"],
                     [place("external-3", 1), place("external", 1), place("external-2", 5)])
        let usable: Set<String> = ["builtin", "external"]
        let atThird = MapPlaces.ghosts([r], mode: .docked, live: true, usable: usable, connected: usable,
                                       screen: "external-2", desktop: 5)
        #expect(atThird.map(\.label) == ["3 · Plan · Atlas"])
        let atFirst = MapPlaces.ghosts([r], mode: .docked, live: true, usable: usable, connected: usable,
                                       screen: "external-3", desktop: 1)
        #expect(atFirst.map(\.order) == [1])
    }

    @Test func ghost_appWideRuleLabelUsesAppName() {
        let r = rule("w", "Notes", [place("external-2", 1), place("external", 1)])
        let g = MapPlaces.ghosts([r], mode: .docked, live: true, usable: ["external"], connected: ["external"],
                                 screen: "external-2", desktop: 1)
        #expect(g.map(\.label) == ["1 · Notes"])
        #expect(g.map(\.id) == ["w#1"])
    }

    @Test func ghost_twoUnusedPlacesOnTheSameCardGetDistinctOrdersAndIDs() {
        let r = rule("w", "Docs", [place("external-2", 1), place("external-2", 1), place("external", 1)])
        let g = MapPlaces.ghosts([r], mode: .docked, live: true, usable: ["external"], connected: ["external"],
                                 screen: "external-2", desktop: 1)
        #expect(g.map(\.order) == [1, 2])
        #expect(Set(g.map(\.id)).count == 2)
    }

    @Test func ghost_singlePlacePinAppearsOnAnAwayCardInLivePlanButNotInOtherPlan() {
        let r = rule("w", "Docs", [place("external-2", 1)])
        #expect(MapPlaces.ghosts([r], mode: .docked, live: true, usable: ["external"], connected: ["external"],
                                 screen: "external-2", desktop: 1).map(\.label) == ["1 · Docs"])
        #expect(MapPlaces.ghosts([r], mode: .docked, live: false, usable: [], connected: [],
                                 screen: "external-2", desktop: 1).isEmpty)
    }

    @Test func ghost_noneOnConnectedCardEvenWhenTheRoleIsHeld() {
        // Rol takılı ama onay bekliyor: usable'da yok, connected'ta var.
        let r = rule("w", "Docs", [place("external-2", 1), place("external", 1)])
        #expect(MapPlaces.ghosts([r], mode: .docked, live: true, usable: ["external"],
                                 connected: ["external", "external-2"],
                                 screen: "external-2", desktop: 1).isEmpty)
        // Aynı rol öbür planda (live false) gösterilir: orada bağlantı sorulmaz.
        #expect(MapPlaces.ghosts([r], mode: .docked, live: false, usable: [],
                                 connected: ["external-2"], screen: "external-2", desktop: 1).isEmpty)
    }

    @Test func ghost_otherPlanShowsTheLaterPlacesButNotTheFirst() {
        let r = rule("w", "Docs", [place("external-2", 1), place("external", 1), place("external-3", 1)])
        func labels(_ screen: String) -> [String] {
            MapPlaces.ghosts([r], mode: .docked, live: false, usable: [], connected: [],
                             screen: screen, desktop: 1).map(\.label)
        }
        #expect(labels("external-2").isEmpty)
        #expect(labels("external") == ["2 · Docs"])
        #expect(labels("external-3") == ["3 · Docs"])
    }

    @Test func ghost_wrongDesktopOrLaptopModeGivesNothing() {
        let r = rule("w", "Docs", [place("external-2", 1), place("external", 1)])
        #expect(MapPlaces.ghosts([r], mode: .docked, live: true, usable: ["external"], connected: ["external"],
                                 screen: "external-2", desktop: 2).isEmpty)
        #expect(MapPlaces.ghosts([r], mode: .undocked, live: true, usable: ["external"], connected: ["external"],
                                 screen: "external-2", desktop: 1).isEmpty)
    }

    // MARK: - Yan panel satırları

    @Test func inspector_ruleWithoutDockedPlacesHasNoRowsAndNoFallback() {
        let r = Rule(id: "m", appName: "M", bundleID: "m", tokens: [], undocked: place("builtin"))
        let res = MapPlaces.rows(r, live: true, usable: ["builtin", "external"])
        #expect(res.rows.isEmpty)
        #expect(res.fallback == nil)
    }

    @Test func inspector_onlyTheWinnerRowWinsAndEarlierDisconnectedRowsStayPlain() {
        let r = rule("w", "Docs", [place("external-3"), place("external", 2), place("external-2", 3)])
        let res = MapPlaces.rows(r, live: true, usable: ["builtin", "external", "external-2"])
        #expect(res.rows.map(\.wins) == [false, true, false])
        #expect(res.rows.map(\.connected) == [false, true, true])
        #expect(res.rows.map(\.index) == [0, 1, 2])
        #expect(res.rows.map(\.id) == [0, 1, 2])
    }

    @Test func inspector_fallbackNoteComesWithNoWinningRowAndNoConnectedRow() {
        let r = rule("w", "Docs", [place("external-3", 4), place("external-4", 1)])
        let res = MapPlaces.rows(r, live: true, usable: ["builtin", "external-2"])
        #expect(res.rows.allSatisfy { !$0.wins && !$0.connected })
        #expect(res.fallback?.destination == Destination(screen: "external-2", desktop: 4))
    }

    @Test func inspector_noFallbackNoteInOtherPlanOrWhenAWinnerExists() {
        let r = rule("w", "Docs", [place("external-3")])
        #expect(MapPlaces.rows(r, live: false, usable: ["external"]).fallback == nil)
        let ok = rule("w", "Docs", [place("external")])
        #expect(MapPlaces.rows(ok, live: true, usable: ["external"]).fallback == nil)
    }

    @Test func inspector_heldMonitorIsNotConnectedForRows() {
        // Onay bekleyen rol usable'a girmez: satır bağlı sayılmaz, yedek devreye girer.
        let r = rule("w", "Docs", [place("external-2", 1)])
        let res = MapPlaces.rows(r, live: true, usable: ["builtin", "external"])
        #expect(res.rows.map(\.connected) == [false])
        #expect(res.fallback?.destination.screen == "external")
    }

    // MARK: - K6 düğmeleri

    @Test func k6_replaceMenuHasNoEntryWhenDeskmapKnowsNoMonitor() {
        // İlk kez bağlanan tek monitör onaylı (learnedOnce yok): kimse "held" değil.
        let fresh = DisplayRoles()
        #expect(fresh.unconfirmed([("external", "NEW")]).isEmpty)
        // Başka bir monitör hatırlanıyor, yenisi onay bekliyor: Replace menüsünde yalnız hatırlanan.
        let roles = DisplayRoles(remembered: ["external": ["HOME"]])
        let pairs: [(role: String, uuid: String)] = [("external", "NEW")]
        #expect(roles.unconfirmed(pairs) == ["external"])
        #expect(roles.knownMonitors(connected: pairs).map(\.uuid) == ["HOME"])
    }

    @Test func k6_addToEndSkipsHeldRoleAndNeverTakesARememberedRole() {
        let roles = DisplayRoles(remembered: ["external": ["HOME"], "external-2": ["LG"]])
        // Üç monitör bağlı, ikisi tanınıyor: yeni monitör external-3'ü ister.
        let pairs: [(role: String, uuid: String)] = [("external", "HOME"), ("external-2", "LG"), ("external-3", "NEW")]
        #expect(roles.nextFreeRole(connected: pairs) == "external-3")
        // Yeni monitör "external" rolünü geçici tutuyorsa yine hatırlanan rol verilmez.
        #expect(roles.nextFreeRole(connected: [("external", "NEW")]) == "external-3")
    }

    @Test func k6_choosableRolesCountConnectedPlusAwayMonitors() {
        let roles = DisplayRoles(remembered: ["external": ["HOME"], "external-2": ["LG"]])
        #expect(roles.choosableRoles(connected: [("external", "NEW")]) == ["external", "external-2", "external-3"])
        #expect(roles.choosableRoles(connected: []) == ["external", "external-2"])
    }

    // MARK: - Yerelleştirme

    private static func trTable() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/tr.lproj/Localizable.strings")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func tr_placeAndAwayCardTextsAreTranslatedAndKeepTheirSpecifiers() throws {
        let table = try Self.trTable()
        let keys = [
            "Not connected · windows go here when the monitor is plugged in",
            "Add to the end", "Replace…", "Replace %@",
            "fallback: none of its monitors is connected",
            "place %ld of %ld in its list", "Places", "in use", "(not connected)", "Move up",
            "Laptop only: no place", "Laptop only: %@",
            "None of these monitors is connected: the window is on %@ for now (fallback).",
        ]
        for key in keys {
            let tr = try #require(table[key], "tr karşılığı yok: \(key)")
            #expect(!tr.isEmpty)
            #expect(tr != key, "çevrilmemiş: \(key)")
            #expect(key.filter { $0 == "%" }.count == tr.filter { $0 == "%" }.count, "belirteç sayısı: \(key)")
        }
    }

    @Test func tr_roleLabelsAreStableInEnglishWithoutBundle() {
        #expect(DisplayRoles.roleLabel("external") == "Extra monitor")
        #expect(DisplayRoles.roleLabel("external-4") == "Monitor 4")
        #expect(DisplayRoles.displayName(role: "builtin", name: "Laptop") == "Laptop")
        #expect(DisplayRoles.displayName(role: "external-2", name: "Dell") == "Monitor 2")
    }

    // MARK: - Demo senaryoları (Shots)

    @Test func shots_awayMonitorWorldDrivesTheAwayCardGhostAndWinner() throws {
        let world = DemoData.awayMonitor()
        let ids = Set(world.screens.map(\.id))
        #expect(ids == ["builtin", "external"])
        let roles = world.document.displayRoles
        let pairs: [(role: String, uuid: String)] = world.screens.filter { !$0.isBuiltin }
            .map { (role: $0.id, uuid: $0.uuid) }
        let cards = MapPlaces.awayCards(known: world.document.screens,
                                        monitors: roles.knownMonitors(connected: pairs),
                                        connectedUUIDs: Set(pairs.map(\.uuid)), connectedRoles: ids,
                                        names: roles.monitorNames)
        #expect(cards.map(\.screen.id) == ["external-2"])
        let away = try #require(cards.first)
        #expect(MapPlaces.awayDesktopCount(planned: 0,
                                           lastSeen: away.uuid.flatMap { roles.lastDesktopCount[$0] },
                                           used: 0) == 2)
        let usable: Set<String> = ["builtin", "external"]
        let mail = try #require(world.document.rules.first { $0.id == DemoData.awayMailRuleID })
        #expect(MapPlaces.winner(mail, mode: .docked, live: true, usable: usable)?.destination.screen == "external")
        let ghosts = MapPlaces.ghosts(world.document.rules, mode: .docked, live: true, usable: usable,
                                      connected: ids, screen: "external-2", desktop: 1)
        #expect(ghosts.contains { $0.rule.id == DemoData.awayMailRuleID && $0.order == 1 })
    }

    @Test func shots_everyScenarioWorldBuildsWithConsistentScreens() {
        let worlds = [("make", DemoData.make()), ("two", DemoData.twoMonitors()),
                      ("away", DemoData.awayMonitor()), ("crowded", DemoData.crowded())]
        for (name, world) in worlds {
            let ids = Set(world.screens.map(\.id))
            #expect(!ids.isEmpty)
            // crowded kendi kural listesini sonradan ayrı düzenler; profil eşliği yalnız öbürlerinde sözleşme.
            if name != "crowded" { #expect(world.document.rules == world.document.activeProfile?.rules, "\(name)") }
            for window in world.windows {
                if let placement = window.placement { #expect(ids.contains(placement.screen)) }
            }
        }
    }

    @Test func shots_scenarioNamesParseForTheNewScenarios() {
        for name in ["away-monitor", "held-monitor", "two-monitors", "crowded", "demo"] {
            #expect(Shots.parseOptions(["Deskmap", "--shots", "/tmp/o", "--scenario", name])?.scenario == name)
        }
    }

    @Test func shots_anchorsDoNotCollideWithEachOtherOrRealWindowIDs() {
        #expect(MapPlaces.awayAnchorID != MapPlaces.mapEndAnchorID)
        #expect(MapPlaces.awayAnchorID == CGWindowID.max)
        #expect(MapPlaces.mapEndAnchorID == CGWindowID.max - 1)
    }
}
