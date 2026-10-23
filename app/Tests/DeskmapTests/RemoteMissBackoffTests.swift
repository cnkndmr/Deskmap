import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Bulunamayan pencereye üstel bekleme (perf/PLAN-perf.md §3.2).
struct RemoteMissBackoffTests {

    private let start = Date(timeIntervalSinceReferenceDate: 500)
    private let helper: CGWindowID = 40
    private let real: CGWindowID = 41
    private let signatures: [CGWindowID: Int] = [40: 111, 41: 222]

    @Test func delayDoublesUpToTheCeiling() {
        #expect(AX.missBackoffDelay(1) == AX.remoteRescan)
        #expect(AX.missBackoffDelay(2) == AX.remoteRescan * 2)
        #expect(AX.missBackoffDelay(3) == AX.remoteRescan * 4)
        #expect(AX.missBackoffDelay(20) == AX.remoteMissCeiling)
    }

    /// Her tam geçiş bulunamayan numaranın beklemesini uzatır; süresi
    /// dolmadan yeni geçiş başlatmaz (bugün 30 sn'de bir başlatıyordu).
    @Test func repeatedMissWaitsLonger() {
        var gate = AX.RemoteScanGate()
        var now = start
        gate.record([real: 7], aborted: false, wanted: [real, helper], now: now, backoff: signatures)
        #expect(gate.backoff[helper]?.count == 1)
        #expect(gate.backoff[real] == nil)

        now = now.addingTimeInterval(AX.remoteRescan)
        #expect(gate.shouldScan(for: helper, now: now))
        gate.record([real: 7], aborted: false, wanted: [helper], now: now, backoff: signatures)
        #expect(gate.backoff[helper]?.count == 2)
        #expect(!gate.shouldScan(for: helper, now: now.addingTimeInterval(AX.remoteRescan)))
        #expect(gate.shouldScan(for: helper, now: now.addingTimeInterval(AX.remoteRescan * 2)))
    }

    /// Başka numaranın geçişi bekleyen numarayı da arar; bulamazsa sayı artmaz.
    @Test func missInsideTheWaitDoesNotCountAgain() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: false, wanted: [helper], now: start, backoff: signatures)
        let later = start.addingTimeInterval(10)
        gate.record([:], aborted: false, wanted: [helper, real], now: later, backoff: signatures)
        #expect(gate.backoff[helper]?.count == 1)
        #expect(gate.backoff[helper]?.until == start.addingTimeInterval(AX.remoteRescan))
    }

    @Test func foundWindowLeavesTheBackoff() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: false, wanted: [helper], now: start, backoff: signatures)
        let later = start.addingTimeInterval(AX.remoteRescan)
        gate.record([helper: 9], aborted: false, wanted: [helper], now: later, backoff: signatures)
        #expect(gate.backoff[helper] == nil)
        #expect(gate.ids[helper] == 9)
    }

    /// Yardımcı pencere gerçek pencereye dönüşürse (boyut, ekranda) hemen aranır.
    @Test func changedServerRowDropsTheWait() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: false, wanted: [helper], now: start, backoff: signatures)
        gate.dropStaleBackoff(signatures)
        #expect(gate.backoff[helper] != nil)
        gate.dropStaleBackoff([helper: 999, real: 222])
        #expect(gate.backoff[helper] == nil)
        #expect(gate.shouldScan(for: helper, now: start.addingTimeInterval(AX.remoteRescan)))
    }

    @Test func closedWindowDropsTheWait() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: false, wanted: [helper], now: start, backoff: signatures)
        gate.dropStaleBackoff([real: 222])
        #expect(gate.backoff.isEmpty)
    }

    /// Bayrak kapalıyken bugünkü davranış: bekleme kaydı tutulmaz.
    @Test func disabledKeepsTodaysBehaviour() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: false, wanted: [helper], now: start, backoff: signatures)
        gate.record([:], aborted: false, wanted: [helper],
                    now: start.addingTimeInterval(AX.remoteRescan))
        #expect(gate.backoff.isEmpty)
        #expect(gate.shouldScan(for: helper, now: start.addingTimeInterval(AX.remoteRescan * 2)))
    }
}
