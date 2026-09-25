import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Motorun saf yardımcıları: yanıt vermeyen uygulama kararı, pencere
/// sunucusu kaydı süzgeci, masaüstü taşıma soğuması, harici ekran
/// sıralaması, space türü haritası. Hiçbiri pencerelere, SkyLight'a ya da
/// diske dokunmaz.
struct EngineHelperTests {

    // MARK: Accessibility sabitleri

    @Test func trustedCheckOptionPromptMatchesSystemConstant() {
        // Sıkı eşzamanlılık için C genelinin yerine yazılan sabit aynı anahtar.
        #expect(AX.trustedCheckOptionPrompt
                == kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String)
    }

    // MARK: Backoff kararı

    @Test func backoffThresholdsUnchanged() {
        #expect(AX.slowCallThreshold == 0.5)
        #expect(AX.slowTotalThreshold == 4)
    }

    @Test func singleSlowCallMarksUnresponsive() {
        // Donmuş uygulama ilk çağrıda 1 sn zaman aşımına takılır.
        #expect(AX.isUnresponsive(maxSingleCall: 1.0, total: 1.0))
        #expect(AX.isUnresponsive(maxSingleCall: 0.5, total: 0.5))
        #expect(!AX.isUnresponsive(maxSingleCall: 0.49, total: 0.49))
    }

    @Test func busyButResponsiveAppIsNotUnresponsive() {
        // Çok pencereli Electron/tarayıcı: toplam 2 sn ama tek çağrı kısa.
        #expect(!AX.isUnresponsive(maxSingleCall: 0.05, total: 2.0))
        #expect(!AX.isUnresponsive(maxSingleCall: 0.2, total: 3.99))
    }

    @Test func totalSafetyNetStillApplies() {
        #expect(AX.isUnresponsive(maxSingleCall: 0.01, total: 4.0))
        #expect(AX.isUnresponsive(maxSingleCall: 0.01, total: 12))
        #expect(!AX.isUnresponsive(maxSingleCall: 0, total: 0))
    }

    @Test func appTimingTracksTotalAndMax() {
        var timing = AX.AppTiming()
        let a: Int = timing.measure { 1 }
        let b: String = timing.measure { "x" }
        #expect(a == 1 && b == "x")
        #expect(timing.total >= 0)
        #expect(timing.maxCall <= timing.total)
    }

    // MARK: Pencere sunucusu kaydı süzgeci

    /// `CGWindowListCopyWindowInfo` kaydının taklidi; sayılar gerçekte
    /// olduğu gibi `NSNumber`. nil verilen anahtar kayıtta bulunmaz.
    private func serverEntry(
        number: UInt32? = 7, pid: Int32? = 42, layer: Int? = 0, alpha: Double? = 1,
        bounds: (width: Double, height: Double)? = (800, 600), name: String? = "Belge"
    ) -> [String: Any] {
        var entry: [String: Any] = [:]
        if let number { entry[kCGWindowNumber as String] = NSNumber(value: number) }
        if let pid { entry[kCGWindowOwnerPID as String] = NSNumber(value: pid) }
        if let layer { entry[kCGWindowLayer as String] = NSNumber(value: layer) }
        if let alpha { entry[kCGWindowAlpha as String] = NSNumber(value: alpha) }
        if let bounds {
            entry[kCGWindowBounds as String] = [
                "X": NSNumber(value: 0), "Y": NSNumber(value: 0),
                "Width": NSNumber(value: bounds.width), "Height": NSNumber(value: bounds.height),
            ] as [String: Any]
        }
        if let name { entry[kCGWindowName as String] = name }
        return entry
    }

    @Test func standardServerEntryIsLiveAndListed() {
        let entry = serverEntry()
        let live = AX.liveEntry(from: entry)
        #expect(live?.id == 7 && live?.pid == 42)
        let window = AX.serverWindow(from: entry)
        #expect(window?.id == 7)
        #expect(window?.pid == 42)
        #expect(window?.name == "Belge")
    }

    @Test func nonZeroOrMissingLayerIsLiveButNotListed() {
        for entry in [serverEntry(layer: 25), serverEntry(layer: -1), serverEntry(layer: nil)] {
            #expect(AX.liveEntry(from: entry) != nil)
            #expect(AX.serverWindow(from: entry) == nil)
        }
    }

    @Test func transparentWindowIsNotListedButMissingAlphaIs() {
        #expect(AX.serverWindow(from: serverEntry(alpha: 0)) == nil)
        #expect(AX.liveEntry(from: serverEntry(alpha: 0)) != nil)
        #expect(AX.serverWindow(from: serverEntry(alpha: 0.01)) != nil)
        #expect(AX.serverWindow(from: serverEntry(alpha: nil)) != nil)
    }

    @Test func tinyWindowIsNotListedButMissingBoundsIs() {
        #expect(AX.serverWindow(from: serverEntry(bounds: (49, 600))) == nil)
        #expect(AX.serverWindow(from: serverEntry(bounds: (800, 49))) == nil)
        #expect(AX.liveEntry(from: serverEntry(bounds: (10, 10))) != nil)
        // Sınır dâhil: 50 pt geçer.
        #expect(AX.serverWindow(from: serverEntry(bounds: (50, 50))) != nil)
        #expect(AX.serverWindow(from: serverEntry(bounds: nil)) != nil)
    }

    @Test func missingNameBecomesEmpty() {
        #expect(AX.serverWindow(from: serverEntry(name: nil))?.name == "")
    }

    @Test func missingNumberOrPIDIsNeitherLiveNorListed() {
        for entry in [serverEntry(number: nil), serverEntry(pid: nil),
                      serverEntry(number: nil, pid: nil), [:]] {
            #expect(AX.liveEntry(from: entry) == nil)
            #expect(AX.serverWindow(from: entry) == nil)
        }
    }

    @Test func setFrameTimeoutIsLongerThanGlobalReadTimeout() {
        // Yazım yavaş ama çalışan uygulamayı bekler; okumalar 1 sn'de düşer.
        #expect(AX.setFrameTimeout > 1.0)
    }

    // MARK: Masaüstü taşıma soğuması

    @Test func moveAttemptConstantsUnchanged() {
        #expect(Routing.maxMoveAttempts == 6)
        #expect(Routing.moveRetryInterval == 60)
    }

    @Test func moveAttemptsCountUpThenGiveUp() {
        var attempts: [String: Int] = [:]
        var last: [String: Date] = [:]
        let now = Date(timeIntervalSince1970: 1_000)
        var results: [Int?] = []
        for i in 0..<(Routing.maxMoveAttempts + 2) {
            results.append(Routing.recordMoveAttempt(
                key: "m", now: now.addingTimeInterval(Double(i)),
                attempts: &attempts, lastAttempts: &last))
        }
        #expect(results == [1, 2, 3, 4, 5, 6, nil, nil])
        #expect(attempts["m"] == Routing.maxMoveAttempts)
        // Vazgeçilen denemeler zaman damgasını yenilemez.
        #expect(last["m"] == now.addingTimeInterval(5))
    }

    @Test func moveAttemptsResumeAfterCooldown() {
        var attempts: [String: Int] = ["m": Routing.maxMoveAttempts]
        let lastTry = Date(timeIntervalSince1970: 1_000)
        var last: [String: Date] = ["m": lastTry]

        let tooSoon = lastTry.addingTimeInterval(Routing.moveRetryInterval - 1)
        #expect(Routing.recordMoveAttempt(key: "m", now: tooSoon,
                                          attempts: &attempts, lastAttempts: &last) == nil)
        #expect(attempts["m"] == Routing.maxMoveAttempts)
        #expect(last["m"] == lastTry)

        let later = lastTry.addingTimeInterval(Routing.moveRetryInterval)
        #expect(Routing.recordMoveAttempt(key: "m", now: later,
                                          attempts: &attempts, lastAttempts: &last) == 1)
        #expect(attempts["m"] == 1)
        #expect(last["m"] == later)
    }

    @Test func moveAttemptAtLimitWithoutTimestampStaysGivenUp() {
        // Eski kayıt (zaman damgası yok): soğuma ölçülemez, yeni tur açılmaz.
        var attempts: [String: Int] = ["m": Routing.maxMoveAttempts]
        var last: [String: Date] = [:]
        #expect(Routing.recordMoveAttempt(key: "m", now: Date(),
                                          attempts: &attempts, lastAttempts: &last) == nil)
        #expect(last.isEmpty)
    }

    @Test func moveAttemptKeysAreIndependent() {
        var attempts: [String: Int] = ["a": 2]
        var last: [String: Date] = [:]
        let now = Date()
        #expect(Routing.recordMoveAttempt(key: "b", now: now,
                                          attempts: &attempts, lastAttempts: &last) == 1)
        #expect(attempts == ["a": 2, "b": 1])
        #expect(last.keys.sorted() == ["b"])
    }

    // MARK: Yaşayan pencereler

    @Test func emptyServerListStaysEmptyDespiteAXWindows() {
        // Sunucu boş döndürdü (geçici hata): AX pencereleri eklenmez ki
        // budama ve pin düşürme "bilgi yok" diye atlansın.
        let live = Router.liveWindows(server: [:], ax: [(1, 10), (2, 20)])
        #expect(live.isEmpty)
        #expect(Router.liveWindows(server: [:], ax: []).isEmpty)
    }

    @Test func axOnlyWindowsAreAddedToNonEmptyServerList() {
        let live = Router.liveWindows(server: [1: 10, 3: 30], ax: [(1, 99), (2, 20)])
        // Sunucudaki pid korunur, yalnızca sunucuda olmayan eklenir.
        #expect(live == [1: 10, 2: 20, 3: 30])
        #expect(Router.liveWindows(server: [5: 50], ax: []) == [5: 50])
    }

    // MARK: Duraklama emniyeti

    @Test func pauseSafetyDelayIsAFewSeconds() {
        #expect(Router.pauseSafetyDelay == 5)
    }

    @Test func stuckPauseResumesOnlyWhenDisplayAwakeAndOldEnough() {
        let pausedAt = Date(timeIntervalSince1970: 1_000)
        let early = pausedAt.addingTimeInterval(Router.pauseSafetyDelay - 0.1)
        let late = pausedAt.addingTimeInterval(Router.pauseSafetyDelay)
        // Uykuya giriş sırasında bildirim sırasıyla çekişmesin: henüz erken.
        #expect(!Router.shouldResumeFromPause(pausedAt: pausedAt, now: early, displayAsleep: false))
        #expect(Router.shouldResumeFromPause(pausedAt: pausedAt, now: late, displayAsleep: false))
        #expect(Router.shouldResumeFromPause(
            pausedAt: pausedAt, now: late.addingTimeInterval(3_600), displayAsleep: false))
        // Ekran gerçekten uyuyorsa ne kadar geçse de sürdürülmez.
        #expect(!Router.shouldResumeFromPause(
            pausedAt: pausedAt, now: late.addingTimeInterval(3_600), displayAsleep: true))
        // Başlangıç bilinmiyorsa karar verilmez.
        #expect(!Router.shouldResumeFromPause(pausedAt: nil, now: late, displayAsleep: false))
    }

    // MARK: Ekran yatışması üst sınırı

    @Test func settleConstantsUnchanged() {
        #expect(ScreenService.settleInterval == 2.5)
        #expect(ScreenService.settleHardCap == 10)
    }

    @Test func settleDelayIsFullUntilHardCapApproaches() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(ScreenService.settleDelay(episodeStart: start, now: start) == 2.5)
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(6)) == 2.5)
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(7.5)) == 2.5)
        // Sınıra 2 sn kaldı: yalnızca o kadar beklenir.
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(8)) == 2.0)
    }

    @Test func settleDelayIsZeroAtOrPastHardCap() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(10)) == 0)
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(30)) == 0)
        // Saat geri gitse de negatif bekleme yok, normal süre.
        #expect(ScreenService.settleDelay(episodeStart: start, now: start.addingTimeInterval(-5)) == 2.5)
    }

    // MARK: Harici ekran sırası

    private typealias Key = (minX: CGFloat, minY: CGFloat, uuid: String)

    @Test func externalsOrderedLeftToRight() {
        let left: Key = (-2560, 0, "B")
        let right: Key = (1920, 0, "A")
        #expect(ScreenService.externalOrder(left, right))
        #expect(!ScreenService.externalOrder(right, left))
    }

    @Test func sameColumnBreaksTieByMinYThenUUID() {
        let lower: Key = (1920, -1440, "Z")
        let upper: Key = (1920, 0, "A")
        #expect(ScreenService.externalOrder(lower, upper))
        #expect(!ScreenService.externalOrder(upper, lower))

        let a: Key = (1920, 0, "AAAA")
        let b: Key = (1920, 0, "BBBB")
        #expect(ScreenService.externalOrder(a, b))
        #expect(!ScreenService.externalOrder(b, a))
        // Strict weak ordering: eşit anahtarlar iki yönde de false.
        #expect(!ScreenService.externalOrder(a, a))
    }

    @Test func externalOrderIsDeterministicRegardlessOfInput() {
        let keys: [Key] = [(1920, 0, "B"), (1920, 0, "A"), (-1000, 5, "C"), (1920, -100, "D")]
        let sorted = keys.sorted(by: ScreenService.externalOrder)
        let reversed = keys.reversed().sorted(by: ScreenService.externalOrder)
        #expect(sorted.map(\.uuid) == ["C", "D", "A", "B"])
        #expect(sorted.map(\.uuid) == reversed.map(\.uuid))
    }

    // MARK: Space türü haritası

    @Test func spaceTypesCollectedFromAllDisplays() {
        let displays = [
            SkyLight.DisplaySpaces(displayUUID: "A", current: 1, spaces: [
                SkyLight.Space(id: 1, type: 0), SkyLight.Space(id: 2, type: 4),
            ]),
            SkyLight.DisplaySpaces(displayUUID: "B", current: 10, spaces: [
                SkyLight.Space(id: 10, type: 0),
            ]),
        ]
        let types = SkyLight.spaceTypes(of: displays)
        #expect(types == [1: 0, 2: 4, 10: 0])
        // Haritada olmayan kimlik için çağıran `type(of:)` IPC'sine düşer.
        #expect(types[99] == nil)
        #expect(SkyLight.spaceTypes(of: []).isEmpty)
    }

    @Test func spaceTypesKeepFirstOnDuplicateID() {
        let displays = [
            SkyLight.DisplaySpaces(displayUUID: "A", current: 1,
                                   spaces: [SkyLight.Space(id: 1, type: 0)]),
            SkyLight.DisplaySpaces(displayUUID: "B", current: 1,
                                   spaces: [SkyLight.Space(id: 1, type: 4)]),
        ]
        #expect(SkyLight.spaceTypes(of: displays) == [1: 0])
    }

    // MARK: Yerleşim (saf, tek okunan durumla)

    private func screen(_ id: String, uuid: String, frame: CGRect) -> ScreenInfo {
        ScreenInfo(id: id, uuid: uuid, name: id, isBuiltin: id == "builtin",
                   frame: frame, visibleFrame: frame)
    }

    @Test func placementFromSpacesThenFrameThenFirstScreen() {
        let builtin = screen("builtin", uuid: "B", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let external = screen("external", uuid: "E", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        let displays = [
            SkyLight.DisplaySpaces(displayUUID: "B", current: 1, spaces: [
                SkyLight.Space(id: 1, type: 0), SkyLight.Space(id: 2, type: 0),
            ]),
            SkyLight.DisplaySpaces(displayUUID: "E", current: 20, spaces: [
                SkyLight.Space(id: 20, type: 0), SkyLight.Space(id: 21, type: 4),
                SkyLight.Space(id: 22, type: 0),
            ]),
        ]
        let screens = [builtin, external]

        // Space biliniyor: masaüstü sırası yalnızca normal masaüstülere göre.
        let onExternal = Router.WindowState(spaces: [22], isFullscreen: false, frame: nil, isMinimized: false)
        #expect(Router.placement(of: onExternal, displays: displays, screens: screens)
                == Router.Placement(screen: "external", desktop: 2))

        // Birden çok masaüstünde: ekranda görünen masaüstü (20) öne çıkar.
        let sticky = Router.WindowState(spaces: [22, 20], isFullscreen: false, frame: nil, isMinimized: false)
        #expect(Router.placement(of: sticky, displays: displays, screens: screens)
                == Router.Placement(screen: "external", desktop: 1))
        let stickyHidden = Router.WindowState(spaces: [22, 2], isFullscreen: false, frame: nil, isMinimized: false)
        #expect(Router.placement(of: stickyHidden, displays: displays, screens: screens)
                == Router.Placement(screen: "builtin", desktop: 2))

        // Space okundu ama bilinen masaüstlerinde yok: tahmin yok.
        let stray = Router.WindowState(
            spaces: [99], isFullscreen: false,
            frame: CGRect(x: 2000, y: 100, width: 800, height: 600), isMinimized: false)
        #expect(Router.placement(of: stray, displays: displays, screens: screens) == nil)

        // Tam ekran: yerleşim yok.
        let fullscreen = Router.WindowState(spaces: [21], isFullscreen: true, frame: nil, isMinimized: false)
        #expect(Router.placement(of: fullscreen, displays: displays, screens: screens) == nil)

        // Space bilgisi yok: çerçevenin merkezinden ekran (AX koordinatları).
        let byFrame = Router.WindowState(
            spaces: [], isFullscreen: false,
            frame: CGRect(x: 2000, y: 100, width: 800, height: 600), isMinimized: false)
        #expect(Router.placement(of: byFrame, displays: displays, screens: screens)
                == Router.Placement(screen: "external", desktop: 1))

        // Hiçbir bilgi yok: ilk ekran, masaüstü 1.
        let unknown = Router.WindowState(spaces: [], isFullscreen: false, frame: nil, isMinimized: false)
        #expect(Router.placement(of: unknown, displays: displays, screens: screens)
                == Router.Placement(screen: "builtin", desktop: 1))
        #expect(Router.placement(of: unknown, displays: displays, screens: []) == nil)
    }

    @Test func fullscreenSlotKeepsMissionControlOrder() {
        let external = screen("external", uuid: "E", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        let displays = [
            SkyLight.DisplaySpaces(displayUUID: "E", current: 20, spaces: [
                SkyLight.Space(id: 19, type: 4), SkyLight.Space(id: 20, type: 0),
                SkyLight.Space(id: 21, type: 4), SkyLight.Space(id: 23, type: 4),
                SkyLight.Space(id: 22, type: 0),
            ]),
        ]
        func state(_ space: UInt64, fullscreen: Bool = true) -> Router.WindowState {
            Router.WindowState(spaces: [space], isFullscreen: fullscreen, frame: nil, isMinimized: false)
        }
        func slot(_ space: UInt64, fullscreen: Bool = true) -> Router.FullscreenSlot? {
            Router.fullscreenSlot(of: state(space, fullscreen: fullscreen),
                                  displays: displays, screens: [external])
        }
        #expect(slot(19)?.afterDesktop == 0)
        #expect(slot(21)?.afterDesktop == 1)
        #expect(slot(23)?.afterDesktop == 1)
        #expect((slot(21)?.order ?? 0) < (slot(23)?.order ?? 0))
        #expect(slot(21)?.screen == "external")
        // Normal masaüstü ya da bilinmeyen space: yuva yok.
        #expect(slot(20, fullscreen: false) == nil)
        #expect(slot(99) == nil)

        // Arayüz gruplaması: Split View tek satır, sıra korunur, taşan en alta.
        func window(_ id: CGWindowID, _ space: UInt64) -> Router.WindowSnapshot {
            Router.WindowSnapshot(
                id: id, pid: 1, appName: "A", bundleID: "a", title: "", placement: nil,
                frame: nil, isMinimized: false, fullscreen: slot(space))
        }
        let windows = [window(1, 23), window(2, 21), window(3, 21), window(4, 19)]
        let grouped = FullscreenSpace.grouped(windows, screen: "external", rowCount: 2)
        #expect(grouped[0]?.map(\.id) == [19])
        #expect(grouped[1]?.map(\.id) == [21, 23])
        #expect(grouped[1]?.first?.windows.map(\.id) == [2, 3])
        #expect(FullscreenSpace.grouped(windows, screen: "builtin", rowCount: 2).isEmpty)
        #expect(FullscreenSpace.grouped(windows, screen: "external", rowCount: 0)[0]?.count == 3)
    }
}
