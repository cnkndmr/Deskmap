import Foundation
import Combine

/// `rules.json` dosyasının tek sahibi.
/// Hammerspoon motoru aynı dosyayı izler; kaydettiğimiz an kuralları
/// yeniden yükler. Bu yüzden yazma işlemi atomiktir.
@MainActor
final class RuleStore: ObservableObject {

    @Published var document: RulesDocument = .empty
    @Published private(set) var lastError: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var hasUnsavedChanges = false

    static let directoryURL: URL = {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpaceRouter",
                                    isDirectory: true)
    }()

    static let fileURL: URL =
        directoryURL.appendingPathComponent("rules.json")

    private var cancellables = Set<AnyCancellable>()
    private var isApplyingRemoteChange = false

    init(autosave: Bool = true) {
        load()

        guard autosave else { return }

        // Düzenlemeleri toplayıp yarım saniyede bir diske yaz.
        $document
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isApplyingRemoteChange else { return }
                self.save()
            }
            .store(in: &cancellables)
    }

    // MARK: - Okuma

    var configurationExists: Bool {
        FileManager.default.fileExists(atPath: Self.fileURL.path)
    }

    func load() {
        guard configurationExists else {
            lastError = nil
            document = .empty
            return
        }

        do {
            let data = try Data(contentsOf: Self.fileURL)
            let decoded = try JSONDecoder().decode(RulesDocument.self, from: data)

            isApplyingRemoteChange = true
            document = decoded
            isApplyingRemoteChange = false

            hasUnsavedChanges = false
            lastError = nil
        } catch {
            lastError = "rules.json okunamadı: \(error.localizedDescription)"
        }
    }

    // MARK: - Yazma

    @discardableResult
    func save() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys,
                                        .withoutEscapingSlashes]

            let data = try encoder.encode(document)

            // Atomik yazma: motor yarı yazılmış dosya okumasın.
            try data.write(to: Self.fileURL, options: .atomic)

            lastSavedAt = Date()
            hasUnsavedChanges = false
            lastError = nil
            return true
        } catch {
            lastError = "rules.json yazılamadı: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Kural işlemleri

    func addRule(_ rule: Rule) {
        document.rules.append(rule)
    }

    func update(_ rule: Rule) {
        guard let index = document.rules.firstIndex(where: { $0.id == rule.id })
        else { return }
        document.rules[index] = rule
    }

    func delete(ruleID: String) {
        document.rules.removeAll { $0.id == ruleID }
    }

    func move(from source: IndexSet, to destination: Int) {
        document.rules.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Ekran kayıtları

    /// Bağlı ekranları yapılandırmaya ekler; UUID'si zaten kayıtlı
    /// olanları günceller, kaldırılmış kayıtları silmez.
    func syncScreens(with detected: [DetectedScreen]) {
        for screen in detected {
            if let index = document.screens.firstIndex(
                where: { $0.uuid == screen.uuid }) {
                document.screens[index].name = screen.name
                document.screens[index].role =
                    screen.isBuiltin ? .builtin : .external
            } else {
                document.screens.append(
                    ScreenEntry(
                        id: Self.uniqueScreenID(
                            for: screen, existing: document.screens),
                        role: screen.isBuiltin ? .builtin : .external,
                        name: screen.name,
                        uuid: screen.uuid))
            }
        }
    }

    private static func uniqueScreenID(
        for screen: DetectedScreen,
        existing: [ScreenEntry]
    ) -> String {
        let base = screen.isBuiltin ? "builtin" : "external"
        var candidate = base
        var suffix = 2

        while existing.contains(where: { $0.id == candidate }) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func screenEntry(withID id: String) -> ScreenEntry? {
        document.screens.first { $0.id == id }
    }
}
