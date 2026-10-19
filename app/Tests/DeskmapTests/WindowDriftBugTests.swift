import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Claude pencere kayması: işlem × durum tablosu docs/bug-tables.md §B (her
/// hücrede test adı). Kök neden: durumsuz seçim (`Routing.select`, `context`
/// yok) her taramada pencerenin o anki başlığına bakar; başlık oynadığında ya
/// da oturum pini kalktığında pencere başka kurala düşer. Her hücre iki
/// katmanı birden sabitler: durumsuz seçim hatayı hâlâ yeniden üretir
/// (teşhis; bağ verilmeyen yerde kayma geri gelir) ve gerçek Router
/// (`RouterHarness`, bağlarla) düzeltir. Gerçek pencere taşınmaz.
@MainActor
struct WindowDriftBugTests {

    private let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let sessionDesk = Destination(screen: "external", desktop: 5)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: bundle, tokens: tokens, docked: destination)
    }

    /// Durumsuz seçim (eski katman, bağsız).
    private func select(_ rules: [Rule], title: String, window: CGWindowID = 7,
                        pins: [CGWindowID: Destination] = [:]) -> Routing.Match? {
        Routing.select(rules: rules, sessionPins: pins, mode: .docked, windowID: window,
                       bundleID: bundle, appName: "Claude", title: title)
    }

    // MARK: - B1 · Oturum pini kaldırıldı

    /// Pin varken pencere pinin yerinde; pin kalkınca durumsuz seçim uygulama
    /// geneli kurala düşer (14.10'daki ilk kayma). Router pini kaldırırken
    /// "yerinde kal" bağı verir.
    @Test func unpinLeavesWindowInPlace() {
        let appWide = rule("wide", [], mainDesk)
        #expect(select([appWide], title: "Paper review", pins: [7: sessionDesk])?.destination == sessionDesk)
        #expect(select([appWide], title: "Paper review")?.ruleID == "wide")      // teşhis

        let sim = RouterHarness(rules: [appWide])
        sim.titles = [7: "Paper review"]
        sim.pin(7, sessionDesk)
        #expect(sim.sweep()[7] == .some(sessionDesk))
        sim.unpin(7)
        #expect(sim.sweep()[7] == .some(nil))
        #expect(sim.bindings[7] == .stay(minimum: appWide.specificity + 1))
    }

    // MARK: - B2 · Yeni pencere geçici "Claude" başlığıyla açıldı

    /// Yeni oturum penceresi ilk saniyelerde "Claude" başlığını taşır:
    /// durumsuz seçim onu ana pencere kuralına verir. Router başlık oturana
    /// kadar bekletir.
    @Test func newWindowWithTransientTitleWaits() {
        let main = rule("main", ["Claude"], mainDesk)
        #expect(select([main], title: "Claude", window: 42)?.ruleID == "main")  // teşhis

        let sim = RouterHarness(rules: [main])
        _ = sim.sweep()
        sim.titles = [42: "Claude"]
        #expect(sim.sweep()[42] == .some(nil))
        #expect(sim.router.routingContext.held == [42])
    }

    // MARK: - B3 · Başlık parçası daha uzun başlıklarda da geçiyor

    /// "Claude" parçalı ana pencere kuralı, durumsuz seçimde başlığında
    /// "Claude" geçen her oturumu tutar (alt dizi). Router'da tam başlık
    /// sahibi (ana pencere) açıkken kural yalnız tam eşleşir.
    @Test func mainWindowTokenSkipsLongerTitlesWhileOwned() {
        let main = rule("main", ["Claude"], mainDesk)
        #expect(select([main], title: "Claude")?.ruleID == "main")
        #expect(select([main], title: "Claude Code notes", window: 8)?.ruleID == "main")  // teşhis

        let sim = RouterHarness(rules: [main])
        sim.titles = [7: "Claude", 8: "Claude Code notes"]
        let out = sim.sweep()
        #expect(out[7] == .some(mainDesk))
        #expect(out[8] == .some(nil))
        #expect(sim.router.routingContext.exactOwned == ["main"])
    }

    // MARK: - B4 · Fork penceresi

    /// "X" kuralı durumsuz seçimde "X (fork)" penceresini de tutar: iki
    /// pencere üst üste. Router'da asıl pencere açıkken fork kurala uymaz.
    @Test func forkWindowDoesNotShareOriginalRule() {
        let original = rule("orig", ["Paper review"], sessionDesk)
        #expect(select([original], title: "Paper review")?.ruleID == "orig")
        #expect(select([original], title: "Paper review (fork)", window: 9)?.ruleID == "orig")  // teşhis

        let sim = RouterHarness(rules: [original])
        sim.titles = [7: "Paper review", 9: "Paper review (fork)"]
        let out = sim.sweep()
        #expect(out[7] == .some(sessionDesk))
        #expect(out[9] == .some(nil))
    }

    // MARK: - B5 · Ana pencerenin başlığı değişti

    /// Ana pencerede sohbet açılınca başlık sohbet adına döner: durumsuz
    /// seçim pencereyi o adın kuralına taşır. Router'da pencere bağlı olduğu
    /// kuralda kalır.
    @Test func titleChangeKeepsWindowOnItsRule() {
        let main = rule("main", ["Claude"], mainDesk)
        let notes = rule("notes", ["Budget"], otherDesk)
        #expect(select([main, notes], title: "Claude")?.ruleID == "main")
        #expect(select([main, notes], title: "Budget planning")?.ruleID == "notes")  // teşhis

        let sim = RouterHarness(rules: [main, notes])
        sim.titles = [7: "Claude"]
        #expect(sim.sweepRules()[7] == .some("main"))
        sim.titles[7] = "Budget planning"
        #expect(sim.sweepRules()[7] == .some("main"))
    }

    // MARK: - B6 · Oturum yeniden adlandırıldı

    /// Kendi kuralıyla yerleşmiş oturum penceresi yeniden adlandırılınca
    /// durumsuz seçimde uygulama geneli kurala düşer. Router'da kendi
    /// kuralında kalır.
    @Test func renamedSessionKeepsItsRule() {
        let wide = rule("wide", [], mainDesk)
        let session = rule("sess", ["Paper review"], sessionDesk)
        #expect(select([wide, session], title: "Paper review")?.ruleID == "sess")
        #expect(select([wide, session], title: "Draft notes")?.ruleID == "wide")  // teşhis

        let sim = RouterHarness(rules: [wide, session])
        sim.titles = [7: "Paper review"]
        #expect(sim.sweepRules()[7] == .some("sess"))
        sim.titles[7] = "Draft notes"
        #expect(sim.sweepRules()[7] == .some("sess"))
    }

    // MARK: - Doğru çalışan hücreler

    /// B7: daha özgül kural sonradan uyarsa o kazanır (beklenen).
    @Test func moreSpecificRuleTakesOver() {
        let wide = rule("wide", [], mainDesk)
        let session = rule("sess", ["Paper review"], sessionDesk)
        #expect(select([wide, session], title: "Claude")?.ruleID == "wide")
        #expect(select([wide, session], title: "Paper review")?.ruleID == "sess")
    }

    /// B8: kural silinince pencere serbest kalır (beklenen).
    @Test func deletedRuleReleasesWindow() {
        #expect(select([], title: "Paper review") == nil)
    }

    /// B9: oturum pini her kuraldan önce gelir (beklenen).
    @Test func sessionPinBeatsEveryRule() {
        let session = rule("sess", ["Paper review"], sessionDesk)
        #expect(select([session], title: "Paper review", pins: [7: otherDesk])?.destination == otherDesk)
    }
}
