import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// 12.10.2026 20:07–20:11 gerçek Mac günlüğü ("Profile 4", kurulu sürüm
/// 1929637): her tak/çıkar bir masaüstü açıyor, artıklar hiç silinmiyordu.
/// Space kimlikleri ve içerik sayıları `desktop-state.json`'dan; macOS'un
/// davranışı günlükteki sayılardan (çıkarınca 5+5 → 9: monitörün masaüstü 1'i
/// yok olur, pencereleri laptopun o anki masaüstüne; takınca monitöre yeni
/// bir masaüstü 1, monitörü hatırlayan pencereler oraya döner).
@MainActor
struct LeftoverCycleTests {
    private func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }
    private func s(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    private func plans() -> DesktopPlans {
        var plans = DesktopPlans()
        plans.set(["", "", "", "AI", ""], .docked, "builtin")
        plans.set(["HUB", "VEGA", "EXPO", "LUMEN", "ORION"], .docked, "external")
        plans.set(["", "", "", "AI", "HUB", "VEGA", "EXPO", "LUMEN", "ORION", ""], .undocked, "builtin")
        return plans
    }

    /// 20:09:09 sonrası (iki boş artık elle silindi): laptop [5,4,6,8,1678],
    /// monitör [B0,1738,1714,1713,1712]. B0 = Notes Hub'nin o anki space'i
    /// (41–44 kurallı Hub pencereleri, 45 Safari 226110).
    private func dockedFake() -> FakeDesktops {
        var location: [CGWindowID: UInt64] = [101: 5, 102: 5, 103: 5, 104: 4, 105: 4, 106: 4,
                                              107: 6, 108: 6, 109: 6, 110: 8, 111: 8, 112: 8,
                                              51: 1678, 52: 1678,
                                              41: 1700, 42: 1700, 43: 1700, 44: 1700, 45: 1700,
                                              220: 1714, 221: 1714, 222: 1714, 240: 1712, 241: 1712,
                                              242: 1712, 243: 1712]
        for w in 200..<213 { location[CGWindowID(w)] = 1738 }
        for w in 230..<237 { location[CGWindowID(w)] = 1713 }
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678],
                                         "external": [1700, 1738, 1714, 1713, 1712]],
                                location: location)
        fake.nextSpace = 1754
        return fake
    }

    /// Bir geçiş: Router.runTransition'ın saf kısmı (R2, ekler, plan, yürütme, R5).
    private func transition(_ fake: FakeDesktops, names: inout [DesktopName], plans: DesktopPlans,
                            from: [DesktopStateFile.Display], fromContents: [String: [DesktopStateFile.WindowRef]],
                            fromMode: Mode, mode: Mode, compact: Bool = true) async
        -> (plan: PlanApply.Output, outcome: PlanExecutor.Outcome) {
        let displays = fake.spaces.keys.sorted().map { DesktopStateFile.Display(role: $0, uuid: $0, spaces: fake.spaces[$0]!) }
        let live = LiveDesktops(mode: mode, spaces: fake.spaces)
        let snapshot = Succession.Snapshot(spaces: Dictionary(uniqueKeysWithValues: from.map { ($0.role, $0.spaces) }),
                                           contents: DesktopStateFile.windowIDs(fromContents))
        let namedBefore = Set(names.compactMap(\.space))
        let succession = Succession.resolve(names: names, snapshot: snapshot, live: live,
                                            windowSpaces: fake.location, plans: plans)
        names = succession.names
        let extras = PlanApply.transitionExtras(
            from: from, fromContents: fromContents, fromMode: fromMode, mode: mode, live: displays,
            windowSpaces: fake.location, namedBefore: namedBefore, ruled: [], parked: [], now: Date())
        let plan = PlanApply.compute(PlanApply.Input(
            mode: mode, live: fake.spaces, contents: fake.contents, names: names, plans: plans[mode],
            evacuation: succession.evacuation, arriving: extras.arriving, leftovers: extras.leftovers,
            newSpaces: extras.newSpaces, compactBeyondPlan: compact))
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                         allowRemovals: true, world: fake.world)
        for i in names.indices {
            if let space = out.rebinds[names[i].id] { names[i].space = space }
            else if let space = names[i].space, let next = out.spaceMap[space] { names[i].space = next }
        }
        return (plan, out)
    }

    private func snapshot(_ fake: FakeDesktops) -> ([DesktopStateFile.Display], [String: [DesktopStateFile.WindowRef]]) {
        let displays = fake.spaces.keys.sorted().map { DesktopStateFile.Display(role: $0, uuid: $0, spaces: fake.spaces[$0]!) }
        var refs: [String: [DesktopStateFile.WindowRef]] = [:]
        for (space, list) in fake.contents { refs[String(space)] = list.map { .init(id: $0, pid: 1, bundleID: "") } }
        return (displays, refs)
    }

    /// Kararlı durum temizliği (Router.runCleanup'ın saf kısmı).
    private func cleanup(_ fake: FakeDesktops, names: [DesktopName], plans: DesktopPlans, mode: Mode,
                         pinned: [String: Int] = [:]) async {
        var plan = PlanApply.Output()
        plan.removals = PlanApply.cleanupRemovals(
            live: fake.spaces, contents: fake.contents, plans: plans[mode],
            named: Set(names.compactMap(\.space)), pending: [], pinned: pinned)
        _ = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                   allowRemovals: true, world: fake.world)
    }

    private func place(_ fake: FakeDesktops, _ names: [DesktopName], _ id: String) -> Slot? {
        names.first { $0.id == id }?.space.flatMap { LiveDesktops(mode: .docked, spaces: fake.spaces).place(of: $0) }
    }

    /// 20:09:20 çıkar → "created 1" (canlı 9, plan 10: plan uzunluğu için
    /// meşru). 20:10:44 tak → eski kod monitöre 6. masaüstünü açıyordu
    /// ("Desktop added on display 2: 5 → 6 … moved 1 named desktops (4
    /// windows), created 1, failed 1"): macOS'un yeni masaüstü 1'e koyduğu
    /// Hub pencereleri (41–44), Hub'in adı laptopta 1678'e bağlı olduğu
    /// için "yerinden edilen adsız içerik" sayılıp planın ötesine taşınıyordu;
    /// 1678'de kalan Safari (45) taşınamıyordu (failed 1). Laptopta çıkarırken
    /// açılan 1755 (1678'in iki penceresi) planın ötesinde kalıyordu.
    @Test func realLogReplugAdoptsMacDesktopOneAndCompactsBuiltin() async {
        let plans = plans()
        var names = [n("AI", 8), n("HUB", 1700), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)]
        let fake = dockedFake()
        fake.failMoves = [45]

        // Çıkar: macOS B0'ı yok eder, pencereleri laptopun o anki masaüstüne (5. = 1678).
        var (from, fromContents) = snapshot(fake)
        fake.spaces = ["builtin": [5, 4, 6, 8, 1678, 1738, 1714, 1713, 1712]]
        for w: CGWindowID in [41, 42, 43, 44, 45] { fake.location[w] = 1678 }
        let unplug = await transition(fake, names: &names, plans: plans, from: from, fromContents: fromContents,
                                      fromMode: .docked, mode: .undocked)
        #expect(unplug.outcome.created == 1)          // "Desktop added on display 1: 9 → 10"
        #expect(unplug.outcome.moved == 2)            // "(2 windows)": 1678'in adsız içeriği
        #expect(unplug.plan.movedNames == 1)          // Hub 5. masaüstüne
        #expect(fake.spaces["builtin"]!.count == 10)
        let created = fake.spaces["builtin"]!.last!   // 1755
        #expect(fake.location[51] == created && fake.location[52] == created)
        #expect(names.first { $0.id == "HUB" }?.space == 1678)

        // Tak: macOS monitöre yeni masaüstü 1 (1757) ve dört space'i kimlikleriyle
        // verir; monitörü hatırlayan Hub pencereleri 1757'ye döner, Safari 1678'de kalır.
        (from, fromContents) = snapshot(fake)
        fake.spaces = ["builtin": [5, 4, 6, 8, 1678, created], "external": [1757, 1738, 1714, 1713, 1712]]
        for w: CGWindowID in [41, 42, 43, 44] { fake.location[w] = 1757 }
        let replug = await transition(fake, names: &names, plans: plans, from: from, fromContents: fromContents,
                                      fromMode: .undocked, mode: .docked)
        #expect(replug.outcome.created == 0)          // eskiden 1: "5 → 6"
        #expect(replug.plan.creates.isEmpty)
        #expect(names.first { $0.id == "HUB" }?.space == 1757)
        #expect([41, 42, 43, 44].allSatisfy { fake.location[CGWindowID($0)] == 1757 })
        #expect(replug.outcome.failedMoves == [45])   // "failed 1": yalnız Safari
        // 1755'in iki penceresi planın içindeki boş 5. masaüstüne, 1755 silindi.
        #expect(fake.location[51] == 1678 && fake.location[52] == 1678)
        #expect(fake.spaces["builtin"] == [5, 4, 6, 8, 1678])
        #expect(fake.spaces["external"] == [1757, 1738, 1714, 1713, 1712])
        #expect(!fake.removedNonEmpty)
        #expect(place(fake, names, "HUB") == s("external", 1) && place(fake, names, "ORION") == s("external", 5))
    }

    /// Eski davranışın kanıtı: sahiplenme ve toplama olmadan (newSpaces boş,
    /// compact kapalı) aynı tak monitöre bir masaüstü açar ve 4 pencereyi oraya
    /// taşır; günlükteki satırın birebir karşılığı.
    @Test func realLogReplugWithoutAdoptionCreatesExternalSix() {
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked,
            live: ["builtin": [5, 4, 6, 8, 1678, 1755], "external": [1757, 1738, 1714, 1713, 1712]],
            contents: [1678: [45], 1755: [51, 52], 1757: [41, 42, 43, 44], 1738: [200], 1714: [220],
                       1713: [230], 1712: [240], 5: [101], 4: [104], 6: [107], 8: [110]],
            names: [n("AI", 8), n("HUB", 1678), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)],
            plans: plans()[.docked],
            leftovers: [1757, 1738, 1714, 1713, 1712]))
        #expect(out.creates == ["external": 1])
        #expect(out.moves.count == 5 && out.movedNames == 1)
        #expect(out.decisions.contains { $0.hasPrefix("external: add 1") && $0.contains("space 1757") })
        // Aynı girdi, macOS'un açtığı 1757 bilinince: açılış yok, ad onu sahiplenir.
        let fixed = PlanApply.compute(PlanApply.Input(
            mode: .docked,
            live: ["builtin": [5, 4, 6, 8, 1678, 1755], "external": [1757, 1738, 1714, 1713, 1712]],
            contents: [1678: [45], 1755: [51, 52], 1757: [41, 42, 43, 44], 1738: [200], 1714: [220],
                       1713: [230], 1712: [240], 5: [101], 4: [104], 6: [107], 8: [110]],
            names: [n("AI", 8), n("HUB", 1678), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)],
            plans: plans()[.docked],
            leftovers: [1757, 1738, 1714, 1713, 1712], newSpaces: [1757], compactBeyondPlan: true))
        #expect(fixed.creates.isEmpty)
        #expect(Set(fixed.moves) == [.init(window: 45, to: s("external", 1)),
                                     .init(window: 51, to: s("builtin", 5)), .init(window: 52, to: s("builtin", 5))])
        #expect(fixed.rebinds["HUB"] == s("external", 1))
        #expect(fixed.removals == [1755])
        #expect(fixed.decisions.contains { $0.contains("name BR takes new desktop 1 on external") })
    }

    /// Üç tam döngü (her biri günlükteki gibi): sayılar plana yakınsar
    /// (laptop 5 / monitör 5 takılı, laptop 10 çıkarılmış), takışta masaüstü
    /// açılmaz, dolu ya da adlı masaüstü silinmez.
    @Test func realLogRepeatedCyclesConverge() async {
        let plans = plans()
        var names = [n("AI", 8), n("HUB", 1700), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)]
        let fake = dockedFake()
        var nextExternalOne: UInt64 = 1800
        for _ in 0..<3 {
            // Çıkar.
            var (from, fromContents) = snapshot(fake)
            let external = fake.spaces["external"]!
            let brain = names.first { $0.id == "HUB" }!.space!
            #expect(brain == external[0])
            let current = fake.spaces["builtin"]![4]
            for (w, space) in fake.location where space == brain { fake.location[w] = current }
            fake.spaces["builtin"]! += external.dropFirst()
            fake.spaces["external"] = nil
            let unplug = await transition(fake, names: &names, plans: plans, from: from,
                                          fromContents: fromContents, fromMode: .docked, mode: .undocked)
            #expect(!unplug.outcome.aborted)
            await cleanup(fake, names: names, plans: plans, mode: .undocked)
            #expect(fake.spaces["builtin"]!.count == 10)
            // Tak.
            (from, fromContents) = snapshot(fake)
            let back = Array(external.dropFirst())
            nextExternalOne += 1
            fake.spaces["builtin"]!.removeAll { back.contains($0) }
            fake.spaces["external"] = [nextExternalOne] + back
            for w: CGWindowID in [41, 42, 43, 44, 45] { fake.location[w] = nextExternalOne }
            let replug = await transition(fake, names: &names, plans: plans, from: from,
                                          fromContents: fromContents, fromMode: .undocked, mode: .docked)
            #expect(replug.outcome.created == 0)
            await cleanup(fake, names: names, plans: plans, mode: .docked)
            #expect(fake.spaces["builtin"]!.count == 5 && fake.spaces["external"]!.count == 5)
            #expect(place(fake, names, "HUB") == s("external", 1) && place(fake, names, "AI") == s("builtin", 4))
        }
        #expect(!fake.removedNonEmpty)
        // Her pencere yerinde: 1678'in iki penceresi laptopta, Hub'inkiler Hub'de.
        #expect(fake.spaces["builtin"]!.contains(fake.location[51]!))
        #expect(fake.location[41] == names.first { $0.id == "HUB" }?.space)
    }

    /// 20:07:42 açılış ("before: builtin=6 external=6" → "removed 0"): kurulumdan
    /// önce kalan boş artıklar (laptop 6., monitör 6.) geçişin artığı olmadığı
    /// için hiç silinmiyordu (aday listesi yalnız bellekte, açılışta boş).
    /// Kararlı durum temizliği planın ötesindeki boş, adsız, pinsiz her
    /// masaüstünü siler; dolu, adlı ya da pinli olanı bırakır.
    @Test func realLogLaunchRemovesPreexistingEmptyLeftovers() async {
        let plans = plans()
        let names = [n("AI", 8), n("HUB", 1700), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)]
        let fake = dockedFake()
        fake.spaces["builtin"]!.append(1740)
        fake.spaces["external"]!.append(1741)
        // Açılış geçişi: ekranlar aynı, geçiş artığı yok → plan bir şey silmez.
        let launch = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: fake.spaces, contents: fake.contents, names: names, plans: plans[.docked]))
        #expect(launch.removals.isEmpty)
        // Kararlı durum temizliği: ikisi de silinir.
        let decisions = PlanApply.cleanupPlan(live: fake.spaces, contents: fake.contents, plans: plans[.docked],
                                              named: Set(names.compactMap(\.space)), pending: [])
        #expect(decisions.filter { $0.kept == nil }.map(\.space) == [1740, 1741])
        // Laptop 6'ya numara pini varsa kalır (silmek pinleri kaydırırdı).
        let pinned = PlanApply.cleanupPlan(live: fake.spaces, contents: fake.contents, plans: plans[.docked],
                                           named: [], pending: [], pinned: ["builtin": 6])
        #expect(pinned.first { $0.space == 1740 }?.kept == "a pin targets desktop 6")
        // Dolu ya da başka profilde adlı artık kalır.
        fake.location[999] = 1741
        let busy = PlanApply.cleanupPlan(live: fake.spaces, contents: fake.contents, plans: plans[.docked],
                                         named: [1740], pending: [])
        #expect(busy.map(\.kept) == ["named", "not empty (1 windows)"])
        fake.location[999] = nil
        await cleanup(fake, names: names, plans: plans, mode: .docked)
        #expect(fake.spaces["builtin"] == [5, 4, 6, 8, 1678])
        #expect(fake.spaces["external"] == [1700, 1738, 1714, 1713, 1712])
        #expect(!fake.removedNonEmpty)
    }

    /// 20:10:55 takıştan sonra hiç temizlik satırı yoktu: eski temizlik bir kez
    /// bakıyordu; aday (1760) o an doluysa (yönlendirme pencereleri henüz
    /// geri almamış) sessizce düşüyordu. Yeni temizlik aday listesine bağlı
    /// değil: yönlendirme boşalttıktan sonraki kararlı taramada siler.
    @Test func realLogLeftoverEmptiedLaterByRoutingIsRemoved() async {
        let plans = plans()
        let names = [n("AI", 8), n("HUB", 1757), n("VEGA", 1738), n("EXPO", 1714), n("LUMEN", 1713), n("ORION", 1712)]
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678, 1755],
                                         "external": [1757, 1738, 1714, 1713, 1712, 1760]],
                                location: [101: 5, 51: 1678, 52: 1678, 41: 1760, 42: 1760, 45: 1678])
        let first = PlanApply.cleanupPlan(live: fake.spaces, contents: fake.contents, plans: plans[.docked],
                                          named: Set(names.compactMap(\.space)), pending: [])
        #expect(first.first { $0.space == 1760 }?.kept == "not empty (2 windows)")
        #expect(first.first { $0.space == 1755 }?.kept == nil)
        // Yönlendirme Hub pencerelerini yerine aldı.
        fake.location[41] = 1757; fake.location[42] = 1757
        await cleanup(fake, names: names, plans: plans, mode: .docked)
        #expect(fake.spaces["builtin"] == [5, 4, 6, 8, 1678])
        #expect(fake.spaces["external"] == [1757, 1738, 1714, 1713, 1712])
    }

    /// 20:09:09: kullanıcı Mission Control'de iki boş, adsız artığı sildi;
    /// günlük "pins kept on a deleted-desktop row" diyordu. Pinsiz adsız
    /// masaüstünde hayalet satırı açılmaz, yalnız numaralar kayar; silme
    /// kaydı bunu bildirir (günlük satırı buna göre).
    @Test func realLogManualDeletionOfEmptyUnnamedDesktopMakesNoGhost() {
        var d = V6.document(rules: [V6.rule("Terminal", docked: V6.b(5))],
                            names: [n("AI", 8)],
                            plans: DesktopPlans(docked: ["builtin": ["", "", "", "AI", ""]]))
        let deletions = d.followMissionControl(before: ["builtin": [5, 4, 6, 8, 1678, 1740],
                                                        "external": [1700, 1738, 1714, 1713, 1712, 1741]],
                                               after: ["builtin": [5, 4, 6, 8, 1678],
                                                       "external": [1700, 1738, 1714, 1713, 1712]],
                                               mode: .docked)
        #expect(deletions.count == 2 && deletions.allSatisfy { !$0.ghost })
        #expect(d.ghostDesktops.isEmpty && d.profiles.allSatisfy { $0.ghostDesktops.isEmpty })
        #expect(d.rules.first?.docked?.desktop == 5)
        // Numara pini olan masaüstü silinince hayalet açılır.
        var pinned = V6.document(rules: [V6.rule("Terminal", docked: V6.b(6))])
        let withPin = pinned.followMissionControl(before: ["builtin": [5, 4, 6, 8, 1678, 1740]],
                                                  after: ["builtin": [5, 4, 6, 8, 1678]], mode: .docked)
        #expect(withPin.map(\.ghost) == [true])
    }

    /// Testler gerçek veri klasörüne (Deskmap ya da eski Space Router) dokunmaz.
    @Test func testsNeverUseTheRealApplicationSupport() {
        let real = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support").path
        #expect(Log.isTesting)
        if ProcessInfo.processInfo.environment["DESKMAP_DATA_DIR"] == nil {
            #expect(!Store.directoryURL.path.hasPrefix(real))
        }
        #expect(!Store.legacyDirectoryURL.path.hasPrefix(real))
    }
}
