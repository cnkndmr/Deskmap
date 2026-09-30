import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Uzak AX taraması kapısı: bulunamayan numara bekletilir, yeni pencere bekletilmez.
struct RemoteScanGateTests {

    private let start = Date(timeIntervalSinceReferenceDate: 500)
    private let helper: CGWindowID = 40
    private let first: CGWindowID = 41
    private let second: CGWindowID = 42

    /// `first` bulunmuş, `helper` bulunamamış bir tam geçişten sonraki kapı.
    private func scanned() -> AX.RemoteScanGate {
        var gate = AX.RemoteScanGate()
        gate.record([first: 7], aborted: false, wanted: [first, helper], now: start)
        return gate
    }

    @Test func unscannedAppIsScanned() {
        #expect(AX.RemoteScanGate().shouldScan(for: first, now: start))
    }

    @Test func missedWindowWaitsForTheRescanInterval() {
        let gate = scanned()
        #expect(gate.misses == [helper])
        #expect(!gate.shouldScan(for: helper, now: start.addingTimeInterval(10)))
        #expect(gate.shouldScan(for: helper, now: start.addingTimeInterval(AX.remoteRescan)))
    }

    /// Hata: kapı pid başınaydı; geçişten sonra açılan pencere başka
    /// masaüstüne taşınınca 30 sn listelenmiyordu.
    @Test func windowBornAfterTheScanIsScannedAtOnce() {
        var gate = scanned()
        let later = start.addingTimeInterval(10)
        #expect(gate.shouldScan(for: second, now: later))

        gate.record([first: 7, second: 9], aborted: false, wanted: [second, helper], now: later)
        #expect(gate.ids[second] == 9)
        // Süre içindeki geçiş eski kaydı düşürmez: yardımcı pencere yeniden taranmaz.
        #expect(gate.misses == [helper])
        #expect(!gate.shouldScan(for: helper, now: later.addingTimeInterval(1)))
    }

    @Test func newMissIsRememberedAlongsideEarlierOnes() {
        var gate = scanned()
        let later = start.addingTimeInterval(10)
        gate.record([first: 7], aborted: false, wanted: [second], now: later)
        #expect(gate.misses == [helper, second])
        #expect(!gate.shouldScan(for: second, now: later.addingTimeInterval(1)))
    }

    @Test func expiredScanDropsStaleMisses() {
        var gate = scanned()
        let later = start.addingTimeInterval(AX.remoteRescan)
        gate.record([first: 7], aborted: false, wanted: [second], now: later)
        #expect(gate.misses == [second])
    }

    @Test func windowFoundLaterLeavesTheMisses() {
        var gate = scanned()
        let later = start.addingTimeInterval(10)
        gate.record([first: 7, helper: 3], aborted: false, wanted: [second], now: later)
        #expect(gate.misses == [second])
    }

    @Test func cutShortScanBlocksEveryWindowUntilTheRetry() {
        var gate = scanned()
        let later = start.addingTimeInterval(10)
        gate.record([second: 9], aborted: true, wanted: [second], now: later)
        // Kesilen tarama bulduklarını ekler, eski haritayı atmaz.
        #expect(gate.ids == [first: 7, second: 9])
        #expect(!gate.shouldScan(for: 99, now: later.addingTimeInterval(1)))
        #expect(gate.shouldScan(for: 99, now: later.addingTimeInterval(AX.remoteAbortRetry)))
    }

    @Test func fullScanAfterACutShortOneReopensTheGate() {
        var gate = AX.RemoteScanGate()
        gate.record([:], aborted: true, wanted: [first], now: start)
        let retry = start.addingTimeInterval(AX.remoteAbortRetry)
        gate.record([first: 7], aborted: false, wanted: [first, helper], now: retry)
        #expect(gate.shouldScan(for: second, now: retry.addingTimeInterval(1)))
        #expect(!gate.shouldScan(for: helper, now: retry.addingTimeInterval(1)))
    }
}
