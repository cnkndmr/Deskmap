import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Durum yoklamalı yatışma (perf/PLAN-perf.md §4.4 B2).
struct SettleProbeTests {
    private typealias Probe = ScreenService.SettleProbe
    private typealias Sample = ScreenService.SettleSample

    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private let builtin = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let dell = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    private func docked(spaces: [UInt64] = [5, 6]) -> Sample {
        Sample(screens: ["B": builtin, "E": dell], spaces: ["B": [1, 2], "E": spaces])
    }

    @Test func stableConsistentSampleSettlesAfterHalfASecond() {
        var probe = Probe()
        let r1 = probe.feed(docked(), at: t0); #expect(!r1)
        let r2 = probe.feed(docked(), at: t0.addingTimeInterval(0.4)); #expect(!r2)
        let r3 = probe.feed(docked(), at: t0.addingTimeInterval(0.6)); #expect(r3)
    }

    /// SkyLight ekranı henüz görmüyorsa (NSScreen önde) yatışmaz.
    @Test func inconsistentSetsDoNotSettle() {
        var probe = Probe()
        let half = Sample(screens: ["B": builtin, "E": dell], spaces: ["B": [1, 2]])
        let r4 = probe.feed(half, at: t0); #expect(!r4)
        let r5 = probe.feed(half, at: t0.addingTimeInterval(2)); #expect(!r5)
    }

    /// Masaüstü listesi değişirse (macOS masaüstü ekliyor) kararlılık baştan sayılır.
    @Test func changingDesktopsRestartTheClock() {
        var probe = Probe()
        _ = probe.feed(docked(spaces: [5]), at: t0)
        let r6 = probe.feed(docked(spaces: [5, 6]), at: t0.addingTimeInterval(0.6)); #expect(!r6)
        let r7 = probe.feed(docked(spaces: [5, 6]), at: t0.addingTimeInterval(1.2)); #expect(r7)
    }

    @Test func notificationRestartsTheClock() {
        var probe = Probe()
        _ = probe.feed(docked(), at: t0)
        probe.reset(at: t0.addingTimeInterval(0.4))
        let r8 = probe.feed(docked(), at: t0.addingTimeInterval(0.6)); #expect(!r8)
        let r9 = probe.feed(docked(), at: t0.addingTimeInterval(0.9)); #expect(r9)
    }

    @Test func flagsAreOffByDefault() {
        #expect(UserDefaults.standard.object(forKey: "perf.settlePoll") == nil || !ScreenService.settlePoll)
    }
}
