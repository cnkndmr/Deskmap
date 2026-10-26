import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Router'ın şimdiye dek hiç çalışmamış saf yardımcıları ve demo
/// Router'da (AX/SkyLight yok, disk yazımı yok) yürüyen durum geçişleri:
/// bekleyen silme kuyruğu, ekran başına masaüstü listesi, masaüstü
/// sıralaması/ekranlar arası taşımada oturum pinlerinin kayması, serbest
/// hareket izninin verilmediği durumlar, "Son hareketler" günlüğü.
@MainActor
struct RouterCoverageTests {

    private let bundle = "com.example.editor"

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Editor", bundleID: bundle, tokens: tokens, docked: destination)
    }

    /// İki pencereli bir dünya: 1 "Alpha notes", 2 "Beta draft"; kural yok.
    private func world() -> RouterHarness {
        let sim = RouterHarness(rules: [])
        sim.appName = "Editor"
        sim.bundleID = bundle
        sim.titles = [1: "Alpha notes", 2: "Beta draft"]
        _ = sim.sweep()
        return sim
    }

    private func screen(_ id: String, uuid: String) -> ScreenInfo {
        ScreenInfo(id: id, uuid: uuid, name: id, isBuiltin: id == "builtin",
                   frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                   visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780))
    }

    private func space(_ id: UInt64, fullscreen: Bool = false) -> SkyLight.Space {
        SkyLight.Space(id: id, type: fullscreen ? 4 : 0)
    }

    // MARK: - Bekleyen silme kuyruğu (saf)

    /// Kimliği bilinen silmeler hep `all`'a, yalnız etkin kurulumunkiler
    /// `active`'e girer; kimliksiz silme ekranı "çözülmemiş" sayılır. Boş
    /// liste hiçbir kümeye bir şey eklemez.
    @Test func pendingQueueSplitsByModeAndResolution() {
        let docked = Document.planKey(mode: .docked, screen: "external")
        let undocked = Document.planKey(mode: .undocked, screen: "builtin")
        let empty = Document.planKey(mode: .docked, screen: "external-2")
        let queue = Router.pendingQueue([
            docked: [PendingRemoval(desktop: 2, space: 11), PendingRemoval(desktop: 4, space: nil)],
            undocked: [PendingRemoval(desktop: 3, space: 22)],
            empty: [],
        ], mode: .docked)
        #expect(queue.all == [11, 22])
        #expect(queue.active == [11])
        #expect(queue.unresolved == ["external"])
    }

    /// Mod öneki okunamayan (bozuk) anahtar: kimlikli silme yine `all`'da
    /// (başka kurulumun masaüstü yanlışlıkla silinmesin diye etkin değil);
    /// kimliksiz olanın ekranı ham anahtarla bildirilir.
    @Test func pendingQueueWithMalformedKeyIsNeverActive() {
        let queue = Router.pendingQueue([
            "garbage": [PendingRemoval(desktop: 1, space: 7), PendingRemoval(desktop: 2, space: nil)],
        ], mode: .docked)
        #expect(queue.all == [7])
        #expect(queue.active.isEmpty)
        #expect(queue.unresolved == ["garbage"])
    }

    // MARK: - Okunmuş ekran listesi (saf)

    /// Ekran başına yalnız normal masaüstüler sayılır (tam ekran space
    /// masaüstü değildir); bağlı olmayan ekranın listesi atlanır.
    @Test func desktopSpacesAndCountsSkipFullscreenAndUnknownDisplays() {
        let screens = [screen("builtin", uuid: "B"), screen("external", uuid: "E")]
        let displays = [
            SkyLight.DisplaySpaces(displayUUID: "B", current: 1,
                                   spaces: [space(1), space(90, fullscreen: true), space(2)]),
            SkyLight.DisplaySpaces(displayUUID: "E", current: 5, spaces: [space(5)]),
            SkyLight.DisplaySpaces(displayUUID: "GONE", current: 8, spaces: [space(8), space(9)]),
        ]
        #expect(Router.desktopSpaces(displays: displays, screens: screens)
                == ["builtin": [1, 2], "external": [5]])
        #expect(Router.desktopCounts(displays: displays, screens: screens)
                == ["builtin": 2, "external": 1])
        #expect(Router.desktopSpaces(displays: [], screens: screens).isEmpty)
    }

    // MARK: - Oturum pinleri ve masaüstü sıralaması

    /// Masaüstü 1 → 3'e sürüklenince aynı ekrandaki oturum pinleri kurallarla
    /// aynı haritaya göre kayar (2 → 1, 3 → 2); başka ekrandaki pin yerinde kalır.
    @Test func reorderShiftsSessionPinsOnThatScreenOnly() {
        let sim = world()
        sim.pin(1, Destination(screen: "external", desktop: 3))
        sim.pin(2, Destination(screen: "builtin", desktop: 3))
        let changed = sim.router.moveDesktop(on: "external", from: 1, to: 3, count: 3)
        #expect(changed)
        #expect(sim.router.sessionPins[1]?.desktop == 2)
        #expect(sim.router.sessionPins[1]?.screen == "external")
        #expect(sim.router.sessionPins[2] == Destination(screen: "builtin", desktop: 3))
    }

    /// Sıralamayı değiştirmeyen (aynı yere ya da geçersiz numaraya)
    /// sürükleme hiçbir pini oynatmaz ve "değişti" demez (geri alma kaydı yok).
    @Test func noOpReorderLeavesPinsAlone() {
        let sim = world()
        sim.pin(1, Destination(screen: "external", desktop: 2))
        #expect(!sim.router.moveDesktop(on: "external", from: 2, to: 2, count: 3))
        #expect(!sim.router.moveDesktop(on: "external", from: 0, to: 2, count: 3))
        // Pinli masaüstüne dokunmayan sıralama (3 ↔ 4) da pini oynatmaz.
        #expect(!sim.router.moveDesktop(on: "external", from: 3, to: 4, count: 4))
        #expect(sim.router.sessionPins[1]?.desktop == 2)
    }

    /// Ekranlar arası taşıma: taşınan masaüstündeki pin hedef ekrana gider,
    /// kaynakta sonraki masaüstülerin pinleri bir sola kayar; hedefte
    /// eklenen yerden sonrakiler bir sağa kayar.
    @Test func acrossMoveRewritesSessionPinsOnBothScreens() {
        let sim = world()
        sim.titles[3] = "Gamma log"
        sim.titles[4] = "Delta sheet"
        _ = sim.sweep()
        sim.pin(1, Destination(screen: "builtin", desktop: 2))   // taşınan
        sim.pin(2, Destination(screen: "builtin", desktop: 3))   // kaynakta sonra
        sim.pin(3, Destination(screen: "external", desktop: 1))  // hedefte önce
        sim.pin(4, Destination(screen: "external", desktop: 2))  // hedefte eklenen yer
        let changed = sim.router.moveDesktopAcross(from: "builtin", desktop: 2,
                                                   to: "external", at: 2)
        #expect(changed)
        let pins = sim.router.sessionPins
        #expect(pins[1].map { [$0.screen: $0.desktop] } == ["external": 2])
        #expect(pins[2].map { [$0.screen: $0.desktop] } == ["builtin": 2])
        #expect(pins[3].map { [$0.screen: $0.desktop] } == ["external": 1])
        #expect(pins[4].map { [$0.screen: $0.desktop] } == ["external": 3])
    }

    /// Aynı ekrana "ekranlar arası" taşıma anlamsız: hiçbir şey değişmez.
    @Test func acrossMoveToSameScreenIsRejected() {
        let sim = world()
        sim.pin(1, Destination(screen: "builtin", desktop: 2))
        #expect(!sim.router.moveDesktopAcross(from: "builtin", desktop: 1, to: "builtin", at: 2))
        #expect(sim.router.sessionPins[1]?.desktop == 2)
        // Pinsiz yerlere dokunan taşıma da "değişmedi" der.
        #expect(!sim.router.moveDesktopAcross(from: "external", desktop: 4, to: "builtin", at: 5))
    }

    /// Pencere sıralaması yalnız istenirse ve iki uç da gerçek masaüstüyse;
    /// aksi hâlde belge adların bağlarını çevirmez (nil).
    @Test func reorderedSpacesOnlyWhenWindowsReallyMove() {
        let sim = world()
        sim.router.replaceDemoDesktopCounts(["external": 2])
        #expect(sim.router.reorderedSpaces(on: "external", from: 1, to: 2,
                                           reorderWindows: false) == nil)
        // 3. masaüstü gerçekte yok: pencere taşınmaz.
        #expect(sim.router.reorderedSpaces(on: "external", from: 1, to: 3,
                                           reorderWindows: true) == nil)
    }

    // MARK: - Oturum pini kenar durumları

    /// Pinsiz pencerenin pinini kaldırmak hiçbir şey yapmaz: bağ yazılmaz,
    /// pencere genel kurala açık kalır.
    @Test func unpinningAnUnpinnedWindowIsANoOp() {
        let sim = RouterHarness(rules: [rule("main", ["Alpha"], Destination(screen: "external", desktop: 2))])
        sim.appName = "Editor"
        sim.bundleID = bundle
        sim.titles = [1: "Alpha notes"]
        _ = sim.sweep()
        let before = sim.bindings
        sim.unpin(1)
        #expect(sim.bindings == before)
        #expect(sim.router.sessionPins.isEmpty)
    }

    /// Adlı masaüstüne geçici pin adı izler: hedef numaraya
    /// dönüştürülmeden, adıyla saklanır.
    @Test func namedSessionPinKeepsItsName() {
        let sim = world()
        let named = Destination(screen: "external", desktop: 4, nameID: "name-x")
        sim.pin(1, named)
        #expect(sim.router.sessionPins[1] == named)
    }

    // MARK: - Serbest hareket: izin verilmeyen durumlar

    /// Süre sıfır ya da negatifse, pencere açık değilse ya da pencerenin
    /// pini yoksa izin verilmez (motor onu zaten taşımıyor).
    @Test func freeMoveIsNotGrantedWithoutDurationWindowOrPin() {
        let sim = RouterHarness(rules: [rule("main", ["Alpha"], Destination(screen: "external", desktop: 2))])
        sim.appName = "Editor"
        sim.bundleID = bundle
        sim.titles = [1: "Alpha notes", 2: "Unrelated"]
        _ = sim.sweep()
        sim.router.allowFreeMove([1], for: 0)
        sim.router.allowFreeMove([1], for: -60)
        #expect(sim.router.freeMoves.isEmpty)
        sim.router.allowFreeMove([99], for: 60)       // açık değil
        sim.router.allowFreeMove([2], for: 60)        // pini yok
        #expect(sim.router.freeMoves.isEmpty)
        sim.router.allowFreeMove([1, 2, 99], for: 60) // yalnız pinli olana
        #expect(Set(sim.router.freeMoves.keys) == [1])
    }

    /// Süresi dolmuş izin uzatılmaz; elle bitirme yalnız izni olanı etkiler.
    @Test func expiredGrantIsNotExtendedAndEndIsSelective() {
        let sim = RouterHarness(rules: [rule("main", ["Alpha"], Destination(screen: "external", desktop: 2))])
        sim.appName = "Editor"
        sim.bundleID = bundle
        sim.titles = [1: "Alpha notes", 2: "Alpha two"]
        _ = sim.sweep()
        sim.router.allowFreeMove([1, 2], for: 3600)
        sim.router.endFreeMove([2, 77])
        #expect(Set(sim.router.freeMoves.keys) == [1])
        sim.router.extendFreeMove([2], by: 300)       // izni yok: yeni izin değil
        #expect(sim.router.freeMoves[2] == nil)
    }

    // MARK: - Son hareketler

    /// Boş liste günlüğe satır eklemez; aynı turdaki taşımaların sonuncusu
    /// en üstte, günlük sınırda kırpılır.
    @Test func actionLogNewestFirstAndCapped() {
        let sim = world()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        sim.router.recordActions([], at: t0)
        #expect(sim.router.actionLog.isEmpty)
        sim.router.recordActions(["A → D1", "B → D2"], at: t0)
        #expect(sim.router.actionLog.map(\.text) == ["B → D2", "A → D1"])
        let many = (0..<(Router.actionLogLimit + 5)).map { "W\($0)" }
        sim.router.recordActions(many, at: t0.addingTimeInterval(1))
        #expect(sim.router.actionLog.count == Router.actionLogLimit)
        #expect(sim.router.actionLog.first?.text == "W\(Router.actionLogLimit + 4)")
    }

    // MARK: - Shots (demo) yardımcıları

    /// Demo Router'da pencere listesi ve masaüstü sayıları dışarıdan
    /// değiştirilebilir (Shots dizisi); tarama yapılmaz.
    @Test func demoReplacementsTakeEffect() {
        let sim = world()
        let snapshot = Router.WindowSnapshot(id: 42, pid: 1, appName: "Editor", bundleID: bundle,
                                             title: "Moved", placement: nil, frame: nil,
                                             isMinimized: false)
        sim.router.replaceDemoWindows([snapshot])
        #expect(sim.router.windows.map(\.id) == [42])
        sim.router.replaceDemoDesktopCounts(["builtin": 3])
        #expect(sim.router.desktopCounts == ["builtin": 3])
        sim.router.setMapVisible(true)   // demo: tarama yok, liste değişmez
        #expect(sim.router.windows.map(\.id) == [42])
    }

    /// Fiziksel olarak bağlı olmayan ekranda masaüstü eklenemez/silinemez
    /// (Mission Control'e gidilmez); pinler kaymaz.
    @Test func desktopOpsOnUnconnectedScreenFailWithoutShiftingPins() async {
        let sim = world()
        sim.pin(1, Destination(screen: "external", desktop: 3))
        #expect(await sim.router.addDesktop(on: "no-such-screen") == false)
        #expect(await sim.router.removeDesktop(on: "no-such-screen", desktop: 1) == false)
        #expect(sim.router.sessionPins[1]?.desktop == 3)
    }
}
