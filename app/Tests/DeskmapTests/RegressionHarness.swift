import CoreGraphics
import Foundation
@testable import Deskmap

/// Sabit tohumlu üreteç (SplitMix64): rastgele/özellik tabanlı testler her
/// koşuda aynı girdileri üretir.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 09–13.10.2026 hatalarının regresyon düzeneği: macOS'u (FakeDesktops) ve
/// Router'ın saf geçiş/temizlik hattını (Succession → transitionExtras →
/// PlanApply.compute → PlanExecutor.run → bağların kaydı; cleanupPlan →
/// PlanExecutor.run) birlikte sürer. Gerçek veri ya da Mission Control yok.
@MainActor
final class DeskSim {
    let fake: FakeDesktops
    /// Etkin profilin adları.
    var names: [DesktopName]
    /// Öbür profilin adları (bağları silmeyi engeller, R5 ile taşınır).
    var otherNames: [DesktopName] = []
    var plans: DesktopPlans
    /// Numara pinleri: rol → en büyük hedef masaüstü (Router.pinnedDesktops).
    var pinned: [String: Int] = [:]
    /// Kuyruktaki silmeler.
    var pending: Set<UInt64> = []
    /// Yarıda kalan geçişin kaydettiği artıklar (Router: transition.leftovers).
    var savedLeftovers: Set<UInt64> = []
    /// Her başarılı silmeden sonra boşluk okuması bu kadar çağrı boyunca
    /// "dolu" döner (13.10 günlüğündeki geçici okuma; 0 = ideal macOS).
    var transientAfterRemoval = 0
    private var transientLeft = 0
    /// Bir adın bağlı olduğu space silindi mi (asla olmamalı).
    var removedNamed: [UInt64] = []
    /// Tüm silinen space'ler, sırayla.
    var removedLog: [UInt64] { fake.removed }
    /// Yürütücü dünyasına yapılan çağrı sayısı; `abortAtCall` ile kesinti.
    var calls = 0
    var abortAtCall: Int?

    init(fake: FakeDesktops, names: [DesktopName], plans: DesktopPlans) {
        self.fake = fake
        self.names = names
        self.plans = plans
    }

    var allNamedSpaces: Set<UInt64> {
        Set(names.compactMap(\.space)).union(otherNames.compactMap(\.space))
    }

    /// Yürütme sırasında asla silinmemesi gereken space'ler: planın
    /// taşıdığı (yeniden bağlanan ya da taşıma haritasındaki) adların eski
    /// yerleri hariç bütün ad bağları.
    private var guarded: Set<UInt64>?

    var world: PlanExecutor.World {
        var world = fake.world
        let base = fake.world
        world.isEmpty = { [unowned self] space in
            self.calls += 1
            if self.transientLeft > 0 {
                self.transientLeft -= 1
                return false
            }
            return base.isEmpty(space)
        }
        world.removeDesktop = { [unowned self] role, desktop, expected in
            self.calls += 1
            if (self.guarded ?? self.allNamedSpaces).contains(expected) { self.removedNamed.append(expected) }
            let ok = await base.removeDesktop(role, desktop, expected)
            if ok { self.transientLeft = self.transientAfterRemoval }
            return ok
        }
        world.addDesktop = { [unowned self] role in
            self.calls += 1
            return await base.addDesktop(role)
        }
        world.shouldAbort = { [unowned self] in
            if let at = self.abortAtCall, self.calls >= at { return true }
            return base.shouldAbort()
        }
        return world
    }

    func displays() -> [DesktopStateFile.Display] {
        fake.spaces.keys.sorted().map { .init(role: $0, uuid: $0, spaces: fake.spaces[$0]!) }
    }

    func refs() -> [String: [DesktopStateFile.WindowRef]] {
        var out: [String: [DesktopStateFile.WindowRef]] = [:]
        for (space, list) in fake.contents { out[String(space)] = list.map { .init(id: $0, pid: 1, bundleID: "") } }
        return out
    }

    struct Before {
        var displays: [DesktopStateFile.Display]
        var contents: [String: [DesktopStateFile.WindowRef]]
        var mode: Mode
    }

    func snapshot(_ mode: Mode) -> Before { Before(displays: displays(), contents: refs(), mode: mode) }

    /// Bir geçiş turu (Router.runTransition'ın saf kısmı). Yarıda kalırsa
    /// bağlar kaydedilir ve artıklar saklanır; yeniden çağrı aynı `before`
    /// ile kaldığı yerden hesaplar.
    @discardableResult
    func transition(from before: Before, to mode: Mode, compact: Bool = true)
        async -> (plan: PlanApply.Output, outcome: PlanExecutor.Outcome) {
        let live = LiveDesktops(mode: mode, spaces: fake.spaces)
        let snap = Succession.Snapshot(
            spaces: Dictionary(uniqueKeysWithValues: before.displays.map { ($0.role, $0.spaces) }),
            contents: DesktopStateFile.windowIDs(before.contents))
        let namedBefore = Set(names.compactMap(\.space))
        let succession = Succession.resolve(names: names, snapshot: snap, live: live,
                                            windowSpaces: fake.location, plans: plans)
        names = succession.names
        let other = Succession.resolve(names: otherNames, snapshot: snap, live: live,
                                       windowSpaces: fake.location, plans: plans)
        otherNames = other.names
        let extras = PlanApply.transitionExtras(
            from: before.displays, fromContents: before.contents, fromMode: before.mode, mode: mode,
            live: displays(), windowSpaces: fake.location, namedBefore: namedBefore, ruled: [],
            parked: [], now: Date())
        let input = PlanApply.Input(
            mode: mode, live: fake.spaces, contents: fake.contents, names: names, plans: plans[mode],
            evacuation: succession.evacuation, arriving: extras.arriving,
            leftovers: extras.leftovers.union(savedLeftovers), newSpaces: extras.newSpaces,
            compactBeyondPlan: compact, otherNamed: Set(otherNames.compactMap(\.space)), pending: pending)
        let plan = PlanApply.compute(input)
        var keep = Set<UInt64>()
        for name in names where plan.rebinds[name.id] == nil {
            if let space = name.space, plan.spaceMap[space] == nil { keep.insert(space) }
        }
        for name in otherNames { if let space = name.space, plan.spaceMap[space] == nil { keep.insert(space) } }
        guarded = keep
        transientLeft = 0
        defer { guarded = nil }
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                         allowRemovals: true, world: world)
        commit(out)
        savedLeftovers = out.aborted ? PlanExecutor.leftovers(of: plan, input: input, outcome: out) : []
        return (plan, out)
    }

    private func commit(_ out: PlanExecutor.Outcome) {
        for i in names.indices {
            if let space = out.rebinds[names[i].id] { names[i].space = space }
            else if let space = names[i].space, let next = out.spaceMap[space] { names[i].space = next }
        }
        for i in otherNames.indices {
            if let space = otherNames[i].space, let next = out.spaceMap[space] { otherNames[i].space = next }
        }
    }

    /// Kararlı durum temizliği (Router.runCleanup'ın saf kısmı). Silinen sayı.
    @discardableResult
    func cleanup(_ mode: Mode) async -> (planned: [UInt64], removed: Int) {
        var plan = PlanApply.Output()
        plan.removals = PlanApply.cleanupRemovals(
            live: fake.spaces, contents: fake.contents, plans: plans[mode], named: allNamedSpaces,
            pending: pending, pinned: pinned)
        transientLeft = 0
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                         allowRemovals: true, world: world)
        return (plan.removals, out.removed)
    }

    /// Kararlı taramalar: silinecek kalmayana dek en çok `sweeps` kez.
    func settle(_ mode: Mode, sweeps: Int = 3) async {
        for _ in 0..<sweeps {
            let result = await cleanup(mode)
            if result.planned.isEmpty { return }
        }
    }

    func place(_ id: String, mode: Mode) -> Slot? {
        names.first { $0.id == id }?.space.flatMap { LiveDesktops(mode: mode, spaces: fake.spaces).place(of: $0) }
    }

    func space(of id: String) -> UInt64? { names.first { $0.id == id }?.space }

    /// Planlı her ad planındaki yerde mi.
    func namesAtPlan(_ mode: Mode) -> [String] {
        var wrong: [String] = []
        for role in plans[mode].keys.sorted() {
            for (index, id) in plans.entries(mode, role).enumerated() where !id.isEmpty {
                if place(id, mode: mode) != Slot(screen: role, desktop: index + 1) { wrong.append(id) }
            }
        }
        return wrong
    }
}
