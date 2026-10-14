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

    /// Sonuç sayısı haritada vurgulananı sayar: canlı planda açık pencereler
    /// ve penceresi kapalı pinler (açık pin bir kez), öbür planda o planın
    /// pinleri ve atanmamış pencereler.
    @Test func searchHitsCountWhatTheSelectedPlanHighlights() {
        let open = Rule(id: "open", appName: "Code", bundleID: "b.Code", tokens: ["acme"],
                        docked: Destination(screen: "builtin", desktop: 1), undocked: nil)
        let closed = Rule(id: "closed", appName: "Obsidian", bundleID: "b.Obsidian",
                          tokens: ["acme"],
                          docked: Destination(screen: "builtin", desktop: 2), undocked: nil)
        let windows = [win(1, "Code", title: "acme — Code"), win(2, "Mail", title: "acme news"),
                       win(3, "Safari", title: "Docs")]
        let rules = [open, closed]
        func hits(_ query: String, _ mode: Mode, live: Bool) -> Int {
            UIState.searchHits(query: query, windows: windows, rules: rules, sessionPins: [:],
                               mode: mode, isLive: live)
        }
        // Canlı: Code ve Mail pencereleri + kapalı Obsidian pini; açık Code pini ikinci kez sayılmaz.
        #expect(hits("acme", .docked, live: true) == 3)
        // Yalnız kapalı pine uyan arama turuncu sıfır göstermez.
        #expect(hits("obsidian", .docked, live: true) == 1)
        // Öbür planda o planın pinleri (ikisi) + atanmamış Mail; pinli Code penceresi listelenmez.
        #expect(hits("acme", .docked, live: false) == 3)
        // Pini olmayan planda iki pin "Yalnız öbür planda sabitli" çipi + atanmamış Mail.
        #expect(hits("acme", .undocked, live: false) == 3)
        #expect(hits("zzz", .docked, live: true) == 0)

        // Yalnız öbür planda sabitli pin kenar çubuğu kutusunda çip olarak
        // vurgulanır; sayı turuncu sıfır göstermez.
        let laptopOnly = Rule(id: "laptop", appName: "Notes", bundleID: "b.Notes", tokens: [],
                              docked: nil, undocked: Destination(screen: "builtin", desktop: 1))
        func hitsWith(_ query: String, _ windows: [Router.WindowSnapshot], live: Bool) -> Int {
            UIState.searchHits(query: query, windows: windows, rules: [laptopOnly], sessionPins: [:],
                               mode: .docked, isLive: live)
        }
        // Kapalı: iki sekmede de tek çip.
        #expect(hitsWith("notes", [], live: true) == 1)
        #expect(hitsWith("notes", [], live: false) == 1)
        // Açık: canlıda pencere (çip ikinci kez sayılmaz), öbür sekmede çip
        // (penceresi pinli olduğundan atanmamışlar arasında değil).
        let notesWindow = [win(4, "Notes", title: "Shopping")]
        #expect(hitsWith("notes", notesWindow, live: true) == 1)
        #expect(hitsWith("notes", notesWindow, live: false) == 1)
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

    @Test func previewLabelsOnlyTheBoxesNotCoveredFromAbove() {
        let full = CGRect(x: 0, y: 0, width: 150, height: 94)
        let left = CGRect(x: 0, y: 0, width: 75, height: 94)
        let right = CGRect(x: 75, y: 0, width: 75, height: 94)
        // Üç tam ekran pencere üst üste: yalnız en üstteki yazılır.
        #expect(DesktopPreview.labeled([full, full, full]) == [false, false, true])
        // Yan yana iki yarı: ikisi de yazılır.
        #expect(DesktopPreview.labeled([left, right]) == [true, true])
        // Alttaki tam pencerenin yazı alanını üstteki sol yarı örter.
        #expect(DesktopPreview.labeled([full, left]) == [false, true])
        // Alt kenardaki küçük pencere üstteki yazı alanına değmez.
        let bottom = CGRect(x: 0, y: 70, width: 60, height: 24)
        #expect(DesktopPreview.labeled([full, bottom]) == [true, true])
        #expect(DesktopPreview.labeled([]) == [])
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

    /// Hızlı duraklatma yalnız arada anahtar başka yoldan değişmediyse
    /// kendiliğinden devam eder.
    @Test func quickPauseResumesOnlyIfNothingElseToggledIt() {
        #expect(StatusItemMenu.autoResumes(armedAt: 3, changes: 3, enabled: false))
        // Anahtarla açılıp yeniden kapatıldı: süresiz duraklatma kalır.
        #expect(!StatusItemMenu.autoResumes(armedAt: 3, changes: 5, enabled: false))
        #expect(!StatusItemMenu.autoResumes(armedAt: 3, changes: 4, enabled: true))
    }

    @MainActor @Test func storeCountsOnlyEnabledChanges() {
        let store = Store(demo: Document())
        store.document.enabled = false
        #expect(store.enabledChanges == 1)
        store.document.screens = []
        store.document.enabled = false
        #expect(store.enabledChanges == 1)
        store.document.enabled = true
        #expect(store.enabledChanges == 2)
    }

    // MARK: Pencere genişliği

    @Test func inspectorColumnWidensTheWindowButNeverPastTheScreen() {
        let roomy = RootView.totalWidth(visibleWidth: 1710)
        #expect(roomy == RootView.windowWidth(visibleWidth: 1710) + RootView.inspectorWidth + 1)
        let small = RootView.totalWidth(visibleWidth: 1000)
        #expect(small <= 1000 - 2 * RootView.screenMargin)
    }
}

/// Sağ sütunun taşmaması ve kayması: akış düzeni önerilenden geniş rapor
/// etmez, ızgara ve döşemeler sütuna sığar, sütun önce pencereyi uzatır,
/// kaydırma yalnız seçim değişince başa döner.
struct InspectorFitTests {

    @Test func flowLayoutNeverReportsWiderThanItsRow() {
        // Küçülmeyen 336 pt'lik parça 308 pt'lik satırda: satır genişliği aşılmaz.
        let sizes = [CGSize(width: 60, height: 18), CGSize(width: 336, height: 18),
                     CGSize(width: 40, height: 18)]
        let placed = FlowLayout.place(sizes: sizes, width: 308, spacing: 4)
        #expect(placed.size.width <= 308)
        #expect(placed.origins[1] == CGPoint(x: 0, y: 22))
        #expect(placed.origins[2] == CGPoint(x: 0, y: 44))
        #expect(placed.size.height == 62)
        // Sığanlar aynı satırda kalır.
        let row = FlowLayout.place(sizes: [CGSize(width: 50, height: 10), CGSize(width: 50, height: 12)],
                                   width: 308, spacing: 4)
        #expect(row.origins[1] == CGPoint(x: 54, y: 0) && row.size == CGSize(width: 104, height: 12))
    }

    @Test func layoutGridFitsTheInspectorAndKeepsTheAspect() {
        for aspect in [1.33, 1.54, 1.78, 2.0, 2.37, 3.56] {
            let size = LayoutGrid.size(aspect: aspect)
            #expect(size.width <= RootView.inspectorBudget)
            #expect(abs(size.width / size.height - aspect) < 1e-6)
        }
        // Normal ekranda eski boy (170 pt yükseklik) değişmez.
        let normal = LayoutGrid.size(aspect: 1.6)
        #expect(abs(normal.width - 272) < 1e-6 && abs(normal.height - 170) < 1e-6)
        #expect(RootView.inspectorBudget + 32 + RootView.scrollerGutter == RootView.inspectorWidth)
    }

    @Test func customLayoutTileGetsAShortLabel() {
        #expect(BasicLayoutRow.shortLabel(.leftHalf) == WindowLayout.leftHalf.label)
        let odd = WindowLayout(x: 0.1, y: 0.1, w: 0.62, h: 0.57)
        #expect(BasicLayoutRow.shortLabel(odd) == L("Custom"))
        #expect(BasicLayoutRow.shortLabel(.anyFrame) == L("As it is"))
    }

    @Test func inspectorNeverChangesTheWindowHeight() {
        // Sağ sütunun uzunluğu pencereyi büyütmez; sütun kendi içinde kayar.
        let base = RootView.heights(chrome: 120, panel: 0, room: 1400, preferredTotal: 740)
        #expect(base.map == 620)
        #expect(RootView.heights(chrome: 120, panel: 0, room: 1000, preferredTotal: 740).map == 620)
    }

    @Test func scrollResetsOnlyWhenTheSubjectChanges() {
        func window(_ id: CGWindowID, _ title: String) -> Router.WindowSnapshot {
            Router.WindowSnapshot(id: id, pid: 1, appName: "A", bundleID: "a", title: title,
                                  placement: Router.Placement(screen: "s", desktop: 1),
                                  frame: .zero, isMinimized: false)
        }
        let a = PinDraft(window: window(1, "x"), target: Router.Placement(screen: "s", desktop: 1))
        var moved = a
        moved.target = Router.Placement(screen: "s", desktop: 2)
        moved.window = window(1, "y")
        let key = RootView.inspectorSubject
        #expect(key(false, .pin(a)) == key(false, .pin(moved)))
        #expect(key(false, .pin(a)) != key(false, .pin(PinDraft(window: window(2, "x"), target: a.target))))
        #expect(key(false, .rule("r1")) != key(false, .rule("r2")))
        #expect(key(true, .rule("r1")) == key(true, nil))
        #expect(key(false, nil) != key(false, .profile))
    }
}
