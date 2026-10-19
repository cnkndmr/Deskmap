import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Pencere kayması düzeltmesi (docs/bug-tables.md §B, DÜZELTME hücreleri).
/// `Sim`, Router taramasının seçim kısmını aynen kurar (ilk görülme,
/// bekleme, tam başlık sahipleri, bağların taşınması); gerçek pencere yok.
struct WindowDriftFixTests {

    private static let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let sessionDesk = Destination(screen: "external", desktop: 5)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: Self.bundle, tokens: tokens, docked: destination)
    }

    /// Taramalar arası seçim durumu (Router'daki `bindings`/`firstSeen`).
    private struct Sim {
        var rules: [Rule]
        var titles: [CGWindowID: String] = [:]
        var pins: [CGWindowID: Destination] = [:]
        var bindings: [CGWindowID: Routing.Binding] = [:]
        var firstSeen: [CGWindowID: Date] = [:]
        var swept = false
        var mode: Mode = .docked
        var now = Date(timeIntervalSince1970: 1_000_000)

        /// Bir tarama: pencere → seçilen hedef (yoksa nil).
        mutating func sweep() -> [CGWindowID: Destination?] {
            var context = Routing.Context(bindings: bindings)
            for (id, title) in titles {
                let seen = firstSeen[id] ?? (swept ? now : .distantPast)
                firstSeen[id] = seen
                if Routing.isHeld(title: title, appName: "Claude", firstSeen: seen, now: now,
                                  titleRules: Routing.hasTitleRule(rules, bundleID: bundle, appName: "Claude")) {
                    context.held.insert(id)
                }
            }
            context.exactOwned = Routing.exactOwners(
                rules: rules,
                windows: titles.filter { !context.held.contains($0.key) }
                    .map { (bundle, "Claude", $0.value) })
            var result: [CGWindowID: Destination?] = [:]
            for (id, title) in titles {
                let resolved = Routing.resolve(
                    rules: rules, sessionPins: pins, mode: mode, windowID: id,
                    bundleID: bundle, appName: "Claude", title: title, context: context)
                context.bindings[id] = resolved.binding
                result.updateValue(resolved.match?.destination, forKey: id)
            }
            bindings = Routing.prunedBindings(context.bindings, alive: Set(titles.keys))
            firstSeen = firstSeen.filter { titles[$0.key] != nil }
            swept = true
            return result
        }

        mutating func unpin(_ id: CGWindowID) {
            pins[id] = nil
            bindings[id] = Routing.bindingAfterUnpin(
                rules: rules, mode: .docked, bundleID: bundle, appName: "Claude", title: titles[id] ?? "")
        }

        mutating func wait(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

        private var bundle: String { WindowDriftFixTests.bundle }
    }

    // MARK: - B2 · geçici başlık

    @Test func transientTitleIsHeld() {
        var sim = Sim(rules: [rule("main", ["Claude"], mainDesk), rule("sess", ["Paper review"], sessionDesk)])
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
        var sim = Sim(rules: [rule("main", ["Claude"], mainDesk)])
        _ = sim.sweep()
        sim.titles = [3: "Claude"]
        #expect(sim.sweep()[3] == .some(nil))
        sim.wait(Routing.genericTitleGrace + 1)
        #expect(sim.sweep()[3] == .some(mainDesk))
    }

    // MARK: - B3/B4 · tam başlık sahibi

    @Test func exactOwnerKeepsRule() {
        var sim = Sim(rules: [rule("main", ["Claude"], mainDesk), rule("orig", ["Paper review"], sessionDesk)])
        sim.titles = [1: "Claude", 2: "Paper review", 3: "Paper review (fork)", 4: "Claude Code notes"]
        let out = sim.sweep()
        #expect(out[1] == .some(mainDesk))
        #expect(out[2] == .some(sessionDesk))
        #expect(out[3] == .some(nil))                         // fork üst üste binmez
        #expect(out[4] == .some(nil))                         // "Claude" geçen oturum ana masaüstüne gitmez
    }

    @Test func ruleWithoutExactOwnerStillMatchesSubstring() {
        var sim = Sim(rules: [rule("orig", ["Paper review"], sessionDesk)])
        sim.titles = [3: "Paper review (fork)"]               // asıl pencere kapalı
        #expect(sim.sweep()[3] == .some(sessionDesk))
    }

    // MARK: - B5/B6 · başlık değişti

    @Test func bindingSurvivesTitleChange() {
        var sim = Sim(rules: [rule("main", ["Claude"], mainDesk), rule("notes", ["Budget"], otherDesk),
                              rule("wide", [], otherDesk), rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [1: "Claude", 2: "Paper review"]
        _ = sim.sweep()
        sim.titles = [1: "Budget planning", 2: "Draft notes"]   // ana pencerede sohbet, oturum yeniden adlandı
        let out = sim.sweep()
        #expect(out[1] == .some(mainDesk))
        #expect(out[2] == .some(sessionDesk))
    }

    @Test func moreSpecificRuleUpgradesBinding() {
        var sim = Sim(rules: [rule("wide", [], mainDesk), rule("two", ["Paper", "review"], otherDesk)])
        sim.titles = [2: "Paper notes"]
        #expect(sim.sweep()[2] == .some(mainDesk))
        sim.titles[2] = "Paper review"
        #expect(sim.sweep()[2] == .some(otherDesk))
        #expect(sim.bindings[2] == .rule(id: "two", specificity: 2, key: sim.rules[1].bindingKey))
    }

    /// Kural yerinde daraltıldı (uygulama geneli → "Claude" başlığı): ona
    /// bağlı oturum pencereleri artık tutulmaz.
    @Test func editedRuleRebindsByNewTokens() {
        var sim = Sim(rules: [rule("main", [], mainDesk)])
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
        var sim = Sim(rules: [rule("wide", [], otherDesk), rule("sess", ["Paper review"], sessionDesk)])
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
        var sim = Sim(rules: [rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [2: "Paper review"]
        _ = sim.sweep()
        sim.rules[0].tokens = ["Budget"]
        #expect(sim.sweep()[2] == .some(nil))
        #expect(sim.bindings[2] == nil)
    }

    /// İnceleme 2: başlık kuralı olmayan uygulamanın genel başlıklı penceresi
    /// beklemez.
    @Test func noHoldWithoutTitleRules() {
        var sim = Sim(rules: [rule("wide", [], mainDesk)])
        _ = sim.sweep()
        sim.titles = [3: "Claude"]
        #expect(sim.sweep()[3] == .some(mainDesk))
        #expect(!Routing.isHeld(title: "Claude", appName: "Claude", firstSeen: sim.now, now: sim.now,
                                titleRules: false))
    }

    // MARK: - B1 · pin kaldırıldı

    @Test func unpinnedWindowStays() {
        var sim = Sim(rules: [rule("wide", [], mainDesk)])
        sim.titles = [5: "Paper review"]
        sim.pins = [5: sessionDesk]
        #expect(sim.sweep()[5] == .some(sessionDesk))
        sim.unpin(5)
        #expect(sim.sweep()[5] == .some(nil))
        // Sonradan bu pencereye özgü kural yazılırsa alır.
        sim.rules.append(rule("own", ["Paper review"], otherDesk))
        #expect(sim.sweep()[5] == .some(otherDesk))
    }

    // MARK: - Kural silindi, pencere kapandı

    @Test func deletedRuleLeavesWindowInPlace() {
        var sim = Sim(rules: [rule("wide", [], mainDesk), rule("sess", ["Paper review"], sessionDesk)])
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
        var sim = Sim(rules: [rule("sess", ["Paper review"], sessionDesk)])
        sim.titles = [2: "Paper review"]
        _ = sim.sweep()
        #expect(sim.bindings[2] != nil)
        sim.titles = [:]
        _ = sim.sweep()
        #expect(sim.bindings.isEmpty)
        #expect(sim.firstSeen.isEmpty)
    }

    /// Bağ verilmezse (arayüzün öbür modu) eski durumsuz seçim aynen.
    @Test func noContextKeepsStatelessSelection() {
        let rules = [rule("wide", [], mainDesk)]
        #expect(Routing.select(rules: rules, sessionPins: [:], mode: .docked, windowID: 1,
                               bundleID: Self.bundle, appName: "Claude", title: "x")?.ruleID == "wide")
    }
}
