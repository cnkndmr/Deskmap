import Foundation

// MARK: - Düzen kitaplığı

/// Düzenin gösterildiği liste. Her giriş tek yerde görünür: temel satırdaki
/// düzen gelişmiş ızgarada tekrarlanmaz.
enum LayoutList: String, Codable, CaseIterable, Identifiable {
    case basic, advanced, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic:    return L("Basic layouts")
        case .advanced: return L("Advanced layouts")
        case .hidden:   return L("Hidden layouts")
        }
    }

    /// Ayarlar'da bölüm başlığının altındaki açıklama.
    var detail: String {
        switch self {
        case .basic:    return L("Tiles under every pin. Up to %ld.",
                                 LayoutLibrary.maxBasic)
        case .advanced: return L("In the Advanced section, next to the grid.")
        case .hidden:   return L("Not offered anywhere. Pins that use them keep them.")
        }
    }

    /// Menü ve bölümlü seçicide kısa ad.
    var shortTitle: String {
        switch self {
        case .basic:    return L("Basic")
        case .advanced: return L("Advanced")
        case .hidden:   return L("Hidden")
        }
    }
}

/// Kitaplıktaki bir düzen.
struct LayoutEntry: Codable, Equatable, Hashable, Identifiable {
    /// Kalıcı kimlik: hazırlarda sabit ("full", "left-half" … "as-is"),
    /// kullanıcınınkilerde UUID.
    var id: String
    /// Kullanıcının verdiği ad; nil = otomatik (`layout.label`).
    var name: String?
    var layout: WindowLayout
    var list: LayoutList

    init(id: String, name: String? = nil, layout: WindowLayout, list: LayoutList) {
        self.id = id
        self.name = name
        self.layout = layout
        self.list = list
    }

    var isBuiltIn: Bool { LayoutLibrary.builtIn(id) != nil }
    /// Yalnız "olduğu gibi" (yalnız masaüstü) girişi.
    var isDesktopOnly: Bool { layout.isDesktopOnly }
    /// Görünen ad: kullanıcının adı, yoksa hazır ya da genel etiket.
    var displayName: String { name ?? (isDesktopOnly ? L("As it is") : layout.label) }

    private enum CodingKeys: String, CodingKey {
        case id, name, layout, list
    }

    /// Hoşgörülü okuma: kimlik ve düzen şart (yoksa `LossyArray` atlar);
    /// bilinmeyen liste gelişmiş okunur. Eski sürümlerin ekran şekli alanı
    /// (`fit`) yok sayılır: her düzen her ekranda önerilir.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "empty id")
        }
        self.id = id
        layout = try c.decode(WindowLayout.self, forKey: .layout)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        list = (try? c.decode(LayoutList.self, forKey: .list)) ?? .advanced
    }

    /// Ad yoksa yazılmaz.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(layout, forKey: .layout)
        try c.encode(list, forKey: .list)
    }
}

/// Kullanıcının düzen kitaplığı: hangi düzen temel satırda (her pinin
/// altındaki döşemeler), hangisi gelişmiş ızgarada, hangisi gizli. Kurallar
/// düzenin değerini tutar (kimliğini değil): kitaplıkta değişen ya da
/// silinen düzen hiçbir pini bozmaz, hiçbir pencereyi taşımaz. Saf değer
/// tipidir; her değişiklikten sonra `normalized` kurallarına uyar.
struct LayoutLibrary: Codable, Equatable {

    static let currentVersion = 1
    /// Temel satırda en çok bu kadar döşeme (sağ sütunun genişliği; artı
    /// seçili özel düzenin döşemesi).
    static let maxBasic = 6
    static let maxNameLength = 40
    /// "Olduğu gibi" (yalnız masaüstü) girişinin kimliği.
    static let asIsID = "as-is"
    /// Aynı alan sayılan fark (oran); ızgaranın en küçük hücresinden çok küçük.
    static let tolerance = 0.0005

    /// Global sıra; bölümler (temel, gelişmiş, gizli) bitişik tutulur.
    private(set) var entries: [LayoutEntry]

    init(entries: [LayoutEntry]) {
        self.entries = Self.normalized(entries)
    }

    /// Hazır düzenler, varsayılan sırasıyla: tek set (laptop düzenleri), her
    /// ekranda; ultra geniş ekranda da aynıları önerilir.
    static let builtIns: [LayoutEntry] = [
        LayoutEntry(id: "full", layout: .full, list: .basic),
        LayoutEntry(id: "left-half", layout: .leftHalf, list: .basic),
        LayoutEntry(id: "right-half", layout: .rightHalf, list: .basic),
        LayoutEntry(id: asIsID, layout: .anyFrame, list: .basic),
        LayoutEntry(id: "left-70", layout: .left70, list: .advanced),
        LayoutEntry(id: "right-70", layout: .right70, list: .advanced),
        LayoutEntry(id: "left-30", layout: .left30, list: .advanced),
        LayoutEntry(id: "right-30", layout: .right30, list: .advanced),
        LayoutEntry(id: "top-half", layout: .topHalf, list: .advanced),
        LayoutEntry(id: "bottom-half", layout: .bottomHalf, list: .advanced),
        LayoutEntry(id: "top-left", layout: .topLeft, list: .advanced),
        LayoutEntry(id: "top-right", layout: .topRight, list: .advanced),
        LayoutEntry(id: "bottom-left", layout: .bottomLeft, list: .advanced),
        LayoutEntry(id: "bottom-right", layout: .bottomRight, list: .advanced),
        LayoutEntry(id: "center", layout: .center, list: .advanced),
    ]

    static let defaults = LayoutLibrary(entries: builtIns)

    /// Kaldırılan hazır düzenler (eski ultra geniş sütunları): kayıtlı
    /// kitaplıktan okurken atılır. Bunları kullanan kurallar çerçevelerini
    /// kendileri taşıdığı için etkilenmez.
    static let retiredBuiltInIDs: Set<String> = [
        "left-third", "center-third", "right-third", "left-two-thirds",
        "right-two-thirds", "center-half", "left-quarter", "right-quarter",
    ]

    static func builtIn(_ id: String) -> LayoutEntry? {
        builtIns.first { $0.id == id }
    }

    // MARK: Okuma

    func entry(_ id: String) -> LayoutEntry? {
        entries.first { $0.id == id }
    }

    /// Bir listenin girişleri, global sırayla.
    func entries(in list: LayoutList) -> [LayoutEntry] {
        entries.filter { $0.list == list }
    }

    /// Temel satır ("olduğu gibi" dahil); her ekranda aynı.
    func basic() -> [WindowLayout] {
        entries(in: .basic).map(\.layout)
    }

    /// Gelişmiş ızgaranın hazır düzenleri: yalnız gelişmiş girişler (temel
    /// satırdakiler zaten onun üstünde), global sırayla; her ekranda aynı.
    func advanced() -> [WindowLayout] {
        entries(in: .advanced)
            .filter { !$0.isDesktopOnly }
            .map(\.layout)
    }

    /// Düzeni birebir taşıyan giriş (gizliler dahil).
    func entry(matching layout: WindowLayout) -> LayoutEntry? {
        entries.first { $0.layout == layout }
    }

    /// Görünen ad: kitaplıkta adı verilmiş girişin düzeniyse o ad, değilse
    /// düzenin kendi etiketi (hazır ad ya da "%60 × %100"). Yalnız masaüstü
    /// ve sabit boyutlu düzen hep kendi etiketiyle.
    func label(for layout: WindowLayout) -> String {
        guard !layout.isDesktopOnly, layout.fixed == nil,
              let name = entry(matching: layout)?.name else { return layout.label }
        return name
    }

    /// Döşeme yazısı: "Olduğu gibi", temel satırdaki girişin adı, başka bir
    /// düzen için kısa "Özel" (tam adı ipucunda ve satırın altında).
    func shortLabel(for layout: WindowLayout) -> String {
        if layout.isDesktopOnly { return L("As it is") }
        guard basic().contains(layout),
              let entry = entry(matching: layout) else { return L("Custom") }
        return entry.displayName
    }

    /// Aynı (ya da neredeyse aynı) alanı kaplayan başka giriş; `id` hariç.
    /// Yalnız masaüstü girişi alan değildir, karşılaştırılmaz.
    func conflict(for layout: WindowLayout, excluding id: String?) -> LayoutEntry? {
        entries.first { entry in
            entry.id != id && !entry.isDesktopOnly && Self.sameArea(entry.layout, layout)
        }
    }

    var isBasicFull: Bool { entries(in: .basic).count >= Self.maxBasic }

    /// Hazır düzenin özgün alanını şimdi kaplayan başka giriş: varsa
    /// `restore` reddeder (Ayarlar'da "Özgüne dön" kapalı, nedeni yazılı).
    func restoreConflict(_ id: String) -> LayoutEntry? {
        guard let original = Self.builtIn(id) else { return nil }
        return conflict(for: original.layout, excluding: id)
    }

    /// Hazır düzenin alanı ya da adı varsayılandan farklı mı.
    func isModified(_ id: String) -> Bool {
        guard let original = Self.builtIn(id), let current = entry(id) else { return false }
        return current.layout != original.layout || current.name != nil
    }

    static func sameArea(_ a: WindowLayout, _ b: WindowLayout) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance
    }

    // MARK: Değişiklikler (saf; false/nil = reddedildi ya da değişmedi)

    /// Yeni düzen ekler; bölümünün sonuna düşer. Kimliğini, reddedilirse nil
    /// döner (geçersiz ya da yalnız masaüstü düzen, aynı alan, dolu temel
    /// satır, var olan kimlik).
    @discardableResult
    mutating func add(_ layout: WindowLayout, name: String?, list: LayoutList,
                      id: String = UUID().uuidString) -> String? {
        guard !id.isEmpty, entry(id) == nil, !layout.isDesktopOnly,
              let clean = Self.sanitized(layout),
              conflict(for: clean, excluding: nil) == nil,
              !(list == .basic && isBasicFull) else { return nil }
        entries = Self.normalized(entries + [
            LayoutEntry(id: id, name: Self.cleanName(name), layout: clean, list: list),
        ])
        return id
    }

    /// Alanı ve adı değiştirir; liste ve sıra kalır.
    @discardableResult
    mutating func update(_ id: String, layout: WindowLayout, name: String?) -> Bool {
        guard id != Self.asIsID, let index = entries.firstIndex(where: { $0.id == id }),
              !layout.isDesktopOnly, let clean = Self.sanitized(layout),
              conflict(for: clean, excluding: id) == nil else { return false }
        var updated = entries[index]
        updated.layout = Self.snapped(clean, to: [Self.builtIn(id)?.layout, updated.layout])
        updated.name = Self.cleanName(name)
        guard updated != entries[index] else { return false }
        entries[index] = updated
        entries = Self.normalized(entries)
        return true
    }

    /// Ad verir; boş ad otomatik etikete döner.
    @discardableResult
    mutating func rename(_ id: String, to name: String?) -> Bool {
        guard id != Self.asIsID, let index = entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let clean = Self.cleanName(name)
        guard clean != entries[index].name else { return false }
        entries[index].name = clean
        return true
    }

    /// Başka listeye taşır; hedef bölümün sonuna düşer.
    @discardableResult
    mutating func setList(_ id: String, to list: LayoutList) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].list != list,
              !(id == Self.asIsID && list == .advanced),
              !(list == .basic && isBasicFull) else { return false }
        var moved = entries.remove(at: index)
        moved.list = list
        entries = Self.normalized(entries + [moved])
        return true
    }

    /// Bölümünün içinde yukarı (−) ya da aşağı (+) taşır; bölüm dışına çıkmaz.
    @discardableResult
    mutating func move(_ id: String, by offset: Int) -> Bool {
        guard offset != 0, let index = entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let target = index + offset
        guard entries.indices.contains(target), entries[target].list == entries[index].list else {
            return false
        }
        let moved = entries.remove(at: index)
        entries.insert(moved, at: target)
        return true
    }

    /// Kullanıcının düzenini siler; hazırlar silinmez (gizlenir). Kurallar
    /// değeri tuttuğu için pinlere dokunmaz.
    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        guard Self.builtIn(id) == nil, let index = entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        entries.remove(at: index)
        return true
    }

    /// Değiştirilmiş hazır düzenin özgün alanı, adı ve ekran şekli; liste ve
    /// sıra kalır. Özgün alan başka bir girişte varsa reddedilir.
    @discardableResult
    mutating func restore(_ id: String) -> Bool {
        guard let original = Self.builtIn(id), isModified(id),
              let index = entries.firstIndex(where: { $0.id == id }),
              restoreConflict(id) == nil else { return false }
        entries[index].layout = original.layout
        entries[index].name = nil
        entries = Self.normalized(entries)
        return true
    }

    /// Kenar boşluğu alanları alanı bir ulp kaydırabilir (1 − 0,7 =
    /// 0,30000000000000004): aynı alan sayılan değer, sıradaki ilk adayın
    /// (hazırın özgünü, sonra eski değer) bitlerine oturur. Yoksa hazır
    /// düzen "değişti" görünür, eski değeri tutan pinler girişle eşleşmez.
    static func snapped(_ layout: WindowLayout, to candidates: [WindowLayout?]) -> WindowLayout {
        candidates.lazy.compactMap { $0 }.first { sameArea($0, layout) } ?? layout
    }

    // MARK: Temizleme (saf)

    /// Kitaplığa girebilen hâl: yalnız oranlı (sabit boyut ve yalnız
    /// masaüstü atılır). Kenar en az `WindowLayout.minSide` (ızgaranın en
    /// küçük hücresi). Değerler yalnız aralık dışındaysa kırpılır;
    /// aralıktakiler bit bit korunur (üçte bir `.leftThird`'e eşit kalsın).
    /// Sayı olmayan değer varsa nil.
    static func sanitized(_ layout: WindowLayout) -> WindowLayout? {
        guard [layout.x, layout.y, layout.w, layout.h].allSatisfy(\.isFinite) else { return nil }
        let slack = 1e-9
        func clamped(_ v: Double, _ low: Double, _ high: Double) -> Double {
            v < low - slack ? low : (v > high + slack ? high : v)
        }
        let side = WindowLayout.minSide
        let x = clamped(layout.x, 0, 1 - side)
        let y = clamped(layout.y, 0, 1 - side)
        return WindowLayout(x: x, y: y,
                            w: clamped(layout.w, side, 1 - x),
                            h: clamped(layout.h, side, 1 - y))
    }

    /// Baştaki/sondaki boşluk atılır; boş ad nil; en çok `maxNameLength`.
    static func cleanName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    /// Kitaplığın değişmezleri (her değişiklikten ve okumadan sonra):
    /// 1. boş ya da tekrar eden kimlik atılır (ilki kalır);
    /// 2. "olduğu gibi" hep yalnız masaüstü, adsız, her ekranda; gelişmişe
    ///    konamaz (gizli olur); öbürleri `sanitized` (geçersizse atılır);
    /// 3. ad `cleanName`;
    /// 4. aynı düzen ikinci kez giremez;
    /// 5. eksik hazır düzen varsayılanıyla sona eklenir (alanı yoksa);
    /// 6. temel satırda `maxBasic`'ten fazlası gelişmişe iner;
    /// 7. bölümler sırayı koruyarak temel → gelişmiş → gizli dizilir.
    private static func normalized(_ input: [LayoutEntry]) -> [LayoutEntry] {
        var ids = Set<String>()
        var result: [LayoutEntry] = []
        for var entry in input {
            guard !entry.id.isEmpty, !retiredBuiltInIDs.contains(entry.id),
                  ids.insert(entry.id).inserted else { continue }
            if entry.id == asIsID {
                entry.layout = .anyFrame
                entry.name = nil
                if entry.list == .advanced { entry.list = .hidden }
            } else {
                guard let clean = sanitized(entry.layout) else { continue }
                entry.layout = clean
                entry.name = cleanName(entry.name)
            }
            guard !result.contains(where: { $0.layout == entry.layout }) else { continue }
            result.append(entry)
        }
        for original in builtIns where !result.contains(where: { $0.id == original.id }) {
            guard !result.contains(where: { $0.layout == original.layout }) else { continue }
            result.append(original)
        }
        var basicCount = 0
        for index in result.indices where result[index].list == .basic {
            basicCount += 1
            if basicCount > maxBasic {
                result[index].list = result[index].id == asIsID ? .hidden : .advanced
            }
        }
        return LayoutList.allCases.flatMap { list in result.filter { $0.list == list } }
    }

    // MARK: Kayıt

    private enum CodingKeys: String, CodingKey {
        case version, entries
    }

    /// Hoşgörülü okuma: bozuk giriş atlanır, eksik hazırlar eklenir; daha
    /// yeni sürümün kitaplığı okuyabildiği kadarıyla okunur (`version`
    /// yalnız bilgi).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = try? c.decodeIfPresent(LossyArray<LayoutEntry>.self, forKey: .entries)
        self.init(entries: lossy?.elements ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(entries, forKey: .entries)
    }
}

// MARK: - Taslak

/// Ayarlar'daki düzen düzenleyicisinin taslağı (saf): yeni ya da var olan
/// giriş, kaydedilene kadar kitaplığa dokunmaz.
struct LayoutDraft: Equatable {
    /// nil = yeni düzen.
    var id: String?
    var layout: WindowLayout
    /// Ad alanının ham metni; boşsa otomatik ad.
    var name: String
    var list: LayoutList

    /// Yeni taslak: kitaplıkta olmayan ilk ortalı alan, gelişmiş listede.
    static func new(in library: LayoutLibrary) -> LayoutDraft {
        let candidates = [WindowLayout(x: 0.15, y: 0.1, w: 0.7, h: 0.8),
                          WindowLayout(x: 0.25, y: 0, w: 0.5, h: 1),
                          WindowLayout(x: 0.2, y: 0.1, w: 0.6, h: 0.8)]
        let layout = candidates.first { library.conflict(for: $0, excluding: nil) == nil } ?? .center
        return LayoutDraft(id: nil, layout: layout, name: "", list: .advanced)
    }

    static func editing(_ entry: LayoutEntry) -> LayoutDraft {
        LayoutDraft(id: entry.id, layout: entry.layout, name: entry.name ?? "",
                    list: entry.list)
    }

    /// Aynı alanı kaplayan başka giriş (taslağın kendisi hariç).
    func conflict(in library: LayoutLibrary) -> LayoutEntry? {
        library.conflict(for: LayoutLibrary.sanitized(layout) ?? layout, excluding: id)
    }

    /// nil = kaydedilebilir; değilse kullanıcıya gösterilecek neden.
    func problem(in library: LayoutLibrary) -> String? {
        // Taslak açıkken giriş silindiyse (geri alma, başka pencere) kayıt
        // sessizce kaybolmasın.
        if let id, library.entry(id) == nil {
            return L("This layout no longer exists.")
        }
        if let other = conflict(in: library) {
            return L("Same area as “%@”.", other.displayName)
        }
        let alreadyBasic = id.flatMap { library.entry($0) }?.list == .basic
        if list == .basic, !alreadyBasic, library.isBasicFull {
            return L("The basic row is full (%ld layouts). Move one out first.",
                     LayoutLibrary.maxBasic)
        }
        return nil
    }

    /// Taslağı kitaplığa işler (ekler ya da günceller, liste değiştiyse
    /// taşır); girişin kimliği, reddedilirse nil.
    func apply(to library: inout LayoutLibrary) -> String? {
        guard problem(in: library) == nil else { return nil }
        guard let id else {
            return library.add(layout, name: name, list: list)
        }
        guard let entry = library.entry(id) else { return nil }
        var copy = library
        if id != LayoutLibrary.asIsID {
            copy.update(id, layout: layout, name: name)
        }
        if entry.list != list, !copy.setList(id, to: list) { return nil }
        library = copy
        return id
    }

    /// Izgara ve önizleme için ekran boyutu: düzenler laptop ekranına göre
    /// kurulur; ultra geniş olmayan ilk bilinen ekran, yoksa 16:10.
    static func previewSize(screens: [KnownScreen]) -> CGSize {
        if let screen = screens.first(where: { $0.aspect < WindowLayout.ultrawideAspect }) {
            return screen.visibleSize
        }
        return CGSize(width: 1600, height: 1000)
    }
}
