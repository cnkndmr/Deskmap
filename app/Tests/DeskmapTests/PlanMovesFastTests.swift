import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// perf/PLAN-perf.md §4.2 B5: plan taşımaları.
struct PlanMovesFastTests {

    private let builtin = ScreenInfo(id: "builtin", uuid: "B", name: "Built-in", isBuiltin: true,
                                     frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
    private let external = ScreenInfo(id: "external", uuid: "E", name: "Dell", isBuiltin: false,
                                      frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                                      visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415))
    private var screens: [ScreenInfo] { [builtin, external] }

    /// Taklit dünya: taşıma isteği `lag` okuma sonra görülür; `bounceAfter` verilirse
    /// pencere o kadar okumadan sonra eski masaüstüne geri seker (bir kez).
    final class World: @unchecked Sendable {
        var space: [CGWindowID: UInt64]
        var pending: [CGWindowID: (space: UInt64, reads: Int)] = [:]
        var moveCalls = 0
        var bounce: (window: CGWindowID, after: Int, to: UInt64)?
        var readsSinceArrival: [CGWindowID: Int] = [:]
        var bounds: [CGWindowID: CGRect] = [:]
        var frameLag: [CGWindowID: (frame: CGRect, reads: Int)] = [:]
        var boundsCalls = 0
        let lag: Int
        init(space: [CGWindowID: UInt64], lag: Int = 1) { self.space = space; self.lag = lag }
        func spaces(_ id: CGWindowID) -> [UInt64]? {
            if var p = pending[id] {
                p.reads -= 1
                if p.reads <= 0 { space[id] = p.space; pending[id] = nil; readsSinceArrival[id] = 0 } else { pending[id] = p }
            } else if let b = bounce, b.window == id, let n = readsSinceArrival[id] {
                readsSinceArrival[id] = n + 1
                if n + 1 >= b.after { space[id] = b.to; bounce = nil }
            }
            return space[id].map { [$0] }
        }
        func move(_ id: CGWindowID, _ to: UInt64) { moveCalls += 1; pending[id] = (to, lag) }
        func readBounds(_ ids: [CGWindowID]) -> [CGWindowID: CGRect] {
            boundsCalls += 1
            for (id, lagging) in frameLag {
                if lagging.reads <= 1 { bounds[id] = lagging.frame; frameLag[id] = nil }
                else { frameLag[id] = (lagging.frame, lagging.reads - 1) }
            }
            return bounds.filter { ids.contains($0.key) }
        }
    }

    private func run(_ world: World, moves: [(window: CGWindowID, space: UInt64)], pids: [CGWindowID: pid_t] = [:],
                     target: ScreenInfo? = nil, refit: @escaping @Sendable (CGWindowID, pid_t, ScreenInfo) -> CGRect? = { _, _, _ in nil })
        -> (failed: [CGWindowID], slept: TimeInterval) {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        var slept: TimeInterval = 0
        let failed = Router.performMovesFast(
            moves, pids: pids, screens: screens, screenOf: { _ in target ?? self.builtin },
            spaces: world.spaces, move: world.move, bounds: world.readBounds, refit: refit,
            sleep: { clock = clock.addingTimeInterval($0); slept += $0 }, now: { clock })
        return (failed, slept)
    }

    @Test func arrivalIsPolledNotSlept() {
        let world = World(space: [1: 10, 2: 10])
        let out = run(world, moves: [(1, 20), (2, 20)])
        #expect(out.failed.isEmpty)
        #expect(world.moveCalls == 2)
        // 20 ms yoklama + 200 ms onay; bugünkü yol en az 200 ms uyur, sonra döner.
        #expect(out.slept < 0.25)
    }

    /// Varıp geri seken pencere onay okumasında yakalanır ve yeniden taşınır.
    @Test func bounceBackIsCaughtByTheConfirmRead() {
        let world = World(space: [1: 10])
        world.bounce = (1, 1, 10)
        let out = run(world, moves: [(1, 20)])
        #expect(out.failed.isEmpty)
        #expect(world.moveCalls == 2)
    }

    @Test func windowThatNeverArrivesFailsAfterThreeRounds() {
        let world = World(space: [1: 10], lag: 1000)
        let out = run(world, moves: [(1, 20)])
        #expect(out.failed == [1])
        #expect(world.moveCalls == 3)
    }

    /// Refit kararı AX'siz: hedef ekrandaki pencereye dokunulmaz, başka ekrandakine dokunulur.
    @Test func refitOnlyWhenTheScreenChanges() {
        let onBuiltin = CGRect(x: 100, y: 100, width: 600, height: 400)
        let onExternal = CGRect(x: 1700, y: 100, width: 600, height: 400)
        #expect(!Router.needsRefit(bounds: onBuiltin, target: builtin, screens: screens))
        #expect(Router.needsRefit(bounds: onExternal, target: builtin, screens: screens))
        #expect(Router.needsRefit(bounds: nil, target: builtin, screens: screens))
    }

    /// Refit edilen pencerenin çerçevesi masaüstü varışından sonra otursa da beklenir.
    @Test func waitsForTheRefitFrameToSettle() {
        let world = World(space: [1: 10, 2: 10])
        let written = CGRect(x: 50, y: 60, width: 500, height: 300)
        world.bounds = [1: CGRect(x: 1700, y: 100, width: 600, height: 400),
                        2: CGRect(x: 100, y: 100, width: 600, height: 400)]
        world.frameLag = [1: (written, 6)]
        let refitted = NSLock()
        nonisolated(unsafe) var calls: [CGWindowID] = []
        let out = run(world, moves: [(1, 20), (2, 20)], pids: [1: 100, 2: 200], target: builtin) { id, _, _ in
            refitted.lock(); calls.append(id); refitted.unlock()
            return written
        }
        #expect(out.failed.isEmpty)
        #expect(calls == [1])
        #expect(world.bounds[1] == written)
    }
}
