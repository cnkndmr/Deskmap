import Foundation

// MARK: - Uygulama tanımı

/// Kuralın hangi uygulamanın pencerelerine uygulanacağı.
/// JSON'da hem `"Safari"` hem `{ "name": ..., "bundleID": ... }` kabul edilir.
struct AppSpec: Codable, Equatable, Hashable {
    var name: String
    var bundleID: String?

    init(name: String, bundleID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
    }

    private enum CodingKeys: String, CodingKey {
        case name, bundleID
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let shorthand = try? single.decode(String.self) {
            name = shorthand
            bundleID = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        // Boş string yerine alanı hiç yazma; motor bunu "yok" sayar.
        if let bundleID, !bundleID.isEmpty {
            try container.encode(bundleID, forKey: .bundleID)
        }
    }
}

// MARK: - Başlık eşleştirme

enum MatchType: String, Codable, CaseIterable, Identifiable {
    case contains
    case prefix
    case suffix
    case exact
    case pattern

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .contains: return "İçerir"
        case .prefix:   return "İle başlar"
        case .suffix:   return "İle biter"
        case .exact:    return "Tam eşleşir"
        case .pattern:  return "Lua deseni"
        }
    }

    var explanation: String {
        switch self {
        case .contains:
            return "Başlık bu metni herhangi bir yerinde içeriyorsa eşleşir."
        case .prefix:
            return "Başlık bu metinle başlıyorsa eşleşir. " +
                   "Açık dosya adı başlığın sonundaysa en güvenli seçenektir."
        case .suffix:
            return "Başlık bu metinle bitiyorsa eşleşir."
        case .exact:
            return "Başlık tam olarak bu metin ise eşleşir."
        case .pattern:
            return "Lua deseni olarak uygulanır. " +
                   "( ) . % + - * ? [ ] ^ $ karakterleri % ile kaçırılır."
        }
    }
}

struct MatchSpec: Codable, Equatable, Hashable {
    var type: MatchType
    var value: String

    init(type: MatchType = .contains, value: String = "") {
        self.type = type
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(MatchType.self, forKey: .type)
            ?? .contains
        value = try container.decode(String.self, forKey: .value)
    }
}

// MARK: - Layout

/// Ekranın kullanılabilir alanına göre 0..1 oranları.
struct Layout: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    static let full      = Layout(x: 0,    y: 0,    w: 1,    h: 1)
    static let leftHalf  = Layout(x: 0,    y: 0,    w: 0.5,  h: 1)
    static let rightHalf = Layout(x: 0.5,  y: 0,    w: 0.5,  h: 1)
    static let left70    = Layout(x: 0,    y: 0,    w: 0.7,  h: 1)
    static let right30   = Layout(x: 0.7,  y: 0,    w: 0.3,  h: 1)
    static let center80  = Layout(x: 0.1,  y: 0.1,  w: 0.8,  h: 0.8)
    static let topHalf   = Layout(x: 0,    y: 0,    w: 1,    h: 0.5)
    static let bottomHalf = Layout(x: 0,   y: 0.5,  w: 1,    h: 0.5)

    /// UI'da hazır seçenek olarak sunulan düzenler.
    static let presets: [(name: String, layout: Layout)] = [
        ("Tam ekran alanı", .full),
        ("Sol yarı",        .leftHalf),
        ("Sağ yarı",        .rightHalf),
        ("Sol %70",         .left70),
        ("Sağ %30",         .right30),
        ("Ortada %80",      .center80),
        ("Üst yarı",        .topHalf),
        ("Alt yarı",        .bottomHalf),
    ]

    /// Hazır düzenlerden birine karşılık geliyorsa adını döndürür.
    var presetName: String? {
        Layout.presets.first { $0.layout == self }?.name
    }

    var summary: String {
        presetName ?? String(
            format: "x %.0f%% · y %.0f%% · %.0f%%×%.0f%%",
            x * 100, y * 100, w * 100, h * 100)
    }
}

// MARK: - Hedef

/// Bir kuralın docked veya undocked durumdaki hedefi.
struct Destination: Codable, Equatable, Hashable {
    var screen: String
    var desktop: Int
    var layout: Layout

    init(screen: String = "", desktop: Int = 1, layout: Layout = .full) {
        self.screen = screen
        self.desktop = desktop
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        screen = try container.decodeIfPresent(String.self, forKey: .screen) ?? ""
        desktop = try container.decodeIfPresent(Int.self, forKey: .desktop) ?? 1
        layout = try container.decodeIfPresent(Layout.self, forKey: .layout)
            ?? .full
    }
}

// MARK: - Kural

struct Rule: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var enabled: Bool
    var app: AppSpec
    var match: MatchSpec
    var docked: Destination?
    var undocked: Destination?

    init(
        id: String = UUID().uuidString,
        name: String = "Yeni kural",
        enabled: Bool = true,
        app: AppSpec = AppSpec(name: "Safari", bundleID: "com.apple.Safari"),
        match: MatchSpec = MatchSpec(),
        docked: Destination? = Destination(),
        undocked: Destination? = Destination()
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.app = app
        self.match = match
        self.docked = docked
        self.undocked = undocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? true
        app = try container.decode(AppSpec.self, forKey: .app)
        match = try container.decode(MatchSpec.self, forKey: .match)
        docked = try container.decodeIfPresent(
            Destination.self, forKey: .docked)
        undocked = try container.decodeIfPresent(
            Destination.self, forKey: .undocked)
    }

    /// Kaydetmeden önce yakalanan sorunlar.
    var validationIssues: [String] {
        var issues: [String] = []

        if app.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Uygulama adı boş olamaz.")
        }
        if match.value.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Eşleşecek başlık metni boş olamaz.")
        }
        if docked == nil && undocked == nil {
            issues.append(
                "En az bir durum için hedef tanımlanmalı " +
                "(harici monitör bağlı / bağlı değil).")
        }
        if let docked, docked.desktop < 1 {
            issues.append("Docked Desktop numarası 1 veya daha büyük olmalı.")
        }
        if let undocked, undocked.desktop < 1 {
            issues.append("Undocked Desktop numarası 1 veya daha büyük olmalı.")
        }
        return issues
    }
}
