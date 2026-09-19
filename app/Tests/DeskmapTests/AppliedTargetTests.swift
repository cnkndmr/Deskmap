import CoreGraphics
import Testing
@testable import Deskmap

/// Düzen belleği pencere başına çözülmüş hedefe bağlı (B7).
struct AppliedTargetTests {

    private func destination(_ desktop: Int, screen: String = "laptop") -> Destination {
        var value = Destination(screen: screen)
        value.desktop = desktop
        return value
    }

    private func target(_ desktop: Int) -> Router.AppliedTarget {
        Router.AppliedTarget(mode: .undocked, destination: destination(desktop))
    }

    @Test func sameResolvedTargetFromAnotherRuleDoesNotRelayout() {
        // Başlık değişti, başka kural eşleşti ama hedef aynı: elle taşınmış
        // pencere yeniden yerleştirilmez.
        let entry = Router.AppliedEntry(target: target(2), generation: 1)
        #expect(!Router.needsLayout(applied: entry, target: target(2)))
    }

    @Test func returningToEarlierTargetRelayouts() {
        // A → B → A: pencerenin son hedefi B; A'ya dönüş yeniden uygulanır.
        var entry = Router.AppliedEntry(target: target(1), generation: 1)
        #expect(Router.needsLayout(applied: entry, target: target(2)))
        entry = Router.AppliedEntry(target: target(2), generation: 2)
        #expect(Router.needsLayout(applied: entry, target: target(1)))
    }

    @Test func modeIsPartOfTheTarget() {
        let entry = Router.AppliedEntry(target: target(1), generation: 1)
        let other = Router.AppliedTarget(mode: .docked, destination: destination(1))
        #expect(Router.needsLayout(applied: entry, target: other))
        #expect(Router.needsLayout(applied: nil, target: target(1)))
    }

    @Test func entriesFromSweepsStartedBeforeInvalidationAreDropped() {
        let entries: [CGWindowID: Router.AppliedEntry] = [
            1: .init(target: target(1), generation: 4),
            2: .init(target: target(1), generation: 4),
            3: .init(target: target(1), generation: 6),
        ]
        let kept = Router.acceptApplied(entries, floors: [1: 5], globalFloor: 0)
        #expect(Set(kept.keys) == [2, 3])
        let afterReapply = Router.acceptApplied(entries, floors: [:], globalFloor: 5)
        #expect(Set(afterReapply.keys) == [3])
    }
}
