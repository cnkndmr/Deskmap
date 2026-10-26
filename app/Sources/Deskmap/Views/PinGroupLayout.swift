import CoreGraphics
import Foundation

/// Bir masaüstünde çizilen pin grubu kutusu: grubun bu masaüstündeki açık
/// pencereleri ve kapalı (ya da gölgede kalan) pinleri. Grup dağınıksa
/// (üyeleri başka masaüstlerinde de) her masaüstünde ayrı kutu çizilir (K4).
struct PinGroupBox: Identifiable, Equatable {
    let group: PinGroup
    /// Bu masaüstünde açık, kazanan kuralı bu grupta olan pencereler.
    var windows: [Router.WindowSnapshot]
    /// Bu masaüstünde kapalı ya da gölgede kalan üyeler.
    var closed: [Rule]
    /// Bu modda üyesi olan öbür masaüstü numaraları (aynı ekran, sıralı).
    var elsewhere: [Int] = []
    /// Başka ekranda da üye var.
    var otherScreens = false
    /// Uygulama grubunun kimliğiyle (`AppGroup.id`, bundleID) çakışmaz.
    var id: String { Self.idPrefix + group.id }
    var total: Int { windows.count + closed.count }
    /// Grup başka masaüstünde/ekranda da var: kutuyu herhangi bir yere
    /// taşımak (kendi masaüstü dahil) bütün üyeleri orada toplar.
    var isScattered: Bool { !elsewhere.isEmpty || otherScreens }

    static let idPrefix = "pg:"
}

/// Pin grubu kutularının saf kararları (görünümler yalnız çizer).
enum PinGroupLayout {

    /// Pencerenin kazanan kalıcı kuralı (saf): Router ile aynı seçim
    /// (`Routing.select`, oturum pinleri ve yapışkan bağlar). Oturum pini
    /// kazanırsa nil: o pencere gruba girmez (K8).
    static func winningRule(_ window: Router.WindowSnapshot, rules: [Rule],
                                        sessionPins: [CGWindowID: Destination], mode: Mode,
                                        context: Routing.Context?) -> Rule? {
        Routing.select(rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                       bundleID: window.bundleID, appName: window.appName, title: window.title,
                       document: window.document, context: context)?.rule
    }

    /// `windows` ve `closed`'u böler: kutular (`groups` sırasıyla, boş
    /// olmayanlar) ve kalanlar (uygulama gruplarına gider, K9). Pencerenin
    /// kuralı `ruleFor` ile bulunur (`winningRule`); bilinmeyen `groupID`
    /// grupsuz sayılır.
    static func split(windows: [Router.WindowSnapshot], closed: [Rule],
                                  groups: [PinGroup],
                                  ruleFor: (Router.WindowSnapshot) -> Rule?)
        -> (boxes: [PinGroupBox], restWindows: [Router.WindowSnapshot], restClosed: [Rule]) {
        let known = Set(groups.map(\.id))
        var openByGroup: [String: [Router.WindowSnapshot]] = [:]
        var closedByGroup: [String: [Rule]] = [:]
        var restWindows: [Router.WindowSnapshot] = []
        var restClosed: [Rule] = []
        for window in windows {
            if let group = ruleFor(window)?.groupID, known.contains(group) {
                openByGroup[group, default: []].append(window)
            } else {
                restWindows.append(window)
            }
        }
        for rule in closed {
            if let group = rule.groupID, known.contains(group) {
                closedByGroup[group, default: []].append(rule)
            } else {
                restClosed.append(rule)
            }
        }
        let boxes = groups.compactMap { group -> PinGroupBox? in
            let box = PinGroupBox(group: group, windows: openByGroup[group.id] ?? [],
                                  closed: closedByGroup[group.id] ?? [])
            return box.total > 0 ? box : nil
        }
        return (boxes, restWindows, restClosed)
    }

    /// Kutuların gruplarındaki üyelerin bu modda haritada çizildiği yerler
    /// (saf): grup kimliği → yerler. Kutularla aynı kaynak: açık üye
    /// penceresinin gerçek yerinde (`openAt`, kural kimliği → pencerenin
    /// yeri; kural o pencerenin kazananı), kapalı üye kazanan yerinde
    /// (`winner`, `MapPlaces.winner`), kazananı yoksa (bağlı olmayan
    /// monitör) ilk yerinde (soluk kart; `GroupMovePlan.forPinGroup` de
    /// onu taşır). İlk yer (`rule[mode]`) monitör sıralı listede yanlış
    /// "Masaüstü N üzerinde de" ipucu verirdi.
    static func memberPlaces(for boxes: [PinGroupBox], document: Document, mode: Mode,
                             openAt: [String: Router.Placement] = [:],
                             winner: (Rule) -> Destination?) -> [String: [Destination]] {
        var places: [String: [Destination]] = [:]
        for box in boxes {
            places[box.group.id] = document.pinGroupMembers(box.group.id, mode: mode).compactMap { rule in
                if let open = openAt[rule.id] { return Destination(screen: open.screen, desktop: open.desktop) }
                return winner(rule) ?? rule[mode]
            }
        }
        return places
    }

    /// Açık pencerelerin kazanan kuralı → pencerenin yeri (saf). Aynı kural
    /// birden çok pencerenin kazananıysa hepsi sayılmaz, ilki yeter: ipucu
    /// yalnız "başka yerde de var mı" der.
    static func openPlacements(_ windows: [Router.WindowSnapshot],
                               ruleFor: (Router.WindowSnapshot) -> Rule?) -> [String: Router.Placement] {
        var out: [String: Router.Placement] = [:]
        for window in windows {
            guard let placement = window.placement, let rule = ruleFor(window), rule.groupID != nil,
                  out[rule.id] == nil else { continue }
            out[rule.id] = placement
        }
        return out
    }

    /// Kutuların "başka yerde de" bilgisi: üyelerin bu moddaki kazanan
    /// yerleri (`MapPlaces.winner` ile aynı kaynak). `memberPlaces`: grup
    /// kimliği → üyelerin kazanan yerleri.
    static func annotate(_ boxes: inout [PinGroupBox], screen: String, desktop: Int,
                                     memberPlaces: [String: [Destination]]) {
        for i in boxes.indices {
            let places = memberPlaces[boxes[i].group.id] ?? []
            boxes[i].elsewhere = Array(Set(places.filter { $0.screen == screen && $0.desktop != desktop }
                .map(\.desktop))).sorted()
            boxes[i].otherScreens = places.contains { $0.screen != screen }
        }
    }

    /// "Gruba ekle" hedefleri: bu modda üyesi olan (görünür) gruplar, kuralın
    /// kendi grubu hariç. Grup tek masaüstünde olmasa da listelenir.
    static func addTargets(groups: [PinGroup], members: Set<String>,
                                       excluding: String?) -> [PinGroup] {
        groups.filter { members.contains($0.id) && $0.id != excluding }
    }

    /// "Gruba ekle" menüsünün satır adları (saf). Ad tekse yalnız ad; aynı
    /// adlı gruplar (K10) üye sayısıyla, o da aynıysa ilk üyenin başlığıyla
    /// ayrılır ki kullanıcı pinlerin hangi gruba gideceğini görsün.
    static func menuTitles(_ groups: [PinGroup], rules: [Rule], mode: Mode) -> [String: String] {
        func key(_ name: String) -> String { name.lowercased() }
        var nameCount: [String: Int] = [:]
        for group in groups { nameCount[key(group.name), default: 0] += 1 }
        var members: [String: [Rule]] = [:]
        for rule in rules where rule[mode] != nil {
            if let id = rule.groupID { members[id, default: []].append(rule) }
        }
        func counted(_ group: PinGroup) -> String {
            let n = members[group.id]?.count ?? 0
            return n == 1 ? L("%@ · 1 pin", group.name) : L("%@ · %ld pins", group.name, n)
        }
        var countedCount: [String: Int] = [:]
        for group in groups where nameCount[key(group.name), default: 0] > 1 {
            countedCount[key(counted(group)), default: 0] += 1
        }
        var titles: [String: String] = [:]
        for group in groups {
            guard nameCount[key(group.name), default: 0] > 1 else {
                titles[group.id] = group.name
                continue
            }
            let title = counted(group)
            if countedCount[key(title), default: 0] > 1, let first = members[group.id]?.first {
                titles[group.id] = L("%@ · %@", title, first.title)
            } else {
                titles[group.id] = title
            }
        }
        return titles
    }

    /// Bu modda üyesi olan grupların kimlikleri (saf).
    static func groupsWithMembers(_ rules: [Rule], mode: Mode) -> Set<String> {
        Set(rules.compactMap { $0[mode] == nil ? nil : $0.groupID })
    }
}
