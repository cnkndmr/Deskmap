import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Ad çözümü (docs/desktop-names-v2.md §A.7 R1–R5): ad space kimliğini
/// izler; geçişte kaybolan space'in adı pencerelerini izler; geçiş dışında
/// kaybolan space silmedir; kanıt yoksa plana göre.
struct SuccessionTests {

    private func name(_ id: String, _ space: UInt64?) -> DesktopName {
        DesktopName(id: id, name: id, space: space)
    }

    private func snapshot(_ spaces: [String: [UInt64]], _ contents: [UInt64: [CGWindowID]] = [:])
        -> Succession.Snapshot {
        Succession.Snapshot(spaces: spaces, contents: contents)
    }

    // MARK: - R1

    /// Satır 1: monitör çıkınca kimliği korunan space'in adı orada kalır.
    @Test func idKeptOnUnplug() {
        let names = [name("K", 1681), name("AI", 8)]
        let result = Succession.resolve(
            names: names,
            snapshot: snapshot(["external": [1681, 1674], "builtin": [5, 8]]),
            live: LiveDesktops(mode: .undocked, spaces: ["builtin": [5, 8, 1681, 1674]]),
            windowSpaces: [:], plans: DesktopPlans())
        #expect(result.names == names)
        #expect(result.evacuation.isEmpty && result.succeeded.isEmpty)
    }

    // MARK: - R2

    /// Satır 3: space kayboldu, pencereleri yeni (kayıtta olmayan) bir
    /// space'te: ad oraya geçer.
    @Test func newIdsFollowWindows() {
        let result = Succession.resolve(
            names: [name("K", 100)],
            snapshot: snapshot(["external": [100, 101]], [100: [1, 2, 3]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [200, 101], "builtin": [5]]),
            windowSpaces: [1: 200, 2: 200, 3: 5], plans: DesktopPlans())
        #expect(result.names == [name("K", 200)])
        #expect(result.succeeded == ["K": 200])
    }

    /// Satır 3: pencereler macOS'un birleştirdiği (kayıtta içeriği olan)
    /// masaüstünde: ardıl yok, ad yerleşmemiş, tahliye kümesi pencereler.
    @Test func mergedDesktopEvacuationSet() {
        let result = Succession.resolve(
            names: [name("K", 100)],
            snapshot: snapshot(["external": [100], "builtin": [5]], [100: [1, 2], 5: [9]]),
            live: LiveDesktops(mode: .undocked, spaces: ["builtin": [5]]),
            windowSpaces: [1: 5, 2: 5, 9: 5], plans: DesktopPlans())
        #expect(result.names == [name("K", nil)])
        #expect(result.evacuation == ["K": [1, 2]])
    }

    /// Yarıda kalan geçişin tahliye kümesi (Transition.evacuation): ad hâlâ
    /// yerleşmemişse yeniden çözümde pencereleri (yaşayanları) geri gelir;
    /// ad bağlıysa ya da pencereler kapandıysa gelmez.
    @Test func carriedEvacuationForUnplacedName() {
        let live = LiveDesktops(mode: .undocked, spaces: ["builtin": [5]])
        let snap = snapshot(["external": [100], "builtin": [5]], [100: [1, 2], 5: [9]])
        let result = Succession.resolve(
            names: [name("K", nil), name("B", 5), name("Z", nil)], snapshot: snap, live: live,
            windowSpaces: [1: 5, 9: 5], plans: DesktopPlans(),
            carried: ["K": [1, 2], "B": [9], "Z": [7]])
        #expect(result.evacuation == ["K": [1]])
        #expect(result.names == [name("K", nil), name("B", 5), name("Z", nil)])
    }

    /// Eski durum dosyası (evacuation alanı yok) okunur.
    @Test func transitionWithoutEvacuationDecodes() throws {
        let json = #"{"id":"t","startedAt":0,"reason":"r","from":[],"fromContents":{},"fromMode":"docked","moves":[]}"#
        let t = try JSONDecoder().decode(DesktopStateFile.Transition.self, from: Data(json.utf8))
        #expect(t.evacuation == nil)
        var withSet = t
        withSet.evacuation = ["K": [1, 2]]
        let back = try JSONDecoder().decode(DesktopStateFile.Transition.self,
                                            from: JSONEncoder().encode(withSet))
        #expect(back.evacuation == ["K": [1, 2]])
    }

    /// Ardıl adayı bu profilde başka ada bağlıysa ardıl olmaz.
    @Test func successorBoundToAnotherNameIsNotTaken() {
        let result = Succession.resolve(
            names: [name("K", 100), name("M", 200)],
            snapshot: snapshot(["external": [100]], [100: [1]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [200]]),
            windowSpaces: [1: 200], plans: DesktopPlans())
        #expect(result.names.first { $0.id == "K" }?.space == nil)
        #expect(result.evacuation == ["K": [1]])
        #expect(result.names.first { $0.id == "M" }?.space == 200)
    }

    /// Eşitlikte kayıtta olmayan space, sonra küçük sıra.
    @Test func tieBreakPrefersNewSpaceThenLowerIndex() {
        let result = Succession.resolve(
            names: [name("K", 100)],
            snapshot: snapshot(["external": [100, 300]], [100: [1, 2]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [300, 400, 500]]),
            windowSpaces: [1: 300, 2: 500], plans: DesktopPlans())
        #expect(result.names.first?.space == 500)
        let lower = Succession.resolve(
            names: [name("K", 100)],
            snapshot: snapshot(["external": [100]], [100: [1, 2]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [400, 500]]),
            windowSpaces: [1: 500, 2: 400], plans: DesktopPlans())
        #expect(lower.names.first?.space == 400)
    }

    /// Penceresi yaşamayan kaybolmuş space: ad yerleşmemiş (plan açar), hayalet yok.
    @Test func vanishedEmptyDesktopBecomesUnplaced() {
        let result = Succession.resolve(
            names: [name("K", 100)], snapshot: snapshot(["external": [100]], [100: [7]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [200]]),
            windowSpaces: [:], plans: DesktopPlans())
        #expect(result.names == [name("K", nil)])
        #expect(result.evacuation.isEmpty)
    }

    /// 12.10 olayı: monitör yeniden takılınca macOS 1. masaüstünü yeni
    /// kimlikle (1681) açtı. Eski kimlik kayboldu ama silinmedi: Orion
    /// pencereleriyle 1681'e geçer, hiçbir profilde hayalet açılmaz, pinler kaymaz.
    @Test func incidentReplugNewDesktopOneIsSuccessionNotGhost() {
        let before: [String: [UInt64]] = ["builtin": [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680, 1666, 1674, 1673, 1672, 1032]]
        let names = [name("Orion", 1666), name("Nova Ek", 1674), name("Lumen", 1672)]
        let result = Succession.resolve(
            names: names, snapshot: snapshot(before, [1666: [11, 12, 13, 14], 1674: [21], 1672: [31]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [1681, 1674, 1673, 1672, 1032],
                                                        "builtin": [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680]]),
            windowSpaces: [11: 1681, 12: 1681, 13: 1681, 14: 1681, 21: 1674, 31: 1672],
            plans: DesktopPlans())
        #expect(V6.bindings(Profile(name: "x", names: result.names))
                == ["Orion": 1681, "Nova Ek": 1674, "Lumen": 1672])
        var d = V6.document(rules: [V6.rule("Word", docked: V6.at("external", 2, name: "Nova Ek"))],
                            names: result.names)
        d.refreshNameCaches(live: LiveDesktops(mode: .docked, spaces: ["external": [1681, 1674, 1673, 1672, 1032]]))
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.rules[0].docked?.desktop == 2)
    }

    // MARK: - R5 / satır 5

    @Test func coalescedRoundTripIsNoop() {
        let spaces: [String: [UInt64]] = ["external": [1681, 1674], "builtin": [5, 8]]
        let names = [name("K", 1681), name("AI", 8)]
        let result = Succession.resolve(names: names, snapshot: snapshot(spaces, [1681: [1]]),
                                        live: LiveDesktops(mode: .docked, spaces: spaces),
                                        windowSpaces: [1: 1681], plans: DesktopPlans())
        #expect(result.names == names && result.evacuation.isEmpty && result.succeeded.isEmpty)
        let plan = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: spaces, contents: [1681: [1]], names: names,
            plans: ["external": ["K"], "builtin": ["", "AI"]]))
        #expect(plan.isEmpty)
    }

    /// Uyanma penceresinde kaybolan masaüstü geçiştir: çözüm hiç hayalet
    /// açmaz (hayaleti yalnız `followMissionControl` açar).
    @Test func wakeWindowNeverGhosts() {
        var d = V6.document(names: [name("K", 100)], plans: DesktopPlans(docked: ["external": ["K"]]))
        let result = Succession.resolve(names: d.names, snapshot: snapshot(["external": [100]], [100: [1]]),
                                        live: LiveDesktops(mode: .docked, spaces: ["external": [200]]),
                                        windowSpaces: [1: 200], plans: d.plans)
        d.names = result.names
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.names.first?.space == 200)
    }

    // MARK: - R4

    /// Kimlikler yenilendi (yeniden başlatma): kayıtta da canlıda da olmayan
    /// bağ planın etkin kurulumdaki yerine bağlanır.
    @Test func renewedIdsUsePlanPosition() {
        let result = Succession.resolve(
            names: [name("K", 9001), name("M", 9002)],
            snapshot: snapshot(["external": [1, 2]]),
            live: LiveDesktops(mode: .docked, spaces: ["external": [77, 78, 79]]),
            windowSpaces: [:], plans: DesktopPlans(docked: ["external": ["", "K", "M"]]))
        #expect(result.names == [name("K", 78), name("M", 79)])
    }

    @Test func rebootFallsBackToPlan() {
        var d = V6.document(names: [name("K", 9001), name("A", 50)],
                            plans: DesktopPlans(undocked: ["builtin": ["A", "K"]]))
        d.bindByPlan(live: LiveDesktops(mode: .undocked, spaces: ["builtin": [50, 60]]))
        #expect(d.names == [name("K", 60), name("A", 50)])
        // Planın yeri başka ada bağlı: yerleşmemiş.
        var clash = V6.document(names: [name("K", 9001), name("A", 60)],
                                plans: DesktopPlans(undocked: ["builtin": ["A", "K"]]))
        clash.bindByPlan(live: LiveDesktops(mode: .undocked, spaces: ["builtin": [50, 60]]))
        #expect(clash.names.first { $0.id == "K" }?.space == nil)
        #expect(!DesktopStateFile.sameBoot(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 100)))
        #expect(DesktopStateFile.sameBoot(Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 100.5)))
        #expect(DesktopStateFile.sameBoot(nil, Date()))
    }

    // MARK: - R3

    /// Satır 8: ekran kümesi aynıyken (geçiş dışında) kaybolan adlı space
    /// silmedir: her profilde hayalet.
    @Test func deletionOutsideTransitionIsGhost() {
        var d = V6.document(rules: [V6.rule("Word", docked: V6.at("external", 2, name: "EXPO"))],
                            names: [DesktopName(id: "EXPO", name: "Nova Ek", space: 1674)],
                            plans: DesktopPlans(docked: ["external": ["", "EXPO"]], undocked: ["builtin": ["", "EXPO"]]))
        let deletions = d.followMissionControl(before: ["external": [1681, 1674], "builtin": [5]],
                                               after: ["external": [1681], "builtin": [5]], mode: .docked)
        #expect(deletions == [DesktopDeletion(role: "external", desktop: 2, space: 1674, ghost: true)])
        #expect(d.names.isEmpty)
        #expect(d.ghostDesktops.map(\.name) == ["Nova Ek"])
        #expect(d.ghostDesktops.first?.nameID == "EXPO")
        #expect(d.ghostDesktops.first?.cause == GhostDesktop.deletedCause)
        #expect(d.rules.isEmpty)
    }

    /// Deskmap'in kendi sildiği space silme sayılmaz.
    @Test func ownRemovalIsNotADeletion() {
        var d = V6.document(names: [DesktopName(id: "K", name: "K", space: 7)])
        let deletions = d.followMissionControl(before: ["builtin": [5, 7]], after: ["builtin": [5]],
                                               mode: .undocked, ownRemovals: [7])
        #expect(deletions.isEmpty)
        #expect(d.ghostDesktops.isEmpty)
    }

    // MARK: - Satır 21

    /// Deskmap kapalıyken monitör çıkarıldı: kayıtlı durumla ekran kümesi
    /// farklı → geçiş, kayıtlı içerikle ardıllar.
    @Test func catchUpFromSavedSnapshot() {
        let saved = DesktopStateFile(
            mode: .docked,
            displays: [.init(role: "builtin", uuid: "B", spaces: [5]),
                       .init(role: "external", uuid: "E", spaces: [100])],
            contents: ["100": [.init(id: 1, pid: 1, bundleID: "x")]])
        let now: [DesktopStateFile.Display] = [.init(role: "builtin", uuid: "B", spaces: [5, 300])]
        #expect(!saved.sameDisplays(as: now))
        let result = Succession.resolve(
            names: [name("K", 100)], snapshot: saved.snapshot,
            live: LiveDesktops(mode: .undocked, spaces: ["builtin": [5, 300]]),
            windowSpaces: [1: 300], plans: DesktopPlans())
        #expect(result.names.first?.space == 300)
    }

    /// Yarıda kalan uygulama: kayıt dosyasında "önce" durumu ve taşıma
    /// günlüğü kalır; sonraki açılış ondan sürer.
    @Test func resumeTransitionJournal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var state = DesktopStateFile(mode: .undocked, displays: [.init(role: "builtin", uuid: "B", spaces: [5, 6])])
        state.transition = .init(id: "T", startedAt: Date(timeIntervalSince1970: 10), reason: "display",
                                 from: [.init(role: "builtin", uuid: "B", spaces: [5]),
                                        .init(role: "external", uuid: "E", spaces: [100])],
                                 fromContents: ["100": [.init(id: 1, pid: 2, bundleID: "b")]],
                                 fromMode: .docked, moves: [.init(window: 1, space: 6)])
        try state.write(directory: dir)
        let read = try #require(DesktopStateFile.read(directory: dir))
        let transition = try #require(read.transition)
        #expect(transition.fromMode == .docked)
        #expect(transition.moves == [.init(window: 1, space: 6)])
        let snapshot = Succession.Snapshot(spaces: ["builtin": [5], "external": [100]],
                                           contents: DesktopStateFile.windowIDs(transition.fromContents))
        let result = Succession.resolve(names: [name("K", 100)], snapshot: snapshot,
                                        live: LiveDesktops(mode: .undocked, spaces: ["builtin": [5, 6]]),
                                        windowSpaces: [1: 6], plans: DesktopPlans())
        #expect(result.names.first?.space == 6)
    }
}
