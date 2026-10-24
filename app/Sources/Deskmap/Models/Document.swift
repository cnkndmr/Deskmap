import Foundation

/// Adlandırılmış bir pin kümesi ve o profilin masaüstü durumu. Aktif
/// profilin kuralları ve masaüstü durumu `Document`'in üst düzey alanlarında
/// (çalışma kopyası) yaşar, `syncActiveProfile` ile buraya geri yazılır.
/// Masaüstü adları, planlar ve hayaletler profile özeldir (şema 6, bkz.
/// docs/desktop-names-v2.md).
struct Profile: Codable, Equatable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var rules: [Rule] = []
    /// Bu profilin masaüstü adları (her biri bir gerçek masaüstüne bağlı).
    var names: [DesktopName] = []
    /// Kurulum ve ekran başına sıralı masaüstü planı.
    var plans = DesktopPlans()
    /// Bu profilin hayalet (silinmiş) masaüstüleri.
    var ghostDesktops: [GhostDesktop] = []
    /// Bu profilin pin grupları (üyelik kurallarda, `Rule.groupID`). İsteğe
    /// bağlı ek alan: boşsa yazılmaz, eski sürüm yok sayar.
    var pinGroups: [PinGroup] = []
    /// Şema 5'in ad tabloları (yalnız okunur, geçiş sonrası nil; yazılmaz).
    var legacy: LegacyNames?

    init(id: String = UUID().uuidString, name: String, rules: [Rule] = [],
         names: [DesktopName] = [], plans: DesktopPlans = DesktopPlans(),
         ghostDesktops: [GhostDesktop] = [], legacy: LegacyNames? = nil,
         pinGroups: [PinGroup] = []) {
        self.id = id
        self.name = name
        self.rules = rules
        self.names = names
        self.plans = plans
        self.ghostDesktops = ghostDesktops
        self.legacy = legacy
        self.pinGroups = pinGroups
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rules, names, plans, ghostDesktops, pinGroups
        case desktopNames, desktopNameSpaces, plannedDesktops
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        names = (try? c.decodeIfPresent([DesktopName].self, forKey: .names)) ?? []
        plans = (try? c.decodeIfPresent(DesktopPlans.self, forKey: .plans)) ?? DesktopPlans()
        ghostDesktops = (try? c.decodeIfPresent([GhostDesktop].self, forKey: .ghostDesktops)) ?? []
        pinGroups = PinGroup.deduplicated(
            (try? c.decodeIfPresent(LossyArray<PinGroup>.self, forKey: .pinGroups))?.elements ?? [])
        let old = LegacyNames(
            desktopNames: (try? c.decodeIfPresent([String: [String: String]].self, forKey: .desktopNames)) ?? [:],
            desktopNameSpaces: (try? c.decodeIfPresent([String: [String: UInt64]].self,
                                                       forKey: .desktopNameSpaces)) ?? [:],
            plannedDesktops: (try? c.decodeIfPresent([String: Int].self, forKey: .plannedDesktops)) ?? [:])
        legacy = old.isEmpty ? nil : old
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(rules, forKey: .rules)
        // Boş alanlar yazılmaz; şema 5 tabloları hiç yazılmaz.
        if !names.isEmpty { try c.encode(names, forKey: .names) }
        if !plans.isEmpty { try c.encode(plans, forKey: .plans) }
        if !ghostDesktops.isEmpty { try c.encode(ghostDesktops, forKey: .ghostDesktops) }
        if !pinGroups.isEmpty { try c.encode(pinGroups, forKey: .pinGroups) }
    }
}

/// Etkin olmayan modda silinmiş, gerçek silmesi bekleyen masaüstü (eski
/// kayıtlar; şema 6 yenisini yazmaz, kuyruktakiler yine yürütülür).
/// `desktop`: silindiği andaki sıra; `space`: o an bilinen space kimliği.
struct PendingRemoval: Codable, Equatable, Hashable {
    var desktop: Int
    var space: UInt64?
    /// Silmeyi sıraya koyan profil (eski kayıtlarda nil).
    var profileID: String? = nil
}

/// Gerçekten silinmiş, adı ya da pini olan masaüstü. Haritada ekranın
/// sonunda hayalet satır olarak durur; pinler burada saklanır ki sonraki
/// masaüstüne kaymasınlar. Geri getirilince yeni masaüstü açılır, ad ve
/// pinler ona döner. Şema 6'da yalnız gerçek silme hayalet açar.
struct GhostDesktop: Codable, Equatable, Hashable, Identifiable {
    /// Saklanan pin: hangi profilin hangi kuralının hangi moddaki hedefi.
    /// `rule`: kural pinle birlikte tamamen kalktıysa geri eklemek için kopya.
    struct Pin: Codable, Equatable, Hashable {
        var profileID: String
        var mode: Mode
        var rule: Rule
        var destination: Destination
        /// Yerin monitörlü sıradaki yeri (0 = ilk); geri gelince aynı sıraya
        /// girer. Eski kayıtlarda yok (nil): yalnız kuralın o modda yeri
        /// yoksa yazılır.
        var order: Int? = nil
    }
    var id: String = UUID().uuidString
    var screen: String
    var name: String?
    /// Silindiği andaki sırası (yalnız bilgi).
    var desktop: Int
    var deletedAt: Date
    var pins: [Pin] = []
    /// Silinen adın kimliği (geri getirmede yeniden kullanılır).
    var nameID: String?
    /// Neden: şema 6 yalnız "deleted" yazar.
    var cause: String?

    static let deletedCause = "deleted"

    init(id: String = UUID().uuidString, screen: String, name: String? = nil, desktop: Int,
         deletedAt: Date, pins: [Pin] = [], nameID: String? = nil, cause: String? = nil) {
        self.id = id
        self.screen = screen
        self.name = name
        self.desktop = desktop
        self.deletedAt = deletedAt
        self.pins = pins
        self.nameID = nameID
        self.cause = cause
    }
}

/// `rules.json` içeriği. Kural ve profil işlemleri saf değer işlemleridir;
/// `Store` bunları çağırıp sonucu yayınlar ve diske yazar.
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
    /// Mission Control'de başka ekrana sürüklenen masaüstü (Tablo E):
    /// geri al (varsayılan), sor ya da bırak. Varsayılan yazılmaz.
    var missionControlMoves: DesktopRevert.Setting = .defaultValue
    /// Eski sürümlerin sıraya aldığı gerçek masaüstü silmeleri (anahtar
    /// `planKey`); bütün profillerde ortak. Şema 6 yenisini eklemez.
    var pendingRemovals: [String: [PendingRemoval]] = [:]
    /// Aktif profilin masaüstü adları (çalışma kopyası).
    var names: [DesktopName] = []
    /// Aktif profilin planları (çalışma kopyası).
    var plans = DesktopPlans()
    /// Aktif profilin hayalet masaüstüleri (çalışma kopyası).
    var ghostDesktops: [GhostDesktop] = []
    /// Aktif profilin pin grupları (çalışma kopyası). Üst düzeyde yazılmaz;
    /// tek kaynak `profiles[i].pinGroups` (adlar ve planlar gibi).
    var pinGroups: [PinGroup] = []
    /// Harici ekran rolleri ve fiziksel monitörler (`DisplayRoles`). Bütün
    /// profillerde ortak: monitörler profile göre değişmez. İsteğe bağlı ek
    /// alan, şema 6 değişmez.
    var displayRoles = DisplayRoles()
    /// Kullanıcının düzen kitaplığı (temel satır, gelişmiş ızgara, gizli).
    /// Bütün profillerde ortak; varsayılansa yazılmaz. İsteğe bağlı ek alan,
    /// şema 6 değişmez. Kurallar düzenin değerini tutar: kitaplıktan silinen
    /// ya da değişen düzen hiçbir pini bozmaz.
    var layouts = LayoutLibrary.defaults

    /// Okunan dosyanın `version` alanı (yazılmaz). Bu sürümden yeniyse
    /// dosya daha yeni bir Deskmap'e ait; üzerine yazılmamalı.
    var fileVersion: Int = Document.currentVersion
    /// Okunurken atlanan bozuk kural sayısı (yazılmaz).
    var droppedRuleCount = 0

    /// Bu sürümün yazdığı şema. 4: düzenlerde `fixed`. 5: adlar profil
    /// başına. 6: ad bir masaüstüne bağlı kayıt, kurulum başına plan, kural
    /// hedefinde `nameID`. Eski sürüm dosyayı salt okunur açar.
    static let currentVersion = 6

    var isFromNewerVersion: Bool { fileVersion > Self.currentVersion }

    /// Dosya şema 6'dan eski: adlar `MigrationV6` ile taşınmalı.
    var needsNameMigration: Bool { fileVersion < 6 && !isFromNewerVersion }

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
        case desktopNameSpaces, ghostDesktops, displayRoles, missionControlMoves, layouts
    }

    private struct LegacySettings: Decodable { var enabled: Bool? }

    /// Profil kaydı: `Profile` ile aynı alanlar, kuralları hoşgörülü okunur
    /// (bozuk kural atlanır).
    private struct ProfileRecord: Decodable {
        var id: String
        var name: String
        var rules: LossyArray<Rule>
        var names: [DesktopName]?
        var plans: DesktopPlans?
        var desktopNames: [String: [String: String]]?
        var desktopNameSpaces: [String: [String: UInt64]]?
        var ghostDesktops: [GhostDesktop]?
        var plannedDesktops: [String: Int]?
        /// Hoşgörülü: bozuk grup kaydı profili (ve belgeyi) düşürmez.
        var pinGroups: LenientPinGroups?
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
        profiles = records.map {
            let old = LegacyNames(desktopNames: $0.desktopNames ?? [:],
                                  desktopNameSpaces: $0.desktopNameSpaces ?? [:],
                                  plannedDesktops: $0.plannedDesktops ?? [:])
            return Profile(id: $0.id, name: $0.name, rules: $0.rules.elements,
                           names: $0.names ?? [], plans: $0.plans ?? DesktopPlans(),
                           ghostDesktops: $0.ghostDesktops ?? [],
                           legacy: old.isEmpty ? nil : old,
                           pinGroups: $0.pinGroups?.groups ?? [])
        }
        droppedRuleCount += records.reduce(0) { $0 + $1.rules.droppedCount }
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID) ?? ""
        setupNoticeDismissed = try c.decodeIfPresent(Bool.self, forKey: .setupNoticeDismissed) ?? false
        missionControlMoves = (try? c.decodeIfPresent(DesktopRevert.Setting.self,
                                                      forKey: .missionControlMoves)) ?? .defaultValue
        displayRoles = (try? c.decodeIfPresent(DisplayRoles.self, forKey: .displayRoles)) ?? DisplayRoles()
        // Bozuk kitaplık belgeyi okunmaz kılmaz; varsayılanlara döner.
        layouts = (try? c.decodeIfPresent(LayoutLibrary.self, forKey: .layouts)) ?? .defaults
        pendingRemovals = (try? c.decodeIfPresent(
            [String: [PendingRemoval]].self, forKey: .pendingRemovals)) ?? [:]
        // Şema 5'ten önceki ortak (üst düzey) durum.
        let sharedPlans = (try? c.decodeIfPresent([String: Int].self, forKey: .plannedDesktops)) ?? [:]
        let sharedNames = Self.migratedNames((try? c.decodeIfPresent(
            [String: [String: String]].self, forKey: .desktopNames)) ?? [:])
        let sharedSpaces = Self.migratedNames((try? c.decodeIfPresent(
            [String: [String: UInt64]].self, forKey: .desktopNameSpaces)) ?? [:])
        let sharedGhosts = (try? c.decodeIfPresent([GhostDesktop].self, forKey: .ghostDesktops)) ?? []
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
        // Şema 4'ten önce yazılmış sabit boyutlarda oran karşılığı yoktu.
        if fileVersion < 4 {
            rules = Self.backfillingFixed(rules, screens: screens)
            profiles = profiles.map {
                var profile = $0
                profile.rules = Self.backfillingFixed($0.rules, screens: screens)
                return profile
            }
        }
        if fileVersion < 5 {
            // Şema 5'ten önce adlar, bağlar, hayaletler ve plan bütün
            // profillerde ortaktı: kullanıma göre profillere dağıtılır.
            profiles = Self.splittingSharedState(
                profiles: profiles, activeID: activeProfileID, activeRules: rules,
                names: sharedNames, spaces: sharedSpaces,
                ghosts: sharedGhosts, plans: sharedPlans)
        }
        // Çalışma kopyası aktif profilin durumu; kurallar üst düzeyden kalır.
        if let active = profiles.first(where: { $0.id == activeProfileID }) {
            let current = rules
            loadProfileState(active)
            rules = current
        }
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
            let modes: [Mode] = key == "builtin" ? Mode.allCases : [.docked]
            for mode in modes {
                result[planKey(mode: mode, screen: key), default: [:]].merge(list) { old, _ in old }
            }
        }
        return result
    }

    /// Eski (şema < 5) ortak durumu profillere kullanıma göre dağıtır (saf):
    /// - ad (ve bağı) yalnız o kurulum, ekran ve N numaralı masaüstünü hedef
    ///   alan kuralı olan profillere;
    /// - hayalet pinlerinde adı geçen ya da kuralları pinlerdeki kurala bakan
    ///   profillere (yalnız o profilin pinleriyle);
    /// - plan o kurulum ve ekranda herhangi bir masaüstünü kullanan
    ///   profillere. Sonuç profillerin `legacy` tablolarıdır (şema 6'ya
    ///   `MigrationV6` taşır).
    static func splittingSharedState(profiles: [Profile], activeID: String, activeRules: [Rule],
                                     names: [String: [String: String]],
                                     spaces: [String: [String: UInt64]],
                                     ghosts: [GhostDesktop],
                                     plans: [String: Int]) -> [Profile] {
        func usesScreen(_ profile: Profile, _ screen: String) -> Bool {
            let rules = profile.id == activeID ? activeRules : profile.rules
            return rules.contains { rule in
                Mode.allCases.contains { rule[$0]?.screen == screen }
            }
        }
        var pinlessOwners: [String: Set<String>] = [:]
        for ghost in ghosts where ghost.pins.isEmpty && ghost.name != nil {
            var owners = Set(profiles.filter { usesScreen($0, ghost.screen) }.map(\.id))
            if owners.isEmpty {
                owners = [profiles.contains { $0.id == activeID } ? activeID : profiles.first?.id ?? ""]
            }
            pinlessOwners[ghost.id] = owners
        }
        return profiles.map { original in
            var profile = original
            var usedSlots = Set<String>()
            var usedKeys = Set<String>()
            let rules = profile.id == activeID ? activeRules : profile.rules
            for rule in rules {
                for mode in Mode.allCases {
                    for destination in rule.places(mode) {
                        let key = planKey(mode: mode, screen: destination.screen)
                        usedKeys.insert(key)
                        usedSlots.insert("\(key)#\(destination.desktop)")
                    }
                }
            }
            var ownNames: [String: [String: String]] = [:]
            var ownSpaces: [String: [String: UInt64]] = [:]
            for (key, list) in names {
                for (slot, name) in list where usedSlots.contains("\(key)#\(slot)") {
                    ownNames[key, default: [:]][slot] = name
                    if let space = spaces[key]?[slot] { ownSpaces[key, default: [:]][slot] = space }
                }
            }
            let ruleIDs = Set(rules.map(\.id))
            var ownGhosts: [GhostDesktop] = []
            for ghost in ghosts {
                if let owners = pinlessOwners[ghost.id] {
                    if owners.contains(profile.id) { ownGhosts.append(ghost) }
                    continue
                }
                let pins = ghost.pins.filter { $0.profileID == profile.id || ruleIDs.contains($0.rule.id) }
                guard !pins.isEmpty else { continue }
                var copy = ghost
                copy.pins = pins.map { var pin = $0; pin.profileID = profile.id; return pin }
                ownGhosts.append(copy)
            }
            let old = LegacyNames(desktopNames: ownNames, desktopNameSpaces: ownSpaces,
                                  plannedDesktops: plans.filter { usedKeys.contains($0.key) })
            profile.legacy = old.isEmpty ? nil : old
            profile.ghostDesktops = ownGhosts
            return profile
        }
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
            rule.mapPlaces(.docked) { fill($1) }
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
        try c.encode(activeProfileID, forKey: .activeProfileID)
        try c.encode(setupNoticeDismissed, forKey: .setupNoticeDismissed)
        if displayRoles != DisplayRoles() { try c.encode(displayRoles, forKey: .displayRoles) }
        if layouts != .defaults { try c.encode(layouts, forKey: .layouts) }
        if missionControlMoves != .defaultValue {
            try c.encode(missionControlMoves, forKey: .missionControlMoves)
        }
        // Adlar, planlar ve hayaletler profil kayıtlarında; yazarken aktif
        // profilin çalışma kopyası kayda işlenir.
        var written = self
        written.syncActiveProfile()
        try c.encode(written.profiles, forKey: .profiles)
        if !pendingRemovals.isEmpty {
            try c.encode(pendingRemovals, forKey: .pendingRemovals)
        }
    }

    // MARK: - Ortak masaüstü kuyruğu

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
            // Önce çalışma kopyası kayda: aktif profilin kaydı eskiyse
            // (senkronize edilmemiş gruplar) kurallardan başka alan kaybolmasın.
            syncActiveProfile()
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

    /// `keeping`'den büyük masaüstülerinden (`total`'a dek) numara kuralı ya
    /// da oturum pini bakan ilk (en büyük) numarayı döndürür; yoksa nil.
    /// Bütün profillerin bu moddaki pinlerine bakar.
    func desktopBlockingRemoval(on screen: String, mode: Mode, keeping: Int, total: Int,
                                sessionPins: [Destination] = []) -> Int? {
        var used = Set<Int>()
        for list in [rules] + profiles.map(\.rules) {
            for rule in list {
                for d in rule.places(mode) where d.screen == screen { used.insert(d.desktop) }
            }
        }
        for d in sessionPins where d.screen == screen { used.insert(d.desktop) }
        return used.filter { $0 > keeping && $0 <= max(total, used.max() ?? 0) }.max()
    }

    /// Aktif profilin kayıtlı kurallarını ve masaüstü durumunu (adlar,
    /// planlar, hayaletler) üst düzey çalışma kopyasıyla eşitler.
    mutating func syncActiveProfile() {
        guard let i = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            let profile = Profile(
                name: Self.uniqueName(Self.defaultProfileName, in: profiles), rules: rules,
                names: names, plans: plans, ghostDesktops: ghostDesktops, pinGroups: pinGroups)
            profiles.append(profile)
            activeProfileID = profile.id
            return
        }
        var profile = profiles[i]
        writeProfileFields(into: &profile)
        if profile != profiles[i] { profiles[i] = profile }
    }

    /// Çalışma kopyasının profil alanlarını (kurallar, adlar, planlar,
    /// hayaletler, pin grupları) `profile`'a yazar (yalnız farklıysa). Aktif
    /// profille çalışma kopyası arasında taşınan her alan buradan geçer; yeni
    /// alan tek yerde eklenir, bir yol onu unutup kaybetmez.
    func writeProfileFields(into profile: inout Profile) {
        if profile.rules != rules { profile.rules = rules }
        if profile.names != names { profile.names = names }
        if profile.plans != plans { profile.plans = plans }
        if profile.ghostDesktops != ghostDesktops { profile.ghostDesktops = ghostDesktops }
        if profile.pinGroups != pinGroups { profile.pinGroups = pinGroups }
    }

    /// `profile`'ın alanlarını çalışma kopyasına yükler (yalnız farklıysa).
    mutating func readProfileFields(from profile: Profile) {
        if rules != profile.rules { rules = profile.rules }
        if names != profile.names { names = profile.names }
        if plans != profile.plans { plans = profile.plans }
        if ghostDesktops != profile.ghostDesktops { ghostDesktops = profile.ghostDesktops }
        if pinGroups != profile.pinGroups { pinGroups = profile.pinGroups }
    }

    /// Profilin kurallarını ve masaüstü durumunu çalışma kopyasına yükler
    /// (`pendingRemovals` ortaktır, dokunulmaz). Grup kaydı budanmaz (K7).
    mutating func loadProfileState(_ profile: Profile) {
        readProfileFields(from: profile)
    }

    /// `body`'yi tek profile daraltılmış belgede çalıştırır: o profilin
    /// kuralları ve masaüstü durumu çalışma kopyasıdır, öbür profiller
    /// görünmez. Sonuç profile (aktifse çalışma kopyasına da) ve ortak
    /// `pendingRemovals`'a geri yazılır. Fiziksel masaüstü değişikliklerini
    /// her profile kendi adlarıyla uygulamak için.
    @discardableResult
    mutating func inProfileScope<R>(_ id: String, _ body: (inout Document) -> R) -> R? {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var profile = profiles[i]
        if id == activeProfileID { writeProfileFields(into: &profile) }
        var scope = self
        scope.profiles = [profile]
        scope.activeProfileID = id
        scope.loadProfileState(profile)
        let untouched = scope
        let result = body(&scope)
        guard scope != untouched else { return result }
        scope.syncActiveProfile()
        if scope.pendingRemovals != pendingRemovals { pendingRemovals = scope.pendingRemovals }
        guard let updated = scope.profiles.first(where: { $0.id == id }) else { return result }
        if updated != profiles[i] { profiles[i] = updated }
        if id == activeProfileID { readProfileFields(from: updated) }
        return result
    }

    // MARK: - Kurallar

    func rule(_ id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    mutating func update(_ rule: Rule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
    }

    /// Bir kuralın verilen moddaki hedefini değiştirir (nil = atanmamış;
    /// monitörlü modda bütün sıralı liste silinir). Monitörlü modda yeni yer
    /// K7'ye göre yazılır (`Rule.place`; `connected`: bağlı ve onay
    /// beklemeyen roller).
    /// Hedef adlı bir masaüstüyse ad hedefi olur (`normalizedTarget`); yeni
    /// bir ada bağlanan kuralın öbür kurulumda hedefi yoksa orada da o ada
    /// bağlanır (N2).
    mutating func setDestination(_ destination: Destination?, for id: String, mode: Mode,
                                 live: LiveDesktops? = nil, connected: Set<String> = []) {
        guard var rule = rule(id) else { return }
        let old = rule[mode]
        let new = destination.map { normalizedTarget($0, mode: mode, live: live) }
        if let new { rule.place(new, mode: mode, connected: connected) } else { rule.setPlaces([], mode: mode) }
        if let nameID = new?.nameID, nameID != old?.nameID { rule = pinnedToNameInOtherSetup(rule, mode: mode) }
        update(rule)
    }

    /// N2: kural `mode`'da bir ada bağlı ve öbür kurulumda hedefi yoksa
    /// orada da aynı ada (planındaki yeri önbellek) bağlanır.
    func pinnedToNameInOtherSetup(_ rule: Rule, mode: Mode) -> Rule {
        let other = Self.otherMode(mode)
        guard let destination = rule[mode], let nameID = destination.nameID, rule[other] == nil,
              let place = plans.place(of: nameID, mode: other) else { return rule }
        var rule = rule
        rule[other] = Destination(screen: place.screen, desktop: place.desktop,
                                  layout: destination.layout, nameID: nameID)
        return rule
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

    /// "Öbür kurulumdakini kullan": `source` kurulumunun düzeni kuralın öbür
    /// kurulumdaki aynı yerine bir kez kopyalanır (`Rule.adoptLayout`).
    /// Belge gerçekten değiştiyse true.
    @discardableResult
    mutating func adoptLayout(for id: String, from source: Mode) -> Bool {
        guard var rule = rule(id), rule.adoptLayout(from: source) else { return false }
        update(rule)
        return true
    }

    /// Pinler: aynı anahtarlı (uygulama + parçalar) kural varsa onun bu
    /// moddaki hedefi güncellenir, yoksa yeni kural eklenir. Kural kimliği
    /// döner.
    @discardableResult
    mutating func pin(_ draft: Rule, destination: Destination, mode: Mode,
                      live: LiveDesktops? = nil, connected: Set<String> = []) -> String {
        if let existing = rules.first(where: { $0.sameKey(as: draft) }) {
            setDestination(destination, for: existing.id, mode: mode, live: live, connected: connected)
            return existing.id
        }
        var rule = draft
        rule.place(normalizedTarget(destination, mode: mode, live: live), mode: mode, connected: connected)
        rule = pinnedToNameInOtherSetup(rule, mode: mode)
        rules.append(rule)
        return rule.id
    }

    /// Bu moddaki hedefi (monitörlü modda bütün sıralı listeyi) kaldırır;
    /// kuralın hiçbir hedefi kalmazsa silinir.
    mutating func unpin(_ id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule.setPlaces([], mode: mode)
        if rule.hasNoPlaces {
            rules.removeAll { $0.id == id }
        } else {
            update(rule)
        }
    }

    /// Sıralı listeden bir yeri siler (yan panel ×); kuralın hiçbir yeri
    /// kalmazsa kural silinir.
    mutating func removePlace(at index: Int, for id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule.removePlace(at: index, mode: mode)
        if rule.hasNoPlaces { rules.removeAll { $0.id == id } } else { update(rule) }
    }

    /// Sıralı listede bir yeri taşır (yan panel ↑ ↓).
    mutating func movePlace(from source: Int, to target: Int, for id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule.movePlace(from: source, to: target, mode: mode)
        update(rule)
    }

    /// Bir modun bütün kurulumunu diğer modun üzerine yazar: her kuralın
    /// `target` hedefi `source` hedefinin kopyası olur (ad hedefi ad hedefi
    /// kalır); laptop planı da kopyalanır (`copyPlan`). Belge gerçekten
    /// değiştiyse true döner.
    @discardableResult
    mutating func copyLayout(from source: Mode, to target: Mode) -> Bool {
        guard source != target else { return false }
        let before = self
        var copied = rules
        // Monitörlü modun bütün sırası yazılır; laptop yalnız ilk yeri alır.
        for i in copied.indices { copied[i].setPlaces(copied[i].places(source), mode: target) }
        copied.removeAll { $0.docked == nil && $0.undocked == nil }
        if copied != rules { rules = copied }
        copyPlan(from: source, to: target)
        refreshNameCaches(live: nil)
        return self != before
    }

    /// Kopyalanacak bir düzen var mı: bu kurulumda kural hedefi ya da plan.
    func hasLayout(in mode: Mode) -> Bool {
        rules.contains { $0[mode] != nil } || !plans[mode].isEmpty
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

    /// Canlı ekranlar arası taşımadan önce hedef ekrana eklenecek gerçek
    /// masaüstü sayısı. `to` gerçek bir masaüstünü itiyorsa son gerçek
    /// masaüstü `real + 1`'e kayar; itmiyorsa taşınan pencereler `to`'ya iner.
    static func desktopsToAddAcross(real: Int, at to: Int) -> Int {
        guard real > 0 else { return 0 }
        return max(0, (to <= real ? real + 1 : to) - real)
    }

    /// Ekranlar arası masaüstü taşımasında bir yerin yeni hâli; değişmiyorsa
    /// nil. Taşınan masaüstü → (hedef, `to`); hedefte `to` ve sonrası +1;
    /// kaynakta `from` sonrası -1. Saf.
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
        var mapping: [Int: Int] = [:]
        for (index, old) in order.enumerated() { mapping[old] = index + 1 }
        return mapping
    }

    // MARK: - Profiller

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Başka bir profile geçer: mevcut kurallar ve masaüstü durumu aktif
    /// profile yazılır, hedef profilinkiler yüklenir. Planın uygulanması
    /// (eksik masaüstü açma, adlı masaüstlerini yerine taşıma; silme yok)
    /// Router'ın işidir (S1).
    mutating func switchProfile(to id: String) {
        guard id != activeProfileID,
              let target = profiles.first(where: { $0.id == id }) else { return }
        syncActiveProfile()
        activeProfileID = target.id
        loadProfileState(target)
    }

    /// Yeni profil ekler; `activate` ise ona geçer. Boş başlar.
    /// `copyingCurrent`: mevcut profilin her şeyinin kopyasıyla başla.
    @discardableResult
    mutating func addProfile(named name: String? = nil, copyingCurrent: Bool = false,
                             activate: Bool = true) -> Profile {
        syncActiveProfile()
        var profile = Profile(
            name: Self.uniqueName(name ?? L("Profile %ld", profiles.count + 1), in: profiles))
        if copyingCurrent, let source = profiles.first(where: { $0.id == activeProfileID }) {
            Self.copyState(of: source, into: &profile)
        }
        profiles.append(profile)
        if activate {
            activeProfileID = profile.id
            loadProfileState(profile)
        }
        return profile
    }

    /// `source`'un kurallarını ve masaüstü durumunu yeni profile kopyalar:
    /// kural kimlikleri yenilenir, hayalet pinleri yeni profile ve yeni
    /// kurallara bakar. Adlar (kimlik ve bağlarıyla) ve planlar aynen gelir.
    /// Pin gruplarının kimlikleri de yenilenir; kopyalanan kurallar (hayalet
    /// pin kopyaları dahil) yeni gruplara bakar, eşlenmeyen grup kimliği düşer.
    static func copyState(of source: Profile, into profile: inout Profile) {
        var idMap: [String: String] = [:]
        var groupMap: [String: String] = [:]
        profile.pinGroups = source.pinGroups.map { group in
            var copy = group
            copy.id = UUID().uuidString
            groupMap[group.id] = copy.id
            return copy
        }
        profile.rules = source.rules.map { rule in
            var copy = rule
            copy.id = UUID().uuidString
            copy.groupID = rule.groupID.flatMap { groupMap[$0] }
            idMap[rule.id] = copy.id
            return copy
        }
        profile.names = source.names
        profile.plans = source.plans
        let newID = profile.id
        profile.ghostDesktops = source.ghostDesktops.map { ghost in
            var copy = ghost
            copy.id = UUID().uuidString
            copy.pins = ghost.pins.map { pin in
                var pin = pin
                pin.profileID = newID
                pin.rule.id = idMap[pin.rule.id] ?? pin.rule.id
                pin.rule.groupID = pin.rule.groupID.flatMap { groupMap[$0] }
                return pin
            }
            return copy
        }
    }

    /// Verilen profilin kopyasını ekler; etkin profil değişmez.
    @discardableResult
    mutating func duplicateProfile(_ id: String, named name: String) -> Profile? {
        syncActiveProfile()
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        var profile = Profile(name: Self.uniqueName(name, in: profiles))
        Self.copyState(of: source, into: &profile)
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
            loadProfileState(next)
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
        // Adlar (kimlik ve ad), planlar ve ad hedefli kurallar dosyaya girer;
        // bağlar (bu Mac'in space kimlikleri) ve hayaletler girmez.
        var payload = ProfileExport(name: profile.name, screens: doc.screens, rules: profile.rules)
        payload.names = profile.names.map { ProfileExport.Name(id: $0.id, name: $0.name) }
        payload.plans = profile.plans
        payload.pinGroups = profile.pinGroups
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Dosyadan profil okur, yeni profil olarak ekler ve ona geçer. Kural ve
    /// ad kimlikleri yenilenir; adlar yerleşmemiş gelir (ilk plan uygulaması
    /// planındaki yere bağlar, R4). Sürüm 3 dosyası (eski ad tabloları)
    /// şema 6'ya çevrilir.
    @discardableResult
    mutating func importProfile(from data: Data) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ProfileExport.self, from: data)
        // Tanınan tür ya da bir uygulamaya bağlı en az bir kural: türü olmayan
        // eski dosyalar kurallarıyla açılır, yabancı JSON reddedilir (Rule
        // çözücüsü hoşgörülü, `{"bogus":1}` boş kural olur).
        let hasAppRule = payload.rules.contains { !$0.appName.isEmpty || !$0.bundleID.isEmpty }
        guard ProfileExport.knownKinds.contains(payload.kind) || hasAppRule else {
            throw NSError(domain: "Deskmap", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: L("This is not a Deskmap profile")])
        }
        syncActiveProfile()
        var rules = payload.rules.map { rule -> Rule in var r = rule; r.id = UUID().uuidString; return r }
        var names: [DesktopName] = []
        var plans = DesktopPlans()
        if !payload.names.isEmpty || !payload.plans.isEmpty {
            var idMap: [String: String] = [:]
            var seen = Set<String>()
            for name in payload.names {
                let trimmed = name.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(Self.normalizedName(trimmed)).inserted else { continue }
                let fresh = UUID().uuidString
                idMap[name.id] = fresh
                names.append(DesktopName(id: fresh, name: trimmed, space: nil))
            }
            for mode in Mode.allCases {
                for (role, list) in payload.plans[mode] {
                    plans.set(list.map { idMap[$0] ?? "" }, mode, role)
                }
            }
            for i in rules.indices {
                for mode in Mode.allCases {
                    rules[i].mapPlaces(mode) { _, destination in
                        guard let id = destination.nameID else { return destination }
                        var destination = destination
                        destination.nameID = idMap[id]
                        return destination
                    }
                }
            }
        } else if !payload.desktopNames.isEmpty || !payload.plannedDesktops.isEmpty {
            let converted = MigrationV6.convertTables(
                LegacyNames(desktopNames: Self.migratedNames(payload.desktopNames),
                            plannedDesktops: payload.plannedDesktops.filter { $0.value > 0 }),
                rules: rules)
            names = converted.names
            plans = converted.plans
            rules = converted.rules
        }
        // Pin grupları yeni kimlik alır; kuralların grup kimliği eşlenir,
        // dosyada grubu olmayan kimlik düşer.
        var groupMap: [String: String] = [:]
        let groups = payload.pinGroups.map { group -> PinGroup in
            let fresh = PinGroup(name: group.name)
            groupMap[group.id] = fresh.id
            return fresh
        }
        for i in rules.indices { rules[i].groupID = rules[i].groupID.flatMap { groupMap[$0] } }
        let profile = Profile(name: Self.uniqueName(payload.name, in: profiles), rules: rules,
                              names: names, plans: plans, pinGroups: groups)
        profiles.append(profile)
        activeProfileID = profile.id
        loadProfileState(profile)
        // Dosyadaki ekran adları bilinmeyen rolleri tanıtır (harita için).
        for screen in payload.screens where !screens.contains(where: { $0.id == screen.id }) {
            screens.append(screen)
        }
        return profile
    }
}

/// Dışa/içe aktarma dosyası (`Ad.deskmap.json`).
struct ProfileExport: Codable {
    /// Dışa aktarılan ad: kimlik ve ad (masaüstü bağı yok).
    struct Name: Codable, Equatable {
        var id: String
        var name: String
    }

    var kind: String = ProfileExport.kind
    /// 2: düzenlerde `fixed`. 3: masaüstü adları ve plan sayısı (eski
    /// tablolar). 4: `names`, `plans`, kurallarda `nameID` (şema 6).
    /// 5: isteğe bağlı `pinGroups`, kurallarda `groupID` (4 okuyucusu yok sayar).
    var version: Int = 5
    var name: String
    var exportedAt: Date = Date()
    /// Kuralların hangi ekran rollerine yazıldığını anlamak için.
    var screens: [KnownScreen] = []
    var rules: [Rule]
    var names: [Name] = []
    var plans = DesktopPlans()
    /// Sürüm 5: profilin pin grupları (boşsa yazılmaz).
    var pinGroups: [PinGroup] = []
    /// Sürüm 3: profilin masaüstü adları (anahtar `Document.planKey`).
    var desktopNames: [String: [String: String]] = [:]
    /// Sürüm 3: profilin masaüstü planı (anahtar `Document.planKey`).
    var plannedDesktops: [String: Int] = [:]
    /// Okunurken atlanan bozuk kural sayısı (yazılmaz).
    var droppedRuleCount = 0

    static let kind = "deskmap-profile"
    /// SpaceRouter dönemi dosyaları `spacerouter-profile` yazar.
    static let knownKinds: Set<String> = [kind, "spacerouter-profile"]
    static let fileExtension = "deskmap.json"

    private enum CodingKeys: String, CodingKey {
        case kind, version, name, exportedAt, screens, rules, names, plans, pinGroups
        case desktopNames, plannedDesktops
    }

    init(name: String, screens: [KnownScreen], rules: [Rule]) {
        self.name = name
        self.screens = screens
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tür yoksa boş kalır; içe aktarma kural arar (yabancı JSON'u ayırır).
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L("Imported")
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        screens = try c.decodeIfPresent([KnownScreen].self, forKey: .screens) ?? []
        let lossyRules = try c.decodeIfPresent(LossyArray<Rule>.self, forKey: .rules)
        rules = lossyRules?.elements ?? []
        droppedRuleCount = lossyRules?.droppedCount ?? 0
        names = (try? c.decodeIfPresent([Name].self, forKey: .names)) ?? []
        plans = (try? c.decodeIfPresent(DesktopPlans.self, forKey: .plans)) ?? DesktopPlans()
        pinGroups = (try? c.decodeIfPresent(LenientPinGroups.self, forKey: .pinGroups))?.groups ?? []
        desktopNames = (try? c.decodeIfPresent([String: [String: String]].self,
                                               forKey: .desktopNames)) ?? [:]
        plannedDesktops = (try? c.decodeIfPresent([String: Int].self, forKey: .plannedDesktops)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(screens, forKey: .screens)
        try c.encode(rules, forKey: .rules)
        if !names.isEmpty { try c.encode(names, forKey: .names) }
        if !plans.isEmpty { try c.encode(plans, forKey: .plans) }
        if !pinGroups.isEmpty { try c.encode(pinGroups, forKey: .pinGroups) }
    }
}
