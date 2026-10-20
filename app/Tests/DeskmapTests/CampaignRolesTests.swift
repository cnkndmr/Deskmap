import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya: monitör rolleri (K5 takas, K6 sıranın sonuna ekle / yerine geç,
/// K9 tanınan monitörler, unut, öğrenme, soluk kart verisi). Kenar durumlar
/// ve alanlar arası etkileşimler; `DisplayRolesTests`'in kopyası değil.
struct CampaignRolesPureTests {

    private typealias Display = DisplayRoles.Display
    private typealias Pair = (role: String, uuid: String)

    private func pairs(_ list: [(String, String)]) -> [Pair] { list.map { (role: $0.0, uuid: $0.1) } }

    /// Roller soldan sağa öğrenilmiş bellek: external=A, external-2=B ...
    private func learnedMemory(_ uuids: [String]) -> DisplayRoles {
        var memory = DisplayRoles()
        let assignment = uuids.enumerated().map { (role: DisplayRoles.externalRole($0.offset + 1), uuid: $0.element) }
        memory = memory.learning(assignment)
        return memory
    }

    private func current(_ memory: DisplayRoles, _ uuids: [String]) -> [Pair] {
        let displays = uuids.enumerated().map { Display(uuid: $0.element, minX: CGFloat($0.offset) * 1000, minY: 0, name: "M") }
        return memory.assign(displays).map { (role: $0.role, uuid: $0.display.uuid) }
    }

    // MARK: K5 takas

    @Test func K5_swapBetweenTwoConnectedMonitorsKeepsEachInItsOwnSingleSlot() {
        let memory = learnedMemory(["A", "B"])
        let swapped = memory.choosing("B", for: "external", current: current(memory, ["A", "B"]))
        #expect(swapped.remembered == ["external": ["B"], "external-2": ["A"]])
    }

    @Test func K5_choosingAnAwayMonitorSwapsWithTheConnectedOccupant() {
        // C bağlı değil ama external-2'de hatırlanıyor; A bağlı ve external'da.
        var memory = learnedMemory(["A", "C"])
        memory = memory.learning([(role: "external", uuid: "A")])
        let swapped = memory.choosing("C", for: "external", current: pairs([("external", "A")]))
        #expect(swapped.remembered == ["external": ["C"], "external-2": ["A"]])
        #expect(swapped.role(of: "A") == "external-2")
    }

    @Test func K5_chosenMonitorWithoutAnyRoleForgetsTheOldOccupant() {
        let memory = learnedMemory(["A"])
        // N bağlı değil, hiçbir yerde yok: A'nın yerine geçerse A unutulur (yer verilecek rol yok).
        let result = memory.choosing("N", for: "external", current: [])
        #expect(result.remembered == ["external": ["N"]])
        #expect(result.role(of: "A") == nil)
    }

    @Test func K6_replaceKeepsTheReplacedMonitorInHistoryWhenNewOneTakesItsRoleAlone() {
        // N tek başına external olarak bağlı (A takılı değil): N, A'nın yerine geçer,
        // A silinmez, geçmişte N'in arkasında kalır (masa değişimi).
        let memory = learnedMemory(["A"])
        let result = memory.choosing("N", for: "external", current: pairs([("external", "N")]))
        #expect(result.remembered == ["external": ["N", "A"]])
    }

    @Test func K5_selectingTheMonitorThatAlreadyHoldsTheRoleDoesNotReorderOthers() {
        let memory = learnedMemory(["A", "B", "C"])
        let cur = current(memory, ["A", "B", "C"])
        let same = memory.choosing("B", for: "external-2", current: cur)
        #expect(same.remembered == memory.remembered)
    }

    @Test func K5_threeMonitorsOnlyTheTwoSwappedMove() {
        let memory = learnedMemory(["A", "B", "C"])
        let result = memory.choosing("C", for: "external", current: current(memory, ["A", "B", "C"]))
        #expect(result.remembered == ["external": ["C"], "external-2": ["B"], "external-3": ["A"]])
    }

    @Test func K5_swapAcceptsBracedLowercaseUUIDs() {
        let memory = learnedMemory(["AAAA-1", "BBBB-2"])
        let cur = current(memory, ["AAAA-1", "BBBB-2"])
        let result = memory.choosing("{bbbb-2}", for: "external", current: cur)
        #expect(result.role(of: "BBBB-2") == "external")
        #expect(result.role(of: "AAAA-1") == "external-2")
    }

    @Test func K5_swappingTwiceRestoresTheOriginalAssignment() {
        let memory = learnedMemory(["A", "B"])
        let once = memory.choosing("B", for: "external", current: current(memory, ["A", "B"]))
        let twice = once.choosing("B", for: "external-2", current: current(once, ["A", "B"]))
        #expect(twice.remembered == memory.remembered)
    }

    @Test func K5_choosingOnAFreshDocumentMarksItAsLearned() {
        let result = DisplayRoles().choosing("A", for: "external", current: pairs([("external", "A")]))
        #expect(result.learnedOnce)
        #expect(result.remembered == ["external": ["A"]])
    }

    @Test func K5_swapMovesDesktopCountAndNameLookupWithTheMonitor() {
        var memory = learnedMemory(["A", "B"])
        memory = memory.learningDesktopCounts(["external": 5, "external-2": 2],
                                              assignment: pairs([("external", "A"), ("external-2", "B")]),
                                              names: ["A": "Dell", "B": "LG"])
        #expect(memory.lastDesktopCount(role: "external") == 5)
        let swapped = memory.choosing("B", for: "external", current: pairs([("external", "A"), ("external-2", "B")]))
        // Sayı monitöre bağlı: rolün soluk kartı artık B'nin sayısını çizer.
        #expect(swapped.lastDesktopCount(role: "external") == 2)
        #expect(swapped.lastDesktopCount(role: "external-2") == 5)
        #expect(swapped.monitorNames == ["A": "Dell", "B": "LG"])
    }

    // MARK: K6 sıranın sonuna ekle

    @Test func K6_nextFreeRoleOnAnUnlearnedDocumentSkipsConfirmedConnected() {
        // Öğrenmeden önce her şey onaylı: bağlı external dolu sayılır.
        #expect(DisplayRoles().nextFreeRole(connected: pairs([("external", "X")])) == "external-2")
        #expect(DisplayRoles().nextFreeRole(connected: []) == "external")
    }

    @Test func K6_nextFreeRoleFillsTheGapLeftByAnAwayMonitor() {
        // external ve external-3 hatırlanıyor; boşluk external-2.
        var memory = learnedMemory(["A", "B", "C"])
        memory = memory.forgetting("B")
        #expect(memory.nextFreeRole(connected: pairs([("external", "A")])) == "external-2")
    }

    @Test func K6_nextFreeRoleIgnoresUnconfirmedConnectedRoles() {
        let memory = learnedMemory(["A"])
        // N, external-2'de takılı ama onaysız: o rol hâlâ boş sayılır, N kendi yerini alır.
        #expect(memory.nextFreeRole(connected: pairs([("external", "A"), ("external-2", "N")])) == "external-2")
    }

    @Test func K6_nextFreeRoleSkipsAwayRemembered() {
        let memory = learnedMemory(["A", "B"])
        // Yalnız N bağlı (external'a oturmuş, onaysız): A ve B uzakta, ikisinin rolü de dolu.
        #expect(memory.nextFreeRole(connected: pairs([("external", "N")])) == "external-3")
    }

    @Test func K6_addToEndThenConfirmedLeavesAllExistingRolesUntouched() {
        let memory = learnedMemory(["A", "B"])
        let role = memory.nextFreeRole(connected: pairs([("external", "A"), ("external-2", "B"), ("external-3", "N")]))
        #expect(role == "external-3")
        let added = memory.choosing("N", for: role, current: pairs([("external", "A"), ("external-2", "B"), ("external-3", "N")]))
        #expect(added.remembered == ["external": ["A"], "external-2": ["B"], "external-3": ["N"]])
    }

    // MARK: K9 tanınan monitörler

    @Test func K9_knownMonitorsExcludesUnconfirmedConnectedNew() {
        let memory = learnedMemory(["A"])
        let known = memory.knownMonitors(connected: pairs([("external", "A"), ("external-2", "N")]))
        #expect(known.map(\.uuid) == ["A"])
    }

    @Test func K9_knownMonitorsListsAwayOnesInRoleOrder() {
        let memory = learnedMemory(["A", "B", "C"])
        let known = memory.knownMonitors(connected: pairs([("external-2", "B")]))
        #expect(known.map(\.role) == ["external", "external-2", "external-3"])
        #expect(known.map(\.uuid) == ["A", "B", "C"])
    }

    @Test func K9_awayRoleListsOnlyItsNewestMonitor() {
        var memory = learnedMemory(["OLD"])
        memory = memory.choosing("NEW", for: "external", current: pairs([("external", "NEW")]))
        let known = memory.knownMonitors(connected: [])
        #expect(known.map(\.uuid) == ["NEW"])
    }

    @Test func K9_beforeFirstLearningConnectedMonitorsAreAllKnown() {
        let known = DisplayRoles().knownMonitors(connected: pairs([("external", "X"), ("external-2", "Y")]))
        #expect(known.map(\.uuid) == ["X", "Y"])
    }

    @Test func K9_knownMonitorsIgnoresBuiltinPair() {
        let memory = learnedMemory(["A"])
        let known = memory.knownMonitors(connected: pairs([("builtin", "BUILTIN"), ("external", "A")]))
        #expect(known.map(\.role) == ["external"])
    }

    @Test func K9_recognisedMonitorSittingOnTheWrongRoleStillAppearsInTheMenu() {
        // A ve B ikisi de external'da hatırlanıyor (B en yeni). İkisi de bağlı:
        // B external, A boş external-2'ye oturur ama orada onaysız. A tanınan
        // bir monitör; B'nin kartındaki menüde görünmeli (K9: en az bir kez takılmış).
        var memory = learnedMemory(["A"])
        memory = memory.choosing("B", for: "external", current: pairs([("external", "B")]))
        let cur = current(memory, ["A", "B"])
        #expect(Set(cur.map(\.role)) == ["external", "external-2"])
        let known = memory.knownMonitors(connected: cur)
        #expect(Set(known.map(\.uuid)).contains("A"))
        #expect(known.map(\.uuid).filter { $0 == "A" }.count == 1)
    }

    // MARK: Unutma

    @Test func forgetting_removesOneMonitorAndKeepsLearnedOnceAndOthers() {
        let memory = learnedMemory(["A", "B"])
        let forgotten = memory.forgetting("A")
        #expect(forgotten.remembered == ["external-2": ["B"]])
        #expect(forgotten.learnedOnce)
        // Bağlıysa rolü onay bekler.
        #expect(forgotten.unconfirmed(pairs([("external", "A"), ("external-2", "B")])) == ["external"])
    }

    @Test func forgetting_isCaseAndBraceInsensitiveAndIdempotent() {
        let memory = learnedMemory(["AB-1"])
        let once = memory.forgetting("{ab-1}")
        #expect(once.remembered.isEmpty)
        #expect(once.forgetting("AB-1") == once)
        #expect(memory.forgetting("UNKNOWN") == memory)
    }

    @Test func forgetting_removesTheUUIDFromEveryHistoryList() {
        var memory = learnedMemory(["A"])
        memory = memory.choosing("B", for: "external", current: pairs([("external", "B")]))
        #expect(memory.remembered["external"] == ["B", "A"])
        #expect(memory.forgetting("A").remembered == ["external": ["B"]])
    }

    @Test func forgetting_keepsDesktopCountAndNameForALaterReplug() {
        var memory = learnedMemory(["A"])
        memory = memory.learningDesktopCounts(["external": 4], assignment: pairs([("external", "A")]),
                                              names: ["A": "Dell"])
        let forgotten = memory.forgetting("A")
        #expect(forgotten.lastDesktopCount["A"] == 4)
        #expect(forgotten.monitorNames["A"] == "Dell")
        // Rolü kalmadığı için soluk kart sayısı rolden okunamaz.
        #expect(forgotten.lastDesktopCount(role: "external") == nil)
    }

    // MARK: Öğrenme

    @Test func learning_unconfirmedPairIsNotBoundAfterFirstLearning() {
        let memory = learnedMemory(["A"])
        let result = memory.learning(pairs([("external", "A"), ("external-2", "N")]))
        #expect(result.remembered == ["external": ["A"]])
    }

    @Test func learning_emptyOrBuiltinOnlyAssignmentDoesNotMarkLearned() {
        #expect(!DisplayRoles().learning([]).learnedOnce)
        #expect(!DisplayRoles().learning(pairs([("builtin", "BUILTIN")])).learnedOnce)
        #expect(DisplayRoles().learning(pairs([("builtin", "BUILTIN")])).remembered.isEmpty)
    }

    @Test func learning_firstConnectionBindsEverythingByPosition() {
        let result = DisplayRoles().learning(pairs([("external", "A"), ("external-2", "B"), ("external-3", "C")]))
        #expect(result.remembered == ["external": ["A"], "external-2": ["B"], "external-3": ["C"]])
        #expect(result.learnedOnce)
    }

    @Test func learning_twoConnectedRememberedForTheSameRoleOnlyTheWinnerStaysConfirmed() {
        var memory = learnedMemory(["A"])
        memory = memory.choosing("B", for: "external", current: pairs([("external", "B")]))
        let cur = current(memory, ["A", "B"])
        let result = memory.learning(cur)
        // Kaybeden A kendiliğinden başka role bağlanmaz.
        #expect(result.remembered == memory.remembered)
        #expect(result.unconfirmed(cur).count == 1)
    }

    @Test func learning_isIdempotent() {
        let memory = learnedMemory(["A", "B"])
        let cur = current(memory, ["A", "B"])
        #expect(memory.learning(cur) == memory)
    }

    @Test func learning_historyIsCappedAtLimitWhenManyMonitorsTakeTheSlot() {
        var memory = learnedMemory(["M0"])
        for i in 1...12 {
            memory = memory.choosing("M\(i)", for: "external", current: pairs([("external", "M\(i)")]))
        }
        #expect(memory.remembered["external"]?.count == DisplayRoles.historyLimit)
        #expect(memory.remembered["external"]?.first == "M12")
        #expect(memory.role(of: "M0") == nil)
    }

    // MARK: Masaüstü sayısı ve model adı

    @Test func counts_unconfirmedMonitorIsNotLearned() {
        let memory = learnedMemory(["A"])
        let result = memory.learningDesktopCounts(["external": 3, "external-2": 6],
                                                  assignment: pairs([("external", "A"), ("external-2", "N")]),
                                                  names: ["N": "Stranger", "A": "Dell"])
        #expect(result.lastDesktopCount == ["A": 3])
        #expect(result.monitorNames == ["A": "Dell"])
    }

    @Test func counts_zeroCountIsIgnoredButNameIsStored() {
        let memory = learnedMemory(["A"])
        let result = memory.learningDesktopCounts(["external": 0], assignment: pairs([("external", "A")]),
                                                  names: ["A": "Dell"])
        #expect(result.lastDesktopCount.isEmpty)
        #expect(result.monitorNames == ["A": "Dell"])
    }

    @Test func counts_emptyNameDoesNotOverwriteAStoredName() {
        var memory = learnedMemory(["A"])
        memory = memory.learningDesktopCounts([:], assignment: pairs([("external", "A")]), names: ["A": "Dell"])
        let result = memory.learningDesktopCounts([:], assignment: pairs([("external", "A")]), names: ["A": ""])
        #expect(result.monitorNames == ["A": "Dell"])
    }

    @Test func counts_keyedByNormalizedUUIDAndNameLookupAcceptsRawOrNormalized() {
        let memory = learnedMemory(["ab-12"])
        let result = memory.learningDesktopCounts(["external": 2], assignment: pairs([("external", "{ab-12}")]),
                                                  names: ["{ab-12}": "LG"])
        let key = ScreenInfo.normalize("{ab-12}")
        #expect(result.lastDesktopCount[key] == 2)
        #expect(result.monitorNames[key] == "LG")
        #expect(result.lastDesktopCount(role: "external") == 2)
    }

    @Test func counts_builtinPairIsIgnored() {
        let result = DisplayRoles().learningDesktopCounts(["builtin": 4], assignment: pairs([("builtin", "BUILTIN")]),
                                                          names: ["BUILTIN": "Laptop"])
        #expect(result.lastDesktopCount.isEmpty)
        #expect(result.monitorNames.isEmpty)
    }

    @Test func counts_codableDropsBadValuesAndOmitsEmptyFields() throws {
        let json = #"{"remembered":{"external":["{aa}"]},"lastDesktopCount":{"{AA}":3,"BB":0},"monitorNames":{"{AA}":"Dell","BB":""}}"#
        let decoded = try JSONDecoder().decode(DisplayRoles.self, from: Data(json.utf8))
        let key = ScreenInfo.normalize("{AA}")
        #expect(decoded.lastDesktopCount == [key: 3])
        #expect(decoded.monitorNames == [key: "Dell"])
        let empty = String(decoding: try JSONEncoder().encode(DisplayRoles()), as: UTF8.self)
        #expect(!empty.contains("lastDesktopCount") && !empty.contains("monitorNames"))
    }

    // MARK: choosableRoles, atama

    @Test func choosableRoles_countsConnectedPlusAwayMonitors() {
        let memory = learnedMemory(["A", "B", "C"])
        // N tanınmıyor; B ve C uzakta: 2 bağlı + 2 uzak = 4 rol.
        #expect(memory.choosableRoles(connected: pairs([("external", "A"), ("external-2", "N")]))
                == ["external", "external-2", "external-3", "external-4"])
        #expect(memory.choosableRoles(connected: []) == ["external", "external-2", "external-3"])
        #expect(DisplayRoles().choosableRoles(connected: []).isEmpty)
    }

    @Test func assign_gapsInRolesAreFilledSmallestFirstByPosition() {
        var memory = learnedMemory(["A", "B", "C", "D"])
        memory = memory.forgetting("B")
        let displays = [Display(uuid: "A", minX: 0, minY: 0, name: "m"),
                        Display(uuid: "N", minX: -500, minY: 0, name: "m"),
                        Display(uuid: "C", minX: 1000, minY: 0, name: "m"),
                        Display(uuid: "D", minX: 2000, minY: 0, name: "m")]
        let result = Dictionary(uniqueKeysWithValues: memory.assign(displays).map { ($0.display.uuid, $0.role) })
        #expect(result == ["A": "external", "N": "external-2", "C": "external-3", "D": "external-4"])
    }

    @Test func assign_twoNewMonitorsFillGapsInPositionOrder() {
        let memory = learnedMemory(["A"])
        let displays = [Display(uuid: "N2", minX: 3000, minY: 0, name: "m"),
                        Display(uuid: "A", minX: 0, minY: 0, name: "m"),
                        Display(uuid: "N1", minX: 1000, minY: 0, name: "m")]
        let result = Dictionary(uniqueKeysWithValues: memory.assign(displays).map { ($0.display.uuid, $0.role) })
        #expect(result == ["A": "external", "N1": "external-2", "N2": "external-3"])
    }

    @Test func labels_threeIdenticalNamesGetNumbersInPositionOrder() {
        let list = [Display(uuid: "c", minX: 2000, minY: 0, name: "LG"),
                    Display(uuid: "a", minX: 0, minY: 0, name: "LG"),
                    Display(uuid: "b", minX: 1000, minY: 0, name: "LG"),
                    Display(uuid: "d", minX: 500, minY: 0, name: "Dell")]
        let labels = DisplayRoles.labels(list)
        #expect(labels["a"] == "LG (1)" && labels["b"] == "LG (2)" && labels["c"] == "LG (3)")
        #expect(labels["d"] == "Dell")
    }
}

// MARK: - ScreenService + Store

@MainActor
struct CampaignRolesServiceTests {

    private static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Built-in", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))

    private static func external(_ uuid: String, x: CGFloat, name: String = "Monitor") -> ScreenService.RawDisplay {
        .init(uuid: uuid, name: name, isBuiltin: false,
              frame: CGRect(x: x, y: 1112, width: 1920, height: 1080),
              visibleFrame: CGRect(x: x, y: 1112, width: 1920, height: 1050))
    }

    private final class Source { var list: [ScreenService.RawDisplay] = [] }

    @MainActor private struct Rig {
        let source = Source()
        let service: ScreenService
        let store: Store
        let sync: [AnyCancellable]

        init(_ list: [ScreenService.RawDisplay], document: Document = Document()) {
            source.list = list
            let source = source
            service = ScreenService(displays: { source.list })
            store = Store(demo: document)
            sync = AppModel.syncDisplayRoles(store: store, screens: service)
        }

        func change(_ list: [ScreenService.RawDisplay]) {
            source.list = list
            service.simulateChangeForTesting(settle: true)
        }

        var pairs: [(role: String, uuid: String)] {
            service.connectedExternals.map { (role: $0.role, uuid: $0.display.uuid) }
        }

        func role(_ uuid: String) -> String? { service.screens.first { $0.uuid == uuid }?.id }
    }

    // MARK: Öğrenme sırası

    @Test func learning_choiceMadeBeforeASettleIsNotOverwrittenByTheNextSettle() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        // Ardından gelen bir ekran değişimi yatışınca seçim bozulmamalı.
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        #expect(rig.role("B") == "external")
        #expect(rig.role("A") == "external-2")
        #expect(rig.store.document.displayRoles.remembered == ["external": ["B"], "external-2": ["A"]])
    }

    @Test func learning_forgetThenChooseThenSettleKeepsExactlyTheChoice() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920), Self.external("C", x: 3840)])
        rig.store.forgetDisplayRoles()
        rig.store.chooseDisplay("C", for: "external", current: rig.pairs)
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920), Self.external("C", x: 3840)])
        #expect(rig.service.roles == rig.store.document.displayRoles)
        #expect(rig.role("C") == "external")
    }

    @Test func forgetAll_clearsLearnedOnceSoNothingIsHeldAfterwards() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0)])
        #expect(rig.service.heldRoles.isEmpty)
        rig.store.forgetDisplayRoles()
        #expect(!rig.store.document.displayRoles.learnedOnce || rig.store.document.displayRoles.remembered.count == 1)
        // Unuttuktan sonra ilk yatışma yeniden öğrenir; hiçbir rol bekletilmez.
        rig.change([Self.builtin, Self.external("A", x: 0)])
        #expect(rig.service.heldRoles.isEmpty)
        #expect(rig.store.document.displayRoles.remembered == ["external": ["A"]])
    }

    @Test func forgetDisplay_connectedMonitorBecomesHeldAndUsableRolesDropIt() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        rig.store.forgetDisplay("B")
        #expect(rig.service.heldRoles == ["external-2"])
        #expect(rig.service.usableRoles == ["builtin", "external"])
        // Yatışınca B kendiliğinden geri öğrenilmez.
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        #expect(rig.store.document.displayRoles.role(of: "B") == nil)
        #expect(rig.service.heldRoles == ["external-2"])
    }

    @Test func heldRoles_newMonitorOnTheRightIsHeldAndTheKnownOneStaysUsable() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0)])
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("N", x: 1920)])
        #expect(rig.role("N") == "external-2")
        #expect(rig.service.heldRoles == ["external-2"])
        #expect(rig.store.document.displayRoles.role(of: "N") == nil)
    }

    @Test func heldRoles_newMonitorAloneTakesTheFirstRoleButIsHeld() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0)])
        rig.change([Self.builtin, Self.external("N", x: 0)])
        #expect(rig.role("N") == "external")
        #expect(rig.service.heldRoles == ["external"])
        // Yedek bile ona taşımaz: kullanılabilir harici rol yok.
        let resolved = Routing.resolvePlace([Destination(screen: "external", desktop: 2)],
                                            connected: rig.service.screens.map(\.id),
                                            held: rig.service.heldRoles)
        #expect(resolved == nil)
    }

    @Test func K6_replaceMakesTheNewMonitorInheritTheKnownMonitorsRoleAndPins() {
        var document = Document()
        document.rules = [Rule(id: "r", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                               docked: Destination(screen: "external", desktop: 2))]
        let rig = Rig([Self.builtin, Self.external("A", x: 0)], document: document)
        rig.change([Self.builtin, Self.external("N", x: 0)])
        #expect(rig.service.heldRoles == ["external"])
        rig.store.chooseDisplay("N", for: "external", current: rig.pairs)
        #expect(rig.service.heldRoles.isEmpty)
        #expect(rig.store.document.rules[0].docked == Destination(screen: "external", desktop: 2))
        #expect(rig.store.document.displayRoles.remembered["external"] == ["N", "A"])
        // A geri gelince N'in arkasında kalır: yine tanınır ama external'ı N tutar.
        rig.change([Self.builtin, Self.external("N", x: 0), Self.external("A", x: 1920)])
        #expect(rig.role("N") == "external")
        #expect(rig.role("A") == "external-2")
    }

    // MARK: Takas: planlar ve pinler rolle gider

    @Test func K5_swapKeepsPlansPinsAndNextPlacesOnTheRoleWhileTheMonitorMoves() {
        var document = Document()
        document.plans = DesktopPlans(docked: ["external": ["Mail", "Web"], "external-2": ["Chat"]])
        document.rules = [Rule(id: "r", appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                               docked: Destination(screen: "external", desktop: 2),
                               dockedNext: [Destination(screen: "external-2", desktop: 1)])]
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)], document: document)
        let plansBefore = rig.store.document.plans
        let rulesBefore = rig.store.document.rules
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        #expect(rig.store.document.plans == plansBefore)
        #expect(rig.store.document.rules == rulesBefore)
        // "external" rolü artık B monitöründe: pin ve plan onunla gider.
        #expect(rig.role("B") == "external")
        #expect(rig.role("A") == "external-2")
        #expect(rig.service.heldRoles.isEmpty)
    }

    @Test func K5_swapBetweenMonitorsThenUnplugKeepsEachRoleOfTheOther() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        rig.change([Self.builtin, Self.external("A", x: 0)])
        // A tek başına: external-2 olarak kalır, external boş.
        #expect(rig.service.screens.map(\.id) == ["builtin", "external-2"])
        #expect(rig.service.heldRoles.isEmpty)
    }

    @Test func K5_swapWithAwayMonitorTakesEffectWhenItIsPluggedIn() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        rig.change([Self.builtin, Self.external("A", x: 0)])
        // B takılı değil iken kartından seçim (K9): B external olsun.
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        #expect(rig.store.document.displayRoles.remembered == ["external": ["B"], "external-2": ["A"]])
        #expect(rig.role("A") == "external-2")
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        #expect(rig.role("B") == "external")
        #expect(rig.service.heldRoles.isEmpty)
    }

    // MARK: Test ekranı

    @Test func testDisplay_numberedSuffixesAreNeverLearnedNorHeld() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0),
                       Self.external("T1", x: 1920, name: "\(Store.testDisplayName) (1)"),
                       Self.external("T2", x: 3840, name: "\(Store.testDisplayName) (2)")])
        #expect(rig.store.document.displayRoles.remembered == ["external": ["A"]])
        #expect(rig.service.externalAssignment.map(\.uuid) == ["A"])
        #expect(rig.service.heldRoles.isEmpty)
    }

    @Test func testDisplay_aloneLeavesTheDocumentUnlearnedEvenAfterManySettles() {
        let rig = Rig([Self.builtin, Self.external("T", x: 0, name: Store.testDisplayName)])
        for _ in 0..<3 { rig.change([Self.builtin, Self.external("T", x: 0, name: Store.testDisplayName)]) }
        #expect(rig.store.document.displayRoles == DisplayRoles())
        #expect(rig.service.heldRoles.isEmpty)
    }

    @Test func testDisplay_lookalikeNameWithoutParenthesisIsARealMonitor() {
        #expect(!Store.isTestDisplay("Deskmap Test Display 2", learning: false))
        #expect(!Store.isTestDisplay("My Deskmap Test Display", learning: false))
        #expect(Store.isTestDisplay("Deskmap Test Display (12)", learning: false))
        #expect(!Store.isTestDisplay("Deskmap Test Display (1)", learning: true))
    }

    @Test func testDisplay_realMonitorIsNotPushedToASecondRoleByATestDisplayOnItsLeft() {
        // Kanca testinin sanal ekranı gerçek monitörün solunda: rol atamada
        // sıradan harici ekran sayılır (T=external, A=external-2); sözleşme
        // yalnız test ekranının hiç öğrenilmemesini ister (bug-tables §D).
        let rig = Rig([Self.builtin,
                       Self.external("T", x: -2000, name: Store.testDisplayName),
                       Self.external("A", x: 0)])
        #expect(rig.store.document.displayRoles.remembered == ["external-2": ["A"]])
        #expect(rig.store.document.displayRoles.remembered.values.flatMap { $0 }.contains("T") == false)
    }

    // MARK: Aynı UUID, 3+ monitör

    @Test func duplicateUUID_pairedMonitorsCountOnceAndGetOneRole() {
        let rig = Rig([Self.builtin, Self.external("TWIN", x: 0), Self.external("TWIN", x: 1920),
                       Self.external("B", x: 3840)])
        #expect(rig.service.screens.map(\.id) == ["builtin", "external", "external-2"])
        #expect(rig.store.document.displayRoles.remembered.values.flatMap { $0 }.sorted() == ["B", "TWIN"])
    }

    @Test func duplicateUUID_braceAndCaseVariantsAreTheSameMonitor() {
        let rig = Rig([Self.builtin, Self.external("ab-12", x: 0), Self.external("{AB-12}", x: 1920)])
        #expect(rig.service.screens.filter { !$0.isBuiltin }.count == 1)
    }

    @Test func fourMonitors_unplugMiddleOnesAndReplugKeepsEveryRole() {
        let all = [Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920),
                   Self.external("C", x: 3840), Self.external("D", x: 5760)]
        let rig = Rig(all)
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("D", x: 5760)])
        #expect(rig.role("A") == "external")
        #expect(rig.role("D") == "external-4")
        #expect(rig.service.heldRoles.isEmpty)
        // Ters sırada geri tak.
        rig.change([Self.builtin, Self.external("D", x: 0), Self.external("C", x: 1920),
                    Self.external("B", x: 3840), Self.external("A", x: 5760)])
        #expect(["A": rig.role("A"), "B": rig.role("B"), "C": rig.role("C"), "D": rig.role("D")]
                == ["A": "external", "B": "external-2", "C": "external-3", "D": "external-4"])
    }

    @Test func fourMonitors_newFifthFillsTheGapButIsHeldWithoutDisturbingTheOthers() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920),
                       Self.external("C", x: 3840)])
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("C", x: 3840)])
        rig.change([Self.builtin, Self.external("N", x: -100), Self.external("A", x: 0), Self.external("C", x: 3840)])
        #expect(rig.role("A") == "external")
        #expect(rig.role("C") == "external-3")
        #expect(rig.role("N") == "external-2")
        #expect(rig.service.heldRoles == ["external-2"])
    }

    // MARK: Soluk kart verisi (ScreenService zinciri)

    @Test func learnDesktopCounts_storeMergesNamesAndSkipsHeldMonitors() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0)])
        rig.change([Self.builtin, Self.external("A", x: 0), Self.external("N", x: 1920)])
        rig.store.learnDesktopCounts(["external": 4, "external-2": 9], assignment: rig.service.externalAssignment,
                                     names: ["A": "Dell U2720Q", "N": "Unknown Brand"])
        let roles = rig.store.document.displayRoles
        #expect(roles.lastDesktopCount == ["A": 4])
        #expect(roles.monitorNames == ["A": "Dell U2720Q"])
    }

    @Test func learnDesktopCounts_isANoOpWhenNothingChanges() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0)])
        rig.store.learnDesktopCounts(["external": 4], assignment: rig.service.externalAssignment, names: ["A": "Dell"])
        let before = rig.store.document.displayRoles
        rig.store.learnDesktopCounts(["external": 4], assignment: rig.service.externalAssignment, names: ["A": "Dell"])
        #expect(rig.store.document.displayRoles == before)
    }

    @Test func settled_isSentOnceForARoleChangeAndNotForAnIdenticalChoice() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        var count = 0
        let watch = rig.service.settled.sink { count += 1 }
        defer { _ = watch }
        rig.store.chooseDisplay("A", for: "external", current: rig.pairs)
        #expect(count == 0)
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        #expect(count == 1)
    }

    @Test func roles_changeWhileSettlingWaitsForTheSettleToApply() {
        let rig = Rig([Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)])
        rig.source.list = [Self.builtin, Self.external("A", x: 0), Self.external("B", x: 1920)]
        rig.service.simulateChangeForTesting(settle: false)
        #expect(rig.service.isSettling)
        rig.store.chooseDisplay("B", for: "external", current: rig.pairs)
        // Yatışırken roller hemen değişmez; yatışınca uygulanır.
        #expect(rig.role("B") == "external-2")
        rig.service.simulateChangeForTesting(settle: true)
        #expect(rig.role("B") == "external")
    }
}
