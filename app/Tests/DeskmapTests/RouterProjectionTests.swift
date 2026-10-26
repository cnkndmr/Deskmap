import Foundation
import Testing
@testable import Deskmap

/// K11: pin grubu değişimi Router'ın kural aboneliğini tetiklemez;
/// pencereler yeniden yerleştirilmez. Yer değişimi yine tetikler.
struct RouterProjectionTests {

    private func document() -> Document {
        var d = Document()
        d.rules = [Rule(id: "a", appName: "Preview", bundleID: "p", tokens: ["a"],
                        docked: Destination(screen: "builtin", desktop: 3)),
                   Rule(id: "b", appName: "Preview", bundleID: "p", tokens: ["b"],
                        docked: Destination(screen: "builtin", desktop: 3))]
        d.syncActiveProfile()
        return d
    }

    @Test func groupChangesKeepTheRoutingKey() throws {
        var d = document()
        let before = Router.routingKey(d)
        let made = d.createPinGroup(name: "G", ruleIDs: ["a", "b"])
        let group = try #require(made)
        #expect(d.rules != document().rules)
        #expect(Router.routingKey(d) == before)
        d.renamePinGroup(group.id, to: "H")
        d.removeFromPinGroup(ruleIDs: ["a"])
        #expect(Router.routingKey(d) == before)
        d.dissolvePinGroup(group.id)
        #expect(Router.routingKey(d) == before)
    }

    @Test func placeChangesChangeTheRoutingKey() {
        var d = document()
        let before = Router.routingKey(d)
        d.setDestination(Destination(screen: "builtin", desktop: 1), for: "a", mode: .docked)
        #expect(Router.routingKey(d) != before)
    }

    /// Abonelik bu izdüşümü kullanır (kaynakta tek abonelik `.map(\.rules)` değil).
    @Test func subscriptionUsesTheProjection() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Deskmap/Services/Router.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains(".map(Router.routingKey)"))
        #expect(!text.contains(".map(\\.rules)"))
    }
}
