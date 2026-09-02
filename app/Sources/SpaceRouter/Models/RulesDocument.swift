import Foundation

// MARK: - Kök belge

/// `rules.json` dosyasının bellek içi karşılığı.
/// Hammerspoon motoru aynı dosyayı okur; alan adları birebir aynı olmalıdır.
struct RulesDocument: Codable, Equatable {
    var version: Int
    var settings: RouterSettings
    var screens: [ScreenEntry]
    var rules: [Rule]

    static let empty = RulesDocument(
        version: 1,
        settings: RouterSettings(),
        screens: [],
        rules: []
    )

    init(
        version: Int = 1,
        settings: RouterSettings = RouterSettings(),
        screens: [ScreenEntry] = [],
        rules: [Rule] = []
    ) {
        self.version = version
        self.settings = settings
        self.screens = screens
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try container.decodeIfPresent(
            RouterSettings.self, forKey: .settings) ?? RouterSettings()
        screens = try container.decodeIfPresent(
            [ScreenEntry].self, forKey: .screens) ?? []
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}

// MARK: - Ayarlar

struct RouterSettings: Codable, Equatable {
    var enabled: Bool = true
    var debounceSeconds: Double = 0.4
    var screenSettleSeconds: Double = 2.5
    var moveSettleSeconds: Double = 0.25
    var notifications: Bool = true
    var logLevel: String = "info"
    var followWindowAfterMove: Bool = false
    var clampDesktopToAvailable: Bool = true
    var pinSpaces: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RouterSettings()

        enabled = try container.decodeIfPresent(
            Bool.self, forKey: .enabled) ?? defaults.enabled
        debounceSeconds = try container.decodeIfPresent(
            Double.self, forKey: .debounceSeconds) ?? defaults.debounceSeconds
        screenSettleSeconds = try container.decodeIfPresent(
            Double.self, forKey: .screenSettleSeconds)
            ?? defaults.screenSettleSeconds
        moveSettleSeconds = try container.decodeIfPresent(
            Double.self, forKey: .moveSettleSeconds)
            ?? defaults.moveSettleSeconds
        notifications = try container.decodeIfPresent(
            Bool.self, forKey: .notifications) ?? defaults.notifications
        logLevel = try container.decodeIfPresent(
            String.self, forKey: .logLevel) ?? defaults.logLevel
        followWindowAfterMove = try container.decodeIfPresent(
            Bool.self, forKey: .followWindowAfterMove)
            ?? defaults.followWindowAfterMove
        clampDesktopToAvailable = try container.decodeIfPresent(
            Bool.self, forKey: .clampDesktopToAvailable)
            ?? defaults.clampDesktopToAvailable
        pinSpaces = try container.decodeIfPresent(
            Bool.self, forKey: .pinSpaces) ?? defaults.pinSpaces
    }
}

// MARK: - Ekran kaydı

struct ScreenEntry: Codable, Equatable, Identifiable, Hashable {
    enum Role: String, Codable, CaseIterable {
        case builtin
        case external

        var localizedName: String {
            switch self {
            case .builtin: return "Dahili ekran"
            case .external: return "Harici monitör"
            }
        }
    }

    var id: String
    var role: Role
    var name: String
    var uuid: String

    /// Kurulumdan gelen, henüz doldurulmamış örnek değer.
    var hasPlaceholderUUID: Bool {
        uuid.uppercased().contains("REPLACE-WITH") || uuid.isEmpty
    }

    /// UUID'ler farklı kaynaklarda süslü parantezli veya küçük harfli
    /// olabiliyor; karşılaştırma normalize edilmiş biçim üzerinden yapılır.
    static func normalize(_ uuid: String) -> String {
        uuid
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
