import Combine
import Foundation
import Testing
@testable import Deskmap

/// Başlık olaylarından tarama isteği (perf/PLAN-perf.md §6.3).
struct TitleThrottleTests {

    /// Aralıktan sık gelen başlık olayları: debounce hiç tetiklemez, throttle tetikler.
    private func fires(throttle: Bool) -> Int {
        let subject = PassthroughSubject<pid_t, Never>()
        let queue = DispatchQueue(label: "test.title")
        let lock = NSLock()
        nonisolated(unsafe) var count = 0
        let cancellable = Router.titleSweeps(subject.eraseToAnyPublisher(), throttle: throttle,
                                             scheduler: queue, interval: .milliseconds(100))
            .sink { _ in lock.lock(); count += 1; lock.unlock() }
        for _ in 0..<20 { queue.sync { subject.send(42) }; usleep(30_000) }
        cancellable.cancel()
        lock.lock(); defer { lock.unlock() }
        return count
    }

    @Test func debounceNeverFiresOnAFastTitle() { #expect(fires(throttle: false) == 0) }
    @Test func throttleFiresOnAFastTitle() { #expect(fires(throttle: true) >= 3) }
}
