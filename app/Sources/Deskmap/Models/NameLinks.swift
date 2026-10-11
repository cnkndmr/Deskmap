import Foundation

// Adlandırılmış masaüstü = tek mantıksal masaüstü. Kimliği ad (büyük/küçük
// harf duyarsız) ile `desktopNameSpaces`'taki space kimliğidir; her kurulumun
// `desktopNames` tablosu onun o kurulumdaki yeridir. Aşağıdaki saf yardımcılar
// ad ↔ yer eşlemesini, öbür kurulumdaki karşılığı ve pinlerin ada bağlı
// kalmasını sağlar. Şema değişmez (rules.json sürümü aynı).

/// Ekranda bir masaüstü yeri.
struct Slot: Hashable {
    var screen: String
    var desktop: Int
}

/// Bir adın bir kurulumdaki yeri.
struct NamePlace: Equatable, Hashable {
    var mode: Mode
    var screen: String
    var desktop: Int
    var space: UInt64?

    var slot: Slot { Slot(screen: screen, desktop: desktop) }
}

/// Bir adın bir kurulumda yer değiştirmesi (pinleri de taşınır).
struct NameMove: Equatable {
    var mode: Mode
    var name: String
    var from: Slot
    var to: Slot
}

/// Silindiği anlaşılan ya da yerleştirilemeyen ad (Router hayalete çevirir).
struct DroppedName: Equatable {
    var place: NamePlace
    var name: String
}

/// `reconcileNames` sonucu.
struct ReconcileResult: Equatable {
    var changed = false
    var moves: [NameMove] = []
    var dropped: [DroppedName] = []
    /// Masaüstü yerinde ama ad yerleşemedi (numarası dolu); hayalet açılmaz.
    var unplaced: [DroppedName] = []
    var adopted: [NamePlace] = []
}

extension Document {

    /// Ad karşılaştırma anahtarı: kırpılmış, büyük/küçük harf duyarsız.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Adın bütün kurulumlardaki yerleri (belirlenimci sırada).
    func places(ofName name: String) -> [NamePlace] {
        let want = Self.normalizedName(name)
        guard !want.isEmpty else { return [] }
        var result: [NamePlace] = []
        for (key, list) in desktopNames.sorted(by: { $0.key < $1.key }) {
            guard let parts = Self.splitNameKey(key) else { continue }
            let slots = list.compactMap { slot, value -> (Int, String)? in
                Int(slot).map { ($0, value) }
            }.sorted { $0.0 < $1.0 }
            for (desktop, value) in slots where Self.normalizedName(value) == want {
                result.append(NamePlace(mode: parts.mode, screen: parts.screen, desktop: desktop,
                                        space: desktopNameSpaces[key]?[String(desktop)]))
            }
        }
        return result
    }

    /// Adın bu kurulumdaki (tek) yeri.
    func place(mode: Mode, ofName name: String) -> NamePlace? {
        places(ofName: name).first { $0.mode == mode }
    }

    /// Bu yerdeki adın öbür kurulumlardaki karşılığı: önce bağlı space
    /// kimliğiyle, bulunamazsa adla. Yer numarasına hiç bakılmaz.
    func counterparts(of place: NamePlace, name: String? = nil) -> [NamePlace] {
        let known = name ?? desktopName(screen: place.screen, desktop: place.desktop, mode: place.mode)
        var result: [NamePlace] = []
        for mode in Mode.allCases where mode != place.mode {
            // Önce ad: masaüstü sıralaması pencereleri taşır, gerçek
            // masaüstünü değil; bağlı space kimlikleri iki kurulumda
            // çaprazlanabilir. Kimlik yalnız adla bulunamazsa.
            var found: NamePlace?
            if let known {
                found = places(ofName: known).first { $0.mode == mode }
            }
            if found == nil, let space = place.space {
                found = namePlaces(in: mode).first { $0.space == space }
            }
            if let found { result.append(found) }
        }
        return result
    }

    /// Bir kurulumdaki bütün adlı yerler.
    private func namePlaces(in mode: Mode) -> [NamePlace] {
        var result: [NamePlace] = []
        for (key, list) in desktopNames.sorted(by: { $0.key < $1.key }) {
            guard let parts = Self.splitNameKey(key), parts.mode == mode else { continue }
            for slot in list.keys.compactMap(Int.init).sorted() {
                result.append(NamePlace(mode: mode, screen: parts.screen, desktop: slot,
                                        space: desktopNameSpaces[key]?[String(slot)]))
            }
        }
        return result
    }

    /// Bütün profillerin kurallarına aynı dönüşümü uygular (etkin profil
    /// `rules`, diğerleri kendi listesi). `body`: (kurallar, profil kimliği).
    mutating func mapAllRules(_ body: (inout [Rule], String) -> Void) {
        var active = rules
        body(&active, activeProfileID)
        if active != rules { rules = active }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            var other = profiles[i].rules
            body(&other, profiles[i].id)
            if other != profiles[i].rules { profiles[i].rules = other }
        }
    }

    /// Adlı masaüstleri yer değiştirince pinleri de götürür: her kurulumda
    /// `from` yerindeki pinler eş zamanlı `to`'ya geçer (takas güvenli).
    mutating func applyPinMoves(_ moves: [NameMove]) {
        var table: [Mode: [Slot: Slot]] = [:]
        for move in moves where move.from != move.to { table[move.mode, default: [:]][move.from] = move.to }
        guard !table.isEmpty else { return }
        mapAllRules { list, _ in
            for i in list.indices {
                for mode in Mode.allCases {
                    guard var destination = list[i][mode],
                          let to = table[mode]?[Slot(screen: destination.screen,
                                                     desktop: destination.desktop)]
                    else { continue }
                    destination.screen = to.screen
                    destination.desktop = to.desktop
                    list[i][mode] = destination
                }
            }
        }
    }

    /// Adın bir kurulumdaki yerinde pini olup öbür kurulumda hedefi olmayan
    /// kurallara, öbür kurulumdaki yerini yazar. Var olan hedefin üzerine
    /// asla yazmaz.
    /// `adoptedIn`: adın yeni bağlandığı kurulum. Orada adın öbür
    /// kurulumdaki pinleri eski (numaraya bağlı) hedefi de ezer: ad
    /// bağlanınca pinler onu izler (düzen korunur).
    mutating func mirrorPins(forName name: String, adoptedIn: Mode? = nil) {
        let all = places(ofName: name)
        guard all.count > 1 else { return }
        mapAllRules { list, _ in
            for i in list.indices {
                for source in all {
                    guard let destination = list[i][source.mode],
                          destination.screen == source.screen,
                          destination.desktop == source.desktop else { continue }
                    for target in all where target.mode != source.mode {
                        let current = list[i][target.mode]
                        guard current == nil || target.mode == adoptedIn else { continue }
                        list[i][target.mode] = Destination(
                            screen: target.screen, desktop: target.desktop,
                            layout: current?.layout ?? destination.layout)
                    }
                }
            }
        }
    }

    /// Adı bu hedefin öbür kurulumdaki karşılığı olan masaüstü (yoksa nil).
    private func twin(of destination: Destination, mode: Mode, in other: Mode) -> Slot? {
        guard let name = desktopName(screen: destination.screen, desktop: destination.desktop, mode: mode),
              let found = place(mode: other, ofName: name) else { return nil }
        return found.slot
    }

    /// Bir kuralın `mode` hedefi `old`'dan `new`'a değişince öbür kurulumdaki
    /// eşini adla izleyerek günceller: adlı masaüstünün öbür kurulumdaki
    /// yerine yazar ya da (eski yerinde duruyorsa) kaldırır. Yalnız ekran ya
    /// da masaüstü değiştiyse çalışır (düzen adımları dokunmaz).
    func mirroredPins(_ rule: Rule, mode: Mode, old: Destination?, new: Destination?) -> Rule {
        if let old, let new, old.screen == new.screen, old.desktop == new.desktop { return rule }
        var rule = rule
        for other in Mode.allCases where other != mode {
            let oldTwin = old.flatMap { twin(of: $0, mode: mode, in: other) }
            let newTwin = new.flatMap { twin(of: $0, mode: mode, in: other) }
            let current = rule[other]
            let atOldTwin = current != nil && oldTwin != nil
                && current?.screen == oldTwin?.screen && current?.desktop == oldTwin?.desktop
            if let newTwin, let new {
                if current == nil || atOldTwin {
                    rule[other] = Destination(screen: newTwin.screen, desktop: newTwin.desktop,
                                              layout: current?.layout ?? new.layout)
                }
            } else if atOldTwin && new == nil {
                // Pin kaldırıldı: adlı karşılığı da kalkar. Adsız masaüstüne
                // taşındıysa öbür kurulumun pini yerinde kalır (yalnız bağ
                // kopar), sessizce silinmez.
                rule[other] = nil
            }
        }
        return rule
    }

    // MARK: - Hayalet pinlerini geri yazma

    /// Hayalette saklanan pinleri kurallara yazar: `destination` her pin için
    /// yeni hedefi verir (nil = atla). Var olan hedefin üzerine yazılmaz; aynı
    /// anahtarlı kural varsa o kullanılır, çift kural eklenmez.
    mutating func applyGhostPins(_ pins: [GhostDesktop.Pin],
                                 destination: (GhostDesktop.Pin) -> Destination?) {
        for pin in pins {
            guard let target = destination(pin) else { continue }
            func apply(_ list: inout [Rule]) {
                let index = list.firstIndex { $0.id == pin.rule.id }
                    ?? list.firstIndex { $0.sameKey(as: pin.rule) }
                if let index {
                    if list[index][pin.mode] == nil { list[index][pin.mode] = target }
                } else {
                    var rule = pin.rule
                    rule.docked = nil
                    rule.undocked = nil
                    rule[pin.mode] = target
                    list.append(rule)
                }
            }
            if pin.profileID == activeProfileID {
                apply(&rules)
            } else if let i = profiles.firstIndex(where: { $0.id == pin.profileID }) {
                apply(&profiles[i].rules)
            }
        }
    }

    /// Adın kurulum başına canlı yeri.
    func livePlaces(ofName name: String) -> [Mode: NamePlace] {
        var result: [Mode: NamePlace] = [:]
        for found in places(ofName: name) where result[found.mode] == nil { result[found.mode] = found }
        return result
    }

    /// Canlı bir masaüstü hayaletin adını aldı: hayalet tüketilir, pinleri o
    /// adın her kurulumdaki yerine geçer (yeri henüz olmayan kurulumun pini
    /// kayıtlı yerinde bekler).
    mutating func absorbGhosts(named name: String) {
        let want = Self.normalizedName(name)
        while let index = ghostDesktops.firstIndex(where: {
            $0.name.map(Self.normalizedName) == want
        }) {
            let ghost = ghostDesktops.remove(at: index)
            let found = livePlaces(ofName: name)
            applyGhostPins(ghost.pins) { pin in
                guard let found = found[pin.mode] else { return pin.destination }
                var destination = pin.destination
                destination.screen = found.screen
                destination.desktop = found.desktop
                return destination
            }
        }
    }

    // MARK: - Normalleştirme (açılışta, tek seferlik ve idempotent)

    /// Bozuk/eski durumu toparlar: aynı kurulumda yinelenen adı atar, aynı
    /// adlı hayaletleri birleştirir, adı canlı olan hayaleti tüketir. Veri
    /// kaybı yok: yinelenen ad yalnız ad olarak düşer (pinler numarada kalır).
    /// Değişiklik olduysa true.
    @discardableResult
    mutating func normalizeNameLinks() -> Bool {
        let before = self
        // I1: kurulum başına her ad bir kez (küçük anahtar kazanır).
        for mode in Mode.allCases {
            var seenNames = Set<String>()
            for key in desktopNames.keys.sorted() where Self.splitNameKey(key)?.mode == mode {
                for slot in (desktopNames[key] ?? [:]).keys.sorted(by: {
                    (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1)
                }) {
                    let normalized = Self.normalizedName(desktopNames[key]?[slot] ?? "")
                    if normalized.isEmpty || !seenNames.insert(normalized).inserted {
                        desktopNames[key]?[slot] = nil
                        desktopNameSpaces[key]?[slot] = nil
                    }
                }
                if desktopNames[key]?.isEmpty == true { desktopNames[key] = nil }
                if desktopNameSpaces[key]?.isEmpty == true { desktopNameSpaces[key] = nil }
            }
        }
        // I4: aynı adlı hayaletler birleşir; adı canlı olan hayalet tüketilir.
        var merged: [GhostDesktop] = []
        for ghost in ghostDesktops {
            if let name = ghost.name, !Self.normalizedName(name).isEmpty,
               let i = merged.firstIndex(where: {
                   $0.name.map(Self.normalizedName) == Self.normalizedName(name)
               }) {
                merged[i].pins = Self.mergedPins(merged[i].pins, ghost.pins)
            } else {
                merged.append(ghost)
            }
        }
        if merged != ghostDesktops { ghostDesktops = merged }
        for ghost in ghostDesktops {
            guard let name = ghost.name, !places(ofName: name).isEmpty else { continue }
            absorbGhosts(named: name)
        }
        return self != before
    }

    /// Pin listelerini (profil, kural, mod) üçlüsüne göre tekilleştirerek birleştirir.
    static func mergedPins(_ a: [GhostDesktop.Pin], _ b: [GhostDesktop.Pin]) -> [GhostDesktop.Pin] {
        var result = a
        for pin in b where !result.contains(where: {
            $0.profileID == pin.profileID && $0.rule.id == pin.rule.id && $0.mode == pin.mode
        }) { result.append(pin) }
        return result
    }
}
