import CoreGraphics
import Foundation

/// Bir pencerenin "kararlı kimliği" (saf): başlıktan, sayfa numarası,
/// "Edited", kaydedilmemiş nokta, bildirim sayısı gibi oynak parçalar
/// atılır; geriye pencere aynı kaldıkça değişmeyen parçalar kalır.
/// "Bu pencereyi pinle" bu parçalarla kalıcı bir kural yazar.
enum WindowIdentity {

    /// Pinin nasıl yazılacağı.
    enum Resolution: Equatable {
        /// Kalıcı kural, belge yolu ile: yalnız bu dosyayı gösteren pencere.
        case path(String)
        /// Kalıcı kural; başlıkta bu parçaların hepsi geçen pencereler uyar.
        case rule([String])
        /// Kararlı anahtar yok ya da başka açık pencereye de uyuyor: "bu
        /// pencere" sunulmaz, yalnız uygulamanın bütün pencereleri.
        case none

        /// Anahtar için kural taslağı (hedefsiz); anahtar yoksa nil.
        func rule(appName: String, bundleID: String) -> Rule? {
            switch self {
            case .path(let path): return Rule(appName: appName, bundleID: bundleID, tokens: [], path: path)
            case .rule(let tokens): return Rule(appName: appName, bundleID: bundleID, tokens: tokens)
            case .none: return nil
            }
        }

        /// Panelde gösterilecek kısa anahtar.
        var label: String? {
            switch self {
            case .path(let path): return (path as NSString).lastPathComponent
            case .rule(let tokens): return tokens.first
            case .none: return nil
            }
        }
    }

    /// Kararlı parçalar, en belirleyiciden başlayarak (saf). Boş = kararlı
    /// bir şey yok. Hiç başlık değişimi görülmemiş pencere için sezgisel.
    static func candidates(appName: String, bundleID: String, title: String) -> [String] {
        let family = Family(appName: appName, bundleID: bundleID)
        let cleaned = unquote(title)
        var parts: [String]

        switch family {
        case .browser(let safari):
            parts = browserParts(cleaned, appName: appName, safari: safari)
        case .terminal:
            parts = terminalParts(cleaned, appName: appName)
        case .chat:
            parts = []   // başlık hep açık sohbetin adı: kararlı bir şey yok
        default:
            parts = Rule.split(title: cleaned)
                .compactMap { clean(segment: $0, appName: appName, office: family == .office) }
            parts = parts.reversed()   // çalışma alanı/klasör genellikle sondadır
            if family == .outlook, let account = parts.first(where: isEmail) { parts = [account] }
        }

        // Yinelenenleri ve genel başlıkları ele.
        var seen = Set<String>()
        return parts.filter { !isGeneric($0) && seen.insert($0.lowercased()).inserted }
    }

    /// Yalnız başlık sezgisiyle pin kararı (geçmiş ve belge yok). `others` =
    /// aynı anda açık öbür pencereler (kendisi hariç). Anahtar başka
    /// pencereye de uyuyorsa bir sonraki en belirleyici parça eklenir; yine
    /// belirsizse anahtar yok.
    static func resolve(appName: String, bundleID: String, title: String,
                        others: [Router.WindowSnapshot]) -> Resolution {
        narrowed(candidates(appName: appName, bundleID: bundleID, title: title),
                 appName: appName, bundleID: bundleID, title: title, others: others)
    }

    /// Üç katmanlı pin kararı (saf), her uygulama için aynı:
    /// 1. Belge yolu (AXDocument): pencerenin belgesi değiştiği hiç
    ///    görülmediyse ve uygulama belgesi oynayan uygulamalardan değilse.
    /// 2. Başlık geçmişi: başlık değiştiyse değişmeyen parçalar; her parça
    ///    değiştiyse anahtar yok. Safari'de sekme grubu adı araç çubuğundan
    ///    okunduysa doğrudan o (grupsuz pencerede anahtar yok).
    /// 3. Değişim görülmediyse eski sezgi (sayfa no, Edited, sayı atılır).
    /// Anahtar başka açık pencereye de uyuyorsa bir alt katman denenir;
    /// hiçbiri ayırmıyorsa `.none`.
    static func resolve(_ window: Router.WindowSnapshot, others: [Router.WindowSnapshot],
                        history: Observations = Observations()) -> Resolution {
        let app = window.appName, bundle = window.bundleID, title = window.title
        if let path = window.document, history.trustsDocument(of: window) {
            let rule = Rule(appName: app, bundleID: bundle, tokens: [], path: path)
            if !others.contains(where: { rule.matches($0) }) { return .path(path) }
        }
        if let group = window.tabGroup {
            let parts = group.isEmpty || isGeneric(group) ? [] : [group]
            return narrowed(parts, appName: app, bundleID: bundle, title: title, others: others)
        }
        let parts = history.stableSegments(of: window)
            ?? candidates(appName: app, bundleID: bundle, title: title)
        return narrowed(parts, appName: app, bundleID: bundle, title: title, others: others)
    }

    private static func narrowed(_ parts: [String], appName: String, bundleID: String,
                                 title: String, others: [Router.WindowSnapshot]) -> Resolution {
        guard !parts.isEmpty else { return .none }
        // Terminal/Safari'de ek parça oynak (komut, sayfa): daraltma yok,
        // kararlı parça tek başına belirsizse anahtar yok.
        let limit = narrowingLimit(appName: appName, bundleID: bundleID, available: parts.count)
        for count in 1...limit {
            let tokens = Array(parts.prefix(count))
            let rule = Rule(appName: appName, bundleID: bundleID, tokens: tokens)
            // Kendisine uymayan anahtar (ör. saf olmayan temizlik) işe yaramaz.
            guard rule.matches(bundleID: bundleID, appName: appName, title: title) else { continue }
            let clash = others.contains {
                rule.matches($0)
            }
            if !clash { return .rule(tokens) }
        }
        return .none
    }

    // MARK: Gözlem (çalışma anında başlık ve belge geçmişi)

    /// Taramalar boyunca her pencerenin başlık parçaları ve belgesi. Başlık
    /// değiştikçe değişmeyen parçalar daralır; belge değişen uygulama
    /// (ör. VS Code etkin dosyayı bildirir) belge yoluyla anahtarlanmaz.
    struct Observations: Equatable {
        struct Entry: Equatable {
            var lastTitle: String
            /// Görülen bütün başlıklarda geçen parçalar (küçük harf).
            var stable: Set<String>
            var titleChanged = false
            var document: String?
            var documentChanged = false
            /// Başlık değişti ama belge aynı kaldı: belge kararlı.
            var documentHeld = false
        }
        var entries: [CGWindowID: Entry] = [:]
        /// Bir penceresinde belge değiştiği görülen uygulamalar.
        var volatileDocumentApps: Set<String> = []
        /// Başlığı değişirken belgesi aynı kaldığı görülen uygulamalar.
        var stableDocumentApps: Set<String> = []

        init(volatileDocumentApps: Set<String> = [], stableDocumentApps: Set<String> = []) {
            self.volatileDocumentApps = volatileDocumentApps
            self.stableDocumentApps = stableDocumentApps
        }

        private static func appKey(_ window: Router.WindowSnapshot) -> String {
            window.bundleID.isEmpty ? window.appName.lowercased() : window.bundleID
        }

        private static func segments(_ window: Router.WindowSnapshot, title: String) -> [String] {
            WindowIdentity.candidates(appName: window.appName, bundleID: window.bundleID, title: title)
        }

        /// Taramadaki pencereleri işler; görünmeyenler unutulur.
        mutating func observe(_ windows: [Router.WindowSnapshot]) {
            var next: [CGWindowID: Entry] = [:]
            for window in windows {
                let parts = Set(Self.segments(window, title: window.title).map { $0.lowercased() })
                guard var entry = entries[window.id] else {
                    next[window.id] = Entry(lastTitle: window.title, stable: parts,
                                            document: window.document)
                    continue
                }
                let titleDiffers = entry.lastTitle != window.title
                if titleDiffers {
                    entry.lastTitle = window.title
                    entry.stable.formIntersection(parts)
                    entry.titleChanged = true
                }
                let titleMoved = titleDiffers
                if let document = window.document {
                    if let old = entry.document, old != document {
                        entry.documentChanged = true
                        volatileDocumentApps.insert(Self.appKey(window))
                    } else if titleMoved, entry.document == document, !entry.documentChanged {
                        entry.documentHeld = true
                        stableDocumentApps.insert(Self.appKey(window))
                    }
                    entry.document = document
                }
                next[window.id] = entry
            }
            entries = next
        }

        /// Belge yolu anahtar olabilir mi: bu pencerenin ve uygulamanın
        /// belgesi değişirken hiç görülmedi ve belgenin başlık değişimine
        /// dayandığı görüldü (bu pencerede ya da uygulamanın başka
        /// penceresinde). Etkin dosyayı bildiren editörde başlık değişimi
        /// belgeyi de değiştirir: güvenilmez.
        func trustsDocument(of window: Router.WindowSnapshot) -> Bool {
            let app = Self.appKey(window)
            guard window.document != nil, !volatileDocumentApps.contains(app),
                  entries[window.id]?.documentChanged != true else { return false }
            return entries[window.id]?.documentHeld == true || stableDocumentApps.contains(app)
        }

        /// Başlık değiştiyse değişmeyen parçalar (sezgi sırasında, şu anki
        /// yazımıyla; boş = hepsi değişti); değişim görülmediyse nil.
        func stableSegments(of window: Router.WindowSnapshot) -> [String]? {
            guard let entry = entries[window.id], entry.titleChanged else { return nil }
            return Self.segments(window, title: window.title)
                .filter { entry.stable.contains($0.lowercased()) }
        }
    }

    /// Kaç parçaya kadar daraltılabilir.
    private static func narrowingLimit(appName: String, bundleID: String, available: Int) -> Int {
        switch Family(appName: appName, bundleID: bundleID) {
        case .terminal, .browser: return 1
        default: return available
        }
    }

    // MARK: Uygulama aileleri

    private enum Family: Equatable {
        case browser(safari: Bool), terminal, office, outlook, chat, other

        init(appName: String, bundleID: String) {
            let bundle = bundleID.lowercased()
            let name = appName.lowercased()
            if bundle == "com.apple.safari" { self = .browser(safari: true) }
            else if bundle.hasPrefix("com.google.chrome") || bundle.hasPrefix("org.mozilla.firefox")
                        || bundle.hasPrefix("com.brave.browser") || bundle == "com.microsoft.edgemac"
                        || bundle == "company.thebrowser.browser" || bundle.hasPrefix("com.vivaldi")
                        || bundle.hasPrefix("com.operasoftware") {
                self = .browser(safari: false)
            }
            else if bundle == "com.microsoft.outlook" { self = .outlook }
            else if bundle.contains("teams") || name.contains("teams") { self = .chat }
            else if bundle.hasPrefix("com.microsoft.") && ["excel", "word", "powerpoint"].contains(where: name.contains) {
                self = .office
            }
            else if bundle == "com.apple.terminal" || bundle.hasPrefix("com.googlecode.iterm2")
                        || bundle.hasPrefix("com.mitchellh.ghostty") || bundle.hasPrefix("com.cmuxterm")
                        || bundle.hasPrefix("dev.warp") || bundle == "net.kovidgoyal.kitty"
                        || ["terminal", "iterm2", "ghostty", "cmux", "warp", "kitty", "alacritty"].contains(name) {
                self = .terminal
            }
            else { self = .other }
        }
    }

    // MARK: Aileye özgü ayrıştırma

    /// Tarayıcı: Safari'de "Grup — sayfa" biçimi grup adını verir (grup
    /// kararlı, sayfa değil); gruplu olmayan başlık tek parça, sondaki
    /// tarayıcı adı atılır.
    private static func browserParts(_ title: String, appName: String, safari: Bool) -> [String] {
        var text = stripCount(title)
        text = text.replacingOccurrences(
            of: #"\s+[-—–]\s+(Google Chrome|Brave|Arc|Mozilla Firefox|Firefox|Microsoft Edge|Safari|Vivaldi|Opera)$"#,
            with: "", options: .regularExpression)
        if safari, let range = text.range(of: " — ") {
            let group = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            // Sayfa adı oynak: anahtara asla girmez (grup genelse oturum pini).
            return group.isEmpty ? [] : [group]
        }
        let single = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? [] : [single]
    }

    /// Terminal / cmux: "kullanıcı — user@host:dizin — komut — 80×24".
    /// Boyut atılır, "user@host:dizin" dizinsiz "user@host" olur ve öne
    /// geçer; geri kalan parçalar daraltma için sonra gelir.
    private static func terminalParts(_ title: String, appName: String) -> [String] {
        var hosts: [String] = []
        var rest: [String] = []
        for raw in Rule.split(title: title) {
            guard let segment = clean(segment: raw, appName: appName, office: false) else { continue }
            if segment.range(of: #"^\d+\s*[×x]\s*\d+$"#, options: .regularExpression) != nil { continue }
            if segment.contains("@") {
                hosts.append(segment.split(separator: ":", maxSplits: 1).first.map(String.init) ?? segment)
            } else {
                rest.append(segment)
            }
        }
        return hosts + rest
    }

    // MARK: Parça temizliği

    /// Tek bir başlık parçasını temizler; oynak ya da uygulama adıysa nil.
    private static func clean(segment raw: String, appName: String, office: Bool) -> String? {
        var text = stripCount(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // Başta kaydedilmemiş işareti, sonda "*" ya da "(Edited)".
        text = text.replacingOccurrences(of: #"^[●•*]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"\s*(\*|\((edited|modified|bearbeitet|düzenlendi)\))$"#, with: "",
            options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if office {
            text = text.replacingOccurrences(
                of: #"\.(xlsx|xlsm|xlsb|xls|docx|docm|doc|pptx|pptm|ppt|csv)$"#, with: "",
                options: [.regularExpression, .caseInsensitive])
        }
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        // Uygulama adı ("Microsoft Teams", "Visual Studio Code").
        let app = appName.lowercased()
        if lower == app || app.hasSuffix(" " + lower) || lower == "visual studio code"
            && ["code", "visual studio code"].contains(app) { return nil }
        let noise: Set<String> = [
            "edited", "saved", "autosaved", "read-only", "compatibility mode",
            "bearbeitet", "gespeichert", "düzenlendi", "kaydedildi",
        ]
        if noise.contains(lower) { return nil }
        let volatile = [
            #"^(page|seite|sayfa|página)\s+\d+\s+(of|von|de|/)\s+\d+$"#,
            #"^\d+\s+(documents?|dokumente?|belge)\s*,\s*\d+\s+total\s+pages?$"#,
            #"^\d+\s*/\s*\d+$"#,
        ]
        if volatile.contains(where: { lower.range(of: $0, options: .regularExpression) != nil }) { return nil }
        return text
    }

    /// Başta "(3) " ya da sonda " (3)" bildirim sayısını atar.
    private static func stripCount(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\(\d+\)\s*|\s*\(\d+\)$"#, with: "", options: .regularExpression)
    }

    private static func unquote(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    /// Hiçbir şeyi ayırt etmeyen başlıklar.
    static func isGeneric(_ text: String) -> Bool {
        let lower = text.lowercased()
        let names: Set<String> = [
            "untitled", "new tab", "start page", "home", "new window", "adsız", "yeni sekme",
            "untitled window",
        ]
        return text.count < 3 || names.contains(lower)
            || text.range(of: #"^[\d\s.,:/-]+$"#, options: .regularExpression) != nil
    }
}
