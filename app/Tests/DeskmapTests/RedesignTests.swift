import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Yeni arayüzün saf parçaları: pencere arama, "Son hareketler" günlüğü,
/// başlangıç rehberinin açılma kararı, masaüstü önizlemesinin boyu, menü
/// çubuğundaki "olduğu yere sabitle" seçimi ve toplam pencere genişliği.
struct RedesignTests {

    private func win(_ id: CGWindowID, _ app: String, title: String = "", desktop: Int? = 1,
                     fullscreen: Bool = false) -> Router.WindowSnapshot {
        var window = Router.WindowSnapshot(
            id: id, pid: 1, appName: app, bundleID: "b.\(app)", title: title,
            placement: desktop.map { .init(screen: "builtin", desktop: $0) },
            frame: nil, isMinimized: false)
        if fullscreen { window.fullscreen = .init(screen: "builtin", space: 9, afterDesktop: 1, order: 0) }
        return window
    }

    // MARK: Arama

    @Test func searchMatchesAppOrTitleIgnoringCaseAndAccents() {
        #expect(UIState.matches(query: "", appName: "Safari", title: "Docs"))
        #expect(UIState.matches(query: "  ", appName: "Safari", title: "Docs"))
        #expect(UIState.matches(query: "safari", appName: "Safari", title: "Docs"))
        #expect(UIState.matches(query: "DOC", appName: "Safari", title: "Docs"))
        #expect(UIState.matches(query: "gorusme", appName: "Notes", title: "Görüşme notları"))
        #expect(!UIState.matches(query: "mail", appName: "Safari", title: "Docs"))
    }

    // MARK: Son hareketler

    @Test func logPutsNewestFirstAndKeepsTheLimit() {
        let start = Date(timeIntervalSince1970: 0)
        var log = Router.mergedLog([], adding: ["a", "b"], at: start)
        // Aynı taramada sonra yapılan taşıma üstte.
        #expect(log.map(\.text) == ["b", "a"])
        log = Router.mergedLog(log, adding: ["c"], at: start.addingTimeInterval(5))
        #expect(log.map(\.text) == ["c", "b", "a"])
        let many = (0..<(Router.actionLogLimit + 10)).map { "m\($0)" }
        let capped = Router.mergedLog(log, adding: many, at: start)
        #expect(capped.count == Router.actionLogLimit)
        #expect(capped.first?.text == "m\(Router.actionLogLimit + 9)")
    }

    // MARK: Başlangıç rehberi

    @Test func welcomeShowsOnlyOnFirstRunWithoutPins() {
        #expect(WelcomeWindow.shouldShow(done: false, ruleCount: 0))
        #expect(!WelcomeWindow.shouldShow(done: true, ruleCount: 0))
        // Sabitlemesi olan eski kurulumda gösterilmez.
        #expect(!WelcomeWindow.shouldShow(done: false, ruleCount: 3))
    }

    // MARK: Masaüstü önizlemesi

    @Test func previewKeepsTheScreensShapeWithinLimits() {
        let wide = DesktopPreview.size(screenSize: CGSize(width: 1710, height: 1074))
        #expect(wide.width == DesktopPreview.width)
        #expect(abs(wide.height - (DesktopPreview.width / (1710.0 / 1074.0)).rounded()) < 0.5)
        // Ultra geniş ekran çok basık, dikey ekran çok uzun olmasın.
        let ultra = DesktopPreview.size(screenSize: CGSize(width: 5120, height: 1000))
        #expect(ultra.height == (DesktopPreview.width / 3.6).rounded())
        let tall = DesktopPreview.size(screenSize: CGSize(width: 1000, height: 3000))
        #expect(tall.height == (DesktopPreview.width / 0.6).rounded())
        let unknown = DesktopPreview.size(screenSize: .zero)
        #expect(unknown.height == (DesktopPreview.width / 1.6).rounded())
    }

    // MARK: Menü çubuğu

    @Test func menuOffersPinningOnlyForAnUnpinnedPlacedFrontWindow() {
        let rule = Rule(appName: "A", bundleID: "b.A", tokens: [],
                        docked: Destination(screen: "builtin", desktop: 1))
        let windows = [win(1, "A"), win(2, "B"), win(3, "C", desktop: nil), win(4, "D", fullscreen: true)]
        func front(_ id: CGWindowID?) -> CGWindowID? {
            StatusItemMenu.unpinnedFront(id, windows: windows, rules: [rule], sessionPins: [:],
                                         mode: .docked)?.id
        }
        #expect(front(1) == nil)      // sabit: serbest hareket menüsü çıkar
        #expect(front(2) == 2)        // sabit değil, bir masaüstünde
        #expect(front(3) == nil)      // yeri bilinmiyor
        #expect(front(4) == nil)      // tam ekran
        #expect(front(nil) == nil)
        #expect(StatusItemMenu.unpinnedFront(
            2, windows: windows, rules: [rule],
            sessionPins: [2: Destination(screen: "builtin", desktop: 2)], mode: .docked) == nil)
    }

    // MARK: Pencere genişliği

    @Test func inspectorColumnWidensTheWindowButNeverPastTheScreen() {
        let roomy = RootView.totalWidth(visibleWidth: 1710)
        #expect(roomy == RootView.windowWidth(visibleWidth: 1710) + RootView.inspectorWidth + 1)
        let small = RootView.totalWidth(visibleWidth: 1000)
        #expect(small <= 1000 - 2 * RootView.screenMargin)
    }
}
