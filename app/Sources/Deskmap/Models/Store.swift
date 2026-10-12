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

    /// Bağlı ekranların canlı masaüstü sırası (Router her kararlı taramada
    /// verir). Etkin kurulumda satır adları ve ad hedeflerinin yeri buradan.
    @Published private(set) var live: LiveDesktops?

    /// Şema 5 dosyası okundu, adlar henüz taşınmadı (§A.8 aşama 1): belge
    /// geçici şema 6 hâlidir, diske yazılmaz; Router ilk kararlı taramada
    /// canlı kanıtla `completeMigration` çağırır. Bu sürede ad hedefli
    /// pencereler taşınmaz.
    @Published private(set) var migrationPending = false
    /// Geçişin kaynağı (okunan şema 5 belgesi).
    private var migrationSource: Document?
    /// Kaynak geri yüklenen bir yedek (önce-geçiş yedeği yazılmaz).
    private var migrationFromRestore = false
    /// Son geçişin raporu (alt çubuk kartı); kapatılınca nil.
    @Published private(set) var migrationReport: MigrationReport?
    /// "Geçişi geri al" yapıldı: şema 5 dosyası yerinde, bu oturum salt okunur.
    @Published private(set) var upgradeUndone = false
    /// Geçişten önce alınan dosyanın yolu (geri alma için).
    private var preMigrationBackup: URL?

    /// Alt çubukta gösterilecek bir hata; bir sonraki başarılı kayıtta silinir.
    func report(_ message: String) { lastError = message }
    func clearError() { lastError = nil }

    /// Veri klasörü. `DESKMAP_DATA_DIR` ortam değişkeni başka bir klasörü
    /// gösterebilir (geçişi bir kopya üzerinde denemek için).
    nonisolated static let directoryURL: URL = {
        if let path = ProcessInfo.processInfo.environment["DESKMAP_DATA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        // Testler gerçek veri klasörüne asla dokunmaz.
        if Log.isTesting { return testDirectory.appendingPathComponent("Deskmap", isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Deskmap", isDirectory: true)
    }()

    /// Eski ad (Space Router) altındaki veri klasörü; `init()` içinde bir
    /// kez buradan `directoryURL`'e kopyalanır (bkz. `DataMigration`).
    static let legacyDirectoryURL = Log.isTesting
        ? testDirectory.appendingPathComponent("SpaceRouter", isDirectory: true)
        : FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpaceRouter", isDirectory: true)

    /// Test sürecinin geçici kökü (gerçek Application Support yerine).
    nonisolated static let testDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeskmapTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    static let fileURL = directoryURL.appendingPathComponent("rules.json")
    /// Okunamayan `rules.json` üzerine yazılmadan önce buraya kopyalanır.
    static let backupURL = directoryURL.appendingPathComponent("rules.json.bak")
    /// Şema geçişinden önceki dosyaların kopyaları (hiç budanmaz).
    static let preMigrationURL = directoryURL.appendingPathComponent("Backups/pre-migration",
                                                                     isDirectory: true)

    /// Dosya daha yeni bir Deskmap sürümüne aitse (ya da geçiş geri
    /// alındıysa) yazma kapalıdır: eski sürüm bilmediği alanları silmesin.
    var isReadOnly: Bool { document.isFromNewerVersion || upgradeUndone }
    static let newerVersionMessage =
        L("rules.json belongs to a newer version of Deskmap; changes will not be saved")
    static let upgradeUndoneMessage =
        L("Desktop names upgrade undone; changes are not saved until Deskmap restarts")

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
            MainActor.assumeIsolated { _ = self?.flush() }
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
        persists = false
    }

    /// Demo/test örneği diske hiç yazmaz (`save` sessizce döner).
    private var persists = true

    /// Bekleyen değişiklikleri hemen diske yazar.
    @discardableResult
    func flush() -> Bool {
        document.syncActiveProfile()
        return save()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            let decoded = try JSONDecoder().decode(Document.self, from: data)
            beginMigrationIfNeeded(decoded, fromRestore: false)
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

    /// Okunan belge şema 6'dan eskiyse geçici (kanıtsız) şema 6 hâli
    /// yüklenir ve geçiş bekler; değilse belge olduğu gibi.
    private func beginMigrationIfNeeded(_ decoded: Document, fromRestore: Bool) {
        guard decoded.needsNameMigration else {
            migrationSource = nil
            migrationPending = false
            document = decoded
            return
        }
        migrationSource = decoded
        migrationFromRestore = fromRestore
        migrationPending = true
        var provisional = MigrationV6.migrate(decoded, evidence: nil).document
        provisional.droppedRuleCount = decoded.droppedRuleCount
        document = provisional
        Log.app.notice("rules.json is schema \(decoded.fileVersion); desktop names upgrade waits for the first stable sweep")
    }

    /// §A.8 aşama 2: canlı kanıtla geçiş. Önce dosyalar `Backups/pre-migration`'a
    /// kopyalanır (yazılamazsa geçiş yapılmaz, oturum salt okunur kalır),
    /// sonra belge şema 6 olur, tek geri alma adımı ve rapor kartı. Hiç
    /// pencere taşımaz, masaüstü açmaz/silmez.
    @discardableResult
    func completeMigration(evidence: MigrationEvidence?, now: Date = Date()) -> Bool {
        guard migrationPending, let source = migrationSource else { return false }
        if persists && !migrationFromRestore {
            do {
                preMigrationBackup = try Self.writePreMigrationBackup(at: now)
            } catch {
                migrationPending = false
                migrationSource = nil
                upgradeUndone = true
                lastError = L("Desktop names upgrade stopped: could not write the backup (%@)",
                              error.localizedDescription)
                Log.app.error("Pre-migration backup failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        var result = MigrationV6.migrate(source, evidence: evidence)
        result.document.enabled = document.enabled
        result.document.screens = document.screens
        result.document.droppedRuleCount = 0
        let before = document
        migrationPending = false
        migrationSource = nil
        document = result.document
        if preMigrationBackup != nil {
            // ⌘Z = "Geçişi geri al": şema 5 dosyası geri yazılır. Geçici
            // (kanıtsız) belgeye dönmek onu şema 6 olarak kaydederdi.
            undoBuffer.record(L("Desktop names upgraded"), before: document, after: document,
                              companion: { [weak self] in self?.undoUpgrade() })
        } else {
            undoBuffer.record(L("Desktop names upgraded"), before: before, after: document, companion: nil)
        }
        migrationReport = result.report
        for entry in result.report.profiles {
            let bound = entry.bound.map { "\($0.name)→\($0.screen)/\($0.desktop)(\($0.space))" }
                .joined(separator: ", ")
            Log.app.notice("Desktop names upgraded in profile \(entry.profileName, privacy: .private): bound \(bound, privacy: .private); unplaced \(entry.unplaced.count); ghosts removed \(entry.ghostsRemoved); pins restored \(entry.pinsRestored)")
        }
        _ = flush()
        return true
    }

    /// `rules.json` ve `desktop-spaces.json` (varsa) önce-geçiş kopyaları.
    nonisolated static func writePreMigrationBackup(at now: Date,
                                                    directory: URL = directoryURL) throws -> URL {
        let fm = FileManager.default
        let target = directory.appendingPathComponent("Backups/pre-migration", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: now)
        let rules = target.appendingPathComponent("rules-v5-\(stamp).json")
        try? fm.removeItem(at: rules)
        try fm.copyItem(at: directory.appendingPathComponent("rules.json"), to: rules)
        let spaces = directory.appendingPathComponent(DesktopStateFile.legacyFileName)
        if fm.fileExists(atPath: spaces.path) {
            let copy = target.appendingPathComponent("desktop-spaces-\(stamp).json")
            try? fm.removeItem(at: copy)
            try fm.copyItem(at: spaces, to: copy)
        }
        return rules
    }

    /// "Geçişi geri al": önce-geçiş dosyası `rules.json` olarak geri yazılır;
    /// bu oturum salt okunur (eski şema), sonraki açılışta geçiş yeniden.
    func undoUpgrade() {
        guard let backup = preMigrationBackup,
              let data = try? Data(contentsOf: backup) else {
            report(L("The pre-upgrade backup could not be read"))
            return
        }
        do {
            try data.write(to: Self.fileURL, options: .atomic)
            if let decoded = try? JSONDecoder().decode(Document.self, from: data) {
                var provisional = MigrationV6.migrate(decoded, evidence: nil).document
                provisional.enabled = document.enabled
                provisional.screens = document.screens
                document = provisional
            }
            upgradeUndone = true
            migrationReport = nil
            lastError = Self.upgradeUndoneMessage
            Log.app.notice("Desktop names upgrade undone; rules.json restored from \(backup.lastPathComponent, privacy: .public)")
        } catch {
            report(L("Could not write rules.json: %@", error.localizedDescription))
        }
    }

    func dismissMigrationReport() { migrationReport = nil }

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

    /// Başarıyı döndürür (diske yazmayan demo örneğinde true).
    @discardableResult
    func save() -> Bool {
        guard persists else { return true }
        // Geçiş bekliyor: geçici belge yazılmaz (geçişten sonra yazılır).
        guard !migrationPending else { return true }
        // Yeni sürümün dosyası: dokunma, uyarı alt çubukta kalsın.
        guard !isReadOnly else {
            lastError = upgradeUndone ? Self.upgradeUndoneMessage : Self.newerVersionMessage
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL, withIntermediateDirectories: true)
            try Self.encode(document).write(to: Self.fileURL, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = L("Could not write rules.json: %@", error.localizedDescription)
            return false
        }
    }

    /// `rules.json` biçimi (kayıt ve geri yükleme öncesi yedek aynı baytlar).
    nonisolated static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// Yedekten gelen belgeyi yükler (bkz. `BackupService.restore`). Olağan
    /// değişiklik yolu: alt çubukta "Geri al" çıkar, hemen diske yazılır.
    /// Açık/kapalı anahtarı ve tanınan ekranlar şu anki değerleriyle kalır.
    /// Şema 5 yedeği önce şema 6'ya taşınır (Router canlı kanıtla tamamlar).
    /// Belge diske yazıldıysa (ya da geçiş beklemeye alındıysa) true.
    @discardableResult
    func restoreBackup(_ backup: Document) -> Bool {
        guard !isReadOnly, !backup.isFromNewerVersion else {
            lastError = Self.newerVersionMessage
            return false
        }
        var restored = backup
        restored.droppedRuleCount = 0
        restored.enabled = document.enabled
        restored.screens = document.screens
        if restored.needsNameMigration {
            recording(L("Backup restored")) {
                beginMigrationIfNeeded(restored, fromRestore: true)
            }
            return true
        }
        restored.fileVersion = Document.currentVersion
        restored.version = Document.currentVersion
        restored.syncActiveProfile()
        recording(L("Backup restored")) { document = restored }
        if let live { bindByPlan(live: live) }
        return flush()
    }

    // MARK: - Canlı durum

    /// Router'ın canlı masaüstü okuması; ad hedeflerinin önbelleği yenilenir.
    func setLive(_ value: LiveDesktops?) {
        guard value != live else { return }
        live = value
        refreshNameCaches()
    }

    /// Ad hedeflerinin önbelleği (geri alma kaydı yok).
    func refreshNameCaches() {
        var copy = document
        copy.refreshNameCaches(live: live)
        if copy != document { document = copy }
    }

    // MARK: - Geri alma

    /// `change` belgeyi gerçekten değiştirdiyse önceki ve sonraki hâli
    /// `label` ile saklar; etkisiz çağrılar (olmayan kural, son profil) kayıt
    /// bırakmaz. `companion`: belge dışındaki durumu (oturum pinleri) geri
    /// alan kapanış; verilmişse belge değişmese de kayıt bırakılır.
    private func recording(_ label: String, companion: (() -> Void)? = nil,
                           _ change: () -> Void) {
        let before = document
        change()
        if document != before || companion != nil {
            undoBuffer.record(label, before: before, after: document, companion: companion)
        }
    }

    /// Belgeye dokunmayan ama geri alınabilir olması istenen işlem (geçici
    /// pinin sürüklenmesi): yalnızca eşlik kapanışı saklanır.
    func recordSessionChange(_ label: String, undo companion: @escaping () -> Void) {
        undoBuffer.record(label, before: document, after: document, companion: companion)
    }

    /// Son yıkıcı işlemi geri alır: saklanan belge tek atamayla geri gelir,
    /// ardından eşlik kapanışı (oturum pinleri) çalışır. Açık/kapalı
    /// anahtarı ve o arada tanınan ekranlar şu anki değerleriyle korunur.
    func undo() {
        guard let entry = undoBuffer.take() else { return }
        var restored = entry.before
        restored.enabled = document.enabled
        restored.screens = document.screens
        restored.refreshNameCaches(live: live)
        if restored != document { document = restored }
        entry.companion?()
    }

    /// Belgeyi değiştirir, ad önbelleklerini yeniler (geri alma kaydı yok).
    private func mutate(_ body: (inout Document) -> Void) {
        var copy = document
        body(&copy)
        copy.refreshNameCaches(live: live)
        if copy != document { document = copy }
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
        let live = live
        document.setDestination(destination, for: id, mode: mode, live: live)
    }

    /// Sürükleyip bırakma ile hedef değişimi: `setDestination` gibi, ama
    /// geri alınabilir (yanlış masaüstüne bırakılan pin tek tıkla döner).
    func moveRule(_ id: String, to destination: Destination, mode: Mode) {
        let live = live
        recording(L("Pin moved")) {
            document.setDestination(destination, for: id, mode: mode, live: live)
        }
    }

    /// "Şu anki boyutu kullan": pencerenin gerçek çerçevesinden okunan
    /// düzeni kuralın bu moddaki hedefine yazar. Değişiklik olduysa true.
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
        let live = live
        guard let existing = document.rules.first(where: { $0.sameKey(as: draft) }),
              existing[mode] != nil else {
            return document.pin(draft, destination: destination, mode: mode, live: live)
        }
        var id = existing.id
        recording(L("Pin updated")) {
            id = document.pin(draft, destination: destination, mode: mode, live: live)
        }
        return id
    }

    /// Toplu pinleme: hepsi tek adımda yazılır, ⌘Z hepsini geri alır.
    func pinMany(_ items: [(rule: Rule, destination: Destination)], mode: Mode,
                 companion: (() -> Void)? = nil) {
        guard !items.isEmpty else { return }
        let live = live
        recording(L("Windows pinned"), companion: companion) {
            for item in items {
                document.pin(item.rule, destination: item.destination, mode: mode, live: live)
            }
        }
    }

    /// Uygulama grubunun taşınması: kuralların hedefleri `moveRule` ile
    /// aynı biçimde yazılır; tek geri alma adımı.
    func moveGroup(_ moves: [GroupMovePlan.RuleMove], mode: Mode,
                   undoingSessionPins: (() -> Void)? = nil) {
        guard !moves.isEmpty || undoingSessionPins != nil else { return }
        let live = live
        recording(L("Group moved"), companion: undoingSessionPins) {
            for move in moves {
                document.setDestination(move.destination, for: move.id, mode: mode, live: live)
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

    /// "Laptop düzenini buraya kopyala": `source` modunun kurulumu ve laptop
    /// planı `target` modunun üzerine yazılır (geri alınabilir).
    @discardableResult
    func copyLayout(from source: Mode, to target: Mode) -> Bool {
        var changed = false
        recording(L("Layout copied")) {
            changed = document.copyLayout(from: source, to: target)
            document.refreshNameCaches(live: live)
        }
        return changed
    }

    // MARK: - Masaüstü işlemleri

    /// Bir ekrandaki masaüstünü listede başka sıraya taşır (bkz.
    /// `Document.moveDesktop`). `undoingSessionPins`: oturum pinleri de
    /// kaydıysa onları geri taşıyan kapanış.
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode,
                     sharedLaptop: Bool = false, liveSpaces: [UInt64]? = nil,
                     undoingSessionPins companion: (() -> Void)? = nil) {
        let live = live
        recording(L("Desktop order changed"), companion: companion) {
            document.moveDesktop(on: screen, from: from, to: to, count: count, mode: mode,
                                 sharedLaptop: sharedLaptop, liveSpaces: liveSpaces)
            document.refreshNameCaches(live: live)
        }
    }

    /// Masaüstünü başka ekrana taşır (bkz. `Document.moveDesktopAcross`);
    /// pinler ve planlar tek adımda ⌘Z ile geri gelir.
    func moveDesktopAcross(from fromScreen: String, desktop from: Int,
                           to toScreen: String, at to: Int, toCount: Int, mode: Mode,
                           spaceMap: [UInt64: UInt64]? = nil,
                           undoingSessionPins companion: (() -> Void)? = nil) {
        let live = live
        recording(L("Desktop moved to another display"), companion: companion) {
            document.moveDesktopAcross(from: fromScreen, desktop: from, to: toScreen, at: to,
                                       toCount: toCount, mode: mode, spaceMap: spaceMap)
            document.refreshNameCaches(live: live)
        }
    }

    /// Etkin olmayan kurulumun planından satır siler (bkz.
    /// `Document.removePlanEntry`); ⌘Z geri alır.
    func removePlanEntry(on screen: String, desktop: Int, mode: Mode,
                         undoing companion: (() -> Void)? = nil) {
        Log.app.notice("Desktop \(desktop) on \(screen, privacy: .public) removed from the \(mode.rawValue, privacy: .public) plan")
        let live = live
        recording(L("Desktop removed"), companion: companion) {
            document.removePlanEntry(screen: screen, desktop: desktop, mode: mode)
            document.refreshNameCaches(live: live)
        }
    }

    /// Kuyruktaki ilk silme yapıldı ya da geçersiz (geri alma kaydı yok).
    func dropFirstPendingRemoval(mode: Mode, screen: String) {
        document.dropFirstPendingRemoval(mode: mode, screen: screen)
    }

    /// Gerçek bir masaüstü silindi (Mission Control ya da Deskmap): bütün
    /// profillerde ad ve pinler hayalete, numaralar kayar. Geri alma kaydı
    /// yok: ⌘Z masaüstünü geri getiremez.
    @discardableResult
    func recordDeletion(space: UInt64?, role: String, desktop: Int, mode: Mode,
                        shiftModes: [Mode]? = nil) -> GhostDesktop? {
        var ghost: GhostDesktop?
        mutate { ghost = $0.recordDeletion(space: space, role: role, desktop: desktop, mode: mode,
                                           shiftModes: shiftModes) }
        return ghost
    }

    /// Kararlı durumda Mission Control değişikliklerini izler (B 8–12).
    @discardableResult
    func followMissionControl(before: [String: [UInt64]], after: [String: [UInt64]], mode: Mode,
                              ownRemovals: Set<UInt64>) -> [DesktopDeletion] {
        var deletions: [DesktopDeletion] = []
        mutate { deletions = $0.followMissionControl(before: before, after: after, mode: mode,
                                                     ownRemovals: ownRemovals) }
        return deletions
    }

    /// R2: geçişte kaybolan space'lerin adları, her profile ayrı. Etkin
    /// profilin tahliye kümeleri döner.
    func resolveSuccession(snapshot: Succession.Snapshot, live: LiveDesktops,
                           windowSpaces: [CGWindowID: UInt64]) -> [String: [CGWindowID]] {
        var evacuation: [String: [CGWindowID]] = [:]
        mutate { doc in
            doc.syncActiveProfile()
            for i in doc.profiles.indices {
                let result = Succession.resolve(names: doc.profiles[i].names, snapshot: snapshot,
                                                live: live, windowSpaces: windowSpaces,
                                                plans: doc.profiles[i].plans)
                if doc.profiles[i].names != result.names { doc.profiles[i].names = result.names }
                if doc.profiles[i].id == doc.activeProfileID {
                    evacuation = result.evacuation
                    doc.names = result.names
                }
            }
        }
        return evacuation
    }

    /// R4: kanıt yok (yeniden başlatma, geri yükleme).
    func bindByPlan(live: LiveDesktops) {
        mutate { $0.bindByPlan(live: live) }
    }

    /// Plan uygulamasının sonucu: içeriği taşınan space'ler bütün
    /// profillerde (R5), etkin profilin adları kendi yerlerine.
    func commitPlan(rebinds: [String: UInt64], spaceMap: [UInt64: UInt64]) {
        mutate { doc in
            doc.applySpaceMap(spaceMap)
            for i in doc.names.indices {
                if let space = rebinds[doc.names[i].id] { doc.names[i].space = space }
            }
        }
    }

    /// Plan ya da pin satırı silindi: o kurulumda gerçek silme yok.
    func clearPendingRemovals(mode: Mode, screen: String) {
        document.clearPendingRemovals(mode: mode, screen: screen)
    }

    /// Ad hedefinin adı ve "bekliyor" durumu (adın masaüstü yok ya da
    /// canlı kurulumda bağlı değil); numara hedefinde nil.
    func nameTarget(_ destination: Destination?, mode: Mode) -> (name: String, waiting: Bool)? {
        guard let id = destination?.nameID, let record = document.nameRecord(id) else { return nil }
        let waiting: Bool
        if let live, live.mode == mode {
            waiting = record.space.flatMap { live.place(of: $0) } == nil
        } else {
            waiting = record.space == nil && document.plans.place(of: id, mode: mode) == nil
        }
        return (record.name, waiting)
    }

    /// Bu kurulumda yeri olan adlar (gönder menüsü için): ad, kimlik, yer.
    func namedPlaces(mode: Mode) -> [(id: String, name: String, place: Slot)] {
        document.names.compactMap { record in
            var place: Slot?
            if let live, live.mode == mode, let space = record.space { place = live.place(of: space) }
            if place == nil { place = document.plans.place(of: record.id, mode: mode) }
            return place.map { (record.id, record.name, $0) }
        }.sorted { ($0.place.screen, $0.place.desktop) < ($1.place.screen, $1.place.desktop) }
    }

    func desktopName(screen: String, desktop: Int, mode: Mode) -> String? {
        document.desktopName(screen: screen, desktop: desktop, mode: mode, live: live)
    }

    func nameID(screen: String, desktop: Int, mode: Mode) -> String? {
        document.nameID(screen: screen, desktop: desktop, mode: mode, live: live)
    }

    /// Masaüstüne ad verir; boş ad siler (geri alınabilir). Ad aynı
    /// profilde başka masaüstünde varsa reddedilir (false).
    @discardableResult
    func setDesktopName(_ name: String?, screen: String, desktop: Int, mode: Mode) -> Bool {
        var accepted = true
        let live = live
        recording(L("Desktop renamed")) {
            accepted = document.setDesktopName(name, screen: screen, desktop: desktop,
                                               mode: mode, live: live)
            document.refreshNameCaches(live: live)
        }
        return accepted
    }

    /// Masaüstü olmayan adı siler (pinleri adlı hayalete; geri alınabilir).
    func deleteName(_ id: String) {
        let live = live
        recording(L("Desktop removed")) {
            document.deleteName(id)
            document.refreshNameCaches(live: live)
        }
    }

    func ghosts(on screen: String) -> [GhostDesktop] { document.ghosts(on: screen) }

    func ghosts(on screen: String, mode: Mode) -> [GhostDesktop] {
        document.ghosts(on: screen, mode: mode)
    }

    /// Hayaleti yeni açılan masaüstüne geri getirir (geri alınabilir).
    func restoreGhost(_ id: String, desktop: Int, space: UInt64?, mode: Mode) {
        let live = live
        recording(L("Deleted desktop restored")) {
            document.restoreGhost(id, desktop: desktop, space: space, mode: mode, live: live)
            document.refreshNameCaches(live: live)
        }
    }

    /// Hayaleti pinleriyle birlikte tamamen siler (geri alınabilir).
    func discardGhost(_ id: String) {
        recording(L("Deleted desktop forgotten")) {
            document.discardGhost(id)
        }
    }

    /// Etkin olmayan modda masaüstü ekler: plan "" ile uzar (⌘Z geri alır).
    func planDesktop(on screen: String, mode: Mode, count: Int) {
        recording(L("Desktop added")) {
            document.planDesktop(on: screen, mode: mode, count: count)
        }
    }

    // MARK: - Profiller

    var profiles: [Profile] { document.profiles }

    var activeProfile: Profile? { document.activeProfile }

    /// Başka bir profile geçer; Router kural ve profil değişimini görüp
    /// planı uygular (silme yok) ve pencereleri yeniden yerleştirir.
    func switchProfile(to id: String) {
        mutate { $0.switchProfile(to: id) }
    }

    /// Profili ada göre ekler/günceller (bkz. `Document.upsertProfile`).
    func upsertProfile(_ profile: Profile, activate: Bool) {
        mutate { $0.upsertProfile(profile, activate: activate) }
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
    /// başarısızsa belge yayınlanmaz. Adlar yerleşmemiş gelir; canlı durum
    /// biliniyorsa plandaki yerlerine bağlanır (R4).
    @discardableResult
    func importProfile(from data: Data) throws -> Profile {
        var doc = document
        let profile = try doc.importProfile(from: data)
        if let live { doc.bindByPlan(live: live) }
        doc.refreshNameCaches(live: live)
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
