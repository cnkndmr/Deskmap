import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Tablo E: Mission Control'de başka ekrana sürüklenen masaüstünü geri
/// almak (algılama, karar, adım planı, yürütme, ad/plan/pin).
@MainActor
struct MissionControlRevertTests {

    // Örnek düzen (ölçekli): "external" = LG, "external-2" = Dell, "builtin" = laptop.
    // LG: 10 "Okuma" (adlı), 20, 30. Dell: 40, 50, 60.
    private let before: [String: [UInt64]] = [
        "builtin": [1, 2], "external": [10, 20, 30], "external-2": [40, 50, 60]]
    /// E1.1: "Okuma" (10) Dell'in 2. sırasına sürüklendi.
    private let afterMove: [String: [UInt64]] = [
        "builtin": [1, 2], "external": [20, 30], "external-2": [40, 10, 50, 60]]

    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func context(_ setting: DesktopRevert.Setting = .revert, observedLive: Bool = true,
                         movesAllowed: Bool = true, held: Set<String> = [],
                         screenChange: Date? = nil, wake: Date? = nil,
                         recent: [UInt64: Date] = [:]) -> DesktopRevert.Context {
        DesktopRevert.Context(setting: setting, observedLive: observedLive, movesAllowed: movesAllowed,
                              readOnly: false, heldRoles: held, lastScreenChange: screenChange,
                              lastWake: wake, recentReverts: recent, now: now)
    }

    private let okuma = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 1,
                                               to: "external-2", toDesktop: 2)

    // MARK: - E1 · Algılama

    @Test func e1_1_crossingDetected() {
        #expect(DesktopRevert.crossings(before: before, after: afterMove) == [okuma])
    }

    @Test func e1_3_twoCrossingsInOneSession() {
        let after: [String: [UInt64]] = ["builtin": [1, 2, 30], "external": [20], "external-2": [40, 10, 50, 60]]
        let found = DesktopRevert.crossings(before: before, after: after)
        #expect(found.map(\.space) == [10, 30])
        #expect(found[1] == .init(space: 30, from: "external", fromDesktop: 3, to: "builtin", toDesktop: 3))
    }

    /// E1.4: aynı farkta silme de var; yalnız ekran değiştiren sayılır.
    @Test func e1_4_deletionIsNotACrossing() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [30], "external-2": [40, 10, 50, 60]]
        #expect(DesktopRevert.crossings(before: before, after: after) == [okuma])
    }

    /// E1.8: laptop ↔ monitör de bir taşımadır.
    @Test func e1_8_builtinCrossing() {
        let after: [String: [UInt64]] = ["builtin": [2], "external": [1, 10, 20, 30], "external-2": [40, 50, 60]]
        #expect(DesktopRevert.crossings(before: before, after: after)
                == [.init(space: 1, from: "builtin", fromDesktop: 1, to: "external", toDesktop: 1)])
    }

    /// E3.1: rol kayboldu (monitör çıktı): taşıma sayılmaz.
    @Test func e3_1_vanishedRoleIsNotACrossing() {
        let after: [String: [UInt64]] = ["builtin": [1, 2, 10, 20, 30], "external-2": [40, 50, 60]]
        #expect(DesktopRevert.crossings(before: before, after: after).isEmpty)
    }

    /// E4.2: Deskmap içi taşıma yeni space açar; kimlik ekran değiştirmez.
    @Test func e4_2_newSpacesAreNotCrossings() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [10, 20, 30, 70], "external-2": [40, 50]]
        #expect(DesktopRevert.crossings(before: before, after: after).isEmpty)
    }

    @Test func reorderOnOneDisplayIsNotACrossing() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [30, 10, 20], "external-2": [40, 50, 60]]
        #expect(DesktopRevert.crossings(before: before, after: after).isEmpty)
    }

    // MARK: - Karar (SE1–SE7)

    @Test func e1_1_revertsByDefault() {
        #expect(DesktopRevert.Setting.defaultValue == .revert)
        #expect(DesktopRevert.decide(okuma, context()) == .revert)
    }

    @Test func e6_1_askAndLeaveSettings() {
        #expect(DesktopRevert.decide(okuma, context(.ask)) == .ask)
        #expect(DesktopRevert.decide(okuma, context(.leave)) == .leave)
    }

    /// E1.6 / SE2: Deskmap kapalıyken olan taşıma: kart, kendiliğinden değil.
    @Test func e1_6_catchUpAsks() {
        #expect(DesktopRevert.decide(okuma, context(observedLive: false)) == .ask)
        #expect(DesktopRevert.decide(okuma, context(.leave, observedLive: false)) == .leave)
        // Açılışın kendi ekran ölçümü kartı engellemez.
        #expect(DesktopRevert.decide(okuma, context(observedLive: false,
                                                    screenChange: now.addingTimeInterval(-1))) == .ask)
    }

    /// E2.8: masaüstü taşıma kapalı: sessiz değil, kart.
    @Test func e2_8_movesOffShowsCard() {
        #expect(DesktopRevert.decide(okuma, context(movesAllowed: false)) == .blocked)
        #expect(DesktopRevert.decide(okuma, context(.ask, movesAllowed: false)) == .blocked)
        #expect(DesktopRevert.decide(okuma, context(observedLive: false, movesAllowed: false)) == .blocked)
    }

    /// E3.5: son 15 sn'de ekran bildirimi: macOS'un işi olabilir.
    @Test func e3_5_recentScreenChangeLeaves() {
        #expect(DesktopRevert.decide(okuma, context(screenChange: now.addingTimeInterval(-5))) == .leave)
        #expect(DesktopRevert.decide(okuma, context(screenChange: now.addingTimeInterval(-16))) == .revert)
    }

    /// E3.4: uyanmadan 60 sn içinde geri alma yok.
    @Test func e3_4_recentWakeLeaves() {
        #expect(DesktopRevert.decide(okuma, context(wake: now.addingTimeInterval(-30))) == .leave)
        #expect(DesktopRevert.decide(okuma, context(wake: now.addingTimeInterval(-61))) == .revert)
    }

    /// E3.7 / SE6: onay bekleyen monitöre ya da ondan taşıma izlenir.
    @Test func e3_7_heldRoleLeaves() {
        #expect(DesktopRevert.decide(okuma, context(held: ["external-2"])) == .leave)
        #expect(DesktopRevert.decide(okuma, context(held: ["external"])) == .leave)
        #expect(DesktopRevert.decide(okuma, context(held: ["external-3"])) == .revert)
    }

    /// E4.3 / SE3: geri alınan masaüstü 60 sn içinde yine taşındı: kasıtlı.
    @Test func e4_3_repeatWithinAMinuteLeaves() {
        #expect(DesktopRevert.decide(okuma, context(recent: [10: now.addingTimeInterval(-20)])) == .leave)
        #expect(DesktopRevert.decide(okuma, context(recent: [10: now.addingTimeInterval(-70)])) == .revert)
    }

    @Test func readOnlyLeaves() {
        var c = context()
        c.readOnly = true
        #expect(DesktopRevert.decide(okuma, c) == .leave)
    }

    @Test func settingCodable() throws {
        var d = Document()
        #expect(d.missionControlMoves == .revert)
        d.missionControlMoves = .ask
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.missionControlMoves == .ask)
        // Eski dosya (alan yok) varsayılanı alır; varsayılan yazılmaz.
        let plain = try JSONEncoder().encode(Document())
        #expect(!(String(data: plain, encoding: .utf8) ?? "").contains("missionControlMoves"))
        #expect(try JSONDecoder().decode(Document.self, from: plain).missionControlMoves == .revert)
    }

    // MARK: - E2 · Adım planı

    /// E2.1: "Okuma" (LG · 1) geri: LG'nin sonuna masaüstü, LG · 1 ve sonrası
    /// birer kayar, X'in içeriği LG · 1'e, X silinir.
    @Test func e2_1_planShiftsAndRemoves() throws {
        let contents: [UInt64: [CGWindowID]] = [10: [101, 102], 20: [201], 30: [301]]
        let plan = try #require(DesktopRevert.plan(okuma, live: afterMove, contents: contents))
        #expect(plan.creates == ["external": 1])
        #expect(Set(plan.moves) == [
            .init(window: 101, to: Slot(screen: "external", desktop: 1)),
            .init(window: 102, to: Slot(screen: "external", desktop: 1)),
            .init(window: 201, to: Slot(screen: "external", desktop: 2)),
            .init(window: 301, to: Slot(screen: "external", desktop: 3))])
        #expect(plan.spaceMap == [10: Slot(screen: "external", desktop: 1),
                                  20: Slot(screen: "external", desktop: 2),
                                  30: Slot(screen: "external", desktop: 3)])
        #expect(plan.removals == [10])
        #expect(plan.rebinds.isEmpty)
    }

    /// E2.2: son masaüstüydü: kaydırma yok.
    @Test func e2_2_lastDesktopNoShift() throws {
        let crossing = DesktopRevert.Crossing(space: 30, from: "external", fromDesktop: 3,
                                              to: "external-2", toDesktop: 4)
        let live: [String: [UInt64]] = ["external": [10, 20], "external-2": [40, 50, 60, 30]]
        let plan = try #require(DesktopRevert.plan(crossing, live: live, contents: [30: [301], 10: [101]]))
        #expect(plan.moves == [.init(window: 301, to: Slot(screen: "external", desktop: 3))])
        #expect(plan.spaceMap == [30: Slot(screen: "external", desktop: 3)])
    }

    /// E2.3: ortadaki masaüstü: o sıra ve sonrası kayar, öncekiler yerinde.
    @Test func e2_3_middleDesktopShiftsOnlyLater() throws {
        let crossing = DesktopRevert.Crossing(space: 20, from: "external", fromDesktop: 2,
                                              to: "external-2", toDesktop: 1)
        let live: [String: [UInt64]] = ["external": [10, 30], "external-2": [20, 40, 50, 60]]
        let plan = try #require(DesktopRevert.plan(crossing, live: live,
                                                   contents: [10: [101], 20: [201], 30: [301]]))
        #expect(Set(plan.moves) == [.init(window: 201, to: Slot(screen: "external", desktop: 2)),
                                    .init(window: 301, to: Slot(screen: "external", desktop: 3))])
        #expect(plan.spaceMap[10] == nil)
    }

    /// Masaüstü artık yoksa ya da kaynak ekranın tek masaüstüyse plan yok.
    @Test func noPlanWhenGoneOrLast() {
        #expect(DesktopRevert.plan(okuma, live: before, contents: [:]) == nil)
        let lone: [String: [UInt64]] = ["external": [20], "external-2": [10]]
        #expect(DesktopRevert.plan(okuma, live: lone, contents: [:]) == nil)
    }

    // MARK: - E2 · Yürütme (sahte Mission Control + SkyLight)

    private func run(_ fake: FakeDesktops, _ crossing: DesktopRevert.Crossing) async -> PlanExecutor.Outcome? {
        await DesktopRevert.run(crossing, contents: fake.contents, windowSpaces: fake.location,
                                world: fake.world)
    }

    @Test func e2_1_executesRevert() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 201: 20, 301: 30, 401: 40, 501: 50])
        let out = try #require(await run(fake, okuma))
        let lg = try #require(fake.spaces["external"])
        #expect(lg.count == 3 && lg[0] == 20 && lg[1] == 30)
        #expect(fake.spaces["external-2"] == [40, 50, 60])
        #expect(fake.location[101] == lg[0] && fake.location[201] == lg[1] && fake.location[301] == lg[2])
        #expect(fake.location[401] == 40 && fake.location[501] == 50)
        #expect(out.removedSpaces == [10])
        #expect(DesktopRevert.result(out, crossing: okuma) == .reverted(newSpace: lg[0]))
    }

    /// E2.6 / SE5: X'te taşınamayan pencere: X kalır, sonuç "kısmen".
    @Test func e2_6_windowLeftKeepsDesktop() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 102: 10])
        fake.failMoves = [102]
        let out = try #require(await run(fake, okuma))
        #expect(fake.spaces["external-2"]?.contains(10) == true)
        #expect(!fake.removedNonEmpty)
        let lg = try #require(fake.spaces["external"])
        #expect(DesktopRevert.result(out, crossing: okuma) == .partial(newSpace: lg[0], stayed: 1))
    }

    /// E2.7: masaüstü eklenemedi: hiçbir şey değişmez.
    @Test func e2_7_addFailsChangesNothing() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10])
        fake.failAdds = true
        let out = try #require(await run(fake, okuma))
        #expect(fake.spaces == afterMove && fake.location == [101: 10])
        #expect(DesktopRevert.result(out, crossing: okuma) == .failed)
    }

    /// E2.7: açılan masaüstü sona gelmedi (sıra kaydı): hiçbir pencere taşınmaz.
    @Test func e2_7_addNotAtEndMovesNothing() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 201: 20])
        fake.addAtFront = true
        let out = try #require(await run(fake, okuma))
        #expect(fake.moveCount.isEmpty && fake.removed.isEmpty)
        #expect(DesktopRevert.result(out, crossing: okuma) == .failed)
    }

    /// E2.10: yarıda kesildi (ekran değişti): silme yok.
    @Test func e2_10_abortKeepsSource() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10])
        fake.abortWhen = { $0.spaces["external"]?.count == 3 }
        let out = try #require(await run(fake, okuma))
        #expect(out.aborted && fake.removed.isEmpty)
        #expect(fake.spaces["external-2"]?.contains(10) == true)
    }

    /// E2.5: "All Desktops" penceresi içerikte değil, silmeyi engellemez.
    @Test func e2_5_allDesktopsWindowIgnored() async throws {
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10])
        let out = try #require(await run(fake, okuma))
        #expect(out.removedSpaces == [10])
    }

    // MARK: - E5 · Ad, plan, pin

    private func lgDoc() -> Document {
        V6.document(
            rules: [V6.rule("Safari", docked: V6.at("external", 1, name: "OKUMA")),
                    V6.rule("Notes", docked: V6.e(2)),
                    V6.rule("Mail", docked: V6.at("external-2", 3))],
            names: [DesktopName(id: "OKUMA", name: "Okuma", space: 10)],
            plans: DesktopPlans(docked: ["external": ["OKUMA", "", ""], "external-2": ["", "", ""],
                                         "builtin": ["", ""]]))
    }

    /// E5.1–E5.3: izleme (P3) + geri alma = önceki planlar ve pinler; ad yeni space'te.
    @Test func e5_followThenRevertRestoresPlansAndPins() async throws {
        var d = lgDoc()
        let original = d
        d.followMissionControl(before: before, after: afterMove, mode: .docked)
        #expect(d.plans.entries(.docked, "external-2") == ["", "OKUMA", "", ""])
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 201: 20])
        let out = try #require(await run(fake, okuma))
        d.applySpaceMap(out.spaceMap)
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        #expect(d.plans == original.plans)
        #expect(d.rules == original.rules)
        let lg = try #require(fake.spaces["external"])
        #expect(d.names.first?.space == lg[0])
    }

    /// E5.4: kayan masaüstülerinin adları içerikle gider.
    @Test func e5_4_shiftedNamesFollowContent() async throws {
        var d = lgDoc()
        d.names.append(DesktopName(id: "IS", name: "İş", space: 20))
        d.plans.set(["OKUMA", "IS", ""], .docked, "external")
        let original = d.plans
        d.followMissionControl(before: before, after: afterMove, mode: .docked)
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 201: 20])
        let out = try #require(await run(fake, okuma))
        d.applySpaceMap(out.spaceMap)
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        let lg = try #require(fake.spaces["external"])
        #expect(d.nameRecord("IS")?.space == lg[1])
        #expect(d.plans == original)
    }

    /// Bütün profillerde plan girdisi geri döner (izleme de bütün profilleri yazar).
    @Test func e5_returnPlanEntryAllProfiles() {
        var d = lgDoc()
        _ = d.duplicateProfile(d.activeProfileID, named: "Copy")
        d.followMissionControl(before: before, after: afterMove, mode: .docked)
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        d.syncActiveProfile()
        for profile in d.profiles {
            #expect(profile.plans.entries(.docked, "external") == ["OKUMA", "", ""])
            #expect(profile.plans.entries(.docked, "external-2") == ["", "", ""])
        }
    }

    /// E4.4: "Böyle kalsın" ters taşıma: geri alınanın yeni space'i
    /// kullanıcının bıraktığı yere.
    @Test func e4_4_keepIsTheReverseCrossing() {
        let keep = DesktopRevert.reverse(okuma, newSpace: 70)
        #expect(keep == .init(space: 70, from: "external-2", fromDesktop: 2, to: "external", toDesktop: 1))
    }
}
