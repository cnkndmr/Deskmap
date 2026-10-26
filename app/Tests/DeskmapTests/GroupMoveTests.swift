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

    // MARK: - Pin grubu (K3)

    private func member(_ id: String, _ screen: String, _ desktop: Int, group: String? = "g",
                        layout: WindowLayout = .full, undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "Preview", bundleID: "pv", tokens: [id],
             docked: Destination(screen: screen, desktop: desktop, layout: layout),
             undocked: undocked, groupID: group)
    }

    /// Başka masaüstündeki (ve ekrandaki) üyeler de taşınır; grup dışı kural
    /// taşınmaz; hedefte zaten olan atlanır; düzen korunur; öbür modun
    /// hedefi değişmez.
    @Test func pinGroupMovesEveryMemberAndOnlyMembers() {
        let half = WindowLayout.leftHalf
        let laptop = Destination(screen: "s", desktop: 4)
        let rules = [member("a", "s", 1, layout: half, undocked: laptop), member("b", "s", 3),
                     member("c", "e", 1), member("d", "e", 2),
                     member("x", "s", 1, group: nil), member("y", "s", 1, group: "other")]
        let plan = GroupMovePlan.forPinGroup("g", rules: rules, mode: .docked, to: there,
                                             winner: { $0[.docked] })
        #expect(plan.rules == [.init(id: "a", destination: Destination(screen: "e", desktop: 2, layout: half)),
                               .init(id: "b", destination: Destination(screen: "e", desktop: 2)),
                               .init(id: "c", destination: Destination(screen: "e", desktop: 2))])
        #expect(plan.sessions.isEmpty && plan.windows.isEmpty)
        // Öbür modun hedefleri plana girmez; Store'da da değişmez.
        var d = Document()
        d.rules = rules
        for move in plan.rules { d.setDestination(move.destination, for: move.id, mode: .docked) }
        #expect(d.rule("a")?.undocked == laptop)
        #expect(d.rule("x")?.docked?.desktop == 1)
    }

    /// O modda yeri olmayan üyeye yer eklenmez.
    @Test func pinGroupMemberWithoutAPlaceInThisModeStays() {
        var onlyLaptop = member("a", "s", 1)
        onlyLaptop.docked = nil
        onlyLaptop.undocked = Destination(screen: "s", desktop: 2)
        let plan = GroupMovePlan.forPinGroup("g", rules: [onlyLaptop, member("b", "s", 1)],
                                             mode: .docked, to: there, winner: { $0[.docked] })
        #expect(plan.rules.map(\.id) == ["b"])
    }

    /// Kazanan yer ilk yer değilken (sıralı yerler) "zaten orada" kazanan
    /// yere bakar; uygulama grubu da aynı kuralla.
    @Test func alreadyThereLooksAtTheWinningPlace() {
        var ordered = member("a", "e", 1)
        ordered.dockedNext = [Destination(screen: "s", desktop: 2, layout: .rightHalf)]
        let shown = Router.Placement(screen: "s", desktop: 2)
        let winner: (Rule) -> Destination? = { $0.places(.docked).last }
        #expect(GroupMovePlan.forPinGroup("g", rules: [ordered], mode: .docked, to: shown,
                                          winner: winner).isEmpty)
        // Kazanan yerin düzeniyle taşınır.
        let moved = GroupMovePlan.forPinGroup("g", rules: [ordered], mode: .docked,
                                              to: Router.Placement(screen: "s", desktop: 3), winner: winner)
        #expect(moved.rules == [.init(id: "a", destination: Destination(screen: "s", desktop: 3,
                                                                         layout: .rightHalf))])
        let group = AppGroup(bundleID: "pv", appName: "Preview", windows: [], closed: [ordered])
        #expect(GroupMovePlan.make(group: group, to: shown, mode: .docked, isLive: true,
                                   rules: [ordered], sessionPins: [:], winner: winner).isEmpty)
        // Kazanan verilmezse ilk yer (eski davranış).
        #expect(!GroupMovePlan.make(group: group, to: shown, mode: .docked, isLive: true,
                                    rules: [ordered], sessionPins: [:]).isEmpty)
    }

    /// Adlı masaüstüne taşımada var olan N2 davranışı: öbür kurulumda yeri
    /// olmayan üye orada da o ada bağlanır.
    @Test func movingToANamedDesktopPinsTheOtherSetupToo() throws {
        var d = Document()
        d.rules = [member("a", "s", 1), member("b", "s", 1, undocked: Destination(screen: "builtin", desktop: 1))]
        d.syncActiveProfile()
        let ok = d.setDesktopName("Nova", screen: "e", desktop: 2, mode: .docked)
        #expect(ok)
        let nameID = try #require(d.nameID(screen: "e", desktop: 2, mode: .docked))
        // Öbür kurulumun planında da yeri olsun.
        d.plans.put(nameID, at: 3, .undocked, "builtin")
        let plan = GroupMovePlan.forPinGroup("g", rules: d.rules, mode: .docked, to: there,
                                             winner: { $0[.docked] })
        for move in plan.rules { d.setDestination(move.destination, for: move.id, mode: .docked) }
        #expect(d.rule("a")?.docked?.nameID == nameID)
        #expect(d.rule("a")?.undocked?.nameID == nameID)
        #expect(d.rule("b")?.undocked == Destination(screen: "builtin", desktop: 1))
    }
}
