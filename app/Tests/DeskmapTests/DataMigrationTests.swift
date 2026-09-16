import Foundation
import Testing
@testable import Deskmap

/// Eski "Space Router" veri klasöründen yeni "Deskmap" klasörüne bir kerelik
/// göç. Gerçek Application Support'a hiç dokunmaz; geçici dizinler kullanır.
struct DataMigrationTests {

    @Test func shouldMigrateOnlyWhenNewMissingAndOldPresent() {
        #expect(DataMigration.shouldMigrate(newDirectoryExists: false, oldDirectoryExists: true))
        #expect(!DataMigration.shouldMigrate(newDirectoryExists: true, oldDirectoryExists: true))
        #expect(!DataMigration.shouldMigrate(newDirectoryExists: false, oldDirectoryExists: false))
        #expect(!DataMigration.shouldMigrate(newDirectoryExists: true, oldDirectoryExists: false))
    }

    /// Geçici bir eski/yeni klasör çifti kurar, işi yaptırır, temizler.
    private func withTempDirectories(_ body: (_ old: URL, _ new: URL) throws -> Void) rethrows {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DeskmapMigrationTests-\(UUID())")
        let old = root.appendingPathComponent("SpaceRouter")
        let new = root.appendingPathComponent("Deskmap")
        defer { try? fm.removeItem(at: root) }
        try body(old, new)
    }

    @Test func copiesKnownFilesWithoutDeletingSource() throws {
        try withTempDirectories { old, new in
            let fm = FileManager.default
            try fm.createDirectory(at: old, withIntermediateDirectories: true)
            try Data("rules".utf8).write(to: old.appendingPathComponent("rules.json"))
            try Data("pins".utf8).write(to: old.appendingPathComponent("session-pins.json"))
            // rules.json.bak kasıtlı olarak yok: eksik dosya sessizce atlanmalı.

            DataMigration.migrate(from: old, to: new, fileManager: fm)

            #expect(fm.fileExists(atPath: new.appendingPathComponent("rules.json").path))
            #expect(fm.fileExists(atPath: new.appendingPathComponent("session-pins.json").path))
            #expect(!fm.fileExists(atPath: new.appendingPathComponent("rules.json.bak").path))
            // Silme yok: eski dosyalar yerinde duruyor.
            #expect(fm.fileExists(atPath: old.appendingPathComponent("rules.json").path))
            #expect(fm.fileExists(atPath: old.appendingPathComponent("session-pins.json").path))
        }
    }

    @Test func doesNothingIfNewDirectoryAlreadyExists() throws {
        try withTempDirectories { old, new in
            let fm = FileManager.default
            try fm.createDirectory(at: old, withIntermediateDirectories: true)
            try fm.createDirectory(at: new, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: old.appendingPathComponent("rules.json"))
            try Data("new".utf8).write(to: new.appendingPathComponent("rules.json"))

            DataMigration.migrate(from: old, to: new, fileManager: fm)

            // Yeni klasördeki dosya ezilmedi (göç bir kez, atlanır).
            let content = try String(
                contentsOf: new.appendingPathComponent("rules.json"), encoding: .utf8)
            #expect(content == "new")
        }
    }

    @Test func doesNothingIfOldDirectoryMissing() throws {
        try withTempDirectories { old, new in
            let fm = FileManager.default
            DataMigration.migrate(from: old, to: new, fileManager: fm)
            #expect(!fm.fileExists(atPath: new.path))
        }
    }

    @Test func toleratesUnreadableSourceWithoutCrashing() throws {
        // Bir dosyayı okunamaz yapıp kopyalama hatası üret; fonksiyon hatayı
        // yutar (uygulama çökmez), diğer dosyalara devam eder.
        try withTempDirectories { old, new in
            let fm = FileManager.default
            try fm.createDirectory(at: old, withIntermediateDirectories: true)
            let blocked = old.appendingPathComponent("rules.json")
            try Data("rules".utf8).write(to: blocked)
            try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blocked.path) }
            try Data("pins".utf8).write(to: old.appendingPathComponent("session-pins.json"))

            DataMigration.migrate(from: old, to: new, fileManager: fm)

            #expect(!fm.fileExists(atPath: new.appendingPathComponent("rules.json").path))
            #expect(fm.fileExists(atPath: new.appendingPathComponent("session-pins.json").path))
        }
    }
}
