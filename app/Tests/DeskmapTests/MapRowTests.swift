import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Harita satırları: tıklama, ⌘-seçim, daraltılmış grupların yeniden
/// numaralanması, önizleme yazısı ve etiket sütunu.
struct MapRowTests {

    private func window(_ id: CGWindowID) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "Mail", bundleID: "com.apple.mail",
                              title: "Inbox", placement: Router.Placement(screen: "s", desktop: 1),
                              frame: nil, isMinimized: false)
    }

    // MARK: Seçim ve panel

    @MainActor @Test func openingAPanelClearsTheSelection() {
        let ui = UIState()
        ui.persistsPreferences = false
        ui.selection = [1, 2]
        ui.toggle(.rule("r"))
        #expect(ui.panel == .rule("r"))
        #expect(ui.selection.isEmpty)
    }

    @MainActor @Test func closingThePanelKeepsTheSelection() {
        let ui = UIState()
        ui.persistsPreferences = false
        ui.panel = nil
        ui.selection = [1]
        ui.panel = nil
        #expect(ui.selection == [1])
    }

    // MARK: Tek ve çift tıklama

    @MainActor @Test func singleClickRunsAtOnce() {
        let ui = UIState()
        var singles = 0, doubles = 0
        ui.handleClick(count: 1, single: { singles += 1; ui.toggle(.rule("r")) },
                       double: { doubles += 1 })
        #expect(singles == 1 && doubles == 0)
        #expect(ui.panel == .rule("r"))
    }

    @MainActor @Test func doubleClickUndoesTheFirstClickThenRunsOnce() {
        let ui = UIState()
        ui.selection = [7]
        var doubles = 0
        let single = { ui.toggle(.rule("r"), from: 3) }
        ui.handleClick(count: 1, single: single, double: { doubles += 1 })
        #expect(ui.panel == .rule("r"))
        ui.handleClick(count: 2, single: single, double: { doubles += 1 })
        #expect(doubles == 1)
        #expect(ui.panel == nil)
        #expect(ui.panelSourceWindowID == nil)
        #expect(ui.selection == [7])
    }

    @MainActor @Test func doubleClickRestoresAnOpenPanel() {
        let ui = UIState()
        ui.toggle(.rule("r"))
        let single = { ui.toggle(.rule("r")) }
        ui.handleClick(count: 1, single: single, double: {})
        #expect(ui.panel == nil)
        ui.handleClick(count: 2, single: single, double: {})
        #expect(ui.panel == .rule("r"))
    }

    @MainActor @Test func tripleClickIsIgnored() {
        let ui = UIState()
        var calls = 0
        ui.handleClick(count: 3, single: { calls += 1 }, double: { calls += 1 })
        #expect(calls == 0)
    }

    // MARK: Daraltılmış gruplar

    @Test func collapsedKeysFollowAReorderedDesktop() {
        let keys: Set = ["docked|s|2|com.apple.Safari", "docked|s|4|com.apple.mail",
                         "docked|t|2|com.apple.Safari"]
        let mapping = Document.desktopMapping(from: 2, to: 4, count: 4)!
        let next = UIState.remapCollapsed(keys, modes: [.docked]) { s, d in
            s == "s" ? (s, mapping[d] ?? d) : (s, d)
        }
        #expect(next == ["docked|s|4|com.apple.Safari", "docked|s|3|com.apple.mail",
                         "docked|t|2|com.apple.Safari"])
    }

    @Test func collapsedKeysOfARemovedDesktopAreDropped() {
        let keys: Set = ["docked|s|1|a", "docked|s|2|b", "docked|s|3|c"]
        let next = UIState.remapCollapsed(keys, modes: [.docked]) { s, d in
            guard d >= 2 else { return (s, d) }
            return d == 2 ? nil : (s, d - 1)
        }
        #expect(next == ["docked|s|1|a", "docked|s|2|c"])
    }

    @Test func collapsedKeysMoveAcrossScreens() {
        let keys: Set = ["docked|s|2|a", "docked|s|3|b", "docked|t|1|c", "docked|t|2|d"]
        let next = UIState.remapCollapsed(keys, modes: [.docked]) { s, d in
            Document.acrossPlacement(screen: s, desktop: d, from: "s", desktop: 2,
                                     to: "t", at: 2) ?? (s, d)
        }
        #expect(next == ["docked|t|2|a", "docked|s|2|b", "docked|t|1|c", "docked|t|3|d"])
    }

    /// Öbür planın sekmesindeki silme canlı sekmenin daraltmalarını kaydırmaz.
    @Test func collapsedKeysOfTheOtherPlanStay() {
        let keys: Set = [UIState.collapseKey(mode: .docked, screen: "builtin", desktop: 3,
                                             group: "com.apple.Safari"),
                         UIState.collapseKey(mode: .undocked, screen: "builtin", desktop: 3,
                                             group: "com.apple.Safari")]
        let next = UIState.remapCollapsed(keys, modes: [.undocked]) { s, d in
            guard d >= 2 else { return (s, d) }
            return d == 2 ? nil : (s, d - 1)
        }
        #expect(next == ["docked|builtin|3|com.apple.Safari", "undocked|builtin|2|com.apple.Safari"])
    }

    @Test func malformedCollapsedKeysStay() {
        let next = UIState.remapCollapsed(["odd", "s|x|a", "docked|s|x|a", "plan|s|1|a"],
                                          modes: Mode.allCases) { _, _ in nil }
        #expect(next == ["odd", "s|x|a", "docked|s|x|a", "plan|s|1|a"])
    }

    /// ⌘Z numaraları geri getirir; arada elle daraltılan grup korunur.
    @Test func revertingARemapKeepsLaterToggles() {
        let before: Set = ["docked|s|2|a", "docked|s|3|b"]
        let after: Set = ["docked|s|2|b"]
        let current = after.union(["docked|s|1|c"])
        #expect(UIState.revertRemap(current, before: before, after: after)
                == ["docked|s|2|a", "docked|s|3|b", "docked|s|1|c"])
    }

    @MainActor @Test func remapReturnsAnUndoClosure() {
        let ui = UIState()
        ui.collapsed = ["docked|s|2|a", "docked|s|3|b"]
        let undo = ui.remapCollapsed(modes: [.docked]) { s, d in d == 2 ? nil : (s, d - 1) }
        #expect(ui.collapsed == ["docked|s|2|b"])
        undo?()
        #expect(ui.collapsed == ["docked|s|2|a", "docked|s|3|b"])
        #expect(ui.remapCollapsed(modes: [.undocked]) { _, _ in nil } == nil)
    }

    // MARK: Önizleme yazısı

    @Test func previewLabelDropsTheAppName() {
        #expect(DesktopPreview.label(appName: "Mail", title: "Release notes — Mail") == "Release notes")
        #expect(DesktopPreview.label(appName: "Code", title: "a.swift - Code") == "a.swift")
        #expect(DesktopPreview.label(appName: "Messages", title: "general") == "general")
        #expect(DesktopPreview.label(appName: "Mail", title: "") == "Mail")
        #expect(DesktopPreview.label(appName: "Mail", title: "Mail") == "Mail")
    }

    // MARK: Etiket sütunu

    @Test func labelColumnIsSharedPerMode() {
        #expect(ScreenMapView.labelWidth(visual: true, hasNamedRows: false) == DesktopPreview.width)
        #expect(ScreenMapView.labelWidth(visual: true, hasNamedRows: true) == DesktopPreview.width)
        #expect(ScreenMapView.labelWidth(visual: false, hasNamedRows: false) == 84)
        #expect(ScreenMapView.labelWidth(visual: false, hasNamedRows: true) == 132)
    }
}
