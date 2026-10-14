import AppKit
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
        let closed = code("closed", tokens: ["vega"], docked: external)
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
        var external = d
        external.screen = "external"
        let otherScreen = Rule(id: "screen", appName: "F", bundleID: "f", tokens: [],
                               docked: external, undocked: d)
        let empty = Rule(id: "empty", appName: "G", bundleID: "g", tokens: [])
        let rules = [both, dockedOnly, laptopOnly, moved, resized, otherScreen, empty]
        // İki modda da yeri olanlar (başka yerde bile) ve boş kural listelenmez.
        let groups = ScreenMapView.setupDifferences(rules: rules, mode: .docked)
        #expect(groups.onlyOther.map(\.id) == ["lap"])
        #expect(groups.onlyThis.map(\.id) == ["dock"])
        let laptop = ScreenMapView.setupDifferences(rules: rules, mode: .undocked)
        #expect(laptop.onlyOther.map(\.id) == ["dock"])
        #expect(laptop.onlyThis.map(\.id) == ["lap"])
    }

    @Test func desktopDropAcceptsOtherDisplays() {
        #expect(!ScreenMapView.acceptsDesktopDrop(fromScreen: "builtin", from: 2,
                                                  toScreen: "builtin", to: 2))
        #expect(ScreenMapView.acceptsDesktopDrop(fromScreen: "builtin", from: 2,
                                                 toScreen: "builtin", to: 1))
        #expect(ScreenMapView.acceptsDesktopDrop(fromScreen: "builtin", from: 2,
                                                 toScreen: "external", to: 2))
    }

    @Test func unownedExcludesAnyPinInEitherMode() {
        func window(_ id: CGWindowID, _ bundle: String, _ title: String) -> Router.WindowSnapshot {
            Router.WindowSnapshot(id: id, pid: 1, appName: bundle, bundleID: bundle, title: title,
                                  placement: .init(screen: "builtin", desktop: 1), frame: nil,
                                  isMinimized: false, fullscreen: nil)
        }
        let laptopOnly = Rule(id: "lap", appName: "c", bundleID: "c", tokens: [], undocked: d)
        let titled = Rule(id: "t", appName: "a", bundleID: "a", tokens: ["Work"], docked: d)
        let empty = Rule(id: "e", appName: "x", bundleID: "x", tokens: [])
        let windows = [window(1, "a", "Work – doc"), window(2, "a", "Home"),
                       window(3, "c", "any"), window(4, "s", "session"), window(5, "x", "no dest")]
        let unowned = ScreenMapView.unownedWindows(windows, rules: [laptopOnly, titled, empty],
                                                   sessionPins: [4: d])
        #expect(unowned.map(\.id) == [2, 5])
        // Tam ekran ya da yeri bilinmeyen pencere listelenmez (dokunulmaz).
        var full = window(6, "z", "video")
        full.fullscreen = Router.FullscreenSlot(screen: "builtin", space: 9, afterDesktop: 1, order: 0)
        let unplaced = Router.WindowSnapshot(id: 7, pid: 1, appName: "z", bundleID: "z", title: "t",
                                             placement: nil, frame: nil, isMinimized: false)
        #expect(ScreenMapView.unownedWindows([full, unplaced], rules: [], sessionPins: [:]).isEmpty)
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

    private func total(_ chrome: CGFloat, _ panel: CGFloat, _ room: CGFloat,
                       _ preferred: CGFloat = 740) -> CGFloat {
        let h = RootView.heights(chrome: chrome, panel: panel, room: room, preferredTotal: preferred)
        return chrome + h.map + min(panel, h.panelCap ?? panel)
    }

    @Test func panelGrowsTheWindowInsteadOfTheMap() {
        let closed = RootView.heights(chrome: 120, panel: 0, room: 1400, preferredTotal: 740)
        let open = RootView.heights(chrome: 120, panel: 320, room: 1400, preferredTotal: 740)
        #expect(closed.map == 620)
        #expect(open.map == closed.map)
        #expect(open.panelCap == nil)
    }

    @Test func shrinksTheMapByTheOverflowOnly() {
        // 900 pt alan: 900 - 120 - 320 = 460.
        let h = RootView.heights(chrome: 120, panel: 320, room: 900, preferredTotal: 740)
        #expect(h.map == 460 && h.panelCap == nil)
    }

    @Test func panelScrollsWhenEvenTheMinimumMapDoesNotFit() {
        let h = RootView.heights(chrome: 120, panel: 500, room: 700, preferredTotal: 740)
        #expect(h.map == RootView.minMapHeight)
        #expect(h.panelCap == 700 - 120 - RootView.minMapHeight)
    }

    @Test func neverTallerThanTheRoom() {
        for room in stride(from: CGFloat(100), through: 1600, by: 37) {
            for panel in stride(from: CGFloat(0), through: 900, by: 53) {
                for chrome in [CGFloat(80), 126, 170] {
                    let preferred = RootView.preferredHeight(visibleHeight: room)
                    #expect(total(chrome, panel, room, preferred) <= max(room, chrome) + 0.001,
                            "room \(room) panel \(panel) chrome \(chrome)")
                }
            }
        }
    }

    @Test func sizeIsRelativeToTheScreen() {
        // Bu Mac'in laptop ekranı (1710×1074 pt): ≈ 906×752.
        #expect(abs(RootView.windowWidth(visibleWidth: 1710) - 906) < 1)
        #expect(abs(RootView.preferredHeight(visibleHeight: 1074) - 752) < 1)
        // Küçük ekran (1280×775, ör. 13" varsayılan): alt sınır, ekrana sığar.
        #expect(abs(RootView.windowWidth(visibleWidth: 1280) - 678.4) < 0.01)
        #expect(RootView.windowWidth(visibleWidth: 1024) == RootView.minWindowWidth)
        #expect(RootView.preferredHeight(visibleHeight: 775) < 775)
        // Çok dar ekran: ekrandan geniş olmaz.
        #expect(RootView.windowWidth(visibleWidth: 600) == 600 - 2 * RootView.screenMargin)
        // Çok büyük ekran: üst sınır.
        #expect(RootView.windowWidth(visibleWidth: 5120) == RootView.maxWindowWidth)
        #expect(RootView.preferredHeight(visibleHeight: 1410) == RootView.maxWindowHeight)
        // Kenar çubuğu pencereyle orantılı, sınırlar içinde.
        #expect(RootView.sidebarWidth(windowWidth: 660) == 220)
        #expect(RootView.sidebarWidth(windowWidth: 1100) == 300)
    }

    @Test func roomComesFromTheVisibleFrameNotTheWindowTop() {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 875)   // Dock 70 pt, menü çubuğu üstte
        #expect(WindowRoomReader.room(visible: visible, margin: 12) == 863)
    }
}

@MainActor
struct MenuBarBadgeTests {

    @Test func badgeTextCapsAtNine() {
        #expect(MenuBarLabel.badgeText(1) == "1")
        #expect(MenuBarLabel.badgeText(9) == "9")
        #expect(MenuBarLabel.badgeText(12) == "9+")
    }

    @Test func badgedIconIsATemplateAndWiderThanTheIcon() {
        let base = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        let badged = MenuBarLabel.badged(base, count: 4)
        #expect(badged.isTemplate)
        #expect(badged.size.width > 22 && badged.size.height == 16)
    }
}

struct OtherSetupDraftTests {

    private let laptop = [KnownScreen(id: "builtin", name: "Built-in", aspect: 1.6)]

    @Test func liveSetupUsesWhereTheWindowIs() {
        let here = Router.Placement(screen: "external", desktop: 3)
        #expect(WindowRow.draftTarget(here, isLive: true, screens: laptop) == here)
    }

    @Test func otherSetupKeepsThePlaceOnlyIfThatDisplayBelongsToIt() {
        let onBuiltin = Router.Placement(screen: "builtin", desktop: 4)
        #expect(WindowRow.draftTarget(onBuiltin, isLive: false, screens: laptop) == onBuiltin)
        let onExternal = Router.Placement(screen: "external", desktop: 2)
        #expect(WindowRow.draftTarget(onExternal, isLive: false, screens: laptop)
                == Router.Placement(screen: "builtin", desktop: 1))
        #expect(WindowRow.draftTarget(nil, isLive: false, screens: []) == nil)
    }
}

struct LiveDraftFollowTests {

    private let first = Router.Placement(screen: "builtin", desktop: 1)
    private let second = Router.Placement(screen: "builtin", desktop: 2)

    private func window(_ placement: Router.Placement?, title: String = "t",
                        id: CGWindowID = 1) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "a", bundleID: "a", title: title,
                              placement: placement, frame: nil, isMinimized: false)
    }

    @Test func liveDraftFollowsTheWindowToAnotherDesktop() {
        let draft = PinDraft(window: window(first), target: first)
        let followed = draft.following(window(second, title: "renamed"), isLive: true)
        #expect(followed.target == second)
        #expect(followed.window.placement == second)
        // Seçilen parçalar taslağın açıldığı başlığa ait.
        #expect(followed.window.title == "t")
    }

    @Test func unmovedUnknownOrOtherWindowLeavesTheDraftAlone() {
        let draft = PinDraft(window: window(first), target: first)
        #expect(draft.following(window(first, title: "renamed"), isLive: true) == draft)
        #expect(draft.following(window(nil), isLive: true) == draft)
        #expect(draft.following(window(second, id: 2), isLive: true) == draft)
    }

    @Test func liveDraftFollowsTheWindowFrameButKeepsADroppedTarget() {
        func sized(_ width: CGFloat, _ placement: Router.Placement) -> Router.WindowSnapshot {
            Router.WindowSnapshot(id: 1, pid: 1, appName: "a", bundleID: "a", title: "t",
                                  placement: placement,
                                  frame: CGRect(x: 0, y: 0, width: width, height: 500),
                                  isMinimized: false)
        }
        // Harita kapalıyken boyutu değişen pencere: taze ölçüm taslağa geçer.
        let stale = PinDraft(window: sized(840, first), target: first)
        let fresh = stale.following(sized(1000, first), isLive: true)
        #expect(fresh.window.frame?.width == 1000)
        #expect(fresh.target == first)
        #expect(fresh.following(sized(1000, first), isLive: true) == fresh)
        // Bırakmayla seçilen hedef, pencere henüz eski masaüstündeyken gelen
        // çerçeve değişimiyle geri dönmez.
        let dropped = PinDraft(window: sized(840, first), target: second)
        #expect(dropped.following(sized(1000, first), isLive: true).target == second)
        // Diğer kurulumun taslağı çerçeveyi de izlemez.
        let other = PinDraft(window: sized(840, first), target: second, followsWindow: false)
        #expect(other.following(sized(1000, first), isLive: true) == other)
    }

    @Test func otherSetupDraftKeepsItsTarget() {
        let draft = PinDraft(window: window(first), target: second)
        #expect(draft.following(window(second), isLive: false) == draft)
    }

    @Test func draftOpenedInTheOtherSetupKeepsItsTargetWhenThatSetupGoesLive() {
        // Undocked sekmesinde harici ekrandaki pencere dahili · Masaüstü 2'ye
        // bırakıldı; monitör çıkınca sekme canlı olur, macOS pencereyi
        // dahili · Masaüstü 1'e alır. Kullanıcının seçtiği hedef kalır.
        let external = Router.Placement(screen: "external", desktop: 1)
        let draft = PinDraft(window: window(external), target: second, followsWindow: false)
        #expect(draft.following(window(first), isLive: true) == draft)
    }

    @Test func droppedDraftSurvivesAStaleScanAndSettlesOnTheMove() {
        // Bırakma hedefi hemen yeni masaüstüne alır; pencere eski yerinde
        // görünen ara tarama taslağı geri çevirmez.
        let dropped = PinDraft(window: window(first), target: second)
        #expect(dropped.following(window(first), isLive: true) == dropped)
        let settled = dropped.following(window(second), isLive: true)
        #expect(settled.target == second)
        #expect(settled.following(window(second), isLive: true) == settled)
    }
}

struct UnpinnedDropTests {

    private let here = Router.Placement(screen: "builtin", desktop: 2)

    private var window: Router.WindowSnapshot {
        Router.WindowSnapshot(id: 1, pid: 1, appName: "a", bundleID: "a", title: "t",
                              placement: here, frame: nil, isMinimized: false)
    }

    @Test func onlyRealMovesOrOtherSetupDraftsAct() {
        #expect(!WindowRow.unpinnedDropActs(.tray, window: window, isLive: true))
        #expect(!WindowRow.unpinnedDropActs(.desktop(screen: "builtin", desktop: 2), window: window, isLive: true))
        #expect(WindowRow.unpinnedDropActs(.desktop(screen: "builtin", desktop: 3), window: window, isLive: true))
        #expect(WindowRow.unpinnedDropActs(.desktop(screen: "builtin", desktop: 2), window: window, isLive: false))
    }

    // MARK: Harita açılışında öndeki pencere

    private func entry(_ id: UInt32, pid: Int32, layer: Int = 0,
                       size: (Double, Double) = (800, 600)) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
         kCGWindowLayer as String: layer,
         kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": size.0, "Height": size.1]]
    }

    @Test func frontWindowIsFirstNormalWindowOfTheApp() {
        // Önden arkaya: başka uygulama, menü katmanı, küçük yardımcı, sonra asıl pencereler.
        let list = [entry(1, pid: 9), entry(2, pid: 7, layer: 25),
                    entry(3, pid: 7, size: (30, 30)), entry(4, pid: 7), entry(5, pid: 7)]
        #expect(AX.frontWindowID(in: list, pid: 7) == 4)
        #expect(AX.frontWindowID(in: list, pid: 8) == nil)
    }

    @Test func openingPanelMatchesClickingTheRow() {
        let place = Router.Placement(screen: "external", desktop: 2)
        let placed = Router.WindowSnapshot(id: 5, pid: 1, appName: "Code", bundleID: "c",
                                           title: "t", placement: place, frame: nil,
                                           isMinimized: false)
        #expect(UIState.openingPanel(for: placed, sessionPinned: true, ruleID: "r")
                == .session(5))
        #expect(UIState.openingPanel(for: placed, sessionPinned: false, ruleID: "r")
                == .rule("r"))
        #expect(UIState.openingPanel(for: placed, sessionPinned: false, ruleID: nil)
                == .pin(PinDraft(window: placed, target: place)))
        // Yeri bilinmeyen pinsiz pencerede taslak açılmaz.
        let unplaced = Router.WindowSnapshot(id: 6, pid: 1, appName: "Code", bundleID: "c",
                                             title: "t", placement: nil, frame: nil,
                                             isMinimized: false)
        #expect(UIState.openingPanel(for: unplaced, sessionPinned: false, ruleID: nil) == nil)
    }

    // MARK: Simgeye sağ tık menüsü

    @Test func statusMenuOnlyForPinnedFrontWindow() {
        let place = Router.Placement(screen: "external", desktop: 2)
        let code = Router.WindowSnapshot(id: 5, pid: 1, appName: "Code", bundleID: "c",
                                         title: "atlas", placement: place, frame: nil,
                                         isMinimized: false)
        let other = Router.WindowSnapshot(id: 6, pid: 2, appName: "Notes", bundleID: "n",
                                          title: "note", placement: place, frame: nil,
                                          isMinimized: false)
        let target = Destination(screen: "external", desktop: 2)
        let rule = Rule(id: "r", appName: "Code", bundleID: "c", tokens: [], docked: target)
        func front(_ id: CGWindowID?, pins: [CGWindowID: Destination] = [:],
                   mode: Mode = .docked) -> CGWindowID? {
            StatusItemMenu.pinnedFront(id, windows: [code, other], rules: [rule],
                                       sessionPins: pins, mode: mode)?.id
        }
        #expect(front(5) == 5)
        // Pinsiz pencere, bilinmeyen pencere, öndeki pencere yok: menü yok.
        #expect(front(6) == nil)
        #expect(front(99) == nil)
        #expect(front(nil) == nil)
        // Kuralın bu kurulumda hedefi yok.
        #expect(front(5, mode: .undocked) == nil)
        // Geçici pin de pin sayılır.
        #expect(front(6, pins: [6: target]) == 6)
    }

    @Test func statusMenuHeaderShortensLongTitles() {
        func snapshot(_ title: String) -> Router.WindowSnapshot {
            Router.WindowSnapshot(id: 1, pid: 1, appName: "Safari", bundleID: "s", title: title,
                                  placement: nil, frame: nil, isMinimized: false)
        }
        #expect(StatusItemMenu.header(for: snapshot("")) == "Safari")
        #expect(StatusItemMenu.header(for: snapshot("Safari")) == "Safari")
        #expect(StatusItemMenu.header(for: snapshot("Docs")) == "Safari — Docs")
        let long = StatusItemMenu.header(for: snapshot(String(repeating: "a", count: 80)), limit: 10)
        #expect(long == "Safari — aaaaaaaaa…")
    }

}

/// "Yalnız bir planda sabit" kutusundaki çipin panelinde "Sabitlemeyi
/// kaldır": bakılan planda pin yoksa pinin durduğu öbür planı kaldırır
/// (eskiden bakılan planı hedefleyip hiçbir şey yapmıyordu).
struct TrayUnpinTests {

    private let builtin2 = Destination(screen: "builtin", desktop: 2)

    @Test func unpinTargetsThePlanBeingViewedWhenItHasAPin() {
        let rule = Rule(id: "r", appName: "Telegram", bundleID: "tg", tokens: [],
                        docked: builtin2, undocked: builtin2)
        #expect(RulePanel.unpinMode(for: rule, viewing: .docked) == .docked)
        #expect(RulePanel.unpinMode(for: rule, viewing: .undocked) == .undocked)
    }

    @Test func unpinFallsBackToTheOtherPlanForAnOtherPlanOnlyChip() {
        let laptopOnly = Rule(id: "r", appName: "Telegram", bundleID: "tg", tokens: [],
                              undocked: builtin2)
        #expect(RulePanel.unpinMode(for: laptopOnly, viewing: .docked) == .undocked)
        var doc = Document()
        doc.rules = [laptopOnly]
        doc.unpin("r", mode: RulePanel.unpinMode(for: laptopOnly, viewing: .docked)!)
        #expect(doc.rules.isEmpty)
    }

    @Test func noUnpinWithoutAnyPin() {
        let empty = Rule(id: "r", appName: "A", bundleID: "a", tokens: [])
        #expect(RulePanel.unpinMode(for: empty, viewing: .docked) == nil)
    }
}

struct MapWindowPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func builtInScreenCentersAtTop() {
        let p = WindowRoomReader.placed(CGRect(x: 1300, y: 10, width: 1000, height: 600),
                                        visible: visible, builtIn: true)
        #expect(p == CGPoint(x: 256, y: 344))
    }

    @Test func externalScreenKeepsPositionButStaysInside() {
        let ext = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
        let inside = WindowRoomReader.placed(CGRect(x: 2000, y: 500, width: 1000, height: 600),
                                             visible: ext, builtIn: false)
        #expect(inside == CGPoint(x: 2000, y: 500))
        let over = WindowRoomReader.placed(CGRect(x: 3500, y: 1000, width: 1000, height: 600),
                                           visible: ext, builtIn: false)
        #expect(over == CGPoint(x: 3072, y: 815))
    }
}
