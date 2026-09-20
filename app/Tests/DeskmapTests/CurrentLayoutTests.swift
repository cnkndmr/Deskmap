import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// "Şu anki boyutu ve konumu kullan": pencerenin gerçek çerçevesinden
/// düzen okuma (`WindowSnapshot.currentLayout`) ve Store üzerinden geri
/// alınabilir kayıt (`Store.saveLayout`).
struct CurrentLayoutTests {

    private func screen(_ id: String, frame: CGRect) -> ScreenInfo {
        ScreenInfo(id: id, uuid: id.uppercased(), name: id, isBuiltin: id == "builtin",
                   frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20))
    }

    private func window(_ id: CGWindowID = 7, placement: Router.Placement?,
                        frame: CGRect?) -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: "Code", bundleID: "com.microsoft.VSCode",
                              title: "A", placement: placement, frame: frame, isMinimized: false)
    }

    private let builtin = CGRect(x: 0, y: 0, width: 1000, height: 800)

    // MARK: Ölçü okuma

    /// Çerçeve, bulunduğu ekranın kullanılabilir alanına oranlanır; alan
    /// Cocoa'dan AX'e (üst kenar y = 0) çevrilir.
    @Test func layoutIsReadAgainstUsableAreaOfWindowsScreen() throws {
        let screens = [screen("builtin", frame: builtin)]
        // visibleFrame: y 20..780 (Cocoa) → AX'te y 20..780, yükseklik 760.
        // Pencere AX: x 100, y 20 + 76 (alanın %10'u), 500 × 380.
        let frame = CGRect(x: 100, y: 96, width: 500, height: 380)
        let layout = try #require(window(placement: Router.Placement(screen: "builtin", desktop: 1),
                                         frame: frame).currentLayout(screens: screens))
        #expect(abs(layout.x - 0.1) < 1e-9)
        #expect(abs(layout.y - 0.1) < 1e-9)
        #expect(abs(layout.w - 0.5) < 1e-9)
        #expect(abs(layout.h - 0.5) < 1e-9)
    }

    /// Pencere ikinci ekrandaysa oranlar o ekranın alanına göredir; birinci
    /// ekrana göre değil.
    @Test func layoutUsesSecondaryScreenArea() throws {
        let external = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let screens = [screen("builtin", frame: builtin), screen("external", frame: external)]
        // external visibleFrame Cocoa: x 1000..3000, y 20..980 → AX y: 800-980=-180 .. 780.
        let area = Coordinates.axRect(fromCocoa: screens[1].visibleFrame, screens: screens)
        let frame = CGRect(x: area.minX + area.width / 2, y: area.minY,
                           width: area.width / 2, height: area.height)
        let layout = try #require(window(placement: Router.Placement(screen: "external", desktop: 3),
                                         frame: frame).currentLayout(screens: screens))
        #expect(layout == .rightHalf)
    }

    /// Yeri bilinmeyen pencere (tam ekran / taranmamış) yedek ekranla ölçülür;
    /// yedek de yoksa nil.
    @Test func fallbackScreenIsUsedWhenPlacementIsUnknown() {
        let screens = [screen("builtin", frame: builtin)]
        let frame = CGRect(x: 0, y: 20, width: 1000, height: 760)
        #expect(window(placement: nil, frame: frame)
                    .currentLayout(screens: screens, fallbackScreen: "builtin") == .full)
        #expect(window(placement: nil, frame: frame).currentLayout(screens: screens) == nil)
    }

    /// Çerçevesi olmayan pencere ya da listede olmayan ekran: ölçü yok.
    @Test func layoutIsNilWithoutFrameOrScreen() {
        let screens = [screen("builtin", frame: builtin)]
        let placed = Router.Placement(screen: "builtin", desktop: 1)
        #expect(window(placement: placed, frame: nil).currentLayout(screens: screens) == nil)
        #expect(window(placement: Router.Placement(screen: "external", desktop: 1),
                       frame: CGRect(x: 0, y: 0, width: 10, height: 10))
                    .currentLayout(screens: screens) == nil)
    }

    // MARK: Motor: yakalanan düzen aynı yere uygulanır

    /// "Şu anki boyutu kullan" ile okunan düzen, motor tarafından aynı
    /// çerçeveye uygulanmalı (gidiş-dönüş). Eskiden hedef Cocoa alanında
    /// hesaplanıp çevriliyordu ve dikey eksen ters dönüyordu: üstteki pencere
    /// alta iniyordu.
    @Test func targetFrameRoundTripsCapturedLayout() throws {
        let external = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let screens = [screen("builtin", frame: builtin), screen("external", frame: external)]
        for (screenID, frame) in [
            ("builtin", CGRect(x: 100, y: 96, width: 500, height: 380)),
            ("builtin", CGRect(x: 0, y: 20, width: 700, height: 300)),
            ("external", CGRect(x: 1200, y: -100, width: 800, height: 500)),
        ] {
            let info = try #require(screens.first { $0.id == screenID })
            let layout = try #require(window(placement: Router.Placement(screen: screenID, desktop: 1),
                                             frame: frame).currentLayout(screens: screens))
            let applied = Router.targetFrame(for: layout, on: info, screens: screens)
            #expect(abs(applied.minX - frame.minX) < 1e-6, "\(screenID) x")
            #expect(abs(applied.minY - frame.minY) < 1e-6, "\(screenID) y")
            #expect(abs(applied.width - frame.width) < 1e-6, "\(screenID) w")
            #expect(abs(applied.height - frame.height) < 1e-6, "\(screenID) h")
        }
    }

    /// "Üst yarı" kullanılabilir alanın üstüne, "Alt yarı" altına oturur
    /// (AX'te üst kenar y = 0).
    @Test func topAndBottomHalvesLandOnTheRightEdge() {
        let screens = [screen("builtin", frame: builtin)]
        let area = Coordinates.axRect(fromCocoa: screens[0].visibleFrame, screens: screens)
        let top = Router.targetFrame(for: .topHalf, on: screens[0], screens: screens)
        let bottom = Router.targetFrame(for: .bottomHalf, on: screens[0], screens: screens)
        #expect(top.minY == area.minY)
        #expect(bottom.maxY == area.maxY)
        #expect(top.maxY == bottom.minY)
    }

    // MARK: Store: geri alınabilir kayıt

    private let external2 = Destination(screen: "external", desktop: 2, layout: .leftHalf)

    /// Kayıt yalnızca düzeni değiştirir, ekran ve masaüstü kalır; geri alma
    /// eski düzeni getirir; etkisiz çağrı geri alma kaydı bırakmaz.
    @MainActor @Test func saveLayoutIsUndoableAndKeepsTarget() {
        let rule = Rule(id: "r", appName: "Code", bundleID: "com.microsoft.VSCode", tokens: ["A"],
                        docked: external2, undocked: nil)
        var document = Document()
        document.rules = [rule]
        let store = Store(demo: document)
        let layout = WindowLayout(x: 0.25, y: 0, w: 0.5, h: 1)

        #expect(store.saveLayout(layout, for: "r", mode: .docked))
        #expect(store.rule("r")?.docked == Destination(screen: "external", desktop: 2, layout: layout))
        #expect(store.rule("r")?.undocked == nil)
        #expect(store.undoBuffer.entry?.label == "Layout saved")

        store.undo()
        #expect(store.rule("r")?.docked == external2)
        #expect(store.undoBuffer.isEmpty)

        // Aynı düzeni yeniden kaydetmek etkisizdir: kayıt yok.
        #expect(!store.saveLayout(.leftHalf, for: "r", mode: .docked))
        #expect(store.undoBuffer.isEmpty)
        // Bu modda hedefi olmayan kural: dokunulmaz.
        #expect(!store.saveLayout(layout, for: "r", mode: .undocked))
        #expect(store.rule("r")?.undocked == nil)
    }
}
