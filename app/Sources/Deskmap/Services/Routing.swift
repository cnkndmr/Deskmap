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
        windowID: CGWindowID, bundleID: String, appName: String, title: String
    ) -> Match? {
        if let pinned = sessionPins[windowID] {
            return Match(destination: pinned, ruleID: sessionRuleID, rule: nil)
        }
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
            $0[mode] != nil && $0.matches(bundleID: bundleID, appName: appName, loweredTitle: lowered())
        }), let destination = rule[mode] else { return nil }
        return Match(destination: destination, ruleID: rule.id, rule: rule)
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
