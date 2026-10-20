import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Kampanya (profil alanı): profil değişimi ile bağların, oturum pinlerinin,
/// monitör rollerinin ve yönlendirme durdurmalarının (kapalı, yatışma)
/// etkileşimi. Gerçek Router `RouterHarness` ile sürülür; profil işlemleri
/// Store üzerinden yapılır (uygulamadaki yol). Bağlar profile bağlıdır
/// (`bindingsProfileID`): profil değişince baştan kurulur, aynı profilde
/// silinen pin pencereyi yerinde bırakır.
@MainActor
struct CampaignProfileTests {

    private let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)
    private let sessionDesk = Destination(screen: "external", desktop: 4)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: bundle, tokens: tokens, docked: destination)
    }

    /// A etkin; B (başka kurallarla) tanımlı. Dönüş: harness, A ve B kimlikleri.
    private func twoProfiles(a: [Rule], b: [Rule]) -> (sim: RouterHarness, a: String, b: String) {
        let sim = RouterHarness(rules: a)
        let aID = sim.store.document.activeProfileID
        sim.store.addProfile(named: "B")
        let bID = sim.store.document.activeProfileID
        sim.rules = b
        sim.store.switchProfile(to: aID)
        return (sim, aID, bID)
    }

    /// A'da "Claude" kuralıyla yerleşip sonra "Budget planning" olan pencere
    /// (7): yalnız bağ onu "main"e bağlı tutar.
    private func driftedInA(b: [Rule]) -> (sim: RouterHarness, a: String, b: String) {
        let setup = twoProfiles(a: [rule("main", ["Claude"], mainDesk)], b: b)
        setup.sim.titles = [7: "Claude"]
        _ = setup.sim.sweep()
        setup.sim.titles[7] = "Budget planning"
        _ = setup.sim.sweep()
        return setup
    }

    // MARK: - Bağlar profil değişince baştan kurulur

    @Test func switchAndBackDoesNotResurrectOldBinding() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        #expect(s.sim.bindings[7] != nil)
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweepRules()[7] == .some("b-wide"))
        s.sim.store.switchProfile(to: s.a)
        // A'ya dönünce başlık "Budget planning": main'e uymaz, eski bağ geri gelmez.
        #expect(s.sim.sweepRules()[7] == .some(nil))
        #expect(s.sim.bindings[7] == nil)
    }

    @Test func sameRuleIDInOtherProfileDoesNotInheritBinding() {
        // B'de de "main" kimliği ve aynı parçalar var (içe aktarma); hedef farklı.
        let s = driftedInA(b: [rule("main", ["Claude"], otherDesk)])
        s.sim.store.switchProfile(to: s.b)
        // Bağ kimliğe değil profile bakar: "Budget planning" B'nin main'ine uymaz.
        #expect(s.sim.sweep()[7] == .some(nil))
    }

    @Test func staleRuleBindingFromOldProfileWouldPinWindowInPlace() {
        // Güvence mekanizması: bağ sıfırlanmasaydı B'nin kural listesinde
        // "kural silindi" sayılıp pencere yerinde kalırdı (saf seçim).
        let stale: [CGWindowID: Routing.Binding] = [7: .rule(id: "a-main", specificity: 1, key: "k")]
        let window = Router.WindowSnapshot(id: 7, pid: 1, appName: "Claude", bundleID: bundle,
                                           title: "Claude", placement: nil, frame: nil,
                                           isMinimized: false)
        let wide = rule("b-wide", [], otherDesk)
        let withStale = Router.select(windows: [window], rules: [wide], sessionPins: [:], mode: .docked,
                                      bindings: stale, firstSeen: [7: .distantPast], initial: false,
                                      now: Date(timeIntervalSince1970: 1_000_000))
        #expect(withStale.matches[7] == nil)
        #expect(withStale.context.bindings[7] == .stay(minimum: 1))
        let fresh = Router.select(windows: [window], rules: [wide], sessionPins: [:], mode: .docked,
                                  bindings: [:], firstSeen: [7: .distantPast], initial: false,
                                  now: Date(timeIntervalSince1970: 1_000_000))
        #expect(fresh.matches[7]?.ruleID == "b-wide")
    }

    @Test func deletedPinStaysInSameProfileButProfileSwitchReleasesIt() {
        let s = twoProfiles(a: [rule("main", ["Claude"], mainDesk), rule("wide", [], otherDesk)],
                            b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [7: "Claude"]
        #expect(s.sim.sweepRules()[7] == .some("main"))
        s.sim.rules.removeAll { $0.id == "main" }
        #expect(s.sim.sweepRules()[7] == .some(nil))
        #expect(s.sim.bindings[7] == .stay(minimum: 1))
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweepRules()[7] == .some("b-wide"))
    }

    @Test func switchingToTheActiveProfileKeepsBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        let bound = s.sim.bindings[7]
        s.sim.store.switchProfile(to: s.a)
        #expect(s.sim.sweepRules()[7] == .some("main"))
        #expect(s.sim.bindings[7] == bound)
    }

    @Test func quickRoundTripWithoutSweepKeepsBindings() {
        // A→B→A arada tarama yok: bağların profili hiç değişmedi.
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.switchProfile(to: s.b)
        s.sim.store.switchProfile(to: s.a)
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func renamingProfileKeepsBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.renameProfile(s.a, to: "Renamed A")
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func deletingInactiveProfileKeepsBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.deleteProfile(s.b)
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func deletingActiveProfileResetsBindingsToTheFallbackProfile() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.deleteProfile(s.a)
        #expect(s.sim.store.document.activeProfileID == s.b)
        #expect(s.sim.sweepRules()[7] == .some("b-wide"))
    }

    // MARK: - Profil kopyası

    @Test func duplicatingAProfileDoesNotDisturbActiveBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        let copy = s.sim.store.duplicateProfile(s.a, named: "A copy")
        #expect(copy != nil)
        #expect(s.sim.store.document.activeProfileID == s.a)
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func switchingToACopyDoesNotInheritBindingToTheOriginalRuleIDs() throws {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        let copy = try #require(s.sim.store.duplicateProfile(s.a, named: "A copy"))
        #expect(copy.rules.map(\.id) != ["main"])   // kimlikler yenilenir
        s.sim.store.switchProfile(to: copy.id)
        // Pencere "Budget planning": kopyanın kuralı da uymaz, bağ taşınmaz.
        #expect(s.sim.sweepRules()[7] == .some(nil))
        #expect(s.sim.bindings[7] == nil)
        // Başlık "Claude"a dönünce kopyanın kendi kuralı alır.
        s.sim.titles[7] = "Claude"
        #expect(s.sim.sweepRules()[7] == .some(copy.rules[0].id))
    }

    @Test func addingProfileCopyingCurrentBindsToTheNewRules() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        let added = s.sim.store.addProfile(named: "C", copyingCurrent: true)
        #expect(s.sim.store.document.activeProfileID == added.id)
        #expect(s.sim.sweepRules()[7] == .some(nil))
        s.sim.titles[7] = "Claude"
        let ids = s.sim.sweepRules()
        #expect(ids[7] != .some("main"))
        #expect(ids[7] == .some(added.rules.first?.id))
    }

    @Test func addingProfileWithoutActivatingKeepsBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.addProfile(named: "Later", activate: false)
        #expect(s.sim.store.document.activeProfileID == s.a)
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func upsertingTheActiveProfileKeepsItsIdentityAndWindowStaysPut() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        var incoming = Profile(name: s.sim.store.document.activeProfile?.name ?? "")
        incoming.rules = [rule("new-main", ["Claude"], otherDesk), rule("wide", [], mainDesk)]
        s.sim.store.upsertProfile(incoming, activate: false)
        #expect(s.sim.store.document.activeProfileID == s.a)
        // Aynı profil: "main" kuralı gitti, pencere yerinde kalır (pin silindi).
        #expect(s.sim.sweepRules()[7] == .some(nil))
    }

    // MARK: - Oturum pini

    @Test func sessionPinSurvivesProfileSwitch() {
        let s = twoProfiles(a: [rule("wide", [], mainDesk)], b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        #expect(s.sim.sweep()[5] == .some(sessionDesk))
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweep()[5] == .some(sessionDesk))
        #expect(s.sim.sweepRules()[5] == .some(Routing.sessionRuleID))
        s.sim.store.switchProfile(to: s.a)
        #expect(s.sim.sweep()[5] == .some(sessionDesk))
    }

    @Test func sessionPinHoldsAgainstTheNewProfilesMoreSpecificRule() {
        let s = twoProfiles(a: [rule("wide", [], mainDesk)],
                            b: [rule("b-paper", ["Paper review"], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweepRules()[5] == .some(Routing.sessionRuleID))
    }

    @Test func unpinStaysAndNewProfileWideRuleDoesNotPullTheWindow() {
        let s = twoProfiles(a: [rule("wide", [], mainDesk)], b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        _ = s.sim.sweep()
        s.sim.store.switchProfile(to: s.b)
        _ = s.sim.sweep()
        s.sim.unpin(5)
        // Pini kalkan pencere B'de de yerinde kalır (B'nin genel kuralı çekmez).
        #expect(s.sim.sweep()[5] == .some(nil))
        // B'ye sonradan özgül kural yazılırsa alır.
        s.sim.rules.append(rule("b-paper", ["Paper review"], otherDesk))
        #expect(s.sim.sweep()[5] == .some(otherDesk))
    }

    @Test func unpinThenImmediateProfileSwitchReleasesTheWindowToTheNewProfile() {
        // Pini kaldırıp tarama gelmeden profil değişince "kal" bağı da profille
        // sıfırlanır (profil değişimi bağları bırakır); sonraki turlar sabit.
        let s = twoProfiles(a: [rule("wide", [], mainDesk)], b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        _ = s.sim.sweep()
        s.sim.unpin(5)
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweep()[5] == .some(otherDesk))
        #expect(s.sim.sweep()[5] == .some(nil))
    }

    @Test func unpinOverrideIsDroppedWhenTheWindowCloses() {
        let s = twoProfiles(a: [rule("wide", [], mainDesk)], b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        _ = s.sim.sweep()
        s.sim.unpin(5)
        s.sim.titles = [6: "Other"]
        _ = s.sim.sweep()
        #expect(s.sim.bindings[5] == nil)
        // Aynı kimlikle yeni pencere (nadir): eski "kal" bağı taşınmaz.
        s.sim.titles = [5: "Other"]
        #expect(s.sim.sweep()[5] == .some(mainDesk))
    }

    @Test func sessionPinRemovedWhileSettlingStillGetsItsStayBinding() {
        let s = twoProfiles(a: [rule("wide", [], mainDesk)], b: [rule("b-wide", [], otherDesk)])
        s.sim.titles = [5: "Paper review"]
        s.sim.pin(5, sessionDesk)
        _ = s.sim.sweep()
        s.sim.screens.simulateChangeForTesting(settle: false)
        s.sim.unpin(5)
        _ = s.sim.sweep()                                  // yatışırken
        s.sim.screens.simulateChangeForTesting(settle: true)
        #expect(s.sim.sweep()[5] == .some(nil))
    }

    // MARK: - Yönlendirme kapalı / yatışma

    @Test func profileSwitchWhileDisabledDoesNotCarryOldBindingsToTheNewProfile() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.document.enabled = false
        _ = s.sim.sweep()
        #expect(s.sim.bindings[7] != nil)                 // kapalıyken A'nın bağı korunur
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweepRules()[7] == .some(nil))      // kapalı: kural yok
        #expect(s.sim.bindings[7] == nil)                 // ama A'nın bağı B'ye sızmaz
        s.sim.store.document.enabled = true
        #expect(s.sim.sweepRules()[7] == .some("b-wide"))
    }

    @Test func bindingsStayWhileDisabledAcrossManySweepsOfTheSameProfile() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.document.enabled = false
        for _ in 0..<5 { _ = s.sim.sweep() }
        s.sim.store.document.enabled = true
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func settlingSwitchKeepsNoRoutingThenNewProfileRoutesAfterSettle() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.screens.simulateChangeForTesting(settle: false)
        s.sim.store.switchProfile(to: s.b)
        #expect(s.sim.sweepRules()[7] == .some(nil))
        #expect(s.sim.bindings[7] == nil)
        s.sim.screens.simulateChangeForTesting(settle: true)
        #expect(s.sim.sweepRules()[7] == .some("b-wide"))
    }

    @Test func settlingWithoutSwitchKeepsBindingsAcrossManySweeps() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.screens.simulateChangeForTesting(settle: false)
        for _ in 0..<3 { _ = s.sim.sweep() }
        s.sim.screens.simulateChangeForTesting(settle: true)
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    @Test func disabledAndSettlingTogetherThenSwitchBackToOriginalProfile() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.store.document.enabled = false
        s.sim.screens.simulateChangeForTesting(settle: false)
        s.sim.store.switchProfile(to: s.b)
        _ = s.sim.sweep()                  // B taramayı gördü: A'nın bağları gitti
        s.sim.store.switchProfile(to: s.a)
        _ = s.sim.sweep()
        s.sim.store.document.enabled = true
        s.sim.screens.simulateChangeForTesting(settle: true)
        // Başlık hâlâ "Budget planning": bağ yeniden kurulmadı, main uymaz.
        #expect(s.sim.sweepRules()[7] == .some(nil))
    }

    @Test func reapplyAllKeepsBindings() {
        let s = driftedInA(b: [rule("b-wide", [], otherDesk)])
        s.sim.router.reapplyAll()
        #expect(s.sim.sweepRules()[7] == .some("main"))
    }

    // MARK: - Beklemeler profil değişiminden etkilenmez

    @Test func newWindowStaysHeldAcrossProfileSwitchUntilGraceEnds() {
        let s = twoProfiles(a: [rule("a-paper", ["Paper"], mainDesk)],
                            b: [rule("b-paper", ["Paper"], otherDesk)])
        s.sim.titles = [1: "Paper notes"]
        _ = s.sim.sweep()
        s.sim.titles[2] = "Claude"                      // sonradan açıldı, genel başlık
        #expect(s.sim.sweep()[2] == .some(nil))          // A'da bekler
        s.sim.store.switchProfile(to: s.b)
        s.sim.wait(2)
        #expect(s.sim.sweep()[2] == .some(nil))          // ilk görülme korunur, hâlâ bekler
        #expect(s.sim.router.firstSeen[2] != nil)
        s.sim.wait(Routing.genericTitleGrace)
        s.sim.titles[2] = "Paper chat"
        #expect(s.sim.sweepRules()[2] == .some("b-paper"))
    }

    // MARK: - Roller ve profil (belge düzeyi; roller profilden bağımsız)

    private static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Built-in", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))

    private static func external(_ uuid: String, x: CGFloat) -> ScreenService.RawDisplay {
        .init(uuid: uuid, name: "Monitor", isBuiltin: false,
              frame: CGRect(x: x, y: 1112, width: 1920, height: 1080),
              visibleFrame: CGRect(x: x, y: 1112, width: 1920, height: 1050))
    }

    private final class Source { var list: [ScreenService.RawDisplay] = [] }

    private struct Rig {
        let source: Source
        let service: ScreenService
        let store: Store
        let sync: [AnyCancellable]
        let a: String
        let b: String
    }

    private func rig() -> Rig {
        let source = Source()
        source.list = [Self.builtin, Self.external("DELL", x: 0), Self.external("PEBBLE", x: 1920)]
        let service = ScreenService(displays: { source.list })
        var document = Document()
        document.rules = [Rule(id: "r", appName: "Claude", bundleID: bundle, tokens: [],
                               docked: Destination(screen: "external-2", desktop: 2))]
        let store = Store(demo: document)
        let aID = store.document.activeProfileID
        store.addProfile(named: "B")
        store.document.rules = [Rule(id: "rb", appName: "Claude", bundleID: bundle, tokens: [],
                                     docked: Destination(screen: "external", desktop: 3))]
        store.switchProfile(to: aID)
        let sync = AppModel.syncDisplayRoles(store: store, screens: service)
        return Rig(source: source, service: service, store: store, sync: sync, a: aID,
                   b: store.profiles.first { $0.id != aID }!.id)
    }

    @Test func rolesAreNotPartOfTheProfile() {
        let r = rig()
        let before = r.store.document.displayRoles
        #expect(before.remembered["external"] == ["DELL"])
        r.store.switchProfile(to: r.b)
        #expect(r.store.document.displayRoles == before)
        r.store.switchProfile(to: r.a)
        #expect(r.store.document.displayRoles == before)
        r.store.addProfile(named: "C", copyingCurrent: true)
        r.store.deleteProfile(r.store.document.activeProfileID)
        #expect(r.store.document.displayRoles == before)
        _ = r.sync
    }

    @Test func chosenRoleSwapSurvivesProfileSwitchAndRulesKeepTheirRoleIDs() {
        let r = rig()
        let current = r.service.connectedExternals.map { (role: $0.role, uuid: $0.display.uuid) }
        r.store.chooseDisplay("PEBBLE", for: "external", current: current)
        #expect(r.service.screens.first { $0.uuid == "PEBBLE" }?.id == "external")
        r.store.switchProfile(to: r.b)
        #expect(r.service.screens.first { $0.uuid == "PEBBLE" }?.id == "external")
        #expect(r.service.screens.first { $0.uuid == "DELL" }?.id == "external-2")
        // Kurallar rol kimliğiyle durur; takas kuralları değiştirmez.
        #expect(r.store.document.rules.first?.docked == Destination(screen: "external", desktop: 3))
        r.store.switchProfile(to: r.a)
        #expect(r.store.document.rules.first?.docked == Destination(screen: "external-2", desktop: 2))
        _ = r.sync
    }

    @Test func forgottenMonitorHoldsItsRoleAcrossProfileSwitch() {
        let r = rig()
        #expect(r.service.heldRoles.isEmpty)
        r.store.forgetDisplay("PEBBLE")
        #expect(r.service.heldRoles == ["external-2"])
        r.store.switchProfile(to: r.b)
        #expect(r.service.heldRoles == ["external-2"])   // onay profil değişimiyle gitmez
        r.store.switchProfile(to: r.a)
        #expect(r.service.heldRoles == ["external-2"])
        _ = r.sync
    }

    @Test func confirmingPendingRoleAfterProfileSwitchReleasesIt() {
        let r = rig()
        r.store.forgetDisplay("PEBBLE")
        r.store.switchProfile(to: r.b)
        let current = r.service.connectedExternals.map { (role: $0.role, uuid: $0.display.uuid) }
        r.store.chooseDisplay("PEBBLE", for: "external-2", current: current)
        #expect(r.service.heldRoles.isEmpty)
        #expect(r.store.document.displayRoles.remembered["external-2"] == ["PEBBLE"])
        #expect(r.store.document.activeProfileID == r.b)
        _ = r.sync
    }

    @Test func forgetAllRolesThenProfileSwitchHoldsNothing() {
        let r = rig()
        r.store.forgetDisplayRoles()
        r.store.switchProfile(to: r.b)
        #expect(r.service.heldRoles.isEmpty)     // ilk bağlanış gibi: her şey onaylı
        _ = r.sync
    }

    @Test func routerBuiltOnTheRigSeesNoSelectionChangeFromRolesAlone() {
        // Rol kararı seçimi değiştirmez; bağ yalnız profil kimliğine bakar.
        let r = rig()
        let router = Router(store: r.store, screens: r.service, demoWindows: [])
        let window = Router.WindowSnapshot(id: 3, pid: 1, appName: "Claude", bundleID: bundle,
                                           title: "Claude", placement: nil, frame: nil,
                                           isMinimized: false)
        #expect(router.sweepSelection(windows: [window])[3]?.ruleID == "r")
        r.store.forgetDisplay("PEBBLE")
        #expect(router.sweepSelection(windows: [window])[3]?.ruleID == "r")
        r.store.switchProfile(to: r.b)
        #expect(router.sweepSelection(windows: [window])[3]?.ruleID == "rb")
        _ = r.sync
    }

    // MARK: - Plan uygulaması ve profil (saf)

    private func slot(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    @Test func eachProfileCarriesItsOwnNamesAndPlansAcrossSwitch() {
        var document = Document()
        document.names = [DesktopName(id: "n-a", name: "Alpha")]
        document.plans.docked = ["external": ["Alpha", ""]]
        let aID = document.activeProfileID
        let b = document.addProfile(named: "B")
        #expect(document.names.isEmpty && document.plans.docked.isEmpty)
        document.names = [DesktopName(id: "n-b", name: "Beta")]
        document.plans.docked = ["external": ["", "Beta"]]
        document.switchProfile(to: aID)
        #expect(document.names.map(\.name) == ["Alpha"])
        #expect(document.plans.docked["external"] == ["Alpha", ""])
        document.switchProfile(to: b.id)
        #expect(document.names.map(\.name) == ["Beta"])
        #expect(document.plans.docked["external"] == ["", "Beta"])
    }

    @Test func planOfTheNewProfileOpensOnlyItsMissingDesktops() {
        // A'nın planı 2 masaüstü, B'ninki 4; canlıda 2 var. B'ye geçince 2 açılır.
        func input(plan: [String]) -> PlanApply.Input {
            var input = PlanApply.Input(
                mode: .docked, live: ["external": [10, 11]], contents: [10: [1], 11: [2]],
                names: [], plans: ["external": plan])
            input.allowMoves = true
            return input
        }
        #expect(PlanApply.compute(input(plan: ["", ""])).creates["external"] == nil)
        #expect(PlanApply.compute(input(plan: ["", "", "", ""])).creates["external"] == 2)
    }

    @Test func planNeverRemovesDesktopsOnProfileSwitchEvenWhenNewPlanIsShorter() {
        var input = PlanApply.Input(
            mode: .docked, live: ["external": [10, 11, 12, 13]],
            contents: [10: [1], 11: [], 12: [], 13: []], names: [], plans: ["external": [""]])
        input.allowMoves = true
        input.allowRemovals = false
        #expect(PlanApply.compute(input).removals.isEmpty)
    }

    @Test func heldRoleKeepsPlanAwayFromThatDisplayWhateverTheProfile() {
        var input = PlanApply.Input(
            mode: .docked, live: ["external": [10, 11], "external-2": [20, 21]],
            contents: [10: [1], 11: [2], 20: [3], 21: [4]],
            names: [DesktopName(id: "n", name: "Beta", space: 21)],
            plans: ["external": ["", ""], "external-2": ["Beta", ""]])
        input.allowMoves = true
        let held = PlanApply.compute(PlanApply.holding(input, roles: ["external-2"]))
        #expect(held.moves.allSatisfy { $0.to.screen != "external-2" && $0.window != 3 && $0.window != 4 })
        #expect(held.creates["external-2"] == nil)
        #expect(held.rebinds["n"] == nil)
        let free = PlanApply.compute(PlanApply.holding(input, roles: []))
        #expect(free.rebinds["n"] != nil || !free.moves.isEmpty || free.isEmpty)
    }
}
