import AppKit
import Combine
import Foundation

/// Bilinen bir ekran: rol kimliği ve kullanıcıya gösterilecek ad.
struct KnownScreen: Codable, Equatable, Identifiable, Hashable {
    var id: String        // builtin, external, external-2 ...
    var name: String
    var aspect: Double    // genişlik / yükseklik
    /// Kullanılabilir alanın boyutu (pt); sabit boyutlu düzen önizlemesi
    /// için. Eski kayıtlarda yok.
    var visibleWidth: Double?
    var visibleHeight: Double?

    /// Kaydedilmiş gerçek kullanılabilir alan; ekran bu sürümde hiç
    /// bağlanmadıysa nil (sabit boyuta çevirme o zaman kapalı).
    var knownVisibleSize: CGSize? {
        guard let visibleWidth, let visibleHeight, visibleWidth > 0, visibleHeight > 0
        else { return nil }
        return CGSize(width: visibleWidth, height: visibleHeight)
    }

    /// Önizleme için kullanılabilir alan; bilinmiyorsa en-boy oranından
    /// 1000 pt yüksekliğe göre tahmin (yalnız çizim için).
    var visibleSize: CGSize {
        knownVisibleSize ?? CGSize(width: 1000 * max(aspect, 0.5), height: 1000)
    }

    var isBuiltin: Bool { id == "builtin" }
}

/// Adlandırılmış bir pin kümesi. Aktif profilin kuralları `Document.rules`
/// olarak yaşar ve her değişiklikte profile geri yazılır.
struct Profile: Codable, Equatable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var rules: [Rule] = []
}

/// `rules.json` içeriği. Kural ve profil işlemleri saf değer işlemleridir;
/// `Store` bunları çağırıp sonucu yayınlar ve diske yazar.
/// Etkin olmayan modda silinmiş, gerçek silmesi bekleyen masaüstü.
/// `desktop`: silindiği andaki sıra (önceki bekleyen silmelerden sonra);
/// `space`: o an bilinen SkyLight space kimliği (ekran bağlıysa). Mod
/// etkinleşince önce kimlik aranır; macOS masaüstülerini başka ekrandan
/// eklese de doğru masaüstü silinir. Kimlik yoksa sıra kullanılır.
struct PendingRemoval: Codable, Equatable, Hashable {
    var desktop: Int
    var space: UInt64?
}

/// Deskmap dışında (Mission Control) silinmiş, adı ya da pini olan
/// masaüstü. Haritada ekranın sonunda hayalet satır olarak durur; pinler
/// burada saklanır ki sonraki masaüstüne kaymasınlar. Geri getirilince yeni
/// masaüstü açılır, ad ve pinler ona döner.
struct GhostDesktop: Codable, Equatable, Hashable, Identifiable {
    /// Saklanan pin: hangi profilin hangi kuralının hangi moddaki hedefi.
    /// `rule`: kural pinle birlikte tamamen kalktıysa geri eklemek için kopya.
    struct Pin: Codable, Equatable, Hashable {
        var profileID: String
        var mode: Mode
        var rule: Rule
        var destination: Destination
    }
    var id: String = UUID().uuidString
    var screen: String
    var name: String?
    /// Silindiği andaki sırası (yalnız bilgi).
    var desktop: Int
    var deletedAt: Date
    var pins: [Pin] = []
}

struct Document: Codable, Equatable {
    var version: Int = Document.currentVersion
    var enabled: Bool = true
    var screens: [KnownScreen] = []
    /// Aktif profilin kuralları (router bunu okur).
    var rules: [Rule] = []
    var profiles: [Profile] = []
    var activeProfileID: String = ""
    /// Kurulum hatırlatması (Dock "Assign To" vb.) kullanıcı tarafından
    /// kapatıldı mı? Canlı denetlenen ayarlar bozuksa kart yine görünür.
    var setupNoticeDismissed: Bool = false
    /// Mod ve ekran başına istenen en az masaüstü sayısı (anahtar
    /// `planKey`). Etkin olmayan modda "+ Masaüstü" ile eklenen masaüstü
    /// burada durur; mod etkinleşince Router eksikleri Mission Control ile
    /// yaratır. Profilden bağımsız (masaüstüleri ekranın, kuralların değil).
    var plannedDesktops: [String: Int] = [:]
    /// Etkin olmayan modda silinen masaüstüleri (anahtar `planKey`), silme
    /// sırasıyla. Pinler silme anında kayar; gerçek masaüstünü Router mod
    /// etkinleşince Mission Control ile siler. Laptop ekranının masaüstüleri
    /// iki modda ortak olduğu için hemen silmek öbür kurulumu da bozardı.
    var pendingRemovals: [String: [PendingRemoval]] = [:]
    /// Masaüstü adları: ekran kimliği → masaüstü numarası (metin) → ad.
    /// Profilden ve moddan bağımsız (masaüstüleri ekranın; laptop
    /// masaüstüleri iki kurulumda aynı, harici ekranlar yalnız monitörlü
    /// kurulumda var). Masaüstü taşınınca ya da silinince adlar da kayar.
    var desktopNames: [String: [String: String]] = [:]
    /// Adın bağlı olduğu gerçek masaüstü (SkyLight space kimliği), aynı
    /// biçimde. macOS'ta masaüstü Mission Control'den taşınır ya da silinirse
    /// ad numarayla değil kimlikle izlenir (`reconcileDesktopNames`).
    var desktopNameSpaces: [String: [String: UInt64]] = [:]
    /// Deskmap dışında silinmiş masaüstüleri (bkz. `GhostDesktop`).
    var ghostDesktops: [GhostDesktop] = []

    /// Okunan dosyanın `version` alanı (yazılmaz). Bu sürümden yeniyse
    /// dosya daha yeni bir Deskmap'e ait; üzerine yazılmamalı.
    var fileVersion: Int = Document.currentVersion
    /// Okunurken atlanan bozuk kural sayısı (yazılmaz).
    var droppedRuleCount = 0

    /// Bu sürümün yazdığı şema. 4: düzenlerde `fixed` (sabit boyut); eski
    /// sürüm bu alanı bilmez, dosyayı salt okunur açar (üstüne yazıp sabit
    /// boyutları silmesin).
    static let currentVersion = 4

    var isFromNewerVersion: Bool { fileVersion > Self.currentVersion }

    init() {
        let profile = Profile(name: Self.defaultProfileName)
        profiles = [profile]
        activeProfileID = profile.id
    }

    /// Yeni ya da profilsiz (v1/v2) belgede üretilen profilin adı; kullanıcı
    /// verisidir, kaydedildikten sonra dil değişse de aynı kalır.
    static let defaultProfileName = L("Default")

    private enum CodingKeys: String, CodingKey {
        case version, enabled, screens, rules, profiles, activeProfileID, settings
        case setupNoticeDismissed, plannedDesktops, pendingRemovals, desktopNames
        case desktopNameSpaces, ghostDesktops
    }

    private struct LegacySettings: Decodable { var enabled: Bool? }

    /// Profil kaydı: `Profile` ile aynı zorunlu alanlar, kuralları
    /// hoşgörülü okunur (bozuk kural atlanır).
    private struct ProfileRecord: Decodable {
        var id: String
        var name: String
        var rules: LossyArray<Rule>
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.currentVersion
        // Sayı değilse eski dosya sayılır (alan daha önce hiç okunmuyordu).
        fileVersion = (try? c.decode(Int.self, forKey: .version)) ?? 1
        let lossyRules = try c.decodeIfPresent(LossyArray<Rule>.self, forKey: .rules)
        rules = lossyRules?.elements ?? []
        droppedRuleCount = lossyRules?.droppedCount ?? 0

        if let flag = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = flag
        } else if let legacy = try? c.decode(LegacySettings.self, forKey: .settings) {
            enabled = legacy.enabled ?? true
        }

        // v2 ekran kayıtları; v1 kayıtları (uuid/role) atlanır, yeniden keşfedilir.
        screens = (try? c.decode([KnownScreen].self, forKey: .screens)) ?? []

        // v3 profiller; yoksa (v1/v2) mevcut kurallar "Varsayılan" profil olur.
        let records = (try? c.decode([ProfileRecord].self, forKey: .profiles)) ?? []
        profiles = records.map { Profile(id: $0.id, name: $0.name, rules: $0.rules.elements) }
        droppedRuleCount += records.reduce(0) { $0 + $1.rules.droppedCount }
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID) ?? ""
        setupNoticeDismissed = try c.decodeIfPresent(Bool.self, forKey: .setupNoticeDismissed) ?? false
        plannedDesktops = (try? c.decodeIfPresent([String: Int].self, forKey: .plannedDesktops)) ?? [:]
        pendingRemovals = (try? c.decodeIfPresent(
            [String: [PendingRemoval]].self, forKey: .pendingRemovals)) ?? [:]
        desktopNames = Self.migratedNames((try? c.decodeIfPresent(
            [String: [String: String]].self, forKey: .desktopNames)) ?? [:])
        desktopNameSpaces = Self.migratedNames((try? c.decodeIfPresent(
            [String: [String: UInt64]].self, forKey: .desktopNameSpaces)) ?? [:])
        ghostDesktops = (try? c.decodeIfPresent([GhostDesktop].self, forKey: .ghostDesktops)) ?? []
        if profiles.isEmpty {
            let profile = Profile(name: Self.defaultProfileName, rules: rules)
            profiles = [profile]
            activeProfileID = profile.id
        } else if let active = profiles.first(where: { $0.id == activeProfileID }) {
            // Aktif profilin kayıtlı kuralları ile üst düzey `rules` aynı
            // olmalı; üst düzey daha güncel kabul edilir (yarım kalan yazım).
            if c.contains(.rules) == false { rules = active.rules }
        } else {
            activeProfileID = profiles[0].id
            rules = profiles[0].rules
        }
        // Şema 4'ten önce yazılmış sabit boyutlarda oran karşılığı yoktu
        // (0/0/1/1); eski sürüm salt okunur açsa da "Tam" görmesin diye
        // bilinen ekran boyutuyla doldurulur.
        if fileVersion < 4 {
            rules = Self.backfillingFixed(rules, screens: screens)
            profiles = profiles.map {
                Profile(id: $0.id, name: $0.name, rules: Self.backfillingFixed($0.rules, screens: screens))
            }
        }
        // Ad bağları: yinelenen ad, eski/ikili hayalet toparlanır (idempotent).
        if !isFromNewerVersion { normalizeNameLinks() }
    }

    /// Sabit boyutlu hedeflere oran karşılığı yazar (saf); ekran boyutu
    /// bilinmiyorsa dokunmaz.
    static func backfillingFixed(_ rules: [Rule], screens: [KnownScreen]) -> [Rule] {
        func fill(_ destination: Destination?) -> Destination? {
            guard var destination, let fixed = destination.layout.fixed,
                  let size = screens.first(where: { $0.id == destination.screen })?.knownVisibleSize
            else { return destination }
            destination.layout = WindowLayout(fixed: fixed, screenSize: size)
            return destination
        }
        return rules.map { rule in
            var rule = rule
            rule.docked = fill(rule.docked)
            rule.undocked = fill(rule.undocked)
            return rule
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(screens, forKey: .screens)
        try c.encode(rules, forKey: .rules)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(activeProfileID, forKey: .activeProfileID)
        try c.encode(setupNoticeDismissed, forKey: .setupNoticeDismissed)
        if !plannedDesktops.isEmpty {
            try c.encode(plannedDesktops, forKey: .plannedDesktops)
        }
        if !pendingRemovals.isEmpty {
            try c.encode(pendingRemovals, forKey: .pendingRemovals)
        }
        if !desktopNames.isEmpty {
            try c.encode(desktopNames, forKey: .desktopNames)
        }
        if !desktopNameSpaces.isEmpty {
            try c.encode(desktopNameSpaces, forKey: .desktopNameSpaces)
        }
        if !ghostDesktops.isEmpty {
            try c.encode(ghostDesktops, forKey: .ghostDesktops)
        }
    }

    // MARK: - Masaüstü adları

    /// Adlar pinler gibi kuruluma bağlıdır (anahtar `planKey`): monitörlü
    /// kurulumda monitöre taşınan "Nova", laptop kurulumunda laptop'taki
    /// yerinde kalır; monitör çıkınca orada görünür. Laptop masaüstüleri iki
    /// kurulumda aynı fiziksel masaüstü olduğu için laptop'a verilen ad iki
    /// kuruluma birden yazılır.
    static func nameModes(screen: String, mode: Mode) -> [Mode] {
        screen == "builtin" ? Mode.allCases : [mode]
    }

    /// Anahtar → (kurulum, ekran); eski (kurulumsuz) anahtar nil.
    static func splitNameKey(_ key: String) -> (mode: Mode, screen: String)? {
        guard let bar = key.firstIndex(of: "|"),
              let mode = Mode(rawValue: String(key[..<bar])) else { return nil }
        return (mode, String(key[key.index(after: bar)...]))
    }

    /// Eski biçim (anahtar yalnız ekran) → kuruluma bağlı biçim: laptop
    /// adları iki kurulumda, harici ekranınkiler monitörlü kurulumda.
    static func migratedNames<T>(_ table: [String: [String: T]]) -> [String: [String: T]] {
        var result: [String: [String: T]] = [:]
        for (key, list) in table {
            if splitNameKey(key) != nil {
                result[key, default: [:]].merge(list) { _, new in new }
                continue
            }
            for mode in nameModes(screen: key, mode: .docked) {
                result[planKey(mode: mode, screen: key), default: [:]].merge(list) { old, _ in old }
            }
        }
        return result
    }

    func desktopName(screen: String, desktop: Int, mode: Mode) -> String? {
        desktopNames[Self.planKey(mode: mode, screen: screen)]?[String(desktop)]
    }

    /// Bir kurulumun adları, ekran → masaüstü → ad (durum dosyası, CLI).
    func desktopNames(for mode: Mode) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for (key, list) in desktopNames {
            guard let parts = Self.splitNameKey(key), parts.mode == mode else { continue }
            result[parts.screen] = list
        }
        return result
    }

    /// Ad verir; boş ad (boşluklar kırpılır) adı siler. `space`: o anki
    /// gerçek masaüstü kimliği (bilinmiyorsa sonraki taramada bağlanır).
    /// Adlandırılmış masaüstü tek mantıksal masaüstüdür: yeniden adlandırma
    /// ve ad silme öbür kurulumdaki karşılığına (bağlı kimlik, yoksa eski ad)
    /// da uygulanır. Aynı kurulumda başka masaüstünde olan ad (büyük/küçük
    /// harf duyarsız) reddedilir: false döner, hiçbir şey değişmez.
    @discardableResult
    mutating func setDesktopName(_ name: String?, screen: String, desktop: Int, mode: Mode,
                                 space: UInt64? = nil) -> Bool {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = Self.planKey(mode: mode, screen: screen)
        let slot = String(desktop)
        let oldName = desktopNames[key]?[slot]
        let here = NamePlace(mode: mode, screen: screen, desktop: desktop,
                             space: desktopNameSpaces[key]?[slot])
        let linked = oldName.map { counterparts(of: here, name: $0) } ?? []
        if !trimmed.isEmpty {
            func clash(_ target: Mode, _ ownSlot: Slot?) -> Bool {
                places(ofName: trimmed).contains { $0.mode == target && $0.slot != ownSlot }
            }
            if clash(mode, Slot(screen: screen, desktop: desktop)) { return false }
            for twin in linked where clash(twin.mode, twin.slot) { return false }
        }
        func write(_ target: NamePlace, _ value: String?, _ bound: UInt64?) {
            let key = Self.planKey(mode: target.mode, screen: target.screen)
            let slot = String(target.desktop)
            var names = desktopNames[key] ?? [:]
            names[slot] = value
            desktopNames[key] = names.isEmpty ? nil : names
            var spaces = desktopNameSpaces[key] ?? [:]
            spaces[slot] = value == nil ? nil : bound
            desktopNameSpaces[key] = spaces.isEmpty ? nil : spaces
        }
        write(here, trimmed.isEmpty ? nil : trimmed, space)
        for twin in linked { write(twin, trimmed.isEmpty ? nil : trimmed, twin.space) }
        if linked.isEmpty, !trimmed.isEmpty {
            // Karşılık yok: laptop masaüstü iki kurulumda aynı yerde. Yalnız
            // boş ve var olabilecek bir yere yazılır (hayalet ad açılmaz).
            for target in Self.nameModes(screen: screen, mode: mode) where target != mode {
                let planned = plannedDesktops(mode: target, screen: screen)
                guard place(mode: target, ofName: trimmed) == nil,
                      desktopName(screen: screen, desktop: desktop, mode: target) == nil,
                      planned == 0 || desktop <= planned else { continue }
                write(NamePlace(mode: target, screen: screen, desktop: desktop, space: space),
                      trimmed, space)
            }
        }
        if !trimmed.isEmpty { absorbGhosts(named: trimmed) }
        return true
    }

    /// Verilen kurulumlardaki adları yeni yerlerine taşır (Deskmap'in kendi
    /// masaüstü işlemleri): `place` eski (ekran, masaüstü) için yeni yeri
    /// verir; nil = yer değişmedi, `(_, 0)` = ad düşer. Yeri değişen adın
    /// kimlik bağı düşer; sonraki taramada yeni numarasındaki masaüstüne
    /// bağlanır (Deskmap sırayı pencereleri taşıyarak değiştirir, gerçek
    /// masaüstüleri değil). Öbür kurulumun adlarına dokunulmaz. Yer değiştiren
    /// adları döndürür (pinleri `applyPinMoves` ile götürülür).
    @discardableResult
    mutating func remapDesktopNames(modes: [Mode],
                                    _ place: (String, Int) -> (screen: String, desktop: Int)?) -> [NameMove] {
        remapNames { mode, screen, desktop in
            modes.contains(mode) ? place(screen, desktop) : nil
        }
    }

    /// `remapDesktopNames`'in kurulumu da gören çekirdeği.
    @discardableResult
    mutating func remapNames(_ place: (Mode, String, Int) -> (screen: String, desktop: Int)?) -> [NameMove] {
        var names: [String: [String: String]] = [:]
        var spaces: [String: [String: UInt64]] = [:]
        var moves: [NameMove] = []
        for (key, list) in desktopNames {
            guard let parts = Self.splitNameKey(key) else {
                names[key] = list
                if let bound = desktopNameSpaces[key] { spaces[key] = bound }
                continue
            }
            for (slot, name) in list {
                guard let desktop = Int(slot) else { continue }
                let moved = place(parts.mode, parts.screen, desktop)
                let next = moved ?? (parts.screen, desktop)
                guard next.desktop >= 1 else { continue }
                let nextKey = Self.planKey(mode: parts.mode, screen: next.screen)
                names[nextKey, default: [:]][String(next.desktop)] = name
                if next.screen == parts.screen && next.desktop == desktop {
                    if let space = desktopNameSpaces[key]?[slot] { spaces[key, default: [:]][slot] = space }
                } else {
                    moves.append(NameMove(mode: parts.mode, name: name,
                                          from: Slot(screen: parts.screen, desktop: desktop),
                                          to: Slot(screen: next.screen, desktop: next.desktop)))
                }
            }
        }
        if names != desktopNames { desktopNames = names }
        if spaces != desktopNameSpaces { desktopNameSpaces = spaces }
        return moves
    }

    /// Etkin kurulumun adlarını gerçek masaüstülerine göre yerleştirir:
    /// `spaces`: bağlı ekranların sıralı masaüstü kimlikleri; `seen`: bu
    /// oturumda daha önce görülmüş kimlikler; `previous`: bir önceki okuma
    /// (kurulum değişince yeni laptop masaüstlerini bulmak için). Öbür
    /// kurulumun adlarına dokunulmaz: monitör takılıp çıkarılırken macOS
    /// masaüstüleri ekranlar arasında kaydırır, o kurulumun adları kendi
    /// yerlerinde kalmalı.
    /// - Bağlı kimlik bir ekranda bulunursa ad oraya gider (Mission
    ///   Control'de sıra ya da ekran değişse de); adın pinleri de gider.
    /// - Kimlik bu oturumda görülmüş ama artık yoksa masaüstü silinmiştir:
    ///   ad `dropped`'a girer (Router hayalete çevirir). Ekranın bağlı bütün
    ///   kimlikleri birden yoksa kimlikler yenilenmiştir: silme sayılmaz, ad
    ///   numarasında kalır ve yeniden bağlanır.
    /// - Bağ yoksa ya da kimlik hiç görülmediyse (yeniden başlatma) ad
    ///   numarasında kalır ve oradaki masaüstüne bağlanır.
    /// - Ekran bağlı değilse dokunulmaz. Çakışmada kimlikle bulunan kazanır.
    /// - Sahiplenme: öbür kurulumda adlı, bağlı masaüstü artık bu kurulumun
    ///   ekranındaysa (macOS monitör masaüstülerini laptop'a taşıdı) ve ad bu
    ///   kurulumda yoksa oraya adlanır; pinleri karşı kurulumdan yansıtılır.
    ///   Kimlikler yenilendiyse ve kurulum değiştiyse, yalnız bayat monitör
    ///   adları laptop'a yeni eklenen masaüstülerine, özgün sırayla, sayılar
    ///   birebir tutuyorsa atanır.
    /// - `live`: şu an gerçekten var olan bütün kimlikler (`spaces` mantıksal
    ///   liste olup kuyruktaki silmeleri düşmüş olabilir; nil = `spaces`).
    ///   Canlı kimliğe bağlı ad asla silinmiş sayılmaz; yeri bulunamayan ad
    ///   (numarası dolu, sonrası yok) hayalete değil `unplaced`'a girer: pinleri
    ///   başka bir canlı masaüstünden alınmaz.
    mutating func reconcileNames(spaces: [String: [UInt64]], seen: Set<UInt64>, mode: Mode,
                                 previous: [String: [UInt64]] = [:],
                                 live: Set<UInt64>? = nil) -> ReconcileResult {
        let original = self
        var result = ReconcileResult()
        var location: [UInt64: (screen: String, desktop: Int)] = [:]
        for (screen, list) in spaces {
            for (index, id) in list.enumerated() { location[id] = (screen, index + 1) }
        }
        let live = live ?? Set(spaces.values.joined())
        // Kimlikleri yenilenmiş ekranlar: bağlı kimliklerinin hiçbiri yok.
        // Önceki okuma varsa ölçüt onun kimlikleri (biri bile duruyorsa silme
        // gerçektir); yoksa adı bağlı kimliklerin hiçbiri.
        var renewed = Set<String>()
        for (screen, list) in spaces where !list.isEmpty {
            if let before = previous[screen], !before.isEmpty {
                if !before.contains(where: { location[$0] != nil }) { renewed.insert(screen) }
                continue
            }
            let bound = desktopNameSpaces[Self.planKey(mode: mode, screen: screen)]?.values
            if let bound, !bound.isEmpty, !bound.contains(where: { location[$0] != nil }) {
                renewed.insert(screen)
            }
        }
        var names: [String: [String: String]] = [:]
        var bindings: [String: [String: UInt64]] = [:]
        for (key, list) in desktopNames where Self.splitNameKey(key)?.mode != mode {
            names[key] = list
            if let bound = desktopNameSpaces[key] { bindings[key] = bound }
        }
        var activeNames = Set<String>()
        func put(_ name: String, _ screen: String, _ desktop: Int, _ space: UInt64?) -> Bool {
            let key = Self.planKey(mode: mode, screen: screen)
            let slot = String(desktop)
            guard names[key]?[slot] == nil else { return false }
            names[key, default: [:]][slot] = name
            if let space { bindings[key, default: [:]][slot] = space }
            activeNames.insert(Self.normalizedName(name))
            return true
        }
        var rest: [(screen: String, desktop: Int, name: String, space: UInt64?)] = []
        // Önce kimliğiyle bulunanlar (sıralı: sonuç belirlenimci olsun).
        for (key, list) in desktopNames.sorted(by: { $0.key < $1.key }) {
            guard let parts = Self.splitNameKey(key), parts.mode == mode else { continue }
            for (slot, name) in list.sorted(by: { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }) {
                guard let desktop = Int(slot) else { continue }
                let space = desktopNameSpaces[key]?[slot]
                if let space, let found = location[space] {
                    if put(name, found.screen, found.desktop, space) {
                        if found.screen != parts.screen || found.desktop != desktop {
                            result.moves.append(NameMove(
                                mode: mode, name: name,
                                from: Slot(screen: parts.screen, desktop: desktop),
                                to: Slot(screen: found.screen, desktop: found.desktop)))
                        }
                        continue
                    }
                }
                rest.append((parts.screen, desktop, name, space))
            }
        }
        func drop(_ item: (screen: String, desktop: Int, name: String, space: UInt64?)) {
            result.dropped.append(DroppedName(
                place: NamePlace(mode: mode, screen: item.screen, desktop: item.desktop,
                                 space: item.space),
                name: item.name))
        }
        for item in rest {
            // Silinmiş masaüstü: kimlik bu oturumda canlı görülmüş ve artık
            // hiçbir listede yok. Ad eşleşmesi ya da numara tek başına yetmez.
            if let space = item.space, seen.contains(space), !live.contains(space),
               location[space] == nil, !renewed.contains(item.screen) {
                drop(item)
                continue
            }
            if let list = spaces[item.screen] {
                let live = item.desktop <= list.count ? list[item.desktop - 1] : nil
                if put(item.name, item.screen, item.desktop, live ?? item.space) { continue }
                // Numarası kimlikle gelen başka ada kaldı: ilk boş numara.
                var n = item.desktop + 1
                while names[Self.planKey(mode: mode, screen: item.screen)]?[String(n)] != nil { n += 1 }
                // Var olmayan masaüstüne ad yazılmaz (hayalet ad olmasın).
                // Masaüstü silinmiş değil: hayalet açılmaz (o numaradaki pinler
                // başka bir canlı masaüstünün), yalnız ad yerleşemedi.
                guard n <= list.count else {
                    result.unplaced.append(DroppedName(
                        place: NamePlace(mode: mode, screen: item.screen, desktop: item.desktop,
                                         space: item.space),
                        name: item.name))
                    continue
                }
                if put(item.name, item.screen, n, list[n - 1]) {
                    result.moves.append(NameMove(
                        mode: mode, name: item.name,
                        from: Slot(screen: item.screen, desktop: item.desktop),
                        to: Slot(screen: item.screen, desktop: n)))
                }
            } else {
                _ = put(item.name, item.screen, item.desktop, item.space)
            }
        }

        // Sahiplenme 1: öbür kurulumun bağlı kimliği bu kurulumun ekranında.
        var adoptedNames: [String] = []
        for other in Mode.allCases where other != mode {
            for key in desktopNames.keys.sorted() where Self.splitNameKey(key)?.mode == other {
                for slot in (desktopNames[key] ?? [:]).keys.sorted(by: {
                    (Int($0) ?? .max) < (Int($1) ?? .max)
                }) {
                    guard let name = desktopNames[key]?[slot],
                          !activeNames.contains(Self.normalizedName(name)),
                          let space = desktopNameSpaces[key]?[slot],
                          let found = location[space],
                          put(name, found.screen, found.desktop, space) else { continue }
                    adoptedNames.append(name)
                    result.adopted.append(NamePlace(mode: mode, screen: found.screen,
                                                    desktop: found.desktop, space: space))
                }
            }
        }
        // Sahiplenme 2: kimlikler yenilenmiş; kurulum değişti, monitör
        // masaüstleri laptop'un yeni masaüstüne dönüştü. Sayılar birebir
        // tutarsa özgün sırayla atanır, tutmazsa dokunulmaz.
        let gone = previous.keys.filter { $0 != "builtin" && spaces[$0] == nil }.sorted()
        if !gone.isEmpty, let laptop = spaces["builtin"] {
            let known = Set(previous.values.joined())
            let fresh = laptop.indices.filter { !known.contains(laptop[$0]) }.map { $0 + 1 }
            let total = gone.reduce(0) { $0 + (previous[$1]?.count ?? 0) }
            if !fresh.isEmpty, fresh.count == total {
                var offset = 0
                for screen in gone {
                    let count = previous[screen]?.count ?? 0
                    for other in Mode.allCases where other != mode {
                        let key = Self.planKey(mode: other, screen: screen)
                        for slot in (desktopNames[key] ?? [:]).keys.sorted(by: {
                            (Int($0) ?? .max) < (Int($1) ?? .max)
                        }) {
                            guard let desktop = Int(slot), desktop >= 1, desktop <= count,
                                  let name = desktopNames[key]?[slot],
                                  !activeNames.contains(Self.normalizedName(name)) else { continue }
                            let target = fresh[offset + desktop - 1]
                            if put(name, "builtin", target, laptop[target - 1]) {
                                adoptedNames.append(name)
                                result.adopted.append(NamePlace(
                                    mode: mode, screen: "builtin", desktop: target,
                                    space: laptop[target - 1]))
                            }
                        }
                    }
                    offset += count
                }
            }
        }
        if names != desktopNames || bindings != desktopNameSpaces {
            desktopNames = names
            desktopNameSpaces = bindings
        }
        applyPinMoves(result.moves)
        for name in adoptedNames {
            absorbGhosts(named: name)
            mirrorPins(forName: name, adoptedIn: mode)
        }
        syncTravellingBindings(mode: mode)
        result.changed = self != original
        return result
    }

    /// Monitör masaüstü monitör çıkınca aynı kimlikle laptop'a geçer. Etkin
    /// kurulumda dış ekrandaki adın bağlı kimliği değiştiyse (Deskmap'te
    /// sıralama pencereleri taşır, masaüstünü değil) öbür kurulumda aynı
    /// adın laptop bağı da o kimliğe çekilir; o kimliği tutan başka ad eski
    /// kimliği alır (yalnız takas; kimlik orada bağlı değilse dokunulmaz), böylece çıkarışta adlar doğru masaüstüne oturur.
    mutating func syncTravellingBindings(mode: Mode) {
        for (key, list) in desktopNameSpaces {
            guard let parts = Self.splitNameKey(key), parts.mode == mode,
                  parts.screen != "builtin" else { continue }
            for (slot, id) in list {
                guard let name = desktopNames[key]?[slot] else { continue }
                for other in Mode.allCases where other != mode {
                    let otherKey = Self.planKey(mode: other, screen: "builtin")
                    guard let place = places(ofName: name).first(where: {
                              $0.mode == other && $0.screen == "builtin" }),
                          var bindings = desktopNameSpaces[otherKey] else { continue }
                    let own = String(place.desktop)
                    let old = bindings[own]
                    // Yalnız takas: kimlik öbür kurulumda zaten bağlıysa
                    // (yenilenen kimlik yeni bağ olup sahte silme üretmesin).
                    guard old != id,
                          let holder = bindings.first(where: { $0.value == id && $0.key != own })?.key
                    else { continue }
                    bindings[holder] = old
                    bindings[own] = id
                    desktopNameSpaces[otherKey] = bindings
                }
            }
        }
    }

    /// `reconcileNames`'in eski imzası: yalnız değişti mi bilgisi. Silinmiş
    /// adlar burada hayalete çevrilmez (Router `reconcileNames` kullanır).
    @discardableResult
    mutating func reconcileDesktopNames(spaces: [String: [UInt64]], seen: Set<UInt64>,
                                        mode: Mode) -> Bool {
        reconcileNames(spaces: spaces, seen: seen, mode: mode).changed
    }

    // MARK: - Hayalet masaüstüleri

    func ghosts(on screen: String) -> [GhostDesktop] {
        ghostDesktops.filter { $0.screen == screen }
    }

    /// Bu kurulumda görünecek hayaletler: adı ya da bu kurulumda pini olan,
    /// adı hiçbir kurulumda canlı olmayan.
    func ghosts(on screen: String, mode: Mode) -> [GhostDesktop] {
        ghosts(on: screen).filter { ghost in
            if let name = ghost.name, !places(ofName: name).isEmpty { return false }
            return ghost.name != nil || ghost.pins.contains { $0.mode == mode }
        }
    }

    /// Bir (kurulum, ekran, masaüstü) yeri.
    private struct Target: Hashable {
        var mode: Mode
        var screen: String
        var desktop: Int
    }

    /// Silinen masaüstü + adı varsa öbür kurulumlardaki karşılıkları.
    /// `live` verilirse canlı bir masaüstüne bağlı karşılık atlanır: aynı ad
    /// başka bir gerçek masaüstünde yaşıyor, silinmiş değil (yalnız ad eşleşmesi
    /// silme sebebi olmaz).
    private func removalTargets(screen: String, desktop: Int, modes: [Mode], name: String?,
                                droppedSpace: UInt64? = nil, droppedMode: Mode? = nil,
                                live: Set<UInt64>? = nil)
        -> (targets: [Target], name: String?) {
        var targets = modes.map { Target(mode: $0, screen: screen, desktop: desktop) }
        var name = name
        var seeds: [NamePlace] = []
        for target in targets {
            let key = Self.planKey(mode: target.mode, screen: screen)
            guard let found = desktopNames[key]?[String(desktop)] else { continue }
            // Düşen ad verildiyse o slotta şimdi duran başka ad tohum olmaz.
            if let dropped = name, droppedMode != nil,
               Self.normalizedName(found) != Self.normalizedName(dropped) { continue }
            name = name ?? found
            seeds.append(NamePlace(mode: target.mode, screen: screen, desktop: desktop,
                                   space: desktopNameSpaces[key]?[String(desktop)]))
        }
        if let name, let mode = droppedMode ?? modes.first,
           !seeds.contains(where: { $0.mode == mode }) {
            seeds.append(NamePlace(mode: mode, screen: screen, desktop: desktop, space: droppedSpace))
        }
        let seedTargets = Set(seeds.map { Target(mode: $0.mode, screen: $0.screen, desktop: $0.desktop) })
        for seed in seeds {
            for twin in counterparts(of: seed, name: name) {
                if let live, let bound = twin.space, bound != seed.space, live.contains(bound) { continue }
                let target = Target(mode: twin.mode, screen: twin.screen, desktop: twin.desktop)
                if targets.contains(target) { continue }
                // Karşılık varsa o kurulumda aynı numaralı yer değil karşılık
                // silinir (numara iki kurulumda farklı olabilir).
                targets.removeAll { $0.mode == target.mode && !seedTargets.contains($0) }
                targets.append(target)
            }
        }
        return (targets, name)
    }

    /// Masaüstü Deskmap dışında silindi: o masaüstünün pinleri (bütün
    /// profiller, verilen modlar) ve adı hayalete taşınır, sonraki
    /// masaüstülerinin pinleri bir yukarı kayar, plan bir azalır. Adlı
    /// masaüstünün öbür kurulumdaki karşılığı (aynı mantıksal masaüstü) da
    /// aynı hayalete katılır ve oradaki numaralar kayar. Aynı adlı hayalet
    /// varsa onunla birleşir. Ad ya da pin yoksa hayalet açılmaz (kaydırma
    /// yine yapılır). Hayalet döner. `name`: ad tablodan zaten düşmüşse
    /// (reconcile) adı verir; `shiftNames: false` adları kaydırmaz.
    /// `live`: şu an canlı masaüstü kimlikleri (biliniyorsa); başka canlı
    /// masaüstüne bağlı karşılık silinmiş sayılmaz (yalnız adı tutuyor).
    @discardableResult
    mutating func ghostDesktop(on screen: String, desktop: Int, modes: [Mode],
                               now: Date = Date(), name droppedName: String? = nil,
                               droppedSpace: UInt64? = nil, droppedMode: Mode? = nil,
                               shiftNames: Bool = true, live: Set<UInt64>? = nil)
        -> GhostDesktop? {
        let resolved = removalTargets(screen: screen, desktop: desktop, modes: modes,
                                      name: droppedName, droppedSpace: droppedSpace,
                                      droppedMode: droppedMode, live: live)
        let targets = resolved.targets
        let name = resolved.name
        var pins: [GhostDesktop.Pin] = []
        mapAllRules { list, profileID in
            var result: [Rule] = []
            for var rule in list {
                for target in targets {
                    guard var destination = rule[target.mode], destination.screen == target.screen
                    else { continue }
                    if destination.desktop == target.desktop {
                        pins.append(.init(profileID: profileID, mode: target.mode, rule: rule,
                                          destination: destination))
                        rule[target.mode] = nil
                    } else if destination.desktop > target.desktop {
                        destination.desktop -= 1
                        rule[target.mode] = destination
                    }
                }
                if rule.docked != nil || rule.undocked != nil { result.append(rule) }
            }
            list = result
        }
        for target in targets {
            let planned = plannedDesktops(mode: target.mode, screen: target.screen)
            if planned >= target.desktop {
                setPlannedDesktops(planned - 1, mode: target.mode, screen: target.screen)
            }
        }
        if shiftNames {
            // Ad tablodan zaten düştüyse (reconcile) o yerin adları yeniden kaymaz.
            let nameTargets = targets.filter {
                !(droppedName != nil && $0.mode == droppedMode && $0.screen == screen
                  && $0.desktop == desktop)
            }
            remapNames { mode, screenID, number in
                guard let target = nameTargets.first(where: { $0.mode == mode && $0.screen == screenID }),
                      number >= target.desktop else { return nil }
                return (screenID, number == target.desktop ? 0 : number - 1)
            }
        }
        guard name != nil || !pins.isEmpty else { return nil }
        if let name, let i = ghostDesktops.firstIndex(where: {
            $0.name.map(Self.normalizedName) == Self.normalizedName(name)
        }) {
            ghostDesktops[i].pins = Self.mergedPins(ghostDesktops[i].pins, pins)
            return ghostDesktops[i]
        }
        let ghost = GhostDesktop(screen: screen, name: name, desktop: desktop,
                                 deletedAt: now, pins: pins)
        ghostDesktops.append(ghost)
        return ghost
    }

    /// Hayaleti `desktop` numaralı (yeni açılmış) masaüstüne geri getirir:
    /// ad ve pinler döner. Adlı hayaletin bütün pinleri (öbür kurulumunkiler
    /// o kurulumdaki aynı adlı yere) döner; adsız hayaletin yalnız `mode`
    /// pinleri döner, ötekiler hayalette kalır (başka kurulumun numarası
    /// bilinmez). Ad bu kurulumda başka bir masaüstündeyse yeniden adlandırma
    /// yapılmaz, pinler o masaüstüne gider. Profili artık olmayan pin atlanır;
    /// kuralı silinmişse kopyası eklenir; var olan hedefin üzerine yazılmaz.
    mutating func restoreGhost(_ id: String, desktop: Int, space: UInt64? = nil, mode: Mode = .docked) {
        guard let index = ghostDesktops.firstIndex(where: { $0.id == id }) else { return }
        var ghost = ghostDesktops.remove(at: index)
        var screen = ghost.screen
        var desktop = desktop
        if let name = ghost.name {
            if let live = place(mode: mode, ofName: name) {
                screen = live.screen
                desktop = live.desktop
            } else {
                setDesktopName(name, screen: ghost.screen, desktop: desktop, mode: mode, space: space)
            }
        }
        let own = ghost.pins.filter { $0.mode == mode }
        let others = ghost.pins.filter { $0.mode != mode }
        let restoredRules = Set(own.map(\.rule.id))
        applyGhostPins(own) { pin in
            var destination = pin.destination
            destination.screen = screen
            destination.desktop = desktop
            return destination
        }
        if let name = ghost.name {
            let live = livePlaces(ofName: name)
            applyGhostPins(others) { pin in
                if let found = live[pin.mode] {
                    var destination = pin.destination
                    destination.screen = found.screen
                    destination.desktop = found.desktop
                    return destination
                }
                // Yeri henüz yok: aynı kuralın bu moddaki pini yeniden
                // yansıtılır (adopt), yoksa kayıtlı yerinde bekler.
                return restoredRules.contains(pin.rule.id) ? nil : pin.destination
            }
        } else if !others.isEmpty {
            ghost.pins = others
            ghostDesktops.insert(ghost, at: min(index, ghostDesktops.count))
        }
    }

    mutating func discardGhost(_ id: String) {
        ghostDesktops.removeAll { $0.id == id }
    }

    static func planKey(mode: Mode, screen: String) -> String { "\(mode.rawValue)|\(screen)" }

    /// Bu mod ve ekran için planlanmış masaüstü sayısı; plan yoksa 0.
    func plannedDesktops(mode: Mode, screen: String) -> Int {
        plannedDesktops[Self.planKey(mode: mode, screen: screen)] ?? 0
    }

    func pendingRemovals(mode: Mode, screen: String) -> [PendingRemoval] {
        pendingRemovals[Self.planKey(mode: mode, screen: screen)] ?? []
    }

    /// Etkin olmayan modda masaüstü siler: pinler hemen kayar; `existing`
    /// (masaüstü gerçekte var) ise gerçek silme mod etkinleşince yapılsın
    /// diye sıraya yazılır, yoksa (plan/pin satırı) yalnız numaralar kayar.
    mutating func removeDesktopLater(on screen: String, desktop: Int, mode: Mode,
                                     existing: Bool, space: UInt64?) {
        // Gerçek silme sonra yapılacaksa öbür kurulumdaki karşılığa şimdi
        // dokunulmaz (mod etkinleşince silme yürürken kayar, iki kez değil).
        removeDesktop(on: screen, desktop: desktop, modes: [mode], expandCounterparts: existing == false)
        guard existing else { return }
        pendingRemovals[Self.planKey(mode: mode, screen: screen), default: []]
            .append(PendingRemoval(desktop: desktop, space: space))
    }

    /// Etkin olmayan kurulumun planından silinecek gerçek masaüstü (`space`)
    /// başka bir yerde başka bir ada bağlıysa o ad (yoksa nil). Laptop
    /// masaüstleri iki kurulumda aynı fiziksel masaüstü: bu kurulumda boş
    /// görünen satır öbür kurulumun (ya da bu kurulumun monitördeki) adlı
    /// masaüstü olabilir; sıraya alınan silme kurulum değişince onu yok
    /// ederdi (11.10). Satırın kendi adı (aynı mantıksal masaüstü) engel değil.
    func pendingRemovalConflict(on screen: String, desktop: Int, mode: Mode,
                                space: UInt64) -> String? {
        let own = desktopName(screen: screen, desktop: desktop, mode: mode).map(Self.normalizedName)
        let ownKey = Self.planKey(mode: mode, screen: screen)
        for (key, list) in desktopNameSpaces.sorted(by: { $0.key < $1.key }) {
            for (slot, bound) in list.sorted(by: { $0.key < $1.key }) where bound == space {
                if key == ownKey && slot == String(desktop) { continue }
                guard let name = desktopNames[key]?[slot] else { continue }
                if Self.normalizedName(name) == own { continue }
                return name
            }
        }
        return nil
    }

    mutating func clearPendingRemovals(mode: Mode, screen: String) {
        pendingRemovals[Self.planKey(mode: mode, screen: screen)] = nil
    }

    /// Kuyruktaki ilk silme yapıldı ya da geçersiz: kuyruktan düşer.
    mutating func dropFirstPendingRemoval(mode: Mode, screen: String) {
        let key = Self.planKey(mode: mode, screen: screen)
        guard var list = pendingRemovals[key], !list.isEmpty else { return }
        list.removeFirst()
        pendingRemovals[key] = list.isEmpty ? nil : list
    }

    /// Planı `count`'a ayarlar; 0 ya da altı planı siler.
    mutating func setPlannedDesktops(_ count: Int, mode: Mode, screen: String) {
        let key = Self.planKey(mode: mode, screen: screen)
        plannedDesktops[key] = count > 0 ? count : nil
    }

    /// Verilen adı, listedekilerle çakışmayacak biçimde ("Ad (2)") döndürür.
    static func uniqueName(_ name: String, in profiles: [Profile]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(profiles.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) (\(n))".lowercased()) { n += 1 }
        return "\(base) (\(n))"
    }

    /// Profili ada göre (tam eşleşme) ekler ya da kurallarını değiştirir;
    /// mevcut profilin kimliği korunur, diğer profillere dokunulmaz. Hedef
    /// aktif profilse canlı `rules` da güncellenir. `activate`: ona geçer.
    @discardableResult
    mutating func upsertProfile(_ incoming: Profile, activate: Bool) -> Profile {
        let target: Profile
        if let i = profiles.firstIndex(where: { $0.name == incoming.name }) {
            profiles[i].rules = incoming.rules
            if profiles[i].id == activeProfileID { rules = incoming.rules }
            target = profiles[i]
        } else {
            var created = incoming
            if profiles.contains(where: { $0.id == created.id }) {
                created.id = UUID().uuidString
            }
            syncActiveProfile()
            profiles.append(created)
            target = created
        }
        if activate { switchProfile(to: target.id) }
        return target
    }

    /// `keeping`'den büyük masaüstülerinden (`total`'a dek) kural ya da
    /// oturum pini bakan ilk (en büyük) numarayı döndürür; yoksa nil. Bütün
    /// profillerin bu moddaki pinlerine bakar.
    func desktopBlockingRemoval(on screen: String, mode: Mode, keeping: Int, total: Int,
                                sessionPins: [Destination] = []) -> Int? {
        var used = Set<Int>()
        for list in [rules] + profiles.map(\.rules) {
            for rule in list {
                if let d = rule[mode], d.screen == screen { used.insert(d.desktop) }
            }
        }
        for d in sessionPins where d.screen == screen { used.insert(d.desktop) }
        return used.filter { $0 > keeping && $0 <= max(total, used.max() ?? 0) }.max()
    }

    /// Aktif profilin kayıtlı kurallarını üst düzey `rules` ile eşitler.
    mutating func syncActiveProfile() {
        guard let i = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            let profile = Profile(
                name: Self.uniqueName(Self.defaultProfileName, in: profiles), rules: rules)
            profiles.append(profile)
            activeProfileID = profile.id
            return
        }
        if profiles[i].rules != rules { profiles[i].rules = rules }
    }

    // MARK: - Kurallar

    func rule(_ id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    mutating func update(_ rule: Rule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
    }

    /// Bir kuralın verilen moddaki hedefini değiştirir (nil = atanmamış).
    mutating func setDestination(_ destination: Destination?, for id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        let old = rule[mode]
        rule[mode] = destination
        // Adlı masaüstü öbür kurulumda da aynı: pin karşılığına da yazılır.
        update(mirroredPins(rule, mode: mode, old: old, new: destination))
    }

    /// Kuralın bu moddaki hedefinin yalnızca düzenini değiştirir; ekran ve
    /// masaüstü olduğu gibi kalır. Kural ya da bu modda hedef yoksa dokunmaz.
    /// Belge gerçekten değiştiyse true döner.
    @discardableResult
    mutating func setLayout(_ layout: WindowLayout, for id: String, mode: Mode) -> Bool {
        guard var rule = rule(id), var destination = rule[mode],
              destination.layout != layout else { return false }
        destination.layout = layout
        rule[mode] = destination
        update(rule)
        return true
    }

    /// Pinler: aynı anahtarlı (uygulama + parçalar) kural varsa onun bu
    /// moddaki hedefi güncellenir, yoksa yeni kural eklenir. Kural kimliği
    /// döner.
    @discardableResult
    mutating func pin(_ draft: Rule, destination: Destination, mode: Mode) -> String {
        if let existing = rules.first(where: { $0.sameKey(as: draft) }) {
            setDestination(destination, for: existing.id, mode: mode)
            return existing.id
        }
        var rule = draft
        rule[mode] = destination
        rule = mirroredPins(rule, mode: mode, old: nil, new: destination)
        rules.append(rule)
        return rule.id
    }

    /// Bu moddaki hedefi kaldırır; kuralın hiçbir hedefi kalmazsa silinir.
    mutating func unpin(_ id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        let old = rule[mode]
        rule[mode] = nil
        rule = mirroredPins(rule, mode: mode, old: old, new: nil)
        if rule.docked == nil && rule.undocked == nil {
            rules.removeAll { $0.id == id }
        } else {
            update(rule)
        }
    }

    /// Bir modun bütün kurulumunu diğer modun üzerine yazar: her kuralın
    /// `target` hedefi `source` hedefinin kopyası olur. Hedef modun eski
    /// kurulumu tamamen silinir; `source`'ta hedefi olmayan kuralın `target`
    /// hedefi kalkar, hiç hedefi kalmayan kural silinir. Belge gerçekten
    /// değiştiyse true döner.
    @discardableResult
    mutating func copyLayout(from source: Mode, to target: Mode) -> Bool {
        guard source != target else { return false }
        var copied = rules
        for i in copied.indices { copied[i][target] = copied[i][source] }
        copied.removeAll { $0.docked == nil && $0.undocked == nil }
        guard copied != rules else { return false }
        rules = copied
        return true
    }

    /// Kuralın parçaları `tokens` olsaydı aynı anahtara (uygulama + parçalar)
    /// sahip olacak başka bir kural; yoksa nil.
    func conflictingRule(ifTokens tokens: [String], for id: String) -> Rule? {
        guard var probe = rule(id) else { return nil }
        probe.tokens = tokens
        return rules.first { $0.id != id && $0.sameKey(as: probe) }
    }

    /// Kuralın başlık parçalarını değiştirir; hedefler ve kimlik korunur.
    /// Başka bir kuralla anahtar çakışırsa dokunmaz ve false döner.
    @discardableResult
    mutating func setTokens(_ tokens: [String], for id: String) -> Bool {
        guard var rule = rule(id), conflictingRule(ifTokens: tokens, for: id) == nil
        else { return false }
        rule.tokens = tokens
        update(rule)
        return true
    }

    /// Bir ekrandaki masaüstünü listede başka sıraya taşır; o ekranın bu
    /// moddaki bütün pinlerinin masaüstü numaraları buna göre kayar.
    /// `count`: listedeki satır sayısı (gerçek + pinlerin kullandığı).
    /// `sharedLaptop`: etkin modda gerçekten taşındı; laptop masaüstleri iki
    /// kurulumda aynı fiziksel masaüstü olduğundan öbür kurulumun adları ve
    /// pinleri de aynı haritayla kayar. Etkin olmayan modda yalnız o modun
    /// planı değişir.
    /// `liveSpaces`: pencereler gerçekten taşındıysa ekranın sıralı space
    /// kimlikleri. macOS gerçek masaüstünü taşımaya izin vermez; içerik
    /// (pencereler) yer değiştirir. Eski `i`. masaüstünün içeriği artık
    /// `mapping[i]`. space'tedir: bütün kurulumlarda bu kimliğe bağlı adlar
    /// aynı permütasyonla yeni kimliğe geçer (öbür kurulumun bağları
    /// çaprazlanmaz), taşınan adlar yeni yerlerinin kimliğine hemen bağlanır.
    mutating func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode,
                              sharedLaptop: Bool = false, liveSpaces: [UInt64]? = nil) {
        guard let mapping = Self.desktopMapping(from: from, to: to, count: count)
        else { return }
        if let liveSpaces { permuteBindings(mapping: mapping, spaces: liveSpaces) }
        let modes = sharedLaptop && screen == "builtin" ? Mode.allCases : [mode]
        // Bağı bu ekranın canlı space listesinde olmayan adlar (öbür kurulumun
        // başka ekrandaki masaüstüne bağlı adı) yeniden bağlanmaz.
        var foreign: [Mode: Set<String>] = [:]
        var foreignBound: [Mode: [String: UInt64]] = [:]
        if let liveSpaces {
            let live = Set(liveSpaces)
            for m in modes {
                let key = Self.planKey(mode: m, screen: screen)
                for (slot, space) in desktopNameSpaces[key] ?? [:] where !live.contains(space) {
                    if let name = desktopNames[key]?[slot] {
                        foreign[m, default: []].insert(name)
                        foreignBound[m, default: [:]][name] = space
                    }
                }
            }
        }

        // Bütün profiller: masaüstünün içeriği yer değiştirdi; öbür
        // profilin pinleri eski numarada kalırsa profil değişince pencereler
        // yanlış masaüstüne giderdi (ekranlar arası taşıma ve silme de öyle).
        func remap(_ list: [Rule]) -> [Rule] {
            var moved = list
            for i in moved.indices {
                for mode in modes {
                    guard var destination = moved[i][mode], destination.screen == screen,
                          let updated = mapping[destination.desktop] else { continue }
                    destination.desktop = updated
                    moved[i][mode] = destination
                }
            }
            return moved
        }
        let moved = remap(rules)
        if moved != rules { rules = moved }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            let other = remap(profiles[i].rules)
            if other != profiles[i].rules { profiles[i].rules = other }
        }
        remapDesktopNames(modes: modes) { name, desktop in
            name == screen ? mapping[desktop].map { (screen, $0) } : nil
        }
        if let liveSpaces {
            bindMovedNames(on: screen, modes: modes, spaces: liveSpaces, skip: foreign)
            // Yabancı adın bağı adla birlikte yeni yerine taşınır (kaybolmaz,
            // sonraki yeniden sıralamada yine yabancı sayılır).
            for (m, bound) in foreignBound {
                let key = Self.planKey(mode: m, screen: screen)
                for (slot, name) in desktopNames[key] ?? [:] {
                    guard let space = bound[name] else { continue }
                    desktopNameSpaces[key, default: [:]][slot] = space
                }
            }
        }
    }

    /// Bağlı space kimliklerini içerik taşımasına göre çevirir (saf
    /// permütasyon; her kurulumda, her ekran anahtarında).
    private mutating func permuteBindings(mapping: [Int: Int], spaces: [UInt64]) {
        var table: [UInt64: UInt64] = [:]
        for (old, new) in mapping where old >= 1 && new >= 1
            && old <= spaces.count && new <= spaces.count {
            table[spaces[old - 1]] = spaces[new - 1]
        }
        guard table.contains(where: { $0.key != $0.value }) else { return }
        var result = desktopNameSpaces
        for (key, list) in desktopNameSpaces {
            result[key] = list.mapValues { table[$0] ?? $0 }
        }
        if result != desktopNameSpaces { desktopNameSpaces = result }
    }

    /// `remapNames` taşınan adların bağını düşürür; içerik taşındığı için
    /// yeni yerin kimliği bilinir, hemen bağlanır.
    private mutating func bindMovedNames(on screen: String, modes: [Mode], spaces: [UInt64],
                                         skip: [Mode: Set<String>] = [:]) {
        for mode in modes {
            let key = Self.planKey(mode: mode, screen: screen)
            guard let names = desktopNames[key] else { continue }
            var bindings = desktopNameSpaces[key] ?? [:]
            for (slot, name) in names {
                guard bindings[slot] == nil, !(skip[mode]?.contains(name) ?? false), let desktop = Int(slot),
                      desktop >= 1, desktop <= spaces.count else { continue }
                bindings[slot] = spaces[desktop - 1]
            }
            if !bindings.isEmpty, bindings != desktopNameSpaces[key] { desktopNameSpaces[key] = bindings }
        }
    }

    /// Bir masaüstünü (pinleriyle) başka ekrana taşır: hedef ekranda `to`
    /// sırasına girer, hedefin `to` ve sonrası bir aşağı kayar; kaynakta
    /// boşluk kapanır (sonrakiler bir yukarı). Bütün profiller, yalnız bu
    /// mod. `toCount`: hedefteki satır sayısı; hedefte bir satır artacağı
    /// için plan en az `toCount + 1` olur (masaüstü boşsa da satır kalsın,
    /// etkin modda eksik masaüstü plan mekanizmasıyla açılır). Kaynakta
    /// gerçek masaüstü silinmez; yalnız plan bir azalır.
    mutating func moveDesktopAcross(from fromScreen: String, desktop from: Int,
                                    to toScreen: String, at to: Int, toCount: Int, mode: Mode) {
        guard fromScreen != toScreen, from >= 1, to >= 1 else { return }
        func remap(_ list: [Rule]) -> [Rule] {
            var moved = list
            for i in moved.indices {
                guard var destination = moved[i][mode],
                      let next = Self.acrossPlacement(
                        screen: destination.screen, desktop: destination.desktop,
                        from: fromScreen, desktop: from, to: toScreen, at: to)
                else { continue }
                destination.screen = next.screen
                destination.desktop = next.desktop
                moved[i][mode] = destination
            }
            return moved
        }
        let moved = remap(rules)
        if moved != rules { rules = moved }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            let other = remap(profiles[i].rules)
            if other != profiles[i].rules { profiles[i].rules = other }
        }
        let planned = plannedDesktops(mode: mode, screen: fromScreen)
        if planned >= from { setPlannedDesktops(planned - 1, mode: mode, screen: fromScreen) }
        let target = plannedDesktops(mode: mode, screen: toScreen)
        let needed = max(toCount, to - 1) + 1
        if target < needed { setPlannedDesktops(needed, mode: mode, screen: toScreen) }
        remapDesktopNames(modes: [mode]) { screen, desktop in
            Self.acrossPlacement(screen: screen, desktop: desktop, from: fromScreen,
                                 desktop: from, to: toScreen, at: to)
        }
    }

    /// Canlı ekranlar arası taşımadan önce hedef ekrana eklenecek gerçek
    /// masaüstü sayısı. `to` gerçek bir masaüstünü itiyorsa son gerçek
    /// masaüstü `real + 1`'e kayar; itmiyorsa taşınan pencereler `to`'ya iner.
    /// Plan (`toCount`) gerçek sayıdan büyük olsa da yer açılır. Saf.
    static func desktopsToAddAcross(real: Int, at to: Int) -> Int {
        guard real > 0 else { return 0 }
        return max(0, (to <= real ? real + 1 : to) - real)
    }

    /// Ekranlar arası masaüstü taşımasında bir yerin yeni hâli; değişmiyorsa
    /// nil. Taşınan masaüstü → (hedef, `to`); hedefte `to` ve sonrası +1;
    /// kaynakta `from` sonrası -1. Tersi aynı işlevin uçları değişmiş hâli. Saf.
    static func acrossPlacement(screen: String, desktop: Int,
                                from fromScreen: String, desktop from: Int,
                                to toScreen: String, at to: Int)
        -> (screen: String, desktop: Int)? {
        guard fromScreen != toScreen else { return nil }
        if screen == fromScreen {
            if desktop == from { return (toScreen, to) }
            if desktop > from { return (fromScreen, desktop - 1) }
        } else if screen == toScreen, desktop >= to {
            return (toScreen, desktop + 1)
        }
        return nil
    }

    /// Bir ekrandaki masaüstü silinince: o ekranın bu moddaki pinleri
    /// `removalMapping`'e göre kayar, plan bir azalır.
    mutating func removeDesktop(on screen: String, desktop: Int, mode: Mode) {
        removeDesktop(on: screen, desktop: desktop, modes: [mode])
    }

    /// Masaüstü silinince verilen modlarda bu ekranın pinleri kayar;
    /// yalnız etkin profil değil bütün profiller (profil değişince pinler
    /// yanlış masaüstüne gitmesin). Planlar da bir azalır. Adlı masaüstü tek
    /// mantıksal masaüstüdür: adı ve pinleri öbür kurulumdaki karşılığıyla
    /// (başka ekranda olsa da) birlikte düşer, orada da sonrakiler kayar.
    /// `shiftNames: false`: adlar kaymaz, karşılıklara da dokunulmaz.
    /// `expandCounterparts: false`: adlı masaüstünün öbür kurulumdaki
    /// karşılığının pinleri ve planı kaydırılmaz.
    /// Adlar yalnız pinleri kayan kurulumlarda kayar: laptop masaüstü iki
    /// kurulumda aynı fiziksel masaüstü olsa da yalnız bu kurulumun planından
    /// silinen (henüz silinmemiş) satır öbür kurulumun adını düşürmez; öbür
    /// kurulumun adları ve pinleri gerçek silme yürüyünce birlikte kayar
    /// (11.10: kurulum dışı plandan silinen laptop satırları canlı kurulumun
    /// 7–9 adlarını düşürmüştü, pinler yerinde kalmıştı).
    mutating func removeDesktop(on screen: String, desktop: Int, modes: [Mode],
                                shiftNames: Bool = true, expandCounterparts: Bool = true) {
        var targets = modes.map { Target(mode: $0, screen: screen, desktop: desktop) }
        if shiftNames && expandCounterparts {
            targets = removalTargets(screen: screen, desktop: desktop, modes: modes, name: nil).targets
        }
        mapAllRules { list, _ in
            for i in list.indices {
                for target in targets {
                    guard var destination = list[i][target.mode], destination.screen == target.screen
                    else { continue }
                    destination.desktop = Self.removalMapping(
                        desktop: destination.desktop, removed: target.desktop)
                    list[i][target.mode] = destination
                }
            }
        }
        for target in targets {
            let planned = plannedDesktops(mode: target.mode, screen: target.screen)
            if planned >= target.desktop {
                setPlannedDesktops(planned - 1, mode: target.mode, screen: target.screen)
            }
        }
        // Silinen masaüstünün adı düşer, sonrakiler bir yukarı kayar; yalnız
        // pinleri kayan yerlerde (ad ile pin aynı adımda kayar).
        guard shiftNames else { return }
        let nameTargets = targets
        remapNames { mode, name, number in
            guard let target = nameTargets.first(where: { $0.mode == mode && $0.screen == name }),
                  number >= target.desktop else { return nil }
            return (name, number == target.desktop ? 0 : number - 1)
        }
    }

    /// Masaüstü `removed` silinince eski numara → yeni numara: öncekiler
    /// aynı, sonrakiler bir yukarı; silinenin pinleri bir öncekine (ilkse
    /// yeni ilk masaüstüne) geçer. Saf.
    static func removalMapping(desktop: Int, removed: Int) -> Int {
        if desktop < removed { return desktop }
        if desktop == removed { return max(removed - 1, 1) }
        return desktop - 1
    }

    /// Masaüstü `from` listede `to` sırasına taşınınca eski numara → yeni
    /// numara haritası (kurallar ve oturum pinleri aynı haritayı kullanır).
    /// Geçersiz taşımada nil.
    static func desktopMapping(from: Int, to: Int, count: Int) -> [Int: Int]? {
        guard from != to, from >= 1, to >= 1 else { return nil }
        let total = max(count, from, to)
        var order = Array(1...total)
        order.remove(at: from - 1)
        order.insert(from, at: min(to, total) - 1)
        // order[newIndex] = eski numara → eski → yeni haritası
        var mapping: [Int: Int] = [:]
        for (index, old) in order.enumerated() { mapping[old] = index + 1 }
        return mapping
    }

    // MARK: - Profiller

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Başka bir profile geçer: mevcut kurallar aktif profile yazılır,
    /// hedef profilin kuralları yüklenir.
    mutating func switchProfile(to id: String) {
        guard id != activeProfileID,
              let target = profiles.first(where: { $0.id == id }) else { return }
        syncActiveProfile()
        activeProfileID = target.id
        rules = target.rules
    }

    /// Yeni profil ekler; `activate` ise ona geçer. `copyingCurrent`: mevcut
    /// pinlerle başla (kural kimlikleri yenilenir).
    @discardableResult
    mutating func addProfile(named name: String? = nil, copyingCurrent: Bool = false,
                             activate: Bool = true) -> Profile {
        syncActiveProfile()
        let profile = Profile(
            name: Self.uniqueName(name ?? L("Profile %ld", profiles.count + 1), in: profiles),
            rules: copyingCurrent ? Self.regeneratingIDs(rules) : [])
        profiles.append(profile)
        if activate {
            activeProfileID = profile.id
            rules = profile.rules
        }
        return profile
    }

    /// Verilen profilin kopyasını ekler (kural kimlikleri yenilenir); etkin
    /// profil değişmez, pencereler yerinde kalır. Etkin profil kopyalanıyorsa
    /// kurallar canlı `rules`'tan alınır.
    @discardableResult
    mutating func duplicateProfile(_ id: String, named name: String) -> Profile? {
        syncActiveProfile()
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        let profile = Profile(name: Self.uniqueName(name, in: profiles),
                              rules: Self.regeneratingIDs(source.rules))
        profiles.append(profile)
        return profile
    }

    mutating func renameProfile(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = trimmed
    }

    /// Profili siler; son profil silinemez. Aktif siliniyorsa ilk kalana geçilir.
    mutating func deleteProfile(_ id: String) {
        guard profiles.count > 1,
              let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: i)
        if activeProfileID == id, let next = profiles.first {
            activeProfileID = next.id
            rules = next.rules
        }
    }

    // MARK: - Dışa / içe aktarma

    func exportData(for id: String) throws -> Data {
        var doc = self
        doc.syncActiveProfile()
        guard let profile = doc.profiles.first(where: { $0.id == id }) else {
            throw NSError(domain: "Deskmap", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("Profile not found")])
        }
        let payload = ProfileExport(name: profile.name, screens: doc.screens,
                                    rules: profile.rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Dosyadan profil okur, yeni profil olarak ekler ve ona geçer.
    /// Kural kimlikleri çakışmasın diye yenilenir.
    @discardableResult
    mutating func importProfile(from data: Data) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ProfileExport.self, from: data)
        guard payload.kind == ProfileExport.kind || payload.kind == ProfileExport.legacyKind
                || !payload.rules.isEmpty else {
            throw NSError(domain: "Deskmap", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: L("This is not a Deskmap profile")])
        }
        syncActiveProfile()
        let profile = Profile(name: Self.uniqueName(payload.name, in: profiles),
                              rules: Self.regeneratingIDs(payload.rules))
        profiles.append(profile)
        activeProfileID = profile.id
        rules = profile.rules
        // Dosyadaki ekran adları bilinmeyen rolleri tanıtır (harita için).
        for screen in payload.screens where !screens.contains(where: { $0.id == screen.id }) {
            screens.append(screen)
        }
        return profile
    }

    private static func regeneratingIDs(_ rules: [Rule]) -> [Rule] {
        rules.map { var r = $0; r.id = UUID().uuidString; return r }
    }
}

/// Dışa/içe aktarma dosyası (`Ad.deskmap.json`). Eski `Ad.spacerouter.json`
/// dosyaları (`kind` alanı `legacyKind`) da içe aktarılabilir; yalnızca
/// dışa aktarma yeni adı ve uzantıyı kullanır.
struct ProfileExport: Codable {
    var kind: String = ProfileExport.kind
    /// 2: düzenlerde `fixed` olabilir (eski sürüm oranlı karşılığı okur).
    var version: Int = 2
    var name: String
    var exportedAt: Date = Date()
    /// Kuralların hangi ekran rollerine yazıldığını anlamak için.
    var screens: [KnownScreen] = []
    var rules: [Rule]
    /// Okunurken atlanan bozuk kural sayısı (yazılmaz).
    var droppedRuleCount = 0

    static let kind = "deskmap-profile"
    /// Deskmap'in eski adı; içe aktarmada hâlâ kabul edilir.
    static let legacyKind = "spacerouter-profile"
    static let fileExtension = "deskmap.json"

    /// Yalnızca kurallar listesi içeren düz bir `rules.json` de kabul edilir.
    private enum CodingKeys: String, CodingKey {
        case kind, version, name, exportedAt, screens, rules
    }

    init(name: String, screens: [KnownScreen], rules: [Rule]) {
        self.name = name
        self.screens = screens
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? Self.kind
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L("Imported")
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        screens = try c.decodeIfPresent([KnownScreen].self, forKey: .screens) ?? []
        let lossyRules = try c.decodeIfPresent(LossyArray<Rule>.self, forKey: .rules)
        rules = lossyRules?.elements ?? []
        droppedRuleCount = lossyRules?.droppedCount ?? 0
    }
}

/// Yapılandırmanın tek sahibi. Değişiklikler yarım saniye sonra diske yazılır.
/// Kural/profil mantığı `Document` üzerindedir; burası yalnızca çağırır,
/// yayınlar ve kaydeder.
@MainActor
final class Store: ObservableObject {

    @Published var document = Document() {
        didSet {
            // Kayıttan sonra belge başka yoldan değiştiyse (yeni pin, düzen
            // adımı, profil geçişi, URL komutu) geri alma o değişikliği de
            // silerdi; kayıt düşer. Kaydı bırakan işlemin kendi değişimi
            // `recording` içinde kayıttan önce gerçekleşir, ona dokunmaz.
            undoBuffer.invalidate(ifChangedFrom: document)
            if oldValue.enabled != document.enabled { enabledChanges += 1 }
        }
    }
    /// Açık/duraklat anahtarı kaç kez değişti (kaydedilmez); "15 dakika
    /// duraklat" süresi dolunca yalnız arada başka yoldan (anahtar, Ayarlar,
    /// URL komutu) değişmediyse devam ettirir.
    private(set) var enabledChanges = 0
    @Published private(set) var lastError: String?
    /// Son yıkıcı işlemden önceki belge; alt çubuktaki "Geri al" bunu geri
    /// yükler. Düzen adımları ve profil geçişi kaydedilmez; araya girerlerse
    /// bekleyen kaydı düşürürler.
    @Published private(set) var undoBuffer = UndoBuffer()

    /// Alt çubukta gösterilecek bir hata; bir sonraki başarılı kayıtta silinir.
    func report(_ message: String) { lastError = message }
    func clearError() { lastError = nil }

    static let directoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Deskmap",
                                isDirectory: true)

    /// Eski ad (Space Router) altındaki veri klasörü; `init()` içinde bir
    /// kez buradan `directoryURL`'e kopyalanır (bkz. `DataMigration`).
    static let legacyDirectoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SpaceRouter",
                                isDirectory: true)

    static let fileURL = directoryURL.appendingPathComponent("rules.json")
    /// Okunamayan `rules.json` üzerine yazılmadan önce buraya kopyalanır.
    static let backupURL = directoryURL.appendingPathComponent("rules.json.bak")

    /// Dosya daha yeni bir Deskmap sürümüne aitse yazma kapalıdır:
    /// eski sürüm bilmediği alanları silerek dosyayı bozmasın.
    var isReadOnly: Bool { document.isFromNewerVersion }
    static let newerVersionMessage =
        L("rules.json belongs to a newer version of Deskmap; changes will not be saved")

    private var cancellables = Set<AnyCancellable>()
    // nonisolated(unsafe): yalnızca init'te (ana aktör) atanır, deinit'te
    // kaldırılır; gözlemci belirteci Sendable olmadığı için deinit erişimi
    // başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var terminateObserver: NSObjectProtocol?

    init() {
        // Deskmap'in eski adı Space Router'dı; yeni klasör hiç yoksa ve eski
        // klasör varsa üç dosya bir kez kopyalanır (taşınmaz, silinmez).
        DataMigration.migrate(from: Self.legacyDirectoryURL, to: Self.directoryURL)
        load()
        $document
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.document.syncActiveProfile()
                self?.save()
            }
            .store(in: &cancellables)

        // Kayıt 400 ms gecikmeli; çıkışta bekleyen değişiklik kaybolmasın.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    /// Shots modu (`--shots`): dosyaya hiç dokunmaz. Kayıt zamanlayıcısı
    /// (`$document` sink'i) ve çıkışta yazan `willTerminate` gözlemcisi
    /// kurulmaz; `document` dışarıdan sabit verilir. Üretim `init()`'i
    /// değişmez.
    init(demo document: Document) {
        self.document = document
    }

    /// Bekleyen değişiklikleri hemen diske yazar.
    func flush() {
        document.syncActiveProfile()
        save()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            document = try JSONDecoder().decode(Document.self, from: data)
            if document.isFromNewerVersion {
                lastError = Self.newerVersionMessage
            } else if document.droppedRuleCount > 0 {
                // Atlanan kurallar ilk kayıtta dosyadan düşecek; önce yedeğini al.
                let backedUp = backUpFile()
                let count = document.droppedRuleCount
                lastError = Self.withBackupNote(
                    count == 1 ? L("1 rule could not be read")
                               : L("%ld rules could not be read", count),
                    backedUp: backedUp)
            } else {
                lastError = nil
            }
        } catch {
            // Bozuk dosya ilk değişiklikte ezilecek; önce yedeğini al.
            let backedUp = backUpFile()
            lastError = Self.withBackupNote(
                L("Could not read rules.json: %@", error.localizedDescription),
                backedUp: backedUp)
        }
    }

    /// Yedek alındıysa iletinin sonuna yedek dosyasının adını ekler.
    private static func withBackupNote(_ message: String, backedUp: Bool) -> String {
        backedUp ? L("%@ (backup: rules.json.bak)", message) : message
    }

    /// `rules.json`'ı `rules.json.bak` olarak kopyalar; başarıyı döndürür.
    private func backUpFile() -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.backupURL)
        return (try? fm.copyItem(at: Self.fileURL, to: Self.backupURL)) != nil
    }

    func save() {
        // Yeni sürümün dosyası: dokunma, uyarı alt çubukta kalsın.
        guard !isReadOnly else {
            lastError = Self.newerVersionMessage
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys,
                                        .withoutEscapingSlashes]
            try encoder.encode(document).write(to: Self.fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = L("Could not write rules.json: %@", error.localizedDescription)
        }
    }

    // MARK: - Geri alma

    /// `change` belgeyi gerçekten değiştirdiyse önceki ve sonraki hâli
    /// `label` ile saklar; etkisiz çağrılar (olmayan kural, son profil) kayıt
    /// bırakmaz. `companion`: belge dışındaki durumu (oturum pinleri) geri
    /// alan kapanış; verilmişse belge değişmese de kayıt bırakılır (yalnızca
    /// oturum pinleri kaymış olabilir).
    private func recording(_ label: String, companion: (() -> Void)? = nil,
                           _ change: () -> Void) {
        let before = document
        change()
        if document != before || companion != nil {
            undoBuffer.record(label, before: before, after: document, companion: companion)
        }
    }

    /// Belgeye dokunmayan ama geri alınabilir olması istenen işlem (geçici
    /// pinin sürüklenmesi): yalnızca eşlik kapanışı saklanır. Belge sonradan
    /// değişirse bu kayıt da düşer.
    func recordSessionChange(_ label: String, undo companion: @escaping () -> Void) {
        undoBuffer.record(label, before: document, after: document, companion: companion)
    }

    /// Son yıkıcı işlemi geri alır: saklanan belge tek atamayla geri gelir,
    /// ardından eşlik kapanışı (oturum pinleri) çalışır. Açık/kapalı
    /// anahtarı ve o arada tanınan ekranlar işlemle ilgisiz olduğu için şu
    /// anki değerleriyle korunur.
    func undo() {
        guard let entry = undoBuffer.take() else { return }
        var restored = entry.before
        restored.enabled = document.enabled
        restored.screens = document.screens
        if restored != document { document = restored }
        entry.companion?()
    }

    // MARK: - Kurallar

    func add(_ rule: Rule) {
        document.rules.append(rule)
    }

    func update(_ rule: Rule) {
        document.update(rule)
    }

    func remove(_ id: String) {
        recording(L("Pin deleted")) {
            document.rules.removeAll { $0.id == id }
        }
    }

    func rule(_ id: String) -> Rule? {
        document.rule(id)
    }

    /// Bir kuralın verilen moddaki hedefini değiştirir (nil = atanmamış).
    /// Düzen adımları buradan geçer; geri alma kaydı bırakmaz.
    func setDestination(_ destination: Destination?, for id: String, mode: Mode) {
        document.setDestination(destination, for: id, mode: mode)
    }

    /// Sürükleyip bırakma ile hedef değişimi: `setDestination` gibi, ama
    /// geri alınabilir (yanlış masaüstüne bırakılan pin tek tıkla döner).
    func moveRule(_ id: String, to destination: Destination, mode: Mode) {
        recording(L("Pin moved")) {
            document.setDestination(destination, for: id, mode: mode)
        }
    }

    /// "Şu anki boyutu kullan": pencerenin gerçek çerçevesinden okunan
    /// düzeni kuralın bu moddaki hedefine yazar. Ekran ve masaüstü değişmez;
    /// pencere başka masaüstüne taşınmaz. Eski düzen ezildiği için geri
    /// alınabilir. Değişiklik olduysa true döner.
    @discardableResult
    func saveLayout(_ layout: WindowLayout, for id: String, mode: Mode) -> Bool {
        var changed = false
        recording(L("Layout saved")) {
            changed = document.setLayout(layout, for: id, mode: mode)
        }
        return changed
    }

    /// Pinler: aynı anahtarlı (uygulama + parçalar) kural varsa onun bu
    /// moddaki hedefi güncellenir (mevcut hedef eziliyorsa geri alınabilir),
    /// yoksa yeni kural eklenir. Kural kimliği döner.
    @discardableResult
    func pin(_ draft: Rule, destination: Destination, mode: Mode) -> String {
        // Yeni kural ya da bu modda henüz hedefi olmayan kural: ezilen bir
        // şey yok, kayıt gerekmez (bekleyen kaydı belge değişimi düşürür).
        guard let existing = document.rules.first(where: { $0.sameKey(as: draft) }),
              existing[mode] != nil else {
            return document.pin(draft, destination: destination, mode: mode)
        }
        var id = existing.id
        recording(L("Pin updated")) {
            id = document.pin(draft, destination: destination, mode: mode)
        }
        return id
    }

    /// Toplu pinleme: hepsi tek adımda yazılır, ⌘Z hepsini geri alır.
    func pinMany(_ items: [(rule: Rule, destination: Destination)], mode: Mode,
                 companion: (() -> Void)? = nil) {
        guard !items.isEmpty else { return }
        recording(L("Windows pinned"), companion: companion) {
            for item in items {
                document.pin(item.rule, destination: item.destination, mode: mode)
            }
        }
    }

    /// Uygulama grubunun taşınması: kuralların hedefleri `moveRule` ile
    /// aynı biçimde yazılır (ad bağları dahil); oturum pinleri çağıran
    /// tarafından taşınır, `undoingSessionPins` onları geri getirir. Tek
    /// geri alma adımı.
    func moveGroup(_ moves: [GroupMovePlan.RuleMove], mode: Mode,
                   undoingSessionPins: (() -> Void)? = nil) {
        guard !moves.isEmpty || undoingSessionPins != nil else { return }
        recording(L("Group moved"), companion: undoingSessionPins) {
            for move in moves {
                document.setDestination(move.destination, for: move.id, mode: mode)
            }
        }
    }

    /// Kuralın başlık parçalarını değiştirir (geri alınabilir). Başka bir
    /// kuralla anahtar çakışırsa dokunmaz ve false döner.
    @discardableResult
    func setTokens(_ tokens: [String], for id: String) -> Bool {
        var changed = false
        recording(L("Title parts changed")) {
            changed = document.setTokens(tokens, for: id)
        }
        return changed
    }

    /// Bu moddaki hedefi kaldırır; kuralın hiçbir hedefi kalmazsa silinir.
    func unpin(_ id: String, mode: Mode) {
        recording(L("Pin removed")) {
            document.unpin(id, mode: mode)
        }
    }

    /// "Laptop düzenini buraya kopyala": `source` modunun kurulumu `target`
    /// modunun üzerine yazılır, eskisi silinir (geri alınabilir).
    @discardableResult
    func copyLayout(from source: Mode, to target: Mode) -> Bool {
        var changed = false
        recording(L("Layout copied")) {
            changed = document.copyLayout(from: source, to: target)
        }
        return changed
    }

    /// Bir ekrandaki masaüstünü listede başka sıraya taşır; o ekranın bu
    /// moddaki bütün pinlerinin masaüstü numaraları buna göre kayar.
    /// `undoingSessionPins`: oturum pinleri de kaydıysa onları geri taşıyan
    /// kapanış (Router'ın ters taşıması); geri almada belgeyle birlikte çalışır.
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode,
                     sharedLaptop: Bool = false, liveSpaces: [UInt64]? = nil,
                     undoingSessionPins companion: (() -> Void)? = nil) {
        recording(L("Desktop order changed"), companion: companion) {
            document.moveDesktop(on: screen, from: from, to: to, count: count, mode: mode,
                                 sharedLaptop: sharedLaptop, liveSpaces: liveSpaces)
        }
    }

    /// Masaüstünü başka ekrana taşır (bkz. `Document.moveDesktopAcross`);
    /// pinler ve planlar tek adımda ⌘Z ile geri gelir.
    func moveDesktopAcross(from fromScreen: String, desktop from: Int,
                           to toScreen: String, at to: Int, toCount: Int, mode: Mode,
                           undoingSessionPins companion: (() -> Void)? = nil) {
        recording(L("Desktop moved to another display"), companion: companion) {
            document.moveDesktopAcross(from: fromScreen, desktop: from, to: toScreen, at: to,
                                       toCount: toCount, mode: mode)
        }
    }

    /// Etkin olmayan modda masaüstü siler (bkz. `Document.removeDesktopLater`);
    /// yalnız belge değişir, ⌘Z geri alır (`undoing`: belgeyle birlikte
    /// geri alınan arayüz durumu, ör. daraltılmış grupların numaraları).
    /// Silinecek gerçek masaüstü başka bir yerde başka bir ada bağlıysa
    /// (`Document.pendingRemovalConflict`) reddedilir, bildirilir: false.
    @discardableResult
    func removeDesktopLater(on screen: String, desktop: Int, mode: Mode,
                            existing: Bool, space: UInt64?,
                            undoing companion: (() -> Void)? = nil) -> Bool {
        guard !refusesPendingRemoval(on: screen, desktop: desktop, mode: mode,
                                     existing: existing, space: space) else { return false }
        Log.app.notice("Desktop \(desktop) on \(screen, privacy: .public) removed from the \(mode.rawValue, privacy: .public) setup (existing: \(existing), space: \(space.map(String.init) ?? "none", privacy: .public))")
        recording(L("Desktop removed"), companion: companion) {
            document.removeDesktopLater(on: screen, desktop: desktop, mode: mode,
                                        existing: existing, space: space)
        }
        return true
    }

    /// Etkin olmayan kurulumdan silme reddedilecek mi (`removeDesktopLater`):
    /// reddedilirse bildirir. Arayüz numaraları kaydırmadan önce sorar.
    func refusesPendingRemoval(on screen: String, desktop: Int, mode: Mode,
                               existing: Bool, space: UInt64?) -> Bool {
        guard existing, let space,
              let name = document.pendingRemovalConflict(on: screen, desktop: desktop,
                                                         mode: mode, space: space)
        else { return false }
        Log.app.notice("Removal of desktop \(desktop) on \(screen, privacy: .public) in the \(mode.rawValue, privacy: .public) setup refused: it is a named desktop elsewhere")
        report(L("Desktop %ld is the desktop named “%@” elsewhere; remove it where it has that name",
                 desktop, name))
        return true
    }

    /// Bekleyen ilk silme yapıldı ya da geçersiz (geri alma kaydı yok).
    func dropFirstPendingRemoval(mode: Mode, screen: String) {
        document.dropFirstPendingRemoval(mode: mode, screen: screen)
    }

    /// Plan karşılandı (geri alma kaydı yok).
    func clearPlannedDesktops(mode: Mode, screen: String) {
        document.setPlannedDesktops(0, mode: mode, screen: screen)
    }

    /// Gerçek masaüstü silindikten sonra pinleri yeniden numaralar. Geri
    /// alma kaydı yok: ⌘Z masaüstünü geri getiremez, yalnız numaraları
    /// bozardı.
    func removeDesktop(on screen: String, desktop: Int, modes: [Mode], shiftNames: Bool = true,
                       expandCounterparts: Bool = true) {
        document.removeDesktop(on: screen, desktop: desktop, modes: modes, shiftNames: shiftNames,
                               expandCounterparts: expandCounterparts)
    }

    func desktopName(screen: String, desktop: Int, mode: Mode) -> String? {
        document.desktopName(screen: screen, desktop: desktop, mode: mode)
    }

    /// Masaüstüne ad verir; boş ad siler (geri alınabilir). Ad, o anki
    /// gerçek masaüstüne (space kimliği) bağlanır.
    /// Ad aynı kurulumda başka masaüstünde varsa reddedilir (false).
    @discardableResult
    func setDesktopName(_ name: String?, screen: String, desktop: Int, mode: Mode,
                        space: UInt64? = nil) -> Bool {
        var accepted = true
        recording(L("Desktop renamed")) {
            accepted = document.setDesktopName(name, screen: screen, desktop: desktop,
                                               mode: mode, space: space)
        }
        return accepted
    }

    func ghosts(on screen: String) -> [GhostDesktop] { document.ghosts(on: screen) }

    func ghosts(on screen: String, mode: Mode) -> [GhostDesktop] {
        document.ghosts(on: screen, mode: mode)
    }

    /// Deskmap dışında silinen masaüstü (geri alma kaydı yok: macOS'ta
    /// olmuş bir değişikliği izler). `name`: ad tablodan zaten düştüyse.
    func ghostDesktop(on screen: String, desktop: Int, modes: [Mode],
                      name: String? = nil, space: UInt64? = nil, droppedMode: Mode? = nil,
                      shiftNames: Bool = true, live: Set<UInt64>? = nil) {
        document.ghostDesktop(on: screen, desktop: desktop, modes: modes, name: name,
                              droppedSpace: space, droppedMode: droppedMode, shiftNames: shiftNames,
                              live: live)
    }

    /// Hayaleti yeni açılan masaüstüne geri getirir (geri alınabilir).
    func restoreGhost(_ id: String, desktop: Int, space: UInt64?, mode: Mode) {
        recording(L("Deleted desktop restored")) {
            document.restoreGhost(id, desktop: desktop, space: space, mode: mode)
        }
    }

    /// Hayaleti pinleriyle birlikte tamamen siler (geri alınabilir).
    func discardGhost(_ id: String) {
        recording(L("Deleted desktop forgotten")) {
            document.discardGhost(id)
        }
    }

    /// Taramadan gelen gerçek masaüstü listesine göre adları yerleştirir
    /// (geri alma kaydı yok; macOS'ta olmuş bir değişikliği izler).
    @discardableResult
    func reconcileDesktopNames(spaces: [String: [UInt64]], seen: Set<UInt64>, mode: Mode,
                               previous: [String: [UInt64]] = [:],
                               live: Set<UInt64>? = nil) -> ReconcileResult {
        var copy = document
        let result = copy.reconcileNames(spaces: spaces, seen: seen, mode: mode, previous: previous,
                                         live: live)
        if result.changed { document = copy }
        return result
    }

    /// Etkin olmayan modda masaüstü ekler: yalnız plana yazılır (⌘Z geri
    /// alır); mod etkinleşince Router gerçek masaüstünü yaratır.
    func planDesktop(on screen: String, mode: Mode, count: Int) {
        recording(L("Desktop added")) {
            document.setPlannedDesktops(count, mode: mode, screen: screen)
        }
    }

    // MARK: - Profiller

    var profiles: [Profile] { document.profiles }

    var activeProfile: Profile? { document.activeProfile }

    /// Başka bir profile geçer; Router kural değişimini görüp pencereleri
    /// yeniden yerleştirir.
    func switchProfile(to id: String) {
        document.switchProfile(to: id)
    }

    /// Profili ada göre ekler/günceller (bkz. `Document.upsertProfile`).
    func upsertProfile(_ profile: Profile, activate: Bool) {
        var doc = document
        doc.upsertProfile(profile, activate: activate)
        document = doc
    }

    /// Yeni profil ekler; `activate` ise ona geçer. `copyingCurrent`: mevcut pinlerle başla.
    @discardableResult
    func addProfile(named name: String? = nil, copyingCurrent: Bool = false,
                    activate: Bool = true) -> Profile {
        document.addProfile(named: name, copyingCurrent: copyingCurrent, activate: activate)
    }

    /// Profilin kopyasını ekler; etkin profil değişmez.
    @discardableResult
    func duplicateProfile(_ id: String, named name: String) -> Profile? {
        document.duplicateProfile(id, named: name)
    }

    func renameProfile(_ id: String, to name: String) {
        document.renameProfile(id, to: name)
    }

    /// Profili siler; son profil silinemez. Aktif siliniyorsa ilk kalana geçilir.
    func deleteProfile(_ id: String) {
        let name = profiles.first { $0.id == id }?.name ?? ""
        recording(L("Profile deleted: %@", name)) {
            document.deleteProfile(id)
        }
    }

    // MARK: - Dışa / içe aktarma

    func exportData(for id: String) throws -> Data {
        try document.exportData(for: id)
    }

    /// Dosyadan profil okur, yeni profil olarak ekler ve ona geçer. Okuma
    /// başarısızsa belge yayınlanmaz.
    @discardableResult
    func importProfile(from data: Data) throws -> Profile {
        var doc = document
        let profile = try doc.importProfile(from: data)
        document = doc
        return profile
    }

    // MARK: - Ekranlar

    /// Bağlı ekranları bilinen ekranlara işler; bağlı olmayanlar silinmez.
    /// Kanca testlerinin sanal ekranı (scripts/hooktest/vdisplay): yalnız
    /// test sürerken bağlıdır; hatırlanmaz, haritada kalıcı yer tutmaz.
    nonisolated static let testDisplayName = "Deskmap Test Display"

    func remember(_ screens: [KnownScreen]) {
        var known = document.screens.filter { $0.name != Self.testDisplayName }
        for screen in screens where screen.name != Self.testDisplayName {
            if let i = known.firstIndex(where: { $0.id == screen.id }) {
                known[i] = screen
            } else {
                known.append(screen)
            }
        }
        known.sort { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }
        if known != document.screens {
            document.screens = known
        }
    }

    /// Ekranın önizleme boyutu (kayıtlı kullanılabilir alan ya da tahmin);
    /// ekran bilinmiyorsa 1710 × 1074 pt (bu Mac'in dahili ekranı).
    func screenSize(of screenID: String) -> CGSize {
        (document.screens.first { $0.id == screenID }
            ?? screens(for: .docked).first { $0.id == screenID })?.visibleSize
            ?? CGSize(width: 1710, height: 1074)
    }

    /// Verilen modda haritada gösterilecek ekranlar.
    func screens(for mode: Mode) -> [KnownScreen] {
        let builtin = document.screens.first { $0.isBuiltin }
            ?? KnownScreen(id: "builtin", name: L("Built-in display"), aspect: 1.55)
        switch mode {
        case .undocked:
            return [builtin]
        case .docked:
            var externals = document.screens.filter { !$0.isBuiltin }
            if externals.isEmpty {
                externals = [KnownScreen(id: "external", name: L("External display"),
                                         aspect: 1.78)]
            }
            return externals + [builtin]
        }
    }
}
