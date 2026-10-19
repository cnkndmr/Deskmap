import CoreGraphics
import Foundation

/// Harici ekran rolleri (`external`, `external-2` …) ile fiziksel monitörler
/// arasındaki kalıcı bağ. Rol eskiden yalnız konumdan gelirdi (soldan sağa):
/// ekranların yeri değişince ya da sanal ekran soldan eklenince roller, onlarla
/// birlikte kurallar, adlar ve planlar öteki monitöre kayardı.
///
/// Kural: bir monitör bir role bir kez oturunca (otomatik ya da elle) o rolü
/// korur. Monitör UUID'si macOS'un ekran kimliğidir (EDID'den türer, bu Mac'te
/// kalıcıdır); aynı model iki monitör de seri numaraları farklıysa ayrı UUID
/// alır. Hatırlanan bir rolde birden çok monitör olabilir (ofiste her masada
/// başka monitör): en son kullanılan önde.
///
/// `rules.json`'da isteğe bağlı ek alan (`displayRoles`); şema 6 değişmez.
/// Eski sürüm okurken yok sayar, yazarken düşürür: o zaman konum sırasına
/// dönülür ve ilk bağlanışta yeniden öğrenilir.
struct DisplayRoles: Codable, Equatable {

    /// Rol → o rolde görülmüş monitör UUID'leri (normalleştirilmiş, en yeni
    /// önde). Bir UUID yalnız bir rolde bulunur.
    var remembered: [String: [String]] = [:]
    /// Kuralın harici ekranı (`external-2` …) bağlı değilken pencere ilk
    /// harici ekrana (`external`), aynı masaüstü numarasına gider. Kapalıysa
    /// pencereye dokunulmaz (eski davranış).
    var fallbackToFirstExternal: Bool = true

    /// Bir rolde tutulan en çok UUID (eski masa monitörleri düşer).
    static let historyLimit = 8

    var isEmpty: Bool { remembered.isEmpty }

    private enum CodingKeys: String, CodingKey { case remembered, fallbackToFirstExternal }

    init(remembered: [String: [String]] = [:], fallbackToFirstExternal: Bool = true) {
        self.remembered = remembered
        self.fallbackToFirstExternal = fallbackToFirstExternal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: [String]].self, forKey: .remembered)) ?? [:]
        // Yalnız harici roller; boş listeler atılır, UUID'ler normalleşir.
        var clean: [String: [String]] = [:]
        for (role, uuids) in raw where Self.isExternalRole(role) {
            var seen = Set<String>()
            let list = uuids.map(ScreenInfo.normalize).filter { !$0.isEmpty && seen.insert($0).inserted }
            if !list.isEmpty { clean[role] = Array(list.prefix(Self.historyLimit)) }
        }
        remembered = clean
        fallbackToFirstExternal = (try? c.decodeIfPresent(Bool.self, forKey: .fallbackToFirstExternal)) ?? true
    }

    // MARK: - Roller

    /// `external` → 1, `external-2` → 2 …; harici rol değilse nil.
    static func externalIndex(of role: String) -> Int? {
        if role == "external" { return 1 }
        guard role.hasPrefix("external-"), let n = Int(role.dropFirst("external-".count)), n >= 2
        else { return nil }
        return n
    }

    static func isExternalRole(_ role: String) -> Bool { externalIndex(of: role) != nil }

    static func externalRole(_ index: Int) -> String { index <= 1 ? "external" : "external-\(index)" }

    /// Hatırlanan rolü olan UUID → rol (ilk eşleşme).
    func role(of uuid: String) -> String? {
        let key = ScreenInfo.normalize(uuid)
        return remembered.first { $0.value.contains(key) }?.key
    }

    // MARK: - Atama (saf)

    /// Rol atamasının girdisi olan harici ekran.
    struct Display: Equatable, Hashable {
        let uuid: String
        let minX: CGFloat
        let minY: CGFloat
        let name: String
    }

    /// Bağlı harici ekranlara rol verir. Sonuç rol sırasında.
    ///
    /// 1. Hatırlanan rolü olan ekran o rolü alır. Aynı rolde iki bağlı ekran
    ///    hatırlanıyorsa listede önde olan (en son kullanılan) kazanır.
    /// 2. Kalan ekranlar konum sırasıyla (`ScreenService.externalOrder`) boş
    ///    rollere oturur, en küçük boş rol önce: yeni bir monitör eksik
    ///    olanın yerini alır, öteki monitörün rolüne dokunmaz.
    /// Hiç kayıt yoksa sonuç eski konum sırasının aynısıdır.
    func assign(_ externals: [Display]) -> [(role: String, display: Display)] {
        let ordered = Self.positional(externals)
        var taken: [String: (display: Display, rank: Int)] = [:]
        for display in ordered {
            let key = ScreenInfo.normalize(display.uuid)
            guard let role = role(of: key), let rank = remembered[role]?.firstIndex(of: key),
                  rank < (taken[role]?.rank ?? Int.max) else { continue }
            taken[role] = (display, rank)
        }
        // Kaybeden ve hiç hatırlanmayan ekranlar konum sırasıyla boş rollere.
        let placed = Set(taken.values.map { ScreenInfo.normalize($0.display.uuid) })
        let rest = ordered.filter { !placed.contains(ScreenInfo.normalize($0.uuid)) }
        var result = taken.map { (role: $0.key, display: $0.value.display) }
        var index = 1
        for display in rest {
            while taken[Self.externalRole(index)] != nil { index += 1 }
            let role = Self.externalRole(index)
            taken[role] = (display, Int.max)
            result.append((role: role, display: display))
        }
        return result.sorted {
            (Self.externalIndex(of: $0.role) ?? 0) < (Self.externalIndex(of: $1.role) ?? 0)
        }
    }

    /// Konum sırası (soldan sağa, sonra aşağıdan yukarı, sonra UUID).
    static func positional(_ externals: [Display]) -> [Display] {
        externals.sorted {
            ScreenService.externalOrder(($0.minX, $0.minY, $0.uuid), ($1.minX, $1.minY, $1.uuid))
        }
    }

    /// Bağlı ekranların rolleri öğrenilir: her UUID kendi rolünün önüne
    /// geçer, başka rollerden silinir. Bağlı olmayan monitörlerin kayıtları
    /// kalır (yalnız sınırı aşan en eski düşer).
    func learning(_ assignment: [(role: String, uuid: String)]) -> DisplayRoles {
        var copy = self
        for (role, uuid) in assignment where Self.isExternalRole(role) {
            copy.bind(ScreenInfo.normalize(uuid), to: role)
        }
        return copy
    }

    private mutating func bind(_ uuid: String, to role: String) {
        for key in remembered.keys {
            remembered[key]?.removeAll { $0 == uuid }
            if remembered[key]?.isEmpty == true { remembered[key] = nil }
        }
        var list = remembered[role] ?? []
        list.insert(uuid, at: 0)
        remembered[role] = Array(list.prefix(Self.historyLimit))
    }

    /// Kullanıcı `uuid` monitörünü `role` rolüne verdi. O rolde şu an başka
    /// bir bağlı monitör varsa ikisi yer değiştirir (o monitör seçilenin eski
    /// rolünü alır); seçilenin rolü yoksa öteki konum sırasına göre yeniden
    /// yer bulur (bir sonraki atamada).
    func choosing(_ uuid: String, for role: String,
                  current: [(role: String, uuid: String)]) -> DisplayRoles {
        guard Self.isExternalRole(role) else { return self }
        let key = ScreenInfo.normalize(uuid)
        let oldRole = current.first { ScreenInfo.normalize($0.uuid) == key }?.role
        var copy = self
        if let occupant = current.first(where: { $0.role == role }),
           ScreenInfo.normalize(occupant.uuid) != key {
            let other = ScreenInfo.normalize(occupant.uuid)
            if let oldRole {
                copy.bind(other, to: oldRole)
            } else {
                for k in copy.remembered.keys {
                    copy.remembered[k]?.removeAll { $0 == other }
                    if copy.remembered[k]?.isEmpty == true { copy.remembered[k] = nil }
                }
            }
        }
        copy.bind(key, to: role)
        return copy
    }

    // MARK: - Eksik ekran

    /// Kuralın ekranı bağlı değilken pencerenin gideceği bağlı ekran rolü
    /// (saf). Bağlıysa kendisi; `external-N` (N ≥ 2) bağlı değil, seçenek açık
    /// ve `external` bağlıysa `external`; yoksa nil (pencereye dokunulmaz).
    static func effectiveScreen(_ screen: String, connected: Set<String>, fallback: Bool) -> String? {
        if connected.contains(screen) { return screen }
        guard fallback, let index = externalIndex(of: screen), index >= 2,
              connected.contains("external") else { return nil }
        return "external"
    }

    // MARK: - Ad

    /// Menüdeki monitör adları (UUID → etiket): ad tekse olduğu gibi; aynı
    /// adlı iki monitöre "(sol)"/"(sağ)", daha fazlasına konum sırasıyla
    /// "(1)", "(2)" … eklenir. Önceki tasarımdan (Faz 1) alındı.
    static func labels(_ externals: [Display]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, group) in Dictionary(grouping: externals, by: \.name) {
            guard group.count > 1 else {
                result[group[0].uuid] = name
                continue
            }
            let ordered = positional(group)
            for (index, display) in ordered.enumerated() {
                if ordered.count == 2 {
                    result[display.uuid] = index == 0 ? L("%@ (left)", name) : L("%@ (right)", name)
                } else {
                    result[display.uuid] = "\(name) (\(index + 1))"
                }
            }
        }
        return result
    }

    /// Kart başlığındaki rol adı: "Monitör 1", "Monitör 2" …
    static func roleLabel(_ role: String) -> String {
        L("Monitor %ld", externalIndex(of: role) ?? 1)
    }
}
