import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Ana harici monitör hatası (Faz 1): işlem × durum tablosu
/// docs/bug-tables.md §A (her hücrede test adı). Roller `DisplayRoles`
/// üzerinden (UUID ile kalıcı, gece-deskmap-c); onay bekleyen rol
/// (`DisplayRoles.unconfirmed`) planın ve kuralların dışında
/// (`PlanApply.holding`). Gerçek pencere taşınmaz, ekranlar ve
/// masaüstüleri sahte.
///
/// Ortam (15.10 denemesinin günlüğünden, nötr adlarla): dahili ekran
/// (0, 0); geniş monitör "Wide" solda ve üstte (minX −1686); sanal ekran
/// "Virtual" dahilinin sağında (minX 1710). Sanal ekran denemede iki kez
/// kapanıp yeniden açıldı.
struct PrimaryExternalBugTests {

    private typealias Display = DisplayRoles.Display

    private let wide = Display(uuid: "WIDE-0001", minX: -1686, minY: 1112, name: "Wide")
    private let virtual = Display(uuid: "VIRTUAL-0002", minX: 1710, minY: 0, name: "Virtual")

    private func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }

    private func at(_ d: Display, x: CGFloat) -> Display {
        Display(uuid: d.uuid, minX: x, minY: d.minY, name: d.name)
    }

    private func pairs(_ memory: DisplayRoles, _ list: [Display]) -> [(role: String, uuid: String)] {
        memory.assign(list).map { (role: $0.role, uuid: $0.display.uuid) }
    }

    private func roles(_ memory: DisplayRoles, _ list: [Display]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: memory.assign(list).map { ($0.display.uuid, $0.role) })
    }

    private func learned(_ list: [Display], _ memory: DisplayRoles = DisplayRoles()) -> DisplayRoles {
        memory.learning(pairs(memory, list))
    }

    /// Monitördeki üç adlı masaüstü (space 101–103), her birinde bir pencere;
    /// plan `external` rolünde. `externalSpaces`: şu an `external` rolünü
    /// alan ekranın masaüstüleri; `others`: öbür harici ekran.
    private func input(externalSpaces: [UInt64], others: [UInt64]?) -> PlanApply.Input {
        var live: [String: [UInt64]] = ["builtin": [1, 2], "external": externalSpaces]
        if let others { live["external-2"] = others }
        return PlanApply.Input(
            mode: .docked, live: live,
            contents: [101: [11], 102: [12], 103: [13], 201: []],
            names: [n("ALPHA", 101), n("BETA", 102), n("GAMMA", 103)],
            plans: ["external": ["ALPHA", "BETA", "GAMMA"]],
            compactBeyondPlan: true)
    }

    // MARK: - A1 · Sanal ekran takıldı (seçim yok)

    /// A1-a: sanal ekran monitörün sağında: monitör `external` kalır.
    @Test func virtualRightOfMonitorKeepsMonitorExternal() {
        let memory = learned([wide])
        #expect(roles(memory, [wide, virtual]) == ["WIDE-0001": "external", "VIRTUAL-0002": "external-2"])
    }

    /// A1-b: sanal ekran monitörün soluna konsa da `external` monitörde
    /// kalır (rol UUID'den, konumdan değil). Eskiden bu test main'in
    /// konum sırasını (`ScreenService.externalOrder`) ölçüyordu.
    @Test func virtualLeftOfMonitorDoesNotStealExternalRole() {
        let memory = learned([wide])
        let assignment = pairs(memory, [wide, at(virtual, x: -3606)])
        #expect(Dictionary(uniqueKeysWithValues: assignment.map { ($0.uuid, $0.role) })
                == ["WIDE-0001": "external", "VIRTUAL-0002": "external-2"])
        // Sanal ekran hatırlanmıyor: kendi rolü (external-2) de onay bekler.
        #expect(memory.unconfirmed(assignment) == ["external-2"])
    }

    // MARK: - A2 · Doğru roller: plan sessiz

    @Test func correctRolesNeedNoWork() {
        let memory = learned([wide, virtual])
        #expect(memory.unconfirmed(pairs(memory, [wide, virtual])).isEmpty)
        let out = PlanApply.compute(input(externalSpaces: [101, 102, 103], others: [201]))
        #expect(out.isEmpty)
    }

    // MARK: - A3 · Rol yer değiştirdi

    /// A3-a: kendiliğinden rol değişimi. İkisi de `external`da hatırlanıyor,
    /// sanal ekran daha yeni: ikisi bağlıyken monitör `external-2`ye düşer.
    /// Bu atama onaysız: `external-2` bekler, monitörün adlı masaüstüleri
    /// ne taşınır ne yeniden bağlanır ne silinir. (Sanal ekran `external`
    /// rolünde onaylı: planın masaüstü sayısı ona uygulanır, boş masaüstü
    /// açılabilir; içerik gelmez.)
    @Test func automaticRoleChangeIsHeldUntilConfirmed() {
        let memory = DisplayRoles(remembered: ["external": ["VIRTUAL-0002", "WIDE-0001"]])
        let assignment = pairs(memory, [wide, virtual])
        #expect(Dictionary(uniqueKeysWithValues: assignment.map { ($0.uuid, $0.role) })
                == ["VIRTUAL-0002": "external", "WIDE-0001": "external-2"])
        let held = memory.unconfirmed(assignment)
        #expect(held == ["external-2"])
        let out = PlanApply.compute(PlanApply.holding(
            input(externalSpaces: [201], others: [101, 102, 103]), roles: held))
        #expect(out.moves.isEmpty)
        #expect(out.rebinds.isEmpty)
        #expect(out.spaceMap.isEmpty)
        #expect(out.removals.isEmpty)
        #expect(out.creates["external-2"] == nil)
        // Kendiliğinden öğrenilmez: monitör external-2'ye yazılmaz.
        #expect(memory.learning(assignment).remembered["external-2"] == nil)
    }

    /// A3-b: onaysız eski davranış (kapı yokken) bütün düzeni taşırdı: bu
    /// test kapının neyi durdurduğunu belgeler.
    @Test func withoutTheGateTheWholeLayoutWouldMove() {
        let out = PlanApply.compute(input(externalSpaces: [201], others: [101, 102, 103]))
        #expect(!out.moves.isEmpty || !out.creates.isEmpty)
    }

    /// A3-c: menüden seçim (onay penceresinden sonra) onaylıdır: bekleyen rol
    /// kalmaz, plan uygulanır (düzenin taşınması kullanıcının isteği).
    @Test func menuChoiceIsConfirmedAndApplied() {
        let memory = learned([wide, virtual])
        let chosen = memory.choosing("VIRTUAL-0002", for: "external", current: pairs(memory, [wide, virtual]))
        let assignment = pairs(chosen, [wide, virtual])
        #expect(Dictionary(uniqueKeysWithValues: assignment.map { ($0.uuid, $0.role) })
                == ["VIRTUAL-0002": "external", "WIDE-0001": "external-2"])
        #expect(chosen.unconfirmed(assignment).isEmpty)
    }

    /// A3-d: bekleyen rolün kuralları da uygulanmaz: `external-2`ye pinli
    /// pencere bekleyen `external`a yedeklenmez.
    @Test func heldRoleIsNotAFallbackTarget() {
        let screens = [
            ScreenInfo(id: "builtin", uuid: "B", name: "B", isBuiltin: true,
                       frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                       visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074)),
            ScreenInfo(id: "external", uuid: "VIRTUAL-0002", name: "Virtual", isBuiltin: false,
                       frame: CGRect(x: 1710, y: 0, width: 1920, height: 1080),
                       visibleFrame: CGRect(x: 1710, y: 0, width: 1920, height: 1050)),
        ]
        let rule = Destination(screen: "external-2", desktop: 2, layout: .full)
        let open = Router.resolveTarget(rule, nameSpaces: [:], holdNames: false, displays: [],
                                        screens: screens, displayFallback: true)
        #expect(open?.screen == "external")
        let held = Router.resolveTarget(rule, nameSpaces: [:], holdNames: false, displays: [],
                                        screens: screens, displayFallback: true, heldRoles: ["external"])
        #expect(held == rule)   // bağlı olmayan ekran: taramada atlanır
    }

    // MARK: - A4 · Ana monitör çıktı, yalnız (hatırlanmayan) sanal ekran kaldı

    /// A4-a: hatırlanmayan tek ekran konumdan `external` rolünü alır ama rol
    /// onay bekler: monitör planı ona uygulanmaz.
    @Test func loneUnknownDisplayDoesNotTakeMonitorPlan() {
        let memory = learned([wide])
        let assignment = pairs(memory, [virtual])
        #expect(assignment.map(\.role) == ["external"])
        let held = memory.unconfirmed(assignment)
        #expect(held == ["external"])
        let out = PlanApply.compute(PlanApply.holding(input(externalSpaces: [201], others: nil), roles: held))
        #expect(out.creates["external", default: 0] == 0)
        #expect(out.rebinds.isEmpty)
        #expect(out.moves.isEmpty)
        #expect(memory.learning(assignment) == memory)
    }

    /// A4-b: menüdeki seçenekler: tek bağlı ekran Ekstra monitörün yerini
    /// alabilir ya da 2. monitör olabilir (Ekstra monitör boş kalır).
    @Test func loneUnknownDisplayCanBecomeMonitor2() {
        let memory = learned([wide])
        let assignment = pairs(memory, [virtual])
        #expect(memory.choosableRoles(connected: assignment) == ["external", "external-2"])
        let chosen = memory.choosing("VIRTUAL-0002", for: "external-2", current: assignment)
        let after = pairs(chosen, [virtual])
        #expect(after.map(\.role) == ["external-2"])
        #expect(chosen.unconfirmed(after).isEmpty)
        // Monitör dönünce kendi rolünde.
        #expect(roles(chosen, [wide, virtual]) == ["WIDE-0001": "external", "VIRTUAL-0002": "external-2"])
    }

    /// A4-c: tek ekranı "Ekstra monitör" olarak onaylamak (ofis masası):
    /// hatırlanır, evdeki monitörün kaydı kalır.
    @Test func loneUnknownDisplayConfirmedAsExtraMonitor() {
        let memory = learned([wide])
        let chosen = memory.choosing("VIRTUAL-0002", for: "external", current: pairs(memory, [virtual]))
        #expect(chosen.remembered["external"] == ["VIRTUAL-0002", "WIDE-0001"])
        #expect(chosen.unconfirmed(pairs(chosen, [virtual])).isEmpty)
    }

    /// A4-d: tek monitörü unutmak: rolü onay bekler, kendiliğinden yeniden
    /// öğrenilmez (kayıt boşalsa bile).
    @Test func forgettingOneMonitorPutsItOnHold() {
        let memory = learned([wide])
        let forgotten = memory.forgetting("{wide-0001}")
        #expect(forgotten.remembered.isEmpty)
        #expect(forgotten.learnedOnce)
        let assignment = pairs(forgotten, [wide])
        #expect(forgotten.unconfirmed(assignment) == ["external"])
        #expect(forgotten.learning(assignment).remembered.isEmpty)
    }

    /// A4-e: ilk bağlanış (hiç kayıt yok, yükseltme) onay beklemez: davranış
    /// değişmez, roller konumdan öğrenilir.
    @Test func firstConnectionIsNotHeld() {
        let memory = DisplayRoles()
        let assignment = pairs(memory, [virtual])
        #expect(memory.unconfirmed(assignment).isEmpty)
        let after = memory.learning(assignment)
        #expect(after.remembered == ["external": ["VIRTUAL-0002"]])
        #expect(after.learnedOnce)
    }

    /// A4-f: bu alandan önceki kayıt: bir şey hatırlıyorsa öğrenilmiş sayılır.
    @Test func olderFileWithoutFlag() throws {
        let some = try JSONDecoder().decode(DisplayRoles.self, from: Data(#"{"remembered":{"external":["A"]}}"#.utf8))
        #expect(some.learnedOnce)
        let none = try JSONDecoder().decode(DisplayRoles.self, from: Data("{}".utf8))
        #expect(!none.learnedOnce)
        var doc = Document()
        doc.displayRoles = some.forgetting("A")
        let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(doc))
        #expect(back.displayRoles.learnedOnce)
        #expect(back.displayRoles.remembered.isEmpty)
    }

    /// A4-g: bekleyen ekrandaki boş masaüstüleri temizlikte silinmez.
    @Test func cleanupLeavesHeldDisplayAlone() {
        let live: [String: [UInt64]] = ["builtin": [1], "external": [201, 202, 203]]
        let plans: [String: [String]] = ["external": ["ALPHA"]]
        let open = PlanApply.cleanupRemovals(live: live, contents: [:], plans: plans, named: [], pending: [])
        #expect(open == [203, 202])
        let held = PlanApply.cleanupRemovals(live: PlanApply.holding(live: live, roles: ["external"]),
                                             contents: [:], plans: plans, named: [], pending: [])
        #expect(held.isEmpty)
    }

    /// A4-h: bekleyen rol dışındaki roller etkilenmez: dahili ekran planı
    /// yine uygulanır.
    @Test func holdingKeepsOtherRoles() {
        var base = input(externalSpaces: [201], others: nil)
        base.plans["builtin"] = ["", "ALPHA"]
        let held = PlanApply.holding(base, roles: ["external"])
        #expect(held.live.keys.sorted() == ["builtin"])
        #expect(held.plans.keys.sorted() == ["builtin"])
        #expect(PlanApply.holding(base, roles: []).live == base.live)
    }
}

/// Onay kapısı uçtan uca: sahte ekranlar, Store ile eşitleme, menü/CLI yolu.
@MainActor
struct PrimaryExternalServiceTests {

    private static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Built-in", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))

    private static func external(_ uuid: String, x: CGFloat, name: String = "Monitor") -> ScreenService.RawDisplay {
        .init(uuid: uuid, name: name, isBuiltin: false,
              frame: CGRect(x: x, y: 1112, width: 1920, height: 1080),
              visibleFrame: CGRect(x: x, y: 1112, width: 1920, height: 1050))
    }

    final class Source { var list: [ScreenService.RawDisplay] = [] }

    /// Monitör çıkar, hatırlanmayan sanal ekran tek kalır: rol bekler,
    /// öğrenilmez; menüden "Ekstra monitör olarak kullan" onaylar.
    @Test func loneVirtualIsHeldUntilChosen() {
        let source = Source()
        source.list = [Self.builtin, Self.external("WIDE", x: -1686)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        #expect(service.heldRoles.isEmpty)
        #expect(store.document.displayRoles.remembered == ["external": ["WIDE"]])

        source.list = [Self.builtin, Self.external("VIRTUAL", x: 1710)]
        service.simulateChangeForTesting(settle: true)
        #expect(service.screens.map(\.id) == ["builtin", "external"])
        #expect(service.heldRoles == ["external"])
        #expect(store.document.displayRoles.remembered == ["external": ["WIDE"]])

        store.chooseDisplay("VIRTUAL", for: "external",
                            current: service.externalAssignment)
        #expect(service.heldRoles.isEmpty)
        #expect(store.document.displayRoles.remembered["external"] == ["VIRTUAL", "WIDE"])
    }

    /// Tek monitörü unut (kart menüsü / `screen-role DISPLAY --forget`):
    /// bekler; hepsini unut (Ayarlar / `--forget`): baştan, konumdan öğrenilir.
    @Test func forgetOneHoldsForgetAllStartsOver() {
        let source = Source()
        source.list = [Self.builtin, Self.external("WIDE", x: 0)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        store.forgetDisplay("WIDE")
        #expect(service.heldRoles == ["external"])
        service.simulateChangeForTesting(settle: true)
        #expect(service.heldRoles == ["external"])   // yeniden öğrenilmedi

        store.forgetDisplayRoles()
        #expect(!store.document.displayRoles.learnedOnce)
        #expect(service.heldRoles.isEmpty)
        service.simulateChangeForTesting(settle: true)
        #expect(store.document.displayRoles.remembered == ["external": ["WIDE"]])
    }

    /// Test ekranı ("Deskmap Test Display") hiç beklemez.
    @Test func testDisplayIsNeverHeld() {
        let source = Source()
        source.list = [Self.builtin, Self.external("WIDE", x: 0)]
        let service = ScreenService(displays: { source.list })
        let store = Store(demo: Document())
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        defer { _ = sync }
        source.list = [Self.builtin, Self.external("TEST", x: 0, name: Store.testDisplayName)]
        service.simulateChangeForTesting(settle: true)
        #expect(service.heldRoles.isEmpty)
    }

    /// URL komutları: tek monitörü unut.
    @Test func forgetOneURLParses() {
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role-forget/ABCD-1234")!)
                == .forgetScreen(display: "ABCD-1234"))
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role-forget")!) == .forgetScreenRoles)
        #expect(URLCommand.parse(URL(string: "deskmap://screen-role-forget/a/b")!) == nil)
    }
}
