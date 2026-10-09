import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Masaüstü satırındaki uygulama grupları: kapalı pinler kendi uygulamasının
/// grubuna, açık pencerelerden sonra girer.
struct AppGroupTests {

    private func window(_ id: CGWindowID, app: String, bundle: String)
        -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: bundle,
                              title: "t\(id)", placement: nil, frame: nil, isMinimized: false)
    }

    private func rule(_ id: String, app: String, bundle: String) -> Rule {
        Rule(id: id, appName: app, bundleID: bundle, tokens: [id],
             docked: Destination(screen: "s", desktop: 1), undocked: nil)
    }

    @Test func closedPinJoinsOpenGroupAfterWindows() {
        let groups = AppGroup.grouped(
            windows: [window(1, app: "Code", bundle: "vs"), window(2, app: "Code", bundle: "vs")],
            closed: [rule("a", app: "Code", bundle: "vs")])
        #expect(groups.count == 1)
        #expect(groups[0].windows.count == 2)
        #expect(groups[0].closed.map(\.id) == ["a"])
    }

    @Test func appWithOnlyClosedPinsGetsOwnGroupAfterOpenOnes() {
        let groups = AppGroup.grouped(
            windows: [window(1, app: "Code", bundle: "vs")],
            closed: [rule("m1", app: "Mail", bundle: "mail"), rule("m2", app: "Mail", bundle: "mail")])
        #expect(groups.map(\.id) == ["vs", "mail"])
        #expect(groups[1].windows.isEmpty)
        #expect(groups[1].closed.map(\.id) == ["m1", "m2"])
    }

    @Test func fallsBackToAppNameWhenBundleIDEmpty() {
        let groups = AppGroup.grouped(
            windows: [window(1, app: "Legacy", bundle: "")],
            closed: [rule("l", app: "Legacy", bundle: ""), rule("x", app: "Other", bundle: "")])
        #expect(groups.map(\.id) == ["Legacy", "Other"])
        #expect(groups[0].closed.map(\.id) == ["l"])
    }

    @Test func differentBundlesStaySeparateDespiteSameName() {
        let groups = AppGroup.grouped(
            windows: [window(1, app: "Code", bundle: "a")],
            closed: [rule("r", app: "Code", bundle: "b")])
        #expect(groups.count == 2)
    }

    @Test func noWindowsNoPinsIsEmpty() {
        #expect(AppGroup.grouped(windows: [], closed: []).isEmpty)
    }

    @Test func headerOnlyWithTwoOrMoreItems() {
        let one = AppGroup.grouped(windows: [], closed: [rule("a", app: "Code", bundle: "vs")])
        #expect(one[0].total == 1 && !one[0].showsHeader)
        let win = AppGroup.grouped(windows: [window(1, app: "Code", bundle: "vs")], closed: [])
        #expect(!win[0].showsHeader)
        let mixed = AppGroup.grouped(windows: [window(1, app: "Code", bundle: "vs")],
                                     closed: [rule("a", app: "Code", bundle: "vs")])
        #expect(mixed[0].total == 2 && mixed[0].showsHeader)
        let two = AppGroup.grouped(windows: [],
                                   closed: [rule("a", app: "Code", bundle: "vs"), rule("b", app: "Code", bundle: "vs")])
        #expect(two.count == 1 && two[0].showsHeader)
    }

    @Test func deletedDesktopLabelsGroupByApp() {
        let g = AppGroup.groupedLabels([("Code", "vs", "a"), ("Mail", "m", ""), ("Code", "vs", "b"), ("Code", "vs", "a")])
        #expect(g.map(\.app) == ["Code", "Mail"])
        #expect(g[0].details == ["a", "b"])
    }
}
