import Foundation
import Testing
@testable import Deskmap

/// Uygulama içi ve Mission Control işlemleri (docs/desktop-names-v2.md B 8–17, 20).
struct PlanEditTests {

    private let liveD = LiveDesktops(mode: .docked, spaces: ["external": [10, 20, 30], "builtin": [1, 2, 3]])

    private func doc() -> Document {
        V6.document(
            rules: [V6.rule("Word", docked: V6.at("external", 2, name: "EXPO"), undocked: V6.at("builtin", 4, name: "EXPO")),
                    V6.rule("Mail", docked: V6.e(3), undocked: V6.b(3)),
                    V6.rule("Late", docked: V6.e(2))],
            names: [DesktopName(id: "EXPO", name: "Nova Ek", space: 20)],
            plans: DesktopPlans(docked: ["external": ["", "EXPO", ""], "builtin": ["", "", ""]],
                                undocked: ["builtin": ["", "", "", "EXPO"]]))
    }

    // MARK: - Satır 8–9

    @Test func deleteNamedRemovesFromBothPlans() {
        var d = doc()
        d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked)
        #expect(d.names.isEmpty)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.undocked, "builtin") == ["", "", ""])
    }

    @Test func namePinsGoToGhost() {
        var d = doc()
        let ghost = d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked)
        #expect(ghost?.name == "Nova Ek" && ghost?.nameID == "EXPO")
        #expect(Set(ghost?.pins.map(\.mode) ?? []) == [.docked, .undocked])
        #expect(!d.rules.contains { $0.appName == "Word" })
    }

    /// Numara pinleri: o sıradaki hayalete, sonrakiler bir yukarı.
    @Test func numberPinsShift() {
        var d = doc()
        d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked)
        #expect(d.rule(d.rules.first { $0.appName == "Mail" }!.id)?.docked?.desktop == 2)
        #expect(!d.rules.contains { $0.appName == "Late" })
        #expect(d.ghostDesktops.first?.pins.contains { $0.rule.appName == "Late" } == true)
    }

    @Test func deleteUnnamedShiftsNumbersOnly() {
        var d = doc()
        d.recordDeletion(space: 10, role: "external", desktop: 1, mode: .docked)
        #expect(d.names.first?.space == 20)
        #expect(d.rules.first { $0.appName == "Word" }?.docked?.nameID == "EXPO")
        #expect(d.rules.first { $0.appName == "Mail" }?.docked?.desktop == 2)
        #expect(d.plans.entries(.docked, "external") == ["EXPO", ""])
        #expect(d.ghostDesktops.isEmpty)
    }

    // MARK: - Satır 10–12

    /// P3: Mission Control'de sıralama yalnız etkin kurulumun planını yazar.
    @Test func mcReorderRewritesCurrentPlan() {
        var d = doc()
        d.followMissionControl(before: liveD.spaces, after: ["external": [20, 10, 30], "builtin": [1, 2, 3]], mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["EXPO", "", ""])
        #expect(d.plans.entries(.undocked, "builtin") == ["", "", "", "EXPO"])
        #expect(d.rules.first { $0.appName == "Mail" }?.docked?.desktop == 3)
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func mcAddAppendsEmptyEntry() {
        var d = doc()
        d.followMissionControl(before: liveD.spaces, after: ["external": [10, 20, 30, 40], "builtin": [1, 2, 3]], mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", "EXPO", "", ""])
    }

    @Test func mcMoveAcrossMovesPlanEntry() {
        var d = doc()
        d.followMissionControl(before: liveD.spaces, after: ["external": [10, 30], "builtin": [1, 2, 3, 20]], mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.docked, "builtin") == ["", "", "", "EXPO"])
        #expect(d.names.first?.space == 20)
    }

    // MARK: - Satır 13

    @Test func renameKeepsIdAndPins() {
        var d = doc()
        let ok1 = d.setDesktopName("Ek 2", screen: "external", desktop: 2, mode: .docked, live: liveD); #expect(ok1)
        #expect(d.names == [DesktopName(id: "EXPO", name: "Ek 2", space: 20)])
        #expect(d.rules.first { $0.appName == "Word" }?.docked?.nameID == "EXPO")
    }

    @Test func renameClashRefused() {
        var d = doc()
        let ok2 = d.setDesktopName("Other", screen: "external", desktop: 1, mode: .docked, live: liveD); #expect(ok2)
        let before = d
        let ok3 = d.setDesktopName("nova ek", screen: "external", desktop: 1, mode: .docked, live: liveD); #expect(!ok3)
        #expect(d == before)
    }

    /// N1: monitörde verilen ad laptop planının sonuna eklenir; laptop adı
    /// iki kurulumda aynı sıraya. Bu sıradaki numara pinleri ad pini olur.
    @Test func nameDesktopAddsToBothPlans() throws {
        var d = doc()
        let ok4 = d.setDesktopName("Paper", screen: "external", desktop: 3, mode: .docked, live: liveD); #expect(ok4)
        let paper = try #require(d.nameRecord(named: "Paper"))
        #expect(paper.space == 30)
        #expect(d.plans.entries(.docked, "external") == ["", "EXPO", paper.id])
        #expect(d.plans.entries(.undocked, "builtin") == ["", "", "", "EXPO", paper.id])
        #expect(d.rules.first { $0.appName == "Mail" }?.docked?.nameID == paper.id)
        #expect(d.rules.first { $0.appName == "Mail" }?.undocked?.nameID == nil)
        let ok5 = d.setDesktopName("Lap", screen: "builtin", desktop: 2, mode: .docked, live: liveD); #expect(ok5)
        let lap = try #require(d.nameRecord(named: "Lap"))
        #expect(d.plans.entries(.docked, "builtin") == ["", lap.id, ""])
        #expect(d.plans.entries(.undocked, "builtin")[1] == lap.id)
    }

    @Test func nameAbsorbsGhost() throws {
        var d = doc()
        d.ghostDesktops = [GhostDesktop(screen: "external", name: "Paper", desktop: 5, deletedAt: Date(),
                                        pins: [.init(profileID: d.activeProfileID, mode: .docked,
                                                     rule: V6.rule("Pdf"), destination: V6.e(5))],
                                        nameID: "OLD")]
        let ok6 = d.setDesktopName("paper", screen: "external", desktop: 1, mode: .docked, live: liveD); #expect(ok6)
        #expect(d.ghostDesktops.isEmpty)
        let pdf = try #require(d.rules.first { $0.appName == "Pdf" })
        #expect(pdf.docked?.nameID == "OLD")
        #expect(pdf.docked?.desktop == 1)
    }

    @Test func removeNameTurnsPinsIntoNumbers() {
        var d = doc()
        let ok7 = d.setDesktopName("", screen: "external", desktop: 2, mode: .docked, live: liveD); #expect(ok7)
        #expect(d.names.isEmpty)
        #expect(d.plans.entries(.docked, "external") == ["", "", ""])
        let word = d.rules.first { $0.appName == "Word" }
        #expect(word?.docked == V6.e(2) && word?.undocked == V6.b(4))
    }

    // MARK: - Satır 14

    @Test func inAppDeleteMakesGhost() {
        var d = doc()
        let ghost = d.recordDeletion(space: 30, role: "external", desktop: 3, mode: .docked)
        #expect(ghost?.name == nil)
        #expect(ghost?.pins.map(\.rule.appName) == ["Mail"])
    }

    /// Etkin olmayan kurulumun satırı: plan girdisi düşer; yerleşmemiş adın
    /// satırıysa ad silinir (adlı hayalet). Canlı adın masaüstü silinmez, kuyruğa
    /// da girmez (şema 6 yeni kuyruk yazmaz; ad yalnız o planın dışında kalır).
    @Test func inactiveDeleteQueuesById() {
        var d = doc()
        d.removePlanEntry(screen: "builtin", desktop: 4, mode: .undocked)
        #expect(d.plans.entries(.undocked, "builtin") == ["", "", ""])
        #expect(d.names.count == 1 && d.pendingRemovals.isEmpty)
        var unplaced = V6.document(rules: [V6.rule("X", undocked: V6.at("builtin", 2, name: "U"))],
                                   names: [DesktopName(id: "U", name: "Plan", space: nil)],
                                   plans: DesktopPlans(undocked: ["builtin": ["", "U"]]))
        let ghost = unplaced.removePlanEntry(screen: "builtin", desktop: 2, mode: .undocked)
        #expect(ghost?.name == "Plan")
        #expect(unplaced.names.isEmpty && unplaced.rules.isEmpty)
        #expect(unplaced.plans.entries(.undocked, "builtin") == [""])
    }

    // MARK: - Satır 15–16

    /// R5: pencereler taşınınca bütün profillerin adları içerikle gider.
    @Test func reorderPermutesAllProfilesBindings() {
        var d = doc()
        d.syncActiveProfile()
        let other = d.addProfile(named: "B", activate: false)
        d.profiles[d.profiles.firstIndex { $0.id == other.id }!].names = [DesktopName(id: "Z", name: "Z", space: 10)]
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: .docked, sharedLaptop: true,
                      liveSpaces: [10, 20, 30])
        #expect(d.names.first?.space == 10)
        #expect(d.profiles.first { $0.id == other.id }?.names.first?.space == 30)
        #expect(d.plans.entries(.docked, "external") == ["EXPO", "", ""])
        #expect(d.rules.first { $0.appName == "Mail" }?.docked?.desktop == 2)
    }

    /// D2'nin belge kısmı: içerik haritası R5'e girer, plan girdisi hedef rol listesine.
    @Test func moveAcrossRemovesEmptySource() {
        let map = Router.acrossSpaceMap(spaces: ["external": [10, 20, 30], "builtin": [1, 2, 3, 4]],
                                        from: "external", desktop: 2, to: "builtin", at: 2)
        #expect(map[20] == 2 && map[30] == 20 && map[2] == 3 && map[3] == 4)
        var d = doc()
        d.moveDesktopAcross(from: "external", desktop: 2, to: "builtin", at: 2, toCount: 3, mode: .docked,
                            spaceMap: map)
        #expect(d.names.first?.space == 2)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.docked, "builtin") == ["", "EXPO", "", ""])
    }

    @Test func inactiveReorderPlanOnly() {
        var d = doc()
        d.moveDesktop(on: "builtin", from: 4, to: 1, count: 4, mode: .undocked)
        #expect(d.plans.entries(.undocked, "builtin") == ["EXPO", "", "", ""])
        #expect(d.names.first?.space == 20)
        #expect(d.rules.first { $0.appName == "Mail" }?.undocked?.desktop == 4)
    }

    @Test func addActiveAndInactive() {
        var d = doc()
        d.planDesktop(on: "builtin", mode: .undocked, count: 6)
        #expect(d.plans.entries(.undocked, "builtin") == ["", "", "", "EXPO", "", ""])
        d.followMissionControl(before: liveD.spaces, after: ["external": [10, 20, 30], "builtin": [1, 2, 3, 4]], mode: .docked)
        #expect(d.plans.entries(.docked, "builtin") == ["", "", "", ""])
    }

    // MARK: - Satır 17

    /// N2: ada pin öbür kurulumda hedefi yoksa orada da o ada bağlanır.
    @Test func pinToNameBothSetups() throws {
        var d = doc()
        let id = d.pin(V6.rule("Pdf"), destination: V6.e(2), mode: .docked, live: liveD)
        let rule = try #require(d.rule(id))
        #expect(rule.docked?.nameID == "EXPO")
        #expect(rule.undocked == V6.at("builtin", 4, name: "EXPO"))
        // Öbür kurulumda hedefi olan kural: yalnız bu kurulum.
        let mail = d.rules.first { $0.appName == "Mail" }!
        d.setDestination(V6.e(2), for: mail.id, mode: .docked, live: liveD)
        #expect(d.rule(mail.id)?.undocked == V6.b(3))
        #expect(d.rule(mail.id)?.docked?.nameID == "EXPO")
        // Adsız masaüstüne taşınan pin numara hedefi olur.
        d.setDestination(V6.e(1), for: mail.id, mode: .docked, live: liveD)
        #expect(d.rule(mail.id)?.docked?.nameID == nil)
    }

    // MARK: - Satır 20

    @Test func copyLaptopLayoutPlans() {
        var d = doc()
        d.copyLayout(from: .undocked, to: .docked)
        #expect(d.plans.entries(.docked, "builtin") == ["", "", "", "EXPO"])
        #expect(d.plans.entries(.docked, "external") == ["", "", ""])
        #expect(d.rules.first { $0.appName == "Word" }?.docked?.nameID == "EXPO")
    }

    /// Ad hedefinin önbelleği canlı yeri izler; sıralama ad pinini kaydırmaz.
    @Test func nameCachesFollowLiveSpace() {
        var d = doc()
        d.refreshNameCaches(live: LiveDesktops(mode: .docked, spaces: ["external": [20, 10, 30]]))
        #expect(d.rules.first { $0.appName == "Word" }?.docked?.desktop == 1)
        #expect(d.rules.first { $0.appName == "Word" }?.undocked?.desktop == 4)
    }
}
