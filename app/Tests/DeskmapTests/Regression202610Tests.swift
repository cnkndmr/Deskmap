import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// 09–13.10.2026 masaüstü/ad/plan hatalarının regresyon testleri.
/// Beklenti tablosu: docs/test-matrix-2026-10.md (her satırda test adı).
/// Bilinen (düzeltilmemiş) hatalar `withKnownIssue` ile işaretli.
@MainActor
struct Regression202610Tests {
    private func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }
    private func s(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    /// LeftoverCycleTests ile aynı plan (Profile 4).
    private func plans() -> DesktopPlans {
        var plans = DesktopPlans()
        plans.set(["", "", "", "AI", ""], .docked, "builtin")
        plans.set(["HUB", "VEGA", "EXPO", "LUMEN", "ORION"], .docked, "external")
        plans.set(["", "", "", "AI", "HUB", "VEGA", "EXPO", "LUMEN", "ORION", ""], .undocked, "builtin")
        return plans
    }

    /// Takılı kararlı durum: her masaüstünde pencereler, adlar yerinde.
    private func dockedSim() -> DeskSim {
        var location: [CGWindowID: UInt64] = [101: 5, 102: 5, 104: 4, 107: 6, 110: 8, 111: 8, 151: 1678]
        for (i, space) in [UInt64(1700), 1738, 1714, 1713, 1712].enumerated() {
            for k in 0..<3 { location[CGWindowID(300 + i * 10 + k)] = space }
        }
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678],
                                         "external": [1700, 1738, 1714, 1713, 1712]],
                                location: location)
        fake.nextSpace = 2000
        return DeskSim(fake: fake, names: [n("AI", 8), n("HUB", 1700), n("VEGA", 1738), n("EXPO", 1714),
                                           n("LUMEN", 1713), n("ORION", 1712)], plans: plans())
    }

    /// Adın penceresi (dockedSim'de).
    private func windows(of id: String) -> [CGWindowID] {
        guard let i = ["HUB", "VEGA", "EXPO", "LUMEN", "ORION"].firstIndex(of: id) else { return [110, 111] }
        return (0..<3).map { CGWindowID(300 + i * 10 + $0) }
    }

    // MARK: - macOS modeli

    /// Çıkar: monitörün masaüstü 1'i yok olur, pencereleri laptopun `current`.
    /// masaüstüne; kalan monitör masaüstüleri laptopun sonuna.
    private func macUnplug(_ sim: DeskSim, current: Int = 5) {
        let external = sim.fake.spaces["external"]!
        let target = sim.fake.spaces["builtin"]![min(current, sim.fake.spaces["builtin"]!.count) - 1]
        for (w, space) in sim.fake.location where space == external[0] { sim.fake.location[w] = target }
        sim.fake.spaces["builtin"]! += external.dropFirst()
        sim.fake.spaces["external"] = nil
    }

    /// Tak: macOS monitöre yeni masaüstü 1 açar; `back` laptoptan monitöre
    /// (verilen sırayla) döner; `remember` pencereleri yeni masaüstü 1'e.
    @discardableResult
    private func macPlug(_ sim: DeskSim, back: [UInt64], remember: [CGWindowID]) -> UInt64 {
        sim.fake.nextSpace += 1
        let one = sim.fake.nextSpace
        sim.fake.spaces["builtin"]!.removeAll { back.contains($0) }
        sim.fake.spaces["external"] = [one] + back
        for w in remember { sim.fake.location[w] = one }
        return one
    }

    // MARK: - 13.10 08:58–09:01 sanal monitör: "removed 1 of 3"

    /// 08:58:47 temizliği: laptop 9/5, monitör 5/5. Karar satırları günlükle
    /// birebir (sondan: 1712, 1713, 1714, 1738 → remove).
    @Test func log1013CleanupDecisionsMatchLog() {
        let live: [String: [UInt64]] = ["builtin": [5, 4, 6, 8, 1678, 1738, 1714, 1713, 1712],
                                        "external": [1777, 1780, 1781, 1782, 1783]]
        let contents: [UInt64: [CGWindowID]] = [5: [1], 4: [2], 6: [3], 8: [4], 1678: [5, 6],
                                                1777: [7], 1780: [8], 1781: [9], 1782: [10], 1783: [11]]
        var p = DesktopPlans()
        p.set(["", "", "", "AI", ""], .docked, "builtin")
        p.set(["A", "B", "C", "D", "E"], .docked, "external")
        let decisions = PlanApply.cleanupPlan(live: live, contents: contents, plans: p[.docked],
                                              named: [8, 1777, 1780, 1781, 1782, 1783], pending: [])
        #expect(decisions.map(\.text) == [
            "desktop 9 on builtin (space 1712): remove", "desktop 8 on builtin (space 1713): remove",
            "desktop 7 on builtin (space 1714): remove", "desktop 6 on builtin (space 1738): remove"])
    }

    /// Mekanizma: Mission Control silmesinden hemen sonra boşluk okuması
    /// geçici olarak "dolu" dönerse yürütücü yalnız ilkini siler, sonrakileri
    /// "kept (not empty)" bırakırdı; günlükteki "removed 1 of 4" / "1 of 3".
    /// Düzeltildi: yerleşme beklemesi + yeniden okuma.
    @Test func log1013TransientEmptinessAfterRemovalRemovesOnlyFirst() async {
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678, 1738, 1714],
                                         "external": [1784, 1781, 1780, 1787, 1788, 1789]],
                                location: [1: 5, 2: 4, 3: 6, 4: 8, 5: 1678, 6: 1784, 7: 1781, 8: 1780, 9: 1787, 10: 1788])
        let sim = DeskSim(fake: fake, names: [], plans: plans())
        sim.plans.set(["", "", "", "", ""], .docked, "builtin")
        sim.plans.set(["", "", "", "", ""], .docked, "external")
        sim.transientAfterRemoval = 10
        let result = await sim.cleanup(.docked)
        #expect(result.planned == [1714, 1738, 1789])     // 13.10: "removed 1 of 3"
        // Düzeltme: yürütücü silmeden sonra yerleşmeyi bekleyip yeniden okur.
        #expect(result.removed == 3)
        #expect(fake.removed == [1714, 1738, 1789])
        await sim.settle(.docked, sweeps: 6)
        #expect(fake.spaces["builtin"]!.count == 5 && fake.spaces["external"]!.count == 5)
        #expect(!fake.removedNonEmpty)
    }

    /// Yeniden okuma gerçekten dolu masaüstünü asla silmez: silmeden sonra
    /// okuma geçici "dolu", sonraki masaüstünde pencere var (yarışla geldi).
    @Test func settleRetryNeverRemovesARealWindowDesktop() async {
        let fake = FakeDesktops(spaces: ["builtin": [1, 2, 3, 4]], location: [10: 1, 11: 3])
        let sim = DeskSim(fake: fake, names: [], plans: plans())
        sim.transientAfterRemoval = 3
        var plan = PlanApply.Output()
        plan.removals = [2, 3, 4]
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                         allowRemovals: true, world: sim.world)
        #expect(out.removedSpaces == [2, 4])
        #expect(fake.spaces["builtin"] == [1, 3] && !fake.removedNonEmpty)
    }

    /// Kullanıcı beklentisi: tek temizlik turu planın ötesindeki bütün boş
    /// artıkları siler. Yürütücü boşluğu silmeden hemen sonra bir kez okur,
    /// yeniden denemez (PlanExecutor.swift `let empty = world.isEmpty(space)`
    /// sonrası `continue`); temizlik de "1 of 3"ten sonra yeniden planlanmaz.
    @Test func log1013OneCleanupPassRemovesAllEmptyLeftovers() async {
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678, 1738, 1714],
                                         "external": [1784, 1781, 1780, 1787, 1788, 1789]],
                                location: [1: 5, 2: 4, 3: 6, 4: 8, 5: 1678, 6: 1784, 7: 1781, 8: 1780, 9: 1787, 10: 1788])
        let sim = DeskSim(fake: fake, names: [], plans: plans())
        sim.plans.set(["", "", "", "", ""], .docked, "builtin")
        sim.plans.set(["", "", "", "", ""], .docked, "external")
        sim.transientAfterRemoval = 10
        let result = await sim.cleanup(.docked)
        #expect(result.removed == 3)
        #expect(!fake.removedNonEmpty)
    }

    /// Aynı hata geçişin kendi silmelerinde (08:58:53 çıkar: "remove 1783,1782"
    /// → 1782 "kept (not empty)").
    @Test func log1013TransitionRemovalsStopAfterFirstUnderTransientRead() async {
        let sim = dockedSim()
        sim.transientAfterRemoval = 10
        let before = sim.snapshot(.docked)
        macUnplug(sim)
        // Takışta açılmış, boş iki ek monitör masaüstü de laptopa gelir.
        sim.fake.spaces["builtin"]! += [1782, 1783, 1785]
        let r = await sim.transition(from: before, to: .undocked)
        #expect(r.plan.removals.count >= 2)
        #expect(r.outcome.removed == r.plan.removals.count)
        #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty)
    }

    /// 08:59:14 tak (tur 3): macOS monitöre yeni 1784'ü açıp D5A'nın 4
    /// penceresini koydu, 1781 ve 1780 ters sırayla döndü. Plan günlükteki
    /// kararları verir: D5A 1784'ü sahiplenir, monitöre 3 açılış, 1781'in
    /// adsız içeriği (yeri FED'e planlı) planın ötesine (6.) gider.
    @Test func log1013ReplugReversedSpacesFixture() async {
        var p = DesktopPlans()
        p.set(["", "", "", "AI", ""], .docked, "builtin")
        p.set(["D5A", "FED", "DB6", "585", "CA6"], .docked, "external")
        let location: [CGWindowID: UInt64] = [
            1: 5, 2: 4, 3: 6, 4: 8, 5: 1678,
            11: 1784, 12: 1784, 13: 1784, 14: 1784,            // D5A (macOS koydu)
            21: 1781, 22: 1781,                                // adsız
            31: 1780, 32: 1780, 33: 1780, 34: 1780,            // CA6
            41: 1738, 42: 1738, 43: 1738,                      // FED
            51: 1714, 52: 1714,                                // DB6
            61: 1713, 62: 1713]                                // 585
        let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678, 1738, 1714, 1713],
                                         "external": [1784, 1781, 1780]], location: location)
        fake.nextSpace = 1786
        let sim = DeskSim(fake: fake, names: [n("AI", 8), n("D5A", 1777), n("FED", 1738), n("DB6", 1714),
                                              n("585", 1713), n("CA6", 1780)], plans: p)
        let before = DeskSim.Before(
            displays: [.init(role: "builtin", uuid: "builtin",
                             spaces: [5, 4, 6, 8, 1678, 1738, 1714, 1713, 1777, 1781, 1780])],
            contents: ["1777": [11, 12, 13, 14].map { .init(id: $0, pid: 1, bundleID: "") },
                       "1781": [21, 22].map { .init(id: $0, pid: 1, bundleID: "") },
                       "1780": [31, 32, 33, 34].map { .init(id: $0, pid: 1, bundleID: "") }],
            mode: .undocked)
        let r = await sim.transition(from: before, to: .docked)
        #expect(r.plan.creates == ["external": 3])
        #expect(r.plan.decisions.contains { $0.contains("unnamed content of space 1781") && $0.contains("needs desktop 6") })
        #expect(Set(r.plan.removals) == [1713, 1714, 1738])
        #expect(sim.namesAtPlan(.docked).isEmpty)
        #expect(!fake.removedNonEmpty && sim.removedNamed.isEmpty)
        // Yönlendirme 1781'in iki penceresini götürünce kararlı tarama 6.'yı siler.
        fake.location[21] = 1678; fake.location[22] = 1678
        await sim.settle(.docked)
        #expect(fake.spaces["builtin"]!.count == 5 && fake.spaces["external"]!.count == 5)
    }

    // MARK: - Çok turlu tak-çıkar

    /// 10 tak-çıkar döngüsü (ideal macOS): her takılı/çıkarılı durumda sayı ==
    /// plan, adlar planlı yerde, adın pencereleri adın masaüstünde, pencereli
    /// ya da adlı masaüstü hiç silinmez, takışta planın ötesine açılış yok.
    @Test func tenPlugCyclesConvergeAndKeepNames() async {
        let sim = dockedSim()
        var rng = SeededRNG(seed: 1013)
        for cycle in 0..<10 {
            let before = sim.snapshot(.docked)
            let external = sim.fake.spaces["external"]!
            macUnplug(sim, current: Int.random(in: 1...5, using: &rng))
            let un = await sim.transition(from: before, to: .undocked)
            #expect(!un.outcome.aborted, "cycle \(cycle) unplug")
            await sim.settle(.undocked)
            #expect(sim.fake.spaces["builtin"]!.count == 10, "cycle \(cycle) undocked count")
            #expect(sim.namesAtPlan(.undocked).isEmpty, "cycle \(cycle) undocked names")

            let back = sim.fake.spaces["builtin"]!.filter { external.contains($0) && $0 != external[0] }
            let order = cycle % 3 == 1 ? back.reversed() : back
            let take = cycle % 4 == 3 ? Array(order.prefix(2)) : Array(order)
            let remember = cycle % 2 == 0 ? windows(of: "HUB") : []
            let before2 = sim.snapshot(.undocked)
            macPlug(sim, back: take, remember: remember)
            let pl = await sim.transition(from: before2, to: .docked)
            #expect(!pl.outcome.aborted, "cycle \(cycle) plug")
            #expect((pl.plan.creates["external"] ?? 0) <= 5 - (take.count + 1), "cycle \(cycle) creates beyond plan")
            await sim.settle(.docked)
            #expect(sim.fake.spaces["builtin"]!.count == 5, "cycle \(cycle) builtin \(sim.fake.spaces["builtin"]!)")
            #expect(sim.fake.spaces["external"]!.count == 5, "cycle \(cycle) external \(sim.fake.spaces["external"]!)")
            #expect(sim.namesAtPlan(.docked).isEmpty, "cycle \(cycle) docked names \(sim.namesAtPlan(.docked))")
            for id in ["HUB", "VEGA", "EXPO", "LUMEN", "ORION"] {
                #expect(windows(of: id).allSatisfy { sim.fake.location[$0] == sim.space(of: id) }, "cycle \(cycle) \(id) windows")
            }
        }
        #expect(!sim.fake.removedNonEmpty)
        #expect(sim.removedNamed.isEmpty)
        // Unnamed laptop windows stayed on the laptop.
        for w: CGWindowID in [101, 102, 104, 107, 151] {
            #expect(sim.fake.spaces["builtin"]!.contains(sim.fake.location[w]!))
        }
    }

    /// Aynı döngü, 13.10'daki geçici okumayla ve tek temizlik turuyla:
    /// kullanıcı beklentisi her takıştan sonra sayı == plan.
    @Test func plugCyclesWithTransientReadsLeaveNoExtraDesktops() async {
        let sim = dockedSim()
        sim.transientAfterRemoval = 10
        var extra = 0
        for _ in 0..<4 {
            let before = sim.snapshot(.docked)
            let external = sim.fake.spaces["external"]!
            macUnplug(sim)
            // macOS'un bu geçişte bıraktığı dört boş artık (13.10: 1780–1783).
            for k: UInt64 in 1...4 { sim.fake.spaces["builtin"]!.append(sim.fake.nextSpace + 500 + k) }
            sim.fake.nextSpace += 10
            await sim.transition(from: before, to: .undocked)
            _ = await sim.cleanup(.undocked)
            extra = max(extra, sim.fake.spaces["builtin"]!.count - 10)
            let back = sim.fake.spaces["builtin"]!.filter { external.contains($0) }
            let before2 = sim.snapshot(.undocked)
            macPlug(sim, back: back, remember: windows(of: "HUB"))
            await sim.transition(from: before2, to: .docked)
            _ = await sim.cleanup(.docked)
            extra = max(extra, sim.fake.spaces.values.map(\.count).reduce(0, +) - 10)
        }
        #expect(extra == 0)
        #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty)
        // Kararlı taramalar sonunda yakınsar.
        await sim.settle(.docked, sweeps: 6)
        #expect(sim.fake.spaces["builtin"]!.count == 5 && sim.fake.spaces["external"]!.count == 5)
    }

    // MARK: - Kesinti ve yeniden deneme

    /// Geçiş her olası adımda yarıda kesilir (abortAtCall 1…12), sonra aynı
    /// "önce" durumundan yeniden başlar: sonuç kesintisizle aynı, dolu ya da
    /// adlı masaüstü silinmez, açılan masaüstü birikmez.
    @Test func interruptedPlugAtEveryStepRestartsToSameResult() async {
        for at in 1...12 {
            let sim = dockedSim()
            let before = sim.snapshot(.docked)
            let external = sim.fake.spaces["external"]!
            macUnplug(sim)
            await sim.transition(from: before, to: .undocked)
            await sim.settle(.undocked)
            let back = sim.fake.spaces["builtin"]!.filter { external.contains($0) }.reversed()
            let before2 = sim.snapshot(.undocked)
            macPlug(sim, back: Array(back.prefix(2)), remember: windows(of: "HUB"))
            sim.calls = 0
            sim.abortAtCall = at
            await sim.transition(from: before2, to: .docked)
            sim.abortAtCall = nil
            var tries = 0
            while !sim.savedLeftovers.isEmpty || tries == 0 {
                tries += 1
                let r = await sim.transition(from: before2, to: .docked)
                if !r.outcome.aborted || tries > 3 { break }
            }
            await sim.settle(.docked)
            #expect(sim.fake.spaces["builtin"]!.count == 5, "abort at \(at): \(sim.fake.spaces)")
            #expect(sim.fake.spaces["external"]!.count == 5, "abort at \(at): \(sim.fake.spaces)")
            #expect(sim.namesAtPlan(.docked).isEmpty, "abort at \(at)")
            #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty, "abort at \(at)")
        }
    }

    /// Çıkar: macOS monitörün masaüstü 1'ini (BR) dolu laptop masaüstü 1'e
    /// katar → BR yerleşmemiş, pencereleri tahliye kümesinde (R2). Geçiş ilk
    /// açılıştan sonra kesilir. Store.resolveSuccession adın yerleşmemiş
    /// hâlini kalıcı yazar, ama tahliye kümesi Transition'da saklanmaz:
    /// yeniden başlayan geçiş BR'yi kanıtsız ad sayıp boş yerine bağlar,
    /// BR'nin pencereleri adsız içerik olarak planın ötesine gider. Kullanıcı
    /// beklentisi: kesintiden sonra ad pencereleriyle birlikte.
    @Test func interruptedEvacuationKeepsNameWithWindows() async {
        let sim = dockedSim()
        let before = sim.snapshot(.docked)
        macUnplug(sim, current: 1)
        sim.calls = 0
        sim.abortAtCall = 1
        let first = await sim.transition(from: before, to: .undocked)
        #expect(first.outcome.aborted && first.outcome.created == 1)
        #expect(sim.space(of: "HUB") == nil)            // yerleşmemiş (kalıcı)
        sim.abortAtCall = nil
        let second = await sim.transition(from: before, to: .undocked)
        #expect(!second.outcome.aborted)
        await sim.settle(.undocked)
        #expect(sim.savedEvacuation.isEmpty)
        #expect(windows(of: "HUB").allSatisfy { sim.fake.location[$0] == sim.space(of: "HUB") })
        #expect(sim.fake.spaces["builtin"]!.count == 10)
        #expect(sim.place("HUB", mode: .undocked) == s("builtin", 5))
        #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty)
    }

    /// 13.10 08:58:29: '+' bulunamadı, açılış yarıda kaldı ("stopped
    /// (interrupted) after 2 created"); yeniden hesap yalnız eksik kalanı açar.
    @Test func failedCreateMidwayRestartCreatesOnlyTheRest() async {
        let sim = dockedSim()
        let before = sim.snapshot(.docked)
        macUnplug(sim)
        await sim.transition(from: before, to: .undocked)
        await sim.settle(.undocked)
        let before2 = sim.snapshot(.undocked)
        macPlug(sim, back: [], remember: [])
        var adds = 0
        // İkinci açılıştan sonra '+' bulunamıyor.
        let world = sim.world
        var w2 = world
        w2.addDesktop = { role in
            adds += 1
            if adds > 2 { return false }
            return await world.addDesktop(role)
        }
        let live = LiveDesktops(mode: .docked, spaces: sim.fake.spaces)
        let snap = Succession.Snapshot(spaces: ["builtin": before2.displays[0].spaces],
                                       contents: DesktopStateFile.windowIDs(before2.contents))
        sim.names = Succession.resolve(names: sim.names, snapshot: snap, live: live,
                                       windowSpaces: sim.fake.location, plans: sim.plans).names
        let plan = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: sim.fake.spaces, contents: sim.fake.contents, names: sim.names,
            plans: sim.plans[.docked]))
        #expect(plan.creates["external"] == 4)
        let out = await PlanExecutor.run(plan, expected: sim.fake.spaces, windowSpaces: sim.fake.location,
                                         allowRemovals: true, world: w2)
        #expect(out.created == 2 && out.failedCreates == ["external"])
        #expect(out.createdSpaces.count == 2)
        #expect(!sim.fake.removedNonEmpty)
        // Yeniden: 4 değil 2 açılır.
        let r = await sim.transition(from: before2, to: .docked)
        #expect(r.plan.creates["external"] == 2)
        await sim.settle(.docked)
        #expect(sim.fake.spaces["external"]!.count == 5 && sim.fake.spaces["builtin"]!.count == 5)
        #expect(sim.namesAtPlan(.docked).isEmpty)
    }

    // MARK: - İdempotentlik

    /// Yakınsamış durumda aynı plan ikinci kez: değişiklik yok; temizlik de
    /// bir şey bulmaz; ekran değişmeden gelen "geçiş" (açılış, uyanma) hiçbir
    /// şeyi taşımaz/silmez.
    @Test func samePlanTwiceIsNoop() async {
        let sim = dockedSim()
        let again = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: sim.fake.spaces, contents: sim.fake.contents, names: sim.names,
            plans: sim.plans[.docked], compactBeyondPlan: true))
        #expect(again.isEmpty)
        #expect(PlanApply.cleanupRemovals(live: sim.fake.spaces, contents: sim.fake.contents,
                                          plans: sim.plans[.docked], named: sim.allNamedSpaces, pending: []).isEmpty)
        let before = sim.snapshot(.docked)
        let r = await sim.transition(from: before, to: .docked)
        #expect(r.plan.isEmpty && r.outcome.removed == 0 && r.outcome.created == 0)
        #expect(sim.fake.moveCount.isEmpty)
    }

    // MARK: - Pin, kuyruk, profil

    /// Numara pini planın ötesindeki masaüstünü hedefliyorsa temizlik onu
    /// silmez; geçiş de silmemeli (silmek pinleri kaydırır). Geçişin girdisinde
    /// pin bilgisi yoktu (PlanApply.Input), boş artık pin hedefi olsa da silinirdi.
    @Test func transitionNeverRemovesNumberPinTarget() {
        let live: [String: [UInt64]] = ["builtin": [5, 4, 6, 8, 1678, 1755]]
        let contents: [UInt64: [CGWindowID]] = [5: [1], 4: [2], 6: [3], 8: [4], 1678: [5]]
        let p = plans()
        // Temizlik: pin korur.
        #expect(PlanApply.cleanupRemovals(live: live, contents: contents, plans: p[.docked], named: [8],
                                          pending: [], pinned: ["builtin": 6]).isEmpty)
        // Geçiş: aynı masaüstü bu geçişin artığı (macOS açtı).
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: live, contents: contents, names: [n("AI", 8)], plans: p[.docked],
            leftovers: [1755], pinned: ["builtin": 6]))
        #expect(!out.removals.contains(1755))
        #expect(out.decisions.contains { $0.contains("space 1755") && $0.contains("a pin targets desktop 6") })
        // Pin yokken aynı artık silinir (koruma yalnız pinden gelir).
        let unpinned = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: live, contents: contents, names: [n("AI", 8)], plans: p[.docked],
            leftovers: [1755]))
        #expect(unpinned.removals == [1755])
    }

    /// Kuyruktaki silme ne geçişte ne temizlikte otomatik silinir.
    @Test func queuedRemovalIsNeverAutoRemoved() async {
        let sim = dockedSim()
        sim.fake.spaces["builtin"]!.append(1999)
        sim.pending = [1999]
        let before = sim.snapshot(.docked)
        await sim.transition(from: before, to: .docked)
        await sim.settle(.docked)
        #expect(sim.fake.spaces["builtin"]!.contains(1999))
        sim.pending = []
        await sim.settle(.docked)
        #expect(!sim.fake.spaces["builtin"]!.contains(1999))
    }

    /// Öbür profilde adlı, boş, planın ötesindeki masaüstü (laptop 6.):
    /// etkin profilin çıkarışı onu ICC'nin hedefi yapar (plan sırası 6),
    /// ICC'nin pencereleri oraya taşınır, R5 taşıma haritası OTHER adını
    /// sonraki takışta ICC'nin içeriğiyle sürükler ve 1990 silinir. Kullanıcı
    /// beklentisi: başka profilin adlı masaüstü bu profilin hedefi olmaz,
    /// silinmez, adı yerinde kalır.
    @Test func otherProfileNamedDesktopIsNotTakenOnUnplug() async {
        let sim = dockedSim()
        sim.fake.spaces["builtin"]!.append(1990)
        sim.otherNames = [n("OTHER", 1990)]
        let before = sim.snapshot(.docked)
        macUnplug(sim)
        let r = await sim.transition(from: before, to: .undocked)
        #expect(r.plan.rebinds["VEGA"] != s("builtin", 6))
        #expect(sim.fake.contents[1990, default: []].isEmpty)
        #expect(sim.fake.spaces["builtin"]!.contains(1990) && sim.otherNames.first?.space == 1990)
        #expect(windows(of: "VEGA").allSatisfy { sim.fake.location[$0] == sim.space(of: "VEGA") })
        #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty)
    }

    @Test func otherProfileNamedDesktopSurvivesCyclesAndCleanup() async {
        let sim = dockedSim()
        sim.fake.spaces["builtin"]!.append(1990)
        sim.otherNames = [n("OTHER", 1990)]
        for _ in 0..<3 {
            let before = sim.snapshot(.docked)
            let external = sim.fake.spaces["external"]!
            macUnplug(sim)
            await sim.transition(from: before, to: .undocked)
            await sim.settle(.undocked)
            let back = sim.fake.spaces["builtin"]!.filter { external.contains($0) }
            let before2 = sim.snapshot(.undocked)
            macPlug(sim, back: back, remember: windows(of: "HUB"))
            await sim.transition(from: before2, to: .docked)
            await sim.settle(.docked)
        }
        #expect(sim.fake.spaces["builtin"]!.contains(1990))
        #expect(sim.otherNames.first?.space == 1990)
        #expect(sim.removedNamed.isEmpty && !sim.fake.removedNonEmpty)
        #expect(sim.namesAtPlan(.docked).isEmpty)
    }

    /// 12.10 şikâyeti: adlar profilden bağımsızdı, yeni profilde eski adlar
    /// çıktı. Yeni (boş) profilin canlı masaüstü adları boş; eski profile
    /// dönünce adlar geri; çoğaltılan profilde ad silmek kaynağa dokunmaz.
    @Test func newProfileShowsNoOldNamesOnLiveDesktops() {
        var d = V6.document(names: [n("AI", 8), n("HUB", 1700)], plans: plans())
        let live = LiveDesktops(mode: .docked, spaces: ["builtin": [5, 4, 6, 8, 1678],
                                                        "external": [1700, 1738, 1714, 1713, 1712]])
        let original = d.activeProfileID
        #expect(d.desktopNames(for: .docked, live: live)["builtin"]?["4"] == "AI")
        d.addProfile(named: "Yeni")
        #expect(d.desktopNames(for: .docked, live: live).isEmpty)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: .docked, live: live) == nil)
        #expect(d.namedSpacesInAnyProfile == [8, 1700])   // öbür profilin bağları korunur
        let copy = d.duplicateProfile(original, named: "Kopya")!
        d.switchProfile(to: copy.id)
        #expect(d.desktopName(screen: "builtin", desktop: 4, mode: .docked, live: live) == "AI")
        d.setDesktopName(nil, screen: "builtin", desktop: 4, mode: .docked, live: live)
        d.switchProfile(to: original)
        #expect(d.desktopName(screen: "builtin", desktop: 4, mode: .docked, live: live) == "AI")
        #expect(d.desktopName(screen: "external", desktop: 1, mode: .docked, live: live) == "HUB")
    }

    // MARK: - Plan düzenleme

    /// Plan kısaltılınca (laptop 5 → 3) kararlı temizlik yalnız boş, adsız
    /// masaüstülerini siler; adlı (AI, planda olmasa da) ve dolu olan kalır.
    /// Plan uzatılınca bir sonraki uygulama yalnız eksik olanı açar, hiçbir
    /// pencere taşınmaz.
    @Test func planShortenAndExtend() async {
        let sim = dockedSim()
        sim.fake.location[101] = nil; sim.fake.location[102] = nil   // laptop 1 boş
        sim.fake.location[151] = nil                                  // laptop 5 boş
        sim.plans.set(["", "", ""], .docked, "builtin")
        await sim.settle(.docked)
        #expect(sim.fake.spaces["builtin"] == [5, 4, 6, 8])          // 1678 silindi, AI (8) kaldı
        #expect(sim.space(of: "AI") == 8)
        sim.plans.set(["", "", "", "AI", "", ""], .docked, "builtin")
        let r = await sim.transition(from: sim.snapshot(.docked), to: .docked)
        #expect(r.plan.creates == ["builtin": 2] && r.plan.moves.isEmpty)
        #expect(sim.fake.spaces["builtin"]!.count == 6)
        #expect(!sim.fake.removedNonEmpty && sim.removedNamed.isEmpty)
    }

    // MARK: - v6 göçü

    /// Göçten sonraki ilk plan uygulaması (12.10 19:16 kurulum): adlar
    /// pencerelerin masaüstüne bağlandığı için hiçbir pencere taşınmaz,
    /// hiçbir masaüstü açılmaz ya da silinmez; öbür profillerin bağları korunur.
    @Test func firstPlanAfterMigrationIsCalm() {
        let result = MigrationV6.migrate(V6.incidentDocument(), evidence: V6.evidence(V6.normalProfilWindows()))
        var d = result.document
        d.syncActiveProfile()
        var contents: [UInt64: [CGWindowID]] = [:]
        for (i, w) in V6.normalProfilWindows().enumerated() { contents[w.space, default: []].append(CGWindowID(i + 1)) }
        var otherNamed = Set<UInt64>()
        for profile in d.profiles where profile.id != d.activeProfileID {
            otherNamed.formUnion(profile.names.compactMap(\.space))
        }
        let out = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: V6.live.spaces, contents: contents, names: d.names, plans: d.plans[.docked],
            compactBeyondPlan: true, otherNamed: otherNamed))
        #expect(out.moves.isEmpty, "\(out.decisions)")
        #expect(out.creates.isEmpty && out.removals.isEmpty && out.rebinds.isEmpty)
        // Kararlı temizlik yalnız boş, adsız artıkları seçer; adlı/dolu olan kalır.
        let named = d.namedSpacesInAnyProfile
        let removals = PlanApply.cleanupRemovals(live: V6.live.spaces, contents: contents, plans: d.plans[.docked],
                                                 named: named, pending: [])
        #expect(removals.allSatisfy { !named.contains($0) && contents[$0] == nil })
    }

    // MARK: - Birden çok monitör

    /// İki monitör (external, external2) birlikte çıkar/takılır: her rolün
    /// adları kendi monitörüne döner, laptop plana yakınsar.
    @Test func twoMonitorsUnplugReplugEachGetsItsNames() async {
        var p = DesktopPlans()
        p.set(["", "AI"], .docked, "builtin")
        p.set(["A1", "A2"], .docked, "external")
        p.set(["B1", "B2"], .docked, "external2")
        p.set(["", "AI", "A1", "A2", "B1", "B2"], .undocked, "builtin")
        let fake = FakeDesktops(spaces: ["builtin": [1, 2], "external": [10, 11], "external2": [20, 21]],
                                location: [1: 1, 2: 2, 10: 10, 11: 11, 20: 20, 21: 21, 22: 21])
        fake.nextSpace = 100
        let sim = DeskSim(fake: fake, names: [n("AI", 2), n("A1", 10), n("A2", 11), n("B1", 20), n("B2", 21)],
                          plans: p)
        let before = sim.snapshot(.docked)
        // Çıkar: iki monitörün masaüstü 1'leri yok olur; pencereleri laptop 1'e.
        fake.location[10] = 1; fake.location[20] = 1
        fake.spaces = ["builtin": [1, 2, 11, 21]]
        await sim.transition(from: before, to: .undocked)
        await sim.settle(.undocked)
        #expect(fake.spaces["builtin"]!.count == 6)
        #expect(sim.namesAtPlan(.undocked).isEmpty)
        let before2 = sim.snapshot(.undocked)
        let a1 = sim.space(of: "A1")!, b1 = sim.space(of: "B1")!
        fake.spaces["builtin"]!.removeAll { [a1, 11, b1, 21].contains($0) }
        fake.spaces["external"] = [500, 11]
        fake.spaces["external2"] = [600, 21]
        fake.location[10] = 500; fake.location[20] = 600
        let r = await sim.transition(from: before2, to: .docked)
        #expect(r.plan.creates.isEmpty)
        await sim.settle(.docked)
        #expect(sim.namesAtPlan(.docked).isEmpty)
        #expect(fake.spaces.mapValues(\.count) == ["builtin": 2, "external": 2, "external2": 2])
        #expect(!fake.removedNonEmpty && sim.removedNamed.isEmpty)
    }

    // MARK: - macOS'un açtığı masaüstü

    /// Takışta macOS'un açtığı masaüstü 1 boş (pencereler monitörü
    /// hatırlamadı): planın ötesine açılış olmaz, ad o masaüstünü alır.
    @Test func emptyMacCreatedDesktopOneIsUsedNotExtended() async {
        let sim = dockedSim()
        let before = sim.snapshot(.docked)
        let external = sim.fake.spaces["external"]!
        macUnplug(sim)
        await sim.transition(from: before, to: .undocked)
        await sim.settle(.undocked)
        let back = sim.fake.spaces["builtin"]!.filter { external.contains($0) }
        let before2 = sim.snapshot(.undocked)
        let one = macPlug(sim, back: back, remember: [])
        let r = await sim.transition(from: before2, to: .docked)
        #expect(r.plan.creates.isEmpty)
        #expect(sim.space(of: "HUB") == one)
        await sim.settle(.docked)
        #expect(sim.fake.spaces["external"]!.count == 5 && sim.fake.spaces["builtin"]!.count == 5)
    }
}
