import AppKit
import Combine
import Foundation

/// Bilinen bir ekran: rol kimliği ve kullanıcıya gösterilecek ad.
struct KnownScreen: Codable, Equatable, Identifiable, Hashable {
    var id: String        // builtin, external, external-2 ...
    var name: String
    var aspect: Double    // genişlik / yükseklik

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

    /// Okunan dosyanın `version` alanı (yazılmaz). Bu sürümden yeniyse
    /// dosya daha yeni bir Deskmap'e ait; üzerine yazılmamalı.
    var fileVersion: Int = Document.currentVersion
    /// Okunurken atlanan bozuk kural sayısı (yazılmaz).
    var droppedRuleCount = 0

    /// Bu sürümün yazdığı şema.
    static let currentVersion = 3

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
        case setupNoticeDismissed, plannedDesktops, pendingRemovals
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
        removeDesktop(on: screen, desktop: desktop, mode: mode)
        guard existing else { return }
        pendingRemovals[Self.planKey(mode: mode, screen: screen), default: []]
            .append(PendingRemoval(desktop: desktop, space: space))
    }

    mutating func clearPendingRemovals(mode: Mode, screen: String) {
        pendingRemovals[Self.planKey(mode: mode, screen: screen)] = nil
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
        rule[mode] = destination
        update(rule)
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
        rules.append(rule)
        return rule.id
    }

    /// Bu moddaki hedefi kaldırır; kuralın hiçbir hedefi kalmazsa silinir.
    mutating func unpin(_ id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule[mode] = nil
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
    mutating func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode) {
        guard let mapping = Self.desktopMapping(from: from, to: to, count: count)
        else { return }

        var moved = rules
        for i in moved.indices {
            guard var destination = moved[i][mode], destination.screen == screen,
                  let updated = mapping[destination.desktop] else { continue }
            destination.desktop = updated
            moved[i][mode] = destination
        }
        if moved != rules { rules = moved }
    }

    /// Bir ekrandaki masaüstü silinince: o ekranın bu moddaki pinleri
    /// `removalMapping`'e göre kayar, plan bir azalır.
    mutating func removeDesktop(on screen: String, desktop: Int, mode: Mode) {
        var moved = rules
        for i in moved.indices {
            guard var destination = moved[i][mode], destination.screen == screen
            else { continue }
            destination.desktop = Self.removalMapping(desktop: destination.desktop, removed: desktop)
            moved[i][mode] = destination
        }
        if moved != rules { rules = moved }
        let planned = plannedDesktops(mode: mode, screen: screen)
        if planned >= desktop { setPlannedDesktops(planned - 1, mode: mode, screen: screen) }
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

    /// Yeni profil ekler ve ona geçer. `copyingCurrent`: mevcut pinlerle başla
    /// (kural kimlikleri yenilenir).
    @discardableResult
    mutating func addProfile(named name: String? = nil, copyingCurrent: Bool = false) -> Profile {
        syncActiveProfile()
        let profile = Profile(
            name: Self.uniqueName(name ?? L("Profile %ld", profiles.count + 1), in: profiles),
            rules: copyingCurrent ? Self.regeneratingIDs(rules) : [])
        profiles.append(profile)
        activeProfileID = profile.id
        rules = profile.rules
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
    var version: Int = 1
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
        }
    }
    @Published private(set) var lastError: String?
    /// Son yıkıcı işlemden önceki belge; alt çubuktaki "Geri al" bunu geri
    /// yükler. Düzen adımları ve profil geçişi kaydedilmez; araya girerlerse
    /// bekleyen kaydı düşürürler.
    @Published private(set) var undoBuffer = UndoBuffer()

    /// Alt çubukta gösterilecek bir hata; bir sonraki başarılı kayıtta silinir.
    func report(_ message: String) { lastError = message }

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
                     undoingSessionPins companion: (() -> Void)? = nil) {
        recording(L("Desktop order changed"), companion: companion) {
            document.moveDesktop(on: screen, from: from, to: to, count: count, mode: mode)
        }
    }

    /// Etkin olmayan modda masaüstü siler (bkz. `Document.removeDesktopLater`);
    /// yalnız belge değişir, ⌘Z geri alır.
    func removeDesktopLater(on screen: String, desktop: Int, mode: Mode,
                            existing: Bool, space: UInt64?) {
        recording(L("Desktop removed")) {
            document.removeDesktopLater(on: screen, desktop: desktop, mode: mode,
                                        existing: existing, space: space)
        }
    }

    /// Bekleyen silmeler yapıldı ya da geçersiz: kayıt geri alınamaz.
    func clearPendingRemovals(mode: Mode, screen: String) {
        document.clearPendingRemovals(mode: mode, screen: screen)
    }

    /// Gerçek masaüstü silindikten sonra pinleri yeniden numaralar. Geri
    /// alma kaydı yok: ⌘Z masaüstünü geri getiremez, yalnız numaraları
    /// bozardı.
    func removeDesktop(on screen: String, desktop: Int, mode: Mode) {
        document.removeDesktop(on: screen, desktop: desktop, mode: mode)
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

    /// Yeni profil ekler ve ona geçer. `copyingCurrent`: mevcut pinlerle başla.
    @discardableResult
    func addProfile(named name: String? = nil, copyingCurrent: Bool = false) -> Profile {
        document.addProfile(named: name, copyingCurrent: copyingCurrent)
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
    func remember(_ screens: [KnownScreen]) {
        var known = document.screens
        for screen in screens {
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
