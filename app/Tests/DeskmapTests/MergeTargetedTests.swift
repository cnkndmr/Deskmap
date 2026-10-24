import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Hedefli okuma sonucunun tam listeye katılması (perf/PLAN-perf.md §5.1 ilk adım).
struct MergeTargetedTests {
    private func w(_ id: CGWindowID, _ app: String, x: CGFloat = 0) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: "b", title: "t", placement: nil,
                              frame: CGRect(x: x, y: 0, width: 10, height: 10), isMinimized: false)
    }

    @Test func updatesOnlyTheTargetedWindow() {
        let full = [w(1, "Alpha"), w(2, "Beta"), w(3, "Gamma")]
        let out = Router.mergeTargeted(full, partial: [w(2, "Beta", x: 50)])
        #expect(out.map(\.id) == [1, 2, 3])
        #expect(out[1].frame?.minX == 50)
        #expect(out[0] == full[0] && out[2] == full[2])
    }

    /// Tek pencerelik sonuç ötekileri listeden düşürmez.
    @Test func emptyPartialKeepsTheList() {
        let full = [w(1, "Alpha"), w(2, "Beta")]
        #expect(Router.mergeTargeted(full, partial: []) == full)
    }

    @Test func newWindowIsInsertedInSweepOrder() {
        let full = [w(1, "Alpha"), w(3, "Gamma")]
        #expect(Router.mergeTargeted(full, partial: [w(9, "Beta")]).map(\.id) == [1, 9, 3])
    }
}
