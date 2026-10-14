import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Sol kenardaki zamanlı pinler kutusu: hangi pencereler, hangi sırayla.
struct FreeMoveTrayTests {

    private func window(_ id: CGWindowID) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "App", bundleID: "app",
                              title: "t\(id)", placement: nil, frame: nil, isMinimized: false)
    }

    @Test func listsOnlyRunningGrantsSoonestFirst() {
        let now = Date(timeIntervalSince1970: 1000)
        let grants: [CGWindowID: Date] = [
            1: now.addingTimeInterval(600),
            2: now.addingTimeInterval(-5),          // süresi dolmuş
            3: now.addingTimeInterval(60),
            4: now.addingTimeInterval(Router.freeMoveUntilLock),  // kilide kadar: en sonda
        ]
        let windows = (1...5).map { window(CGWindowID($0)) }
        let ids = FreeMoveTray.timedWindows(windows, freeMoves: grants, now: now).map(\.id)
        #expect(ids == [3, 1, 4])
    }

    @Test func emptyWithoutGrants() {
        #expect(FreeMoveTray.timedWindows([window(1)], freeMoves: [:], now: Date()).isEmpty)
    }
}
