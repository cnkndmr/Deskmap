import Testing
@testable import Deskmap

/// Menü çubuğu simgesinin üç durumu.
struct AppHealthTests {

    private func state(enabled: Bool = true, trusted: Bool = true, settings: Bool = true,
                       degraded: Bool = false) -> AppHealth {
        AppHealth.state(enabled: enabled, trusted: trusted, requiredSettingsOK: settings,
                        movesDegraded: degraded)
    }

    @Test func readyAndPaused() {
        #expect(state() == .ready)
        #expect(state(enabled: false) == .paused)
    }

    @Test func anyProblemNeedsAttentionEvenWhenPaused() {
        #expect(state(trusted: false) == .needsAttention)
        #expect(state(settings: false) == .needsAttention)
        #expect(state(degraded: true) == .needsAttention)
        #expect(state(enabled: false, trusted: false) == .needsAttention)
    }

    @Test func labelsDiffer() {
        #expect(Set([AppHealth.ready, .paused, .needsAttention].map(\.label)).count == 3)
    }
}
