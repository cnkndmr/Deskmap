import Foundation

// MARK: - Düzen

/// Ekranın kullanılabilir alanına göre 0..1 oranları.
struct WindowLayout: Codable, Equatable, Hashable {
    var x: Double = 0
    var y: Double = 0
    var w: Double = 1
    var h: Double = 1

    /// Pencerenin gerçek çerçevesinden (AX koordinatları) ekranın
    /// kullanılabilir alanına göre oranlar. Pin, o anki çerçeveyi böyle
    /// saklar; çözünürlük değişse de aynı yere oturur.
    init(frame: CGRect, in area: CGRect) {
        guard area.width > 0, area.height > 0 else { self.init(); return }
        let x = (frame.minX - area.minX) / area.width
        let y = (frame.minY - area.minY) / area.height
        let w = frame.width / area.width
        let h = frame.height / area.height
        self.init(
            x: min(max(x, 0), 0.95),
            y: min(max(y, 0), 0.95),
            w: min(max(w, 0.05), 1),
            h: min(max(h, 0.05), 1))
    }

    init(x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    static let full       = WindowLayout(x: 0,   y: 0,   w: 1,   h: 1)
    static let leftHalf   = WindowLayout(x: 0,   y: 0,   w: 0.5, h: 1)
    static let rightHalf  = WindowLayout(x: 0.5, y: 0,   w: 0.5, h: 1)
    static let left70     = WindowLayout(x: 0,   y: 0,   w: 0.7, h: 1)
    static let right30    = WindowLayout(x: 0.7, y: 0,   w: 0.3, h: 1)
    static let topHalf    = WindowLayout(x: 0,   y: 0,   w: 1,   h: 0.5)
    static let bottomHalf = WindowLayout(x: 0,   y: 0.5, w: 1,   h: 0.5)
    static let center     = WindowLayout(x: 0.1, y: 0.1, w: 0.8, h: 0.8)

    /// Düzen seçicide gösterilen hazır seçenekler.
    static let presets: [WindowLayout] = [
        .full, .leftHalf, .rightHalf, .left70, .right30,
        .topHalf, .bottomHalf, .center,
    ]

    var label: String {
        switch self {
        case .full:       return "Tam"
        case .leftHalf:   return "Sol yarı"
        case .rightHalf:  return "Sağ yarı"
        case .left70:     return "Sol %70"
        case .right30:    return "Sağ %30"
        case .topHalf:    return "Üst yarı"
        case .bottomHalf: return "Alt yarı"
        case .center:     return "Orta"
        default:
            return "%\(Int((w * 100).rounded())) × %\(Int((h * 100).rounded()))"
        }
    }

    /// Verilen dikdörtgen içinde düzenin karşılık geldiği alan.
    func rect(in area: CGRect) -> CGRect {
        let cx = min(max(x, 0), 1)
        let cy = min(max(y, 0), 1)
        let cw = min(max(w, 0.05), 1 - cx)
        let ch = min(max(h, 0.05), 1 - cy)
        return CGRect(
            x: area.minX + area.width * cx,
            y: area.minY + area.height * cy,
            width: area.width * cw,
            height: area.height * ch)
    }
}

// MARK: - Hedef

/// Bir kuralın belirli bir moddaki (harici monitör var / yok) hedefi.
struct Destination: Codable, Equatable, Hashable {
    /// Ekran rolü: `builtin`, `external`, `external-2` ...
    var screen: String
    /// O ekrandaki normal masaüstü sırası (1 tabanlı).
    var desktop: Int
    var layout: WindowLayout

    init(screen: String, desktop: Int = 1, layout: WindowLayout = .full) {
        self.screen = screen
        self.desktop = max(1, desktop)
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screen = try c.decodeIfPresent(String.self, forKey: .screen) ?? "builtin"
        desktop = max(1, try c.decodeIfPresent(Int.self, forKey: .desktop) ?? 1)
        layout = try c.decodeIfPresent(WindowLayout.self, forKey: .layout) ?? .full
    }
}

// MARK: - Mod

enum Mode: String, Codable, CaseIterable, Identifiable {
    /// Harici monitör bağlı.
    case docked
    /// Yalnızca dahili ekran.
    case undocked

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .docked:   return "display.2"
        case .undocked: return "laptopcomputer"
        }
    }

    var title: String {
        switch self {
        case .docked:   return "Monitör bağlı"
        case .undocked: return "Sadece laptop"
        }
    }
}

// MARK: - Kural

/// "Şu uygulamanın başlığında şu parçalar geçen penceresi şuraya gitsin."
struct Rule: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var appName: String
    var bundleID: String
    /// Başlıkta (büyük/küçük harf duyarsız) hepsi geçmesi gereken parçalar.
    var tokens: [String]
    var docked: Destination?
    var undocked: Destination?

    init(
        id: String = UUID().uuidString,
        appName: String,
        bundleID: String,
        tokens: [String],
        docked: Destination? = nil,
        undocked: Destination? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.tokens = tokens
        self.docked = docked
        self.undocked = undocked
    }

    /// Boş `tokens` = uygulamanın bütün pencereleri.
    var isAppWide: Bool { tokens.isEmpty }

    var title: String {
        isAppWide ? "tüm pencereler" : tokens.joined(separator: " · ")
    }

    /// Verilen moddaki hedef. İki mod (monitör bağlı / sadece laptop)
    /// birbirinden tamamen bağımsızdır; biri diğerinden devralmaz,
    /// kullanıcı her iki kurulumu da ayrı ayrı yapar.
    subscript(mode: Mode) -> Destination? {
        get { mode == .docked ? docked : undocked }
        set {
            if mode == .docked { docked = newValue } else { undocked = newValue }
        }
    }

    // MARK: Çözümleme (eski şemayı da okur)

    private enum CodingKeys: String, CodingKey {
        case id, appName, bundleID, tokens, docked, undocked
        // v1 alanları
        case app, match
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        docked = try c.decodeIfPresent(Destination.self, forKey: .docked)
        undocked = try c.decodeIfPresent(Destination.self, forKey: .undocked)

        if let name = try c.decodeIfPresent(String.self, forKey: .appName) {
            appName = name
            bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
            tokens = try c.decodeIfPresent([String].self, forKey: .tokens) ?? []
            return
        }

        // v1: { app: "Safari" | {name, bundleID}, match: {type, value} }
        if let legacy = try? c.decode(LegacyApp.self, forKey: .app) {
            appName = legacy.name
            bundleID = legacy.bundleID ?? ""
        } else {
            appName = (try? c.decode(String.self, forKey: .app)) ?? ""
            bundleID = ""
        }
        let match = try? c.decode(LegacyMatch.self, forKey: .match)
        let value = match?.value ?? ""
        tokens = value.isEmpty ? [] : [value]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(appName, forKey: .appName)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(tokens, forKey: .tokens)
        try c.encodeIfPresent(docked, forKey: .docked)
        try c.encodeIfPresent(undocked, forKey: .undocked)
    }

    private struct LegacyApp: Decodable {
        var name: String
        var bundleID: String?
    }

    private struct LegacyMatch: Decodable {
        var value: String
    }
}

// MARK: - Hoşgörülü dizi çözümleme

/// Öğelerinden biri okunamayan dizi: bozuk öğe atlanır, kalanlar okunur.
/// Tek bir bozuk kural (`"desktop": "x"` gibi) bütün `rules.json`'ı
/// okunmaz kılmasın; atlanan sayısı `droppedCount` ile kullanıcıya bildirilir.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var droppedCount = 0

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let element = try? c.decode(Element.self) {
                elements.append(element)
            } else {
                // Başarısız çözümleme imleci ilerletmez; öğeyi boş okuyup geç.
                _ = try? c.decode(Skip.self)
                droppedCount += 1
            }
        }
    }

    /// Her JSON değerini okumadan kabul eder; yalnızca imleci ilerletir.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

// MARK: - Eşleştirme

extension Array where Element == Rule {
    /// Başlığa özgü kurallar uygulama geneli kurallardan önce denenir.
    var bySpecificity: [Rule] {
        sorted { $0.tokens.count > $1.tokens.count }
    }
}

extension Rule {
    func matches(bundleID windowBundle: String, appName windowApp: String,
                 title: String) -> Bool {
        if !bundleID.isEmpty {
            guard bundleID == windowBundle else { return false }
        } else {
            guard appName.caseInsensitiveCompare(windowApp) == .orderedSame
            else { return false }
        }
        if tokens.isEmpty { return true }
        let haystack = title.lowercased()
        return tokens.allSatisfy { haystack.contains($0.lowercased()) }
    }
}

// MARK: - Başlık parçalama

extension Rule {
    /// Başlığı yaygın ayraçlardan böler: " — ", " – ", " - ", " | ", " · ", " • ", " : "
    static func split(title: String) -> [String] {
        let separator = try! Regex(#"\s*[—–|·•]\s*|\s+[-:]\s+"#)
        let cleaned = title.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^[●•*]\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? (title.isEmpty ? [] : [title]) : cleaned
    }

    /// Aynı uygulama + aynı parçalar (büyük/küçük harf duyarsız).
    func sameKey(as other: Rule) -> Bool {
        let a = bundleID.isEmpty ? appName.lowercased() : bundleID
        let b = other.bundleID.isEmpty ? other.appName.lowercased() : other.bundleID
        guard a == b, tokens.count == other.tokens.count else { return false }
        return zip(tokens, other.tokens).allSatisfy {
            $0.caseInsensitiveCompare($1) == .orderedSame
        }
    }
}
