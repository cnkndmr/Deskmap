import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

struct StatusIndicatorTests {

    private func win(_ id: CGWindowID, _ app: String, desktop: Int?, screen: String = "builtin",
                     minimized: Bool = false) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: "b.\(app)", title: "t\(id)",
                              placement: desktop.map { .init(screen: screen, desktop: $0) },
                              frame: nil, isMinimized: minimized)
    }

    private func rule(_ app: String, desktop: Int) -> Rule {
        Rule(appName: app, bundleID: "b.\(app)", tokens: [],
             docked: Destination(screen: "builtin", desktop: desktop))
    }

    @Test func greenWhenEverythingIsInPlace() {
        let found = StatusIndicator.check(windows: [win(1, "A", desktop: 2)], rules: [rule("A", desktop: 2)],
                                          sessionPins: [:], mode: .docked,
                                          desktopCounts: ["builtin": 3], free: [])
        #expect(found.misplaced.isEmpty && found.missing.isEmpty)
        #expect(StatusIndicator.evaluate(.init()).level == .green)
    }

    @Test func misplacedIsOrangeThenRedWhenStuck() {
        let found = StatusIndicator.check(
            windows: [win(1, "A", desktop: 1), win(2, "B", desktop: 1, minimized: true),
                      win(3, "C", desktop: 1)],
            rules: [rule("A", desktop: 2), rule("B", desktop: 2), rule("C", desktop: 2)],
            sessionPins: [:], mode: .docked, desktopCounts: ["builtin": 3], free: [3])
        #expect(found.misplaced == ["A t1"])
        let now = Date()
        var input = StatusIndicator.Inputs(misplaced: found.misplaced, workingSince: now, now: now)
        let orange = StatusIndicator.evaluate(input)
        #expect(orange.level == .orange && orange.reason.contains("A t1"))
        input.now = now.addingTimeInterval(StatusIndicator.stuckAfter + 1)
        #expect(StatusIndicator.evaluate(input).level == .red)
    }

    @Test func missingTargetAndPermissionAreRed() {
        let found = StatusIndicator.check(windows: [win(1, "A", desktop: 1)], rules: [rule("A", desktop: 5)],
                                          sessionPins: [:], mode: .docked,
                                          desktopCounts: ["builtin": 3], free: [])
        #expect(found.missing == ["A → builtin/5"] && found.misplaced.isEmpty)
        #expect(StatusIndicator.evaluate(.init(missingTargets: found.missing)).level == .red)
        #expect(StatusIndicator.evaluate(.init(trusted: false)).level == .red)
    }

    @Test func settlingIsOrangeAndDisconnectedScreenIgnored() {
        #expect(StatusIndicator.evaluate(.init(settling: true)).level == .orange)
        let found = StatusIndicator.check(windows: [win(1, "A", desktop: 1)],
                                          rules: [Rule(appName: "A", bundleID: "b.A", tokens: [],
                                                       docked: Destination(screen: "external", desktop: 2))],
                                          sessionPins: [:], mode: .docked,
                                          desktopCounts: ["builtin": 3], free: [])
        #expect(found.misplaced.isEmpty && found.missing.isEmpty)
    }

    @Test func listShortens() {
        #expect(StatusIndicator.list(["a", "b", "c"]) == "a, b, …")
    }
}
