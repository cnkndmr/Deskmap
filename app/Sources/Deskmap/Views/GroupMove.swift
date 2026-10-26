import CoreGraphics
import Foundation

/// Bir uygulama grubunun (açık pencereler + kapalı pinler) başka masaüstüne
/// taşınması. Her öğe tek tek sürüklemeyle aynı yoldan gider: oturum pini
/// ve pinli pencerenin kuralı yeni hedefe (düzen korunur), pinsiz pencere
/// canlı kurulumda tek seferlik taşınır, kapalı pinin hedefi değişir.
struct GroupMovePlan: Equatable {
    struct RuleMove: Equatable { var id: String; var destination: Destination }
    struct SessionMove: Equatable {
        var window: CGWindowID
        var from: Destination
        var to: Destination
    }
    var rules: [RuleMove] = []
    var sessions: [SessionMove] = []
    /// Pinsiz, tek seferlik taşınacak pencereler.
    var windows: [CGWindowID] = []

    var isEmpty: Bool { rules.isEmpty && sessions.isEmpty && windows.isEmpty }

    /// Saf. Aynı kurala uyan birden çok pencere ya da hem pencereye hem
    /// kapalı çipe düşen kural bir kez taşınır. Hedefi zaten orası olan
    /// öğe atlanır. `context`: Router'ın yapışkan bağları (`Router.context(for:)`);
    /// pencere başlığına uyan değil, onu yerleştiren kural taşınır.
    /// `winner`: kuralın haritada görünen (kazanan) yeri (`MapPlaces.winner`);
    /// verilmezse ilk yer. "Zaten orada" buna bakar.
    static func make(group: AppGroup, to placement: Router.Placement, mode: Mode, isLive: Bool,
                     rules: [Rule], sessionPins: [CGWindowID: Destination],
                     context: Routing.Context? = nil,
                     winner: ((Rule) -> Destination?)? = nil) -> GroupMovePlan {
        make(windows: group.windows, closed: group.closed, to: placement, mode: mode,
             isLive: isLive, rules: rules, sessionPins: sessionPins, context: context, winner: winner)
    }

    /// Uygulama grubu planının gövdesi (pencereler + kapalı pinler).
    static func make(windows: [Router.WindowSnapshot], closed: [Rule], to placement: Router.Placement,
                     mode: Mode, isLive: Bool, rules: [Rule], sessionPins: [CGWindowID: Destination],
                     context: Routing.Context?, winner: ((Rule) -> Destination?)?) -> GroupMovePlan {
        var plan = GroupMovePlan()
        func moveRule(_ rule: Rule, layout: WindowLayout) {
            guard !plan.rules.contains(where: { $0.id == rule.id }) else { return }
            let next = Destination(screen: placement.screen, desktop: placement.desktop, layout: layout)
            guard !isAlreadyThere(rule, at: placement, mode: mode, winner: winner?(rule)) else { return }
            plan.rules.append(RuleMove(id: rule.id, destination: next))
        }
        for window in windows {
            if let current = sessionPins[window.id] {
                let next = Destination(screen: placement.screen, desktop: placement.desktop,
                                       layout: current.layout)
                if next != current {
                    plan.sessions.append(SessionMove(window: window.id, from: current, to: next))
                }
            } else if let rule = Routing.select(
                        rules: rules, sessionPins: [:], mode: mode, windowID: window.id,
                        bundleID: window.bundleID, appName: window.appName,
                        title: window.title, document: window.document, context: context)?.rule,
                      let current = rule[mode] {
                moveRule(rule, layout: current.layout)
            } else if isLive, WindowRow.unpinnedDropActs(
                        .desktop(screen: placement.screen, desktop: placement.desktop),
                        window: window, isLive: true) {
                plan.windows.append(window.id)
            }
        }
        for closed in closed {
            let rule = rules.first { $0.id == closed.id } ?? closed
            moveRule(rule, layout: rule[mode]?.layout ?? .full)
        }
        return plan
    }

    /// "Zaten orada" (saf): kuralın kazanan yeri (verilmezse bu moddaki ilk
    /// yeri) hedef ekran ve masaüstü. Monitörlü sıralı yerlerde (`dockedNext`)
    /// kazanan yer ilk yer olmayabilir; haritada görünen yer esas alınır.
    static func isAlreadyThere(_ rule: Rule, at placement: Router.Placement, mode: Mode,
                               winner: Destination?) -> Bool {
        guard let place = winner ?? rule[mode] else { return false }
        return place.screen == placement.screen && place.desktop == placement.desktop
    }

    /// Pin grubunun bu moddaki bütün üyelerini hedefe taşıma planı (K3):
    /// yalnız `groupID == id` olan ve bu modda yeri olan kurallar; grup dışı
    /// kural (aynı pencereye başka kural seçilse de) taşınmaz, yeri olmayan
    /// üyeye yer eklenmez. Hedefte zaten olan üye atlanır. Düzen kazanan
    /// yerinkidir. Oturum pinleri gruba girmez (K8), pinsiz pencere yoktur:
    /// plan yalnız kurallardır; canlı planda Router pencereleri kural
    /// değişimiyle taşır, öbür planda yalnız kurallar değişir.
    static func forPinGroup(_ id: String, rules: [Rule], mode: Mode, to placement: Router.Placement,
                            winner: (Rule) -> Destination?) -> GroupMovePlan {
        var plan = GroupMovePlan()
        for rule in rules where rule.groupID == id {
            guard let first = rule[mode] else { continue }
            let place = winner(rule) ?? first
            guard !isAlreadyThere(rule, at: placement, mode: mode, winner: place) else { continue }
            plan.rules.append(RuleMove(id: rule.id, destination: Destination(
                screen: placement.screen, desktop: placement.desktop, layout: place.layout)))
        }
        return plan
    }

    /// Saf. "Grubu gönder" menüsünün hedefleri: haritadaki her ekranın her
    /// masaüstü, grubun bulunduğu masaüstü hariç.
    static func sendTargets(screens: [KnownScreen], tileCounts: [String: Int],
                            current: Router.Placement) -> [WindowRow.SendTargetScreen] {
        WindowRow.sendTargets(screens: screens, tileCounts: tileCounts,
                              current: Destination(screen: current.screen, desktop: current.desktop))
            .map { screen in
                var screen = screen
                screen.desktops.removeAll(where: \.isCurrent)
                return screen
            }
            .filter { !$0.desktops.isEmpty }
    }
}
