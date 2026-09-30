import Testing
@testable import Deskmap

/// Plan/silme hedefleri: yalnız gerçek başarısızlık oturum boyunca engeller.
struct PlannedAttemptsTests {

    private let key = "remove|docked|external|1"

    /// Hedefi bir kez dener, verilen sonuçla bitirir; aynı hedef yeniden
    /// başlayabiliyor mu.
    private func restarts(after outcome: PlannedAttempts.Outcome) -> Bool {
        var attempts = PlannedAttempts()
        _ = attempts.begin(key)
        attempts.finish(key, outcome)
        return attempts.begin(key)
    }

    @Test func runningAttemptBlocksASecondOne() {
        var attempts = PlannedAttempts()
        let first = attempts.begin(key)
        let second = attempts.begin(key)
        let other = attempts.begin("add|docked|external|3")
        #expect(first)
        #expect(!second)
        #expect(other)
    }

    @Test func finishedAttemptCanBePlannedAgain() {
        #expect(restarts(after: .done))
    }

    @Test func interruptedAttemptIsRetried() {
        #expect(restarts(after: .interrupted))
    }

    @Test func failedAttemptStaysBlockedForTheSession() {
        #expect(!restarts(after: .failed))
        // Başka sayı başka hedef: kısmen ilerlemiş kuyruk ayrı denenir.
        var attempts = PlannedAttempts()
        _ = attempts.begin(key)
        attempts.finish(key, .failed)
        let shorter = attempts.begin("remove|docked|external|2")
        #expect(shorter)
    }

    @Test func addOutcomeFollowsTheLiveCount() {
        #expect(PlannedAttempts.addOutcome(live: 3, want: 3, interrupted: false) == .done)
        #expect(PlannedAttempts.addOutcome(live: 4, want: 3, interrupted: true) == .done)
        #expect(PlannedAttempts.addOutcome(live: 2, want: 3, interrupted: true) == .interrupted)
        // Ekran çıkarılmış: geri gelince yeniden denenir.
        #expect(PlannedAttempts.addOutcome(live: nil, want: 3, interrupted: false) == .interrupted)
        // Tavan doldu, sayı hâlâ eksik: döngü olmasın.
        #expect(PlannedAttempts.addOutcome(live: 2, want: 3, interrupted: false) == .failed)
    }
}
