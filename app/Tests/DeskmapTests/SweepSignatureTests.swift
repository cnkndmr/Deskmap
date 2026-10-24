import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Zamanlayıcı turu imzası taramanın gördüğü ana çekilir (perf/PLAN-perf.md §5.4 adım 1).
struct SweepSignatureTests {

    private func sig(onscreen: Bool) -> AX.WindowServerSignature {
        AX.WindowServerSignature(rows: [AX.SignatureRow(id: 7, pid: 70, bounds: [0, 38, 520, 340], onscreen: onscreen)])
    }

    private func tickSweeps(last: AX.WindowServerSignature?, now: AX.WindowServerSignature) -> Bool {
        Router.shouldSweepOnTick(signatureChanged: now != last, mapVisible: false, deadline: nil,
                                 now: Date(), sinceLastSweep: 10)
    }

    /// Tur A'da pencere başka masaüstünde (imza "uzakta"), tarama geri taşır, takip taraması
    /// "evde" okur; kullanıcı sonraki turdan önce yine uzağa alır. Bugün: tur imzası yine
    /// "uzakta", değişim yok, tarama yok. Düzeltmeyle: son tarama "evde" gördü, değişim var.
    @Test func awayHomeAwayBetweenTicksIsCaught() {
        let away = sig(onscreen: false), home = sig(onscreen: true)
        let tickA = away
        // bugünkü davranış: taramalar imzaya dokunmaz
        #expect(!tickSweeps(last: Router.signatureAfterSweep(tick: tickA, swept: nil), now: away))
        // bayrak açık: önce geri taşıyan tarama (uzakta okudu), sonra takip taraması (evde okudu)
        var last = Router.signatureAfterSweep(tick: tickA, swept: away)
        last = Router.signatureAfterSweep(tick: last, swept: home)
        #expect(tickSweeps(last: last, now: away))
    }

    /// Değişim yokken fazladan tarama yok.
    @Test func steadyStateDoesNotSweep() {
        let home = sig(onscreen: true)
        let last = Router.signatureAfterSweep(tick: home, swept: home)
        #expect(!tickSweeps(last: last, now: home))
    }

    @Test func flagOffKeepsTickSignature() {
        let away = sig(onscreen: false)
        #expect(Router.signatureAfterSweep(tick: away, swept: nil) == away)
    }
}
