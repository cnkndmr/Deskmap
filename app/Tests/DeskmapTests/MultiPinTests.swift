import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Toplu pinleme planı: varsayılan başlık parçası, başka pencereye taşma
/// olursa daha dar başlık ya da oturum pini.
struct MultiPinTests {

    private func window(_ id: CGWindowID, _ app: String, _ title: String,
                        desktop: Int = 2) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: "b.\(app)", title: title,
                              placement: Router.Placement(screen: "external", desktop: desktop),
                              frame: nil, isMinimized: false)
    }

    private func plan(_ ids: Set<CGWindowID>, _ windows: [Router.WindowSnapshot]) -> MultiPinBar.Plan {
        MultiPinBar.plan(selected: ids, windows: windows) { _ in .full }
    }

    @Test func pinsEachWhereItIsWithDefaultToken() {
        let windows = [window(1, "Code", "a.md — Orion", desktop: 3),
                       window(2, "Finder", "Nova", desktop: 2)]
        let result = plan([1, 2], windows)
        #expect(result.sessions.isEmpty)
        #expect(result.rules.map(\.rule.tokens) == [["Orion"], ["Nova"]])
        #expect(result.rules.map(\.destination.desktop) == [3, 2])
    }

    @Test func narrowsTitleWhenDefaultWouldGrabAnUnselectedWindow() {
        // "Orion" öbür Code penceresine de uyar: bütün başlık kullanılır.
        let windows = [window(1, "Code", "a.md — Orion"),
                       window(3, "Code", "b.md — Orion", desktop: 5)]
        let result = plan([1], windows)
        #expect(result.rules.map(\.rule.tokens) == [["Orion", "a.md"]])
    }

    @Test func identicalTitlesFallBackToSessionPins() {
        // Aynı başlıklı iki Finder penceresi: kural ikisini ayıramaz.
        let windows = [window(1, "Finder", "Comet_notes", desktop: 4),
                       window(2, "Finder", "Comet_notes", desktop: 5)]
        let both = plan([1, 2], windows)
        #expect(both.rules.count == 1 && both.sessions.map(\.window) == [2])
        let one = plan([1], windows)
        #expect(one.rules.isEmpty && one.sessions.map(\.window) == [1])
    }

    @Test func skipsWindowsWithoutAPlace() {
        var full = window(1, "Code", "x")
        full.fullscreen = Router.FullscreenSlot(screen: "external", space: 9, afterDesktop: 1, order: 0)
        let unknown = Router.WindowSnapshot(id: 2, pid: 1, appName: "A", bundleID: "b", title: "t",
                                            placement: nil, frame: nil, isMinimized: false)
        let result = plan([1, 2], [full, unknown])
        #expect(result.rules.isEmpty && result.sessions.isEmpty)
    }

    @MainActor @Test func storePinManyIsOneUndoStep() {
        let store = Store(demo: Document())
        let rules = [(Rule(appName: "A", bundleID: "a", tokens: ["x"]), Destination(screen: "external", desktop: 1)),
                     (Rule(appName: "B", bundleID: "b", tokens: ["y"]), Destination(screen: "external", desktop: 2))]
        store.pinMany(rules.map { (rule: $0.0, destination: $0.1) }, mode: .docked)
        #expect(store.document.rules.count == 2)
        store.undo()
        #expect(store.document.rules.isEmpty)
    }

    /// Toplu pinin oturum pinleri de aynı geri alma adımında kalkar.
    @MainActor @Test func storePinManyRunsCompanionOnUndo() {
        let store = Store(demo: Document())
        var undone = false
        store.pinMany([(rule: Rule(appName: "A", bundleID: "a", tokens: ["x"]),
                        destination: Destination(screen: "external", desktop: 1))],
                      mode: .docked, companion: { undone = true })
        store.undo()
        #expect(undone)
        #expect(store.document.rules.isEmpty)
    }
}
