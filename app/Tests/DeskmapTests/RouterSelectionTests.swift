import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Router'ın tarama seçimi ve birleştirmesi gerçek Router üzerinden
/// (`RouterHarness`: sahte ekran ve pencere kaynakları, `sweepSelection`).
/// Arayüzün statik yardımcıları (grup taşıma, gölge listesi) Router'ın
/// bağlamını alınca taramayla aynı kuralı görür.
@MainActor
struct RouterSelectionTests {

    private let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: bundle, tokens: tokens, docked: destination)
    }

    /// Ana pencere "Claude" kuralıyla yerleşti, sonra başlığı "Budget
    /// planning" oldu; başlığa yeni uyan "notes" kuralı onu almaz.
    private func driftedMainWindow() -> RouterHarness {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk),
                                        rule("notes", ["Budget"], otherDesk)])
        sim.titles = [7: "Claude"]
        _ = sim.sweep()
        sim.titles[7] = "Budget planning"
        _ = sim.sweep()
        return sim
    }

    // MARK: - Birleştirme (sweep sonucu → Router durumu)

    /// Kurallar kapalıyken (duraklatma anahtarı) tarama kural vermez ama
    /// bağları silmez; açılınca pencere yine bağlı kuralına gider.
    @Test func disabledRoutingKeepsBindings() {
        let sim = driftedMainWindow()
        let bound = sim.bindings[7]
        #expect(bound != nil)
        sim.store.document.enabled = false
        #expect(sim.sweepRules()[7] == .some(nil))
        #expect(sim.bindings[7] == bound)
        sim.store.document.enabled = true
        #expect(sim.sweepRules()[7] == .some("main"))
    }

    /// Ekranlar yatışırken de aynı: yönlendirme yok, bağlar korunur.
    @Test func settlingScreensKeepBindings() {
        let sim = driftedMainWindow()
        let bound = sim.bindings[7]
        sim.screens.simulateChangeForTesting(settle: false)
        #expect(sim.screens.isSettling)
        #expect(sim.sweepRules()[7] == .some(nil))
        #expect(sim.bindings[7] == bound)
        sim.screens.simulateChangeForTesting(settle: true)
        #expect(sim.sweepRules()[7] == .some("main"))
    }

    /// İlk taramada açık olan genel başlıklı pencere beklemez; sonradan
    /// açılan bekler.
    @Test func firstSweepDoesNotHold() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk),
                                        rule("sess", ["Paper review"], otherDesk)])
        sim.titles = [1: "Claude"]
        #expect(sim.sweep()[1] == .some(mainDesk))
        #expect(sim.router.firstSeen[1] == .distantPast)
        sim.titles[2] = "Claude"
        #expect(sim.sweep()[2] == .some(nil))
        #expect(sim.router.firstSeen[2] == sim.now)
    }

    /// Arayüzün bağlamı yalnız canlı modda; öbür modun seçimi durumsuz.
    @Test func contextOnlyForLiveMode() {
        let sim = driftedMainWindow()
        #expect(sim.router.context(for: .docked) == sim.router.routingContext)
        #expect(sim.router.context(for: .undocked) == nil)
    }

    /// Arayüzün seçimi (`router.context(for:)` ile) taramanın seçimiyle aynı.
    @Test func interfaceSelectionMatchesSweep() {
        let sim = driftedMainWindow()
        let ui = Routing.select(
            rules: sim.rules, sessionPins: sim.router.sessionPins, mode: .docked, windowID: 7,
            bundleID: bundle, appName: "Claude", title: "Budget planning",
            context: sim.router.context(for: .docked))
        #expect(ui?.ruleID == "main")
        #expect(sim.sweepRules()[7] == .some("main"))
    }

    // MARK: - Grup taşıma ve gölge listesi bağı görür

    /// Grubu taşımak pencereyi yerleştiren kuralı taşır, başlığına yeni uyan
    /// kuralı değil.
    @Test func groupMoveMovesBoundRule() {
        let sim = driftedMainWindow()
        let group = AppGroup(bundleID: bundle, appName: "Claude", windows: sim.windows)
        let there = Router.Placement(screen: "builtin", desktop: 4)
        let bound = GroupMovePlan.make(group: group, to: there, mode: .docked, isLive: true,
                                       rules: sim.rules, sessionPins: [:],
                                       context: sim.router.context(for: .docked))
        #expect(bound.rules.map(\.id) == ["main"])
        // Bağ verilmezse eski durumsuz seçim: başlığa uyan kural taşınırdı.
        let stateless = GroupMovePlan.make(group: group, to: there, mode: .docked, isLive: true,
                                           rules: sim.rules, sessionPins: [:])
        #expect(stateless.rules.map(\.id) == ["notes"])
    }

    /// Pini kaldırılmış (yerinde kalan) pencere grupla pinsiz pencere gibi
    /// tek seferlik taşınır; genel kural taşınmaz.
    @Test func groupMoveTreatsStayingWindowAsUnpinned() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk)])
        sim.titles = [5: "Paper review"]
        sim.pin(5, otherDesk)
        _ = sim.sweep()
        sim.unpin(5)
        _ = sim.sweep()
        let group = AppGroup(bundleID: bundle, appName: "Claude", windows: sim.windows)
        let plan = GroupMovePlan.make(group: group, to: .init(screen: "builtin", desktop: 4),
                                      mode: .docked, isLive: true, rules: sim.rules,
                                      sessionPins: sim.router.sessionPins,
                                      context: sim.router.context(for: .docked))
        #expect(plan.rules.isEmpty)
        #expect(plan.sessions.isEmpty)
    }

    /// Gölge listesi: başlığa yeni uyan kural, pencereyi tutan bağlı kurala
    /// yenilir (gölgede); bağsız listede tersi görünürdü.
    @Test func shadowsFollowBinding() {
        let sim = driftedMainWindow()
        let bound = ScreenMapView.shadows(rules: sim.rules, windows: sim.windows,
                                          sessionPins: [:], mode: .docked,
                                          context: sim.router.context(for: .docked))
        #expect(bound.winners == ["main"])
        #expect(bound.shadowedBy == ["notes": "main"])
        let stateless = ScreenMapView.shadows(rules: sim.rules, windows: sim.windows,
                                              sessionPins: [:], mode: .docked)
        #expect(stateless.winners == ["notes"])
    }

    /// Bağlı kural da başlığa uyarken önde duran eşit özgüllükte kural
    /// gölgede sayılır (pencere bağlı kuralda).
    @Test func shadowsCountRuleLosingToBinding() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk)])
        sim.titles = [7: "Draft"]
        _ = sim.sweep()
        // Aynı özgüllükte (uygulama geneli) ikinci kural sonradan eklendi:
        // bağ onu geçer.
        sim.rules.insert(Rule(id: "wide2", appName: "Claude", bundleID: bundle, tokens: [],
                              docked: otherDesk), at: 0)
        _ = sim.sweep()
        let result = ScreenMapView.shadows(rules: sim.rules, windows: sim.windows,
                                           sessionPins: [:], mode: .docked,
                                           context: sim.router.context(for: .docked))
        #expect(result.winners == ["wide"])
        #expect(result.shadowedBy == ["wide2": "wide"])
        let stateless = ScreenMapView.shadows(rules: sim.rules, windows: sim.windows,
                                              sessionPins: [:], mode: .docked)
        #expect(stateless.winners == ["wide2"])
    }

    // MARK: - Profil geçişi

    /// A profilinde başlık kuralıyla yerleşen pencere, B profiline geçince
    /// B'nin uygulama geneli kuralına gider: A'nın kuralı B'de yok ama bu
    /// silinmiş pin değil, bağ eski yerde tutmaz.
    @Test func profileSwitchDropsBindings() {
        let sim = RouterHarness(rules: [rule("a-main", ["Claude"], mainDesk)])
        sim.titles = [7: "Claude"]
        #expect(sim.sweepRules()[7] == .some("a-main"))
        sim.store.addProfile(named: "B")
        sim.rules = [rule("b-wide", [], otherDesk)]
        #expect(sim.sweepRules()[7] == .some("b-wide"))
    }

    /// Aynı profilde silinen pin pencereyi yine yerinde bırakır (geçişin
    /// bağları düşürmesi bunu bozmaz).
    @Test func deletedRuleStillStaysWithinProfile() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk),
                                        rule("wide", [], otherDesk)])
        sim.titles = [7: "Claude"]
        #expect(sim.sweepRules()[7] == .some("main"))
        sim.rules.removeAll { $0.id == "main" }
        #expect(sim.sweepRules()[7] == .some(nil))
    }
}
