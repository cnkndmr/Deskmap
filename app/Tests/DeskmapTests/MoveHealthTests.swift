import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Taşıma doğrulaması ve devre kesici (saf).
struct MoveHealthTests {

    @Test func startsUnknownAndAllowsMoves() {
        let health = MoveHealth()
        #expect(health.state == .unknown)
        #expect(health.movesAllowed)
    }

    @Test func verifiedMoveMarksWorking() {
        var health = MoveHealth()
        let first = health.record(window: 1, verified: true)
        #expect(first)
        #expect(health.state == .working)
        let second = health.record(window: 2, verified: true)
        #expect(!second)
    }

    @Test func consecutiveFailuresOnDistinctWindowsOpenBreaker() {
        var health = MoveHealth()
        for i in 0..<(MoveHealth.failureLimit - 1) {
            health.record(window: CGWindowID(i % 2 + 1), verified: false)
        }
        #expect(health.movesAllowed)
        let opened = health.record(window: 1, verified: false)
        #expect(opened)
        #expect(health.state == .degraded)
        #expect(!health.movesAllowed)
    }

    /// Tek bir inatçı pencere bütün taşımayı durdurmaz.
    @Test func singleStubbornWindowDoesNotOpenBreaker() {
        var health = MoveHealth()
        for _ in 0..<(MoveHealth.failureLimit * 3) { health.record(window: 7, verified: false) }
        #expect(health.movesAllowed)
    }

    @Test func successResetsFailureCount() {
        var health = MoveHealth()
        for i in 0..<(MoveHealth.failureLimit - 1) {
            health.record(window: CGWindowID(i + 1), verified: false)
        }
        health.record(window: 9, verified: true)
        #expect(health.consecutiveFailures == 0)
        health.record(window: 1, verified: false)
        #expect(health.movesAllowed)
    }

    @Test func degradedStaysUntilResetEvenAfterLateSuccess() {
        var health = MoveHealth()
        for i in 0..<MoveHealth.failureLimit { health.record(window: CGWindowID(i + 1), verified: false) }
        #expect(health.state == .degraded)
        health.record(window: 1, verified: true)
        // Geç gelen tek doğrulama devreyi kapatmaz; kapatmak kullanıcının işi.
        #expect(health.state == .degraded)
        health.reset()
        #expect(health == MoveHealth())
    }

    // MARK: - Bekleyen taşıma doğrulaması

    private let now = Date(timeIntervalSinceReferenceDate: 500)

    @Test func tooFreshMoveWaits() {
        let pending = [CGWindowID(1): PendingMove(space: 10, issuedAt: now)]
        let check = PendingMove.verify(pending: pending, observed: [1: [11]], now: now)
        #expect(check.results.isEmpty)
        #expect(check.remaining == pending)
    }

    @Test func settledMoveIsVerifiedOrFailed() {
        let old = now.addingTimeInterval(-1)
        let pending = [CGWindowID(1): PendingMove(space: 10, issuedAt: old),
                       CGWindowID(2): PendingMove(space: 20, issuedAt: old)]
        let check = PendingMove.verify(pending: pending, observed: [1: [10], 2: [21]], now: now)
        #expect(check.results.map(\.window) == [1, 2])
        #expect(check.results.map(\.verified) == [true, false])
        #expect(check.remaining.isEmpty)
    }

    @Test func unknownSpacesWaitThenExpireWithoutCounting() {
        let pending = [CGWindowID(1): PendingMove(space: 10, issuedAt: now.addingTimeInterval(-2))]
        let waiting = PendingMove.verify(pending: pending, observed: [1: []], now: now)
        #expect(waiting.results.isEmpty)
        #expect(waiting.remaining.count == 1)
        let expired = PendingMove.verify(
            pending: pending, observed: [:], now: now.addingTimeInterval(PendingMove.expiry))
        #expect(expired.results.isEmpty)
        #expect(expired.remaining.isEmpty)
    }
}
