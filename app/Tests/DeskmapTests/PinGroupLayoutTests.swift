import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Pin grubu kutularının saf kararları: bölme, "başka yerde de", ekleme hedefleri.
struct PinGroupLayoutTests {

    private let groups = [PinGroup(id: "g1", name: "Nova drafts"), PinGroup(id: "g2", name: "Orion")]

    private func rule(_ id: String, app: String = "Preview", bundle: String = "com.apple.Preview",
                      group: String? = nil, desktop: Int = 3) -> Rule {
        Rule(id: id, appName: app, bundleID: bundle, tokens: [id],
             docked: Destination(screen: "builtin", desktop: desktop), groupID: group)
    }

    private func window(_ id: CGWindowID, _ title: String, app: String = "Preview",
                        bundle: String = "com.apple.Preview") -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: bundle, title: title,
                              placement: Router.Placement(screen: "builtin", desktop: 3),
                              frame: nil, isMinimized: false)
    }

    @Test func splitGroupsByWinningRuleInGroupOrder() {
        let rules = [rule("a", group: "g2"), rule("b", group: "g1"), rule("c"), rule("d", group: "g1")]
        let windows = [window(1, "a"), window(2, "c"), window(3, "s")]
        let ruleFor: (Router.WindowSnapshot) -> Rule? = { w in
            // Oturum pinli pencere (3) kuralsız sayılır (K8).
            rules.first { $0.id == w.title }
        }
        let split = PinGroupLayout.split(windows: windows, closed: [rules[1], rules[3], rules[2]],
                                         groups: groups, ruleFor: ruleFor)
        #expect(split.boxes.map(\.group.id) == ["g1", "g2"])
        #expect(split.boxes[0].closed.map(\.id) == ["b", "d"])
        #expect(split.boxes[0].windows.isEmpty)
        #expect(split.boxes[1].windows.map(\.id) == [1])
        #expect(split.restWindows.map(\.id) == [2, 3])
        #expect(split.restClosed.map(\.id) == ["c"])
        // Gruplu pinler uygulama grubundan çıkar; aynı uygulamanın grupsuz pini kalır.
        let apps = AppGroup.grouped(windows: split.restWindows, closed: split.restClosed)
        #expect(apps.count == 1)
        #expect(apps[0].windows.map(\.id) == [2, 3])
        #expect(apps[0].closed.map(\.id) == ["c"])
    }

    @Test func singleMemberBoxAndUnknownGroupAndEmptyGroup() {
        let single = PinGroupLayout.split(windows: [], closed: [rule("a", group: "g1")],
                                          groups: groups, ruleFor: { _ in nil })
        #expect(single.boxes.count == 1 && single.boxes[0].total == 1)
        let unknown = PinGroupLayout.split(windows: [], closed: [rule("a", group: "gone")],
                                           groups: groups, ruleFor: { _ in nil })
        #expect(unknown.boxes.isEmpty)
        #expect(unknown.restClosed.map(\.id) == ["a"])
        // Üyesi görünmeyen (boş) grup çizilmez (K7).
        let none = PinGroupLayout.split(windows: [], closed: [], groups: groups, ruleFor: { _ in nil })
        #expect(none.boxes.isEmpty)
    }

    /// Oturum pini kazanan pencere gruba girmez: `winningRule` nil döner.
    @Test func sessionPinKeepsAWindowOutOfItsGroup() {
        let member = rule("a", group: "g1")
        let w = window(7, "a")
        #expect(PinGroupLayout.winningRule(w, rules: [member], sessionPins: [:], mode: .docked,
                                           context: nil)?.id == "a")
        #expect(PinGroupLayout.winningRule(w, rules: [member],
                                           sessionPins: [7: Destination(screen: "builtin", desktop: 1)],
                                           mode: .docked, context: nil) == nil)
    }

    @Test func annotateElsewhereAndOtherScreens() {
        var boxes = [PinGroupBox(group: groups[0], windows: [], closed: [rule("a", group: "g1")]),
                     PinGroupBox(group: groups[1], windows: [], closed: [rule("b", group: "g2")])]
        PinGroupLayout.annotate(&boxes, screen: "builtin", desktop: 3, memberPlaces: [
            "g1": [Destination(screen: "builtin", desktop: 3), Destination(screen: "builtin", desktop: 5),
                   Destination(screen: "builtin", desktop: 1), Destination(screen: "builtin", desktop: 5)],
            "g2": [Destination(screen: "builtin", desktop: 3), Destination(screen: "external", desktop: 1)],
        ])
        #expect(boxes[0].elsewhere == [1, 5])
        #expect(!boxes[0].otherScreens)
        #expect(boxes[0].isScattered)
        #expect(boxes[1].elsewhere.isEmpty)
        #expect(boxes[1].otherScreens)
        var lone = [PinGroupBox(group: groups[0], windows: [], closed: [])]
        PinGroupLayout.annotate(&lone, screen: "builtin", desktop: 3,
                                memberPlaces: ["g1": [Destination(screen: "builtin", desktop: 3)]])
        #expect(!lone[0].isScattered)
    }

    @Test func addTargetsAndIDs() {
        let rules = [rule("a", group: "g1"), rule("b", group: "g2"), rule("c", group: "g3")]
        let withMembers = PinGroupLayout.groupsWithMembers(rules, mode: .docked)
        #expect(withMembers == ["g1", "g2", "g3"])
        #expect(PinGroupLayout.groupsWithMembers(rules, mode: .undocked).isEmpty)
        #expect(PinGroupLayout.addTargets(groups: groups, members: withMembers, excluding: "g1").map(\.id) == ["g2"])
        #expect(PinGroupLayout.addTargets(groups: groups, members: ["g1"], excluding: nil).map(\.id) == ["g1"])
        let box = PinGroupBox(group: groups[0], windows: [], closed: [])
        #expect(box.id.hasPrefix("pg:"))
        let app = AppGroup(bundleID: "g1", appName: "x", windows: [])
        #expect(box.id != app.id)
    }
}
