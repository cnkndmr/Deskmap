import Foundation
import Testing
@testable import Deskmap

/// Kampanya: sıralı yer listesi API'si (K3, K7; Tablo D4). Pür `Rule` /
/// `Document` işlemleri ve `Store` üzerinden geri al / yinele. Roller:
/// `external` (Dell), `external-2` (LG), `external-3` (Samsung).
private func spot(_ screen: String, _ desktop: Int = 1, name: String? = nil,
                  layout: WindowLayout = .full) -> Destination {
    Destination(screen: screen, desktop: desktop, layout: layout, nameID: name)
}

private func labels(_ list: [Destination]) -> [String] {
    list.map { "\($0.screen)·\($0.desktop)" }
}

private func rule(_ id: String = "r", docked: [Destination] = [], undocked: Destination? = nil,
                  app: String = "Acme", tokens: [String] = []) -> Rule {
    var rule = Rule(id: id, appName: app, bundleID: "com.acme.\(app)", tokens: tokens,
                    undocked: undocked)
    rule.setPlaces(docked, mode: .docked)
    return rule
}

// MARK: - Rule.place (K7)

struct CampaignRulePlaceTests {

    private let all: Set<String> = ["builtin", "external", "external-2", "external-3"]

    @Test func k7_emptyListGetsASinglePlace() {
        var r = rule()
        r.place(spot("external", 2), mode: .docked, connected: all)
        #expect(labels(r.places(.docked)) == ["external·2"])
        #expect(r.dockedNext.isEmpty)
    }

    @Test func k7_connectedTargetGoesBeforeTheFirstConnectedPlace() {
        // LG ve Dell bağlı değil; Samsung bağlı: Samsung'a bırakınca yeni yer
        // bağlı ilk yerin (Samsung zaten listede yok, bağlı yer yok) sonuna girer.
        var r = rule(docked: [spot("external-2"), spot("external", 2)])
        r.place(spot("external-3", 1), mode: .docked, connected: ["external-3"])
        #expect(labels(r.places(.docked)) == ["external-2·1", "external·2", "external-3·1"])
    }

    @Test func k7_connectedTargetInsertsRightBeforeFirstConnectedPlace() {
        // LG bağlı değil, Dell bağlı; Samsung bağlı. Samsung, Dell'in önüne girer
        // ama bağlı olmayan LG'nin önüne geçmez.
        var r = rule(docked: [spot("external-2"), spot("external", 2)])
        r.place(spot("external-3", 1), mode: .docked, connected: ["external", "external-3"])
        #expect(labels(r.places(.docked)) == ["external-2·1", "external-3·1", "external·2"])
    }

    @Test func k7_disconnectedTargetAlwaysGoesFirst() {
        var r = rule(docked: [spot("external"), spot("external-2")])
        r.place(spot("external-3", 4), mode: .docked, connected: ["external"])
        #expect(labels(r.places(.docked)) == ["external-3·4", "external·1", "external-2·1"])
        #expect(r.docked == spot("external-3", 4))
    }

    @Test func k7_noConnectedPlaceAppendsConnectedTargetAtTheEnd() {
        var r = rule(docked: [spot("external-2"), spot("external-3")])
        r.place(spot("external"), mode: .docked, connected: ["external"])
        #expect(labels(r.places(.docked)) == ["external-2·1", "external-3·1", "external·1"])
    }

    @Test func k7_sameScreenReplacesWithoutDuplicatingAndUsesTheNewDesktop() {
        var r = rule(docked: [spot("external", 1), spot("external-2", 2), spot("external-3", 3)])
        r.place(spot("external-2", 5, layout: .leftHalf), mode: .docked, connected: all)
        // Bağlı ilk yerin (Dell) önüne girer: Dell artık ikinci.
        #expect(labels(r.places(.docked)) == ["external-2·5", "external·1", "external-3·3"])
        #expect(r.places(.docked).filter { $0.screen == "external-2" }.count == 1)
        #expect(r.docked?.layout == .leftHalf)
    }

    @Test func k7_sameScreenOnlyConnectedWithOtherDisconnectedKeepsPriority() {
        // Yalnız Dell bağlıyken Dell içinde sürüklemek LG'nin önceliğini bozmaz.
        var r = rule(docked: [spot("external-2", 1), spot("external", 2)])
        r.place(spot("external", 3), mode: .docked, connected: ["external"])
        #expect(labels(r.places(.docked)) == ["external-2·1", "external·3"])
    }

    @Test func k7_heldRoleCountsAsDisconnected() {
        // `connected`: onay beklemeyen roller. Bekleyen (held) bir rol kümede
        // yoktur; oraya bırakılan yer başa geçer, bağlı yerleri geçmez de.
        var r = rule(docked: [spot("external"), spot("external-2")])
        let connectedWithoutHeld: Set<String> = ["external", "external-2"]
        r.place(spot("external-4", 1), mode: .docked, connected: connectedWithoutHeld)
        #expect(labels(r.places(.docked)) == ["external-4·1", "external·1", "external-2·1"])
    }

    @Test func k7_emptyConnectedSetMakesEveryDropGoFirst() {
        var r = rule(docked: [spot("external")])
        r.place(spot("external-2"), mode: .docked, connected: [])
        r.place(spot("external-3"), mode: .docked, connected: [])
        #expect(labels(r.places(.docked)) == ["external-3·1", "external-2·1", "external·1"])
    }

    @Test func k7_laptopModeReplacesTheSinglePlaceAndIgnoresConnected() {
        var r = rule(docked: [spot("external"), spot("external-2")], undocked: spot("builtin", 1))
        r.place(spot("builtin", 4), mode: .undocked, connected: [])
        #expect(r.undocked == spot("builtin", 4))
        #expect(labels(r.places(.docked)) == ["external·1", "external-2·1"])
        #expect(r.places(.undocked).count == 1)
    }

    @Test func k7_nameTargetedPlaceIsReplacedByScreenToo() {
        // Ad hedefi de ekran başına bir yer sayılır (önbellekteki ekran).
        var r = rule(docked: [spot("external-2", 1, name: "N1"), spot("external", 2)])
        r.place(spot("external-2", 3), mode: .docked, connected: all)
        #expect(r.places(.docked).filter { $0.screen == "external-2" } == [spot("external-2", 3)])
        #expect(r.places(.docked).allSatisfy { $0.nameID == nil })
    }

    @Test func k7_nameTargetedDropKeepsItsNameID() {
        var r = rule(docked: [spot("external", 2)])
        r.place(spot("external-2", 1, name: "READING"), mode: .docked, connected: ["external"])
        // LG bağlı değil: ad hedefi başa geçer ve adını korur.
        #expect(r.docked?.nameID == "READING")
        #expect(r.dockedNext == [spot("external", 2)])
    }

    @Test func k7_nameTargetedPlaceCountsAsConnectedByItsCachedScreen() {
        var r = rule(docked: [spot("external-2", 1, name: "N1"), spot("external", 2)])
        r.place(spot("external-3", 1), mode: .docked, connected: ["external-2", "external-3"])
        // Ad hedefli ilk yer bağlı sayılır: Samsung onun hemen önüne girer.
        #expect(labels(r.places(.docked)) == ["external-3·1", "external-2·1", "external·2"])
        #expect(r.dockedNext.first?.nameID == "N1")
    }

    @Test func d4_dropOnTheSamePlaceTwiceIsIdempotent() {
        var r = rule(docked: [spot("external-2", 1), spot("external", 2)])
        r.place(spot("external", 2), mode: .docked, connected: all)
        let once = r.places(.docked)
        r.place(spot("external", 2), mode: .docked, connected: all)
        #expect(r.places(.docked) == once)
    }
}

// MARK: - Rule.removePlace / movePlace / setPlaces / subscript

struct CampaignRuleListTests {

    private let three = [spot("external", 1), spot("external-2", 2), spot("external-3", 3)]

    @Test func d4_removePlaceOutOfRangeIsANoOp() {
        var r = rule(docked: three)
        r.removePlace(at: 3, mode: .docked)
        r.removePlace(at: -1, mode: .docked)
        #expect(r.places(.docked) == three)
    }

    @Test func d4_removeFirstPlacePromotesTheNext() {
        var r = rule(docked: three)
        r.removePlace(at: 0, mode: .docked)
        #expect(r.docked == spot("external-2", 2))
        #expect(r.dockedNext == [spot("external-3", 3)])
    }

    @Test func d4_removeLastRemainingPlaceClearsDocked() {
        var r = rule(docked: [spot("external")])
        r.removePlace(at: 0, mode: .docked)
        #expect(r.docked == nil && r.dockedNext.isEmpty)
        #expect(r.places(.docked).isEmpty)
    }

    @Test func d4_removeLaptopPlaceOnlyAtIndexZero() {
        var r = rule(docked: three, undocked: spot("builtin", 2))
        r.removePlace(at: 1, mode: .undocked)
        #expect(r.undocked == spot("builtin", 2))
        r.removePlace(at: 0, mode: .undocked)
        #expect(r.undocked == nil)
        #expect(r.places(.docked) == three)
    }

    @Test func d4_movePlaceBoundsAndSameIndexAreNoOps() {
        var r = rule(docked: three)
        r.movePlace(from: 0, to: 0, mode: .docked)
        r.movePlace(from: 3, to: 0, mode: .docked)
        r.movePlace(from: 0, to: 3, mode: .docked)
        r.movePlace(from: -1, to: 1, mode: .docked)
        r.movePlace(from: 1, to: -1, mode: .docked)
        #expect(r.places(.docked) == three)
    }

    @Test func d4_moveFirstToLastAndBack() {
        var r = rule(docked: three)
        r.movePlace(from: 0, to: 2, mode: .docked)
        #expect(labels(r.places(.docked)) == ["external-2·2", "external-3·3", "external·1"])
        #expect(r.docked == spot("external-2", 2))
        r.movePlace(from: 2, to: 0, mode: .docked)
        #expect(r.places(.docked) == three)
    }

    @Test func d4_moveInLaptopModeIsANoOp() {
        var r = rule(docked: three, undocked: spot("builtin"))
        r.movePlace(from: 0, to: 1, mode: .undocked)
        #expect(r.undocked == spot("builtin"))
    }

    @Test func k3_setPlacesOnLaptopKeepsOnlyTheFirst() {
        var r = rule()
        r.setPlaces(three, mode: .undocked)
        #expect(r.undocked == three[0])
        #expect(r.places(.undocked) == [three[0]])
        #expect(r.docked == nil)
    }

    @Test func k3_setPlacesEmptyClearsTheWholeDockedList() {
        var r = rule(docked: three)
        r.setPlaces([], mode: .docked)
        #expect(r.docked == nil && r.dockedNext.isEmpty && r.hasNoPlaces)
    }

    @Test func k3_subscriptNilDropsOnlyTheFirstPlaceInDockedMode() {
        var r = rule(docked: three, undocked: spot("builtin"))
        r[.docked] = nil
        #expect(labels(r.places(.docked)) == ["external-2·2", "external-3·3"])
        r[.undocked] = nil
        #expect(r.undocked == nil)
        #expect(r.docked != nil)
    }

    @Test func k3_subscriptAssignReplacesTheFirstAndKeepsTheRest() {
        var r = rule(docked: three)
        r[.docked] = spot("external", 7)
        #expect(labels(r.places(.docked)) == ["external·7", "external-2·2", "external-3·3"])
    }

    @Test func k3_initWithoutDockedDropsNextPlaces() {
        let r = Rule(appName: "Acme", bundleID: "a", tokens: [], docked: nil,
                     undocked: nil, dockedNext: [spot("external")])
        #expect(r.dockedNext.isEmpty && r.places(.docked).isEmpty)
    }

    @Test func k3_mapPlacesDroppedPlacesShiftUp() {
        var r = rule(docked: three)
        r.mapPlaces(.docked) { index, place in index == 0 ? nil : place }
        #expect(labels(r.places(.docked)) == ["external-2·2", "external-3·3"])
        r.mapPlaces(.docked) { _, _ in nil }
        #expect(r.hasNoPlaces)
    }

    @Test func k3_hasNoPlacesNeedsBothModesEmpty() {
        #expect(!rule(undocked: spot("builtin")).hasNoPlaces)
        #expect(!rule(docked: [spot("external")]).hasNoPlaces)
        #expect(rule().hasNoPlaces)
    }
}

// MARK: - Document: setDestination / unpin / removePlace / setLayout / copyLayout / pin

struct CampaignDocumentPlacesTests {

    private func document(_ rules: Rule...) -> Document {
        var d = Document()
        d.rules = rules
        return d
    }

    private let all: Set<String> = ["builtin", "external", "external-2", "external-3"]

    @Test func d4_setDestinationNilClearsTheWholeDockedListButNotTheLaptopPlace() {
        var d = document(rule(docked: [spot("external-2"), spot("external", 2)],
                              undocked: spot("builtin")))
        d.setDestination(nil, for: "r", mode: .docked, connected: all)
        #expect(d.rule("r")?.places(.docked).isEmpty == true)
        #expect(d.rule("r")?.undocked == spot("builtin"))
    }

    @Test func d4_setDestinationNilKeepsTheRuleEvenWithoutPlaces() {
        // Düzen adımlarında nil "atanmamış"; kural silinmez (silmek unpin'in işi).
        var d = document(rule(docked: [spot("external")]))
        d.setDestination(nil, for: "r", mode: .docked)
        #expect(d.rule("r") != nil)
        #expect(d.rule("r")?.hasNoPlaces == true)
    }

    @Test func d4_setDestinationNilOnLaptopLeavesTheDockedList() {
        var d = document(rule(docked: [spot("external"), spot("external-2")], undocked: spot("builtin")))
        d.setDestination(nil, for: "r", mode: .undocked)
        #expect(d.rule("r")?.undocked == nil)
        #expect(labels(d.rule("r")?.places(.docked) ?? []) == ["external·1", "external-2·1"])
    }

    @Test func d4_setDestinationUnknownRuleIsANoOp() {
        var d = document(rule(docked: [spot("external")]))
        let before = d
        d.setDestination(spot("external-2"), for: "ghost", mode: .docked, connected: all)
        d.unpin("ghost", mode: .docked)
        d.removePlace(at: 0, for: "ghost", mode: .docked)
        d.movePlace(from: 0, to: 1, for: "ghost", mode: .docked)
        #expect(d == before)
    }

    @Test func d4_unpinKeepsRuleWhenTheOtherModeHasAPlace() {
        var d = document(rule(docked: [spot("external"), spot("external-2")], undocked: spot("builtin")))
        d.unpin("r", mode: .docked)
        #expect(d.rule("r")?.docked == nil && d.rule("r")?.dockedNext.isEmpty == true)
        #expect(d.rule("r")?.undocked == spot("builtin"))
    }

    @Test func d4_unpinDeletesRuleWhenNothingIsLeft() {
        var d = document(rule(docked: [spot("external"), spot("external-2")]))
        d.unpin("r", mode: .docked)
        #expect(d.rule("r") == nil)
    }

    @Test func d4_unpinLaptopLeavesTheMonitorList() {
        var d = document(rule(docked: [spot("external"), spot("external-2")], undocked: spot("builtin")))
        d.unpin("r", mode: .undocked)
        #expect(labels(d.rule("r")?.places(.docked) ?? []) == ["external·1", "external-2·1"])
        #expect(d.rule("r")?.undocked == nil)
    }

    @Test func d4_removeOnlyPlaceDeletesTheRuleUnlessLaptopHasOne() {
        var d = document(rule("a", docked: [spot("external")], app: "A"),
                         rule("b", docked: [spot("external")], undocked: spot("builtin"), app: "B"))
        d.removePlace(at: 0, for: "a", mode: .docked)
        d.removePlace(at: 0, for: "b", mode: .docked)
        #expect(d.rule("a") == nil)
        #expect(d.rule("b")?.undocked == spot("builtin"))
        #expect(d.rule("b")?.places(.docked).isEmpty == true)
    }

    @Test func d4_removePlaceOutOfRangeKeepsTheRule() {
        var d = document(rule(docked: [spot("external")]))
        let before = d
        d.removePlace(at: 5, for: "r", mode: .docked)
        #expect(d == before)
    }

    @Test func d4_movePlaceThroughDocumentReordersAndPromotesFirst() {
        var d = document(rule(docked: [spot("external", 1), spot("external-2", 2)]))
        d.movePlace(from: 1, to: 0, for: "r", mode: .docked)
        #expect(d.rule("r")?.docked == spot("external-2", 2))
        #expect(d.rule("r")?.dockedNext == [spot("external", 1)])
    }

    @Test func k3_setLayoutChangesOnlyTheFirstPlace() {
        var d = document(rule(docked: [spot("external", 1), spot("external-2", 2)]))
        let ok1 = d.setLayout(.leftHalf, for: "r", mode: .docked)
        #expect(ok1)
        let places = d.rule("r")?.places(.docked) ?? []
        #expect(places[0].layout == .leftHalf)
        #expect(places[1].layout == .full)
        #expect(places[0].screen == "external" && places[0].desktop == 1)
    }

    @Test func k3_setLayoutSameLayoutOrMissingTargetReturnsFalse() {
        var d = document(rule(docked: [spot("external", 1, layout: .leftHalf)]))
        let ok2 = d.setLayout(.leftHalf, for: "r", mode: .docked)
        #expect(!ok2)
        let ok3 = d.setLayout(.full, for: "r", mode: .undocked)
        #expect(!ok3)
        let ok4 = d.setLayout(.full, for: "ghost", mode: .docked)
        #expect(!ok4)
        #expect(d.rule("r")?.undocked == nil)
    }

    @Test func k3_setLayoutOnLaptopLeavesTheMonitorLayouts() {
        var d = document(rule(docked: [spot("external"), spot("external-2")], undocked: spot("builtin")))
        let ok5 = d.setLayout(.rightHalf, for: "r", mode: .undocked)
        #expect(ok5)
        #expect(d.rule("r")?.places(.docked).allSatisfy { $0.layout == .full } == true)
    }

    @Test func k3_copyLayoutDockedToLaptopTakesOnlyTheFirstPlace() {
        var d = document(rule(docked: [spot("external-2", 2), spot("external", 3)], undocked: spot("builtin")))
        let ok6 = d.copyLayout(from: .docked, to: .undocked)
        #expect(ok6)
        #expect(d.rule("r")?.undocked == spot("external-2", 2))
        #expect(labels(d.rule("r")?.places(.docked) ?? []) == ["external-2·2", "external·3"])
    }

    @Test func k3_copyLayoutLaptopToDockedOverwritesTheWholeList() {
        var d = document(rule(docked: [spot("external-2", 2), spot("external", 3)], undocked: spot("builtin", 4)))
        let ok7 = d.copyLayout(from: .undocked, to: .docked)
        #expect(ok7)
        #expect(labels(d.rule("r")?.places(.docked) ?? []) == ["builtin·4"])
        #expect(d.rule("r")?.dockedNext.isEmpty == true)
    }

    @Test func k3_copyLayoutDropsRulesLeftWithoutAnyPlace() {
        var d = document(rule("only", docked: [spot("external")], app: "Only"),
                         rule("both", docked: [spot("external")], undocked: spot("builtin"), app: "Both"))
        let ok8 = d.copyLayout(from: .undocked, to: .docked)
        #expect(ok8)
        // "only" laptop yeri yok: monitör listesi silinir, kural kalmaz.
        #expect(d.rule("only") == nil)
        #expect(d.rule("both")?.docked == spot("builtin"))
    }

    @Test func k3_copyLayoutSameModeAndAlreadyEqualReturnFalse() {
        var d = document(rule(docked: [spot("builtin")], undocked: spot("builtin")))
        let ok9 = d.copyLayout(from: .docked, to: .docked)
        #expect(!ok9)
        let ok10 = d.copyLayout(from: .docked, to: .undocked)
        #expect(!ok10)
    }

    @Test func d4_pinWithSameKeyUpdatesTheExistingRuleThroughK7() {
        var d = document(rule("safari", docked: [spot("external-2"), spot("external", 2)],
                              app: "Safari", tokens: ["Inbox", "Work"]))
        let draft = rule("draft", app: "Safari", tokens: ["work", "INBOX"])
        let id = d.pin(draft, destination: spot("external-3"), mode: .docked, connected: ["external", "external-3"])
        #expect(id == "safari")
        #expect(d.rules.count == 1)
        #expect(labels(d.rule("safari")?.places(.docked) ?? []) == ["external-2·1", "external-3·1", "external·2"])
    }

    @Test func d4_pinWithDifferentTokensCreatesASeparateRule() {
        var d = document(rule("a", docked: [spot("external")], app: "Safari", tokens: ["Inbox"]))
        let id = d.pin(rule("b", app: "Safari", tokens: ["Other"]), destination: spot("external-2"),
                       mode: .docked, connected: all)
        #expect(id == "b" && d.rules.count == 2)
        #expect(labels(d.rule("a")?.places(.docked) ?? []) == ["external·1"])
        #expect(labels(d.rule("b")?.places(.docked) ?? []) == ["external-2·1"])
    }

    @Test func d4_pinOnLaptopModeOfAnExistingRuleKeepsItsMonitorList() {
        var d = document(rule("a", docked: [spot("external"), spot("external-2")], app: "Safari"))
        d.pin(rule("x", app: "Safari"), destination: spot("builtin", 2), mode: .undocked)
        #expect(d.rules.count == 1)
        #expect(d.rule("a")?.undocked == spot("builtin", 2))
        #expect(labels(d.rule("a")?.places(.docked) ?? []) == ["external·1", "external-2·1"])
    }

    @Test func d4_pinDifferentBundleSameNameStaysSeparate() {
        var d = document(rule("a", docked: [spot("external")], app: "Safari"))
        var other = rule("b", app: "Safari")
        other.bundleID = "com.other.Safari"
        d.pin(other, destination: spot("external-2"), mode: .docked)
        #expect(d.rules.count == 2)
    }
}

// MARK: - Adlı masaüstü hedefleri (K7 + şema 6)

struct CampaignNamedPlacesTests {

    /// `external` rolünün 2. masaüstü "Reading" adlı.
    private func namedDocument(_ rules: Rule...) -> (Document, String) {
        var d = Document()
        d.rules = rules
        let ok11 = d.setDesktopName("Reading", screen: "external", desktop: 2, mode: .docked)
        #expect(ok11)
        return (d, d.nameRecord(named: "Reading")!.id)
    }

    @Test func n_setDestinationOnANamedSlotBecomesANameTarget() {
        var (d, id) = namedDocument(rule(docked: [spot("external-2")]))
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external", "external-2"])
        #expect(d.rule("r")?.places(.docked).first?.nameID == id)
        #expect(d.rule("r")?.places(.docked).count == 2)
    }

    @Test func n_setDestinationOnAPlainSlotOfTheSameScreenDropsTheName() {
        var (d, id) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external"])
        #expect(d.rule("r")?.docked?.nameID == id)
        d.setDestination(spot("external", 3), for: "r", mode: .docked, connected: ["external"])
        #expect(d.rule("r")?.places(.docked) == [spot("external", 3)])
        #expect(d.rule("r")?.docked?.nameID == nil)
    }

    @Test func n_nameTargetKeepsItsPlaceWhenAnotherScreenIsDropped() {
        var (d, id) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external", "external-2"])
        d.setDestination(spot("external-2", 1), for: "r", mode: .docked, connected: ["external", "external-2"])
        // LG, bağlı ilk yer olan Dell adının önüne girer; ad bağı korunur.
        let places = d.rule("r")?.places(.docked) ?? []
        #expect(places.map(\.screen) == ["external-2", "external"])
        #expect(places[1].nameID == id)
    }

    @Test func n_unpinRemovesTheNameTargetedListToo() {
        var (d, _) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external"])
        d.setDestination(spot("external-2", 1), for: "r", mode: .docked, connected: ["external"])
        d.unpin("r", mode: .docked)
        // N2: ad öbür kurulumda da bağlanmış olabilir; yalnız monitör listesi silinir.
        #expect(d.rule("r")?.places(.docked).isEmpty ?? true)
        #expect(d.names.count == 1)   // ad masaüstüne aittir, pin silinince gitmez
    }

    @Test func n_removingTheNamedPlaceKeepsTheNumberedFallback() {
        var (d, _) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external"])
        d.setDestination(spot("external-2", 1), for: "r", mode: .docked, connected: [])
        d.removePlace(at: 0, for: "r", mode: .docked)
        #expect(d.rule("r")?.places(.docked).count == 1)
        #expect(d.rule("r")?.docked?.nameID != nil)
    }

    @Test func n_copyLayoutKeepsNameTargetsAsNameTargets() {
        var (d, id) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external"])
        _ = d.copyLayout(from: .docked, to: .undocked)
        #expect(d.rule("r")?.undocked?.nameID == id)
    }

    @Test func n_layoutOfANameTargetChangesWithoutLosingTheName() {
        var (d, id) = namedDocument(rule())
        d.setDestination(spot("external", 2), for: "r", mode: .docked, connected: ["external"])
        let ok12 = d.setLayout(.topHalf, for: "r", mode: .docked)
        #expect(ok12)
        #expect(d.rule("r")?.docked?.nameID == id)
        #expect(d.rule("r")?.docked?.layout == .topHalf)
    }
}

// MARK: - Store: bağlı roller kapanışı, geri al / yinele

@MainActor
struct CampaignStorePlacesTests {

    private func store(_ rules: [Rule], connected: Set<String>) -> Store {
        var d = Document()
        d.rules = rules
        let s = Store(demo: d)
        s.connectedRoles = { connected }
        return s
    }

    private func places(_ s: Store, _ id: String = "r") -> [String] {
        labels(s.document.rule(id)?.places(.docked) ?? [])
    }

    @Test func d4_moveRuleUsesTheConnectedClosure() {
        let connectedOnlyDell = store([rule(docked: [spot("external-2"), spot("external", 2)])],
                                      connected: ["external", "external-3"])
        connectedOnlyDell.moveRule("r", to: spot("external-3"), mode: .docked)
        #expect(places(connectedOnlyDell) == ["external-2·1", "external-3·1", "external·2"])

        let nothingConnected = store([rule(docked: [spot("external-2"), spot("external", 2)])], connected: [])
        nothingConnected.moveRule("r", to: spot("external-3"), mode: .docked)
        #expect(places(nothingConnected) == ["external-3·1", "external-2·1", "external·2"])
    }

    @Test func d4_moveRuleUndoRestoresTheWholeListAndRedoReplays() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2)])], connected: ["external"])
        let before = places(s)
        s.moveRule("r", to: spot("external-3"), mode: .docked)
        let after = places(s)
        #expect(after != before)
        s.undo()
        #expect(places(s) == before)
        s.redo()
        #expect(places(s) == after)
    }

    @Test func d4_removePlaceUndoBringsBackTheSecondaryPlace() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2), spot("external-3", 3)])],
                      connected: [])
        s.removePlace(at: 1, for: "r", mode: .docked)
        #expect(places(s) == ["external-2·1", "external-3·3"])
        s.undo()
        #expect(places(s) == ["external-2·1", "external·2", "external-3·3"])
        s.redo()
        #expect(places(s) == ["external-2·1", "external-3·3"])
    }

    @Test func d4_removeOnlyPlaceDeletesRuleAndUndoRestoresIt() {
        let s = store([rule(docked: [spot("external", 2, layout: .leftHalf)])], connected: [])
        s.removePlace(at: 0, for: "r", mode: .docked)
        #expect(s.document.rule("r") == nil)
        s.undo()
        #expect(s.document.rule("r")?.docked == spot("external", 2, layout: .leftHalf))
    }

    @Test func d4_movePlaceUndoRedo() {
        let s = store([rule(docked: [spot("external"), spot("external-2"), spot("external-3")])], connected: [])
        s.movePlace(from: 2, to: 0, for: "r", mode: .docked)
        #expect(places(s) == ["external-3·1", "external·1", "external-2·1"])
        s.undo()
        #expect(places(s) == ["external·1", "external-2·1", "external-3·1"])
        s.redo()
        #expect(places(s) == ["external-3·1", "external·1", "external-2·1"])
    }

    @Test func d4_noOpMovePlaceLeavesNoHistoryStep() {
        let s = store([rule(docked: [spot("external"), spot("external-2")])], connected: [])
        let steps = s.history.entries.count
        s.movePlace(from: 0, to: 0, for: "r", mode: .docked)
        s.movePlace(from: 0, to: 9, for: "r", mode: .docked)
        s.removePlace(at: 9, for: "r", mode: .docked)
        #expect(s.history.entries.count == steps)
    }

    @Test func d4_unpinUndoRestoresTheEntireDockedList() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2)], undocked: spot("builtin"))],
                      connected: [])
        s.unpin("r", mode: .docked)
        #expect(places(s).isEmpty)
        s.undo()
        #expect(places(s) == ["external-2·1", "external·2"])
        #expect(s.document.rule("r")?.undocked == spot("builtin"))
    }

    @Test func d4_pinManyWritesEveryItemWithOneUndoStep() {
        let a = rule("a", docked: [spot("external-2")], app: "A")
        let b = rule("b", docked: [spot("external-2")], app: "B")
        let s = store([a, b], connected: ["external"])
        s.pinMany([(rule: a, destination: spot("external", 3)),
                   (rule: b, destination: spot("external-3", 1))], mode: .docked)
        #expect(places(s, "a") == ["external-2·1", "external·3"])
        #expect(places(s, "b") == ["external-3·1", "external-2·1"])
        s.undo()
        #expect(places(s, "a") == ["external-2·1"])
        #expect(places(s, "b") == ["external-2·1"])
        s.redo()
        #expect(places(s, "a") == ["external-2·1", "external·3"])
    }

    @Test func d4_pinManySameRuleTwiceKeepsOnePlacePerScreen() {
        let a = rule("a", docked: [spot("external-2")], app: "A")
        let s = store([a], connected: ["external", "external-2"])
        s.pinMany([(rule: a, destination: spot("external", 1)),
                   (rule: a, destination: spot("external", 4))], mode: .docked)
        #expect(places(s, "a").filter { $0.hasPrefix("external·") } == ["external·4"])
        #expect(s.document.rules.count == 1)
    }

    @Test func d4_pinManyEmptyBatchLeavesNoStep() {
        let s = store([rule(docked: [spot("external")])], connected: [])
        let steps = s.history.entries.count
        s.pinMany([], mode: .docked)
        #expect(s.history.entries.count == steps)
    }

    @Test func d4_moveGroupAppliesPerRuleK7AndUndoesTogether() {
        let a = rule("a", docked: [spot("external-2"), spot("external", 2)], app: "A")
        let b = rule("b", docked: [spot("external", 1)], app: "B")
        let s = store([a, b], connected: ["external", "external-3"])
        s.moveGroup([.init(id: "a", destination: spot("external-3")),
                     .init(id: "b", destination: spot("external-3"))], mode: .docked)
        #expect(places(s, "a") == ["external-2·1", "external-3·1", "external·2"])
        #expect(places(s, "b") == ["external-3·1", "external·1"])
        s.undo()
        #expect(places(s, "a") == ["external-2·1", "external·2"])
        #expect(places(s, "b") == ["external·1"])
    }

    @Test func d4_moveGroupIgnoresUnknownRuleIDs() {
        let s = store([rule(docked: [spot("external")])], connected: ["external"])
        s.moveGroup([.init(id: "ghost", destination: spot("external-2"))], mode: .docked)
        #expect(places(s) == ["external·1"])
        #expect(s.document.rules.count == 1)
    }

    @Test func d4_pinOverExistingPlaceIsUndoableButFirstPinIsAddedToo() {
        let s = store([rule("safari", docked: [spot("external-2")], app: "Safari")], connected: ["external"])
        let draft = rule("d", app: "Safari")
        let id = s.pin(draft, destination: spot("external", 2), mode: .docked)
        #expect(id == "safari")
        #expect(places(s, "safari") == ["external-2·1", "external·2"])
        s.undo()
        #expect(places(s, "safari") == ["external-2·1"])
    }

    @Test func d4_pinInAnEmptyModeOfAnExistingRuleKeepsTheOtherModeAndBumpsNoDuplicate() {
        let s = store([rule("safari", undocked: spot("builtin"), app: "Safari")], connected: ["external"])
        let id = s.pin(rule("d", app: "Safari"), destination: spot("external"), mode: .docked)
        #expect(id == "safari" && s.document.rules.count == 1)
        #expect(places(s, "safari") == ["external·1"])
        #expect(s.document.rule("safari")?.undocked == spot("builtin"))
    }

    @Test func k3_saveLayoutStoreChangesOnlyTheFirstPlaceAndUndoes() {
        let s = store([rule(docked: [spot("external"), spot("external-2")])], connected: [])
        #expect(s.saveLayout(.right30, for: "r", mode: .docked))
        #expect(s.document.rule("r")?.docked?.layout == .right30)
        #expect(s.document.rule("r")?.dockedNext.first?.layout == .full)
        s.undo()
        #expect(s.document.rule("r")?.docked?.layout == .full)
    }

    @Test func k3_copyLayoutStoreUndoRestoresTheDockedList() {
        let s = store([rule(docked: [spot("external-2", 2), spot("external", 3)], undocked: spot("builtin", 4))],
                      connected: [])
        #expect(s.copyLayout(from: .undocked, to: .docked))
        #expect(places(s) == ["builtin·4"])
        s.undo()
        #expect(places(s) == ["external-2·2", "external·3"])
        s.redo()
        #expect(places(s) == ["builtin·4"])
    }

    @Test func d4_undoThenNewEditDropsTheRedoBranch() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2)])], connected: [])
        s.movePlace(from: 1, to: 0, for: "r", mode: .docked)
        s.undo()
        s.removePlace(at: 0, for: "r", mode: .docked)
        let after = places(s)
        s.redo()
        #expect(places(s) == after)
    }

    @Test func d4_setDestinationStoreUsesTheLiveConnectedSet() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2)])], connected: ["external", "external-3"])
        s.setDestination(spot("external-3", 2), for: "r", mode: .docked)
        #expect(places(s) == ["external-2·1", "external-3·2", "external·2"])
        s.connectedRoles = { [] }
        s.setDestination(spot("external", 5), for: "r", mode: .docked)
        #expect(places(s).first == "external·5")
    }

    @Test func d4_setDestinationNilStoreClearsAllMonitorPlaces() {
        let s = store([rule(docked: [spot("external-2"), spot("external", 2)], undocked: spot("builtin"))],
                      connected: [])
        s.setDestination(nil, for: "r", mode: .docked)
        #expect(places(s).isEmpty)
        #expect(s.document.rule("r")?.undocked == spot("builtin"))
    }
}
