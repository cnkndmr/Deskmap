import Foundation
import Testing
@testable import Deskmap

/// Uygulama başına paralel okuma (perf/PLAN-perf.md §3.3). Testler süreye değil
/// sıraya/sayaca dayanır: yüklü makinede de aynı sonucu verir.
struct PerPidParallelTests {

    @Test func resultsKeepTheKeyOrder() {
        let keys = Array(0..<40)
        let out = AX.concurrently(keys) { key -> Int in
            usleep(useconds_t((40 - key) * 200))
            return key * 10
        }
        #expect(out == keys.map { $0 * 10 })
    }

    final class Counter: @unchecked Sendable {
        let lock = NSLock(); var now = 0; var peak = 0
        func enter() { lock.lock(); now += 1; peak = max(peak, now); lock.unlock() }
        func leave() { lock.lock(); now -= 1; lock.unlock() }
    }

    /// Sınır 3: her iş içeride bir eş görene dek bekler (bariyer, süre yok; son iş
    /// ötekiler bitince geçer), yani en az 2 eşzamanlılık kanıtlanır; tepe 3'ü aşmaz.
    @Test func concurrencyStaysWithinTheLimit() {
        let counter = Counter()
        let changed = NSCondition()
        var finished = 0, timedOut = 0
        let total = 30
        _ = AX.concurrently(Array(0..<total), limit: 3) { _ -> Int in
            changed.lock()
            counter.enter(); changed.broadcast()
            let deadline = Date().addingTimeInterval(5)
            while counter.now < 2 && finished < total - 1 {
                if !changed.wait(until: deadline) { timedOut += 1; break }
            }
            counter.leave(); finished += 1; changed.broadcast()
            changed.unlock()
            return 0
        }
        #expect(counter.peak <= 3)
        #expect(counter.peak >= 2)
        #expect(timedOut == 0)
    }

    /// İşler gerçekten eşzamanlı: her iş bir öbürü başlayana dek bekler.
    /// Seri yolda ilk iş kimseyi bulamaz ve zaman aşımına düşer.
    @Test func workRunsConcurrently() {
        let started = DispatchSemaphore(value: 0)
        let partner = DispatchSemaphore(value: 0)
        let timedOut = Counter()
        _ = AX.concurrently([0, 1], limit: 2) { key -> Int in
            if key == 0 {
                if started.wait(timeout: .now() + 5) == .timedOut { timedOut.enter() }
                partner.signal()
            } else {
                started.signal()
                if partner.wait(timeout: .now() + 5) == .timedOut { timedOut.enter() }
            }
            return key
        }
        #expect(timedOut.peak == 0)
    }

    /// Donan bir uygulama ötekileri bekletmez: yavaş iş, ötekilerin hepsi bitene
    /// dek bırakılmaz; seri yolda bu bekleyiş zaman aşımına düşerdi.
    @Test func oneSlowAppDoesNotSerializeTheRest() {
        let others = DispatchSemaphore(value: 0)
        let blocked = Counter()
        _ = AX.concurrently(Array(0..<12)) { key -> Int in
            if key == 0 {
                for _ in 1..<12 where others.wait(timeout: .now() + 5) == .timedOut { blocked.enter() }
            } else {
                others.signal()
            }
            return key
        }
        #expect(blocked.peak == 0)
    }
}
