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
        let windows = [window(1, "Finder", "Vega-Notes", desktop: 4),
                       window(2, "Finder", "Vega-Notes", desktop: 5)]
        let both = plan([1, 2], windows)
        #expect(both.rules.count == 1 && both.sessions.map(\.window) == [2])
        let one = plan([1], windows)
        #expect(one.rules.isEmpty && one.sessions.map(\.window) == [1])
    }

    /// Gruplama planı: seçili kapalı çip ve pinli pencere `existing`'e,
    /// taslağı var olan kurala düşen pencere `existing`'e, yeni pencere
    /// `rules`'a, ayırt edilemeyen pencere `sessions`'a gider.
    @Test func groupingPlanSeparatesExistingPins() {
        let closed = Rule(id: "closed", appName: "Preview", bundleID: "b.Preview", tokens: ["Vega"],
                          docked: Destination(screen: "external", desktop: 3))
        let pinned = Rule(id: "pinned", appName: "Code", bundleID: "b.Code", tokens: ["Orion"],
                          docked: Destination(screen: "external", desktop: 2))
        let sameKey = Rule(id: "same", appName: "Finder", bundleID: "b.Finder", tokens: ["Nova"],
                           undocked: Destination(screen: "builtin", desktop: 1))
        let rules = [closed, pinned, sameKey]
        let windows = [window(1, "Code", "a.md — Orion"), window(2, "Finder", "Nova"),
                       window(3, "Mail", "Inbox"),
                       window(4, "Notes", "Lumen"), window(5, "Notes", "Lumen", desktop: 4)]
        let ruleFor: (Router.WindowSnapshot) -> Rule? = { $0.id == 1 ? pinned : nil }
        let result = MultiPinBar.plan(selected: [1, 2, 3, 4, 5], windows: windows,
                                      existingRules: rules, selectedRules: ["closed", "gone"],
                                      ruleFor: ruleFor) { _ in .full }
        #expect(result.existing == ["pinned", "same", "closed"])
        #expect(result.rules.map(\.rule.appName) == ["Mail", "Notes"])
        #expect(result.sessions.map(\.window) == [5])
        // Gruplamasız plan eski davranış: pinli pencere de yeniden pinlenir.
        let plain = plan([1, 2, 3], windows)
        #expect(plain.existing.isEmpty)
        #expect(plain.rules.count == 3)
        #expect(result != plain)
    }

    /// Plan bu modu bilince: taslağı yalnız öbür planda yeri olan kurala
    /// düşen pencere pinlenir (`rules`, `Document.pin` o kurala bu planın
    /// yerini ekler), öbür planın seçili çipi gruba girmez, oturum pini olan
    /// pencere `temporary`'ye gider (K8).
    @Test func groupingPlanChecksPlacesInThisModeAndSkipsTemporaryPins() {
        let docked = Rule(id: "docked", appName: "Code", bundleID: "b.Code", tokens: ["Orion"],
                          docked: Destination(screen: "external", desktop: 2))
        let otherPlan = Rule(id: "other", appName: "Finder", bundleID: "b.Finder", tokens: ["Nova"],
                             undocked: Destination(screen: "builtin", desktop: 1))
        let tray = Rule(id: "tray", appName: "Preview", bundleID: "b.Preview", tokens: ["Vega"],
                        undocked: Destination(screen: "builtin", desktop: 2))
        let rules = [docked, otherPlan, tray]
        let windows = [window(1, "Code", "a.md — Orion"), window(2, "Finder", "Nova"),
                       window(3, "Mail", "Inbox"), window(4, "Notes", "Lumen")]
        // 1 ve 4 oturum pinli: ruleFor nil döner (oturum pini kazanır).
        let result = MultiPinBar.plan(selected: [1, 2, 3, 4], windows: windows,
                                      existingRules: rules, selectedRules: ["tray", "docked"],
                                      mode: .docked, sessionPinned: [1, 4],
                                      ruleFor: { _ in nil }) { _ in .full }
        #expect(result.existing == ["docked"])
        #expect(result.rules.map(\.rule.appName) == ["Finder", "Mail"])
        #expect(result.temporary == [1, 4])
        #expect(result.sessions.isEmpty)
        // Gruplamasız planda oturum pini denetimi yok (eski davranış).
        let plain = MultiPinBar.plan(selected: [1], windows: windows, sessionPinned: [1]) { _ in .full }
        #expect(plain.temporary.isEmpty && plain.rules.count == 1)
    }

    /// Öbür planda yeri olan kurala düşen pencere gruplanınca bu planda da
    /// yer alır ve grubun bu moddaki üyesi olur.
    @MainActor @Test func pinAsGroupPlacesARuleThatOnlyHadTheOtherPlan() throws {
        var d = Document()
        d.rules = [Rule(id: "other", appName: "Finder", bundleID: "b.Finder", tokens: ["Nova"],
                        undocked: Destination(screen: "builtin", desktop: 1))]
        d.syncActiveProfile()
        let store = Store(demo: d)
        let plan = MultiPinBar.plan(selected: [2], windows: [window(2, "Finder", "Nova")],
                                    existingRules: store.document.rules, mode: .docked,
                                    ruleFor: { _ in nil }) { _ in .full }
        let id = try #require(store.pinAsGroup(new: plan.rules, existing: plan.existing, mode: .docked))
        #expect(store.document.rules.count == 1)
        #expect(store.document.pinGroupMembers(id, mode: .docked).map(\.id) == ["other"])
        #expect(store.document.rules[0][.docked]?.desktop == 2)
        #expect(store.document.rules[0][.undocked]?.desktop == 1)
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
