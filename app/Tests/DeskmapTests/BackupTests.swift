import Foundation
import Testing
@testable import Deskmap

/// Otomatik GFS yedeği: kova adları, budama, atomik yazım, geçersiz belge,
/// aynı içerik, geri yükleme. Gerçek Application Support'a hiç dokunmaz;
/// her test kendi geçici klasörünü kullanır.
struct BackupTests {

    private static let paris = TimeZone(identifier: "Europe/Paris")!
    private let schedule = BackupSchedule(timeZone: BackupTests.paris)

    /// Paris yerel saatiyle an.
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.paris
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func withArchive(_ body: (BackupArchive, URL) throws -> Void) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DeskmapBackupTests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try body(BackupArchive(sourceDirectory: root, schedule: schedule), root)
    }

    private func document(rules: Int, profile: String = "Work") -> Document {
        var doc = Document()
        doc.profiles[0].name = profile
        doc.rules = (0..<rules).map {
            Rule(id: "r\($0)", appName: "Code", bundleID: "com.microsoft.VSCode",
                 tokens: ["T\($0)"], docked: Destination(screen: "builtin", desktop: 1),
                 undocked: nil)
        }
        doc.syncActiveProfile()
        return doc
    }

    private func writeDocument(_ doc: Document, in dir: URL) throws {
        try Store.encode(doc).write(to: dir.appendingPathComponent("rules.json"))
    }

    // MARK: Kova adları

    @Test func stemsUseUTCHourLocalDayAndISOWeek() {
        let date = at(2026, 10, 12, 14, 30) // UTC 12:30
        #expect(schedule.stem(.hourly, at: date) == "hourly-20261012T12Z")
        #expect(schedule.stem(.daily, at: date) == "daily-2026-10-12")
        #expect(schedule.stem(.weekly, at: date) == "weekly-2026-W42")
        #expect(schedule.stem(.preRestore, at: date) == "pre-restore-20261012T123000Z")
    }

    /// Yerel gece yarısından hemen sonra: UTC hâlâ önceki gün, gün kovası yerel.
    @Test func dayBoundaryIsLocal() {
        let date = at(2026, 10, 13, 0, 30)
        #expect(schedule.stem(.daily, at: date) == "daily-2026-10-13")
        #expect(schedule.stem(.hourly, at: date) == "hourly-20261012T22Z")
        #expect(schedule.stem(.daily, at: at(2026, 10, 12, 23, 59)) == "daily-2026-10-12")
    }

    /// ISO haftası yıl sınırında: 31.12.2026 ve 01.01.2027 2026-W53'e,
    /// 04.01.2027 Pazartesi 2027-W01'e; 30.12.2024 Pazartesi 2025-W01'e ait.
    @Test func isoWeekAcrossYearBoundary() {
        #expect(schedule.stem(.weekly, at: at(2026, 12, 31)) == "weekly-2026-W53")
        #expect(schedule.stem(.weekly, at: at(2027, 1, 1)) == "weekly-2026-W53")
        #expect(schedule.stem(.weekly, at: at(2027, 1, 3, 23, 59)) == "weekly-2026-W53")
        #expect(schedule.stem(.weekly, at: at(2027, 1, 4, 0, 0)) == "weekly-2027-W01")
        #expect(schedule.stem(.weekly, at: at(2024, 12, 30)) == "weekly-2025-W01")
        // Pazar → Pazartesi geçişi hafta sınırı.
        #expect(schedule.stem(.weekly, at: at(2026, 10, 11, 23, 59)) == "weekly-2026-W41")
        #expect(schedule.stem(.weekly, at: at(2026, 10, 12, 0, 0)) == "weekly-2026-W42")
    }

    /// Kış saatine geçiş (25.10.2026, 03:00 → 02:00): yerel "02:30" iki kez
    /// yaşanır ama UTC saat kovaları ayrı kalır; gün kovası tek.
    @Test func dstFallBackKeepsHoursDistinct() {
        let first = utc(2026, 10, 25, 0, 30)  // yerel 02:30 CEST
        let second = utc(2026, 10, 25, 1, 30) // yerel 02:30 CET
        #expect(schedule.stem(.hourly, at: first) != schedule.stem(.hourly, at: second))
        #expect(schedule.stem(.daily, at: first) == schedule.stem(.daily, at: second))
    }

    @Test func parseRoundTripsAndRejectsForeignNames() {
        for date in [at(2026, 10, 12, 14), at(2026, 12, 31), at(2027, 1, 1), at(2026, 3, 29, 3)] {
            for tier in BackupTier.allCases {
                let stem = schedule.stem(tier, at: date)
                #expect(schedule.parse(stem)?.tier == tier, "\(stem)")
                if let start = schedule.parse(stem)?.start {
                    #expect(schedule.stem(tier, at: start) == stem, "\(stem)")
                }
            }
        }
        for bad in ["", "hourly-", "hourly-20261012T14", "hourly-20261312T14Z", "daily-2026-02-31",
                    "daily-2026-10-12x", "weekly-2026-W00", "weekly-2025-W53", "weekly-2026-41",
                    ".tmp-ABC-daily-2026-10-12", "notes", "daily-2026-10-12.json", "../daily-2026-10-12",
                    "hourly-2026101٢T14Z"] {
            #expect(schedule.parse(bad) == nil, "\(bad)")
        }
        #expect(schedule.parse("weekly-2026-W53")?.tier == .weekly)
    }

    // MARK: Budama

    @Test func hourlyKeepsLast24Hours() {
        let now = utc(2026, 10, 12, 14, 10)
        let stems = (0...30).map { schedule.stem(.hourly, at: now.addingTimeInterval(-Double($0) * 3600)) }
        let dropped = schedule.expired(stems, tier: .hourly, now: now)
        // 0…23 saat önce başlayan kovalar kalır; 24 ve daha eskiler gider.
        #expect(Set(dropped) == Set(stems[24...]))
        #expect(dropped == dropped.sorted())
    }

    @Test func dailyKeepsLast7CalendarDaysAcrossDST() {
        let now = at(2026, 10, 29, 0, 5) // kış saatine geçişten sonra
        let stems = (0...10).map { "daily-2026-10-\(String(format: "%02d", 29 - $0))" }
        let dropped = schedule.expired(stems, tier: .daily, now: now)
        #expect(Set(dropped) == Set(stems[7...]))
    }

    @Test func weeklyIsNeverPruned() {
        let stems = (1...52).map { String(format: "weekly-2020-W%02d", $0) }
        #expect(schedule.expired(stems, tier: .weekly, now: at(2030, 1, 1)).isEmpty)
    }

    /// Uzun süre kapalı kalan uygulama: tüm kovalar eski; en yenisi yine kalır.
    @Test func newestCopyIsNeverPruned() {
        let now = at(2027, 6, 1)
        let hourly = ["hourly-20261001T10Z", "hourly-20261001T11Z"]
        #expect(schedule.expired(hourly, tier: .hourly, now: now) == ["hourly-20261001T10Z"])
        let daily = ["daily-2026-10-01", "daily-2026-10-02"]
        #expect(schedule.expired(daily, tier: .daily, now: now) == ["daily-2026-10-01"])
    }

    /// Saat geri alındı: "gelecekteki" kovalar silinmez; başka katmanın ya da
    /// tanınmayan adlar hiç seçilmez.
    @Test func futureAndForeignNamesAreKept() {
        let now = utc(2026, 10, 12, 14)
        let stems = ["hourly-20261013T10Z", "hourly-20261012T14Z", "daily-2026-01-01", "readme"]
        #expect(schedule.expired(stems, tier: .hourly, now: now).isEmpty)
    }

    @Test func preRestoreKeepsNewestTen() {
        let now = utc(2026, 10, 12, 14)
        let stems = (0..<13).map { schedule.stem(.preRestore, at: now.addingTimeInterval(-Double($0) * 60)) }
        #expect(Set(schedule.expired(stems, tier: .preRestore, now: now)) == Set(stems[10...]))
    }

    // MARK: Disk

    @Test func runWritesAllTiersAndSkipsIdenticalContent() throws {
        try withArchive { archive, dir in
            try writeDocument(document(rules: 2), in: dir)
            try Data("[]".utf8).write(to: dir.appendingPathComponent("hooks.json"))
            let now = at(2026, 10, 12, 14)
            let first = archive.run(now: now)
            #expect(first.skipped == nil)
            #expect(first.written == ["hourly-20261012T12Z", "daily-2026-10-12", "weekly-2026-W42"])
            let bundle = try archive.read("daily-2026-10-12")
            #expect(bundle.files["hooks.json"] == "[]")
            #expect(bundle.files["desktop-spaces.json"] == nil)

            // Diske bakarak aynı içerik: yazılmaz (dosya tarihi değişmez).
            let url = archive.url(.daily, stem: "daily-2026-10-12")
            let stamp = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let second = archive.run(now: now.addingTimeInterval(600))
            #expect(second.written.isEmpty)
            #expect(second.unchanged.count == 3)
            #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == stamp)
            // Bellekteki durum aynı: diske hiç bakılmaz.
            let third = archive.run(now: now.addingTimeInterval(700), previous: second.state)
            #expect(third.written.isEmpty && third.state == second.state)
        }
    }

    /// Gün içinde değişen belge: günlük kova günün son hâlini tutar, yeni
    /// saat kovası açılır, haftalık da güncellenir.
    @Test func dailyAndWeeklyHoldLatestState() throws {
        try withArchive { archive, dir in
            try writeDocument(document(rules: 1), in: dir)
            _ = archive.run(now: at(2026, 10, 12, 9))
            try writeDocument(document(rules: 3), in: dir)
            let result = archive.run(now: at(2026, 10, 12, 15))
            #expect(result.written.count == 3)
            #expect(archive.stems(in: .hourly).count == 2)
            #expect(try archive.read("daily-2026-10-12").document().rules.count == 3)
            #expect(try archive.read("weekly-2026-W42").document().rules.count == 3)
        }
    }

    @Test func simulatedWeeksPruneHourlyAndDailyButKeepWeekly() throws {
        try withArchive { archive, dir in
            var now = at(2026, 12, 20, 0)
            for step in 0..<(24 * 21) { // üç hafta, saatte bir, her seferinde farklı belge
                try writeDocument(document(rules: step % 5 + 1, profile: "P\(step)"), in: dir)
                _ = archive.run(now: now)
                now = now.addingTimeInterval(3600)
            }
            #expect(archive.stems(in: .hourly).count == 24)
            #expect(archive.stems(in: .daily).count == 7)
            // 20.12.2026 (W51) … 09.01.2027 (2027-W01): W51, W52, W53, W01.
            #expect(archive.stems(in: .weekly).sorted()
                    == ["weekly-2026-W51", "weekly-2026-W52", "weekly-2026-W53", "weekly-2027-W01"])
        }
    }

    @Test func invalidDocumentsAreNeverBackedUp() throws {
        try withArchive { archive, dir in
            let now = at(2026, 10, 12)
            #expect(archive.run(now: now).skipped == .noDocument)

            try Data("{ broken".utf8).write(to: dir.appendingPathComponent("rules.json"))
            #expect(archive.run(now: now).skipped == .unreadable)

            var newer = document(rules: 1)
            newer.version = Document.currentVersion + 1
            try Store.encode(newer).write(to: dir.appendingPathComponent("rules.json"))
            // `version` alanı kodlamada currentVersion yazılabilir; elle yükselt.
            var json = try JSONSerialization.jsonObject(
                with: Data(contentsOf: dir.appendingPathComponent("rules.json"))) as! [String: Any]
            json["version"] = Document.currentVersion + 1
            try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("rules.json"))
            #expect(archive.run(now: now).skipped == .newerVersion)
            #expect(archive.stems(in: .daily).isEmpty)
        }
    }

    /// İyi yedek varken bozuk ya da boş belge onu ezmez, budama da çalışmaz.
    @Test func brokenOrEmptyNeverReplacesGoodBackup() throws {
        try withArchive { archive, dir in
            let now = at(2026, 10, 12, 10)
            try writeDocument(document(rules: 4), in: dir)
            _ = archive.run(now: now)
            try Data("{".utf8).write(to: dir.appendingPathComponent("rules.json"))
            _ = archive.run(now: now.addingTimeInterval(30 * 3600))
            #expect(archive.stems(in: .hourly) == ["hourly-20261012T08Z"])
            try writeDocument(document(rules: 0), in: dir)
            _ = archive.run(now: now.addingTimeInterval(60))
            #expect(try archive.read("daily-2026-10-12").document().rules.count == 4)
        }
    }

    @Test func pruningIgnoresUnknownFilesAndTemporaries() throws {
        try withArchive { archive, dir in
            let hourly = archive.directory(.hourly)
            try FileManager.default.createDirectory(at: hourly, withIntermediateDirectories: true)
            let foreign = ["notes.txt", "hourly-old.json", ".tmp-X-hourly-20200101T00Z.json",
                           "hourly-20200101T00Z.json.bak"]
            for name in foreign { try Data("x".utf8).write(to: hourly.appendingPathComponent(name)) }
            try writeDocument(document(rules: 1), in: dir)
            _ = archive.run(now: at(2026, 10, 12))
            let names = Set(try FileManager.default.contentsOfDirectory(atPath: hourly.path))
            // Yeni geçici dosya bir saatten genç: kalır. Yabancılar dokunulmaz.
            #expect(names.isSuperset(of: foreign))
            #expect(archive.list().count == 3)
        }
    }

    @Test func atomicWriteReplacesAndLeavesNoTemporary() throws {
        try withArchive { _, dir in
            let target = dir.appendingPathComponent("file.json")
            try Data("old".utf8).write(to: target)
            try BackupArchive.atomicWrite(Data("new".utf8), to: target)
            #expect(try String(contentsOf: target, encoding: .utf8) == "new")
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix(BackupArchive.tempPrefix) }
            #expect(leftovers.isEmpty)
            // Yazılamayan hedef: hata, eski dosya ve geçici dosya kalmaz.
            let missing = dir.appendingPathComponent("no/such/dir/file.json")
            #expect(throws: (any Error).self) { try BackupArchive.atomicWrite(Data(), to: missing) }
        }
    }

    @Test func readRejectsPathLikeIDs() throws {
        try withArchive { archive, _ in
            for id in ["../rules", "daily-2026-10-12/../../x", "", "daily-2026-10-12.json"] {
                #expect(throws: BackupError.invalidID) { try archive.read(id) }
            }
            #expect(throws: BackupError.notFound) { try archive.read("daily-2026-10-12") }
        }
    }

    // MARK: Geri yükleme

    @MainActor @Test func restoreRoundTrip() throws {
        try withArchive { archive, dir in
            var original = document(rules: 3, profile: "Office")
            original.addProfile(named: "Home")
            original.switchProfile(to: original.profiles[0].id)
            original.names = [DesktopName(id: "MAIL", name: "Mail", space: 5)]
            original.plans.put("MAIL", at: 1, .docked, "builtin")
            try writeDocument(original, in: dir)
            _ = archive.run(now: at(2026, 10, 12))

            let entry = try #require(archive.list().first { $0.tier == .weekly })
            #expect(entry.profiles.map(\.name) == ["Office", "Home"])
            #expect(entry.profiles.map(\.ruleCount) == [3, 0])
            #expect(entry.profiles.first?.isActive == true)

            let backup = try archive.read(entry.id).document()
            let store = Store(demo: document(rules: 0, profile: "Other"))
            store.document.enabled = false
            store.restoreBackup(backup)
            #expect(store.document.profiles.map(\.name) == ["Office", "Home"])
            #expect(store.document.rules.count == 3)
            #expect(store.document.names == backup.names && !backup.names.isEmpty)
            #expect(store.document.plans == backup.plans)
            #expect(store.document.enabled == false) // anahtar korunur
            #expect(store.history.canUndo)
            store.undo()
            #expect(store.document.profiles.map(\.name) == ["Other"])
        }
    }

    @Test func preRestoreSnapshotDoesNotOverwrite() throws {
        try withArchive { archive, dir in
            try writeDocument(document(rules: 1), in: dir)
            let now = at(2026, 10, 12)
            let data = try Store.encode(document(rules: 2))
            let a = try archive.writePreRestore(document: data, now: now)
            let b = try archive.writePreRestore(document: data, now: now)
            #expect(a != b)
            #expect(try archive.read(a).document().rules.count == 2)
            #expect(archive.stems(in: .preRestore).count == 2)
        }
    }

    /// Saat geri alınmışken: ileri tarihli 10 kopya varken yeni kopya
    /// hemen silinmez; toplam sınır korunur.
    @Test func preRestoreKeepsNewCopyWhenClockWentBack() throws {
        try withArchive { archive, dir in
            try writeDocument(document(rules: 1), in: dir)
            let data = try Store.encode(document(rules: 2))
            for i in 0..<BackupSchedule.preRestoreLimit {
                try archive.writePreRestore(document: data, now: at(2026, 10, 20, 12, i))
            }
            let stem = try archive.writePreRestore(document: data, now: at(2026, 10, 12))
            let stems = archive.stems(in: .preRestore)
            #expect(stems.contains(stem))
            #expect(stems.count == BackupSchedule.preRestoreLimit)
        }
    }

    /// Yeni sürümden gelen yedek geri yüklenmez, başarı bildirilmez.
    @MainActor @Test func restoreBackupReportsFailure() {
        let store = Store(demo: document(rules: 1))
        var newer = document(rules: 2)
        newer.fileVersion = Document.currentVersion + 1
        #expect(newer.isFromNewerVersion)
        let rejected = store.restoreBackup(newer)
        #expect(!rejected)
        let accepted = store.restoreBackup(document(rules: 3))
        #expect(accepted)
    }

    /// `reload()` yaşam süresi: kuyruk işi servisi güçlü tutar (liste okunur),
    /// ana iş parçacığına dönüş zayıf; servis bırakılınca serbest kalır.
    @MainActor @Test func reloadPublishesEntriesAndReleasesService() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DeskmapBackupTests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let archive = BackupArchive(sourceDirectory: root, schedule: schedule)
        try writeDocument(document(rules: 1), in: root)
        _ = archive.run(now: at(2026, 10, 12))
        #expect(!archive.list().isEmpty)

        var service: BackupService? = BackupService(archive: archive)
        weak let weakService = service
        service?.reload()
        for _ in 0..<200 where service?.entries.isEmpty == true {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(service?.entries.count == archive.list().count)

        service = nil
        for _ in 0..<200 where weakService != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(weakService == nil)
    }

    @Test func urlCommandsParse() {
        #expect(URLCommand.parse(URL(string: "deskmap://backup-now")!) == .backupNow)
        #expect(URLCommand.parse(URL(string: "deskmap://backup-restore/daily-2026-10-12")!)
                == .restoreBackup(id: "daily-2026-10-12"))
        #expect(URLCommand.parse(URL(string: "deskmap://backup-restore")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://backup-now/x")!) == nil)
    }
}
