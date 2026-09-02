import Foundation
import Combine

/// Bilinen bir ekran: rol kimliği ve kullanıcıya gösterilecek ad.
struct KnownScreen: Codable, Equatable, Identifiable, Hashable {
    var id: String        // builtin, external, external-2 ...
    var name: String
    var aspect: Double    // genişlik / yükseklik

    var isBuiltin: Bool { id == "builtin" }
}

/// `rules.json` içeriği.
struct Document: Codable, Equatable {
    var version: Int = 2
    var enabled: Bool = true
    var screens: [KnownScreen] = []
    var rules: [Rule] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, enabled, screens, rules, settings
    }

    private struct LegacySettings: Decodable { var enabled: Bool? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = 2
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []

        if let flag = try c.decodeIfPresent(Bool.self, forKey: .enabled) {
            enabled = flag
        } else if let legacy = try? c.decode(LegacySettings.self, forKey: .settings) {
            enabled = legacy.enabled ?? true
        }

        // v2 ekran kayıtları; v1 kayıtları (uuid/role) atlanır, yeniden keşfedilir.
        screens = (try? c.decode([KnownScreen].self, forKey: .screens)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(screens, forKey: .screens)
        try c.encode(rules, forKey: .rules)
    }
}

/// Yapılandırmanın tek sahibi. Değişiklikler yarım saniye sonra diske yazılır.
@MainActor
final class Store: ObservableObject {

    @Published var document = Document()
    @Published private(set) var lastError: String?

    static let directoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SpaceRouter",
                                isDirectory: true)

    static let fileURL = directoryURL.appendingPathComponent("rules.json")

    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        $document
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
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
            lastError = "rules.json okunamadı: \(error.localizedDescription)"
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
