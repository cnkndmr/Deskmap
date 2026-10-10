import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Uygulama grubunu başka masaüstüne taşıma: tek sürüklemeyle aynı anlam,
/// tek geri alma adımı.
struct GroupMoveTests {

    private let here = Router.Placement(screen: "s", desktop: 1)
    private let there = Router.Placement(screen: "e", desktop: 2)

    private func window(_ id: CGWindowID, title: String, placement: Router.Placement? = nil)
        -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "Code", bundleID: "vs", title: title,
                              placement: placement ?? here, frame: nil, isMinimized: false)
    }

    private func rule(_ id: String, token: String, layout: WindowLayout = .full) -> Rule {
        Rule(id: id, appName: "Code", bundleID: "vs", tokens: [token],
             docked: Destination(screen: "s", desktop: 1, layout: layout), undocked: nil)
    }

    @Test func eachKindFollowsSingleDragSemantics() {
        let half = WindowLayout(x: 0, y: 0, w: 0.5, h: 1)
        let pinned = rule("p", token: "alpha", layout: half)
        let closed = rule("c", token: "gone")
        let session = Destination(screen: "s", desktop: 1, layout: half)
        let group = AppGroup(bundleID: "vs", appName: "Code",
                             windows: [window(1, title: "alpha"), window(2, title: "beta"),
                                       window(3, title: "gamma")],
                             closed: [closed])
        let plan = GroupMovePlan.make(group: group, to: there, mode: .docked, isLive: true,
                                      rules: [pinned, closed], sessionPins: [3: session])
        #expect(plan.rules == [.init(id: "p", destination: Destination(screen: "e", desktop: 2, layout: half)),
                               .init(id: "c", destination: Destination(screen: "e", desktop: 2))])
        #expect(plan.sessions == [.init(window: 3, from: session,
                                        to: Destination(screen: "e", desktop: 2, layout: half))])
        #expect(plan.windows == [2])
    }

    @Test func sharedRuleMovesOnceAndInactiveViewSkipsUnpinned() {
        let appWide = Rule(id: "a", appName: "Code", bundleID: "vs", tokens: [],
                           docked: Destination(screen: "s", desktop: 1), undocked: nil)
        let group = AppGroup(bundleID: "vs", appName: "Code",
                             windows: [window(1, title: "x"), window(2, title: "y")], closed: [appWide])
        let plan = GroupMovePlan.make(group: group, to: there, mode: .docked, isLive: true,
                                      rules: [appWide], sessionPins: [:])
        #expect(plan.rules.map(\.id) == ["a"])
        #expect(plan.windows.isEmpty)

        let loose = AppGroup(bundleID: "vs", appName: "Code",
                             windows: [window(1, title: "x"), window(2, title: "y")])
        #expect(GroupMovePlan.make(group: loose, to: there, mode: .docked, isLive: false,
                                   rules: [], sessionPins: [:]).isEmpty)
    }

    @Test func sameDesktopIsNoOp() {
        let group = AppGroup(bundleID: "vs", appName: "Code", windows: [window(1, title: "x")],
                             closed: [rule("c", token: "gone")])
        #expect(GroupMovePlan.make(group: group, to: here, mode: .docked, isLive: true,
                                   rules: [rule("c", token: "gone")], sessionPins: [:]).isEmpty)
    }

    @Test func sendTargetsExcludeCurrentDesktop() {
        let screens = [KnownScreen(id: "s", name: "Dahili", aspect: 1.55),
                       KnownScreen(id: "e", name: "LG", aspect: 1.78)]
        let targets = GroupMovePlan.sendTargets(screens: screens, tileCounts: ["s": 1, "e": 2],
                                                current: here)
        #expect(targets.map(\.screen) == ["e"])
        #expect(targets[0].desktops.map(\.desktop) == [1, 2])
    }

    @MainActor @Test func storeMoveGroupIsOneUndoStep() {
        var document = Document()
        document.rules = [rule("a", token: "x"), rule("b", token: "y")]
        let store = Store(demo: document)
        var undone = false
        store.moveGroup([.init(id: "a", destination: Destination(screen: "e", desktop: 2)),
                         .init(id: "b", destination: Destination(screen: "e", desktop: 2))],
                        mode: .docked, undoingSessionPins: { undone = true })
        #expect(store.document.rules.allSatisfy { $0[.docked]?.screen == "e" })
        store.undo()
        #expect(store.document.rules.allSatisfy { $0[.docked]?.screen == "s" })
        #expect(undone)
    }
}
