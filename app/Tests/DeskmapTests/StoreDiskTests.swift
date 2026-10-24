import Foundation
import Testing
@testable import Deskmap

/// `Store()` gerçek yükleme/kaydetme yolu. Testlerde `Store.directoryURL`
/// süreç başına geçici klasördür (`Log.isTesting`); `DESKMAP_DATA_DIR`
/// başka yeri gösteriyorsa hiçbir test çalışmaz. Paylaşılan tek klasör
/// olduğu için paket sıralıdır; her test kendi dosyalarını baştan ve sondan siler.
@MainActor
@Suite(.serialized)
struct StoreDiskTests {

    /// Yalnız bu sürecin geçici klasörü altındaki veri klasörü.
    private func prepared() throws -> URL {
        let dir = Store.directoryURL
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        try #require(dir.resolvingSymlinksInPath().path.hasPrefix(temp), "refusing to touch \(dir.path)")
        try #require(dir.path.contains("DeskmapTests-"), "refusing to touch \(dir.path)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cleanUp()
        return dir
    }

    /// Yalnız bu paketin dosyaları: klasörün kendisi Router testleriyle paylaşılır
    /// (session-pins.json, desktop-spaces.json), onu silmek onları bozardı.
    private func cleanUp() {
        let dir = Store.directoryURL
        for name in ["rules.json", "rules.json.bak", "Backups"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func rule(_ id: String, desktop: Int = 1) -> Rule {
        Rule(id: id, appName: "App-\(id)", bundleID: "b.\(id)", tokens: [id],
             docked: Destination(screen: "external", desktop: desktop), undocked: nil)
    }

    private static let v5Json = """
        {"version":5,"enabled":true,"rules":[
          {"id":"old","appName":"Mail","bundleID":"b.mail","tokens":["inbox"],
           "docked":{"screen":"builtin","desktop":2}}]}
        """

    @Test func missingFileLeavesDefaultsAndNoError() throws {
        _ = try prepared()
        defer { cleanUp() }
        let store = Store()
        #expect(store.document.rules.isEmpty && store.lastError == nil)
        #expect(!store.isReadOnly && !store.migrationPending)
    }

    @Test func flushWritesExactEncodingAndReloadReadsItBack() throws {
        _ = try prepared()
        defer { cleanUp() }
        let store = Store()
        store.add(rule("a", desktop: 3))
        #expect(store.flush())
        let onDisk = try Data(contentsOf: Store.fileURL)
        let reread = try JSONDecoder().decode(Document.self, from: onDisk)
        #expect(reread.rules.map(\.id) == ["a"] && reread.rules.first?.docked?.desktop == 3)
        #expect(reread.profiles.first?.rules.map(\.id) == ["a"]) // profil kopyası eşitlendi
        let second = Store()
        #expect(second.document.rules.map(\.id) == ["a"])
        #expect(second.lastError == nil)
        #expect(!second.history.canUndo) // açılış durumu geçmişin tabanı
    }

    @Test func unwritablePathReportsAnErrorAndClearsItOnNextSuccess() throws {
        let dir = try prepared()
        defer { cleanUp() }
        let store = Store()
        // rules.json yolu bir klasör: atomik yazım başarısız olur.
        try FileManager.default.createDirectory(at: Store.fileURL, withIntermediateDirectories: true)
        #expect(!store.flush())
        #expect(store.lastError?.contains("rules.json") == true)
        try FileManager.default.removeItem(at: Store.fileURL)
        #expect(store.flush())
        #expect(store.lastError == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("rules.json").path))
    }

    @Test func corruptFileIsCopiedToBakBeforeAnyOverwrite() throws {
        _ = try prepared()
        defer { cleanUp() }
        try Data("{ this is not json".utf8).write(to: Store.fileURL)
        let store = Store()
        #expect(store.lastError?.contains("rules.json.bak") == true)
        #expect(try String(contentsOf: Store.backupURL, encoding: .utf8) == "{ this is not json")
        #expect(store.document.rules.isEmpty)
        #expect(store.flush()) // bozuk dosyanın üstüne yazılır; yedek durur
        #expect(try String(contentsOf: Store.backupURL, encoding: .utf8) == "{ this is not json")
        #expect((try? JSONDecoder().decode(Document.self, from: Data(contentsOf: Store.fileURL))) != nil)
    }

    @Test func unreadableRulesAreCountedAndBackedUpNotSilentlyLost() throws {
        _ = try prepared()
        defer { cleanUp() }
        let json = """
            {"version":6,"rules":[{"id":"ok","appName":"A","bundleID":"b","tokens":[],"docked":{"screen":"builtin"}}, 5, "x"]}
            """
        try Data(json.utf8).write(to: Store.fileURL)
        let store = Store()
        #expect(store.document.rules.map(\.id) == ["ok"])
        #expect(store.document.droppedRuleCount == 2)
        #expect(store.lastError?.contains("2") == true && store.lastError?.contains("backup") == true)
        #expect(try String(contentsOf: Store.backupURL, encoding: .utf8) == json)
    }

    @Test func newerVersionFileIsReadOnlyAndNeverOverwritten() throws {
        _ = try prepared()
        defer { cleanUp() }
        let json = #"{"version":99,"rules":[{"id":"future","appName":"A","bundleID":"b","tokens":[]}]}"#
        try Data(json.utf8).write(to: Store.fileURL)
        let store = Store()
        #expect(store.isReadOnly)
        #expect(store.lastError == Store.newerVersionMessage)
        store.add(rule("local"))
        #expect(!store.flush())
        #expect(try String(contentsOf: Store.fileURL, encoding: .utf8) == json)
        #expect(!store.restoreBackup(Document()))
    }

    @Test func schemaFiveFileWaitsForEvidenceAndIsNotRewrittenUntilMigrated() throws {
        _ = try prepared()
        defer { cleanUp() }
        try Data(Self.v5Json.utf8).write(to: Store.fileURL)
        let store = Store()
        #expect(store.migrationPending)
        #expect(store.document.rules.map(\.id) == ["old"]) // geçici şema 6 hâli
        #expect(store.flush()) // başarı bildirir ama dosyaya dokunmaz
        #expect(try String(contentsOf: Store.fileURL, encoding: .utf8) == Self.v5Json)
    }

    @Test func completingMigrationBacksUpTheOldFileWritesSchemaSixAndUndoRestoresIt() throws {
        let dir = try prepared()
        defer { cleanUp() }
        try Data(Self.v5Json.utf8).write(to: Store.fileURL)
        let store = Store()
        #expect(store.completeMigration(evidence: nil, now: Date(timeIntervalSince1970: 1_791_000_000)))
        #expect(!store.migrationPending && store.migrationReport != nil)
        let backups = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("Backups/pre-migration").path)
        #expect(backups.count == 1 && backups[0].hasPrefix("rules-v5-"))
        let backed = try String(contentsOf: dir.appendingPathComponent("Backups/pre-migration/\(backups[0])"),
                                encoding: .utf8)
        #expect(backed == Self.v5Json)
        let migrated = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Store.fileURL))
        #expect(migrated.fileVersion == Document.currentVersion)
        #expect(migrated.rules.map(\.id) == ["old"])
        // ⌘Z: geçişi geri al, şema 5 dosyası yerine yazılır, oturum salt okunur.
        #expect(store.history.canUndo)
        store.undo()
        #expect(store.upgradeUndone && store.isReadOnly)
        #expect(store.lastError == Store.upgradeUndoneMessage)
        #expect(try String(contentsOf: Store.fileURL, encoding: .utf8) == Self.v5Json)
        store.add(rule("late"))
        #expect(!store.flush())
        #expect(try String(contentsOf: Store.fileURL, encoding: .utf8) == Self.v5Json)
    }

    @Test func migrationStopsAndGoesReadOnlyWhenTheBackupCannotBeWritten() throws {
        let dir = try prepared()
        defer { cleanUp() }
        try Data(Self.v5Json.utf8).write(to: Store.fileURL)
        let store = Store()
        // Yedek klasörünün yeri bir dosya: oluşturulamaz.
        try Data("x".utf8).write(to: dir.appendingPathComponent("Backups"))
        #expect(!store.completeMigration(evidence: nil))
        #expect(!store.migrationPending && store.upgradeUndone && store.isReadOnly)
        #expect(store.lastError?.contains("backup") == true)
        #expect(try String(contentsOf: Store.fileURL, encoding: .utf8) == Self.v5Json)
    }

    @Test func restoringASchemaFiveBackupSkipsThePreMigrationCopy() throws {
        let dir = try prepared()
        defer { cleanUp() }
        let store = Store()
        store.add(rule("keep"))
        #expect(store.flush())
        var old = Document()
        old.rules = [rule("fromBackup")]
        old.syncActiveProfile()
        old.fileVersion = 5
        #expect(store.restoreBackup(old))
        #expect(store.migrationPending)
        #expect(store.completeMigration(evidence: nil))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Backups/pre-migration").path))
        #expect(store.document.rules.map(\.id) == ["fromBackup"])
        #expect(store.flush())
        let onDisk = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Store.fileURL))
        #expect(onDisk.rules.map(\.id) == ["fromBackup"])
    }

    @Test func restoreBackupWritesTheRestoredDocumentAndUndoWritesTheOldOneBack() throws {
        _ = try prepared()
        defer { cleanUp() }
        let store = Store()
        store.add(rule("before"))
        #expect(store.flush())
        var backup = Document()
        backup.rules = [rule("restored")]
        backup.syncActiveProfile()
        #expect(store.restoreBackup(backup))
        var onDisk = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Store.fileURL))
        #expect(onDisk.rules.map(\.id) == ["restored"])
        store.undo()
        #expect(store.flush())
        onDisk = try JSONDecoder().decode(Document.self, from: Data(contentsOf: Store.fileURL))
        #expect(onDisk.rules.map(\.id) == ["before"])
    }
}
