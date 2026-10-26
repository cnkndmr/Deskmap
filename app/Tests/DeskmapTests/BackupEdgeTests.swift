import Foundation
import Testing
@testable import Deskmap

/// Yedekleme kenar durumları: kova adı sınırları, budama eşikleri, bozuk
/// ve eksik dosyalar, yazım hataları, geri yükleme servisi. Her test kendi
/// geçici klasörünü kullanır; gerçek Application Support'a dokunmaz.
struct BackupEdgeTests {

    private static let paris = TimeZone(identifier: "Europe/Paris")!
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let schedule = BackupSchedule(timeZone: BackupEdgeTests.paris)

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    private func withArchive(_ body: (BackupArchive, URL) throws -> Void) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DeskmapBackupEdge-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try body(BackupArchive(sourceDirectory: root, schedule: schedule), root)
    }

    private func document(rules: Int, extraProfileRules: Int? = nil) -> Document {
        var doc = Document()
        doc.rules = (0..<rules).map {
            Rule(id: "r\($0)", appName: "Code", bundleID: "b.code", tokens: ["T\($0)"],
                 docked: Destination(screen: "builtin", desktop: 1), undocked: nil)
        }
        doc.syncActiveProfile()
        if let extra = extraProfileRules {
            doc.addProfile(named: "Second", activate: true)
            doc.rules = (0..<extra).map {
                Rule(id: "x\($0)", appName: "Mail", bundleID: "b.mail", tokens: ["M\($0)"],
                     docked: Destination(screen: "builtin", desktop: 2), undocked: nil)
            }
            doc.syncActiveProfile()
        }
        return doc
    }

    private func write(_ doc: Document, in dir: URL) throws {
        try Store.encode(doc).write(to: dir.appendingPathComponent("rules.json"))
    }

    // MARK: - Kova adları

    @Test func hourlyStemUsesUTCForHalfHourOffsetZones() {
        let kolkata = BackupSchedule(timeZone: Self.kolkata)
        // 01:00 yerel (UTC+5:30) = önceki gün 19:30 UTC.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.kolkata
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1))!
        #expect(kolkata.stem(.hourly, at: date) == "hourly-20251231T19Z")
        #expect(kolkata.stem(.daily, at: date) == "daily-2026-01-01")
        #expect(kolkata.stem(.weekly, at: date) == "weekly-2026-W01")
    }

    @Test func dailyStemCrossesTheDateLineDifferentlyThanUTC() {
        let tokyo = BackupSchedule(timeZone: Self.tokyo)
        let date = utc(2026, 12, 31, 20, 0) // Tokyo: 1 Ocak 05:00
        #expect(tokyo.stem(.daily, at: date) == "daily-2027-01-01")
        #expect(tokyo.stem(.weekly, at: date) == "weekly-2026-W53")
        #expect(tokyo.stem(.hourly, at: date) == "hourly-20261231T20Z")
    }

    @Test func parseRejectsOverflowingAndNonASCIIComponents() {
        for bad in ["hourly-20261012T24Z", "hourly-20260012T10Z", "hourly-20261032T10Z",
                    "daily-2026-13-01", "daily-2026-00-10", "daily-2026-04-31", "daily-2026-1-12",
                    "pre-restore-20261012T240000Z", "pre-restore-20261012T126000Z",
                    "pre-restore-20261012T121260Z", "pre-restore-20261012T1212Z",
                    "weekly-2026-W54", "weekly-2026-W5", "weekly-20260-W41",
                    "Hourly-20261012T14Z", "daily-2026-10-12 ", " daily-2026-10-12",
                    "daily-２０２６-10-12"] {
            #expect(schedule.parse(bad) == nil, "\(bad)")
        }
    }

    @Test func parseAcceptsLeapDayButNotInNonLeapYears() {
        #expect(schedule.parse("daily-2028-02-29")?.tier == .daily)
        #expect(schedule.parse("daily-2027-02-29") == nil)
        #expect(schedule.parse("hourly-20280229T23Z")?.tier == .hourly)
    }

    @Test func parsedStartsAreBucketStarts() {
        #expect(schedule.parse("hourly-20261012T14Z")?.start == utc(2026, 10, 12, 14))
        #expect(schedule.parse("pre-restore-20261012T143005Z")?.start == utc(2026, 10, 12, 14, 30, 5))
        // Haftanın başlangıcı yerel Pazartesi 00:00 (Paris).
        let week = schedule.parse("weekly-2026-W42")?.start
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.paris
        #expect(week == calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
    }

    // MARK: - Budama eşikleri

    @Test func hourlyThresholdIsExactlyTwentyFourHours() {
        let now = utc(2026, 10, 12, 14, 59, 59)
        let fresh = "hourly-20261012T14Z"
        let edgeKept = "hourly-20261011T15Z"   // 23 sa 59 dk 59 sn önce başladı
        let edgeDropped = "hourly-20261011T14Z" // tam 24 sa 59 dk önce
        #expect(schedule.expired([fresh, edgeKept, edgeDropped], tier: .hourly, now: now) == [edgeDropped])
        let onTheHour = utc(2026, 10, 12, 14)
        #expect(schedule.expired([fresh, "hourly-20261011T14Z"], tier: .hourly, now: onTheHour)
                == ["hourly-20261011T14Z"]) // tam 24 sa: gider
        #expect(schedule.expired([fresh, "hourly-20261011T15Z"], tier: .hourly, now: onTheHour).isEmpty)
    }

    @Test func dailyThresholdIsSevenCalendarDaysBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.paris
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 59))!
        let stems = ["daily-2026-10-12", "daily-2026-10-06", "daily-2026-10-05", "daily-2026-09-01"]
        #expect(schedule.expired(stems, tier: .daily, now: now) == ["daily-2026-09-01", "daily-2026-10-05"])
    }

    @Test func expiredSortsByStartAndDropsOnlyItsOwnTier() {
        let now = utc(2027, 1, 1)
        let mixed = ["daily-2026-01-01", "hourly-20260101T00Z", "hourly-20260101T01Z", "weekly-2020-W01",
                     "pre-restore-20260101T000000Z", "junk"]
        #expect(schedule.expired(mixed, tier: .hourly, now: now) == ["hourly-20260101T00Z"])
        #expect(schedule.expired(mixed, tier: .daily, now: now).isEmpty) // tek günlük = en yeni
        #expect(schedule.expired([], tier: .hourly, now: now).isEmpty)
    }

    @Test func expiredWithDuplicateAndEquallyDatedStemsIsStable() {
        let now = utc(2027, 1, 1)
        let stems = ["hourly-20260101T00Z", "hourly-20260101T00Z", "hourly-20260101T01Z"]
        let dropped = schedule.expired(stems, tier: .hourly, now: now)
        #expect(dropped == ["hourly-20260101T00Z", "hourly-20260101T00Z"])
    }

    @Test func preRestoreKeepParameterBoundaries() {
        let now = utc(2026, 10, 12, 14)
        let stems = (0..<5).map { schedule.stem(.preRestore, at: now.addingTimeInterval(-Double($0) * 60)) }
        #expect(schedule.expired(stems, tier: .preRestore, now: now, keep: 5).isEmpty)
        #expect(schedule.expired(stems, tier: .preRestore, now: now, keep: 1) == Array(stems[1...]).sorted())
        #expect(schedule.expired(stems, tier: .preRestore, now: now, keep: 0).count == 5)
        #expect(schedule.expired(stems, tier: .preRestore, now: now, keep: -3).count == 5) // negatif = 0
        #expect(schedule.expired(stems, tier: .preRestore, now: now, keep: 99).isEmpty)
    }

    // MARK: - Paket (bundle)

    @Test func bundleValidityRules() {
        let ok = BackupBundle(created: utc(2026, 10, 12), files: ["rules.json": "{}"])
        #expect(ok.isValid)
        var other = ok
        other.kind = "something-else"
        #expect(!other.isValid)
        other = ok
        other.format = BackupBundle.currentFormat + 1
        #expect(!other.isValid)
        other = ok
        other.files = ["hooks.json": "[]"]
        #expect(!other.isValid)
        other.format = 0
        other.files = ["rules.json": ""]
        #expect(other.isValid) // eski biçim numarası ve boş metin geçerli paket; belge ayrıca doğrulanır
    }

    @Test func bundleRoundTripKeepsUnicodeAndSecondPrecisionDates() throws {
        let created = utc(2026, 10, 12, 14, 30, 5).addingTimeInterval(0.75)
        let bundle = BackupBundle(created: created, files: [
            "rules.json": "{\"x\":\"Ünal 日本語 🚀 \\\"q\\\"\"}\n", "hooks.json": "[\n]"])
        let back = try BackupBundle.decode(bundle.encoded())
        #expect(back.files == bundle.files)
        #expect(abs(back.created.timeIntervalSince(created)) < 1) // iso8601: saniye duyarlılığı
        #expect(throws: (any Error).self) { try BackupBundle.decode(Data("nope".utf8)) }
        #expect(throws: (any Error).self) { try BackupBundle.decode(Data("{}".utf8)) }
    }

    @Test func bundleDocumentErrorsAreTyped() throws {
        let missing = BackupBundle(created: Date(), files: ["rules.json": "{ broken"])
        #expect(throws: BackupError.unreadable) { try missing.document() }
        let none = BackupBundle(created: Date(), files: ["hooks.json": "[]"])
        #expect(throws: BackupError.unreadable) { try none.document() }
        // `version` alanını yeni sürüme çevirerek yaz.
        let text = String(decoding: try Store.encode(document(rules: 1)), as: UTF8.self)
            .replacingOccurrences(of: "\"version\" : \(Document.currentVersion)",
                                  with: "\"version\" : \(Document.currentVersion + 1)")
        #expect(throws: BackupError.newerVersion) {
            try BackupBundle(created: Date(), files: ["rules.json": text]).document()
        }
        let dropped = #"{"version":6,"rules":[{"appName":"A","bundleID":"b","tokens":[]}, 7]}"#
        #expect(throws: BackupError.unreadable) {
            try BackupBundle(created: Date(), files: ["rules.json": dropped]).document()
        }
    }

    @Test func errorDescriptionsAreUserReadable() {
        for error in [BackupError.noDocument, .unreadable, .newerVersion, .notFound, .invalidID] {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(BackupError.notFound.errorDescription == BackupError.invalidID.errorDescription)
        #expect(BackupError.noDocument.errorDescription != BackupError.unreadable.errorDescription)
    }

    // MARK: - Anlık görüntü ve çalışma

    @Test func snapshotIncludesOptionalFilesOnlyWhenTheyAreUTF8() throws {
        try withArchive { archive, dir in
            try write(document(rules: 1), in: dir)
            try Data([0xFF, 0xFE, 0x00]).write(to: dir.appendingPathComponent("hooks.json"))
            try Data("{\"spaces\":[]}".utf8).write(to: dir.appendingPathComponent("desktop-spaces.json"))
            let files = try archive.snapshot()
            #expect(Set(files.keys) == ["rules.json", "desktop-spaces.json"])
        }
    }

    @Test func snapshotErrorsAreTyped() throws {
        try withArchive { archive, dir in
            #expect(throws: BackupError.noDocument) { try archive.snapshot() }
            try Data("{ not json".utf8).write(to: dir.appendingPathComponent("rules.json"))
            #expect(throws: BackupError.unreadable) { try archive.snapshot() }
            try Data([0xFF, 0xFE, 0xFD]).write(to: dir.appendingPathComponent("rules.json"))
            #expect(throws: BackupError.unreadable) { try archive.snapshot() }
            try Data("[1,2]".utf8).write(to: dir.appendingPathComponent("rules.json"))
            #expect(throws: BackupError.unreadable) { try archive.snapshot() }
        }
    }

    @Test func runReportsSkipReasonAndWritesNothingWhenDocumentIsMissingOrBroken() throws {
        try withArchive { archive, dir in
            let missing = archive.run(now: utc(2026, 10, 12, 14))
            #expect(missing.skipped == .noDocument && missing.written.isEmpty && missing.state == nil)
            try Data("{ x".utf8).write(to: dir.appendingPathComponent("rules.json"))
            let broken = archive.run(now: utc(2026, 10, 12, 14))
            #expect(broken.skipped == .unreadable)
            #expect(!FileManager.default.fileExists(atPath: archive.root.path))
        }
    }

    @Test func runWithMatchingPreviousStateDoesNotTouchTheDisk() throws {
        try withArchive { archive, dir in
            try write(document(rules: 2), in: dir)
            let now = utc(2026, 10, 12, 14)
            let first = archive.run(now: now)
            #expect(first.written.count == 3)
            let hourly = archive.url(.hourly, stem: archive.schedule.stem(.hourly, at: now))
            try FileManager.default.removeItem(at: hourly)
            // Aynı durum: disk yoklanmaz, silinen dosya geri yazılmaz.
            let second = archive.run(now: now.addingTimeInterval(60), previous: first.state)
            #expect(second.written.isEmpty && second.unchanged.count == 3)
            #expect(!FileManager.default.fileExists(atPath: hourly.path))
            // Durum yok: yeniden yoklar ve eksik kovayı yazar.
            let third = archive.run(now: now.addingTimeInterval(60))
            #expect(third.written == [archive.schedule.stem(.hourly, at: now)])
        }
    }

    @Test func newBucketGetsEmptyDocumentButSameBucketKeepsTheGoodOne() throws {
        try withArchive { archive, dir in
            try write(document(rules: 3), in: dir)
            _ = archive.run(now: utc(2026, 10, 12, 14))
            try write(document(rules: 0), in: dir)
            let sameHour = archive.run(now: utc(2026, 10, 12, 14, 40))
            #expect(sameHour.written.isEmpty)
            let stem = archive.schedule.stem(.hourly, at: utc(2026, 10, 12, 14))
            #expect(try archive.read(stem).document().rules.count == 3)
            let nextHour = archive.run(now: utc(2026, 10, 12, 15))
            #expect(nextHour.written.contains(archive.schedule.stem(.hourly, at: utc(2026, 10, 12, 15))))
            let newStem = archive.schedule.stem(.hourly, at: utc(2026, 10, 12, 15))
            #expect(try archive.read(newStem).document().rules.isEmpty)
        }
    }

    @Test func ruleCountTakesTheLargerOfProfilesAndTopLevel() throws {
        let multi = document(rules: 1, extraProfileRules: 4)
        let text = String(decoding: try Store.encode(multi), as: UTF8.self)
        // Bütün profillerin toplamı (1 + 4); üst düzey (etkin profil) 4 kural.
        #expect(BackupArchive.ruleCount(["rules.json": text]) == 5)
        #expect(BackupArchive.ruleCount([:]) == 0)
        #expect(BackupArchive.ruleCount(["rules.json": "garbage"]) == 0)
        #expect(BackupArchive.ruleCount(["hooks.json": "[]"]) == 0)
    }

    @Test func aBlockedTierSkipsPruningAndDropsTheState() throws {
        try withArchive { archive, dir in
            try write(document(rules: 1), in: dir)
            let long = utc(2026, 10, 1, 10)
            // Eski saatlik kopyalar (budanması gereken) hazırla.
            for hour in 0..<3 {
                let stem = archive.schedule.stem(.hourly, at: long.addingTimeInterval(Double(hour) * 3600))
                try archive.write(BackupBundle(created: long, files: ["rules.json": "{}"]),
                                  to: archive.url(.hourly, stem: stem))
            }
            // Haftalık klasörün yeri bir dosya: yazım başarısız.
            try Data("x".utf8).write(to: archive.root.appendingPathComponent("weekly"))
            let result = archive.run(now: utc(2026, 10, 12, 14))
            #expect(result.written.count == 2) // hourly + daily
            #expect(result.pruned.isEmpty && result.state == nil)
            #expect(archive.stems(in: .hourly).count == 4) // hiçbiri silinmedi
        }
    }

    @Test func pruneRemovesOnlyExpiredFilesOfHourlyAndDailyTiers() throws {
        try withArchive { archive, dir in
            try write(document(rules: 1), in: dir)
            let now = utc(2026, 10, 20, 12)
            for age in [0, 5, 23, 24, 48, 200] {
                let date = now.addingTimeInterval(-Double(age) * 3600)
                try archive.write(BackupBundle(created: date, files: ["rules.json": "{}"]),
                                  to: archive.url(.hourly, stem: archive.schedule.stem(.hourly, at: date)))
            }
            let weekly = archive.schedule.stem(.weekly, at: utc(2020, 1, 1))
            try archive.write(BackupBundle(created: now, files: ["rules.json": "{}"]),
                              to: archive.url(.weekly, stem: weekly))
            let removed = archive.prune(now: now)
            #expect(removed.count == 3) // 24, 48, 200 saat
            #expect(archive.stems(in: .hourly).count == 3)
            #expect(archive.stems(in: .weekly) == [weekly])
        }
    }

    @Test func stemsAndListIgnoreMisplacedAndCorruptFiles() throws {
        try withArchive { archive, dir in
            try write(document(rules: 2), in: dir)
            _ = archive.run(now: utc(2026, 10, 12, 14))
            let hourlyDir = archive.directory(.hourly)
            // Başka katmanın adı yanlış klasörde, uzantısız ve geçici dosya.
            try Data("{}".utf8).write(to: hourlyDir.appendingPathComponent("daily-2026-10-12.json"))
            try Data("{}".utf8).write(to: hourlyDir.appendingPathComponent("hourly-20261012T10Z"))
            try Data("{}".utf8).write(to: hourlyDir.appendingPathComponent(".tmp-ABC-hourly-20261012T10Z.json"))
            try Data("garbage".utf8).write(to: hourlyDir.appendingPathComponent("hourly-20261012T09Z.json"))
            #expect(archive.stems(in: .hourly).sorted() == ["hourly-20261012T09Z", "hourly-20261012T14Z"])
            let ids = archive.list().map(\.id)
            #expect(ids.contains("hourly-20261012T14Z") && !ids.contains("hourly-20261012T09Z"))
            #expect(archive.list().count == 3) // hourly + daily + weekly
        }
    }

    @Test func listSortsNewestFirstAndSummarisesProfiles() throws {
        try withArchive { archive, dir in
            let early = utc(2026, 10, 12, 8)
            let late = utc(2026, 10, 12, 16)
            try write(document(rules: 1, extraProfileRules: 3), in: dir)
            _ = archive.run(now: early)
            _ = archive.run(now: late)
            let entries = archive.list()
            #expect(entries.map(\.created) == entries.map(\.created).sorted(by: >))
            let newest = try #require(entries.first)
            #expect(newest.created == late)
            #expect(newest.profiles.count == 2)
            #expect(newest.profiles.filter(\.isActive).count == 1)
            #expect(newest.profiles.first(where: \.isActive)?.ruleCount == 3)
        }
    }

    @Test func readRejectsEveryNonBucketID() throws {
        try withArchive { archive, dir in
            try write(document(rules: 1), in: dir)
            _ = archive.run(now: utc(2026, 10, 12, 14))
            for bad in ["", "..", "../rules", "hourly-20261012T14Z/../../rules",
                        "hourly-20261012T14Z.json", "hourly-20261012T14Z\0", "/etc/passwd"] {
                #expect(throws: BackupError.invalidID, "\(bad)") { try archive.read(bad) }
            }
            #expect(throws: BackupError.notFound) { try archive.read("hourly-20200101T00Z") }
            let url = archive.url(.hourly, stem: "hourly-20261012T14Z")
            try Data("{\"kind\":\"other\",\"format\":1,\"created\":\"2026-10-12T14:00:00Z\",\"files\":{\"rules.json\":\"{}\"}}".utf8).write(to: url)
            #expect(throws: BackupError.unreadable) { try archive.read("hourly-20261012T14Z") }
            try Data("junk".utf8).write(to: url)
            #expect(throws: BackupError.unreadable) { try archive.read("hourly-20261012T14Z") }
        }
    }

    // MARK: - Geri yükleme öncesi kopya

    @Test func preRestoreWorksWithoutAnyRulesFileOnDiskAndRejectsNonUTF8() throws {
        try withArchive { archive, _ in
            let data = try Store.encode(document(rules: 2))
            let stem = try archive.writePreRestore(document: data, now: utc(2026, 10, 12, 14))
            #expect(try archive.read(stem).document().rules.count == 2)
            #expect(throws: BackupError.unreadable) {
                try archive.writePreRestore(document: Data([0xFF, 0xFE]), now: utc(2026, 10, 12, 15))
            }
            #expect(archive.stems(in: .preRestore) == [stem]) // başarısız yazım iz bırakmadı
        }
    }

    @Test func preRestoreSameSecondWritesNeverClobberAndLimitHolds() throws {
        try withArchive { archive, _ in
            let data = try Store.encode(document(rules: 1))
            let now = utc(2026, 10, 12, 14)
            var stems: [String] = []
            for _ in 0..<14 {
                let stem = try archive.writePreRestore(document: data, now: now)
                // Her yeni kopya yazıldığı anda sağ kalır ve öncekini ezmez.
                #expect(archive.stems(in: .preRestore).contains(stem))
                stems.append(stem)
            }
            #expect(Set(stems.prefix(BackupSchedule.preRestoreLimit)).count == BackupSchedule.preRestoreLimit)
            let kept = archive.stems(in: .preRestore)
            #expect(kept.count == BackupSchedule.preRestoreLimit)
            #expect(kept.contains(stems.last!)) // en yeni asla budanmaz
        }
    }

    @Test func preRestoreCarriesTheOtherFilesFromDiskButTheGivenDocument() throws {
        try withArchive { archive, dir in
            try write(document(rules: 1), in: dir)
            try Data("[\"hook\"]".utf8).write(to: dir.appendingPathComponent("hooks.json"))
            let memory = try Store.encode(document(rules: 5))
            let stem = try archive.writePreRestore(document: memory, now: utc(2026, 10, 12, 14))
            let bundle = try archive.read(stem)
            #expect(bundle.files["hooks.json"] == "[\"hook\"]")
            #expect(try bundle.document().rules.count == 5)
        }
    }

    // MARK: - Dosya yazımı

    @Test func atomicWriteOverwritesAndFailsCleanlyWithoutDirectory() throws {
        try withArchive { _, dir in
            let target = dir.appendingPathComponent("x.json")
            try BackupArchive.atomicWrite(Data("one".utf8), to: target)
            try BackupArchive.atomicWrite(Data("two".utf8), to: target)
            #expect(try String(contentsOf: target, encoding: .utf8) == "two")
            let missing = dir.appendingPathComponent("no/such/dir/x.json")
            #expect(throws: (any Error).self) { try BackupArchive.atomicWrite(Data("x".utf8), to: missing) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["x.json"])
        }
    }

    @Test func atomicWriteOntoADirectoryFailsAndLeavesNoTemporary() throws {
        try withArchive { _, dir in
            let target = dir.appendingPathComponent("occupied.json", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try BackupArchive.atomicWrite(Data("x".utf8), to: target) }
            let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(left == ["occupied.json"])
        }
    }

    @Test func staleTemporariesGoButFreshOnesAndForeignFilesStay() throws {
        try withArchive { archive, _ in
            let fm = FileManager.default
            let dir = archive.directory(.daily)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let now = utc(2026, 10, 12, 14)
            func make(_ name: String, age: TimeInterval) throws {
                let url = dir.appendingPathComponent(name)
                try Data("x".utf8).write(to: url)
                try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
            }
            try make(".tmp-old-daily-2026-10-12.json", age: 3601)
            try make(".tmp-edge-daily-2026-10-12.json", age: 3600)
            try make(".tmp-fresh-daily-2026-10-12.json", age: 10)
            try make("notes.txt", age: 99_999)
            archive.removeStaleTemporaries(now: now)
            let names = Set(try fm.contentsOfDirectory(atPath: dir.path))
            #expect(names == [".tmp-edge-daily-2026-10-12.json", ".tmp-fresh-daily-2026-10-12.json", "notes.txt"])
        }
    }

    @Test func writeCreatesMissingDirectories() throws {
        try withArchive { archive, _ in
            let url = archive.url(.preRestore, stem: "pre-restore-20261012T140000Z")
            try archive.write(BackupBundle(created: Date(), files: ["rules.json": "{}"]), to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func archiveDefaultsRootToBackupsInsideTheSourceDirectory() {
        let source = URL(fileURLWithPath: "/tmp/deskmap-fake-source", isDirectory: true)
        let archive = BackupArchive(sourceDirectory: source)
        #expect(archive.root.lastPathComponent == "Backups")
        #expect(archive.directory(.preRestore).lastPathComponent == "pre-restore")
        #expect(archive.url(.weekly, stem: "weekly-2026-W41").lastPathComponent == "weekly-2026-W41.json")
    }
}

/// `BackupService`: Store ve geçici klasörle (Router yok). Zamanlayıcı ve
/// sistem bildirimleri (`start()`) kurulmaz.
@MainActor
struct BackupServiceTests {

    private func withService(_ body: (BackupService, URL, Store) async throws -> Void) async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("DeskmapBackupService-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        var doc = Document()
        doc.rules = [Rule(id: "disk", appName: "Code", bundleID: "b", tokens: ["d"],
                          docked: Destination(screen: "builtin"), undocked: nil)]
        doc.syncActiveProfile()
        try Store.encode(doc).write(to: dir.appendingPathComponent("rules.json"))
        let service = BackupService(archive: BackupArchive(sourceDirectory: dir))
        try await body(service, dir, Store(demo: doc))
    }

    @Test func runNowWritesThreeTiersThenReportsUnchanged() async throws {
        try await withService { service, _, _ in
            let first = service.runNow()
            #expect(first.written.count == 3 && first.skipped == nil)
            let second = service.runNow()
            #expect(second.written.isEmpty && second.unchanged.count == 3)
        }
    }

    @Test func runNowWithoutADocumentIsSkippedNotCrashed() async throws {
        try await withService { service, dir, _ in
            try FileManager.default.removeItem(at: dir.appendingPathComponent("rules.json"))
            #expect(service.runNow().skipped == .noDocument)
        }
    }

    @Test func runInBackgroundEventuallyWritesAndStampsLastRun() async throws {
        try await withService { service, _, _ in
            #expect(service.lastRun == nil)
            service.runInBackground()
            for _ in 0..<200 where service.lastRun == nil { try await Task.sleep(nanoseconds: 25_000_000) }
            #expect(service.lastRun != nil)
            #expect(service.archive.stems(in: .hourly).count == 1)
        }
    }

    @Test func restoreAppliesTheBackupSavesPreRestoreCopyAndRewritesHooks() async throws {
        try await withService { service, dir, store in
            try Data("[\"old-hooks\"]".utf8).write(to: dir.appendingPathComponent("hooks.json"))
            let result = service.runNow()
            let id = try #require(result.written.first { $0.hasPrefix("daily-") })
            // Sonradan: bellekte başka kural, hooks.json değişti.
            store.document.rules = []
            store.document.syncActiveProfile()
            try Data("[\"new-hooks\"]".utf8).write(to: dir.appendingPathComponent("hooks.json"))
            #expect(service.restore(id, store: store, router: nil))
            #expect(store.document.rules.map(\.id) == ["disk"])
            #expect(try String(contentsOf: dir.appendingPathComponent("hooks.json"), encoding: .utf8) == "[\"old-hooks\"]")
            let pre = service.archive.stems(in: .preRestore)
            #expect(pre.count == 1)
            #expect(try service.archive.read(pre[0]).document().rules.isEmpty) // bellekteki hâl yedeklendi
            store.undo()
            #expect(store.document.rules.isEmpty)
        }
    }

    @Test func restoreOfAnUnknownOrBrokenIDReportsAndChangesNothing() async throws {
        try await withService { service, _, store in
            let before = store.document
            #expect(!service.restore("daily-2001-01-01", store: store, router: nil))
            #expect(store.lastError?.hasPrefix(L("Could not restore backup: %@", "")) == true
                    || store.lastError?.contains(L("Backup not found")) == true)
            #expect(!service.restore("../../etc/passwd", store: store, router: nil))
            #expect(store.document == before)
            #expect(service.archive.stems(in: .preRestore).isEmpty)
        }
    }

    @Test func restoreIsRefusedWhileTheSessionIsReadOnly() async throws {
        try await withService { service, _, store in
            let id = try #require(service.runNow().written.first)
            var future = store.document
            future.fileVersion = Document.currentVersion + 1
            store.document = future
            #expect(store.isReadOnly)
            #expect(!service.restore(id, store: store, router: nil))
            #expect(store.lastError == Store.newerVersionMessage)
            #expect(service.archive.stems(in: .preRestore).isEmpty)
        }
    }
}
