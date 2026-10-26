import CoreGraphics
import Testing
@testable import Deskmap

/// Toplu aç/kapat kararları: her uygulamada aynı (Excel yalnız örnek).
struct PinBatchTests {

    private func rule(_ id: String, app: String = "Microsoft Excel") -> Rule {
        Rule(id: id, appName: app, bundleID: "b.\(app)", tokens: [id],
             docked: Destination(screen: "s", desktop: 1), undocked: nil)
    }

    @Test func allOpenCloses() {
        #expect(PinBatch.groupAction(openPinned: 3, closed: 0) == .close)
    }

    @Test func allClosedOpens() {
        #expect(PinBatch.groupAction(openPinned: 0, closed: 2) == .open)
    }

    @Test func partlyOpenOpensTheRestFirst() {
        #expect(PinBatch.groupAction(openPinned: 1, closed: 2) == .open)
    }

    @Test func unpinnedOnlyGroupHasNoButton() {
        #expect(PinBatch.groupAction(openPinned: 0, closed: 0) == .none)
    }

    @Test func shadowedPinIsNotReopened() {
        let rules = [rule("a"), rule("b"), rule("c", app: "Finder")]
        let result = PinBatch.reopenable(rules, shadowed: ["b": "x"])
        #expect(result.map(\.id) == ["a", "c"])
    }

    // MARK: - Pin grubu

    private func window(_ id: CGWindowID, title: String) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "Microsoft Excel", bundleID: "b.Microsoft Excel",
                              title: title, placement: Router.Placement(screen: "s", desktop: 1),
                              frame: nil, isMinimized: false)
    }

    /// Bütün üyeler: açık olanlar kapanır, kapalılar açılır; gölgede kalan
    /// (penceresi açık, başka kural kazanmış) açılmaz; oturum pinli pencere
    /// (`ruleFor` nil) grubun penceresi sayılmaz.
    @Test func pinGroupInputCoversEveryMember() {
        let members = [rule("a"), rule("b"), rule("c"), rule("d")]
        let windows = [window(1, title: "a"), window(2, title: "b"), window(3, title: "x")]
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let ruleFor: (Router.WindowSnapshot) -> Rule? = { w in
            w.id == 2 ? nil : byID[w.title]
        }
        let mixed = PinBatch.pinGroupInput(members: members, windows: windows,
                                           shadowed: ["d": "z"], ruleFor: ruleFor)
        #expect(mixed.openPinned.map(\.id) == [1])
        #expect(mixed.closed.map(\.id) == ["c"])
        #expect(PinBatch.groupAction(openPinned: mixed.openPinned.count, closed: mixed.closed.count) == .open)

        let allOpen = PinBatch.pinGroupInput(members: [rule("a")], windows: windows, shadowed: [:],
                                             ruleFor: ruleFor)
        #expect(PinBatch.groupAction(openPinned: allOpen.openPinned.count,
                                     closed: allOpen.closed.count) == .close)
        let allClosed = PinBatch.pinGroupInput(members: [rule("c")], windows: windows, shadowed: [:],
                                               ruleFor: ruleFor)
        #expect(PinBatch.groupAction(openPinned: allClosed.openPinned.count,
                                     closed: allClosed.closed.count) == .open)
        let shadowedOnly = PinBatch.pinGroupInput(members: [rule("d")], windows: windows,
                                                  shadowed: ["d": "z"], ruleFor: ruleFor)
        #expect(PinBatch.groupAction(openPinned: shadowedOnly.openPinned.count,
                                     closed: shadowedOnly.closed.count) == .none)
    }
}
