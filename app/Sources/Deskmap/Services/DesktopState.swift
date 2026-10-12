import CoreGraphics
import Foundation

/// `desktop-state.json` (docs/desktop-names-v2.md §A.4): bütün profillerde
/// ortak fiziksel durum. Son kararlı ekran ve masaüstü listesi, her
/// masaüstünün içeriği (başlıksız: pencere, pid, paket), park edilmiş
/// pencereler ve süren plan uygulaması. Yedeklere ve dışa aktarmaya girmez.
/// `desktop-spaces.json`'un yerini alır (o bir kez okunur).
struct DesktopStateFile: Codable, Equatable {
    struct Display: Codable, Equatable {
        var role: String
        var uuid: String
        var spaces: [UInt64]
    }
    struct WindowRef: Codable, Equatable, Hashable {
        var id: CGWindowID
        var pid: pid_t
        var bundleID: String
    }
    struct JournalMove: Codable, Equatable {
        var window: CGWindowID
        var space: UInt64
    }
    /// Süren uygulama: çökme olursa sonraki açılış buradan sürdürür.
    struct Transition: Codable, Equatable {
        var id: String
        var startedAt: Date
        var reason: String
        var from: [Display]
        var fromContents: [String: [WindowRef]]
        var fromMode: Mode
        var moves: [JournalMove] = []
        /// Günlükteki taşımalarla birlikte kaydedilecek bağlar (ad → space)
        /// ve taşıma haritası (space → space); metin anahtarlı.
        var rebinds: [String: UInt64]?
        var spaceMap: [String: UInt64]?
    }

    var version = 1
    var savedAt = Date()
    var bootTime: Date?
    var mode: Mode
    var displays: [Display]
    /// Space kimliği (metin) → yalnız o masaüstündeki pencereler.
    var contents: [String: [WindowRef]] = [:]
    var parked: [PlanApply.Parked] = []
    var transition: Transition?

    static let fileName = "desktop-state.json"
    static let legacyFileName = "desktop-spaces.json"
    /// Park kaydı bu kadar günden eskiyse düşer.
    static let parkedLifetime: TimeInterval = 14 * 24 * 3600

    var spaces: [String: [UInt64]] {
        Dictionary(displays.map { ($0.role, $0.spaces) }, uniquingKeysWith: { a, _ in a })
    }

    var snapshot: Succession.Snapshot {
        Succession.Snapshot(spaces: spaces, contents: Self.windowIDs(contents))
    }

    /// Ekran kümesi (rol + monitör kimliği). Eski dosyadan gelen kayıtta
    /// kimlik yoksa yalnız rol karşılaştırılır.
    func sameDisplays(as other: [Display]) -> Bool {
        let mine = displays.map { ($0.role, $0.uuid) }.sorted { $0.0 < $1.0 }
        let theirs = other.map { ($0.role, $0.uuid) }.sorted { $0.0 < $1.0 }
        guard mine.count == theirs.count else { return false }
        return zip(mine, theirs).allSatisfy { a, b in
            a.0 == b.0 && (a.1.isEmpty || b.1.isEmpty || a.1 == b.1)
        }
    }

    static func windowIDs(_ contents: [String: [WindowRef]]) -> [UInt64: [CGWindowID]] {
        var result: [UInt64: [CGWindowID]] = [:]
        for (key, list) in contents {
            if let space = UInt64(key) { result[space] = list.map(\.id) }
        }
        return result
    }

    static func encodeContents(_ contents: [UInt64: [WindowRef]]) -> [String: [WindowRef]] {
        var result: [String: [WindowRef]] = [:]
        for (space, list) in contents where !list.isEmpty {
            result[String(space)] = list.sorted { $0.id < $1.id }
        }
        return result
    }

    /// Süresi dolan ya da penceresi artık olmayan park kayıtlarını düşürür (saf).
    static func prunedParked(_ parked: [PlanApply.Parked], alive: Set<CGWindowID>?,
                             now: Date) -> [PlanApply.Parked] {
        parked.filter { entry in
            guard now.timeIntervalSince(entry.since) < parkedLifetime else { return false }
            guard let alive else { return true }
            return alive.contains(entry.window)
        }
    }

    // MARK: - Dosya

    static func read(directory: URL) -> DesktopStateFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let state = try? decoder.decode(DesktopStateFile.self, from: data) else { return nil }
        return state
    }

    /// Eski `desktop-spaces.json` (rol → space'ler): monitör kimliği ve
    /// içerik yok.
    static func readLegacy(directory: URL) -> DesktopStateFile? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(legacyFileName)),
              let saved = try? JSONDecoder().decode([String: [UInt64]].self, from: data),
              !saved.isEmpty else { return nil }
        let displays = saved.keys.sorted().map { Display(role: $0, uuid: "", spaces: saved[$0] ?? []) }
        return DesktopStateFile(mode: saved.keys.contains { $0 != "builtin" } ? .docked : .undocked,
                                displays: displays)
    }

    func write(directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// Sistemin açılış anı (yeniden başlatmada kimlikler yenilenir).
    static func currentBootTime() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    /// İki açılış anı aynı mı. Saat düzeltmeleri (uyanınca NTP) açılış
    /// anını birkaç saniye kaydırabilir; bir dakikadan küçük fark aynı açılış.
    static func sameBoot(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return true }
        return abs(a.timeIntervalSince(b)) < 60
    }
}
