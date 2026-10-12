import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Sahte Mission Control + SkyLight: masaüstüleri ve pencere yerleri.
@MainActor
final class FakeDesktops {
    var spaces: [String: [UInt64]]
    var location: [CGWindowID: UInt64]
    var nextSpace: UInt64 = 9000
    var failAdds = false
    var addAtFront = false
    var failMoves: Set<CGWindowID> = []
    var abortWhen: (FakeDesktops) -> Bool = { _ in false }
    var moveCount: [CGWindowID: Int] = [:]
    var removed: [UInt64] = []
    var removedNonEmpty = false

    init(spaces: [String: [UInt64]], location: [CGWindowID: UInt64]) {
        self.spaces = spaces
        self.location = location
    }

    var contents: [UInt64: [CGWindowID]] {
        var result: [UInt64: [CGWindowID]] = [:]
        for (window, space) in location { result[space, default: []].append(window) }
        return result.mapValues { $0.sorted() }
    }

    var world: PlanExecutor.World {
        PlanExecutor.World(
            liveSpaces: { self.spaces },
            addDesktop: { role in
                guard !self.failAdds else { return false }
                self.nextSpace += 1
                if self.addAtFront { self.spaces[role, default: []].insert(self.nextSpace, at: 0) }
                else { self.spaces[role, default: []].append(self.nextSpace) }
                return true
            },
            move: { moves in
                var failed: [CGWindowID] = []
                for move in moves {
                    if self.failMoves.contains(move.window) { failed.append(move.window); continue }
                    self.location[move.window] = move.space
                    self.moveCount[move.window, default: 0] += 1
                }
                return failed
            },
            isEmpty: { space in !self.location.values.contains(space) },
            removeDesktop: { role, desktop, expected in
                guard var list = self.spaces[role], desktop >= 1, desktop <= list.count,
                      list[desktop - 1] == expected, list.count > 1 else { return false }
                if self.location.values.contains(expected) { self.removedNonEmpty = true }
                let neighbour = desktop > 1 ? list[desktop - 2] : list[1]
                for (window, space) in self.location where space == expected { self.location[window] = neighbour }
                list.remove(at: desktop - 1)
                self.spaces[role] = list
                self.removed.append(expected)
                return true
            },
            shouldAbort: { self.abortWhen(self) })
    }
}

@MainActor
struct PlanExecutorTests {
    private func s(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    @Test func abortBeforeStartDoesNothing() async {
        let fake = FakeDesktops(spaces: ["builtin": [1, 2]], location: [10: 1])
        fake.abortWhen = { _ in true }
        var plan = PlanApply.Output()
        plan.creates = ["builtin": 1]
        plan.moves = [.init(window: 10, to: s("builtin", 3))]
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: [10: 1],
                                         allowRemovals: true, world: fake.world)
        #expect(out.aborted && out.created == 0 && fake.moveCount.isEmpty)
    }

    @Test func desktopsChangedBeforeApplyAborts() async {
        let fake = FakeDesktops(spaces: ["builtin": [1, 2, 3]], location: [10: 1])
        var plan = PlanApply.Output()
        plan.moves = [.init(window: 10, to: s("builtin", 2))]
        let out = await PlanExecutor.run(plan, expected: ["builtin": [1, 3, 2]], windowSpaces: [10: 1],
                                         allowRemovals: true, world: fake.world)
        #expect(out.aborted && fake.moveCount.isEmpty)
    }

    @Test func createNotAtEndAbortsBeforeMoves() async {
        let fake = FakeDesktops(spaces: ["external": [1]], location: [10: 1])
        fake.addAtFront = true
        var plan = PlanApply.Output()
        plan.creates = ["external": 1]
        plan.moves = [.init(window: 10, to: s("external", 2))]
        let out = await PlanExecutor.run(plan, expected: ["external": [1]], windowSpaces: [10: 1],
                                         allowRemovals: true, world: fake.world)
        #expect(out.aborted && fake.moveCount.isEmpty)
    }

    @Test func failedCreateKeepsMovesToMissingSlotUndone() async {
        let fake = FakeDesktops(spaces: ["external": [1]], location: [10: 1, 11: 1])
        fake.failAdds = true
        var plan = PlanApply.Output()
        plan.creates = ["external": 2]
        plan.moves = [.init(window: 10, to: s("external", 2))]
        plan.removals = [1]
        let out = await PlanExecutor.run(plan, expected: ["external": [1]], windowSpaces: [10: 1, 11: 1],
                                         allowRemovals: true, world: fake.world)
        #expect(out.failedCreates == ["external"])
        #expect(out.failedMoves == [10])
        #expect(fake.removed.isEmpty && !fake.removedNonEmpty)
    }

    @Test func neverRemovesNonEmptyAndMoveFailureKeepsSource() async {
        let fake = FakeDesktops(spaces: ["builtin": [1, 2, 3, 4]], location: [10: 3, 11: 4, 12: 4])
        fake.failMoves = [12]
        // Plan dışı bir pencere 2'ye geldi (plan bilmiyordu).
        fake.location[99] = 2
        var plan = PlanApply.Output()
        plan.moves = [.init(window: 10, to: s("builtin", 1)), .init(window: 11, to: s("builtin", 1)),
                      .init(window: 12, to: s("builtin", 1))]
        plan.rebinds = ["N": s("builtin", 1)]
        plan.spaceMap = [4: s("builtin", 1)]
        plan.removals = [4, 3, 2]
        let out = await PlanExecutor.run(plan, expected: fake.spaces,
                                         windowSpaces: [10: 3, 11: 4, 12: 4],
                                         allowRemovals: true, world: fake.world)
        #expect(fake.removed == [3])
        #expect(!fake.removedNonEmpty)
        #expect(out.rebinds == ["N": 1])
        #expect(out.failedMoves == [12])
    }

    @Test func abortDuringRemovalsKeepsBindingsAndRemovesNothing() async {
        let fake = FakeDesktops(spaces: ["builtin": [1, 2, 3]], location: [10: 3])
        fake.abortWhen = { $0.moveCount[10] != nil }
        var plan = PlanApply.Output()
        plan.moves = [.init(window: 10, to: s("builtin", 2))]
        plan.rebinds = ["N": s("builtin", 2)]
        plan.spaceMap = [3: s("builtin", 2)]
        plan.removals = [3]
        let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: [10: 3],
                                         allowRemovals: true, world: fake.world)
        #expect(out.aborted)
        #expect(out.rebinds == ["N": 2] && out.spaceMap == [3: 2])
        #expect(fake.removed.isEmpty)
    }

    @Test func journalDoneByMajority() {
        let moves = [PlanExecutor.ResolvedMove(window: 1, space: 5), .init(window: 2, space: 5),
                     .init(window: 3, space: 6)]
        #expect(PlanExecutor.journalDone(moves, windowSpaces: [1: 5, 2: 5, 3: 9]))
        #expect(!PlanExecutor.journalDone(moves, windowSpaces: [1: 4, 2: 4, 3: 6]))
        #expect(!PlanExecutor.journalDone(moves, windowSpaces: [:]))
    }

    @Test func changeNeedsTwoObservations() {
        let a = [DesktopStateFile.Display(role: "builtin", uuid: "B", spaces: [1, 2])]
        let b = [DesktopStateFile.Display(role: "builtin", uuid: "B", spaces: [1])]
        let t0 = Date(timeIntervalSince1970: 0)
        let first = Router.confirmChange(pending: nil, observed: a, now: t0)
        #expect(!first.confirmed)
        let early = Router.confirmChange(pending: first.pending, observed: a, now: t0.addingTimeInterval(0.5))
        #expect(!early.confirmed)
        let other = Router.confirmChange(pending: first.pending, observed: b, now: t0.addingTimeInterval(2))
        #expect(!other.confirmed && other.pending?.displays == b)
        let late = Router.confirmChange(pending: first.pending, observed: a, now: t0.addingTimeInterval(2))
        #expect(late.confirmed && late.pending == nil)
    }

    @Test func displaysAgreeOnlyWhenSkyLightMatchesScreens() {
        #expect(Router.displaysAgree(sky: ["B", "E"], connected: ["B", "E"], separateSpaces: true))
        #expect(!Router.displaysAgree(sky: ["B"], connected: ["B", "E"], separateSpaces: true))
        #expect(!Router.displaysAgree(sky: ["B", "E"], connected: ["B"], separateSpaces: true))
        #expect(Router.displaysAgree(sky: ["B"], connected: ["B", "E"], separateSpaces: false))
    }

    /// Satır 1→2: "normal profil" monitör çıkar, sonra takılır. Silinen
    /// masaüstünde pencere yok, her ad planındaki yerinde, ikinci uygulama boş.
    @Test func unplugReplugCycleEndsAtPlanWithoutGhostMovesOrNonEmptyRemovals() async {
        func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }
        var names = [n("AI", 8), n("HUB", 1652), n("NOVA", 1653), n("ORION", 1681), n("EXPO", 1674), n("LUMEN", 1672)]
        var plans = DesktopPlans()
        plans.set(["", "", "", "AI", "HUB", "NOVA"], .docked, "builtin")
        plans.set(["ORION", "EXPO", "", "LUMEN"], .docked, "external")
        plans.set(["", "", "", "AI", "HUB", "NOVA", "EXPO", "LUMEN", "ORION", ""], .undocked, "builtin")
        let fake = FakeDesktops(
            spaces: ["builtin": [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680],
                     "external": [1681, 1674, 1673, 1672, 1032]],
            location: [1: 5, 2: 4, 3: 8, 4: 1652, 5: 1653, 10: 1681, 11: 1681, 12: 1674, 13: 1673, 14: 1672])
        func displays() -> [DesktopStateFile.Display] {
            fake.spaces.keys.sorted().map { .init(role: $0, uuid: $0, spaces: fake.spaces[$0]!) }
        }
        func refs() -> [String: [DesktopStateFile.WindowRef]] {
            var out: [String: [DesktopStateFile.WindowRef]] = [:]
            for (space, list) in fake.contents { out[String(space)] = list.map { .init(id: $0, pid: 1, bundleID: "") } }
            return out
        }
        func apply(from: [DesktopStateFile.Display], fromContents: [String: [DesktopStateFile.WindowRef]],
                   fromMode: Mode, mode: Mode) async -> PlanApply.Output {
            let live = LiveDesktops(mode: mode, spaces: fake.spaces)
            let snapshot = Succession.Snapshot(spaces: Dictionary(uniqueKeysWithValues: from.map { ($0.role, $0.spaces) }),
                                               contents: DesktopStateFile.windowIDs(fromContents))
            let namedBefore = Set(names.compactMap(\.space))
            let succession = Succession.resolve(names: names, snapshot: snapshot, live: live,
                                                windowSpaces: fake.location, plans: plans)
            names = succession.names
            let extras = PlanApply.transitionExtras(
                from: from, fromContents: fromContents, fromMode: fromMode, mode: mode, live: displays(),
                windowSpaces: fake.location, namedBefore: namedBefore, ruled: [], parked: [], now: Date())
            let plan = PlanApply.compute(PlanApply.Input(
                mode: mode, live: fake.spaces, contents: fake.contents, names: names, plans: plans[mode],
                evacuation: succession.evacuation, arriving: extras.arriving, leftovers: extras.leftovers))
            let out = await PlanExecutor.run(plan, expected: fake.spaces, windowSpaces: fake.location,
                                             allowRemovals: true, world: fake.world)
            #expect(!out.aborted)
            for i in names.indices {
                if let space = out.rebinds[names[i].id] { names[i].space = space }
                else if let space = names[i].space, let next = out.spaceMap[space] { names[i].space = next }
            }
            return plan
        }
        func place(_ id: String) -> Slot? {
            names.first { $0.id == id }?.space.flatMap { LiveDesktops(mode: .docked, spaces: fake.spaces).place(of: $0) }
        }

        // Çıkar: macOS monitör masaüstülerini pencereleriyle laptopun sonuna ekler.
        var before = displays(), beforeContents = refs()
        fake.spaces["builtin"]! += fake.spaces["external"]!
        fake.spaces["external"] = nil
        _ = await apply(from: before, fromContents: beforeContents, fromMode: .docked, mode: .undocked)
        #expect(!fake.removedNonEmpty)
        #expect(place("EXPO") == s("builtin", 7) && place("LUMEN") == s("builtin", 8) && place("ORION") == s("builtin", 9))
        #expect(place("AI") == s("builtin", 4) && place("HUB") == s("builtin", 5) && place("NOVA") == s("builtin", 6))
        #expect(fake.location[10] == fake.location[11] && fake.location[10] == names.first { $0.id == "ORION" }?.space)
        #expect(fake.spaces["builtin"]!.count == 10)

        // Tak: macOS yeni bir masaüstü 1 açar.
        before = displays(); beforeContents = refs()
        fake.spaces["external"] = [7777]
        _ = await apply(from: before, fromContents: beforeContents, fromMode: .undocked, mode: .docked)
        #expect(!fake.removedNonEmpty)
        #expect(place("ORION") == s("external", 1) && place("EXPO") == s("external", 2) && place("LUMEN") == s("external", 4))
        #expect(place("AI") == s("builtin", 4))
        #expect(fake.location[12] == names.first { $0.id == "EXPO" }?.space)
        #expect(fake.location[14] == names.first { $0.id == "LUMEN" }?.space)
        // Her pencere döngüde en çok iki kez (çıkar + tak) taşındı.
        #expect(fake.moveCount.values.allSatisfy { $0 <= 2 })

        // Aynı durumda yeniden uygulama hiçbir şey yapmaz (döngü yok).
        let again = PlanApply.compute(PlanApply.Input(
            mode: .docked, live: fake.spaces, contents: fake.contents, names: names, plans: plans[.docked]))
        #expect(again.isEmpty)
    }
}
