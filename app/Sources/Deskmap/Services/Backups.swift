import AppKit
import Combine
import Foundation

// MARK: - Katmanlar ve takvim (saf)

/// Otomatik yedeğin katmanları (GFS). Her katman kendi klasöründe,
/// zaman dilimi (kova) başına tek dosya tutar; kovanın dosyası o dilimdeki
/// en son belge hâlidir.
///
/// - `hourly`: saat başına bir kopya, son 24 saat (kova UTC saati: yaz/kış
///   saati geçişinde iki yerel "01:00" çakışmaz).
/// - `daily`: gün başına bir kopya, son 7 takvim günü (yerel saat).
/// - `weekly`: ISO hafta başına bir kopya; **hiç silinmez**.
/// - `preRestore`: geri yüklemeden hemen önceki hâl; son `preRestoreLimit`.
enum BackupTier: String, CaseIterable, Codable, Sendable {
    case hourly
    case daily
    case weekly
    case preRestore = "pre-restore"
}

/// Kova adları, ad ayrıştırma ve budama kararı. Disk yok; takvim ve "şimdi"
/// dışarıdan verilir (testler saat dilimi, yaz saati ve yıl sınırını böyle
/// sınar).
struct BackupSchedule: Sendable {

    /// Günlük/haftalık kovaların saat dilimi (kullanıcının yerel saati).
    var timeZone: TimeZone

    static let hourlyWindow: TimeInterval = 24 * 3600
    static let dailyDays = 7
    static let preRestoreLimit = 10

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    private var local: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private var iso: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Katmanın `date` anındaki kova adı (dosya adı, uzantısız; aynı zamanda
    /// yedeğin kimliği): `hourly-20261012T14Z`, `daily-2026-10-12`,
    /// `weekly-2026-W41`, `pre-restore-20261012T143005Z`.
    func stem(_ tier: BackupTier, at date: Date) -> String {
        switch tier {
        case .hourly:
            let c = Self.utc.dateComponents([.year, .month, .day, .hour], from: date)
            return String(format: "hourly-%04d%02d%02dT%02dZ",
                          c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0)
        case .daily:
            let c = local.dateComponents([.year, .month, .day], from: date)
            return String(format: "daily-%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        case .weekly:
            let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "weekly-%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
        case .preRestore:
            let c = Self.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            return String(format: "pre-restore-%04d%02d%02dT%02d%02d%02dZ",
                          c.year ?? 0, c.month ?? 0, c.day ?? 0,
                          c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        }
    }

    /// Kova adını çözer: katman ve kovanın başlangıç anı. Bu biçimde
    /// olmayan (başkasının, geçici, bozuk adlı) her ad `nil`; budama
    /// yalnızca çözülebilen adlara dokunur.
    func parse(_ stem: String) -> (tier: BackupTier, start: Date)? {
        func numbers(_ text: Substring, _ widths: [Int], separators: [Character?]) -> [Int]? {
            var rest = text
            var values: [Int] = []
            for (index, width) in widths.enumerated() {
                let digits = rest.prefix(width)
                guard digits.count == width, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let value = Int(digits) else { return nil }
                values.append(value)
                rest = rest.dropFirst(width)
                if let separator = separators[index] {
                    guard rest.first == separator else { return nil }
                    rest = rest.dropFirst()
                }
            }
            return rest.isEmpty ? values : nil
        }
        func date(_ calendar: Calendar, _ components: DateComponents) -> Date? {
            guard let date = calendar.date(from: components) else { return nil }
            // Taşan tarihleri (13. ay, 31 Şubat) reddet: geri çevirince aynı olmalı.
            let back = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            for (want, got) in [(components.year, back.year), (components.month, back.month),
                                (components.day, back.day), (components.hour, back.hour),
                                (components.minute, back.minute), (components.second, back.second)]
            where want != nil && want != got { return nil }
            return date
        }

        if stem.hasPrefix("hourly-") {
            guard let v = numbers(stem.dropFirst(7), [4, 2, 2, 2], separators: [nil, nil, "T", "Z"]),
                  let start = date(Self.utc, DateComponents(year: v[0], month: v[1], day: v[2], hour: v[3]))
            else { return nil }
            return (.hourly, start)
        }
        if stem.hasPrefix("daily-") {
            guard let v = numbers(stem.dropFirst(6), [4, 2, 2], separators: ["-", "-", nil]),
                  let start = date(local, DateComponents(year: v[0], month: v[1], day: v[2]))
            else { return nil }
            return (.daily, start)
        }
        if stem.hasPrefix("weekly-") {
            let body = stem.dropFirst(7) // "2026-W41"
            guard body.count == 8, body.dropFirst(4).hasPrefix("-W"),
                  let v = numbers(body.prefix(4), [4], separators: [nil]),
                  let w = numbers(body.dropFirst(6), [2], separators: [nil]),
                  (1...53).contains(w[0]) else { return nil }
            var components = DateComponents()
            components.yearForWeekOfYear = v[0]
            components.weekOfYear = w[0]
            components.weekday = 2 // Pazartesi
            guard let start = iso.date(from: components),
                  stem == self.stem(.weekly, at: start) else { return nil }
            return (.weekly, iso.startOfDay(for: start))
        }
        if stem.hasPrefix("pre-restore-") {
            guard let v = numbers(stem.dropFirst(12), [4, 2, 2, 2, 2, 2],
                                  separators: [nil, nil, "T", nil, nil, "Z"]),
                  let start = date(Self.utc, DateComponents(
                    year: v[0], month: v[1], day: v[2], hour: v[3], minute: v[4], second: v[5]))
            else { return nil }
            return (.preRestore, start)
        }
        return nil
    }

    /// Katmanın dosyalarından (kova adları) silinecekleri seçer. Saf ve
    /// belirlenimci:
    /// - adı çözülemeyen ya da başka katmana ait ad hiç seçilmez;
    /// - `weekly` hiç budanmaz;
    /// - en yeni kova (çözülen başlangıcı en büyük) hiç silinmez: saat
    ///   ileri/geri atlasa da elde en az bir kopya kalır;
    /// - "şimdi"den ileri tarihli kovalar (saat geri alındı) silinmez;
    ///   zamanı gelince sıradan kova gibi budanır.
    /// `keep`: `pre-restore` katmanında kalacak sayı (varsayılan sınır).
    func expired(_ stems: [String], tier: BackupTier, now: Date, keep: Int? = nil) -> [String] {
        guard tier != .weekly else { return [] }
        let parsed = stems.compactMap { stem -> (String, Date)? in
            guard let p = parse(stem), p.tier == tier else { return nil }
            return (stem, p.start)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 > $1.0 }
        var drop: [String] = []
        switch tier {
        case .hourly:
            for (stem, start) in parsed.dropFirst()
            where now.timeIntervalSince(start) >= Self.hourlyWindow {
                drop.append(stem)
            }
        case .daily:
            let today = local.startOfDay(for: now)
            for (stem, start) in parsed.dropFirst() {
                let days = local.dateComponents([.day], from: local.startOfDay(for: start), to: today).day ?? 0
                if days >= Self.dailyDays { drop.append(stem) }
            }
        case .preRestore:
            drop = parsed.dropFirst(max(0, keep ?? Self.preRestoreLimit)).map(\.0)
        case .weekly:
            break
        }
        return drop.sorted()
    }
}

// MARK: - Yedek dosyası

/// Tek yedek dosyası: yedeklenen dosyaların ham metni, adlarına göre.
/// Ham metin saklanır (yeniden kodlanmaz): yedek, diskteki dosyanın
/// bayt bayt aynısıdır.
struct BackupBundle: Codable, Equatable, Sendable {
    static let kindValue = "deskmap-backup"
    static let currentFormat = 1

    var kind = BackupBundle.kindValue
    var format = BackupBundle.currentFormat
    var created: Date
    /// "rules.json" (her zaman), "hooks.json", "desktop-spaces.json".
    var files: [String: String]

    static let documentFile = "rules.json"
    static let hooksFile = "hooks.json"
    static let spacesFile = "desktop-spaces.json"
    /// Yedeklenen dosyalar, sırayla.
    static let fileNames = [documentFile, hooksFile, spacesFile]

    var isValid: Bool {
        kind == Self.kindValue && format <= Self.currentFormat && files[Self.documentFile] != nil
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupBundle.self, from: data)
    }

    /// İçindeki belge; okunamıyor, kuralı atlanıyor ya da daha yeni bir
    /// sürüme aitse hata.
    func document() throws -> Document {
        guard let text = files[Self.documentFile] else { throw BackupError.unreadable }
        return try BackupArchive.validDocument(Data(text.utf8))
    }
}

enum BackupError: Error, Equatable, LocalizedError {
    case noDocument
    case unreadable
    case newerVersion
    case notFound
    case invalidID

    var errorDescription: String? {
        switch self {
        case .noDocument:   return L("There is no rules.json to back up")
        case .unreadable:   return L("The backup cannot be read")
        case .newerVersion: return L("The backup belongs to a newer version of Deskmap")
        case .notFound:     return L("Backup not found")
        case .invalidID:    return L("Backup not found")
        }
    }
}

/// Listede gösterilen yedek özeti.
struct BackupEntry: Identifiable, Equatable, Sendable {
    struct ProfileSummary: Equatable, Sendable {
        let name: String
        let ruleCount: Int
        let isActive: Bool
    }
    /// Kova adı (`daily-2026-10-12`); `deskmap backup-restore <id>`.
    let id: String
    let tier: BackupTier
    /// Kopyanın alındığı an (kovanın içindeki son yazım).
    let created: Date
    let profiles: [ProfileSummary]
}

// MARK: - Disk

/// Yedek klasörü üzerindeki dosya işlemleri. Ana aktöre bağlı değil;
/// `BackupService` bunu arka plan kuyruğunda çalıştırır. Klasörler
/// dışarıdan verilir (testler geçici klasör kullanır).
struct BackupArchive: Sendable {

    /// Yedeklenen dosyaların klasörü (`Application Support/Deskmap`).
    let sourceDirectory: URL
    /// Yedeklerin kökü (`Application Support/Deskmap/Backups`).
    let root: URL
    var schedule = BackupSchedule()

    static let fileExtension = "json"
    /// Yazım sırasında kullanılan geçici dosya öneki; adı çözülemez,
    /// budama ve liste onu görmez. Yarıda kalanlar sonraki çalışmada silinir.
    static let tempPrefix = ".tmp-"

    init(sourceDirectory: URL, root: URL? = nil, schedule: BackupSchedule = BackupSchedule()) {
        self.sourceDirectory = sourceDirectory
        self.root = root ?? sourceDirectory.appendingPathComponent("Backups", isDirectory: true)
        self.schedule = schedule
    }

    func directory(_ tier: BackupTier) -> URL {
        root.appendingPathComponent(tier.rawValue, isDirectory: true)
    }

    func url(_ tier: BackupTier, stem: String) -> URL {
        directory(tier).appendingPathComponent("\(stem).\(Self.fileExtension)")
    }

    /// Belge yedeklenebilir mi: çözülmeli, daha yeni sürümün olmamalı,
    /// atlanan kuralı olmamalı (yarım belge iyi bir yedeğin yerini almasın).
    static func validDocument(_ data: Data) throws -> Document {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
        if document.isFromNewerVersion { throw BackupError.newerVersion }
        if document.droppedRuleCount > 0 { throw BackupError.unreadable }
        return document
    }

    /// Kaynak klasördeki dosyaların şu anki hâli. `rules.json` yoksa ya
    /// da geçerli değilse hata; diğer dosyalar varsa (ve UTF-8 ise) eklenir.
    func snapshot() throws -> [String: String] {
        let documentURL = sourceDirectory.appendingPathComponent(BackupBundle.documentFile)
        guard let data = try? Data(contentsOf: documentURL) else { throw BackupError.noDocument }
        _ = try Self.validDocument(data)
        guard let text = String(data: data, encoding: .utf8) else { throw BackupError.unreadable }
        var files = [BackupBundle.documentFile: text]
        for name in BackupBundle.fileNames where name != BackupBundle.documentFile {
            let url = sourceDirectory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                files[name] = text
            }
        }
        return files
    }

    /// Bir çalışmanın sonucu.
    struct RunResult: Equatable, Sendable {
        /// Yazılan kova adları.
        var written: [String] = []
        /// İçeriği aynı olduğu için yazılmayanlar.
        var unchanged: [String] = []
        /// Silinen (süresi dolan) kova adları.
        var pruned: [String] = []
        /// Yedek alınmadıysa nedeni.
        var skipped: BackupError?
        /// Bu çalışmanın kova adları ve içeriği (sonraki çalışma aynıysa
        /// diske hiç bakmaz).
        var state: State?
    }

    struct State: Equatable, Sendable {
        let stems: [String]
        let files: [String: String]
    }

    /// Saatlik/günlük/haftalık kovaları günceller, süresi dolanları budar.
    /// `previous` bu çalışmanın kova adları ve içeriğiyle aynıysa hiçbir
    /// dosyaya dokunmaz (beş dakikada bir tetiklenir; ucuz kalmalı).
    func run(now: Date, previous: State? = nil) -> RunResult {
        var result = RunResult()
        let files: [String: String]
        do {
            files = try snapshot()
        } catch let error as BackupError {
            result.skipped = error
            return result
        } catch {
            result.skipped = .unreadable
            return result
        }
        let tiers: [BackupTier] = [.hourly, .daily, .weekly]
        let stems = tiers.map { schedule.stem($0, at: now) }
        let state = State(stems: stems, files: files)
        result.state = state
        if state == previous {
            result.unchanged = stems
            return result
        }
        let newRules = Self.ruleCount(files)
        var complete = true
        for (tier, stem) in zip(tiers, stems) {
            let target = url(tier, stem: stem)
            if let existing = try? BackupBundle.decode(Data(contentsOf: target)), existing.isValid {
                if existing.files == files {
                    result.unchanged.append(stem)
                    continue
                }
                // Boş belge (hiç kural yok) aynı kovadaki dolu yedeğin yerini almaz.
                if newRules == 0, Self.ruleCount(existing.files) > 0 {
                    result.unchanged.append(stem)
                    continue
                }
            }
            do {
                try write(BackupBundle(created: now, files: files), to: target)
                result.written.append(stem)
            } catch {
                complete = false
            }
        }
        // Budama yalnızca bu çalışmanın kovaları yerindeyse: elde geçerli
        // en yeni kopya olmadan eski kopya silinmez.
        if complete {
            result.pruned = prune(now: now)
        } else {
            result.state = nil
        }
        removeStaleTemporaries(now: now)
        return result
    }

    /// Belgedeki toplam kural sayısı (tüm profiller); okunamazsa 0.
    static func ruleCount(_ files: [String: String]) -> Int {
        guard let text = files[BackupBundle.documentFile],
              let document = try? JSONDecoder().decode(Document.self, from: Data(text.utf8))
        else { return 0 }
        let profileRules = document.profiles.reduce(0) { $0 + $1.rules.count }
        return max(profileRules, document.rules.count)
    }

    /// Geri yüklemeden önceki hâl: verilen belge (bellekteki, kaydedilmemiş
    /// değişiklikler dahil) ve diskteki diğer dosyalar.
    @discardableResult
    func writePreRestore(document: Data, now: Date) throws -> String {
        var files: [String: String] = [:]
        if let current = try? snapshot() { files = current }
        guard let text = String(data: document, encoding: .utf8) else { throw BackupError.unreadable }
        files[BackupBundle.documentFile] = text
        var stem = schedule.stem(.preRestore, at: now)
        // Aynı saniyede ikinci geri yükleme: öncekini ezmesin, bir saniye ileri.
        var offset: TimeInterval = 0
        while FileManager.default.fileExists(atPath: url(.preRestore, stem: stem).path) {
            offset += 1
            stem = schedule.stem(.preRestore, at: now.addingTimeInterval(offset))
        }
        try write(BackupBundle(created: now, files: files), to: url(.preRestore, stem: stem))
        // Yeni yazılan kopya hiç silinmez (saat geri alınmış olsa da);
        // diğerlerinden en yeni `limit - 1` tanesi kalır.
        let others = stems(in: .preRestore).filter { $0 != stem }
        for old in schedule.expired(others, tier: .preRestore, now: now, keep: BackupSchedule.preRestoreLimit - 1) {
            try? FileManager.default.removeItem(at: url(.preRestore, stem: old))
        }
        return stem
    }

    /// Süresi dolan saatlik ve günlük kovaları siler; silinenleri döndürür.
    @discardableResult
    func prune(now: Date) -> [String] {
        var removed: [String] = []
        for tier in [BackupTier.hourly, .daily] {
            for stem in schedule.expired(stems(in: tier), tier: tier, now: now)
            where (try? FileManager.default.removeItem(at: url(tier, stem: stem))) != nil {
                removed.append(stem)
            }
        }
        return removed
    }

    /// Katman klasöründeki, o katmana ait adlı yedeklerin kova adları.
    func stems(in tier: BackupTier) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory(tier).path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".\(Self.fileExtension)") else { return nil }
            let stem = String(name.dropLast(Self.fileExtension.count + 1))
            guard schedule.parse(stem)?.tier == tier else { return nil }
            return stem
        }
    }

    /// Tüm yedekler; yeniden eskiye, okunamayanlar atlanır.
    func list() -> [BackupEntry] {
        var entries: [BackupEntry] = []
        for tier in BackupTier.allCases {
            for stem in stems(in: tier) {
                guard let bundle = try? read(stem), let document = try? bundle.document()
                else { continue }
                entries.append(BackupEntry(
                    id: stem, tier: tier, created: bundle.created,
                    profiles: document.profiles.map {
                        .init(name: $0.name,
                              ruleCount: $0.id == document.activeProfileID
                                ? max($0.rules.count, document.rules.count) : $0.rules.count,
                              isActive: $0.id == document.activeProfileID)
                    }))
            }
        }
        return entries.sorted { $0.created != $1.created ? $0.created > $1.created : $0.id < $1.id }
    }

    /// Kimliği verilen yedeği okur. Kimlik bir kova adı olmalı; yol, nokta
    /// ya da başka karakter içeren ad reddedilir.
    func read(_ id: String) throws -> BackupBundle {
        guard let tier = schedule.parse(id)?.tier else { throw BackupError.invalidID }
        guard let data = try? Data(contentsOf: url(tier, stem: id)) else { throw BackupError.notFound }
        guard let bundle = try? BackupBundle.decode(data), bundle.isValid else {
            throw BackupError.unreadable
        }
        return bundle
    }

    /// Geçici dosyaya yazar, diske işler, sonra tek adımda yerine taşır:
    /// yarıda kalan yazım eski yedeği bozmaz.
    func write(_ bundle: BackupBundle, to target: URL) throws {
        let fm = FileManager.default
        let directory = target.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.atomicWrite(try bundle.encoded(), to: target)
    }

    /// Aynı klasörde geçici dosya + `fsync` + `rename(2)`.
    static func atomicWrite(_ data: Data, to target: URL) throws {
        let directory = target.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(
            "\(tempPrefix)\(UUID().uuidString)-\(target.lastPathComponent)")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        if rename(temp.path, target.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Yarıda kalmış (bir saatten eski) geçici dosyaları siler; yalnızca
    /// kendi önekimizi taşıyanları.
    func removeStaleTemporaries(now: Date) {
        let fm = FileManager.default
        for tier in BackupTier.allCases {
            let dir = directory(tier)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            where name.hasPrefix(Self.tempPrefix) {
                let url = dir.appendingPathComponent(name)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? now
                if now.timeIntervalSince(modified) > 3600 { try? fm.removeItem(at: url) }
            }
        }
    }
}

// MARK: - Uygulama içi zamanlayıcı

/// Otomatik yedeği uygulamanın kendisi çalıştırır: açılışta, beş dakikada
/// bir (kova değiştiyse ya da belge değiştiyse yazar), uykudan uyanınca,
/// saat/gün değişince. Zamanlayıcı süreyi sistem saatinden değil geçen
/// süreden sayar; kova adı her seferinde o anki saatten hesaplanır, saat
/// ileri/geri alınsa da doğru kovaya yazılır. Dosya işleri arka plan
/// kuyruğunda; ana iş parçacığı beklemez.
@MainActor
final class BackupService: ObservableObject {

    /// Liste (panel açıkken yüklenir).
    @Published private(set) var entries: [BackupEntry] = []
    @Published private(set) var lastRun: Date?

    /// Üretimdeki örnek (`AppModel`); Shots modunda nil. Panel bunu okur:
    /// `AppModel.shared`'a dokunmak üretim yolunu başlatırdı.
    static var current: BackupService?

    let archive: BackupArchive
    static let tickInterval: TimeInterval = 300

    private let queue = DispatchQueue(label: "deskmap.backup", qos: .utility)
    /// Yalnızca `queue` üzerinde okunur/yazılır.
    nonisolated(unsafe) private var previous: BackupArchive.State?
    nonisolated(unsafe) private var timer: Timer?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(archive: BackupArchive) {
        self.archive = archive
    }

    deinit {
        timer?.invalidate()
    }

    /// Açılışta bir kez çağrılır.
    func start() {
        guard timer == nil else { return }
        runInBackground()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runInBackground() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        for (nc, name) in [(workspace, NSWorkspace.didWakeNotification),
                           (center, Notification.Name.NSSystemClockDidChange),
                           (center, Notification.Name.NSCalendarDayChanged),
                           (center, Notification.Name.NSSystemTimeZoneDidChange)] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runInBackground() }
            }
            tokens.append((nc, token))
        }
    }

    /// Arka planda bir çalışma; kuyruk sıralı olduğu için çakışmaz.
    func runInBackground() {
        let archive = archive
        queue.async { [weak self] in
            guard let self else { return }
            var archive = archive
            archive.schedule = BackupSchedule(timeZone: .current)
            let result = archive.run(now: Date(), previous: self.previous)
            self.previous = result.state
            if !result.written.isEmpty || !result.pruned.isEmpty {
                Log.app.notice("Backup: wrote \(result.written.count), pruned \(result.pruned.count)")
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.lastRun = Date() }
            }
        }
    }

    /// Şimdi yedek al (komut satırı): eşzamanlı, sonucu döndürür.
    func runNow() -> BackupArchive.RunResult {
        queue.sync {
            var archive = archive
            archive.schedule = BackupSchedule(timeZone: .current)
            let result = archive.run(now: Date(), previous: nil)
            previous = result.state
            return result
        }
    }

    /// Listeyi arka planda yeniler.
    func reload() {
        let archive = archive
        queue.async {
            let entries = archive.list()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.entries = entries }
            }
        }
    }

    /// Yedeği geri yükler: önce şimdiki hâl `pre-restore` katmanına yazılır
    /// (başaramazsa hiçbir şey değişmez), sonra belge Store'un olağan
    /// yolundan (geri alınabilir) değişir, `hooks.json` yedekteki hâline
    /// döner ve pinler yeniden uygulanır. `desktop-spaces.json` geri
    /// yüklenmez: içindeki masaüstü kimlikleri o anki oturuma ait.
    @discardableResult
    func restore(_ id: String, store: Store, router: Router?) -> Bool {
        guard !store.isReadOnly else {
            store.report(Store.newerVersionMessage)
            return false
        }
        let bundle: BackupBundle
        let document: Document
        do {
            bundle = try queue.sync { try archive.read(id) }
            document = try bundle.document()
        } catch {
            store.report(L("Could not restore backup: %@", error.localizedDescription))
            return false
        }
        store.flush()
        do {
            let current = try Store.encode(store.document)
            _ = try queue.sync { try archive.writePreRestore(document: current, now: Date()) }
        } catch {
            store.report(L("Could not restore backup: %@", error.localizedDescription))
            return false
        }
        // rules.json yazılamadıysa hooks.json'a dokunma: iki dosya ayrışmasın.
        guard store.restoreBackup(document) else {
            if let message = store.lastError {
                store.report(L("Could not restore backup: %@", message))
            }
            reload()
            return false
        }
        if let hooks = bundle.files[BackupBundle.hooksFile] {
            let target = archive.sourceDirectory.appendingPathComponent(BackupBundle.hooksFile)
            if (try? String(contentsOf: target, encoding: .utf8)) != hooks {
                do {
                    try BackupArchive.atomicWrite(Data(hooks.utf8), to: target)
                } catch {
                    store.report(L("Could not restore hooks.json: %@", error.localizedDescription))
                    router?.reapplyAll()
                    reload()
                    return false
                }
            }
        }
        router?.reapplyAll()
        reload()
        return true
    }
}
