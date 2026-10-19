import CoreGraphics
import Foundation

/// Yönlendirmenin saf (yan etkisiz) kısmı: bir pencere için hangi hedefin
/// geçerli olduğu ve düzen denemelerinin sayımı. Router ile arayüz aynı
/// seçimi buradan yapar; ikisi birbirinden ayrı düşmesin.
enum Routing {

    /// Bir pencereye uyan hedef.
    struct Match: Equatable {
        let destination: Destination
        /// Kuralın kimliği; oturum pini için `Routing.sessionRuleID`.
        let ruleID: String
        /// Eşleşen kalıcı kural; oturum pininde nil.
        let rule: Rule?
    }

    /// Oturum pinlerinin düzen/deneme anahtarlarında kullanılan kural kimliği.
    static let sessionRuleID = "session"

    /// Pencere için geçerli hedef. Oturum pini (pencere kimliği) kalıcı
    /// kuraldan önce gelir; yoksa özgüllük sırasında, bu modda hedefi olan
    /// ilk eşleşen kural. Hedefi olmayan daha özgül bir kural engellemez.
    static func select(
        rules: [Rule], sessionPins: [CGWindowID: Destination], mode: Mode,
        windowID: CGWindowID, bundleID: String, appName: String, title: String,
        document: String? = nil, context: Context? = nil
    ) -> Match? {
        resolve(rules: rules, sessionPins: sessionPins, mode: mode, windowID: windowID,
                bundleID: bundleID, appName: appName, title: title, document: document,
                context: context).match
    }

    // MARK: - Yapışkan bağ (kayma, docs/bug-tables.md §B)

    /// Pencerenin bir kurala bağı. Başlık değişse de pencere kapanana kadar
    /// sürer; yalnız kesin olarak daha özgül bir kural pencereyi alabilir.
    enum Binding: Equatable, Hashable {
        /// Bu kural yerleştirdi. `key`: bağ kurulduğundaki parçalar/yol;
        /// kural yerinde düzenlenip değişirse bağ geçersiz olur.
        case rule(id: String, specificity: Int, key: String)
        /// Yerinde kal (pini kaldırıldı ya da kuralı silindi): yalnız en az
        /// `minimum` özgüllükte bir kural pencereyi alır.
        case stay(minimum: Int)
    }

    /// Router'ın taramada tuttuğu, seçimi etkileyen durum.
    struct Context: Equatable {
        var bindings: [CGWindowID: Binding] = [:]
        /// Yeni açılmış, başlığı henüz genel (uygulama adı) pencereler:
        /// başlık oturana kadar yönlendirilmez.
        var held: Set<CGWindowID> = []
        /// Tek parçalı kurallardan, parçasına bütün başlığı eşit açık bir
        /// pencere olanlar: o pencere açıkken kural yalnız tam eşleşir.
        var exactOwned: Set<String> = []
    }

    /// Genel başlıklı yeni pencere bu kadar süre beklenir (yeni Claude
    /// oturum penceresi "Claude" diye açılır, adını birkaç saniyede alır).
    static let genericTitleGrace: TimeInterval = 8

    /// Başlık genel mi (saf): boş ya da uygulamanın adı.
    static func isGenericTitle(_ title: String, appName: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare(appName) == .orderedSame
    }

    /// Pencere bekletilsin mi (saf): başlığı genel ve ilk görülmesinden bu
    /// yana `genericTitleGrace` geçmedi. `titleRules` false ise (uygulamanın
    /// başlık ya da yol parçalı kuralı yok) beklenecek bir şey yok.
    static func isHeld(title: String, appName: String, firstSeen: Date, now: Date,
                       titleRules: Bool = true) -> Bool {
        titleRules && isGenericTitle(title, appName: appName)
            && now.timeIntervalSince(firstSeen) < genericTitleGrace
    }

    /// Uygulamanın başlık ya da belge yolu parçalı kuralı var mı (saf).
    static func hasTitleRule(_ rules: [Rule], bundleID: String, appName: String) -> Bool {
        rules.contains { !$0.isAppWide && $0.matchesApp(bundleID: bundleID, appName: appName) }
    }

    /// Tam başlık sahibi olan kurallar (saf): tek parçalı, belge yolsuz ve
    /// aynı uygulamanın açık bir penceresinin bütün başlığı parçaya eşit.
    static func exactOwners(rules: [Rule],
                            windows: [(bundleID: String, appName: String, title: String)]) -> Set<String> {
        var owned = Set<String>()
        for rule in rules where rule.tokens.count == 1 && rule.path == nil {
            if windows.contains(where: { rule.isExactTitle(of: $0.bundleID, appName: $0.appName, title: $0.title) }) {
                owned.insert(rule.id)
            }
        }
        return owned
    }

    /// Seçim ve pencerenin yeni bağı (saf). Bağ yoksa (`context` nil) eski
    /// durumsuz seçim: o anki başlığa uyan en özgül kural.
    static func resolve(
        rules: [Rule], sessionPins: [CGWindowID: Destination], mode: Mode,
        windowID: CGWindowID, bundleID: String, appName: String, title: String,
        document: String? = nil, context: Context? = nil
    ) -> (match: Match?, binding: Binding?) {
        if let pinned = sessionPins[windowID] {
            return (Match(destination: pinned, ruleID: sessionRuleID, rule: nil),
                    context?.bindings[windowID])
        }
        guard let context else {
            return (fresh(rules: rules, mode: mode, bundleID: bundleID, appName: appName,
                          title: title, document: document, exactOwned: []), nil)
        }
        let bound = context.bindings[windowID]
        if context.held.contains(windowID) { return (nil, bound) }
        let best = fresh(rules: rules, mode: mode, bundleID: bundleID, appName: appName,
                         title: title, document: document, exactOwned: context.exactOwned)
        func take(_ match: Match?) -> (match: Match?, binding: Binding?) {
            guard let match, let rule = match.rule else { return (nil, bound) }
            return (match, .rule(id: rule.id, specificity: rule.specificity, key: rule.bindingKey))
        }
        switch bound {
        case nil:
            return take(best)
        case .stay(let minimum):
            if let rule = best?.rule, rule.specificity >= minimum { return take(best) }
            return (nil, bound)
        case .rule(let id, let specificity, let key):
            // Kural yerinde düzenlendi (parçalar değişti): bağ yok sayılır,
            // pencere yeni parçalara göre seçilir.
            guard let rule = rules.first(where: { $0.id == id }) else {
                // Kural silindi (haritada pin kaldırıldı): pencere yerinde
                // kalır, genel bir kural onu çekmez.
                if let rule = best?.rule, rule.specificity >= specificity { return take(best) }
                return (nil, .stay(minimum: specificity))
            }
            if rule.bindingKey != key {
                // Yerinde düzenlendi: bağ düşer, yeni parçalara göre seçilir.
                let fresh = take(best)
                return (fresh.match, fresh.match == nil ? nil : fresh.binding)
            }
            guard let destination = rule[mode], rule.matchesApp(bundleID: bundleID, appName: appName),
                  !(context.exactOwned.contains(id) && !rule.isExactTitle(
                    of: bundleID, appName: appName, title: title))
            else {
                // Bu modda hedefi yok (öbür kurulum) ya da tam başlık sahibi
                // açık: bağ korunur, kural geri gelince yine geçerli. Genel
                // kural bu arada pencereyi çekmez.
                if let better = best?.rule, better.specificity > specificity { return take(best) }
                return (nil, bound)
            }
            if let better = best?.rule, better.id != id, better.specificity > specificity {
                return take(best)
            }
            return (Match(destination: destination, ruleID: id, rule: rule), bound)
        }
    }

    /// Pini kaldırılan pencerenin bağı (saf): yerinde kalır; şu an ona uyan
    /// kuraldan daha özgül bir kural gelmedikçe taşınmaz.
    static func bindingAfterUnpin(rules: [Rule], mode: Mode, bundleID: String, appName: String,
                                  title: String, document: String? = nil) -> Binding {
        let current = fresh(rules: rules, mode: mode, bundleID: bundleID, appName: appName,
                            title: title, document: document, exactOwned: [])
        return .stay(minimum: (current?.rule?.specificity ?? -1) + 1)
    }

    /// Kapanan pencerelerin bağları budanır (saf).
    static func prunedBindings(_ bindings: [CGWindowID: Binding],
                               alive: Set<CGWindowID>) -> [CGWindowID: Binding] {
        bindings.filter { alive.contains($0.key) }
    }

    /// Durumsuz seçim: o anki başlığa uyan, bu modda hedefi olan en özgül
    /// kural; tam başlık sahibi olan kural yalnız tam eşleşmede.
    private static func fresh(
        rules: [Rule], mode: Mode, bundleID: String, appName: String, title: String,
        document: String?, exactOwned: Set<String>
    ) -> Match? {
        // Başlık en fazla bir kez küçültülür (yalnızca başlığa bakan bir
        // kural sırası gelirse); `Rule.matches` kararı aynı.
        var loweredTitle: String?
        func lowered() -> String {
            if let loweredTitle { return loweredTitle }
            let value = title.lowercased()
            loweredTitle = value
            return value
        }
        guard let rule = rules.bySpecificity.first(where: {
            $0[mode] != nil && $0.matches(bundleID: bundleID, appName: appName, loweredTitle: lowered(),
                                           document: document)
                && !(exactOwned.contains($0.id)
                     && !$0.isExactTitle(of: bundleID, appName: appName, title: title))
        }), let destination = rule[mode] else { return nil }
        return Match(destination: destination, ruleID: rule.id, rule: rule)
    }

    // MARK: - "Neden burada?"

    /// Pencere satırının ipucu (saf): hangi kural (ya da oturum pini) hangi
    /// hedefe gönderiyor. Yeni pencere-başı durum tutulmaz; seçim her
    /// seferinde `select` ile yeniden yapılır. Eşleşme yoksa nil.
    static func explanation(for match: Match?, screenName: String?) -> String? {
        reason(for: match, screenName: screenName).map { L("Why here: %@", $0) }
    }

    /// Açıklamanın "Neden burada:" öneki olmadan gövdesi (saf; ayrıntı
    /// sütunundaki "Neden burada?" kutusu kendi başlığıyla gösterir).
    static func reason(for match: Match?, screenName: String?) -> String? {
        guard let match else { return nil }
        let destination = match.destination
        let target = L("%@ · Desktop %ld",
                       DisplayRoles.displayName(role: destination.screen, name: screenName),
                       destination.desktop)
        let layout = L("Layout: %@", destination.layout.label)
        guard let rule = match.rule else {
            return L("temporary pin for this window → %@ (%@)", target, layout)
        }
        let name = ([rule.appName.isEmpty ? rule.bundleID : rule.appName]
                    + (rule.path != nil ? [rule.title] : rule.tokens))
            .joined(separator: " · ")
        return L("pin \"%@\" → %@ (%@)", name, target, layout)
    }

    // MARK: - Düzen denemeleri

    /// Uygulama düzeni bu kadar denemeden sonra da kabul etmezse bırakılır
    /// (ör. en küçük boyut kısıtı olan pencereler). Çerçeve artık pencere
    /// görünürken verildiği için az deneme yeter.
    static let maxAttempts = 6
    /// İlk denemeler hızlı ardışık; sonrası olaylara ve zamanlayıcıya kalır.
    static let quickAttempts = 4

    /// Bir düzen denemesinin sonucunu işler. Oturduysa anahtar "uygulandı"
    /// kümesine girer ve sayaç silinir; oturmadıysa sayaç artar, sınıra
    /// varınca vazgeçilip "uygulandı" sayılır. Kısa süre sonra yeniden
    /// denenmesi gerekiyorsa (ilk hızlı denemeler) true döner.
    static func recordLayoutAttempt(
        key: String, placed: Bool, applied: inout Set<String>, attempts: inout [String: Int]
    ) -> Bool {
        if placed {
            applied.insert(key)
            attempts[key] = nil
            return false
        }
        let count = (attempts[key] ?? 0) + 1
        attempts[key] = count
        if count >= maxAttempts {
            applied.insert(key)
            attempts[key] = nil
            return false
        }
        return count <= quickAttempts
    }

    // MARK: - Masaüstü taşıma denemeleri

    /// Deneme sayacı anahtarı bir masaüstü taşımasına mı ait (düzene değil).
    static func isMoveKey(_ key: String) -> Bool { key.contains("|move|") }

    /// Masaüstü taşıması bu kadar denemeden sonra da tutmazsa (macOS
    /// taşımayı reddediyor / özel API çalışmıyor) o pencere için bir süre
    /// bırakılır; pencere hedefe varınca ya da bellek sıfırlanınca sayaç silinir.
    static let maxMoveAttempts = 6
    /// Vazgeçilen taşıma bu kadar süre sonra yeniden bir deneme turu alır
    /// (kalıcı vazgeçme yok: macOS'un geçici reddi sonsuza kadar sürmesin).
    static let moveRetryInterval: TimeInterval = 60

    /// Bir masaüstü taşıması denenmeli mi? Deneniyorsa sayaç artar, zaman
    /// damgası yenilenir ve deneme sırası döner (1...`maxMoveAttempts`).
    /// Sınıra varılmışsa nil; ancak son denemeden bu yana
    /// `moveRetryInterval` geçtiyse sayaç sıfırlanıp yeni tur başlar.
    static func recordMoveAttempt(
        key: String, now: Date, attempts: inout [String: Int], lastAttempts: inout [String: Date]
    ) -> Int? {
        var count = attempts[key] ?? 0
        if count >= maxMoveAttempts {
            guard let last = lastAttempts[key],
                  now.timeIntervalSince(last) >= moveRetryInterval else { return nil }
            count = 0
        }
        count += 1
        attempts[key] = count
        lastAttempts[key] = now
        return count
    }
}

/// Yönlendirme nesli (P0-2). Ana aktör değişimde `advance()` çağırır; arka
/// plandaki tarama başta aldığı `token`'la her yan etkiden önce hâlâ güncel
/// olup olmadığına bakar. Kilitli sayaç: iki iş parçacığından okunur.
final class RoutingGeneration: @unchecked Sendable {

    struct Token: Sendable {
        fileprivate let owner: RoutingGeneration
        let value: UInt64
        /// Bu token alındığından beri nesil değişmedi mi.
        var isCurrent: Bool { owner.current == value }
    }

    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance() {
        lock.lock(); defer { lock.unlock() }
        value &+= 1
    }

    func token() -> Token { Token(owner: self, value: current) }
}

/// Bu oturumda denenmiş plan/silme hedefleri. Hedef deneme sürerken ve
/// başarısız olduktan sonra tutulur (başarısızlık döngüsü olmasın); biten
/// ya da yarıda kesilen deneme hedefi bırakır, çünkü aynı mod|ekran|sayı
/// sonradan meşru olarak yeniden planlanabilir.
struct PlannedAttempts {

    enum Outcome: Equatable {
        /// Kuyruk boşaldı ya da plan karşılandı.
        case done
        /// Ekran değişimi araya girdi; hiçbir şey başarısız olmadı.
        case interrupted
        /// Gerçek başarısızlık: bu oturumda yeniden denenmez.
        case failed
    }

    private var keys: Set<String> = []

    /// Deneme başlayabilir mi; başlarsa hedef tutulur.
    mutating func begin(_ key: String) -> Bool {
        keys.insert(key).inserted
    }

    mutating func finish(_ key: String, _ outcome: Outcome) {
        if outcome != .failed { keys.remove(key) }
    }

    /// Ekleme döngüsünün sonucu (saf): plan karşılandıysa bitti; araya
    /// ekran değişimi girdiyse ya da ekran artık okunamıyorsa kesildi;
    /// deneme tavanı dolup sayı hâlâ eksikse başarısız.
    static func addOutcome(live: Int?, want: Int, interrupted: Bool) -> Outcome {
        guard let live else { return .interrupted }
        if live >= want { return .done }
        return interrupted ? .interrupted : .failed
    }
}
