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
    /// Eski "İkinci monitör yokken" ayarı. Artık çözümlemeyi etkilemez:
    /// listede bağlı yer yoksa rol sırasıyla yedek hep açık (K4,
    /// `Routing.resolvePlace`). Alan, eski sürümler dosyayı aynı okusun diye
    /// okunup yazılmaya devam eder.
    var fallbackToFirstExternal: Bool = true
    /// Bir kez öğrenildi (ilk bağlanış geride). Öncesinde bağlı monitörler
    /// konum sırasıyla kendiliğinden öğrenilir (yükseltmede davranış
    /// değişmez); sonrasında hatırlanmayan monitörün rolü onay bekler
    /// (`unconfirmed`). Hepsini unutmak bunu da sıfırlar.
    var learnedOnce: Bool = false
    /// Monitör (normalleştirilmiş UUID) → en son bağlıyken görülen masaüstü
    /// sayısı. Bağlı olmayan monitörün soluk kartı bu kadar masaüstü çizer
    /// (rolün planı yoksa). İsteğe bağlı alan; boşsa yazılmaz.
    var lastDesktopCount: [String: Int] = [:]

    /// Bir rolde tutulan en çok UUID (eski masa monitörleri düşer).
    static let historyLimit = 8

    var isEmpty: Bool { remembered.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case remembered, fallbackToFirstExternal, learnedOnce, lastDesktopCount
    }

    init(remembered: [String: [String]] = [:], fallbackToFirstExternal: Bool = true,
         learnedOnce: Bool? = nil) {
        self.remembered = remembered
        self.fallbackToFirstExternal = fallbackToFirstExternal
        self.learnedOnce = learnedOnce ?? !remembered.isEmpty
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
        // Alanı olmayan (bu sürümden önceki) kayıt: bir şey hatırlıyorsa öğrenilmiş sayılır.
        learnedOnce = (try? c.decodeIfPresent(Bool.self, forKey: .learnedOnce)) ?? !clean.isEmpty
        let counts = (try? c.decodeIfPresent([String: Int].self, forKey: .lastDesktopCount)) ?? [:]
        lastDesktopCount = Dictionary(
            counts.filter { $0.value >= 1 }.map { (ScreenInfo.normalize($0.key), $0.value) },
            uniquingKeysWith: { a, _ in a })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(remembered, forKey: .remembered)
        try c.encode(fallbackToFirstExternal, forKey: .fallbackToFirstExternal)
        try c.encode(learnedOnce, forKey: .learnedOnce)
        if !lastDesktopCount.isEmpty { try c.encode(lastDesktopCount, forKey: .lastDesktopCount) }
    }

    // MARK: - Masaüstü sayısı (soluk kart)

    /// Rolde en son kullanılan monitörün son görülen masaüstü sayısı.
    func lastDesktopCount(role: String) -> Int? {
        remembered[role]?.first.flatMap { lastDesktopCount[$0] }
    }

    /// Bağlı, onaylı monitörlerin masaüstü sayıları öğrenilir (saf).
    /// `counts`: rol → gerçek masaüstü sayısı.
    func learningDesktopCounts(_ counts: [String: Int],
                               assignment: [(role: String, uuid: String)]) -> DisplayRoles {
        var copy = self
        for (role, uuid) in assignment where Self.isExternalRole(role) && isConfirmed(role: role, uuid: uuid) {
            guard let count = counts[role], count >= 1 else { continue }
            copy.lastDesktopCount[ScreenInfo.normalize(uuid)] = count
        }
        return copy
    }

    /// Onay bekleyen yeni monitörün "Sıranın sonuna ekle" rolü (K6, saf):
    /// hiçbir monitörün hatırlanmadığı ve bağlı onaylı bir monitörün
    /// tutmadığı en küçük rol.
    func nextFreeRole(connected: [(role: String, uuid: String)]) -> String {
        let taken = Set(remembered.filter { !$0.value.isEmpty }.keys)
            .union(connected.filter { isConfirmed(role: $0.role, uuid: $0.uuid) }.map(\.role))
        var index = 1
        while taken.contains(Self.externalRole(index)) { index += 1 }
        return Self.externalRole(index)
    }

    /// Kart başlığı menüsünde seçilebilen monitörler (D3.4/K9, saf): bağlı
    /// ve onaylı olanlar ile hatırlanan, şu an bağlı olmayanlar (rolündeki en
    /// yeni UUID). Deskmap'in hiç tanımadığı (onay bekleyen) monitör yok.
    /// Rol sırasında.
    func knownMonitors(connected: [(role: String, uuid: String)]) -> [(role: String, uuid: String)] {
        var result: [(role: String, uuid: String)] = connected.filter {
            Self.isExternalRole($0.role) && isConfirmed(role: $0.role, uuid: $0.uuid)
        }
        let present = Set(connected.map { ScreenInfo.normalize($0.uuid) })
        for (role, list) in remembered {
            guard let uuid = list.first, !present.contains(uuid),
                  !result.contains(where: { $0.role == role }) else { continue }
            result.append((role: role, uuid: uuid))
        }
        return result.sorted { (Self.externalIndex(of: $0.role) ?? 0) < (Self.externalIndex(of: $1.role) ?? 0) }
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
    ///
    /// İlk bağlanıştan sonra yalnız onaylı eşler öğrenilir (en yeni öne
    /// geçer): hatırlanmayan bir monitörün konumdan aldığı rol, ya da
    /// hatırlanan bir monitörün başka bir rolde kalması (aynı rolde iki
    /// hatırlanan bağlı) kendiliğinden kalıcı olmaz; kullanıcı seçer.
    func learning(_ assignment: [(role: String, uuid: String)]) -> DisplayRoles {
        var copy = self
        let externals = assignment.filter { Self.isExternalRole($0.role) }
        for (role, uuid) in externals where isConfirmed(role: role, uuid: uuid) {
            copy.bind(ScreenInfo.normalize(uuid), to: role)
        }
        if !externals.isEmpty { copy.learnedOnce = true }
        return copy
    }

    // MARK: - Onay (A3/A4)

    /// Bu monitörün bu roldeki yeri onaylı mı: ilk bağlanıştan önce her şey
    /// onaylı; sonra yalnız monitör bu rolde hatırlanıyorsa.
    func isConfirmed(role: String, uuid: String) -> Bool {
        !learnedOnce || self.role(of: uuid) == role
    }

    /// Onay bekleyen roller (saf): rolü tutan monitör o rolde
    /// hatırlanmıyor. Bu rollerin düzeni (plan, pinler, adlar) monitöre
    /// uygulanmaz, rol bağlı değilmiş gibi bekler; kullanıcı haritadaki
    /// kart menüsünden ya da `deskmap screen-role` ile seçince uygulanır.
    /// Böylece kendiliğinden rol değişimi (yeni ya da unutulmuş monitör,
    /// tek kalan sanal ekran, aynı rolde iki hatırlanan) bütün düzeni sormadan
    /// öbür ekrana taşımaz.
    func unconfirmed(_ assignment: [(role: String, uuid: String)]) -> Set<String> {
        Set(assignment.filter { Self.isExternalRole($0.role) && !isConfirmed(role: $0.role, uuid: $0.uuid) }
            .map(\.role))
    }

    /// Tek bir monitörü unutur. Öteki kayıtlar ve `learnedOnce` kalır: bağlıysa
    /// rolü yeniden onay bekler (hepsini unutmak `DisplayRoles()` ile sıfırlar).
    func forgetting(_ uuid: String) -> DisplayRoles {
        let key = ScreenInfo.normalize(uuid)
        var copy = self
        for role in copy.remembered.keys {
            copy.remembered[role]?.removeAll { $0 == key }
            if copy.remembered[role]?.isEmpty == true { copy.remembered[role] = nil }
        }
        return copy
    }

    /// Menüde ve `screen-role`'de bir monitöre verilebilecek roller (saf):
    /// bağlı monitör sayısı kadar rol, artı bağlı olmayan monitörlerin
    /// hatırlanan rolleri kadar fazlası. Tek kalan sanal ekran böylece
    /// "Ekstra monitör"ü boş bırakıp "2. monitör" olabilir; boşluk büyümez.
    func choosableRoles(connected: [(role: String, uuid: String)]) -> [String] {
        let connectedUUIDs = Set(connected.map { ScreenInfo.normalize($0.uuid) })
        let away = remembered.values.filter { !$0.contains(where: connectedUUIDs.contains) }.count
        let count = connected.count + away
        return count == 0 ? [] : (1...count).map(Self.externalRole)
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

    /// Kullanıcı `uuid` monitörünü `role` rolüne verdi (K5). O rolde başka
    /// bir monitör varsa (bağlı olan; yoksa o rolde hatırlanan, bağlı
    /// olmayanlar) ikisi yer değiştirir: o monitör seçilenin eski rolünü
    /// alır. Pinler ve planlar role bağlı olduğundan düzenler de yer
    /// değiştirir, hiçbiri kaybolmaz. Seçilenin rolü yoksa (yeni monitör
    /// bir yerin yerine geçti) öteki unutulur; bağlıysa konum sırasına göre
    /// yeniden yer bulur (bir sonraki atamada).
    func choosing(_ uuid: String, for role: String,
                  current: [(role: String, uuid: String)]) -> DisplayRoles {
        guard Self.isExternalRole(role) else { return self }
        let key = ScreenInfo.normalize(uuid)
        let oldRole = current.first { ScreenInfo.normalize($0.uuid) == key }?.role
            ?? self.role(of: key)
        var copy = self
        let occupants: [String]
        if let occupant = current.first(where: { $0.role == role }) {
            occupants = [ScreenInfo.normalize(occupant.uuid)]
        } else {
            occupants = remembered[role] ?? []
        }
        // Sıra korunsun: `bind` başa ekler, en yeni en sona kalırdı.
        for other in occupants.reversed() where other != key && oldRole != role {
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
        copy.learnedOnce = true
        return copy
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

    /// Bir ekranın arayüzdeki adı (saf): harici rol için rol adı (aynı model
    /// iki monitör ayrılsın, model adı görünmesin), yoksa verilen ad.
    static func displayName(role: String, name: String?) -> String {
        isExternalRole(role) ? roleLabel(role) : (name ?? role)
    }

    /// Kart başlığındaki rol adı: "Ekstra monitör", "2. monitör" …
    static func roleLabel(_ role: String) -> String {
        let index = externalIndex(of: role) ?? 1
        return index == 1 ? L("Extra monitor") : L("Monitor %ld", index)
    }
}
