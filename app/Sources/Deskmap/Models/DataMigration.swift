import Foundation

/// Deskmap'in eski adı "Space Router" idi; veri klasörü de öyleydi
/// (`~/Library/Application Support/SpaceRouter`). İlk açılışta yeni klasör
/// (`Store.directoryURL`) hiç yoksa ve eski klasör (`Store.legacyDirectoryURL`)
/// varsa bilinen üç dosya oraya **kopyalanır** — taşınmaz, silinmez; eski
/// klasör olduğu gibi kalır (bakımcının kuralı: göçte silme yok). Göç en fazla
/// bir kez gerçekleşir: yeni klasör bir kez oluştuktan sonra bir daha
/// denenmez, böylece daha sonra yeni klasörde biriken veri eskisiyle
/// ezilmez.
enum DataMigration {

    /// Göç sırasında kopyalanacak dosya adları (saf, sabit).
    static let fileNames = ["rules.json", "rules.json.bak", "session-pins.json"]

    /// Göç yapılmalı mı (saf): yeni klasör hiç yoksa VE eski klasör varsa.
    static func shouldMigrate(newDirectoryExists: Bool, oldDirectoryExists: Bool) -> Bool {
        !newDirectoryExists && oldDirectoryExists
    }

    /// Eski klasörden yeni klasöre bilinen dosyaları kopyalar. Eksik dosya
    /// sessizce atlanır; kopyalama hatası uygulamayı çökertmez, yalnızca
    /// `Log.app`'e bir satır yazar. Yeni klasör zaten varsa ya da eski
    /// klasör yoksa hiçbir şey yapmaz (saf karar `shouldMigrate`'tedir).
    static func migrate(from oldDirectory: URL, to newDirectory: URL,
                        fileManager: FileManager = .default) {
        let oldExists = fileManager.fileExists(atPath: oldDirectory.path)
        let newExists = fileManager.fileExists(atPath: newDirectory.path)
        guard shouldMigrate(newDirectoryExists: newExists, oldDirectoryExists: oldExists)
        else { return }

        do {
            try fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        } catch {
            Log.app.error("""
                Could not create \(newDirectory.path, privacy: .public) for migration: \
                \(error.localizedDescription, privacy: .public)
                """)
            return
        }

        for name in fileNames {
            let source = oldDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = newDirectory.appendingPathComponent(name)
            do {
                try fileManager.copyItem(at: source, to: destination)
                Log.app.notice(
                    "Migrated \(name, privacy: .public) from the legacy Space Router folder")
            } catch {
                Log.app.error("""
                    Could not migrate \(name, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
    }
}
