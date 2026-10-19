import CoreGraphics
import Foundation

/// Haritanın sıralı yerlerle ilgili saf kararları (docs/bug-tables.md §D):
/// hangi kart nerede ve kaç masaüstüyle durur, pin hangi masaüstünde normal
/// çip, hangisinde hayalet çip olur, yan paneldeki yer listesi. Görünümler
/// yalnız bunları çizer; kararlar test edilir.
enum MapPlaces {

    // MARK: - Kartlar (K8)

    /// Bağlı olmayan kartlar sırasının kaydırma çapası (`RevealRequest`
    /// bununla o sıraya kaydırır; gerçek pencere kimliğiyle çakışmaz).
    static let awayAnchorID = CGWindowID.max

    /// Canlı monitörlü planda bağlı kartlar üstte (eski sırasıyla), bağlı
    /// olmayan harici kartlar altta ayrı sırada. Öbür planda hepsi
    /// üstte: plan düzenlenir, bağlantı sorulmaz.
    static func cardRows(_ screens: [KnownScreen], connected: Set<String>,
                         live: Bool) -> (main: [KnownScreen], away: [KnownScreen]) {
        guard live else { return (screens, []) }
        let away = screens.filter { !$0.isBuiltin && !connected.contains($0.id) }
        let main = screens.filter { $0.isBuiltin || connected.contains($0.id) }
        return (main, away)
    }

    /// Bağlı olmayan monitörün kartındaki masaüstü sayısı: rolün planı,
    /// yoksa monitörün son görülen sayısı, yoksa 1; o ekrana yeri olan
    /// pinlerin en büyük masaüstüne dek.
    static func awayDesktopCount(planned: Int, lastSeen: Int?, used: Int) -> Int {
        let base = planned > 0 ? planned : (lastSeen ?? 1)
        return max(base, used, 1)
    }

    // MARK: - Çipler

    /// Pinin bu planda haritada görünen (kazanan) yeri. Canlı planda
    /// taramanın seçtiği yer (bağlı ilk yer ya da yedek, `Routing.resolvePlace`);
    /// adlı masaüstü önbellekteki yerinde sayılır. Öbür planda ilk yer.
    static func winner(_ rule: Rule, mode: Mode, live: Bool,
                       usable: Set<String>) -> Routing.ResolvedPlace? {
        let places = rule.places(mode)
        guard !places.isEmpty else { return nil }
        guard live else { return Routing.ResolvedPlace(destination: places[0], choice: .place(0)) }
        var cached = places
        for i in cached.indices { cached[i].nameID = nil }
        guard let resolved = Routing.resolvePlace(cached, connected: Array(usable), held: [])
        else { return nil }
        var destination = resolved.destination
        if case .place(let index) = resolved.choice { destination.nameID = places[index].nameID }
        return Routing.ResolvedPlace(destination: destination, choice: resolved.choice)
    }

    /// Kazanan yeri bu masaüstü olan pinler (kapalı pin ve öbür plan çipleri).
    static func pinned(_ rules: [Rule], mode: Mode, live: Bool, usable: Set<String>,
                       screen: String, desktop: Int) -> [Rule] {
        rules.filter { rule in
            guard let winner = winner(rule, mode: mode, live: live, usable: usable)?.destination
            else { return false }
            return winner.screen == screen && winner.desktop == desktop
        }
    }

    /// Kesik çerçeveli hayalet çip: pinin bu masaüstündeki, şu an
    /// kullanılmayan yeri. `order`: listedeki sırası (1 tabanlı).
    struct Ghost: Equatable, Identifiable {
        let rule: Rule
        let order: Int
        var id: String { "\(rule.id)#\(order)" }
        var label: String { "\(order) · \(rule.isAppWide ? rule.appName : rule.title)" }
    }

    /// Bu masaüstündeki hayalet çipler: kazanan olmayan yerler, yalnız
    /// takılı olmayan monitörün kartında (canlı planda) ya da öbür planda.
    /// Takılı ama onay bekleyen monitörün kartında yok: orada pencereler
    /// zaten görünür, düzen onayı bekler. Yalnız monitörlü plan.
    /// `connected`: canlı planda takılı bütün roller (onay bekleyenler dahil).
    static func ghosts(_ rules: [Rule], mode: Mode, live: Bool, usable: Set<String>,
                       connected: Set<String>, screen: String, desktop: Int) -> [Ghost] {
        guard mode == .docked, !usable.contains(screen), !(live && connected.contains(screen))
        else { return [] }
        return rules.flatMap { rule -> [Ghost] in
            let places = rule.places(.docked)
            guard places.count > 1 || live else { return [] }
            let winner = winner(rule, mode: mode, live: live, usable: usable)
            return places.enumerated().compactMap { index, place in
                guard place.screen == screen, place.desktop == desktop,
                      winner?.choice != .place(index) else { return nil }
                return Ghost(rule: rule, order: index + 1)
            }
        }
    }

    // MARK: - Yan panel

    struct PlaceRow: Equatable, Identifiable {
        let index: Int
        let destination: Destination
        /// Ekranı bağlı ve onaylı.
        let connected: Bool
        /// Taramada kullanılan yer.
        let wins: Bool
        var id: Int { index }
    }

    /// Yan paneldeki sıralı liste: her yer, bağlı mı, kazanan mı.
    /// `fallback`: listede bağlı yer yok, pencere rol sırasıyla yedekte.
    static func rows(_ rule: Rule, live: Bool,
                     usable: Set<String>) -> (rows: [PlaceRow], fallback: Routing.ResolvedPlace?) {
        let resolved = winner(rule, mode: .docked, live: live, usable: usable)
        let rows = rule.places(.docked).enumerated().map { index, place in
            PlaceRow(index: index, destination: place,
                     connected: live && usable.contains(place.screen),
                     wins: live && resolved?.choice == .place(index))
        }
        return (rows, live && resolved?.choice == .fallback ? resolved : nil)
    }
}
