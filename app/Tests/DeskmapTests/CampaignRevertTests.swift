import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya: Mission Control geri alma (Tablo E) için ek kenar durumları.
/// Mevcut `MissionControlRevertTests`'i tekrarlamaz: sınır değerleri, karar
/// önceliği, ardışık geri almalar, rol takası, plan/pin etkileşimleri.
@MainActor
struct CampaignRevertTests {

    private let before: [String: [UInt64]] = [
        "builtin": [1, 2], "external": [10, 20, 30], "external-2": [40, 50, 60]]
    private let now = Date(timeIntervalSince1970: 3_000_000)

    private func context(_ setting: DesktopRevert.Setting = .revert, observedLive: Bool = true,
                         movesAllowed: Bool = true, readOnly: Bool = false, held: Set<String> = [],
                         screenChange: Date? = nil, wake: Date? = nil,
                         recent: [UInt64: Date] = [:]) -> DesktopRevert.Context {
        DesktopRevert.Context(setting: setting, observedLive: observedLive, movesAllowed: movesAllowed,
                              readOnly: readOnly, heldRoles: held, lastScreenChange: screenChange,
                              lastWake: wake, recentReverts: recent, now: now)
    }

    private let okuma = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 1,
                                               to: "external-2", toDesktop: 2)

    // MARK: - E1 · Algılama kenarları

    /// İki masaüstü karşılıklı yer değiştirdi: ikisi de ayrı taşıma.
    @Test func e1_3_swapBetweenRolesReportsBoth() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [40, 20, 30], "external-2": [10, 50, 60]]
        let found = DesktopRevert.crossings(before: before, after: after)
        #expect(Set(found.map(\.space)) == [10, 40])
        #expect(found.first { $0.space == 10 } == .init(space: 10, from: "external", fromDesktop: 1,
                                                        to: "external-2", toDesktop: 1))
        #expect(found.first { $0.space == 40 } == .init(space: 40, from: "external-2", fromDesktop: 1,
                                                        to: "external", toDesktop: 1))
    }

    /// E3.2: sonradan gelen (kayıtta olmayan) rolün masaüstüleri taşıma sayılmaz.
    @Test func e3_2_newRoleOwnsNoCrossings() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [20, 30],
                                         "external-2": [40, 50, 60], "external-3": [10]]
        #expect(DesktopRevert.crossings(before: before, after: after).isEmpty)
    }

    /// Tek masaüstü kalan ekrana taşınma: kaynak ekran boşalsa da (rolü var) algılanır.
    @Test func e1_1_sourceRoleEmptiedStillDetected() {
        let after: [String: [UInt64]] = ["builtin": [1, 2, 10], "external": [], "external-2": [40, 50, 60]]
        let found = DesktopRevert.crossings(before: ["builtin": [1, 2], "external": [10], "external-2": [40, 50, 60]],
                                            after: after)
        #expect(found == [.init(space: 10, from: "external", fromDesktop: 1, to: "builtin", toDesktop: 3)])
    }

    /// E2.4: tam ekran space'ler listelerde yok; kimliği hiçbir listede geçmeyen taşıma görünmez.
    @Test func e2_4_fullscreenSpaceNeverInListsIsInvisible() {
        // 77 (tam ekran Video) iki listede de yok; yalnız normal masaüstüleri kıyaslanır.
        #expect(DesktopRevert.crossings(before: before, after: before).isEmpty)
    }

    /// Aynı sırada, fakat bütün ekranlar aynı: kimlik değişmedi, taşıma yok.
    @Test func e1_1_identicalListsNoCrossing() {
        #expect(DesktopRevert.crossings(before: before, after: before).isEmpty)
    }

    /// E1.3: ardışık iki masaüstü aynı ekrana; eski sıra numaraları kayıttan.
    @Test func e1_3_twoFromSameRoleKeepOriginalDesktopNumbers() {
        let after: [String: [UInt64]] = ["builtin": [1, 2], "external": [30],
                                         "external-2": [40, 10, 20, 50, 60]]
        let found = DesktopRevert.crossings(before: before, after: after)
        #expect(found.map(\.fromDesktop) == [1, 2])
        #expect(found.map(\.toDesktop) == [2, 3])
    }

    /// E1.4: aynı farkta başka ekrandan silme ve eklenme var; taşıma yine yalnız bir tane.
    @Test func e1_4_deletionAndAdditionAlongsideOneMove() {
        let after: [String: [UInt64]] = ["builtin": [1], "external": [20, 30, 99],
                                         "external-2": [40, 10, 50, 60]]
        #expect(DesktopRevert.crossings(before: before, after: after) == [okuma])
    }

    // MARK: - E3 · Rol takası

    /// E3.5/rol takası: iki monitörün rolleri yer değiştirdi (aynı kimlikler, ters roller):
    /// ekran kümesi "değişti" sayılmalı ki 6 masaüstü birden "taşındı" diye geri alınmasın.
    @Test func e3_roleSwapCountsAsDisplaysChanged() {
        let saved = DesktopStateFile(mode: .docked, displays: [
            .init(role: "builtin", uuid: "B", spaces: [1, 2]),
            .init(role: "external", uuid: "DELL", spaces: [10, 20, 30]),
            .init(role: "external-2", uuid: "LG", spaces: [40, 50, 60])])
        let swapped: [DesktopStateFile.Display] = [
            .init(role: "builtin", uuid: "B", spaces: [1, 2]),
            .init(role: "external", uuid: "LG", spaces: [40, 50, 60]),
            .init(role: "external-2", uuid: "DELL", spaces: [10, 20, 30])]
        #expect(!saved.sameDisplays(as: swapped))
        // Aynı kümede yalnız masaüstü listesi değişirse ekranlar aynı kalır.
        let moved: [DesktopStateFile.Display] = [
            .init(role: "builtin", uuid: "B", spaces: [1, 2]),
            .init(role: "external", uuid: "DELL", spaces: [20, 30]),
            .init(role: "external-2", uuid: "LG", spaces: [40, 10, 50, 60])]
        #expect(saved.sameDisplays(as: moved))
    }

    /// Rol takası listelere yansırsa ham fark 6 "taşıma" üretir: bu yüzden
    /// çağıran ekran kümesi karşılaştırmasını önce yapmak zorunda (belgeleyici test).
    @Test func e3_rawRoleSwapDiffWouldBeSixCrossings() {
        let swapped: [String: [UInt64]] = ["builtin": [1, 2], "external": [40, 50, 60], "external-2": [10, 20, 30]]
        #expect(DesktopRevert.crossings(before: before, after: swapped).count == 6)
    }

    // MARK: - Karar (SE1–SE7) sınırları ve öncelikler

    /// Tam 15 sn: sessiz süre bitti (kesin küçüktür).
    @Test func e3_5_exactlyFifteenSecondsReverts() {
        #expect(DesktopRevert.decide(okuma, context(screenChange: now.addingTimeInterval(-15))) == .revert)
        #expect(DesktopRevert.decide(okuma, context(screenChange: now.addingTimeInterval(-14.9))) == .leave)
    }

    @Test func e3_4_exactlySixtySecondsAfterWakeReverts() {
        #expect(DesktopRevert.decide(okuma, context(wake: now.addingTimeInterval(-60))) == .revert)
        #expect(DesktopRevert.decide(okuma, context(wake: now.addingTimeInterval(-59.9))) == .leave)
    }

    @Test func e4_3_exactlySixtySecondsAfterRevertCountsAsFresh() {
        #expect(DesktopRevert.decide(okuma, context(recent: [10: now.addingTimeInterval(-60)])) == .revert)
        #expect(DesktopRevert.decide(okuma, context(recent: [10: now.addingTimeInterval(-59)])) == .leave)
    }

    /// SE3 yalnız o space için: başka space'in yakın geri alması engellemez.
    @Test func e4_3_recentRevertOfOtherSpaceDoesNotBlock() {
        #expect(DesktopRevert.decide(okuma, context(recent: [20: now.addingTimeInterval(-5)])) == .revert)
    }

    /// SE3, Sor ayarında da geçerli: kasıtlı tekrar için kart çıkmaz.
    @Test func e4_3_repeatIsLeftEvenInAskMode() {
        #expect(DesktopRevert.decide(okuma, context(.ask, recent: [10: now.addingTimeInterval(-10)])) == .leave)
    }

    /// Sor ayarı da ekran bildirimi / uyanma sessizliğine uyar: kart değil, izle.
    @Test func e3_askModeAlsoQuietAfterScreenChangeOrWake() {
        #expect(DesktopRevert.decide(okuma, context(.ask, screenChange: now.addingTimeInterval(-3))) == .leave)
        #expect(DesktopRevert.decide(okuma, context(.ask, wake: now.addingTimeInterval(-3))) == .leave)
    }

    /// E2.8 + E3.5: macOS'un işi olabilir; taşıma kapalıyken de "kapalı" kartı çıkmaz.
    @Test func e3_5_quietBeatsBlocked() {
        #expect(DesktopRevert.decide(okuma, context(movesAllowed: false,
                                                    screenChange: now.addingTimeInterval(-2))) == .leave)
    }

    /// SE7: Bırak seçiliyken taşıma kapalı olsa da kart yok (bugünkü izleme).
    @Test func se7_leaveBeatsBlockedAndCatchUpCard() {
        #expect(DesktopRevert.decide(okuma, context(.leave, movesAllowed: false)) == .leave)
        #expect(DesktopRevert.decide(okuma, context(.leave, observedLive: false, movesAllowed: false)) == .leave)
    }

    /// Salt okunur belge: kapalıyken olan taşıma için de kart yok.
    @Test func readOnlyBeatsCatchUpCard() {
        #expect(DesktopRevert.decide(okuma, context(observedLive: false, readOnly: true)) == .leave)
        #expect(DesktopRevert.decide(okuma, context(movesAllowed: false, readOnly: true)) == .leave)
    }

    /// SE6: onay bekleyen rol, kapalıyken olan taşımada da kart çıkarmaz.
    @Test func se6_heldRoleBeatsCatchUpCard() {
        #expect(DesktopRevert.decide(okuma, context(observedLive: false, held: ["external-2"])) == .leave)
    }

    /// SE6: laptop dahil (builtin onay beklemez ama held kümesindeyse yine izlenir).
    @Test func se6_builtinCrossingIncluded() {
        let toBuiltin = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 1,
                                               to: "builtin", toDesktop: 3)
        #expect(DesktopRevert.decide(toBuiltin, context()) == .revert)
        #expect(DesktopRevert.decide(toBuiltin, context(held: ["builtin"])) == .leave)
    }

    /// SE2: kapalıyken olan taşımada uyanma/ekran süreleri sayılmaz (kart yine çıkar).
    @Test func se2_catchUpIgnoresWakeAndRecentRevert() {
        #expect(DesktopRevert.decide(okuma, context(observedLive: false,
                                                    wake: now.addingTimeInterval(-5))) == .ask)
        #expect(DesktopRevert.decide(okuma, context(observedLive: false,
                                                    recent: [10: now.addingTimeInterval(-5)])) == .ask)
    }

    /// Saat geriye atladı (gelecek tarihli ekran bildirimi): güvenli tarafta, izle.
    @Test func e3_futureDatedScreenChangeLeaves() {
        #expect(DesktopRevert.decide(okuma, context(screenChange: now.addingTimeInterval(30))) == .leave)
    }

    // MARK: - E2 · Plan kenarları

    /// Sıra eski sayıdan büyük (ekran küçüldü): sona eklenir, kayma yok.
    @Test func e2_2_desktopNumberBeyondEndClampsToAppend() throws {
        let crossing = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 9,
                                              to: "external-2", toDesktop: 2)
        let live: [String: [UInt64]] = ["external": [20, 30], "external-2": [40, 10, 50]]
        let plan = try #require(DesktopRevert.plan(crossing, live: live, contents: [10: [101], 20: [201]]))
        #expect(plan.moves == [.init(window: 101, to: Slot(screen: "external", desktop: 3))])
        #expect(plan.spaceMap == [10: Slot(screen: "external", desktop: 3)])
    }

    @Test func e2_1_desktopNumberZeroOrNegativeClampsToFirst() throws {
        let crossing = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 0,
                                              to: "external-2", toDesktop: 2)
        let live: [String: [UInt64]] = ["external": [20, 30], "external-2": [40, 10, 50]]
        let plan = try #require(DesktopRevert.plan(crossing, live: live, contents: [10: [101], 20: [201]]))
        #expect(plan.spaceMap[10] == Slot(screen: "external", desktop: 1))
        #expect(plan.spaceMap[20] == Slot(screen: "external", desktop: 2))
        #expect(plan.spaceMap[30] == Slot(screen: "external", desktop: 3))
    }

    /// E2.1: plan yalnız kaynak ve taşınan masaüstüne dokunur; hedef ekranın öbür masaüstülerine değil.
    @Test func e2_1_planNeverTouchesDestinationDisplaysOtherDesktops() throws {
        let live: [String: [UInt64]] = ["builtin": [1, 2], "external": [20, 30], "external-2": [40, 10, 50, 60]]
        let contents: [UInt64: [CGWindowID]] = [1: [901], 2: [902], 10: [101], 20: [201], 30: [301],
                                                40: [401], 50: [501], 60: [601]]
        let plan = try #require(DesktopRevert.plan(okuma, live: live, contents: contents))
        let moved = Set(plan.moves.map(\.window))
        #expect(moved == [101, 201, 301])
        #expect(plan.removals == [10])
        #expect(plan.creates == ["external": 1])
        #expect(plan.moves.allSatisfy { $0.to.screen == "external" })
    }

    /// E1.5: boş (penceresiz) masaüstü geri alınır: taşıma yok, yine de ad haritası var.
    @Test func e1_5_emptyDesktopStillMapsNameAndRemoves() throws {
        let live: [String: [UInt64]] = ["external": [20, 30], "external-2": [40, 10, 50, 60]]
        let plan = try #require(DesktopRevert.plan(okuma, live: live, contents: [:]))
        #expect(plan.moves.isEmpty)
        #expect(plan.spaceMap[10] == Slot(screen: "external", desktop: 1))
        #expect(plan.removals == [10])
    }

    /// Masaüstü başka bir ekrana daha taşınmış: plan yok (kayıt bayat).
    @Test func e2_staleCrossingWhenSpaceMovedAgainHasNoPlan() {
        let live: [String: [UInt64]] = ["builtin": [1, 2, 10], "external": [20, 30], "external-2": [40, 50, 60]]
        #expect(DesktopRevert.plan(okuma, live: live, contents: [:]) == nil)
    }

    /// Masaüstü zaten kaynak ekranda görünüyorsa (çift kayıt) plan yok.
    @Test func e2_planNilWhenSpaceAlreadyHome() {
        let live: [String: [UInt64]] = ["external": [10, 20], "external-2": [40, 10, 50]]
        #expect(DesktopRevert.plan(okuma, live: live, contents: [:]) == nil)
    }

    /// Kaynak ekran artık bağlı değil: plan yok.
    @Test func e3_1_planNilWhenHomeRoleGone() {
        let live: [String: [UInt64]] = ["external-2": [40, 10, 50]]
        #expect(DesktopRevert.plan(okuma, live: live, contents: [10: [101]]) == nil)
    }

    // MARK: - E2 · Yürütme

    /// SE4: ortadaki masaüstü, gerçek sahte dünyada: öncekiler yerinde, sonrakiler içerikle kayar.
    @Test func se4_middleDesktopExecutesWithContentShift() async throws {
        let crossing = DesktopRevert.Crossing(space: 20, from: "external", fromDesktop: 2,
                                              to: "external-2", toDesktop: 1)
        let fake = FakeDesktops(spaces: ["external": [10, 30], "external-2": [20, 40, 50, 60]],
                                location: [101: 10, 201: 20, 301: 30, 401: 40])
        let out = try #require(await DesktopRevert.run(crossing, contents: fake.contents,
                                                       windowSpaces: fake.location, world: fake.world))
        let lg = try #require(fake.spaces["external"])
        #expect(lg.count == 3 && lg[0] == 10)
        #expect(fake.location[101] == 10)              // öncesi yerinde
        #expect(fake.location[201] == lg[1])           // taşınan masaüstü eski sırasına
        #expect(fake.location[301] == lg[2])           // sonrası bir kaydı
        #expect(fake.location[401] == 40)              // hedef ekran dokunulmadı
        #expect(fake.spaces["external-2"] == [40, 50, 60])
        #expect(DesktopRevert.result(out, crossing: crossing) == .reverted(newSpace: lg[1]))
    }

    /// SE4: son masaüstü geri alınınca öncekilerin hiç penceresi taşınmaz.
    @Test func se4_lastDesktopMovesOnlyItsOwnWindows() async throws {
        let crossing = DesktopRevert.Crossing(space: 30, from: "external", fromDesktop: 3,
                                              to: "external-2", toDesktop: 4)
        let fake = FakeDesktops(spaces: ["external": [10, 20], "external-2": [40, 50, 60, 30]],
                                location: [101: 10, 201: 20, 301: 30, 302: 30])
        _ = try #require(await DesktopRevert.run(crossing, contents: fake.contents,
                                                 windowSpaces: fake.location, world: fake.world))
        #expect(fake.moveCount[101] == nil && fake.moveCount[201] == nil)
        #expect(fake.moveCount[301] == 1 && fake.moveCount[302] == 1)
        #expect(fake.removed == [30])
    }

    /// SE5: iki pencereden biri taşınamadı: masaüstü kalır, kalan sayısı 1; sonuç "kısmen".
    @Test func se5_nonEmptyDesktopIsNeverRemovedAndCountsStayers() async throws {
        let fake = FakeDesktops(spaces: ["external": [20, 30], "external-2": [40, 10, 50, 60]],
                                location: [101: 10, 102: 10, 103: 10])
        fake.failMoves = [102, 103]
        let out = try #require(await DesktopRevert.run(okuma, contents: fake.contents,
                                                       windowSpaces: fake.location, world: fake.world))
        #expect(fake.removed.isEmpty && !fake.removedNonEmpty)
        guard case .partial(_, let stayed) = DesktopRevert.result(out, crossing: okuma) else {
            Issue.record("expected partial"); return
        }
        #expect(stayed == 2)
        // Kalan pencereler kaynağında, taşınan öteki yeni masaüstünde.
        #expect(fake.location[102] == 10 && fake.location[103] == 10)
        #expect(fake.location[101] == fake.spaces["external"]?.first)
    }

    /// Boşluk okunamadı (isEmpty nil): silme yapılmaz, yine de "kısmen" (en az 1).
    @Test func se5_unknownEmptinessKeepsDesktop() async throws {
        let fake = FakeDesktops(spaces: ["external": [20, 30], "external-2": [40, 10, 50, 60]],
                                location: [101: 10])
        var world = fake.world
        world.isEmpty = { _ in nil }
        let out = try #require(await DesktopRevert.run(okuma, contents: fake.contents,
                                                       windowSpaces: fake.location, world: world))
        #expect(fake.removed.isEmpty)
        guard case .partial(_, let stayed) = DesktopRevert.result(out, crossing: okuma) else {
            Issue.record("expected partial"); return
        }
        #expect(stayed >= 1)
    }

    /// E2.10: baştan kesildi: masaüstü bile eklenmez, hiçbir şey değişmez.
    @Test func e2_10_abortBeforeAddChangesNothing() async throws {
        let fake = FakeDesktops(spaces: ["external": [20, 30], "external-2": [40, 10, 50, 60]],
                                location: [101: 10])
        fake.abortWhen = { _ in true }
        let out = try #require(await DesktopRevert.run(okuma, contents: fake.contents,
                                                       windowSpaces: fake.location, world: fake.world))
        #expect(out.aborted && fake.spaces["external"] == [20, 30] && fake.moveCount.isEmpty)
        #expect(DesktopRevert.result(out, crossing: okuma) == .failed)
    }

    /// Bayat kayıt (masaüstü artık hedef ekranda değil): nil, hiçbir şey eklenmez.
    @Test func e2_staleCrossingRunReturnsNilAndTouchesNothing() async {
        let fake = FakeDesktops(spaces: ["external": [20, 30], "external-2": [40, 50, 60]],
                                location: [101: 10])
        let out = await DesktopRevert.run(okuma, contents: fake.contents, windowSpaces: fake.location,
                                          world: fake.world)
        #expect(out == nil && fake.nextSpace == 9000 && fake.moveCount.isEmpty)
    }

    /// E1.3: iki masaüstü aynı ekrandan, ardışık geri alma (Router'ın döngüsü gibi her seferinde taze liste).
    @Test func e1_3_sequentialRevertsRestoreOriginalOrder() async throws {
        let fake = FakeDesktops(spaces: ["external": [20], "external-2": [40, 10, 50, 30, 60]],
                                location: [101: 10, 201: 20, 301: 30])
        let first = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 1,
                                           to: "external-2", toDesktop: 2)
        let second = DesktopRevert.Crossing(space: 30, from: "external", fromDesktop: 3,
                                            to: "external-2", toDesktop: 4)
        for crossing in [first, second] {
            guard let index = fake.spaces[crossing.to]?.firstIndex(of: crossing.space) else {
                Issue.record("space vanished before its turn"); return
            }
            var current = crossing
            current.toDesktop = index + 1
            _ = try #require(await DesktopRevert.run(current, contents: fake.contents,
                                                     windowSpaces: fake.location, world: fake.world))
        }
        let lg = try #require(fake.spaces["external"])
        #expect(lg.count == 3)
        #expect(fake.location[101] == lg[0] && fake.location[201] == lg[1] && fake.location[301] == lg[2])
        #expect(fake.spaces["external-2"] == [40, 50, 60])
    }

    /// Aynı iki geri alma ters sırada da özgün sırayı kurar.
    @Test func e1_3_sequentialRevertsInReverseOrderAlsoRestore() async throws {
        let fake = FakeDesktops(spaces: ["external": [20], "external-2": [40, 10, 50, 30, 60]],
                                location: [101: 10, 201: 20, 301: 30])
        let first = DesktopRevert.Crossing(space: 30, from: "external", fromDesktop: 3,
                                           to: "external-2", toDesktop: 4)
        let second = DesktopRevert.Crossing(space: 10, from: "external", fromDesktop: 1,
                                            to: "external-2", toDesktop: 2)
        for crossing in [first, second] {
            guard let index = fake.spaces[crossing.to]?.firstIndex(of: crossing.space) else {
                Issue.record("space vanished before its turn"); return
            }
            var current = crossing
            current.toDesktop = index + 1
            _ = try #require(await DesktopRevert.run(current, contents: fake.contents,
                                                     windowSpaces: fake.location, world: fake.world))
        }
        let lg = try #require(fake.spaces["external"])
        #expect(lg.count == 3)
        #expect(fake.location[101] == lg[0] && fake.location[201] == lg[1] && fake.location[301] == lg[2])
    }

    // MARK: - result() ve reverse()

    @Test func resultFailedWhenNothingCreated() {
        var out = PlanExecutor.Outcome()
        out.spaceMap = [10: 70]
        #expect(DesktopRevert.result(out, crossing: okuma) == .failed)
        out.created = 1
        out.spaceMap = [:]
        #expect(DesktopRevert.result(out, crossing: okuma) == .failed)
    }

    /// "Böyle kalsın" iki kez çevrilince özgün geçişe (yeni space kimliğiyle) döner.
    @Test func e4_4_reverseOfReverseRoundTrips() {
        let back = DesktopRevert.reverse(DesktopRevert.reverse(okuma, newSpace: 70), newSpace: 10)
        #expect(back == okuma)
    }

    // MARK: - E5 · Ad, plan, pin

    private func pinsDoc() -> Document {
        var notes = V6.rule("Notes", docked: V6.e(2))
        notes.dockedNext = [V6.at("external-2", 3), V6.b(1)]
        let mail = V6.rule("Mail", docked: V6.at("external-2", 3), undocked: V6.b(2))
        let safari = V6.rule("Safari", docked: V6.at("external", 1, name: "OKUMA"))
        return V6.document(
            rules: [notes, mail, safari],
            names: [DesktopName(id: "OKUMA", name: "Okuma", space: 10)],
            plans: DesktopPlans(docked: ["external": ["OKUMA", "", ""], "external-2": ["", "", ""],
                                         "builtin": ["", ""]],
                                undocked: ["builtin": ["", ""]]))
    }

    /// E5.3: izleme + geri alma sonunda sayı pinleri (sıralı yer listeleri dahil) aynen kalır.
    @Test func e5_3_placeListsUntouchedByFollowAndRevert() async throws {
        var d = pinsDoc()
        let original = d
        let afterMove: [String: [UInt64]] = ["builtin": [1, 2], "external": [20, 30],
                                             "external-2": [40, 10, 50, 60]]
        d.followMissionControl(before: before, after: afterMove, mode: .docked)
        #expect(d.rules == original.rules)            // izleme de pinlere dokunmaz
        let fake = FakeDesktops(spaces: afterMove, location: [101: 10, 201: 20])
        let out = try #require(await DesktopRevert.run(okuma, contents: fake.contents,
                                                       windowSpaces: fake.location, world: fake.world))
        d.applySpaceMap(out.spaceMap)
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        #expect(d.rules == original.rules)
        #expect(d.rules[0].places(.docked) == original.rules[0].places(.docked))
        #expect(d.plans == original.plans)
    }

    /// returnPlanEntry yalnız verilen modun planına yazar; öbür kurulum aynı kalır.
    @Test func e5_returnPlanEntryLeavesOtherModeAlone() {
        var d = pinsDoc()
        let undockedBefore = d.plans.undocked
        d.followMissionControl(before: before, after: ["builtin": [1, 2], "external": [20, 30],
                                                       "external-2": [40, 10, 50, 60]], mode: .docked)
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        #expect(d.plans.undocked == undockedBefore)
    }

    /// Kaynak ile hedef aynı rol ya da sıra < 1: hiçbir şey yazılmaz.
    @Test func e5_returnPlanEntryGuards() {
        var d = pinsDoc()
        let original = d.plans
        d.returnPlanEntry(from: "external", desktop: 1, to: "external", at: 1, mode: .docked)
        d.returnPlanEntry(from: "external", desktop: 1, to: "external-2", at: 0, mode: .docked)
        #expect(d.plans == original)
    }

    /// Plan girdisi kaynakta yoksa (kısa liste) hedefe "" eklenir, kaynak bozulmaz.
    @Test func e5_returnPlanEntryWithShortSourceInsertsBlank() {
        var d = pinsDoc()
        d.plans.set(["A"], .docked, "external-2")
        d.returnPlanEntry(from: "external-2", desktop: 3, to: "external", at: 2, mode: .docked)
        #expect(d.plans.entries(.docked, "external-2") == ["A"])
        #expect(d.plans.entries(.docked, "external") == ["OKUMA", "", "", ""])
    }

    /// Hedef plan geri koyma sırasından kısaysa boşlukla doldurulur.
    @Test func e5_returnPlanEntryPadsShortTarget() {
        var d = pinsDoc()
        d.plans.set(["X"], .docked, "external")
        d.plans.set(["", "OKUMA"], .docked, "external-2")
        d.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 3, mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["X", "", "OKUMA"])
        #expect(d.plans.entries(.docked, "external-2") == [""])
    }

    /// R5: adlar tek seferde (eşzamanlı) eşlenir; zincir 20→30, 30→N çift kaymaz.
    @Test func e5_4_applySpaceMapIsSimultaneousNotChained() {
        var d = pinsDoc()
        d.names = [DesktopName(id: "A", name: "A", space: 20), DesktopName(id: "B", name: "B", space: 30)]
        d.applySpaceMap([20: 30, 30: 9001])
        #expect(d.nameRecord("A")?.space == 30)
        #expect(d.nameRecord("B")?.space == 9001)
    }

    /// E5.1: bütün profillerde ad yeni space'e bağlanır.
    @Test func e5_1_nameRebindsInEveryProfile() {
        var d = pinsDoc()
        _ = d.duplicateProfile(d.activeProfileID, named: "Copy")
        d.applySpaceMap([10: 9001])
        d.syncActiveProfile()
        for profile in d.profiles {
            #expect(profile.names.first { $0.id == "OKUMA" }?.space == 9001)
        }
    }

    /// Adsız masaüstü geri alınınca plan girdisi "" olarak eski yerine döner (planlar eşit).
    @Test func e5_2_unnamedDesktopRoundTripsPlan() {
        var d = pinsDoc()
        d.plans.set(["OKUMA", "", ""], .docked, "external")
        let crossing = DesktopRevert.Crossing(space: 20, from: "external", fromDesktop: 2,
                                              to: "external-2", toDesktop: 1)
        let original = d.plans
        let afterMove: [String: [UInt64]] = ["builtin": [1, 2], "external": [10, 30],
                                             "external-2": [20, 40, 50, 60]]
        let beforeMove: [String: [UInt64]] = ["builtin": [1, 2], "external": [10, 20, 30],
                                              "external-2": [40, 50, 60]]
        d.followMissionControl(before: beforeMove, after: afterMove, mode: .docked)
        d.returnPlanEntry(from: crossing.to, desktop: 1, to: crossing.from, at: crossing.fromDesktop, mode: .docked)
        #expect(d.plans == original)
    }

    /// Ayar kodlaması: üç değer de gidiş-dönüş; bilinmeyen değer varsayılana düşer.
    @Test func e6_1_settingRoundTripAndUnknownFallsBack() throws {
        for setting in DesktopRevert.Setting.allCases {
            var d = Document()
            d.missionControlMoves = setting
            let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
            #expect(back.missionControlMoves == setting)
        }
        var d = Document()
        d.missionControlMoves = .ask
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        json["missionControlMoves"] = "garbage"
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(Document.self, from: data).missionControlMoves == .revert)
    }

    /// Oturum pinleri belge işlemlerinden etkilenmez: pinli pencerelerin hedefi geri almada değişmez.
    @Test func e5_3_sessionPinsAreNotDocumentState() {
        let h = RouterHarness(rules: [])
        h.titles = [7: "w"]
        h.pin(7, V6.e(2))
        let pinned = h.router.sessionPins[7]
        h.store.document.followMissionControl(before: before,
                                              after: ["builtin": [1, 2], "external": [20, 30],
                                                      "external-2": [40, 10, 50, 60]], mode: .docked)
        h.store.document.returnPlanEntry(from: "external-2", desktop: 2, to: "external", at: 1, mode: .docked)
        #expect(h.router.sessionPins[7] == pinned)
    }
}
