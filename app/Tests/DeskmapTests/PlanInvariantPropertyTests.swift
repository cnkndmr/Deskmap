import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Plan ve temizlik değişmezleri üzerinde sabit tohumlu rastgele testler
/// (docs/test-matrix-2026-10.md, "Değişmezler"). Her vaka yeniden üretilebilir:
/// başarısızlık iletisinde tohum ve vaka numarası var.
@MainActor
struct PlanInvariantPropertyTests {

    struct Case {
        var mode: Mode
        var live: [String: [UInt64]]
        var location: [CGWindowID: UInt64]
        var names: [DesktopName]
        var plans: [String: [String]]
        var leftovers: Set<UInt64>
        var newSpaces: Set<UInt64>
        var otherNamed: Set<UInt64>
        var pending: Set<UInt64>
        var pinned: [String: Int]
        var compact: Bool

        var contents: [UInt64: [CGWindowID]] {
            var result: [UInt64: [CGWindowID]] = [:]
            for (window, space) in location { result[space, default: []].append(window) }
            return result.mapValues { $0.sorted() }
        }
    }

    static func makeCase(_ rng: inout SeededRNG) -> Case {
        let roles = Bool.random(using: &rng) ? ["builtin", "external"] : ["builtin"]
        var next: UInt64 = 100
        var live: [String: [UInt64]] = [:]
        for role in roles {
            live[role] = (0..<Int.random(in: 1...9, using: &rng)).map { _ in next += 1; return next }
        }
        let all = live.values.flatMap { $0 }
        var location: [CGWindowID: UInt64] = [:]
        var window: CGWindowID = 1
        for space in all where Int.random(in: 0..<3, using: &rng) > 0 {
            for _ in 0..<Int.random(in: 1...3, using: &rng) { location[window] = space; window += 1 }
        }
        // Adlar: bir kısmı canlı space'e bağlı (tekil), bir kısmı yerleşmemiş, biri kaybolmuş space'e.
        var names: [DesktopName] = []
        var used = Set<UInt64>()
        for i in 0..<Int.random(in: 0...7, using: &rng) {
            var space: UInt64?
            switch Int.random(in: 0..<5, using: &rng) {
            case 0: space = nil
            case 1: space = 9000 + UInt64(i)
            default:
                if let pick = all.filter({ !used.contains($0) }).randomElement(using: &rng) {
                    space = pick
                    used.insert(pick)
                }
            }
            names.append(DesktopName(id: "N\(i)", name: "N\(i)", space: space))
        }
        // Planlar: her ad en çok bir kez (kurulum içinde), "" girdiler serbest.
        var plans: [String: [String]] = [:]
        var pool = names.map(\.id).shuffled(using: &rng)
        for role in roles {
            var entries: [String] = []
            for _ in 0..<Int.random(in: 0...7, using: &rng) {
                if Bool.random(using: &rng), let id = pool.popLast() { entries.append(id) } else { entries.append("") }
            }
            plans[role] = entries
        }
        func subset(_ p: Int) -> Set<UInt64> { Set(all.filter { _ in Int.random(in: 0..<100, using: &rng) < p }) }
        let leftovers = subset(40)
        let newSpaces = leftovers.filter { _ in Bool.random(using: &rng) }
        let otherNamed = subset(10).subtracting(used)
        let pending = subset(8)
        var pinned: [String: Int] = [:]
        for role in roles where Bool.random(using: &rng) { pinned[role] = Int.random(in: 1...9, using: &rng) }
        return Case(mode: .docked, live: live, location: location, names: names, plans: plans,
                     leftovers: leftovers, newSpaces: newSpaces, otherNamed: otherNamed, pending: pending,
                     pinned: pinned, compact: Bool.random(using: &rng))
    }

    private func input(_ c: Case) -> PlanApply.Input {
        PlanApply.Input(mode: c.mode, live: c.live, contents: c.contents, names: c.names, plans: c.plans,
                        leftovers: c.leftovers, newSpaces: c.newSpaces, compactBeyondPlan: c.compact,
                        otherNamed: c.otherNamed, pending: c.pending)
    }

    /// PlanApply.compute: hiçbir koşulda dolu (taşınmayan pencereli), adlı
    /// (bu ya da öbür profilde, taşınmayan), kuyruktaki, planın içindeki ya da
    /// rolün son masaüstü silinmez; sınırlar aşılmaz; pencere bir kez taşınır;
    /// hedefler var olacak masaüstülerinde.
    @Test func computeNeverRemovesWhatMustStay() {
        var rng = SeededRNG(seed: 20261013)
        for index in 0..<500 {
            let c = Self.makeCase(&rng)
            let out = PlanApply.compute(input(c))
            let label = "case \(index)"
            let moved = Set(out.moves.map(\.window))
            #expect(moved.count == out.moves.count, "\(label): window moved twice")
            #expect(out.removals.count <= 8, "\(label)")
            #expect(Set(out.removals).count == out.removals.count, "\(label): duplicate removal")
            for (role, count) in out.creates { #expect(count <= 8, "\(label) \(role)") }
            let rebound = Set(out.rebinds.keys)
            var stillNamed = Set<UInt64>()
            for name in c.names where !rebound.contains(name.id) {
                if let space = name.space, out.spaceMap[space] == nil { stillNamed.insert(space) }
            }
            let otherStill = c.otherNamed.filter { out.spaceMap[$0] == nil }
            for space in out.removals {
                let role = c.live.first { $0.value.contains(space) }!.key
                let list = c.live[role]!
                let position = list.firstIndex(of: space)! + 1
                #expect(position > max(1, c.plans[role]?.count ?? 0), "\(label): removes inside the plan")
                #expect(!c.pending.contains(space), "\(label): removes queued \(space)")
                #expect(!stillNamed.contains(space), "\(label): removes named \(space)")
                #expect(!otherStill.contains(space), "\(label): removes other-profile named \(space)")
                let stays = (c.contents[space] ?? []).filter { !moved.contains($0) }
                #expect(stays.isEmpty, "\(label): removes non-empty \(space)")
                #expect(c.leftovers.contains(space) || out.spaceMap[space] != nil,
                        "\(label): removes a non-leftover \(space)")
                // Silinen masaüstüne pencere gelmez.
                #expect(!out.moves.contains { $0.to == Slot(screen: role, desktop: position) }, "\(label)")
            }
            for role in c.live.keys {
                let removed = out.removals.filter { c.live[role]!.contains($0) }.count
                #expect(c.live[role]!.count + (out.creates[role] ?? 0) - removed >= 1, "\(label): role emptied")
            }
            for move in out.moves {
                let limit = (c.live[move.to.screen]?.count ?? 0) + (out.creates[move.to.screen] ?? 0)
                #expect(move.to.desktop >= 1 && move.to.desktop <= limit, "\(label): move to missing desktop")
                #expect(c.location[move.window] != nil, "\(label): moves unknown window")
            }
        }
    }

    /// Plan uygulandıktan sonra aynı plan yeniden hesaplanınca iş yok
    /// (idempotentlik); bir sınır aşılmadıysa ve ad atlanmadıysa.
    @Test func applyingTwiceIsIdempotent() async {
        var rng = SeededRNG(seed: 4242)
        var checked = 0
        for index in 0..<300 {
            let c = Self.makeCase(&rng)
            let fake = FakeDesktops(spaces: c.live, location: c.location)
            fake.nextSpace = 5000
            let first = PlanApply.compute(input(c))
            guard !first.truncated, first.skippedNames.isEmpty else { continue }
            let out = await PlanExecutor.run(first, expected: c.live, windowSpaces: c.location,
                                             allowRemovals: true, world: fake.world)
            #expect(!fake.removedNonEmpty, "case \(index)")
            guard !out.aborted, out.failedMoves.isEmpty else { continue }
            var names = c.names
            for i in names.indices {
                if let space = out.rebinds[names[i].id] { names[i].space = space }
                else if let space = names[i].space, let next = out.spaceMap[space] { names[i].space = next }
            }
            let otherNamed = Set(c.otherNamed.compactMap { space -> UInt64? in
                out.spaceMap[space] ?? (fake.spaces.values.contains { $0.contains(space) } ? space : nil)
            })
            let second = PlanApply.compute(PlanApply.Input(
                mode: c.mode, live: fake.spaces, contents: fake.contents, names: names, plans: c.plans,
                compactBeyondPlan: c.compact, otherNamed: otherNamed, pending: c.pending))
            #expect(second.moves.isEmpty && second.creates.values.allSatisfy { $0 == 0 },
                    "case \(index): second pass not idempotent: \(second.decisions)")
            #expect(second.removals.isEmpty, "case \(index)")
            checked += 1
        }
        #expect(checked > 100)
    }

    /// Temizlik: yalnız planın ötesinde, boş, adsız, kuyrukta olmayan,
    /// pin hedefi olmayan masaüstü; her rolde en az biri kalır; yürütüldükten
    /// sonra ikinci temizlik bir şey bulmaz (sınır aşılmadıysa).
    @Test func cleanupInvariantsAndIdempotence() async {
        var rng = SeededRNG(seed: 777)
        for index in 0..<500 {
            let c = Self.makeCase(&rng)
            let named = Set(c.names.compactMap(\.space)).union(c.otherNamed)
            let decisions = PlanApply.cleanupPlan(live: c.live, contents: c.contents, plans: c.plans,
                                                  named: named, pending: c.pending, pinned: c.pinned)
            let removals = decisions.filter { $0.kept == nil }
            for d in removals {
                #expect(d.desktop > max(1, c.plans[d.role]?.count ?? 0), "case \(index)")
                #expect(d.desktop > (c.pinned[d.role] ?? 0), "case \(index): pin target")
                #expect(!named.contains(d.space) && !c.pending.contains(d.space), "case \(index)")
                #expect((c.contents[d.space] ?? []).isEmpty, "case \(index): non-empty")
            }
            for role in c.live.keys {
                #expect(c.live[role]!.count - removals.filter { $0.role == role }.count >= 1, "case \(index)")
            }
            let fake = FakeDesktops(spaces: c.live, location: c.location)
            var plan = PlanApply.Output()
            plan.removals = removals.map(\.space)
            let out = await PlanExecutor.run(plan, expected: c.live, windowSpaces: c.location,
                                             allowRemovals: true, world: fake.world)
            #expect(out.removed == removals.count && !fake.removedNonEmpty, "case \(index)")
            if removals.count < 8 {
                let again = PlanApply.cleanupRemovals(live: fake.spaces, contents: fake.contents, plans: c.plans,
                                                      named: named, pending: c.pending, pinned: c.pinned)
                #expect(again.isEmpty, "case \(index): cleanup not idempotent")
            }
        }
    }

    /// Rastgele tak-çıkar dizileri (macOS'un döndürdüğü space alt kümesi ve
    /// sırası, masaüstü 1'e dönen pencereler, laptopun o anki masaüstü,
    /// geçiş ortasında kesinti rastgele): her kararlı durumda sayı == plan,
    /// adlar yerinde, adlı ya da dolu masaüstü hiç silinmez.
    @Test func randomPlugSequencesConverge() async {
        let failures = await randomPlugSequences(interrupts: false)
        #expect(failures.isEmpty, "\(failures)")
    }

    /// Aynı diziler, geçişler rastgele yarıda kesilip aynı "önce" durumundan
    /// yeniden başlatılarak. Tohum 3: macOS adın pencerelerini dolu bir laptop
    /// masaüstüne kattığında (ad yerleşmemiş + tahliye kümesi) geçiş yarıda
    /// kalırsa tahliye kümesi kaybolurdu; düzeltme: Transition.evacuation (bkz.
    /// Regression202610Tests.interruptedEvacuationKeepsNameWithWindows).
    @Test func randomPlugSequencesWithInterruptsConverge() async {
        let failures = await randomPlugSequences(interrupts: true)
        #expect(failures.isEmpty, "\(failures)")
    }

    /// Başarısız (tohum, adım, neden) listesi.
    private func randomPlugSequences(interrupts: Bool) async -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { failures.append(what()) } }
        for seed: UInt64 in [1, 2, 3, 5, 8, 13, 21, 34] {
            var rng = SeededRNG(seed: seed)
            var plans = DesktopPlans()
            plans.set(["", "", "", "AI", ""], .docked, "builtin")
            plans.set(["HUB", "VEGA", "EXPO", "LUMEN", "ORION"], .docked, "external")
            plans.set(["", "", "", "AI", "HUB", "VEGA", "EXPO", "LUMEN", "ORION", ""], .undocked, "builtin")
            var location: [CGWindowID: UInt64] = [1: 5, 2: 4, 3: 6, 4: 8, 5: 1678]
            let ext: [UInt64] = [1700, 1738, 1714, 1713, 1712]
            for (i, space) in ext.enumerated() { for k in 0..<2 { location[CGWindowID(100 + i * 10 + k)] = space } }
            let fake = FakeDesktops(spaces: ["builtin": [5, 4, 6, 8, 1678], "external": ext], location: location)
            fake.nextSpace = 3000
            let ids = ["HUB", "VEGA", "EXPO", "LUMEN", "ORION"]
            let sim = DeskSim(fake: fake, names: [DesktopName(id: "AI", name: "AI", space: 8)]
                              + zip(ids, ext).map { DesktopName(id: $0, name: $0, space: $1) }, plans: plans)
            var everExternal = Set(ext)
            for step in 0..<6 {
                let label = "seed \(seed) step \(step)"
                // Çıkar.
                let before = sim.snapshot(.docked)
                let external = fake.spaces["external"]!
                everExternal.formUnion(external)
                let current = Int.random(in: 0..<fake.spaces["builtin"]!.count, using: &rng)
                for (w, sp) in fake.location where sp == external[0] { fake.location[w] = fake.spaces["builtin"]![current] }
                fake.spaces["builtin"]! += external.dropFirst()
                fake.spaces["external"] = nil
                await runWithRandomInterrupt(sim, before: before, mode: .undocked, interrupts: interrupts, rng: &rng)
                await sim.settle(.undocked, sweeps: 4)
                check(fake.spaces["builtin"]!.count == 10, "\(label) undocked \(fake.spaces)")
                check(sim.namesAtPlan(.undocked).isEmpty, "\(label) undocked names")
                // Tak.
                let before2 = sim.snapshot(.undocked)
                var back = fake.spaces["builtin"]!.filter { everExternal.contains($0) }.shuffled(using: &rng)
                back = Array(back.prefix(Int.random(in: 0...back.count, using: &rng)))
                fake.nextSpace += 1
                let one = fake.nextSpace
                fake.spaces["builtin"]!.removeAll { back.contains($0) }
                fake.spaces["external"] = [one] + back
                if Bool.random(using: &rng), let br = sim.space(of: "HUB") {
                    for (w, sp) in fake.location where sp == br { fake.location[w] = one }
                }
                await runWithRandomInterrupt(sim, before: before2, mode: .docked, interrupts: interrupts, rng: &rng)
                await sim.settle(.docked, sweeps: 4)
                check(fake.spaces["builtin"]!.count == 5, "\(label) docked \(fake.spaces)")
                check(fake.spaces["external"]!.count == 5, "\(label) docked \(fake.spaces)")
                check(sim.namesAtPlan(.docked).isEmpty, "\(label) docked names \(sim.namesAtPlan(.docked))")
                for (i, id) in ids.enumerated() {
                    for k in 0..<2 {
                        check(fake.location[CGWindowID(100 + i * 10 + k)] == sim.space(of: id), "\(label) \(id) window")
                    }
                }
            }
            check(!fake.removedNonEmpty, "seed \(seed)")
            check(sim.removedNamed.isEmpty, "seed \(seed)")
        }
        return failures
    }

    private func runWithRandomInterrupt(_ sim: DeskSim, before: DeskSim.Before, mode: Mode,
                                        interrupts: Bool, rng: inout SeededRNG) async {
        sim.calls = 0
        let roll = Int.random(in: 0..<4, using: &rng) == 0
        let at = Int.random(in: 1...8, using: &rng)
        sim.abortAtCall = interrupts && roll ? at : nil
        var r = await sim.transition(from: before, to: mode)
        sim.abortAtCall = nil
        var tries = 0
        while r.outcome.aborted && tries < 3 {
            tries += 1
            r = await sim.transition(from: before, to: mode)
        }
    }
}
