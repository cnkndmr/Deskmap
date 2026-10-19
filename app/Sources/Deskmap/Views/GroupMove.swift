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
    static func make(group: AppGroup, to placement: Router.Placement, mode: Mode, isLive: Bool,
                     rules: [Rule], sessionPins: [CGWindowID: Destination],
                     context: Routing.Context? = nil) -> GroupMovePlan {
        var plan = GroupMovePlan()
        func moveRule(_ rule: Rule, layout: WindowLayout) {
            guard !plan.rules.contains(where: { $0.id == rule.id }) else { return }
            let next = Destination(screen: placement.screen, desktop: placement.desktop, layout: layout)
            guard next != rule[mode] else { return }
            plan.rules.append(RuleMove(id: rule.id, destination: next))
        }
        for window in group.windows {
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
        for closed in group.closed {
            let rule = rules.first { $0.id == closed.id } ?? closed
            moveRule(rule, layout: rule[mode]?.layout ?? .full)
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
