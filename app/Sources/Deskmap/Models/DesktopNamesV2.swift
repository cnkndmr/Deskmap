import Foundation

// Masaüstü adları, şema 6 (docs/desktop-names-v2.md). Ad bir gerçek
// masaüstüne (SkyLight space kimliği) bağlıdır; kurulum, ekran ya da
// numara taşımaz. Her kurulumun ekran başına sıralı bir planı vardır
// (`DesktopPlans`); monitör takılıp çıkınca plan uygulanır. Kurallar bir ada
// (`Destination.nameID`) ya da eskisi gibi numaraya bakabilir.

/// Profilin bir masaüstü adı. `space == nil`: henüz masaüstü yok
/// (yerleşmemiş); bir sonraki plan uygulaması açar.
struct DesktopName: Codable, Equatable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var space: UInt64?

    init(id: String = UUID().uuidString, name: String, space: UInt64? = nil) {
        self.id = id
        self.name = name
        self.space = space
    }
}

/// Kurulum başına, ekran rolü başına olması gereken masaüstüleri (sıralı).
/// Girdi bir ad kimliği ya da "" (adsız masaüstü). Dizinin uzunluğu o
/// rolün o kurulumdaki masaüstü sayısıdır.
struct DesktopPlans: Codable, Equatable, Hashable {
    var docked: [String: [String]] = [:]
    var undocked: [String: [String]] = [:]

    init(docked: [String: [String]] = [:], undocked: [String: [String]] = [:]) {
        self.docked = docked
        self.undocked = undocked
    }

    private enum CodingKeys: String, CodingKey { case docked, undocked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        docked = (try? c.decodeIfPresent([String: [String]].self, forKey: .docked)) ?? [:]
        undocked = (try? c.decodeIfPresent([String: [String]].self, forKey: .undocked)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !docked.isEmpty { try c.encode(docked, forKey: .docked) }
        if !undocked.isEmpty { try c.encode(undocked, forKey: .undocked) }
    }

    subscript(mode: Mode) -> [String: [String]] {
        get { mode == .docked ? docked : undocked }
        set { if mode == .docked { docked = newValue } else { undocked = newValue } }
    }

    var isEmpty: Bool { docked.isEmpty && undocked.isEmpty }

    func entries(_ mode: Mode, _ role: String) -> [String] { self[mode][role] ?? [] }

    /// Rolün girdilerini yazar; boş dizi rolü siler.
    mutating func set(_ entries: [String], _ mode: Mode, _ role: String) {
        var table = self[mode]
        table[role] = entries.isEmpty ? nil : entries
        if table != self[mode] { self[mode] = table }
    }

    /// Adın bu kurulumdaki yeri (rol, 1 tabanlı sıra); yoksa nil.
    func place(of id: String, mode: Mode) -> Slot? {
        for role in self[mode].keys.sorted() {
            if let index = self[mode][role]?.firstIndex(of: id) {
                return Slot(screen: role, desktop: index + 1)
            }
        }
        return nil
    }

    /// Adı bu kurulumun planından çıkarır: `collapse` ise girdi silinir
    /// (sonrakiler bir yukarı), değilse "" olur.
    mutating func remove(_ id: String, mode: Mode, collapse: Bool) {
        for (role, list) in self[mode] where list.contains(id) {
            set(collapse ? list.filter { $0 != id } : list.map { $0 == id ? "" : $0 }, mode, role)
        }
    }

    /// Verilen sıraya girdiyi yazar; dizi gerekirse "" ile uzar.
    mutating func put(_ entry: String, at desktop: Int, _ mode: Mode, _ role: String) {
        guard desktop >= 1 else { return }
        var list = entries(mode, role)
        while list.count < desktop { list.append("") }
        list[desktop - 1] = entry
        set(list, mode, role)
    }

    /// Bütün ad kimlikleri (bu kurulumda).
    func ids(_ mode: Mode) -> Set<String> {
        Set(self[mode].values.flatMap { $0 }.filter { !$0.isEmpty })
    }
}

/// Bağlı ekranların canlı masaüstü sırası (yalnız normal masaüstüler).
struct LiveDesktops: Equatable {
    var mode: Mode
    var spaces: [String: [UInt64]]

    /// Space'in canlı yeri (rol, 1 tabanlı sıra).
    func place(of space: UInt64) -> Slot? {
        for role in spaces.keys.sorted() {
            if let index = spaces[role]?.firstIndex(of: space) {
                return Slot(screen: role, desktop: index + 1)
            }
        }
        return nil
    }

    func space(at slot: Slot) -> UInt64? {
        guard let list = spaces[slot.screen], slot.desktop >= 1, slot.desktop <= list.count
        else { return nil }
        return list[slot.desktop - 1]
    }

    var all: Set<UInt64> { Set(spaces.values.joined()) }
}

/// Şema 5'in (ve öncesinin) profil başına ad tabloları: yalnız okunur,
/// şema 6'ya geçiş (`MigrationV6`) bunları kullanır; yazılmaz.
struct LegacyNames: Equatable, Hashable {
    var desktopNames: [String: [String: String]] = [:]
    var desktopNameSpaces: [String: [String: UInt64]] = [:]
    var plannedDesktops: [String: Int] = [:]

    var isEmpty: Bool { desktopNames.isEmpty && desktopNameSpaces.isEmpty && plannedDesktops.isEmpty }
}

/// Ekranda bir masaüstü yeri (rol, 1 tabanlı sıra).
struct Slot: Hashable, Codable {
    var screen: String
    var desktop: Int
}

// MARK: - Arama

extension Document {

    /// Ad karşılaştırma anahtarı: kırpılmış, büyük/küçük harf duyarsız.
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func planKey(mode: Mode, screen: String) -> String { "\(mode.rawValue)|\(screen)" }

    /// Anahtar → (kurulum, ekran); eski (kurulumsuz) anahtar nil.
    static func splitNameKey(_ key: String) -> (mode: Mode, screen: String)? {
        guard let bar = key.firstIndex(of: "|"),
              let mode = Mode(rawValue: String(key[..<bar])) else { return nil }
        return (mode, String(key[key.index(after: bar)...]))
    }

    func nameRecord(_ id: String) -> DesktopName? { names.first { $0.id == id } }

    func nameRecord(named name: String) -> DesktopName? {
        let want = Self.normalizedName(name)
        guard !want.isEmpty else { return nil }
        return names.first { Self.normalizedName($0.name) == want }
    }

    func nameRecord(space: UInt64) -> DesktopName? { names.first { $0.space == space } }

    /// Satırın ad kimliği: canlı kurulumda ve gerçek masaüstü varsa canlı
    /// space'e bağlı ad; yoksa planın girdisi.
    func nameID(screen: String, desktop: Int, mode: Mode, live: LiveDesktops? = nil) -> String? {
        if let live, live.mode == mode, let list = live.spaces[screen], desktop >= 1,
           desktop <= list.count {
            return nameRecord(space: list[desktop - 1])?.id
        }
        let entries = plans.entries(mode, screen)
        guard desktop >= 1, desktop <= entries.count, !entries[desktop - 1].isEmpty,
              nameRecord(entries[desktop - 1]) != nil else { return nil }
        return entries[desktop - 1]
    }

    func desktopName(screen: String, desktop: Int, mode: Mode, live: LiveDesktops? = nil) -> String? {
        nameID(screen: screen, desktop: desktop, mode: mode, live: live).flatMap { nameRecord($0)?.name }
    }

    /// Bir kurulumun adları, ekran → masaüstü → ad (durum dosyası, CLI).
    func desktopNames(for mode: Mode, live: LiveDesktops? = nil) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var roles = Set(plans[mode].keys)
        if let live, live.mode == mode { roles.formUnion(live.spaces.keys) }
        for role in roles {
            let count = max(plans.entries(mode, role).count,
                            live?.mode == mode ? live?.spaces[role]?.count ?? 0 : 0)
            guard count > 0 else { continue }
            for desktop in 1...count {
                if let name = desktopName(screen: role, desktop: desktop, mode: mode, live: live) {
                    result[role, default: [:]][String(desktop)] = name
                }
            }
        }
        return result
    }

    /// Planın bu kurulum ve ekrandaki uzunluğu (eski "planlanan masaüstü sayısı").
    func plannedDesktops(mode: Mode, screen: String) -> Int {
        plans.entries(mode, screen).count
    }

    func pendingRemovals(mode: Mode, screen: String) -> [PendingRemoval] {
        pendingRemovals[Self.planKey(mode: mode, screen: screen)] ?? []
    }

    /// Bütün profillerde ad var mı.
    var hasAnyDesktopNames: Bool {
        !names.isEmpty || profiles.contains { $0.id != activeProfileID && !$0.names.isEmpty }
    }

    /// Bütün profillerde bir ada bağlı space'ler.
    var namedSpacesInAnyProfile: Set<UInt64> {
        var result = Set(names.compactMap(\.space))
        for profile in profiles where profile.id != activeProfileID {
            result.formUnion(profile.names.compactMap(\.space))
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

    /// Her profilin adlarına aynı dönüşümü uygular (etkin profil çalışma kopyası).
    mutating func mapAllNames(_ body: (inout [DesktopName]) -> Void) {
        var active = names
        body(&active)
        if active != names { names = active }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            var other = profiles[i].names
            body(&other)
            if other != profiles[i].names { profiles[i].names = other }
        }
    }

    // MARK: - Ad hedeflerinin önbelleği

    /// Ad hedeflerinin `screen`/`desktop` önbelleğini yeniler (bütün
    /// profiller): canlı kurulumda adın canlı yeri, yoksa o kurulumun
    /// planındaki yeri; ikisi de yoksa dokunulmaz. Önbellek yalnız eski
    /// sürümler ve haritanın "bekliyor" çipi içindir.
    mutating func refreshNameCaches(live: LiveDesktops?) {
        func refresh(_ list: inout [Rule], names: [DesktopName], plans: DesktopPlans) {
            for i in list.indices {
                for mode in Mode.allCases {
                    list[i].mapPlaces(mode) { _, destination in
                        guard let id = destination.nameID,
                              let record = names.first(where: { $0.id == id }) else { return destination }
                        var slot: Slot?
                        if let live, live.mode == mode, let space = record.space {
                            slot = live.place(of: space)
                        }
                        if slot == nil { slot = plans.place(of: id, mode: mode) }
                        guard let slot else { return destination }
                        var destination = destination
                        destination.screen = slot.screen
                        destination.desktop = slot.desktop
                        return destination
                    }
                }
            }
        }
        var active = rules
        refresh(&active, names: names, plans: plans)
        if active != rules { rules = active }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            var other = profiles[i].rules
            refresh(&other, names: profiles[i].names, plans: profiles[i].plans)
            if other != profiles[i].rules { profiles[i].rules = other }
        }
    }

    /// Hedefin ad bağı (saf): hedef yer bu kurulumda adlıysa o ad; değilse
    /// verilen ad kimliği yalnız ad var ve bu kurulumda yeri yoksa (önbellek
    /// denetlenemez) kalır; yoksa numara hedefi.
    func normalizedTarget(_ destination: Destination, mode: Mode, live: LiveDesktops?) -> Destination {
        var destination = destination
        if let slotID = nameID(screen: destination.screen, desktop: destination.desktop,
                               mode: mode, live: live) {
            destination.nameID = slotID
            return destination
        }
        if let id = destination.nameID, let record = nameRecord(id) {
            let livePlace = live?.mode == mode ? record.space.flatMap { live?.place(of: $0) } : nil
            if livePlace == nil, plans.place(of: id, mode: mode) == nil { return destination }
        }
        destination.nameID = nil
        return destination
    }

    // MARK: - R5: Deskmap'in taşımaları

    /// Deskmap içeriği bir space'ten ötekine taşıdı: bütün profillerin
    /// bağları aynı haritayla (eş zamanlı) geçer.
    mutating func applySpaceMap(_ map: [UInt64: UInt64]) {
        let moves = map.filter { $0.key != $0.value }
        guard !moves.isEmpty else { return }
        mapAllNames { list in
            for i in list.indices {
                if let space = list[i].space, let next = moves[space] { list[i].space = next }
            }
        }
    }

    // MARK: - Hayaletler

    func ghosts(on screen: String) -> [GhostDesktop] {
        ghostDesktops.filter { $0.screen == screen }
    }

    /// Bu kurulumda görünecek hayaletler: adı canlı olmayan, adı ya da bu
    /// kurulumda pini olan.
    func ghosts(on screen: String, mode: Mode) -> [GhostDesktop] {
        ghosts(on: screen).filter { ghost in
            if let name = ghost.name, nameRecord(named: name) != nil { return false }
            return ghost.name != nil || ghost.pins.contains { $0.mode == mode }
        }
    }

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
                    var places = list[index].places(pin.mode)
                    if let order = pin.order, pin.mode == .docked {
                        // Sıradaki yer kendi sırasına döner; o ekranda yeri
                        // varsa üzerine yazılmaz.
                        guard !places.contains(where: { $0.screen == target.screen }) else { return }
                        places.insert(target, at: min(order, places.count))
                        list[index].setPlaces(places, mode: pin.mode)
                    } else if places.isEmpty {
                        list[index][pin.mode] = target
                    }
                } else {
                    var rule = pin.rule
                    rule.setPlaces([], mode: .docked)
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

    /// Pin listelerini (profil, kural, mod) üçlüsüne göre tekilleştirerek birleştirir.
    static func mergedPins(_ a: [GhostDesktop.Pin], _ b: [GhostDesktop.Pin]) -> [GhostDesktop.Pin] {
        var result = a
        for pin in b where !result.contains(where: {
            $0.profileID == pin.profileID && $0.rule.id == pin.rule.id && $0.mode == pin.mode
        }) { result.append(pin) }
        return result
    }
}
