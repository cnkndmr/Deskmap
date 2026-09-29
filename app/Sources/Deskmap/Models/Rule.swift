import Foundation

// MARK: - Düzen

/// Ekranın kullanılabilir alanına göre 0..1 oranları; ya da `fixed`
/// verilmişse sabit boyut (pt) ve sabitleme noktası (oranlar yok sayılır).
struct WindowLayout: Codable, Equatable, Hashable {
    var x: Double = 0
    var y: Double = 0
    var w: Double = 1
    var h: Double = 1
    /// Sabit boyut: her ekranda aynı boyut (ekrandan büyükse ekrana
    /// sığdırılır). nil = oranlı düzen. Eski kayıtlarda yok (nil okunur).
    var fixed: FixedSize?

    /// Sabit boyutlu düzen: pt cinsinden boyut ve kullanılabilir alandaki
    /// sabitleme noktası.
    struct FixedSize: Codable, Equatable, Hashable {
        var width: Double
        var height: Double
        var anchor: Anchor = .center
    }

    /// 3 × 3 sabitleme noktası.
    enum Anchor: String, Codable, CaseIterable, Hashable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

        /// Yatay ve dikey konum: 0 = sol/üst, 0,5 = orta, 1 = sağ/alt.
        var unit: (x: Double, y: Double) {
            switch self {
            case .topLeft: return (0, 0)
            case .top: return (0.5, 0)
            case .topRight: return (1, 0)
            case .left: return (0, 0.5)
            case .center: return (0.5, 0.5)
            case .right: return (1, 0.5)
            case .bottomLeft: return (0, 1)
            case .bottom: return (0.5, 1)
            case .bottomRight: return (1, 1)
            }
        }

        var label: String {
            switch self {
            case .topLeft: return L("Top left")
            case .top: return L("Top")
            case .topRight: return L("Top right")
            case .left: return L("Left")
            case .center: return L("Center")
            case .right: return L("Right")
            case .bottomLeft: return L("Bottom left")
            case .bottom: return L("Bottom")
            case .bottomRight: return L("Bottom right")
            }
        }
    }

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

    /// Sabit boyutlu düzen.
    init(fixed: FixedSize) {
        self.init()
        self.fixed = fixed
    }

    static let full       = WindowLayout(x: 0,   y: 0,   w: 1,   h: 1)
    static let leftHalf   = WindowLayout(x: 0,   y: 0,   w: 0.5, h: 1)
    static let rightHalf  = WindowLayout(x: 0.5, y: 0,   w: 0.5, h: 1)
    static let left70     = WindowLayout(x: 0,   y: 0,   w: 0.7, h: 1)
    static let right30    = WindowLayout(x: 0.7, y: 0,   w: 0.3, h: 1)
    static let right70    = WindowLayout(x: 0.3, y: 0,   w: 0.7, h: 1)
    static let left30     = WindowLayout(x: 0,   y: 0,   w: 0.3, h: 1)
    static let topHalf    = WindowLayout(x: 0,   y: 0,   w: 1,   h: 0.5)
    static let bottomHalf = WindowLayout(x: 0,   y: 0.5, w: 1,   h: 0.5)
    static let center     = WindowLayout(x: 0.1, y: 0.1, w: 0.8, h: 0.8)

    static let leftThird       = WindowLayout(x: 0,       y: 0, w: 1.0 / 3, h: 1)
    static let centerThird     = WindowLayout(x: 1.0 / 3, y: 0, w: 1.0 / 3, h: 1)
    static let rightThird      = WindowLayout(x: 2.0 / 3, y: 0, w: 1.0 / 3, h: 1)
    static let leftTwoThirds   = WindowLayout(x: 0,       y: 0, w: 2.0 / 3, h: 1)
    static let rightTwoThirds  = WindowLayout(x: 1.0 / 3, y: 0, w: 2.0 / 3, h: 1)
    static let centerHalf      = WindowLayout(x: 0.25,    y: 0, w: 0.5, h: 1)
    static let leftQuarter     = WindowLayout(x: 0,       y: 0, w: 0.25, h: 1)
    static let rightQuarter    = WindowLayout(x: 0.75,    y: 0, w: 0.25, h: 1)
    static let topLeft         = WindowLayout(x: 0,   y: 0,   w: 0.5, h: 0.5)
    static let topRight        = WindowLayout(x: 0.5, y: 0,   w: 0.5, h: 0.5)
    static let bottomLeft      = WindowLayout(x: 0,   y: 0.5, w: 0.5, h: 0.5)
    static let bottomRight     = WindowLayout(x: 0.5, y: 0.5, w: 0.5, h: 0.5)

    /// Bu en-boy oranından (genişlik / yükseklik) itibaren ekran ultra geniş
    /// sayılır (21:9 ≈ 2,33; 32:9 ≈ 3,56).
    static let ultrawideAspect = 2.2

    /// Eski sabit liste (belgelerde ve testlerde); seçici `presets(aspect:)`
    /// kullanır.
    static let presets: [WindowLayout] = [
        .full, .leftHalf, .rightHalf, .left70, .right30,
        .topHalf, .bottomHalf, .center,
    ]

    /// Hedef ekranın şekline göre hazır düzenler: ultra genişte sütunlar
    /// (üçte bir, üçte iki, çeyrek, ortada yarım), normal ekranda yarımlar,
    /// köşeler ve orta.
    static func presets(aspect: Double) -> [WindowLayout] {
        if aspect >= ultrawideAspect {
            return [.full, .leftHalf, .rightHalf, .leftThird, .centerThird, .rightThird,
                    .leftTwoThirds, .rightTwoThirds, .centerHalf, .leftQuarter, .rightQuarter,
                    .center]
        }
        return [.full, .leftHalf, .rightHalf, .left70, .right70, .left30, .right30,
                .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .center]
    }

    var label: String {
        if let fixed {
            return L("%ld × %ld pt · %@", Int(fixed.width.rounded()), Int(fixed.height.rounded()),
                     fixed.anchor.label)
        }
        switch self {
        case .full:       return L("Full")
        case .leftHalf:   return L("Left half")
        case .rightHalf:  return L("Right half")
        case .left70:     return L("Left 70%")
        case .right30:    return L("Right 30%")
        case .right70:    return L("Right 70%")
        case .left30:     return L("Left 30%")
        case .topHalf:    return L("Top half")
        case .bottomHalf: return L("Bottom half")
        case .center:     return L("Center")
        case .leftThird:      return L("Left third")
        case .centerThird:    return L("Center third")
        case .rightThird:     return L("Right third")
        case .leftTwoThirds:  return L("Left two thirds")
        case .rightTwoThirds: return L("Right two thirds")
        case .centerHalf:     return L("Center half")
        case .leftQuarter:    return L("Left quarter")
        case .rightQuarter:   return L("Right quarter")
        case .topLeft:        return L("Top left quarter")
        case .topRight:       return L("Top right quarter")
        case .bottomLeft:     return L("Bottom left quarter")
        case .bottomRight:    return L("Bottom right quarter")
        default:
            return L("%ld%% × %ld%%", Int((w * 100).rounded()), Int((h * 100).rounded()))
        }
    }

    /// Verilen dikdörtgen içinde düzenin karşılık geldiği alan.
    /// `pointsPerUnit`: sabit boyutlu düzende 1 pt'nin `area` içinde kaç
    /// birim olduğu (önizleme küçültülmüş ekran çizer; gerçek yerleşimde 1).
    func rect(in area: CGRect, pointsPerUnit: CGFloat = 1) -> CGRect {
        if let fixed {
            let width = min(CGFloat(fixed.width) * pointsPerUnit, area.width)
            let height = min(CGFloat(fixed.height) * pointsPerUnit, area.height)
            let unit = fixed.anchor.unit
            return CGRect(
                x: area.minX + (area.width - width) * unit.x,
                y: area.minY + (area.height - height) * unit.y,
                width: width, height: height)
        }
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
        case .docked:   return L("Monitor connected")
        case .undocked: return L("Laptop only")
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
    var tokens: [String] {
        didSet { loweredTokens = Self.lowered(tokens) }
    }
    var docked: Destination?
    var undocked: Destination?

    /// `tokens`'ın küçük harfli kopyası; `matches` her çağrıda yeniden
    /// küçültmesin (her taramada ve her arayüz çiziminde kural × pencere kez
    /// çağrılır). `tokens`'tan türetilir; init'ler ve `didSet` eşit tutar.
    private var loweredTokens: [String]

    private static func lowered(_ tokens: [String]) -> [String] {
        tokens.map { $0.lowercased() }
    }

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
        self.loweredTokens = Self.lowered(tokens)
        self.docked = docked
        self.undocked = undocked
    }

    /// Boş `tokens` = uygulamanın bütün pencereleri.
    var isAppWide: Bool { tokens.isEmpty }

    var title: String {
        isAppWide ? L("all windows") : tokens.joined(separator: " · ")
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

        let decodedTokens: [String]
        if let name = try c.decodeIfPresent(String.self, forKey: .appName) {
            appName = name
            bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
            decodedTokens = try c.decodeIfPresent([String].self, forKey: .tokens) ?? []
        } else {
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
            decodedTokens = value.isEmpty ? [] : [value]
        }
        // Init içinde `didSet` çalışmaz; türetilen kopya burada kurulur.
        tokens = decodedTokens
        loweredTokens = Self.lowered(decodedTokens)
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
    /// Pencere bu kurala uyuyor mu: paket kimliği (yoksa ad, büyük/küçük
    /// harf duyarsız) ve başlıkta bütün parçalar.
    ///
    /// Büyük/küçük harf eşleme `lowercased()` ile yapılır (Unicode küçültme,
    /// yerelden bağımsız): "İ" → "i̇" (i + birleşen nokta), "I" → "i", "ı"
    /// olduğu gibi kalır. `range(of:options: .caseInsensitive)` kullanılmaz:
    /// o, tam katlama uygular ve "ß" ile "SS", "ﬁ" ile "fi" gibi çiftleri de
    /// eşler; kararlar değişmesin diye küçültme semantiği korunur
    /// (`RuleTests` Türkçe ve ß örneklerini sabitler).
    func matches(bundleID windowBundle: String, appName windowApp: String,
                 title: String) -> Bool {
        matches(bundleID: windowBundle, appName: windowApp, loweredTitle: title.lowercased())
    }

    /// Aynı karar; başlığı küçültmeyi çağırana bırakır ve yalnızca
    /// gerektiğinde ister (uygulama uymuyorsa ya da kural uygulama
    /// geneliyse başlığa bakılmaz). `Routing.select` bir pencere için birçok
    /// kural denerken başlığı böylece bir kez küçültür.
    func matches(bundleID windowBundle: String, appName windowApp: String,
                 loweredTitle: @autoclosure () -> String) -> Bool {
        if !bundleID.isEmpty {
            guard bundleID == windowBundle else { return false }
        } else {
            guard appName.caseInsensitiveCompare(windowApp) == .orderedSame
            else { return false }
        }
        if tokens.isEmpty { return true }
        let haystack = loweredTitle()
        return loweredTokens.allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Başlık parçalama

extension Rule {
    /// Başlık ayraçları: " — ", " – ", " - ", " | ", " · ", " • ", " : ".
    /// Bir kez derlenir (eskiden her `split` çağrısında derleniyordu).
    // nonisolated(unsafe): `Regex` bu araç zincirinde Sendable işaretli
    // değil ama değişmez bir değer; `split` yalnızca okur, yazan yok.
    nonisolated(unsafe) private static let titleSeparator =
        try! Regex(#"\s*[—–|·•]\s*|\s+[-:]\s+"#)

    /// Başlığı yaygın ayraçlardan böler: " — ", " – ", " - ", " | ", " · ", " • ", " : "
    static func split(title: String) -> [String] {
        let cleaned = title.split(separator: titleSeparator)
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
