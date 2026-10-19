import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Claude pencere kayması: işlem × durum tablosu docs/bug-tables.md §B (her
/// hücrede test adı). Seçim her taramada pencerenin o anki başlığıyla
/// yeniden yapılıyor (`Routing.select`, durumsuz); başlık oynadığında ya da
/// oturum pini kalktığında pencere başka kurala düşüp taşınıyor. Bilinen
/// hatalar `withKnownIssue` ile işaretli; gerçek pencere taşınmaz.
struct WindowDriftBugTests {

    private let bundle = "com.anthropic.claudefordesktop"
    private let mainDesk = Destination(screen: "external", desktop: 2)
    private let sessionDesk = Destination(screen: "external", desktop: 5)
    private let otherDesk = Destination(screen: "builtin", desktop: 3)

    private func rule(_ id: String, _ tokens: [String], _ destination: Destination) -> Rule {
        Rule(id: id, appName: "Claude", bundleID: bundle, tokens: tokens, docked: destination)
    }

    private func select(_ rules: [Rule], title: String, window: CGWindowID = 7,
                        pins: [CGWindowID: Destination] = [:]) -> Routing.Match? {
        Routing.select(rules: rules, sessionPins: pins, mode: .docked, windowID: window,
                       bundleID: bundle, appName: "Claude", title: title)
    }

    // MARK: - B1 · Oturum pini kaldırıldı

    /// Pin varken pencere pinin yerinde; pin kalkınca uygulama geneli kural
    /// pencereyi ana pencerenin masaüstüne çeker (14.10'daki ilk kayma).
    @Test func unpinFallsBackToAppWideRule() {
        let appWide = rule("wide", [], mainDesk)
        #expect(select([appWide], title: "Paper review", pins: [7: sessionDesk])?.destination == sessionDesk)
        withKnownIssue("Pin kalkınca pencere yerinde kalmıyor, genel kurala düşüyor") {
            #expect(select([appWide], title: "Paper review") == nil)
        }
    }

    // MARK: - B2 · Yeni pencere geçici "Claude" başlığıyla açıldı

    /// Yeni oturum penceresi ilk saniyelerde "Claude" başlığını taşır: ana
    /// pencere kuralına uyar ve ana masaüstüne gider; adını alınca kendi
    /// kuralına göre ikinci kez taşınır ya da (kuralı yoksa) orada kalır.
    @Test func newWindowWithTransientTitleTakesMainWindowRule() {
        let main = rule("main", ["Claude"], mainDesk)
        withKnownIssue("Geçici başlık için bekleme yok") {
            #expect(select([main], title: "Claude", window: 42) == nil)
        }
    }

    // MARK: - B3 · Başlık parçası daha uzun başlıklarda da geçiyor

    /// "Claude" parçalı ana pencere kuralı, başlığında "Claude" geçen her
    /// oturumu da tutar (alt dizi eşleşmesi).
    @Test func mainWindowTokenMatchesLongerTitles() {
        let main = rule("main", ["Claude"], mainDesk)
        #expect(select([main], title: "Claude")?.ruleID == "main")
        withKnownIssue("Tam başlık sahibi varken alt dizi eşleşmesi") {
            #expect(select([main], title: "Claude Code notes", window: 8) == nil)
        }
    }

    // MARK: - B4 · Fork penceresi

    /// "X" kuralı "X (fork)" penceresini de tutar: iki pencere aynı yerde,
    /// üst üste.
    @Test func forkWindowSharesOriginalRule() {
        let original = rule("orig", ["Paper review"], sessionDesk)
        #expect(select([original], title: "Paper review")?.ruleID == "orig")
        withKnownIssue("Fork, asıl pencerenin kuralına uyuyor") {
            #expect(select([original], title: "Paper review (fork)", window: 9) == nil)
        }
    }

    // MARK: - B5 · Ana pencerenin başlığı değişti

    /// Ana pencerede sohbet açılınca başlık sohbet adına dönerse ana pencere
    /// kuralından düşer; o adın parçasını taşıyan başka kural varsa pencere
    /// oraya taşınır.
    @Test func titleChangeMovesWindowToAnotherRule() {
        let main = rule("main", ["Claude"], mainDesk)
        let notes = rule("notes", ["Budget"], otherDesk)
        #expect(select([main, notes], title: "Claude")?.ruleID == "main")
        withKnownIssue("Başlık değişince pencere bağlı olduğu kuraldan düşüyor") {
            #expect(select([main, notes], title: "Budget planning")?.ruleID == "main")
        }
    }

    // MARK: - B6 · Oturum yeniden adlandırıldı

    /// Kendi kuralıyla yerleşmiş oturum penceresi yeniden adlandırılınca
    /// kuralını kaybeder; uygulama geneli kural varsa ona düşer.
    @Test func renamedSessionFallsToAppWideRule() {
        let wide = rule("wide", [], mainDesk)
        let session = rule("sess", ["Paper review"], sessionDesk)
        #expect(select([wide, session], title: "Paper review")?.ruleID == "sess")
        withKnownIssue("Yeniden adlandırma pencereyi genel kurala düşürüyor") {
            #expect(select([wide, session], title: "Draft notes")?.ruleID == "sess")
        }
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
