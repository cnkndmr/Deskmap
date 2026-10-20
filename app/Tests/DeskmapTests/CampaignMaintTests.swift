import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya (maint): iç bakım işlemleri sıralı yer listesini (Rule.docked +
/// dockedNext) her yerde uyguluyor mu. Tablo B (silme 8/9/14, ad kaldırma 13,
/// taşıma 15/16) ve Tablo D (sıralı yerler) sözleşmesi; masaüstü silme,
/// ad silme, plan satırı silme, taşıma, hayalet geri yükleme, şema 6
/// geçişi, `desktopBlockingRemoval`, `backfillingFixed`,
/// `splittingSharedState`.
@MainActor
struct CampaignMaintTests {

    // MARK: Yardımcılar

    private func at(_ screen: String, _ desktop: Int, name: String? = nil) -> Destination {
        Destination(screen: screen, desktop: desktop, nameID: name)
    }

    private func list(_ screen: String, _ desktop: Int) -> String { "\(screen)·\(desktop)" }

    private func shown(_ rule: Rule?, _ mode: Mode = .docked) -> [String] {
        (rule?.places(mode) ?? []).map { list($0.screen, $0.desktop) }
    }

    private func ordered(_ id: String, _ places: [Destination], undocked: Destination? = nil) -> Rule {
        var rule = Rule(id: id, appName: id, bundleID: "b.\(id)", tokens: [])
        rule.setPlaces(places, mode: .docked)
        rule.undocked = undocked
        return rule
    }

    private func document(_ rules: [Rule]) -> Document {
        var d = Document()
        d.rules = rules
        d.syncActiveProfile()
        return d
    }

    /// Etkin profil + ikinci profil (kendi kuralları).
    private func twoProfiles(_ active: [Rule], _ other: [Rule]) -> (Document, String, String) {
        var d = document(active)
        let first = d.activeProfileID
        let second = d.addProfile(named: "B", activate: false).id
        let i = d.profiles.firstIndex { $0.id == second }!
        d.profiles[i].rules = other
        return (d, first, second)
    }

    private func profileRule(_ d: Document, _ profile: String, _ id: String) -> Rule? {
        d.profiles.first { $0.id == profile }?.rules.first { $0.id == id }
    }

    // MARK: - Masaüstü silme: sıralı listenin her yeri, her profil (B8/B9)

    @Test func b8_deleteDesktopShiftsEveryPlaceOfTheOrderedList() {
        // Silinen ext·2'nin ardındakiler (aynı ekranda ikinci yer dahil) bir yukarı kayar.
        var d = document([ordered("r", [at("ext", 3), at("ext2", 2)]),
                          ordered("s", [at("ext2", 4), at("ext", 5)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        #expect(ghost == nil)
        #expect(shown(d.rule("r")) == ["ext·2", "ext2·2"])
        #expect(shown(d.rule("s")) == ["ext2·4", "ext·4"])
    }

    @Test func b8_deleteDesktopHitsEveryProfileWithItsOwnPins() {
        let (start, a, b) = twoProfiles([ordered("r", [at("ext", 2)])],
                                        [ordered("r", [at("ext2", 1), at("ext", 2)])])
        var d = start
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        #expect(d.rule("r") == nil || d.rule("r")?.places(.docked).isEmpty == true || d.rules.isEmpty)
        #expect(ghost?.pins.map(\.profileID) == [a])
        #expect(shown(profileRule(d, b, "r")) == ["ext2·1"])
        let other = d.profiles.first { $0.id == b }?.ghostDesktops.first
        #expect(other?.pins.map(\.profileID) == [b])
        #expect(other?.pins.first?.order == 1)
    }

    @Test func b8_ghostRestoreStaysInItsOwnProfile() {
        let (start, a, b) = twoProfiles([ordered("r", [at("ext", 2)])],
                                        [ordered("r", [at("ext", 2)])])
        var d = start
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        d.restoreGhost(ghost!.id, desktop: 4)
        #expect(shown(d.rule("r")) == ["ext·4"])
        #expect(profileRule(d, b, "r") == nil)
        #expect(d.profiles.first { $0.id == b }?.ghostDesktops.count == 1)
        _ = a
    }

    @Test func b8_deletingFirstPlaceMakesTheNextOneFirstAndRestoreBringsItBack() {
        var d = document([ordered("r", [at("ext", 2), at("ext2", 1), at("ext3", 1)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        #expect(d.rule("r")?.docked == at("ext2", 1))
        #expect(d.rule("r")?.dockedNext == [at("ext3", 1)])
        d.restoreGhost(ghost!.id, desktop: 2)
        #expect(shown(d.rule("r")) == ["ext·2", "ext2·1", "ext3·1"])
    }

    @Test func b8_middlePlaceComesBackInTheMiddle() {
        var d = document([ordered("r", [at("ext", 1), at("ext2", 3), at("ext3", 1)])])
        let ghost = d.recordDeletion(space: nil, role: "ext2", desktop: 3, mode: .docked)
        #expect(ghost?.pins.first?.order == 1)
        #expect(shown(d.rule("r")) == ["ext·1", "ext3·1"])
        d.restoreGhost(ghost!.id, desktop: 5)
        #expect(shown(d.rule("r")) == ["ext·1", "ext2·5", "ext3·1"])
    }

    @Test func b8_restoreDoesNotOverwriteAMonitorThatGotANewPlaceMeanwhile() {
        var d = document([ordered("r", [at("ext", 2), at("ext2", 1)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        // Kullanıcı bu arada ext monitörüne başka bir yer verdi.
        d.rules[0].place(at("ext", 7), mode: .docked, connected: ["ext", "ext2"])
        d.restoreGhost(ghost!.id, desktop: 3)
        #expect(d.rules[0].places(.docked).filter { $0.screen == "ext" }.map(\.desktop) == [7])
    }

    @Test func b8_ghostPinOrderBeyondTheListAppends() {
        var d = document([ordered("r", [at("ext2", 1)])])
        let pin = GhostDesktop.Pin(profileID: d.activeProfileID, mode: .docked, rule: d.rules[0],
                                   destination: at("ext", 2), order: 9)
        d.applyGhostPins([pin]) { $0.destination }
        #expect(shown(d.rule("r")) == ["ext2·1", "ext·2"])
    }

    @Test func b8_oldGhostWithoutOrderOnlyFillsAnEmptyList() {
        // Eski hayalette order yok: kuralın o modda yeri varsa dokunulmaz.
        var d = document([ordered("keeps", [at("ext2", 1)]), ordered("empty", [])])
        let id = d.activeProfileID
        let old = [GhostDesktop.Pin(profileID: id, mode: .docked, rule: d.rules[0], destination: at("ext", 2)),
                   GhostDesktop.Pin(profileID: id, mode: .docked, rule: d.rules[1], destination: at("ext", 2))]
        d.applyGhostPins(old) { $0.destination }
        #expect(shown(d.rule("keeps")) == ["ext2·1"])
        #expect(shown(d.rule("empty")) == ["ext·2"])
    }

    @Test func b8_oldGhostJSONWithoutOrderDecodes() throws {
        var d = document([ordered("r", [at("ext", 2)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        var data = try JSONEncoder().encode(ghost)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var pins = object["pins"] as! [[String: Any]]
        pins[0].removeValue(forKey: "order")
        object["pins"] = pins
        data = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(GhostDesktop.self, from: data)
        #expect(back.pins.first?.order == nil)
        d.applyGhostPins(back.pins) { $0.destination }
        #expect(shown(d.rule("r")) == ["ext·2"])
    }

    @Test func b8_deletionOfAnUnpinnedDesktopLeavesNoGhostButShiftsLaterPlaces() {
        var d = document([ordered("r", [at("ext", 4)])])
        let before = d.ghostDesktops
        _ = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        #expect(d.ghostDesktops == before)
        #expect(shown(d.rule("r")) == ["ext·3"])
    }

    @Test func b9_laptopDeletionShiftsBothModesIncludingSecondaryPlaces() {
        var d = document([ordered("r", [at("ext", 1), at("builtin", 4)], undocked: at("builtin", 3)),
                          ordered("s", [at("builtin", 2), at("builtin", 5)], undocked: at("builtin", 2))])
        let ghost = d.recordDeletion(space: nil, role: "builtin", desktop: 2, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·1", "builtin·3"])
        #expect(shown(d.rule("r"), .undocked) == ["builtin·2"])
        // s: ilk yer silindi (ikinci yer ilk olur ve kayar), undocked yeri silindi.
        #expect(shown(d.rule("s")) == ["builtin·4"])
        #expect(d.rule("s")?.undocked == nil)
        #expect(Set(ghost?.pins.map(\.mode) ?? []) == [.docked, .undocked])
    }

    @Test func b9_monitorDeletionNeverTouchesLaptopPlans() {
        var d = document([ordered("r", [at("ext", 3)], undocked: at("builtin", 3))])
        _ = d.recordDeletion(space: nil, role: "ext", desktop: 1, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·2"])
        #expect(d.rule("r")?.undocked == at("builtin", 3))
    }

    @Test func b9_laptopGhostRestoresPerModeAndKeepsTheRest() {
        var d = document([ordered("r", [at("ext", 1), at("builtin", 2)], undocked: at("builtin", 2))])
        let ghost = d.recordDeletion(space: nil, role: "builtin", desktop: 2, mode: .docked)
        #expect(d.rule("r")?.undocked == nil)
        d.restoreGhost(ghost!.id, desktop: 6, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·1", "builtin·6"])
        #expect(d.rule("r")?.undocked == nil)
        let rest = d.ghostDesktops.first
        #expect(rest?.pins.map(\.mode) == [.undocked])
        d.restoreGhost(rest!.id, desktop: 6, mode: .undocked)
        #expect(d.rule("r")?.undocked == at("builtin", 6))
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func b9_ruleLostWithItsOnlyPlaceIsRecreatedFromTheGhost() {
        var d = document([ordered("only", [at("ext", 2)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        #expect(d.rules.isEmpty)
        d.restoreGhost(ghost!.id, desktop: 2)
        #expect(d.rule("only")?.places(.docked) == [at("ext", 2)])
    }

    // MARK: - Adlı masaüstü silme / ad pinleri

    @Test func b8_namedDesktopDeletionKeepsNamePinOrderAndRestoresItsPlace() {
        var d = document([ordered("r", [at("ext2", 1), at("ext", 2, name: "N")])])
        d.names = [DesktopName(id: "N", name: "Nova", space: 77)]
        d.plans.set(["", "N"], .docked, "ext")
        d.syncActiveProfile()
        let ghost = d.recordDeletion(space: 77, role: "ext", desktop: 2, mode: .docked)
        #expect(ghost?.name == "Nova")
        #expect(d.names.isEmpty)
        #expect(d.plans.entries(.docked, "ext") == [""])
        #expect(shown(d.rule("r")) == ["ext2·1"])
        #expect(ghost?.pins.first?.order == 1)
        // Aynı adı yeniden veren, hayaleti tüketir; ikincil yer ikincil döner.
        d.setDesktopName("Nova", screen: "ext", desktop: 3, mode: .docked)
        #expect(d.ghostDesktops.isEmpty)
        let places = d.rule("r")?.places(.docked)
        #expect(places?.count == 2)
        #expect(places?.first == at("ext2", 1))
        #expect(places?.last?.nameID != nil && places?.last?.desktop == 3)
    }

    @Test func b14_deleteNameKeepsOrderOfPrimaryPin() {
        var d = document([ordered("r", [at("ext", 2, name: "N"), at("ext2", 1)])])
        d.names = [DesktopName(id: "N", name: "Nova", space: nil)]
        d.plans.set(["", "N"], .docked, "ext")
        d.syncActiveProfile()
        let ghost = d.deleteName("N")
        #expect(ghost?.pins.first?.order == 0)
        #expect(d.rule("r")?.docked == at("ext2", 1))
        #expect(d.names.isEmpty)
        d.setDesktopName("nova", screen: "ext", desktop: 4, mode: .docked)
        let places = d.rule("r")?.places(.docked) ?? []
        #expect(places.count == 2)
        #expect(places.first?.nameID != nil)
        #expect(places.last == at("ext2", 1))
    }

    @Test func b14_deleteNameWithPinsOnBothModesStoresBoth() {
        var d = document([ordered("r", [at("builtin", 2, name: "N")], undocked: at("builtin", 2, name: "N"))])
        d.names = [DesktopName(id: "N", name: "Nova", space: nil)]
        d.plans.set(["", "N"], .docked, "builtin")
        d.plans.set(["", "N"], .undocked, "builtin")
        d.syncActiveProfile()
        let ghost = d.deleteName("N")
        #expect(Set(ghost?.pins.map(\.mode) ?? []) == [.docked, .undocked])
        #expect(d.rules.isEmpty)
        #expect(d.plans.entries(.docked, "builtin") == [""] && d.plans.entries(.undocked, "builtin") == [""])
    }

    @Test func b14_deleteUnknownNameChangesNothing() {
        var d = document([ordered("r", [at("ext", 2)])])
        let before = d
        #expect(d.deleteName("missing") == nil)
        #expect(d == before)
    }

    @Test func b14_deleteNameLeavesNumberPinsOnTheSameDesktopAlone() {
        var d = document([ordered("named", [at("ext", 2, name: "N")]), ordered("numbered", [at("ext", 2)])])
        d.names = [DesktopName(id: "N", name: "Nova", space: nil)]
        d.plans.set(["", "N"], .docked, "ext")
        d.syncActiveProfile()
        _ = d.deleteName("N")
        #expect(d.rule("named") == nil)
        #expect(shown(d.rule("numbered")) == ["ext·2"])
    }

    // MARK: - removeName

    @Test func b13_removeNameTurnsNamePinsIntoNumberPinsInPlaceForEveryPlace() {
        var d = document([ordered("r", [at("ext2", 1), at("ext", 3, name: "N")],
                                  undocked: at("builtin", 2, name: "N"))])
        d.names = [DesktopName(id: "N", name: "Nova", space: 5), DesktopName(id: "M", name: "Mira", space: 6)]
        d.plans.set(["M", "", "N"], .docked, "ext")
        d.plans.set(["", "N"], .undocked, "builtin")
        d.syncActiveProfile()
        d.removeName("N")
        #expect(d.rule("r")?.places(.docked) == [at("ext2", 1), at("ext", 3)])
        #expect(d.rule("r")?.undocked == at("builtin", 2))
        // Plan satırları çökmez: Mira yerinde kalır, N'nin yeri boşalır.
        #expect(d.plans.entries(.docked, "ext") == ["M", "", ""])
        #expect(d.names.map(\.id) == ["M"])
    }

    @Test func b13_removeNameTouchesOnlyTheActiveProfile() {
        var (d, _, other) = twoProfiles([ordered("r", [at("ext", 2, name: "N")])],
                                        [ordered("r", [at("ext", 2, name: "N")])])
        d.names = [DesktopName(id: "N", name: "Nova", space: 5)]
        d.syncActiveProfile()
        d.removeName("N")
        #expect(d.rule("r")?.docked?.nameID == nil)
        #expect(profileRule(d, other, "r")?.docked?.nameID == "N")
    }

    @Test func b13_nameGivenToADesktopConvertsOnlyPinsOfThatScreenInEverySlot() {
        var d = document([ordered("a", [at("ext2", 2), at("ext", 2)]), ordered("b", [at("ext", 3)])])
        d.setDesktopName("Nova", screen: "ext", desktop: 2, mode: .docked)
        let id = d.names.first?.id
        #expect(d.rule("a")?.dockedNext.first?.nameID == id)
        #expect(d.rule("a")?.docked?.nameID == nil)
        #expect(d.rule("b")?.docked?.nameID == nil)
    }

    // MARK: - removePlanEntry

    @Test func removePlanEntry_secondaryPlaceShiftsAndOtherModeIsUntouched() {
        var d = document([ordered("r", [at("builtin", 1), at("builtin", 3)], undocked: at("builtin", 3))])
        // Docked'a ikinci builtin yeri geçersiz sayılmasın diye ekran başına tek yer: ext ile dene.
        d.rules = [ordered("r", [at("ext", 1), at("ext2", 3)], undocked: at("ext", 3))]
        d.plans.set(["", "", ""], .undocked, "ext")
        d.plans.set(["", "", ""], .docked, "ext2")
        _ = d.removePlanEntry(screen: "ext2", desktop: 1, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·1", "ext2·2"])
        #expect(d.rule("r")?.undocked == at("ext", 3))
    }

    @Test func removePlanEntry_liveNamedEntryKeepsTheNameAndOtherPlan() {
        var d = document([ordered("r", [at("builtin", 2, name: "N")], undocked: at("builtin", 2, name: "N"))])
        d.names = [DesktopName(id: "N", name: "Nova", space: 9)]
        d.plans.set(["", "N"], .docked, "builtin")
        d.plans.set(["", "N"], .undocked, "builtin")
        d.syncActiveProfile()
        let ghost = d.removePlanEntry(screen: "builtin", desktop: 2, mode: .undocked)
        #expect(ghost == nil)
        #expect(d.names.count == 1)
        #expect(d.plans.entries(.undocked, "builtin") == [""])
        #expect(d.plans.entries(.docked, "builtin") == ["", "N"])
        #expect(d.rule("r")?.docked?.nameID == "N" && d.rule("r")?.undocked?.nameID == "N")
    }

    @Test func removePlanEntry_unplacedNameRowDeletesTheNameWithItsPins() {
        var d = document([ordered("r", [at("ext2", 1), at("ext", 2, name: "N")])])
        d.names = [DesktopName(id: "N", name: "Nova", space: nil)]
        d.plans.set(["", "N"], .docked, "ext")
        d.syncActiveProfile()
        let ghost = d.removePlanEntry(screen: "ext", desktop: 2, mode: .docked)
        #expect(ghost?.name == "Nova" && ghost?.pins.first?.order == 1)
        #expect(d.names.isEmpty)
        #expect(shown(d.rule("r")) == ["ext2·1"])
    }

    @Test func removePlanEntry_pastThePlanStillGhostsThePinAndShiftsTheRest() {
        var d = document([ordered("r", [at("ext", 5)]), ordered("s", [at("ext", 6)])])
        let ghost = d.removePlanEntry(screen: "ext", desktop: 5, mode: .docked)
        #expect(ghost?.pins.map(\.rule.id) == ["r"])
        #expect(shown(d.rule("s")) == ["ext·5"])
        #expect(d.plans.entries(.docked, "ext").isEmpty)
    }

    // MARK: - moveDesktop / moveDesktopAcross

    @Test func b15_moveDesktopRemapsEveryPlaceOfTheListAndSkipsNamePinsAndOtherScreens() {
        var d = document([ordered("r", [at("ext", 1), at("ext2", 3)]),
                          ordered("n", [at("ext", 2, name: "N")]), ordered("o", [at("ext3", 1)])])
        d.moveDesktop(on: "ext2", from: 3, to: 1, count: 3, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·1", "ext2·1"])
        d.moveDesktop(on: "ext", from: 1, to: 2, count: 3, mode: .docked)
        #expect(shown(d.rule("r")) == ["ext·2", "ext2·1"])
        #expect(d.rule("n")?.docked == at("ext", 2, name: "N"))
        #expect(shown(d.rule("o")) == ["ext3·1"])
    }

    @Test func b15_moveDesktopSharedLaptopMovesBothModesButMonitorOnlyOneMode() {
        var d = document([ordered("r", [at("builtin", 1)], undocked: at("builtin", 1)),
                          ordered("m", [at("ext", 1)], undocked: at("ext", 1))])
        d.moveDesktop(on: "builtin", from: 1, to: 3, count: 3, mode: .docked, sharedLaptop: true)
        #expect(d.rule("r")?.docked == at("builtin", 3) && d.rule("r")?.undocked == at("builtin", 3))
        d.moveDesktop(on: "ext", from: 1, to: 2, count: 2, mode: .docked, sharedLaptop: true)
        #expect(d.rule("m")?.docked == at("ext", 2))
        #expect(d.rule("m")?.undocked == at("ext", 1))
    }

    @Test func b15_moveDesktopWithoutLiveSpacesOnlyTouchesTheActiveProfile() {
        let rule = ordered("r", [at("ext", 1)])
        var (d, _, other) = twoProfiles([rule], [rule])
        d.plans.set(["A", "B"], .docked, "ext")
        d.syncActiveProfile()
        let otherPlan = d.profiles.first { $0.id == other }!.plans
        d.moveDesktop(on: "ext", from: 1, to: 2, count: 2, mode: .docked)
        #expect(d.rule("r")?.docked == at("ext", 2))
        #expect(profileRule(d, other, "r")?.docked == at("ext", 1))
        #expect(d.plans.entries(.docked, "ext") == ["B", "A"])
        #expect(d.profiles.first { $0.id == other }!.plans == otherPlan)
    }

    @Test func b15_moveDesktopPlanPermutesWithTheSameMappingAsPins() {
        var d = document([ordered("r", [at("ext", 3)])])
        d.plans.set(["A", "", "B"], .docked, "ext")
        d.syncActiveProfile()
        d.moveDesktop(on: "ext", from: 1, to: 3, count: 3, mode: .docked)
        #expect(d.plans.entries(.docked, "ext") == ["", "B", "A"])
        #expect(d.rule("r")?.docked == at("ext", 2))
    }

    @Test func b15_moveDesktopToItselfDoesNothing() {
        var d = document([ordered("r", [at("ext", 2)])])
        d.plans.set(["A", "B"], .docked, "ext")
        let before = d
        d.moveDesktop(on: "ext", from: 2, to: 2, count: 2, mode: .docked)
        #expect(d == before)
    }

    @Test func b16_moveAcrossKeepsBothPlacesWhenItCreatesTwoOnOneScreen() {
        // Safari: ext·2 birinci, ext2·1 ikinci. ext·2'yi ext2'nin 1. sırasına taşı.
        var d = document([ordered("r", [at("ext", 2), at("ext2", 1)])])
        d.moveDesktopAcross(from: "ext", desktop: 2, to: "ext2", at: 1, toCount: 2, mode: .docked)
        #expect(d.rule("r")?.places(.docked).count == 2)
        #expect(shown(d.rule("r")) == ["ext2·1", "ext2·2"])
    }

    @Test func b16_aTwoPlacesOnOneScreenListStillResolvesToItsFirstPlace() {
        let desk = MultiMonitorDesk(rules: [ordered("r", [at("external", 2), at("external-2", 1)])])
        var document = desk.store.document
        document.moveDesktopAcross(from: "external", desktop: 2, to: "external-2", at: 1, toCount: 3,
                                   mode: .docked)
        desk.store.document = document
        #expect(desk.place("r") == "LG · 1")
    }

    @Test func b16_moveAcrossShiftsSecondaryPlacesOnSourceAndTarget() {
        var d = document([ordered("a", [at("ext", 3), at("ext3", 1)]),
                          ordered("b", [at("ext2", 1), at("ext", 2)]),
                          ordered("c", [at("ext2", 2)])])
        d.moveDesktopAcross(from: "ext", desktop: 2, to: "ext2", at: 2, toCount: 2, mode: .docked)
        #expect(shown(d.rule("a")) == ["ext·2", "ext3·1"])
        #expect(shown(d.rule("b")) == ["ext2·1", "ext2·2"])
        #expect(shown(d.rule("c")) == ["ext2·3"])
    }

    @Test func b16_moveAcrossWithoutSpaceMapStaysInTheActiveProfileAndPlan() {
        let rule = ordered("r", [at("ext", 1)])
        var (d, _, other) = twoProfiles([rule], [rule])
        d.plans.set(["A"], .docked, "ext")
        d.syncActiveProfile()
        let otherPlans = d.profiles.first { $0.id == other }!.plans
        d.moveDesktopAcross(from: "ext", desktop: 1, to: "ext2", at: 1, toCount: 0, mode: .docked)
        #expect(d.rule("r")?.docked == at("ext2", 1))
        #expect(profileRule(d, other, "r")?.docked == at("ext", 1))
        #expect(d.plans.entries(.docked, "ext2") == ["A"] && d.plans.entries(.docked, "ext").isEmpty)
        #expect(d.profiles.first { $0.id == other }!.plans == otherPlans)
    }

    @Test func b16_moveAcrossWithSpaceMapMovesEveryProfileAndItsPlan() {
        let rule = ordered("r", [at("ext", 1)])
        var (d, _, other) = twoProfiles([rule], [rule])
        d.plans.set(["A"], .docked, "ext")
        let i = d.profiles.firstIndex { $0.id == other }!
        d.profiles[i].plans.set(["Z"], .docked, "ext")
        d.syncActiveProfile()
        d.moveDesktopAcross(from: "ext", desktop: 1, to: "ext2", at: 1, toCount: 0, mode: .docked,
                            spaceMap: [10: 20])
        #expect(profileRule(d, other, "r")?.docked == at("ext2", 1))
        #expect(d.profiles.first { $0.id == other }!.plans.entries(.docked, "ext2") == ["Z"])
    }

    @Test func b16_moveAcrossSameScreenOrInvalidIndexIsANoOp() {
        var d = document([ordered("r", [at("ext", 2), at("ext2", 1)])])
        d.plans.set(["A", "B"], .docked, "ext")
        let before = d
        d.moveDesktopAcross(from: "ext", desktop: 2, to: "ext", at: 1, toCount: 2, mode: .docked)
        d.moveDesktopAcross(from: "ext", desktop: 0, to: "ext2", at: 1, toCount: 2, mode: .docked)
        d.moveDesktopAcross(from: "ext", desktop: 1, to: "ext2", at: 0, toCount: 2, mode: .docked)
        #expect(d == before)
    }

    @Test func b16_moveAcrossPadsAShortTargetPlanToTheDropIndex() {
        var d = document([ordered("r", [at("ext", 1)])])
        d.plans.set(["A"], .docked, "ext")
        d.moveDesktopAcross(from: "ext", desktop: 1, to: "ext2", at: 3, toCount: 2, mode: .docked)
        #expect(d.plans.entries(.docked, "ext2") == ["", "", "A"])
    }

    // MARK: - Hayalet geri yükleme: adsız, ikincil yer

    @Test func b8_unnamedGhostRestoresSecondaryPlaceAsSecondary() {
        var d = document([ordered("r", [at("ext2", 1), at("ext", 2)])])
        let ghost = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        d.restoreGhost(ghost!.id, desktop: 3)
        #expect(shown(d.rule("r")) == ["ext2·1", "ext·3"])
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func b8_secondGhostOfTheSameRuleAndDesktopKeepsEachOrder() {
        // İki ayrı silme: önce ext·2 (birinci), sonra ext2·1 (yeni birinci).
        var d = document([ordered("r", [at("ext", 2), at("ext2", 1)])])
        let g1 = d.recordDeletion(space: nil, role: "ext", desktop: 2, mode: .docked)
        let g2 = d.recordDeletion(space: nil, role: "ext2", desktop: 1, mode: .docked)
        #expect(d.rules.isEmpty)
        d.restoreGhost(g2!.id, desktop: 1)
        d.restoreGhost(g1!.id, desktop: 2)
        #expect(Set(shown(d.rule("r"))) == ["ext·2", "ext2·1"])
    }

    // MARK: - MigrationV6 + dockedNext

    private func legacyDocument(rules: [Rule], ghosts: [GhostDesktop] = []) -> Document {
        var d = Document()
        d.profiles[0].rules = rules
        d.profiles[0].ghostDesktops = ghosts
        d.profiles[0].legacy = LegacyNames(desktopNames: ["docked|ext": ["3": "N"]],
                                           desktopNameSpaces: ["docked|ext": ["3": 30]])
        d.loadProfileState(d.profiles[0])
        d.fileVersion = 5
        return d
    }

    @Test func migrationConvertsEveryPlaceOfAnOrderedList() {
        let d = legacyDocument(rules: [ordered("r", [at("builtin", 1), at("ext", 3)])])
        let result = MigrationV6.migrate(d, evidence: nil)
        let id = result.document.names.first?.id
        #expect(result.document.rule("r")?.dockedNext.first?.nameID == id)
        #expect(result.document.rule("r")?.docked?.nameID == nil)
    }

    @Test func migrationJunkGhostReversalShiftsSecondaryPlacesToo() {
        let incident = Date(timeIntervalSinceReferenceDate: 813513160)
        let ghost = GhostDesktop(screen: "ext", name: "N", desktop: 1, deletedAt: incident)
        let d = legacyDocument(rules: [ordered("left", [at("builtin", 1), at("ext", 2)])], ghosts: [ghost])
        let result = MigrationV6.migrate(d, evidence: nil)
        #expect(shown(result.document.rule("left")) == ["builtin·1", "ext·3"])
        #expect(result.document.ghostDesktops.isEmpty)
    }

    @Test func migrationJunkGhostPinNeverOverwritesAnExistingPlace() {
        let incident = Date(timeIntervalSinceReferenceDate: 813513160)
        let rule = ordered("r", [at("builtin", 1)])
        let pin = GhostDesktop.Pin(profileID: "x", mode: .docked, rule: rule, destination: at("ext", 1))
        let ghost = GhostDesktop(screen: "ext", name: "N", desktop: 1, deletedAt: incident, pins: [pin])
        let d = legacyDocument(rules: [rule], ghosts: [ghost])
        let result = MigrationV6.migrate(d, evidence: nil)
        #expect(shown(result.document.rule("r")) == ["builtin·1"])
        #expect(result.report.profiles.first?.pinsRestored == 0)
    }

    @Test func migrationBuildsPlanLengthFromSecondaryPlaces() {
        var d = Document()
        d.profiles[0].rules = [ordered("r", [at("builtin", 1), at("ext", 4)])]
        d.profiles[0].legacy = LegacyNames(plannedDesktops: [:])
        d.loadProfileState(d.profiles[0])
        d.fileVersion = 5
        // Eski tabloda ekran adı yoksa plan yazılmaz; ad olan ekran için uzunluk ikincil yerden gelir.
        d.profiles[0].legacy = LegacyNames(desktopNames: ["docked|ext": ["1": "A"]],
                                           desktopNameSpaces: ["docked|ext": ["1": 11]])
        let result = MigrationV6.migrate(d, evidence: nil)
        #expect(result.document.plans.entries(.docked, "ext").count == 4)
    }

    // MARK: - desktopBlockingRemoval

    @Test func blockingRemovalSeesSecondaryPlacesOfEveryProfileAndSessionPins() {
        let (d, _, _) = twoProfiles([ordered("r", [at("ext2", 1), at("ext", 2)])],
                                    [ordered("s", [at("builtin", 1), at("ext", 5)])])
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .docked, keeping: 3, total: 6) == 5)
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .docked, keeping: 5, total: 6) == nil)
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .docked, keeping: 3, total: 6,
                                         sessionPins: [at("ext", 6)]) == 6)
    }

    @Test func blockingRemovalIgnoresTheOtherModeAndOtherScreens() {
        let d = document([ordered("r", [at("ext", 1)], undocked: at("ext", 9)),
                          ordered("s", [at("ext2", 8)])])
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .docked, keeping: 2, total: 9) == nil)
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .undocked, keeping: 2, total: 9) == 9)
    }

    @Test func blockingRemovalReportsPinsBeyondTheLiveTotal() {
        let d = document([ordered("r", [at("builtin", 1), at("ext", 8)])])
        #expect(d.desktopBlockingRemoval(on: "ext", mode: .docked, keeping: 3, total: 4) == 8)
    }

    // MARK: - backfillingFixed

    private func fixedLayout() -> WindowLayout {
        WindowLayout(fixed: .init(width: 855, height: 1074, anchor: .left))
    }

    @Test func backfillFillsSecondaryAndLaptopPlacesBySelectedScreenSize() {
        let screens = [KnownScreen(id: "ext", name: "E", aspect: 1.78, visibleWidth: 1710, visibleHeight: 1074),
                       KnownScreen(id: "builtin", name: "B", aspect: 1.6, visibleWidth: 855, visibleHeight: 1074)]
        var primary = Destination(screen: "builtin", desktop: 1)
        primary.layout = .full
        var second = Destination(screen: "ext", desktop: 2)
        second.layout = fixedLayout()
        var lap = Destination(screen: "builtin", desktop: 3)
        lap.layout = fixedLayout()
        let rule = Rule(id: "r", appName: "A", bundleID: "a", tokens: [],
                        docked: primary, undocked: lap, dockedNext: [second])
        let out = Document.backfillingFixed([rule], screens: screens)[0]
        #expect(abs((out.dockedNext.first?.layout.w ?? 0) - 0.5) < 1e-9)
        #expect(abs((out.undocked?.layout.w ?? 0) - 1.0) < 1e-9)
        #expect(out.docked == primary)
    }

    @Test func backfillLeavesUnknownScreensAndProportionalLayoutsAlone() {
        var second = Destination(screen: "gone", desktop: 2)
        second.layout = fixedLayout()
        let rule = Rule(id: "r", appName: "A", bundleID: "a", tokens: [],
                        docked: Destination(screen: "ext", desktop: 1), dockedNext: [second])
        let screens = [KnownScreen(id: "ext", name: "E", aspect: 1.78)]
        #expect(Document.backfillingFixed([rule], screens: screens) == [rule])
    }

    // MARK: - splittingSharedState

    private func profile(_ id: String, _ rules: [Rule]) -> Profile { Profile(id: id, name: id, rules: rules) }

    @Test func splitGivesNamesToProfilesThatUseTheSlotThroughASecondaryPlace() {
        let a = profile("A", [ordered("r", [at("builtin", 1), at("ext", 2)])])
        let b = profile("B", [ordered("s", [at("ext", 3)])])
        let out = Document.splittingSharedState(
            profiles: [a, b], activeID: "A", activeRules: a.rules,
            names: ["docked|ext": ["2": "Two", "3": "Three"]],
            spaces: ["docked|ext": ["2": 22, "3": 33]], ghosts: [], plans: [:])
        #expect(out[0].legacy?.desktopNames["docked|ext"] == ["2": "Two"])
        #expect(out[1].legacy?.desktopNames["docked|ext"] == ["3": "Three"])
        #expect(out[0].legacy?.desktopNameSpaces["docked|ext"] == ["2": 22])
    }

    @Test func splitSendsPinnedGhostsToTheirOwnProfileOnly() {
        let ruleA = ordered("r", [at("ext", 1)])
        let a = profile("A", [ruleA]), b = profile("B", [ordered("s", [at("ext", 1)])])
        let pin = GhostDesktop.Pin(profileID: "A", mode: .docked, rule: ruleA, destination: at("ext", 1))
        let ghost = GhostDesktop(screen: "ext", name: nil, desktop: 1, deletedAt: Date(), pins: [pin])
        let out = Document.splittingSharedState(profiles: [a, b], activeID: "A", activeRules: a.rules,
                                                names: [:], spaces: [:], ghosts: [ghost], plans: [:])
        #expect(out[0].ghostDesktops.count == 1 && out[1].ghostDesktops.isEmpty)
        #expect(out[0].ghostDesktops.first?.pins.first?.profileID == "A")
    }

    @Test func splitPinlessNamedGhostGoesToProfilesUsingItsScreenElseTheActiveOne() {
        let a = profile("A", [ordered("r", [at("builtin", 1)])])
        let b = profile("B", [ordered("s", [at("ext", 1)])])
        let onExt = GhostDesktop(screen: "ext", name: "X", desktop: 4, deletedAt: Date())
        let onNobody = GhostDesktop(screen: "ext9", name: "Y", desktop: 2, deletedAt: Date())
        let out = Document.splittingSharedState(profiles: [a, b], activeID: "A", activeRules: a.rules,
                                                names: [:], spaces: [:], ghosts: [onExt, onNobody], plans: [:])
        #expect(out[0].ghostDesktops.map(\.name) == ["Y"])
        #expect(out[1].ghostDesktops.map(\.name) == ["X"])
    }

    @Test func splitUsesActiveRulesForTheActiveProfile() {
        // Profilin kayıtlı kuralı eski; etkin çalışma kopyası ext·2 kullanıyor.
        let stale = profile("A", [])
        let live = [ordered("r", [at("ext", 2)])]
        let out = Document.splittingSharedState(
            profiles: [stale], activeID: "A", activeRules: live,
            names: ["docked|ext": ["2": "Two"]], spaces: [:], ghosts: [], plans: ["docked|ext": 3])
        #expect(out[0].legacy?.desktopNames["docked|ext"] == ["2": "Two"])
        #expect(out[0].legacy?.plannedDesktops == ["docked|ext": 3])
    }
}
