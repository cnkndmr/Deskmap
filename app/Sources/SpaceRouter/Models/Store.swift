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

    /// Okunan dosyanın `version` alanı (yazılmaz). Bu sürümden yeniyse
    /// dosya daha yeni bir Space Router'a ait; üzerine yazılmamalı.
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

    static let defaultProfileName = "Varsayılan"

    private enum CodingKeys: String, CodingKey {
        case version, enabled, screens, rules, profiles, activeProfileID, settings
        case setupNoticeDismissed
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
            name: Self.uniqueName(name ?? "Profil \(profiles.count + 1)", in: profiles),
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
            throw NSError(domain: "SpaceRouter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Profil bulunamadı"])
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
        guard payload.kind == ProfileExport.kind || !payload.rules.isEmpty else {
            throw NSError(domain: "SpaceRouter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Bu bir Space Router profili değil"])
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

/// Dışa/içe aktarma dosyası (`Ad.spacerouter.json`).
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

    static let kind = "spacerouter-profile"
    static let fileExtension = "spacerouter.json"

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
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "İçe aktarılan"
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

    @Published var document = Document()
    @Published private(set) var lastError: String?
    /// Son yıkıcı işlemden önceki belge; alt çubuktaki "Geri al" bunu geri
    /// yükler. Düzen adımları ve profil geçişi kaydedilmez.
    @Published private(set) var undoBuffer = UndoBuffer()

    /// Alt çubukta gösterilecek bir hata; bir sonraki başarılı kayıtta silinir.
    func report(_ message: String) { lastError = message }

    static let directoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SpaceRouter",
                                isDirectory: true)

    static let fileURL = directoryURL.appendingPathComponent("rules.json")
    /// Okunamayan `rules.json` üzerine yazılmadan önce buraya kopyalanır.
    static let backupURL = directoryURL.appendingPathComponent("rules.json.bak")

    /// Dosya daha yeni bir Space Router sürümüne aitse yazma kapalıdır:
    /// eski sürüm bilmediği alanları silerek dosyayı bozmasın.
    var isReadOnly: Bool { document.isFromNewerVersion }
    static let newerVersionMessage =
        "rules.json daha yeni bir Space Router sürümüne ait; değişiklikler kaydedilmeyecek"

    private var cancellables = Set<AnyCancellable>()
    private var terminateObserver: NSObjectProtocol?

    init() {
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
                lastError = "\(document.droppedRuleCount) kural okunamadı"
                    + (backedUp ? " (yedek: rules.json.bak)" : "")
            } else {
                lastError = nil
            }
        } catch {
            // Bozuk dosya ilk değişiklikte ezilecek; önce yedeğini al.
            let backedUp = backUpFile()
            lastError = "rules.json okunamadı: \(error.localizedDescription)"
                + (backedUp ? " (yedek: rules.json.bak)" : "")
        }
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
            lastError = "rules.json yazılamadı: \(error.localizedDescription)"
        }
    }

    // MARK: - Geri alma

    /// `change` belgeyi gerçekten değiştirdiyse önceki hâli `label` ile
    /// saklar; etkisiz çağrılar (olmayan kural, son profil) kayıt bırakmaz.
    private func recording(_ label: String, _ change: () -> Void) {
        let before = document
        change()
        if document != before { undoBuffer.record(label, document: before) }
    }

    /// Son yıkıcı işlemi geri alır: saklanan belge tek atamayla geri gelir.
    /// Açık/kapalı anahtarı ve o arada tanınan ekranlar işlemle ilgisiz
    /// olduğu için şu anki değerleriyle korunur.
    func undo() {
        guard let entry = undoBuffer.take() else { return }
        var restored = entry.document
        restored.enabled = document.enabled
        restored.screens = document.screens
        document = restored
    }

    // MARK: - Kurallar

    func add(_ rule: Rule) {
        document.rules.append(rule)
    }

    func update(_ rule: Rule) {
        document.update(rule)
    }

    func remove(_ id: String) {
        recording("Pin silindi") {
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
        recording("Pin taşındı") {
            document.setDestination(destination, for: id, mode: mode)
        }
    }

    /// Pinler: aynı anahtarlı (uygulama + parçalar) kural varsa onun bu
    /// moddaki hedefi güncellenir, yoksa yeni kural eklenir. Kural kimliği
    /// döner.
    @discardableResult
    func pin(_ draft: Rule, destination: Destination, mode: Mode) -> String {
        document.pin(draft, destination: destination, mode: mode)
    }

    /// Bu moddaki hedefi kaldırır; kuralın hiçbir hedefi kalmazsa silinir.
    func unpin(_ id: String, mode: Mode) {
        recording("Pin kaldırıldı") {
            document.unpin(id, mode: mode)
        }
    }

    /// Bir ekrandaki masaüstünü listede başka sıraya taşır; o ekranın bu
    /// moddaki bütün pinlerinin masaüstü numaraları buna göre kayar.
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode) {
        recording("Masaüstü sırası değişti") {
            document.moveDesktop(on: screen, from: from, to: to, count: count, mode: mode)
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
        recording("Profil silindi: \(name)") {
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
            ?? KnownScreen(id: "builtin", name: "Dahili ekran", aspect: 1.55)
        switch mode {
        case .undocked:
            return [builtin]
        case .docked:
            var externals = document.screens.filter { !$0.isBuiltin }
            if externals.isEmpty {
                externals = [KnownScreen(id: "external", name: "Harici monitör",
                                         aspect: 1.78)]
            }
            return externals + [builtin]
        }
    }
}
