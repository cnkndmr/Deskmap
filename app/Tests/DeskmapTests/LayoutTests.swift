import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `WindowLayout` oranları ve `Coordinates` dönüşümleri.
struct LayoutTests {

    private let area = CGRect(x: 100, y: 50, width: 1000, height: 800)

    @Test func presetRectsInArea() {
        #expect(WindowLayout.full.rect(in: area) == area)
        #expect(WindowLayout.leftHalf.rect(in: area)
                == CGRect(x: 100, y: 50, width: 500, height: 800))
        #expect(WindowLayout.rightHalf.rect(in: area)
                == CGRect(x: 600, y: 50, width: 500, height: 800))
        #expect(WindowLayout.bottomHalf.rect(in: area)
                == CGRect(x: 100, y: 450, width: 1000, height: 400))
        #expect(WindowLayout.center.rect(in: area)
                == CGRect(x: 200, y: 130, width: 800, height: 640))
    }

    @Test func rectClampsToArea() {
        // Genişlik alanın dışına taşamaz; en az bir ızgara sütunu (1/24) kalır.
        let overflow = WindowLayout(x: 0.9, y: 0, w: 0.5, h: 1).rect(in: area)
        #expect(overflow.minX == 1000)
        #expect(abs(overflow.width - 100) < 1e-9)
        let tiny = WindowLayout(x: 0, y: 0, w: 0, h: -1).rect(in: area)
        #expect(abs(tiny.width - 1000.0 / 24) < 1e-9)
        #expect(abs(tiny.height - 800.0 / 24) < 1e-9)
        // Alanın tamamen dışındaki konum kenara kilitlenir.
        let outside = WindowLayout(x: 2, y: -1, w: 1, h: 1).rect(in: area)
        #expect(outside.minX == area.maxX)
        #expect(outside.minY == area.minY)
    }

    @Test func frameInitRoundTrips() {
        for preset in WindowLayout.presets {
            let rect = preset.rect(in: area)
            let back = WindowLayout(frame: rect, in: area)
            #expect(abs(back.x - preset.x) < 1e-9, "\(preset.label) x")
            #expect(abs(back.y - preset.y) < 1e-9, "\(preset.label) y")
            #expect(abs(back.w - preset.w) < 1e-9, "\(preset.label) w")
            #expect(abs(back.h - preset.h) < 1e-9, "\(preset.label) h")
        }
    }

    @Test func frameInitClamps() {
        // Alanın dışında ve alanın iki katı büyüklükte bir pencere.
        let frame = CGRect(x: -500, y: 5000, width: 3000, height: 10)
        let layout = WindowLayout(frame: frame, in: area)
        #expect(layout.x == 0)
        #expect(layout.y == 0.95)
        #expect(layout.w == 1)
        #expect(layout.h == 0.05)
    }

    @Test func frameInitWithZeroAreaFallsBackToFull() {
        let layout = WindowLayout(frame: CGRect(x: 10, y: 10, width: 100, height: 100),
                                  in: CGRect(x: 0, y: 0, width: 0, height: 800))
        #expect(layout == WindowLayout())
        #expect(layout == .full)
    }

    @Test func labels() {
        // Test sürecinde çeviri tablosu yok: İngilizce anahtar görünür.
        #expect(WindowLayout.full.label == "Full")
        #expect(WindowLayout.leftHalf.label == "Left half")
        #expect(WindowLayout.right30.label == "Right 30%")
        #expect(WindowLayout.center.label == "Center")
        #expect(WindowLayout(x: 0.2, y: 0.1, w: 0.6, h: 0.75).label == "60% × 75%")
    }

    // MARK: Coordinates

    private func screen(_ id: String, frame: CGRect) -> ScreenInfo {
        ScreenInfo(id: id, uuid: id.uppercased(), name: id, isBuiltin: id == "builtin",
                   frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20))
    }

    @Test func axRectFlipsYAgainstPrimaryScreen() {
        let primary = screen("builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let rect = CGRect(x: 10, y: 0, width: 100, height: 100)
        let ax = Coordinates.axRect(fromCocoa: rect, screens: [primary])
        #expect(ax == CGRect(x: 10, y: 980, width: 100, height: 100))
        // Birincil ekranın üst kenarı AX'te y = 0'dır.
        let top = CGRect(x: 0, y: 1030, width: 50, height: 50)
        #expect(Coordinates.axRect(fromCocoa: top, screens: [primary]).minY == 0)
    }

    @Test func axRectOnSecondaryScreenUsesPrimaryHeight() {
        let primary = screen("builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let external = screen("external", frame: CGRect(x: 1920, y: 200, width: 2560, height: 1440))
        // Birincil ekranın listede ikinci sırada olması sonucu değiştirmez.
        let rect = CGRect(x: 2000, y: 200, width: 800, height: 600)
        let ax = Coordinates.axRect(fromCocoa: rect, screens: [external, primary])
        #expect(ax == CGRect(x: 2000, y: 1080 - 800, width: 800, height: 600))
        // Yukarı uzanan harici ekranda AX y'si negatif olur.
        let high = CGRect(x: 2000, y: 1500, width: 100, height: 100)
        #expect(Coordinates.axRect(fromCocoa: high, screens: [primary, external]).minY == -520)
    }

    @Test func closeToleranceBoundary() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Coordinates.close(a, a.offsetBy(dx: 4, dy: -4)))
        #expect(Coordinates.close(a, CGRect(x: 0, y: 0, width: 104, height: 96)))
        #expect(!Coordinates.close(a, a.offsetBy(dx: 4.01, dy: 0)))
        #expect(!Coordinates.close(a, CGRect(x: 0, y: 0, width: 100, height: 105)))
        #expect(Coordinates.close(a, a.offsetBy(dx: 10, dy: 0), tolerance: 10))
    }
}

struct LayoutToolTests {

    private let area = CGRect(x: 0, y: 0, width: 5120, height: 1410)

    @Test func fixedSizeIsPlacedAtItsAnchorAndFittedToTheArea() {
        let fixed = WindowLayout(fixed: .init(width: 1400, height: 900, anchor: .center))
        #expect(fixed.rect(in: area) == CGRect(x: 1860, y: 255, width: 1400, height: 900))
        let corner = WindowLayout(fixed: .init(width: 1400, height: 900, anchor: .bottomRight))
        #expect(corner.rect(in: area) == CGRect(x: 3720, y: 510, width: 1400, height: 900))
        // Ekrandan büyük: alana sığdırılır.
        let huge = WindowLayout(fixed: .init(width: 9000, height: 3000, anchor: .topLeft))
        #expect(huge.rect(in: area) == area)
        // Önizleme ölçeği: 1 pt = 0,1 birim.
        let preview = CGRect(x: 0, y: 0, width: 512, height: 141)
        #expect(fixed.rect(in: preview, pointsPerUnit: 0.1).width == 140)
    }

    @Test func oldLayoutsDecodeWithoutFixedAndRoundTrip() throws {
        let old = try JSONDecoder().decode(WindowLayout.self,
                                           from: Data(#"{"x":0,"y":0,"w":0.5,"h":1}"#.utf8))
        #expect(old == .leftHalf && old.fixed == nil)
        let fixed = WindowLayout(fixed: .init(width: 1200, height: 800, anchor: .top))
        let back = try JSONDecoder().decode(WindowLayout.self, from: JSONEncoder().encode(fixed))
        #expect(back == fixed)
        // Oranlı düzen kodlanırken "fixed" anahtarı yazılmaz (eski sürümler okuyabilsin).
        let json = String(decoding: try JSONEncoder().encode(WindowLayout.leftHalf), as: UTF8.self)
        #expect(!json.contains("fixed"))
    }

    @Test func standardPresetsAreTheLaptopSet() {
        let presets = WindowLayout.standardPresets
        #expect(presets.contains(.topLeft) && presets.contains(.topHalf) && !presets.contains(.leftThird))
    }

    @Test func presetListsAreMirrorSymmetric() {
        func mirrored(_ l: WindowLayout) -> WindowLayout {
            WindowLayout(x: 1 - l.x - l.w, y: l.y, w: l.w, h: l.h)
        }
        func close(_ a: WindowLayout, _ b: WindowLayout) -> Bool {
            abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.w - b.w) < 1e-9 && abs(a.h - b.h) < 1e-9
        }
        let presets = WindowLayout.standardPresets
        for preset in presets {
            #expect(presets.contains { close($0, mirrored(preset)) }, "\(preset.label) has no mirror")
        }
    }

    @Test func gridIsFinerOnUltrawideAndSelectsCellRanges() {
        #expect(LayoutGrid.dimensions(aspect: 1.6) == (12, 8))
        #expect(LayoutGrid.dimensions(aspect: 3.56) == (24, 6))
        // 24 sütunda 8 sütun = üçte bir; ters yönde sürükleme de aynı alan.
        let third = LayoutGrid.layout(from: .init(col: 7, row: 5), to: .init(col: 0, row: 0),
                                      cols: 24, rows: 6)
        #expect(abs(third.w - 1.0 / 3) < 1e-9 && third.h == 1 && third.x == 0)
        let cell = LayoutGrid.cell(at: CGPoint(x: 999, y: -5), size: CGSize(width: 420, height: 118),
                                   cols: 24, rows: 6)
        #expect(cell == .init(col: 23, row: 0))
    }

    @Test func togglingFixedKeepsTheArea() {
        let size = CGSize(width: 1710, height: 1074)
        let on = LayoutEditor.toggledFixed(.center, on: true, screenSize: size)
        #expect(on.fixed == .init(width: 1370, height: 860, anchor: .center))
        let off = LayoutEditor.toggledFixed(on, on: false, screenSize: size)
        // Geri çevirince yuvarlama farkı içinde kalan hazır düzen geri gelir.
        #expect(off == .center)
        // Sabitleme noktası alanın dayandığı kenarlardan.
        #expect(LayoutEditor.toggledFixed(.topLeft, on: true, screenSize: size).fixed?.anchor == .topLeft)
        #expect(LayoutEditor.toggledFixed(.rightThird, on: true, screenSize: size).fixed?.anchor == .right)
        #expect(LayoutEditor.toggledFixed(.bottomHalf, on: true, screenSize: size).fixed?.anchor == .bottom)
        #expect(LayoutEditor.toggledFixed(.full, on: true, screenSize: size).fixed?.anchor == .center)
    }
}

struct BugFixTests {

    private let area = CGRect(x: 0, y: 0, width: 1710, height: 1074)

    @Test func refusedFixedSizeIsReanchoredWithTheRealSize() {
        let layout = WindowLayout(fixed: .init(width: 600, height: 400, anchor: .bottomRight))
        // Uygulama en az 900 × 700 kabul ediyor: yine sağ alt köşeye oturur.
        let frame = layout.reanchored(actualSize: CGSize(width: 900, height: 700), in: area)
        #expect(frame == CGRect(x: 810, y: 374, width: 900, height: 700))
    }

    @Test func refusedProportionalSizeIsPulledBackOntoTheScreen() {
        // Sağ %30 (hedef x = 1197, genişlik 513), uygulama en az 760 pt:
        // sağ kenara hizalanır, 247 pt taşmaz.
        let wide = CGSize(width: 760, height: 1074)
        #expect(WindowLayout.right30.refusesSize(wide, in: area))
        #expect(WindowLayout.right30.reanchored(actualSize: wide, in: area)
                == CGRect(x: 950, y: 0, width: 760, height: 1074))
        // Alt yarı, en küçük yükseklik 700: alt kenara hizalanır.
        #expect(WindowLayout.bottomHalf.reanchored(
            actualSize: CGSize(width: 1710, height: 700), in: area).origin == CGPoint(x: 0, y: 374))
        // Taşmayan pencere hedefin köşesinde kalır (büyük ya da küçük).
        #expect(WindowLayout.leftHalf.reanchored(
            actualSize: CGSize(width: 1000, height: 1074), in: area).origin == .zero)
        #expect(WindowLayout.bottomRight.reanchored(
            actualSize: CGSize(width: 400, height: 300), in: area).origin == CGPoint(x: 855, y: 537))
        // Alandan büyük pencere: sol üst köşe alanın içinde kalır.
        let shifted = CGRect(x: 1710, y: 25, width: 1000, height: 800)
        #expect(WindowLayout.right30.reanchored(
            actualSize: CGSize(width: 1200, height: 900), in: shifted).origin == shifted.origin)
    }

    @Test func refusedSizeIsKeptOnlyWhereARetryWouldJump() {
        // Sağ %30, reddi görülmüş 760 pt: içeri çekilmiş pencere (x = 950)
        // yeniden denenmez, hedef köşeye sıçratılmaz.
        let wide = CGSize(width: 760, height: 1074)
        let pulled = CGRect(origin: CGPoint(x: 950, y: 0), size: wide)
        #expect(WindowLayout.right30.holdsRefused(pulled, refused: wide, in: area))
        // Başka boyut ya da başka yer: kayıt tutmaz.
        #expect(!WindowLayout.right30.holdsRefused(
            pulled, refused: CGSize(width: 900, height: 1074), in: area))
        #expect(!WindowLayout.right30.holdsRefused(
            pulled.offsetBy(dx: -200, dy: 0), refused: wide, in: area))
        // Sol yarı, reddi görülmüş 1000 pt: köşe hedefle aynı, yeniden deneme
        // pencereyi oynatmaz; en küçük boyutu düşmüşse 855'e iner.
        let grown = CGRect(x: 0, y: 0, width: 1000, height: 1074)
        #expect(!WindowLayout.leftHalf.holdsRefused(grown, refused: grown.size, in: area))
        // Sabit boyutta kayıt köşe aynı olsa da tutar (bilinçli, b506257).
        let fixed = WindowLayout(fixed: .init(width: 600, height: 400, anchor: .topLeft))
        #expect(fixed.holdsRefused(CGRect(x: 0, y: 0, width: 900, height: 700),
                                   refused: CGSize(width: 900, height: 700), in: area))
    }

    @Test func manualMoveOverflowIsPulledBack() {
        // Elle taşıma: geniş ekranda sağ %30'daki pencere dahili ekrana
        // oranlarıyla gelir (x = 1197, genişlik 513); uygulama 760'ta kalır.
        let layout = WindowLayout(frame: CGRect(x: 1792, y: 0, width: 768, height: 1074),
                                  in: CGRect(x: 0, y: 0, width: 2560, height: 1074))
        let kept = CGRect(x: 1197, y: 0, width: 760, height: 1074)
        #expect(layout.overflowFix(for: kept, in: area)
                == CGRect(x: 950, y: 0, width: 760, height: 1074))
        // Boyut kabul edildi ya da küçük kaldı: dokunulmaz.
        #expect(layout.overflowFix(for: layout.rect(in: area), in: area) == nil)
        #expect(layout.overflowFix(
            for: CGRect(x: 1197, y: 0, width: 400, height: 900), in: area) == nil)
        // Köşesi hedefte olmayan okuma bayat: eski boyutla çerçeve verilmez.
        #expect(layout.overflowFix(
            for: CGRect(x: 1792, y: 0, width: 768, height: 1074), in: area) == nil)
    }

    @Test func fixedLayoutsCarryAProportionalFallbackForOlderVersions() {
        let layout = WindowLayout(fixed: .init(width: 855, height: 1074, anchor: .left),
                                  screenSize: area.size)
        #expect(abs(layout.w - 0.5) < 1e-9 && layout.h == 1 && layout.x == 0)
        // Yerleşim yine sabit boyuttan.
        #expect(layout.rect(in: area).width == 855)
    }

    @Test func useCurrentSizeKeepsFixedLayoutsFixed() {
        let stored = WindowLayout(fixed: .init(width: 1000, height: 600, anchor: .center))
        let there = stored.rect(in: area)
        #expect(Router.WindowSnapshot.fixedLayout(frame: there, stored: stored, area: area) == stored)
        let moved = CGRect(x: 0, y: 0, width: 800, height: 500)
        let saved = Router.WindowSnapshot.fixedLayout(frame: moved, stored: stored, area: area)
        #expect(saved.fixed == .init(width: 800, height: 500, anchor: .topLeft))
        // Sabitleme köşesi yerinde kalıp büyütülen pencere: yeni boyut kaydedilir.
        let corner = WindowLayout(fixed: .init(width: 800, height: 600, anchor: .topLeft))
        let grown = Router.WindowSnapshot.fixedLayout(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 700), stored: corner, area: area)
        #expect(grown.fixed == .init(width: 1000, height: 700, anchor: .topLeft))
        // Hiçbir kenara dayanmayan pencere: kayıtlı sabitleme korunur.
        let right = WindowLayout(fixed: .init(width: 800, height: 600, anchor: .right))
        let floating = Router.WindowSnapshot.fixedLayout(
            frame: CGRect(x: 300, y: 200, width: 700, height: 500), stored: right, area: area)
        #expect(floating.fixed?.anchor == .right)
    }

    @Test func onlyALargerSizeCountsAsRefused() {
        let layout = WindowLayout(fixed: .init(width: 600, height: 400, anchor: .center))
        #expect(layout.refusesSize(CGSize(width: 900, height: 700), in: area))
        // Küçük okuma: henüz uygulanmadı (animasyon), reddedilmiş sayılmaz.
        #expect(!layout.refusesSize(CGSize(width: 300, height: 200), in: area))
        #expect(!layout.refusesSize(CGSize(width: 600, height: 400), in: area))
        // Oranlı düzende ölçü hedef dikdörtgen (sol yarı 855 × 1074).
        #expect(!WindowLayout.leftHalf.refusesSize(CGSize(width: 900, height: 700), in: area))
        #expect(WindowLayout.leftHalf.refusesSize(CGSize(width: 900, height: 1074), in: area))
        #expect(!WindowLayout.leftHalf.refusesSize(CGSize(width: 855, height: 1074), in: area))
    }

    @Test func unknownScreenKeepsTheProportionsWhenEditingFixed() {
        var layout = WindowLayout.leftThird
        layout.fixed = .init(width: 1200, height: 800, anchor: .left)
        let edited = layout.withFixed(.init(width: 1300, height: 800, anchor: .left), screenSize: nil)
        #expect(edited.x == layout.x && edited.w == layout.w && edited.fixed?.width == 1300)
    }

    @Test func olderFilesGetAProportionalFallbackForFixedSizes() {
        let screen = KnownScreen(id: "builtin", name: "B", aspect: 1.6,
                                 visibleWidth: 1710, visibleHeight: 1074)
        let rule = Rule(id: "r", appName: "A", bundleID: "a", tokens: [],
                        docked: Destination(screen: "builtin", desktop: 1,
                                            layout: WindowLayout(fixed: .init(width: 855, height: 1074,
                                                                              anchor: .left))))
        let filled = Document.backfillingFixed([rule], screens: [screen])
        #expect(abs((filled[0].docked?.layout.w ?? 0) - 0.5) < 1e-9)
    }

    @Test func emptyUnassignedTextSaysWhy() {
        let placed = Router.Placement(screen: "builtin", desktop: 1)
        var full = Router.WindowSnapshot(id: 1, pid: 1, appName: "v", bundleID: "v", title: "t",
                                         placement: placed, frame: nil, isMinimized: false)
        full.fullscreen = Router.FullscreenSlot(screen: "builtin", space: 9, afterDesktop: 1, order: 0)
        #expect(UnownedWindowsTray.emptyText(trusted: false, windows: [], rules: [], sessionPins: [:])
                == L("Windows are not listed yet."))
        #expect(UnownedWindowsTray.emptyText(trusted: true, windows: [], rules: [], sessionPins: [:])
                == L("No open windows."))
        #expect(UnownedWindowsTray.emptyText(trusted: true, windows: [full], rules: [], sessionPins: [:])
                == L("Full-screen windows without a pin are left alone."))
    }

    @Test func fixedToggleKeepsEdgeToEdgeSizesExactAndHalvesApart() {
        let size = area.size
        let full = LayoutEditor.toggledFixed(.full, on: true, screenSize: size)
        #expect(full.fixed?.width == 1710 && full.fixed?.height == 1074)
        let left = LayoutEditor.toggledFixed(.leftHalf, on: true, screenSize: size)
        let right = LayoutEditor.toggledFixed(.rightHalf, on: true, screenSize: size)
        #expect((left.fixed?.width ?? 0) + (right.fixed?.width ?? 0) <= 1710)
        // Geri çevirince hazır düzenin kendisi (10 pt'lik yuvarlamaya rağmen).
        for preset in [WindowLayout.full, .leftHalf, .rightHalf, .topHalf, .center, .left70] {
            let back = LayoutEditor.toggledFixed(
                LayoutEditor.toggledFixed(preset, on: true, screenSize: size), on: false, screenSize: size)
            #expect(back == preset, "\(preset.label)")
        }
        // Ultra geniş ekranda da aynı (laptop) set: %70 geri gelir.
        let wide = CGSize(width: 5120, height: 1410)
        let seventy = LayoutEditor.toggledFixed(
            LayoutEditor.toggledFixed(.left70, on: true, screenSize: wide), on: false, screenSize: wide)
        #expect(seventy == .left70)
    }

    /// Kapatınca kitaplıktaki yakın giriş de geri gelir: kullanıcının düzeni
    /// adını ve döşemesini korur (yerleşik listede karşılığı yok).
    @Test func fixedToggleSnapsBackToLibraryEntry() throws {
        let size = area.size
        let code = WindowLayout(x: 0, y: 0, w: 5.0 / 12, h: 1)
        var library = LayoutLibrary.defaults
        let added = library.add(code, name: "Code", list: .basic)
        let id = try #require(added)
        let on = LayoutEditor.toggledFixed(code, on: true, screenSize: size, library: library)
        #expect(on.fixed != nil)
        let back = LayoutEditor.toggledFixed(on, on: false, screenSize: size, library: library)
        #expect(back == code)
        #expect(library.label(for: back) == "Code")
        #expect(library.entry(matching: back)?.id == id)
        // Kitaplıksız yalnız yuvarlanmış oran kalır.
        #expect(LayoutEditor.toggledFixed(on, on: false, screenSize: size) != code)
    }

    @Test func editingOneMarginKeepsTheOtherEdgesExact() {
        let third = WindowLayout.centerThird
        let edited = LayoutEditor.settingMargin(\.top, to: 10, of: third)
        #expect(edited.x == third.x && edited.w == third.w)
        #expect(abs(edited.y - 0.1) < 1e-9 && abs(edited.h - 0.9) < 1e-9)
    }

    @MainActor @Test func autoScrollArmsOnlyAfterLeavingTheEdgeBand() {
        let scroller = AutoScroller()
        let viewport = CGRect(x: 0, y: 0, width: 600, height: 500)
        scroller.update(point: CGPoint(x: 300, y: 5), viewport: viewport)      // bantta başladı
        #expect(!scroller.armed)
        scroller.update(point: CGPoint(x: 300, y: 250), viewport: viewport)    // ortaya çıktı
        #expect(scroller.armed)
        scroller.update(point: nil, viewport: viewport)                        // sürükleme bitti
        #expect(!scroller.armed)
    }
}
