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

/// `rules.json` içeriği.
struct Document: Codable, Equatable {
    var version: Int = 3
    var enabled: Bool = true
    var screens: [KnownScreen] = []
    /// Aktif profilin kuralları (router bunu okur).
    var rules: [Rule] = []
    var profiles: [Profile] = []
    var activeProfileID: String = ""
    /// Kurulum hatırlatması (Dock "Assign To" vb.) kullanıcı tarafından
    /// kapatıldı mı? Canlı denetlenen ayarlar bozuksa kart yine görünür.
    var setupNoticeDismissed: Bool = false

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = 3
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []

        if let flag = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = flag
        } else if let legacy = try? c.decode(LegacySettings.self, forKey: .settings) {
            enabled = legacy.enabled ?? true
        }

        // v2 ekran kayıtları; v1 kayıtları (uuid/role) atlanır, yeniden keşfedilir.
        screens = (try? c.decode([KnownScreen].self, forKey: .screens)) ?? []

        // v3 profiller; yoksa (v1/v2) mevcut kurallar "Varsayılan" profil olur.
        profiles = (try? c.decode([Profile].self, forKey: .profiles)) ?? []
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
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

/// Yapılandırmanın tek sahibi. Değişiklikler yarım saniye sonra diske yazılır.
@MainActor
final class Store: ObservableObject {

    @Published var document = Document()
    @Published private(set) var lastError: String?

    /// Alt çubukta gösterilecek bir hata; bir sonraki başarılı kayıtta silinir.
    func report(_ message: String) { lastError = message }

    static let directoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SpaceRouter",
                                isDirectory: true)

    static let fileURL = directoryURL.appendingPathComponent("rules.json")
    /// Okunamayan `rules.json` üzerine yazılmadan önce buraya kopyalanır.
    static let backupURL = directoryURL.appendingPathComponent("rules.json.bak")

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
            lastError = nil
        } catch {
            // Bozuk dosya ilk değişiklikte ezilecek; önce yedeğini al.
            let fm = FileManager.default
            try? fm.removeItem(at: Self.backupURL)
            let backedUp = (try? fm.copyItem(at: Self.fileURL, to: Self.backupURL)) != nil
            lastError = "rules.json okunamadı: \(error.localizedDescription)"
                + (backedUp ? " (yedek: rules.json.bak)" : "")
        }
    }

    func save() {
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

    // MARK: - Kurallar

    func add(_ rule: Rule) {
        document.rules.append(rule)
    }

    func update(_ rule: Rule) {
        guard let i = document.rules.firstIndex(where: { $0.id == rule.id })
        else { return }
        document.rules[i] = rule
    }

    func remove(_ id: String) {
        document.rules.removeAll { $0.id == id }
    }

    func rule(_ id: String) -> Rule? {
        document.rules.first { $0.id == id }
    }

    /// Bir kuralın verilen moddaki hedefini değiştirir (nil = atanmamış).
    func setDestination(_ destination: Destination?, for id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule[mode] = destination
        update(rule)
    }

    /// Pinler: aynı anahtarlı (uygulama + parçalar) kural varsa onun bu
    /// moddaki hedefi güncellenir, yoksa yeni kural eklenir. Kural kimliği
    /// döner.
    @discardableResult
    func pin(_ draft: Rule, destination: Destination, mode: Mode) -> String {
        if let existing = document.rules.first(where: { $0.sameKey(as: draft) }) {
            setDestination(destination, for: existing.id, mode: mode)
            return existing.id
        }
        var rule = draft
        rule[mode] = destination
        add(rule)
        return rule.id
    }

    /// Bu moddaki hedefi kaldırır; kuralın hiçbir hedefi kalmazsa silinir.
    func unpin(_ id: String, mode: Mode) {
        guard var rule = rule(id) else { return }
        rule[mode] = nil
        if rule.docked == nil && rule.undocked == nil {
            remove(id)
        } else {
            update(rule)
        }
    }

    /// Bir ekrandaki masaüstünü listede başka sıraya taşır; o ekranın bu
    /// moddaki bütün pinlerinin masaüstü numaraları buna göre kayar.
    /// `count`: listedeki satır sayısı (gerçek + pinlerin kullandığı).
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode) {
        guard let mapping = Self.desktopMapping(from: from, to: to, count: count)
        else { return }

        var rules = document.rules
        for i in rules.indices {
            guard var destination = rules[i][mode], destination.screen == screen,
                  let updated = mapping[destination.desktop] else { continue }
            destination.desktop = updated
            rules[i][mode] = destination
        }
        if rules != document.rules { document.rules = rules }
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

    var profiles: [Profile] { document.profiles }

    var activeProfile: Profile? {
        document.profiles.first { $0.id == document.activeProfileID }
    }

    /// Başka bir profile geçer: mevcut kurallar aktif profile yazılır,
    /// hedef profilin kuralları yüklenir. Router kural değişimini görüp
    /// pencereleri yeniden yerleştirir.
    func switchProfile(to id: String) {
        guard id != document.activeProfileID,
              let target = document.profiles.first(where: { $0.id == id }) else { return }
        var doc = document
        doc.syncActiveProfile()
        doc.activeProfileID = target.id
        doc.rules = target.rules
        document = doc
    }

    /// Yeni profil ekler ve ona geçer. `copyingCurrent`: mevcut pinlerle başla.
    @discardableResult
    func addProfile(named name: String? = nil, copyingCurrent: Bool = false) -> Profile {
        var doc = document
        doc.syncActiveProfile()
        let profile = Profile(
            name: uniqueName(name ?? "Profil \(doc.profiles.count + 1)", in: doc.profiles),
            rules: copyingCurrent ? doc.rules.map { var r = $0; r.id = UUID().uuidString; return r } : [])
        doc.profiles.append(profile)
        doc.activeProfileID = profile.id
        doc.rules = profile.rules
        document = doc
        return profile
    }

    func renameProfile(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        document.profiles[i].name = trimmed
    }

    /// Profili siler; son profil silinemez. Aktif siliniyorsa ilk kalana geçilir.
    func deleteProfile(_ id: String) {
        guard document.profiles.count > 1,
              let i = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        var doc = document
        doc.profiles.remove(at: i)
        if doc.activeProfileID == id, let next = doc.profiles.first {
            doc.activeProfileID = next.id
            doc.rules = next.rules
        }
        document = doc
    }

    // MARK: - Dışa / içe aktarma

    func exportData(for id: String) throws -> Data {
        var doc = document
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
    func importProfile(from data: Data) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ProfileExport.self, from: data)
        guard payload.kind == ProfileExport.kind || !payload.rules.isEmpty else {
            throw NSError(domain: "SpaceRouter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Bu bir Space Router profili değil"])
        }
        var doc = document
        doc.syncActiveProfile()
        let rules = payload.rules.map { var r = $0; r.id = UUID().uuidString; return r }
        let profile = Profile(name: uniqueName(payload.name, in: doc.profiles), rules: rules)
        doc.profiles.append(profile)
        doc.activeProfileID = profile.id
        doc.rules = profile.rules
        // Dosyadaki ekran adları bilinmeyen rolleri tanıtır (harita için).
        for screen in payload.screens where !doc.screens.contains(where: { $0.id == screen.id }) {
            doc.screens.append(screen)
        }
        document = doc
        return profile
    }

    private func uniqueName(_ name: String, in profiles: [Profile]) -> String {
        Document.uniqueName(name, in: profiles)
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
