import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Taşıma doğrulamasının yaşı okuma anından (inceleme 24.10, `perf.verifyObservedAt`).
struct VerifyObservedAtTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 2000)

    /// Art arda turlar: taşıma t0'da; sonraki tur space'leri t0+0,3'te (henüz eski masaüstü) okur,
    /// ama uzun sürüp t0+0,8'de birleşir. Bugün: yaş 0,8 → "doğrulanmadı". Düzeltmeyle: yaş 0,3 → bekler.
    @Test func slowSweepDoesNotFailAMoveItReadTooEarly() {
        let pending: [CGWindowID: PendingMove] = [7: PendingMove(space: 20, issuedAt: t0)]
        let observed: [CGWindowID: [UInt64]] = [7: [10]]
        let readAt = t0.addingTimeInterval(0.3), mergedAt = t0.addingTimeInterval(0.8)

        let today = PendingMove.verify(pending: pending, observed: observed,
                                       now: Router.verifyTime(observedAt: readAt, merged: mergedAt, enabled: false))
        #expect(today.results.map(\.verified) == [false])

        let fixed = PendingMove.verify(pending: pending, observed: observed,
                                       now: Router.verifyTime(observedAt: readAt, merged: mergedAt, enabled: true))
        #expect(fixed.results.isEmpty)
        #expect(fixed.remaining[7] != nil)
    }

    /// Dört pencerede art arda bu durum bugün devre kesiciyi açar; düzeltmeyle açmaz.
    @Test func noFalseDegradedAcrossSweeps() {
        var health = MoveHealth()
        var fixedHealth = MoveHealth()
        for id: CGWindowID in [1, 2, 3, 4] {
            let issued = t0.addingTimeInterval(Double(id))
            let pending: [CGWindowID: PendingMove] = [id: PendingMove(space: 20, issuedAt: issued)]
            let read = issued.addingTimeInterval(0.3), merged = issued.addingTimeInterval(0.8)
            for r in PendingMove.verify(pending: pending, observed: [id: [10]],
                                        now: Router.verifyTime(observedAt: read, merged: merged, enabled: false)).results {
                health.record(window: r.window, verified: r.verified)
            }
            for r in PendingMove.verify(pending: pending, observed: [id: [10]],
                                        now: Router.verifyTime(observedAt: read, merged: merged, enabled: true)).results {
                fixedHealth.record(window: r.window, verified: r.verified)
            }
        }
        #expect(health.state == .degraded)
        #expect(fixedHealth.state == .unknown)
    }

    @Test func missingReadTimeFallsBackToMergeTime() {
        #expect(Router.verifyTime(observedAt: nil, merged: t0, enabled: true) == t0)
    }
}
