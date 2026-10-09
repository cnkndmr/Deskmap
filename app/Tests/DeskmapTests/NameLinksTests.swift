import Foundation
import Testing
@testable import Deskmap

private let D = Mode.docked, U = Mode.undocked

private func pinRule(_ app: String, docked: (String, Int)? = nil, undocked: (String, Int)? = nil) -> Rule {
    var rule = Rule(appName: app, bundleID: "b.\(app)", tokens: [])
    if let docked { rule.docked = Destination(screen: docked.0, desktop: docked.1) }
    if let undocked { rule.undocked = Destination(screen: undocked.0, desktop: undocked.1) }
    return rule
}

/// Canlı rules.json'daki biçim: Notes Hub hem docked|external 1 (1027) hem
/// undocked|builtin 5 (421); Nova2/Orion/MD2 yalnız docked|external.
private func liveShape() -> Document {
    var d = Document()
    d.desktopNames = [
        "docked|builtin": ["4": "AI Setup"],
        "undocked|builtin": ["4": "AI Setup", "5": "Notes Hub"],
        "docked|external": ["1": "Notes Hub", "2": "Nova2", "3": "Orion", "4": "MD2"],
    ]
    d.desktopNameSpaces = [
        "docked|builtin": ["4": 8],
        "undocked|builtin": ["4": 8, "5": 421],
        "docked|external": ["1": 1027],
    ]
    return d
}

private func names(_ d: Document, _ mode: Mode) -> [String: [String: String]] { d.desktopNames(for: mode) }

/// Adlı masaüstü = tek mantıksal masaüstü: yeniden adlandırma, ad silme,
/// silme, taşıma ve pinler iki kurulumda birlikte.
struct NameLinkTests {

    @Test func renameDockedExternalRenamesUndockedCounterpart() {
        var d = liveShape()
        let ok1 = d.setDesktopName("Beyin", screen: "external", desktop: 1, mode: D, space: 1027)
        #expect(ok1)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == "Beyin")
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: U) == "Beyin")
        // Kimlik bağı korunur.
        #expect(d.desktopNameSpaces["undocked|builtin"]?["5"] == 421)
    }

    @Test func renameFromTheLaptopSideRenamesTheDellSide() {
        var d = liveShape()
        d.setDesktopName("Beyin", screen: "builtin", desktop: 5, mode: U)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == "Beyin")
    }

    @Test func removeNameOnExternalRemovesUndockedCounterpart() {
        var d = liveShape()
        d.setDesktopName(nil, screen: "external", desktop: 1, mode: D)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == nil)
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: U) == nil)
        #expect(d.desktopNameSpaces["undocked|builtin"]?["5"] == nil)
        // Öbür adlara dokunulmaz.
        #expect(d.desktopName(screen: "builtin", desktop: 4, mode: U) == "AI Setup")
    }

    @Test func renameToDuplicateNameInSameModeIsRejected() {
        var d = liveShape()
        let before = d
        let ok2 = d.setDesktopName("nova2", screen: "external", desktop: 3, mode: D)
        #expect(!ok2)
        #expect(d == before)
        // Karşılığın kurulumunda da çakışma reddedilir.
        d.desktopNames["undocked|builtin"]?["6"] = "Taken"
        let before2 = d
        let ok3 = d.setDesktopName("Taken", screen: "external", desktop: 1, mode: D)
        #expect(!ok3)
        #expect(d == before2)
        // Kendi adına dönmek çakışma değil.
        let ok4 = d.setDesktopName("notes hub", screen: "external", desktop: 1, mode: D)
        #expect(ok4)
    }

    @Test func builtinMirrorSkipsNonexistentSlot() {
        var d = Document()
        d.setPlannedDesktops(4, mode: D, screen: "builtin")
        d.setDesktopName("X", screen: "builtin", desktop: 5, mode: U)
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: D) == nil)
        d.setDesktopName("Y", screen: "builtin", desktop: 3, mode: U)
        #expect(d.desktopName(screen: "builtin", desktop: 3, mode: D) == "Y")
    }

    @Test func builtinMirrorNeverOverwritesAnotherName() {
        var d = Document()
        d.setDesktopName("Old", screen: "builtin", desktop: 3, mode: D)
        d.desktopNames["undocked|builtin"] = ["3": "Other"]
        d.setDesktopName("New", screen: "builtin", desktop: 3, mode: D)
        #expect(d.desktopName(screen: "builtin", desktop: 3, mode: U) == "Other")
    }

    // MARK: Normalleştirme

    @Test func normalizeDedupesNamesPerModeCaseInsensitive() {
        var d = Document()
        d.desktopNames = ["docked|external": ["1": "Foo", "3": "FOO", "2": "Bar"]]
        d.desktopNameSpaces = ["docked|external": ["1": 11, "3": 33]]
        let ok5 = d.normalizeNameLinks()
        #expect(ok5)
        #expect(names(d, D)["external"] == ["1": "Foo", "2": "Bar"])
        #expect(d.desktopNameSpaces["docked|external"] == ["1": 11])
    }

    @Test func normalizeIsIdempotent() throws {
        var d = liveShape()
        d.desktopNames["docked|external"]?["5"] = "notes hub"
        d.ghostDesktops = [
            GhostDesktop(screen: "external", name: "Gone", desktop: 9, deletedAt: Date(timeIntervalSince1970: 1)),
            GhostDesktop(screen: "external", name: "gone", desktop: 8, deletedAt: Date(timeIntervalSince1970: 2)),
        ]
        d.normalizeNameLinks()
        let once = d
        let ok6 = d.normalizeNameLinks()
        #expect(!ok6)
        #expect(d == once)
        #expect(d.ghostDesktops.count == 1)
        // Dosyadan okurken de uygulanır ve tutarlı kalır.
        let decoded = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
        #expect(decoded.desktopNames == d.desktopNames)
    }

    @Test func existingLiveDataMigratesWithoutLoss() throws {
        let d = liveShape()
        var decoded = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
        #expect(decoded.desktopNames == d.desktopNames)
        #expect(decoded.desktopNameSpaces == d.desktopNameSpaces)
        let ok7 = decoded.normalizeNameLinks()
        #expect(!ok7)
        // Yalnız docked'daki adlar undocked'da yok; sahiplenme bunu çözer.
        #expect(decoded.place(mode: U, ofName: "Nova2") == nil)
        #expect(decoded.place(mode: D, ofName: "Notes Hub")?.slot == Slot(screen: "external", desktop: 1))
        #expect(decoded.place(mode: U, ofName: "notes hub")?.slot == Slot(screen: "builtin", desktop: 5))
    }

    @Test func liveDataSetupSwitchAssignsDockedOnlyNamesToNewLaptopDesktops() {
        // Monitör çıktı: Dell'in 4 masaüstü laptop'a 5…8 olarak eklendi, hepsi
        // yeni kimlikle (421 dahil). Sayılar tutuyor: sırayla atanır.
        var d = liveShape()
        d.rules = [pinRule("Nova", docked: ("external", 2)), pinRule("Md", docked: ("external", 4))]
        let previous: [String: [UInt64]] = ["builtin": [1, 2, 3, 8], "external": [1027, 1028, 1029, 1030]]
        let live: [String: [UInt64]] = ["builtin": [1, 2, 3, 8, 421, 422, 423, 424]]
        let result = d.reconcileNames(spaces: live, seen: [], mode: U, previous: previous)
        #expect(result.changed)
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: U) == "Notes Hub")
        #expect(d.desktopName(screen: "builtin", desktop: 6, mode: U) == "Nova2")
        #expect(d.desktopName(screen: "builtin", desktop: 7, mode: U) == "Orion")
        #expect(d.desktopName(screen: "builtin", desktop: 8, mode: U) == "MD2")
        #expect(d.rules.first { $0.appName == "Nova" }?.undocked == Destination(screen: "builtin", desktop: 6))
        #expect(d.rules.first { $0.appName == "Md" }?.undocked == Destination(screen: "builtin", desktop: 8))
        // Docked tarafı bozulmadı.
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova2")
    }

    @Test func setupSwitchWithMismatchedCountsInventsNothing() {
        var d = liveShape()
        let previous: [String: [UInt64]] = ["builtin": [1, 2, 3, 8], "external": [1027, 1028, 1029, 1030]]
        // Yalnız 3 yeni masaüstü: belirsiz, atama yok.
        let live: [String: [UInt64]] = ["builtin": [1, 2, 3, 8, 421, 422, 423]]
        d.reconcileNames(spaces: live, seen: [], mode: U, previous: previous)
        #expect(d.place(mode: U, ofName: "Nova2") == nil)
        #expect(d.place(mode: U, ofName: "MD2") == nil)
    }

    // MARK: Sahiplenme ve izleme

    @Test func reconcileAdoptsNameWhenBoundSpaceMovesToLaptop() {
        var d = Document()
        d.setDesktopName("Nova2", screen: "external", desktop: 2, mode: D, space: 202)
        let result = d.reconcileNames(spaces: ["builtin": [1, 2, 3, 4, 101, 202]],
                                      seen: [1, 2, 3, 4, 101, 202], mode: U)
        #expect(result.adopted.count == 1)
        #expect(d.desktopName(screen: "builtin", desktop: 6, mode: U) == "Nova2")
        #expect(d.desktopNameSpaces["undocked|builtin"]?["6"] == 202)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova2")
    }

    @Test func adoptionMirrorsDockedPinsToUndocked() {
        var d = Document()
        d.setDesktopName("Nova2", screen: "external", desktop: 2, mode: D, space: 202)
        d.rules = [pinRule("Code", docked: ("external", 2)),
                   pinRule("Own", docked: ("external", 2), undocked: ("builtin", 1))]
        d.reconcileNames(spaces: ["builtin": [1, 2, 202]], seen: [], mode: U)
        #expect(d.rules[0].undocked == Destination(screen: "builtin", desktop: 3))
        // Var olan hedefin üzerine yazılmaz.
        #expect(d.rules[1].undocked == Destination(screen: "builtin", desktop: 1))
    }

    @Test func reconcileEmitsMoveOnMissionControlReorderAndPinsFollow() {
        var d = Document()
        d.setDesktopName("Hub", screen: "external", desktop: 1, mode: D, space: 11)
        d.setDesktopName("Other", screen: "external", desktop: 2, mode: D, space: 22)
        d.rules = [pinRule("A", docked: ("external", 1)), pinRule("B", docked: ("external", 2)),
                   pinRule("C", docked: ("external", 3))]
        let result = d.reconcileNames(spaces: ["external": [22, 33, 11]], seen: [11, 22, 33], mode: D)
        #expect(result.moves.count == 2)
        #expect(d.rules.first { $0.appName == "A" }?.docked?.desktop == 3)
        #expect(d.rules.first { $0.appName == "B" }?.docked?.desktop == 1)
        // Adsız masaüstünün pini izlenemez: yerinde kalır.
        #expect(d.rules.first { $0.appName == "C" }?.docked?.desktop == 3)
    }

    @Test func pinsFollowNameOnReorder() {
        var d = Document()
        d.rules = [pinRule("A", docked: ("external", 1), undocked: ("builtin", 5))]
        d.applyPinMoves([NameMove(mode: D, name: "X", from: Slot(screen: "external", desktop: 1),
                                  to: Slot(screen: "external", desktop: 3))])
        #expect(d.rules[0].docked == Destination(screen: "external", desktop: 3))
        // Öbür kurulum dokunulmadı.
        #expect(d.rules[0].undocked == Destination(screen: "builtin", desktop: 5))
    }

    @Test func pinsFollowNameToOtherScreen() {
        var d = Document()
        d.setDesktopName("Hub", screen: "external", desktop: 1, mode: D, space: 11)
        d.rules = [pinRule("A", docked: ("external", 1))]
        d.reconcileNames(spaces: ["external": [5], "builtin": [1, 2, 11]], seen: [11, 5, 1, 2], mode: D)
        #expect(d.desktopName(screen: "builtin", desktop: 3, mode: D) == "Hub")
        #expect(d.rules[0].docked == Destination(screen: "builtin", desktop: 3))
    }

    @Test func applyPinMovesHandlesSwapSimultaneously() {
        var d = Document()
        d.rules = [pinRule("A", docked: ("external", 1)), pinRule("B", docked: ("external", 2))]
        d.applyPinMoves([
            NameMove(mode: D, name: "a", from: Slot(screen: "external", desktop: 1),
                     to: Slot(screen: "external", desktop: 2)),
            NameMove(mode: D, name: "b", from: Slot(screen: "external", desktop: 2),
                     to: Slot(screen: "external", desktop: 1)),
        ])
        #expect(d.rules[0].docked?.desktop == 2)
        #expect(d.rules[1].docked?.desktop == 1)
    }

    @Test func reconcileRenewedIdsRebindByNumberKeepsNames() {
        var d = Document()
        d.setDesktopName("A", screen: "external", desktop: 1, mode: D, space: 11)
        d.setDesktopName("B", screen: "external", desktop: 2, mode: D, space: 22)
        let result = d.reconcileNames(spaces: ["external": [91, 92]], seen: [11, 22], mode: D)
        #expect(result.dropped.isEmpty)
        #expect(names(d, D)["external"] == ["1": "A", "2": "B"])
        #expect(d.desktopNameSpaces["docked|external"] == ["1": 91, "2": 92])
    }

    @Test func reconcileDeletedSeenIdIsReportedAsDropped() {
        var d = Document()
        d.setDesktopName("A", screen: "external", desktop: 1, mode: D, space: 11)
        d.setDesktopName("B", screen: "external", desktop: 2, mode: D, space: 22)
        let result = d.reconcileNames(spaces: ["external": [22]], seen: [11, 22], mode: D)
        #expect(result.dropped.map(\.name) == ["A"])
        #expect(result.dropped.first?.place.desktop == 1)
        #expect(names(d, D)["external"] == ["1": "B"])
    }

    @Test func reconcileOverflowFallbackReportsDroppedNotPhantom() {
        var d = Document()
        // A kimlikle 2'ye gider; B (bağsız) de 2'de duruyor ve 3 yok.
        d.desktopNames["docked|external"] = ["1": "A", "2": "B"]
        d.desktopNameSpaces["docked|external"] = ["1": 22]
        let result = d.reconcileNames(spaces: ["external": [11, 22]], seen: [], mode: D)
        #expect(result.dropped.map(\.name) == ["B"])
        #expect(names(d, D)["external"] == ["2": "A"])
    }

    @Test func unseenIdKeepsNameAfterRestart() {
        var d = Document()
        d.setDesktopName("A", screen: "external", desktop: 1, mode: D, space: 11)
        let result = d.reconcileNames(spaces: ["external": [11, 22], "builtin": [1]], seen: [], mode: D)
        #expect(result.dropped.isEmpty)
        #expect(names(d, D)["external"] == ["1": "A"])
    }

    // MARK: Taşıma ve silme

    @Test func builtinReorderRemapsBothModesNamesAndPins() {
        var d = Document()
        d.setDesktopName("AI", screen: "builtin", desktop: 4, mode: D)
        d.rules = [pinRule("A", docked: ("builtin", 4), undocked: ("builtin", 4))]
        d.moveDesktop(on: "builtin", from: 4, to: 2, count: 4, mode: D, sharedLaptop: true)
        #expect(names(d, D)["builtin"] == ["2": "AI"])
        #expect(names(d, U)["builtin"] == ["2": "AI"])
        #expect(d.rules[0].docked?.desktop == 2)
        #expect(d.rules[0].undocked?.desktop == 2)
        // Etkin olmayan modda (sharedLaptop false) öbür kurulum dokunulmaz.
        var plan = Document()
        plan.setDesktopName("AI", screen: "builtin", desktop: 4, mode: D)
        plan.moveDesktop(on: "builtin", from: 4, to: 2, count: 4, mode: U)
        #expect(names(plan, U)["builtin"] == ["2": "AI"])
        #expect(names(plan, D)["builtin"] == ["4": "AI"])
    }

    @Test func externalReorderRemapsActiveModeOnly() {
        var d = liveShape()
        d.rules = [pinRule("A", docked: ("external", 1), undocked: ("builtin", 5))]
        d.moveDesktop(on: "external", from: 1, to: 3, count: 4, mode: D, sharedLaptop: true)
        #expect(d.rules[0].docked?.desktop == 3)
        #expect(d.rules[0].undocked?.desktop == 5)
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: U) == "Notes Hub")
    }

    @Test func moveAcrossKeepsOtherModeNameAndPinsLinkedByName() {
        var d = Document()
        d.setDesktopName("Nova", screen: "builtin", desktop: 3, mode: D)
        d.rules = [pinRule("A", docked: ("builtin", 3), undocked: ("builtin", 3))]
        d.moveDesktopAcross(from: "builtin", desktop: 3, to: "external", at: 1, toCount: 1, mode: D)
        #expect(d.rules[0].docked == Destination(screen: "external", desktop: 1))
        #expect(d.rules[0].undocked == Destination(screen: "builtin", desktop: 3))
        #expect(d.place(mode: D, ofName: "nova")?.slot == Slot(screen: "external", desktop: 1))
        #expect(d.place(mode: U, ofName: "nova")?.slot == Slot(screen: "builtin", desktop: 3))
    }

    @Test func deferredRemovalShiftsNamesInAllModesOnce() {
        var d = Document()
        d.setDesktopName("A", screen: "builtin", desktop: 1, mode: U)
        d.setDesktopName("C", screen: "builtin", desktop: 3, mode: U)
        d.removeDesktopLater(on: "builtin", desktop: 2, mode: U, existing: true, space: nil)
        #expect(names(d, U)["builtin"] == ["1": "A", "2": "C"])
        #expect(names(d, D)["builtin"] == ["1": "A", "2": "C"])
        d.removeDesktop(on: "builtin", desktop: 2, modes: [D], shiftNames: false)
        #expect(names(d, U)["builtin"] == ["1": "A", "2": "C"])
        #expect(names(d, D)["builtin"] == ["1": "A", "2": "C"])
    }

    @Test func removeNamedDesktopRemovesCounterpartAndPins() {
        var d = liveShape()
        d.desktopNames["undocked|builtin"]?["6"] = "After"
        d.rules = [pinRule("A", docked: ("external", 1), undocked: ("builtin", 5)),
                   pinRule("B", undocked: ("builtin", 6)),
                   pinRule("C", docked: ("external", 2))]
        d.removeDesktop(on: "external", desktop: 1, modes: Mode.allCases)
        #expect(d.place(mode: D, ofName: "Notes Hub") == nil)
        #expect(d.place(mode: U, ofName: "Notes Hub") == nil)
        // Karşılığın ekranında sonrakiler kaydı, Dell'de de.
        #expect(d.desktopName(screen: "builtin", desktop: 5, mode: U) == "After")
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == "Nova2")
        #expect(d.rules.first { $0.appName == "B" }?.undocked?.desktop == 5)
        #expect(d.rules.first { $0.appName == "C" }?.docked?.desktop == 1)
    }

    // MARK: Pinler

    @Test func pinOnNamedDesktopMirrorsToOtherMode() {
        var d = liveShape()
        let id = d.pin(pinRule("Safari"), destination: Destination(screen: "external", desktop: 2), mode: D)
        // Nova2 undocked'da henüz yok: yansıtılmaz.
        #expect(d.rule(id)?.undocked == nil)
        let brain = d.pin(pinRule("Mail"), destination: Destination(screen: "external", desktop: 1,
                                                                       layout: .leftHalf), mode: D)
        #expect(d.rule(brain)?.undocked == Destination(screen: "builtin", desktop: 5, layout: .leftHalf))
        // Hedefi başka adlı masaüstüne taşıyınca karşılık da taşınır.
        d.desktopNames["undocked|builtin"]?["6"] = "Nova2"
        d.setDestination(Destination(screen: "external", desktop: 2), for: brain, mode: D)
        #expect(d.rule(brain)?.undocked?.desktop == 6)
        // Yalnız düzen değişince karşılık dokunulmaz.
        d.setDestination(Destination(screen: "external", desktop: 2, layout: .rightHalf), for: brain, mode: D)
        #expect(d.rule(brain)?.undocked?.layout == .leftHalf)
    }

    @Test func unpinClearsMirroredPin() {
        var d = liveShape()
        let id = d.pin(pinRule("Mail"), destination: Destination(screen: "external", desktop: 1), mode: D)
        #expect(d.rule(id)?.undocked != nil)
        d.unpin(id, mode: D)
        #expect(d.rule(id) == nil)
    }

    @Test func mirrorNeverOverwritesExistingOtherModePin() {
        var d = liveShape()
        var rule = pinRule("Mail", undocked: ("builtin", 1))
        rule.docked = nil
        d.rules = [rule]
        d.pin(pinRule("Mail"), destination: Destination(screen: "external", desktop: 1), mode: D)
        #expect(d.rules[0].undocked == Destination(screen: "builtin", desktop: 1))
        d.mirrorPins(forName: "Notes Hub")
        #expect(d.rules[0].undocked == Destination(screen: "builtin", desktop: 1))
    }

    // MARK: Hayaletler

    @Test func ghostCollectsCounterpartNameAndPinsAcrossModes() throws {
        var d = liveShape()
        d.rules = [pinRule("A", docked: ("external", 1), undocked: ("builtin", 5)),
                   pinRule("B", undocked: ("builtin", 5))]
        let made1 = d.ghostDesktop(on: "external", desktop: 1, modes: Mode.allCases)
        let ghost = try #require(made1)
        #expect(ghost.name == "Notes Hub")
        #expect(Set(ghost.pins.map { "\($0.rule.appName)-\($0.mode.rawValue)" })
                == ["A-docked", "A-undocked", "B-undocked"])
        #expect(d.place(mode: U, ofName: "Notes Hub") == nil)
        #expect(d.ghostDesktops.count == 1)
        #expect(d.rules.isEmpty)
    }

    @Test func ghostMergesByNormalizedName() {
        var d = Document()
        d.setDesktopName("AI", screen: "external", desktop: 2, mode: D)
        d.rules = [pinRule("A", docked: ("external", 2))]
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        d.setDesktopName("ai", screen: "external", desktop: 3, mode: D)
        // Ghost "AI" canlı bir masaüstüne ad olarak verilince tüketilir; ayrı
        // test. Burada ikinci silme: önce ghost'u geri getirmeden yeniden oluştur.
        #expect(d.ghostDesktops.isEmpty)
        d.ghostDesktop(on: "external", desktop: 3, modes: Mode.allCases)
        d.rules = [pinRule("B", docked: ("external", 4))]
        d.setDesktopName("AI", screen: "external", desktop: 4, mode: D)
        d.ghostDesktop(on: "external", desktop: 4, modes: Mode.allCases)
        d.rules = [pinRule("C", docked: ("external", 5))]
        d.setDesktopName("Ai", screen: "external", desktop: 5, mode: D)
        d.ghostDesktop(on: "external", desktop: 5, modes: Mode.allCases)
        #expect(d.ghostDesktops.filter { $0.name?.lowercased() == "ai" }.count == 1)
    }

    @Test func ghostConsumedWhenLiveDesktopTakesName() {
        var d = Document()
        d.setDesktopName("AI Setup", screen: "external", desktop: 2, mode: D)
        d.rules = [pinRule("A", docked: ("external", 2))]
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        #expect(d.ghostDesktops.count == 1)
        let ok8 = d.setDesktopName("ai setup", screen: "external", desktop: 1, mode: D)
        #expect(ok8)
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.rules.first?.docked == Destination(screen: "external", desktop: 1))
    }

    @Test func ghostsOnHidesGhostWithoutPinsInMode() throws {
        var d = Document()
        d.rules = [pinRule("A", docked: ("external", 2))]
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        #expect(d.ghosts(on: "external", mode: D).count == 1)
        #expect(d.ghosts(on: "external", mode: U).isEmpty)
        // Adı canlıysa hiçbir kurulumda görünmez.
        var named = Document()
        named.ghostDesktops = [GhostDesktop(screen: "external", name: "X", desktop: 1, deletedAt: Date())]
        #expect(named.ghosts(on: "external", mode: D).count == 1)
        named.desktopNames["undocked|builtin"] = ["2": "x"]
        #expect(named.ghosts(on: "external", mode: D).isEmpty)
    }

    @Test func restoreUnnamedGhostKeepsOtherModePinsInGhost() throws {
        var d = Document()
        let rule = pinRule("A", docked: ("external", 2), undocked: ("builtin", 2))
        d.ghostDesktops = [GhostDesktop(screen: "external", name: nil, desktop: 2, deletedAt: Date(), pins: [
            .init(profileID: d.activeProfileID, mode: D, rule: rule, destination: rule.docked!),
            .init(profileID: d.activeProfileID, mode: U, rule: rule, destination: rule.undocked!),
        ])]
        d.restoreGhost(d.ghostDesktops[0].id, desktop: 4, mode: D)
        #expect(d.rules.first?.docked == Destination(screen: "external", desktop: 4))
        #expect(d.rules.first?.undocked == nil)
        // Öbür kurulumun pini hayalette bekler.
        #expect(d.ghostDesktops.count == 1)
        #expect(d.ghostDesktops.first?.pins.map(\.mode) == [.undocked])
    }

    @Test func restoreRejectsLiveNameAndMovesPins() throws {
        var d = Document()
        d.setDesktopName("Nova", screen: "external", desktop: 2, mode: D)
        d.rules = [pinRule("A", docked: ("external", 2))]
        let made3 = d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        let ghost = try #require(made3)
        // Aynı ad yeniden doğdu (ghost bu arada kalmış gibi): geri getirme ad vermez.
        d.ghostDesktops = [ghost]
        d.desktopNames["docked|external"] = ["1": "nova"]
        d.restoreGhost(ghost.id, desktop: 4, mode: D)
        #expect(names(d, D)["external"] == ["1": "nova"])
        #expect(d.rules.first?.docked == Destination(screen: "external", desktop: 1))
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func restoreDoesNotOverwriteExistingPinNorDuplicateRules() throws {
        var d = Document()
        d.rules = [pinRule("A", docked: ("external", 2))]
        let made4 = d.ghostDesktop(on: "external", desktop: 2, modes: [D])
        let ghost = try #require(made4)
        // Aynı anahtarlı yeni kural (başka kimlikle) başka yere pinli.
        var again = pinRule("A", docked: ("external", 1))
        again.id = "other"
        d.rules = [again]
        d.restoreGhost(ghost.id, desktop: 4, mode: D)
        #expect(d.rules.count == 1)
        #expect(d.rules[0].docked == Destination(screen: "external", desktop: 1))
    }

    @Test func externallyRemovedUsesPinSpaceNumbersWithPendingFiltered() {
        // 2 numaralı kimlik (22) kuyrukta (pinler kaydı) ve gerçekte duruyor;
        // 3 numaralı (33) Mission Control'de silindi: kaymış numara 2.
        let removed = Router.removedOutsideDeskmap(
            before: ["external": [11, 22, 33, 44]], after: ["external": [11, 22, 44]], pending: [22])
        #expect(removed == ["external": [2]])
        // Kuyruktaki silme tek başına dış silme sayılmaz.
        #expect(Router.removedOutsideDeskmap(
            before: ["external": [11, 22, 33]], after: ["external": [11, 22, 33]], pending: [22]).isEmpty)
    }

    @Test func baselineUpdateOnlyRemovesOwnDeletedIds() {
        let known: [String: [UInt64]] = ["external": [11, 22, 33]]
        // 22'yi Deskmap sildi; 33'ü başkası sildi (canlıda yok) ve tabanda kalmalı.
        let next = Router.updatedBaseline(known: known, removed: [22], live: [:])
        #expect(next == ["external": [11, 33]])
        // Kendi eklediği kimlik sıralı eklenir, dış silme yine tabanda.
        let added = Router.updatedBaseline(known: next, removed: [], live: ["external": [11, 99]])
        #expect(added["external"]?.contains(99) == true && added["external"]?.contains(33) == true)
    }

    @Test func ghostNotDuplicatedAfterReconcileAndBaselineBothDetectDelete() {
        var d = Document()
        d.setDesktopName("A", screen: "external", desktop: 2, mode: D, space: 22)
        d.rules = [pinRule("P", docked: ("external", 2))]
        // Taban farkı hayaleti açtı ve adı düşürdü.
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases)
        // Reconcile aynı silmeyi görse de düşecek ad kalmadı.
        let result = d.reconcileNames(spaces: ["external": [11, 33]], seen: [11, 22, 33], mode: D)
        #expect(result.dropped.isEmpty)
        #expect(d.ghostDesktops.count == 1)
        // Ters sıra: reconcile düşürür, Router adla hayalete çevirir, ikinci çağrı birleşir.
        var e = Document()
        e.setDesktopName("A", screen: "external", desktop: 2, mode: D, space: 22)
        e.rules = [pinRule("P", docked: ("external", 2))]
        let r = e.reconcileNames(spaces: ["external": [11, 33]], seen: [11, 22, 33], mode: D)
        for drop in r.dropped {
            e.ghostDesktop(on: drop.place.screen, desktop: drop.place.desktop, modes: Mode.allCases,
                           name: drop.name, droppedSpace: drop.place.space, droppedMode: drop.place.mode)
        }
        e.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases, name: "A")
        #expect(e.ghostDesktops.count == 1)
        #expect(e.ghostDesktops[0].pins.count == 1)
    }

    @Test func droppedNameGhostTakesCounterpartAcrossModes() throws {
        var d = liveShape()
        d.rules = [pinRule("A", undocked: ("builtin", 5))]
        let r = d.reconcileNames(spaces: ["external": [1028]], seen: [1027, 1028], mode: D,
                                 previous: ["external": [1027, 1028]])
        let drop = try #require(r.dropped.first { $0.name == "Notes Hub" })
        d.ghostDesktop(on: drop.place.screen, desktop: drop.place.desktop, modes: Mode.allCases,
                       name: drop.name, droppedSpace: drop.place.space, droppedMode: drop.place.mode)
        #expect(d.place(mode: U, ofName: "Notes Hub") == nil)
        #expect(d.ghostDesktops.first?.pins.map(\.mode) == [.undocked])
    }

    // MARK: Çapraz kurulum silme: tek sefer, doğru slot

    @Test func deferredRemovalDoesNotShiftCounterpartTwice() {
        var d = Document()
        d.desktopNames = ["docked|builtin": ["2": "X"], "undocked|builtin": ["2": "X"]]
        d.desktopNameSpaces = ["docked|builtin": ["2": 7], "undocked|builtin": ["2": 7]]
        d.rules = [pinRule("P", docked: ("builtin", 3))]
        d.setPlannedDesktops(4, mode: D, screen: "builtin")
        d.removeDesktopLater(on: "builtin", desktop: 2, mode: U, existing: true, space: 7)
        // Sıraya girerken öbür kurulumun pinleri ve planı kımıldamaz.
        #expect(d.rules[0].docked?.desktop == 3)
        #expect(d.plannedDesktops(mode: D, screen: "builtin") == 4)
        // Gerçek silme yürüyünce bir kez kayar.
        d.removeDesktop(on: "builtin", desktop: 2, modes: [D], shiftNames: false)
        #expect(d.rules[0].docked?.desktop == 2)
        #expect(d.plannedDesktops(mode: D, screen: "builtin") == 3)
    }

    @Test func ghostUsesCounterpartSlotInOtherSetup() {
        var d = Document()
        // Docked'da X düşmüş (tabloda yok); undocked'da X 1, B 2.
        d.desktopNames = ["undocked|builtin": ["1": "X", "2": "B"]]
        d.desktopNameSpaces = ["undocked|builtin": ["1": 5, "2": 6]]
        d.rules = [pinRule("PX", undocked: ("builtin", 1)), pinRule("PB", undocked: ("builtin", 2))]
        d.ghostDesktop(on: "builtin", desktop: 2, modes: Mode.allCases, name: "X",
                       droppedSpace: 5, droppedMode: D)
        #expect(names(d, U)["builtin"] == ["1": "B"])
        #expect(d.rules.first { $0.appName == "PB" }?.undocked?.desktop == 1)
        #expect(d.ghostDesktops.first?.pins.map(\.rule.appName) == ["PX"])
    }

    @Test func ghostIgnoresOccupantOfDroppedSlot() {
        var d = Document()
        // Docked 2. slotta şimdi B duruyor; düşen X'in undocked karşılığı 3, B'ninki 4.
        d.desktopNames = ["docked|builtin": ["2": "B"], "undocked|builtin": ["3": "X", "4": "B"]]
        d.desktopNameSpaces = ["docked|builtin": ["2": 6], "undocked|builtin": ["3": 5, "4": 6]]
        d.rules = [pinRule("PX", undocked: ("builtin", 3)), pinRule("PB", undocked: ("builtin", 4))]
        d.ghostDesktop(on: "builtin", desktop: 2, modes: Mode.allCases, name: "X",
                       droppedSpace: 5, droppedMode: D)
        #expect(d.ghostDesktops.first?.pins.map(\.rule.appName) == ["PX"])
        #expect(d.rules.first { $0.appName == "PB" }?.undocked?.desktop == 3)
        #expect(names(d, U)["builtin"]?.values.contains("B") == true)
        #expect(names(d, D)["builtin"]?["2"] == "B")
    }
}
