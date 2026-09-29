import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Ekran haritasının saf kararları: gölgede kalan kurallar, eksik masaüstü rozeti.
struct MapLogicTests {

    private let external = Destination(screen: "external", desktop: 2)
    private let builtin = Destination(screen: "builtin", desktop: 1)

    private func window(_ id: CGWindowID, title: String,
                        app: (name: String, bundle: String) = ("Code", "com.microsoft.VSCode"))
        -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app.name, bundleID: app.bundle,
                              title: title, placement: nil, frame: nil, isMinimized: false)
    }

    private func code(_ id: String, tokens: [String],
                      docked: Destination? = nil, undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "Code", bundleID: "com.microsoft.VSCode", tokens: tokens,
             docked: docked, undocked: undocked)
    }

    // MARK: Gölgede kalan kurallar

    @Test func appWideRuleLosingToSpecificIsShadowed() {
        let wide = code("wide", tokens: [], docked: builtin)
        let specific = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, specific], windows: [window(1, title: "Store.swift — Atlas")],
            sessionPins: [:], mode: .docked)
        #expect(result.winners == ["atlas"])
        #expect(result.shadowedBy == ["wide": "atlas"])
    }

    @Test func ruleWinningElsewhereIsNotShadowed() {
        let wide = code("wide", tokens: [], docked: builtin)
        let specific = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, specific],
            windows: [window(1, title: "Store.swift — Atlas"), window(2, title: "Other.swift")],
            sessionPins: [:], mode: .docked)
        // Geniş kural 2 numaralı pencerede kazandı; gölgede sayılmaz.
        #expect(result.winners == ["atlas", "wide"])
        #expect(result.shadowedBy.isEmpty)
    }

    @Test func sessionPinShadowsMatchingRule() {
        let rule = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [rule], windows: [window(1, title: "Atlas")],
            sessionPins: [1: builtin], mode: .docked)
        #expect(result.winners == [Routing.sessionRuleID])
        #expect(result.shadowedBy == ["atlas": Routing.sessionRuleID])
    }

    @Test func rulesWithoutTargetInModeOrWithoutWindowAreIgnored() {
        let noTarget = code("undockedOnly", tokens: ["atlas"], undocked: external)
        let wide = code("wide", tokens: [], docked: builtin)
        let closed = code("closed", tokens: ["comet"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [noTarget, wide, closed], windows: [window(1, title: "Atlas")],
            sessionPins: [:], mode: .docked)
        #expect(result.winners == ["wide"])
        // Bu modda hedefi olmayan kural gölgede değil (zaten devrede değil);
        // penceresi kapalı kural da değil (o "penceresi yok" çipi olarak görünür).
        #expect(result.shadowedBy.isEmpty)
    }

    @Test func firstShadowingWinnerIsReported() {
        let wide = code("wide", tokens: [], docked: builtin)
        let a = code("a", tokens: ["alpha"], docked: external)
        let b = code("b", tokens: ["beta"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, a, b],
            windows: [window(1, title: "Alpha"), window(2, title: "Beta")],
            sessionPins: [:], mode: .docked)
        #expect(result.shadowedBy == ["wide": "a"])
        #expect(result.winners == ["a", "b"])
    }

    @Test func emptyInputs() {
        let empty = ScreenMapView.shadows(rules: [], windows: [], sessionPins: [:], mode: .docked)
        #expect(empty == ScreenMapView.RuleShadows())
        let noWindows = ScreenMapView.shadows(
            rules: [code("x", tokens: [], docked: builtin)], windows: [],
            sessionPins: [:], mode: .docked)
        #expect(noWindows == ScreenMapView.RuleShadows())
    }

    // MARK: Eksik masaüstü rozeti

    @Test func badgeOnlyWhenTargetExceedsRealCountOnConnectedScreen() {
        #expect(MissingDesktopBadge.clamped(wanted: 5, realCount: 3) == 3)
        #expect(MissingDesktopBadge.clamped(wanted: 3, realCount: 3) == nil)
        #expect(MissingDesktopBadge.clamped(wanted: 2, realCount: 3) == nil)
        // Ekran bağlı değil (sayı bilinmiyor) ya da hiç masaüstü okunamadı: rozet yok.
        #expect(MissingDesktopBadge.clamped(wanted: 5, realCount: nil) == nil)
        #expect(MissingDesktopBadge.clamped(wanted: 5, realCount: 0) == nil)
    }

    @Test func badgeLooksUpDestinationScreen() {
        let counts = ["builtin": 2, "external": 4]
        #expect(MissingDesktopBadge.clamped(
            for: Destination(screen: "builtin", desktop: 3), desktopCounts: counts,
            isLive: true) == 2)
        #expect(MissingDesktopBadge.clamped(
            for: Destination(screen: "external", desktop: 3), desktopCounts: counts,
            isLive: true) == nil)
        #expect(MissingDesktopBadge.clamped(
            for: Destination(screen: "external-2", desktop: 9), desktopCounts: counts,
            isLive: true) == nil)
    }

    @Test func badgeOnlyInLiveMode() {
        // desktopCounts bağlı ekranları anlatır, router yalnızca şu anki modda
        // kırpar; diğer modun haritasında aynı hedef rozet almaz.
        let counts = ["builtin": 2]
        let wanted = Destination(screen: "builtin", desktop: 5)
        #expect(MissingDesktopBadge.clamped(for: wanted, desktopCounts: counts, isLive: true) == 2)
        #expect(MissingDesktopBadge.clamped(for: wanted, desktopCounts: counts, isLive: false) == nil)
    }
}

struct TrayLogicTests {

    private let d = Destination(screen: "builtin", desktop: 1, layout: .full)

    @Test func setupDifferencesSplitsByMode() {
        let both = Rule(id: "both", appName: "A", bundleID: "a", tokens: [], docked: d, undocked: d)
        let dockedOnly = Rule(id: "dock", appName: "B", bundleID: "b", tokens: [], docked: d)
        let laptopOnly = Rule(id: "lap", appName: "C", bundleID: "c", tokens: [], undocked: d)
        var elsewhere = d
        elsewhere.desktop = 3
        var halfLayout = d
        halfLayout.layout = WindowLayout(x: 0, y: 0, w: 0.5, h: 1)
        let moved = Rule(id: "moved", appName: "D", bundleID: "d", tokens: [], docked: d, undocked: elsewhere)
        let resized = Rule(id: "resized", appName: "E", bundleID: "e", tokens: [], docked: d, undocked: halfLayout)
        let groups = ScreenMapView.setupDifferences(
            rules: [both, dockedOnly, laptopOnly, moved, resized], mode: .docked)
        #expect(groups.onlyOther.map(\.id) == ["lap"])
        #expect(groups.onlyThis.map(\.id) == ["dock"])
        #expect(groups.placedDifferently.map(\.id) == ["moved"])
    }

    @Test func unownedExcludesAnyPinInEitherMode() {
        func window(_ id: CGWindowID, _ bundle: String, _ title: String) -> Router.WindowSnapshot {
            Router.WindowSnapshot(id: id, pid: 1, appName: bundle, bundleID: bundle, title: title,
                                  placement: nil, frame: nil, isMinimized: false, fullscreen: nil)
        }
        let laptopOnly = Rule(id: "lap", appName: "c", bundleID: "c", tokens: [], undocked: d)
        let titled = Rule(id: "t", appName: "a", bundleID: "a", tokens: ["Work"], docked: d)
        let empty = Rule(id: "e", appName: "x", bundleID: "x", tokens: [])
        let windows = [window(1, "a", "Work – doc"), window(2, "a", "Home"),
                       window(3, "c", "any"), window(4, "s", "session"), window(5, "x", "no dest")]
        let unowned = ScreenMapView.unownedWindows(windows, rules: [laptopOnly, titled, empty],
                                                   sessionPins: [4: d])
        #expect(unowned.map(\.id) == [2, 5])
    }
}

struct AutoScrollTests {

    private let viewport = CGRect(x: 300, y: 100, width: 600, height: 500)

    @Test func stillInTheMiddleAndInTheSidebar() {
        #expect(AutoScroller.velocity(for: CGPoint(x: 600, y: 350), in: viewport) == 0)
        // Kenar çubuğu (haritanın solunda): kaydırmaz.
        #expect(AutoScroller.velocity(for: CGPoint(x: 100, y: 590), in: viewport) == 0)
    }

    @Test func fasterCloserToTheEdge() {
        let near = AutoScroller.velocity(for: CGPoint(x: 600, y: 590), in: viewport)
        let edge = AutoScroller.velocity(for: CGPoint(x: 600, y: 560), in: viewport)
        #expect(near > edge && edge > 0)
        #expect(AutoScroller.velocity(for: CGPoint(x: 600, y: 700), in: viewport) == AutoScroller.maxSpeed)
        #expect(AutoScroller.velocity(for: CGPoint(x: 600, y: 110), in: viewport) < 0)
        #expect(AutoScroller.velocity(for: CGPoint(x: 600, y: 0), in: viewport) == -AutoScroller.maxSpeed)
    }

    @Test func hiddenTargetsOutsideViewportsAreIgnored() {
        let targets = [DropTargetFrame(target: .tray, frame: CGRect(x: 300, y: -60, width: 600, height: 40))]
        // Görünür alanın üstünde kalmış hedef, imleç üst çubuktayken seçilmez.
        #expect(UIState.target(at: CGPoint(x: 400, y: -40), targets: targets, viewports: [viewport]) == nil)
        #expect(UIState.target(at: CGPoint(x: 400, y: -40), targets: targets, viewports: []) == .tray)
    }
}

struct WindowHeightTests {

    @Test func panelGrowsTheWindowInsteadOfTheMap() {
        // Büyük ekran: panel açık da olsa harita aynı yükseklikte.
        let closed = RootView.mapHeight(chrome: 120, panel: 0, screen: 1400)
        let open = RootView.mapHeight(chrome: 120, panel: 320, screen: 1400)
        #expect(closed == RootView.windowSize.height - 120)
        #expect(open == closed)
    }

    @Test func shrinksOnlyByTheOverflowAndNeverBelowTheMinimum() {
        // 950 pt ekran: 950 - 12 - 120 - 320 = 498.
        #expect(RootView.mapHeight(chrome: 120, panel: 320, screen: 950) == 498)
        #expect(RootView.mapHeight(chrome: 120, panel: 700, screen: 950) == RootView.minMapHeight)
    }
}
