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
}
