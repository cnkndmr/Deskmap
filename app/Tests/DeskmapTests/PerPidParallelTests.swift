import Foundation
import Testing
@testable import Deskmap

/// Uygulama başına paralel okuma (perf/PLAN-perf.md §3.3).
struct PerPidParallelTests {

    @Test func resultsKeepTheKeyOrder() {
        let keys = Array(0..<40)
        let out = AX.concurrently(keys) { key -> Int in
            usleep(useconds_t((40 - key) * 200))
            return key * 10
        }
        #expect(out == keys.map { $0 * 10 })
    }

    @Test func concurrencyStaysWithinTheLimit() {
        final class Counter: @unchecked Sendable {
            let lock = NSLock(); var now = 0; var peak = 0
            func enter() { lock.lock(); now += 1; peak = max(peak, now); lock.unlock() }
            func leave() { lock.lock(); now -= 1; lock.unlock() }
        }
        let counter = Counter()
        _ = AX.concurrently(Array(0..<30), limit: 3) { _ -> Int in
            counter.enter(); usleep(5_000); counter.leave(); return 0
        }
        #expect(counter.peak <= 3)
    }

    /// Donan bir uygulama (1 sn) ötekileri bekletmez: toplam süre en yavaş işe yakın.
    @Test func oneSlowAppDoesNotSerializeTheRest() {
        let start = Date()
        _ = AX.concurrently(Array(0..<12)) { key -> Int in
            usleep(key == 0 ? 300_000 : 50_000); return key
        }
        #expect(Date().timeIntervalSince(start) < 0.7)   // seri: 0,3 + 11 x 0,05 = 0,85 sn
    }
}
