import Foundation
import Testing
@testable import Deskmap

/// AX gözlemci kaydı: geri çekilme süresi ve bütçe (P0-4).
struct ObserverRegistrationTests {

    @Test func retryDelayDoublesUpToCap() {
        #expect(WindowEvents.retryDelay(previous: nil, slow: false) == WindowEvents.minRetry)
        #expect(WindowEvents.retryDelay(previous: 2, slow: false) == 4)
        #expect(WindowEvents.retryDelay(previous: 16, slow: false) == WindowEvents.maxRetry)
        #expect(WindowEvents.retryDelay(previous: 30, slow: false) == WindowEvents.maxRetry)
    }

    @Test func slowRegistrationBacksOffToCapImmediately() {
        #expect(WindowEvents.retryDelay(previous: nil, slow: true) == WindowEvents.maxRetry)
    }

    /// Bütçe, tek AX çağrısının yanıt süresinden (1 sn) uzun olmalı; yoksa
    /// yavaş ama çalışan her uygulama başlık gözlemcisini kaybederdi.
    @Test func budgetExceedsSingleCallTimeout() {
        #expect(WindowEvents.registrationBudget > 1.0)
    }
}

/// Zamanlayıcı turunda bütün süreçleri gezme kararı (pahalı; seyrek).
struct ObserverRefreshTests {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func refreshOnlyWhenRetryDueOrIntervalPassed() {
        let recent = now.addingTimeInterval(-5)
        #expect(!WindowEvents.shouldRefresh(now: now, lastRefresh: recent, nextRetry: nil))
        #expect(!WindowEvents.shouldRefresh(now: now, lastRefresh: recent,
                                            nextRetry: now.addingTimeInterval(1)))
        #expect(WindowEvents.shouldRefresh(now: now, lastRefresh: recent, nextRetry: now))
        #expect(WindowEvents.shouldRefresh(
            now: now, lastRefresh: now.addingTimeInterval(-WindowEvents.refreshInterval),
            nextRetry: nil))
    }
}
