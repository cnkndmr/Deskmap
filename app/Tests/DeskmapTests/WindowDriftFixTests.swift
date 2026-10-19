import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Pencere kayması düzeltmesi (docs/bug-tables.md §B, DÜZELTME hücreleri).
/// Gerçek Router sahte ekran/pencere kaynaklarıyla (`RouterHarness`): ilk
/// görülme, bekleme, tam başlık sahipleri, bağların taramalar arası
/// taşınması ve pin kaldırma Router'ın kendi kodundan geçer; gerçek pencere yok.
@MainActor
struct WindowDriftFixTests {

    private static let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let sessionDesk = Destination(screen: "external", desktop: 5)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: Self.bundle, tokens: tokens, docked: destination)
    }

    // MARK: - B2 · geçici başlık

    @Test func transientTitleIsHeld() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk), rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [1: "Claude"]
        #expect(sim.sweep()[1] == .some(mainDesk))          // açılışta var olan ana pencere beklemez
        sim.titles[2] = "Claude"                              // yeni oturum penceresi
        #expect(sim.sweep()[2] == .some(nil))
        sim.wait(3)
        sim.titles[2] = "Paper review"                        // adını aldı
        #expect(sim.sweep()[2] == .some(sessionDesk))
        #expect(sim.bindings[2] == .rule(id: "sess", specificity: 1, key: sim.rules[1].bindingKey))
    }

    @Test func genericTitleIsRoutedAfterGrace() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk)])
        _ = sim.sweep()
        sim.titles = [3: "Claude"]
        #expect(sim.sweep()[3] == .some(nil))
        sim.wait(Routing.genericTitleGrace + 1)
        #expect(sim.sweep()[3] == .some(mainDesk))
    }

    // MARK: - B3/B4 · tam başlık sahibi

    @Test func exactOwnerKeepsRule() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk), rule("orig", ["Paper review"], sessionDesk)])
        sim.titles = [1: "Claude", 2: "Paper review", 3: "Paper review (fork)", 4: "Claude Code notes"]
        let out = sim.sweep()
        #expect(out[1] == .some(mainDesk))
        #expect(out[2] == .some(sessionDesk))
        #expect(out[3] == .some(nil))                         // fork üst üste binmez
        #expect(out[4] == .some(nil))                         // "Claude" geçen oturum ana masaüstüne gitmez
    }

    @Test func ruleWithoutExactOwnerStillMatchesSubstring() {
        let sim = RouterHarness(rules: [rule("orig", ["Paper review"], sessionDesk)])
        sim.titles = [3: "Paper review (fork)"]               // asıl pencere kapalı
        #expect(sim.sweep()[3] == .some(sessionDesk))
    }

    // MARK: - B5/B6 · başlık değişti

    @Test func bindingSurvivesTitleChange() {
        let sim = RouterHarness(rules: [rule("main", ["Claude"], mainDesk), rule("notes", ["Budget"], otherDesk),
                              rule("wide", [], otherDesk), rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [1: "Claude", 2: "Paper review"]
        _ = sim.sweep()
        sim.titles = [1: "Budget planning", 2: "Draft notes"]   // ana pencerede sohbet, oturum yeniden adlandı
        let out = sim.sweep()
        #expect(out[1] == .some(mainDesk))
        #expect(out[2] == .some(sessionDesk))
    }

    @Test func moreSpecificRuleUpgradesBinding() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk), rule("two", ["Paper", "review"], otherDesk)])
        sim.titles = [2: "Paper notes"]
        #expect(sim.sweep()[2] == .some(mainDesk))
        sim.titles[2] = "Paper review"
        #expect(sim.sweep()[2] == .some(otherDesk))
        #expect(sim.bindings[2] == .rule(id: "two", specificity: 2, key: sim.rules[1].bindingKey))
    }

    /// Kural yerinde daraltıldı (uygulama geneli → "Claude" başlığı): ona
    /// bağlı oturum pencereleri artık tutulmaz.
    @Test func editedRuleRebindsByNewTokens() {
        let sim = RouterHarness(rules: [rule("main", [], mainDesk)])
        sim.titles = [1: "Claude", 2: "Paper review"]
        _ = sim.sweep()
        sim.rules[0].tokens = ["Claude"]
        let out = sim.sweep()
        #expect(out[1] == .some(mainDesk))
        #expect(out[2] == .some(nil))
    }

    /// İnceleme 3: kuralın bu kurulumda hedefi yok (laptop'a geçildi):
    /// bağ korunur, monitör geri gelince pencere yine kuralın yerine gider.
    @Test func bindingSurvivesModeWithoutDestination() {
        let sim = RouterHarness(rules: [rule("wide", [], otherDesk), rule("sess", ["Paper review"], sessionDesk)])
        sim.rules[0].undocked = Destination(screen: "builtin", desktop: 1)
        sim.titles = [2: "Paper review"]
        _ = sim.sweep()
        sim.titles[2] = "Draft notes"
        sim.mode = .undocked
        #expect(sim.sweep()[2] == .some(nil))               // genel kural çekmez
        sim.mode = .docked
        #expect(sim.sweep()[2] == .some(sessionDesk))
    }

    /// İnceleme 7: düzenlenen kural artık uymuyorsa eski bağ saklanmaz.
    @Test func editedRuleWithoutMatchForgetsBinding() {
        let sim = RouterHarness(rules: [rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [2: "Paper review"]
        _ = sim.sweep()
        sim.rules[0].tokens = ["Budget"]
        #expect(sim.sweep()[2] == .some(nil))
        #expect(sim.bindings[2] == nil)
    }

    /// İnceleme 2: başlık kuralı olmayan uygulamanın genel başlıklı penceresi
    /// beklemez.
    @Test func noHoldWithoutTitleRules() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk)])
        _ = sim.sweep()
        sim.titles = [3: "Claude"]
        #expect(sim.sweep()[3] == .some(mainDesk))
        #expect(!Routing.isHeld(title: "Claude", appName: "Claude", firstSeen: sim.now, now: sim.now,
                                titleRules: false))
    }

    // MARK: - B1 · pin kaldırıldı

    @Test func unpinnedWindowStays() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk)])
        sim.titles = [5: "Paper review"]
        sim.pin(5, sessionDesk)
        #expect(sim.sweep()[5] == .some(sessionDesk))
        sim.unpin(5)
        #expect(sim.sweep()[5] == .some(nil))
        // Sonradan bu pencereye özgü kural yazılırsa alır.
        sim.rules.append(rule("own", ["Paper review"], otherDesk))
        #expect(sim.sweep()[5] == .some(otherDesk))
    }

    // MARK: - Kural silindi, pencere kapandı

    @Test func deletedRuleLeavesWindowInPlace() {
        let sim = RouterHarness(rules: [rule("wide", [], mainDesk), rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [2: "Paper review"]
        #expect(sim.sweep()[2] == .some(sessionDesk))
        sim.rules.removeAll { $0.id == "sess" }               // haritada pin kaldırıldı
        #expect(sim.sweep()[2] == .some(nil))
        #expect(sim.bindings[2] == .stay(minimum: 1))
        // Aynı parçayla yeniden pinlenirse (yeni kural) alır.
        sim.rules.append(rule("again", ["Paper review"], otherDesk))
        #expect(sim.sweep()[2] == .some(otherDesk))
    }

    @Test func bindingsPrunedWithWindows() {
        let sim = RouterHarness(rules: [rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [2: "Paper review"]
        _ = sim.sweep()
        #expect(sim.bindings[2] != nil)
        // Budama yaşayan pencere listesine göre (liste boşsa budanmaz).
        sim.titles = [3: "Budget planning"]
        _ = sim.sweep()
        #expect(sim.bindings[2] == nil)
        #expect(sim.router.firstSeen[2] == nil)
        #expect(sim.router.firstSeen[3] != nil)
    }

    /// Bağ verilmezse (arayüzün öbür modu) eski durumsuz seçim aynen.
    @Test func noContextKeepsStatelessSelection() {
        let rules = [rule("wide", [], mainDesk)]
        #expect(Routing.select(rules: rules, sessionPins: [:], mode: .docked, windowID: 1,
                               bundleID: Self.bundle, appName: "Claude", title: "x")?.ruleID == "wide")
    }
}
