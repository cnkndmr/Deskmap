import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Boşta zamanlayıcı: ucuz imza, taramaya bağlı son tarihler ve tur kararı.
struct IdleTimerTests {

    private func entry(_ id: Int, pid: Int = 42, layer: Int = 0,
                       x: Double = 0, onscreen: Bool = true) -> [String: Any] {
        // Pencere sunucusunun döndürdüğü gibi NSNumber değerleri.
        [kCGWindowNumber as String: NSNumber(value: UInt32(id)),
         kCGWindowOwnerPID as String: NSNumber(value: Int32(pid)),
         kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowIsOnscreen as String: NSNumber(value: onscreen),
         kCGWindowBounds as String: ["X": NSNumber(value: x), "Y": NSNumber(value: 0.0),
                                     "Width": NSNumber(value: 800.0),
                                     "Height": NSNumber(value: 600.0)]]
    }

    // MARK: - İmza

    @Test func signatureIgnoresZOrder() {
        #expect(AX.serverSignature([entry(1), entry(2)]).rows.count == 2)
        #expect(AX.serverSignature([entry(1), entry(2)]) == AX.serverSignature([entry(2), entry(1)]))
    }

    @Test func signatureChangesOnMoveNewWindowAndSpaceSwitch() {
        let base = AX.serverSignature([entry(1), entry(2)])
        #expect(base != AX.serverSignature([entry(1, x: 50), entry(2)]))
        #expect(base != AX.serverSignature([entry(1), entry(2), entry(3)]))
        #expect(base != AX.serverSignature([entry(1), entry(2, onscreen: false)]))
    }

    @Test func signatureIgnoresNonZeroLayersAndSubPixelJitter() {
        let base = AX.serverSignature([entry(1)])
        #expect(base == AX.serverSignature([entry(1), entry(9, layer: 25)]))
        #expect(base == AX.serverSignature([entry(1, x: 0.2)]))
    }

    // MARK: - Son tarih

    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func noPendingWorkMeansNoDeadline() {
        #expect(Router.nextSweepDeadline(now: now, pendingSessionMisses: false, attempts: [:],
                                         lastAttempts: [:], backoffEnd: nil) == nil)
    }

    @Test func pendingSessionMissOrLayoutAttemptIsDueNow() {
        #expect(Router.nextSweepDeadline(now: now, pendingSessionMisses: true, attempts: [:],
                                         lastAttempts: [:], backoffEnd: nil) == now)
        #expect(Router.nextSweepDeadline(now: now, pendingSessionMisses: false,
                                         attempts: ["7|rule|laptop|1": 2],
                                         lastAttempts: [:], backoffEnd: nil) == now)
    }

    @Test func givenUpMoveWaitsForRetryInterval() {
        let key = "7|move|rule|laptop|1"
        let last = now.addingTimeInterval(-10)
        let deadline = Router.nextSweepDeadline(
            now: now, pendingSessionMisses: false,
            attempts: [key: Routing.maxMoveAttempts], lastAttempts: [key: last], backoffEnd: nil)
        #expect(deadline == last.addingTimeInterval(Routing.moveRetryInterval))
    }

    @Test func runningMoveIsDueNowAndEarliestWins() {
        let backoff = now.addingTimeInterval(8)
        #expect(Router.nextSweepDeadline(now: now, pendingSessionMisses: false, attempts: [:],
                                         lastAttempts: [:], backoffEnd: backoff) == backoff)
        #expect(Router.nextSweepDeadline(now: now, pendingSessionMisses: false,
                                         attempts: ["7|move|r|laptop|1": 1],
                                         lastAttempts: [:], backoffEnd: backoff) == now)
    }

    @Test func moveKeyDetection() {
        #expect(Routing.isMoveKey("7|move|r|laptop|1"))
        #expect(!Routing.isMoveKey("7|r|laptop|1"))
    }

    // MARK: - Tur kararı

    @Test func tickSweepsOnlyWhenSomethingIsDue() {
        func decide(changed: Bool = false, visible: Bool = false, deadline: Date? = nil,
                    since: TimeInterval = 5) -> Bool {
            Router.shouldSweepOnTick(signatureChanged: changed, mapVisible: visible,
                                     deadline: deadline, now: now, sinceLastSweep: since)
        }
        #expect(!decide())
        #expect(decide(changed: true))
        #expect(decide(visible: true))
        #expect(decide(deadline: now))
        #expect(!decide(deadline: now.addingTimeInterval(1)))
        #expect(decide(since: Router.idleSweepInterval))
    }
}

/// activationPolicy önbelleği: aynı pid süresi dolmadan yeniden sorulmaz.
struct ActivationPolicyCacheTests {

    @Test func fetchesOnceThenCachesUntilTTLOrForget() {
        let cache = ActivationPolicyCache()
        let now = Date()
        var fetches = 0
        func ask(_ at: Date, finished: Bool = true) -> Bool {
            cache.isRegular(pid: 42, finishedLaunching: finished, now: at) {
                fetches += 1
                return true
            }
        }
        #expect(ask(now))
        #expect(ask(now.addingTimeInterval(10)))
        #expect(fetches == 1)
        _ = ask(now.addingTimeInterval(ActivationPolicyCache.ttl + 1))
        #expect(fetches == 2)
        cache.forget(42)
        #expect(cache.count == 0)
    }

    @Test func unfinishedLaunchIsNotCached() {
        let cache = ActivationPolicyCache()
        _ = cache.isRegular(pid: 7, finishedLaunching: false, now: Date()) { false }
        #expect(cache.count == 0)
    }
}
