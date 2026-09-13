import Foundation

/// Tek seviyeli geri alma. Uygulamada onay diyaloğu yok; pin kaldırma,
/// profil silme gibi yıkıcı işlemlerden hemen önce belgenin tamamı burada
/// saklanır ve alt çubukta kısa süre "Geri al" gösterilir. Yeni bir kayıt
/// öncekinin yerini alır; geri alınca tampon boşalır.
///
/// Kayıt işlemden sonraki belgeyi de tutar: belge başka bir yoldan (yeni
/// pin, düzen adımı, profil geçişi, URL komutu) değişirse kayıt geçersizdir,
/// çünkü geri alma o değişikliği de silerdi. `Store` her belge değişiminde
/// `invalidate(ifChangedFrom:)` çağırır.
struct UndoBuffer: Equatable {

    struct Entry: Equatable {
        /// Alt çubukta gösterilen kısa açıklama ("Pin kaldırıldı").
        let label: String
        /// İşlemden önceki belge; geri alma bunu yükler.
        let before: Document
        /// İşlemden hemen sonraki belge; geçerlilik denetimi için.
        let after: Document
        let at: Date
        /// Belge dışında kalan durumu (oturum pinleri) geri alan eşlik
        /// kapanışı; geri almada belge yüklendikten sonra çalışır.
        let companion: (() -> Void)?

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.label == rhs.label && lhs.before == rhs.before
                && lhs.after == rhs.after && lhs.at == rhs.at
        }
    }

    private(set) var entry: Entry?

    /// "Geri al" alt çubukta bu kadar süre görünür; sonrası sessizce düşer.
    static let visibleFor: TimeInterval = 10

    var isEmpty: Bool { entry == nil }

    /// Yıkıcı işlemden hemen sonra çağrılır; önceki kaydın yerine geçer.
    mutating func record(_ label: String, before: Document, after: Document,
                         companion: (() -> Void)? = nil, at: Date = Date()) {
        entry = Entry(label: label, before: before, after: after, at: at, companion: companion)
    }

    /// Saklanan kaydı verir ve tamponu boşaltır.
    mutating func take() -> Entry? {
        defer { entry = nil }
        return entry
    }

    mutating func clear() { entry = nil }

    /// Verilen anda alt çubukta gösterilmeli mi?
    func isVisible(at now: Date) -> Bool {
        guard let entry else { return false }
        return now.timeIntervalSince(entry.at) < Self.visibleFor
    }

    /// Görünürlüğün biteceği an (alt çubuğun yenilenme zamanı).
    var expiry: Date? { entry.map { $0.at.addingTimeInterval(Self.visibleFor) } }

    // MARK: - Geçerlilik

    /// Kayıt hâlâ geri alınabilir mi: şu anki belge, işlemden hemen sonraki
    /// belgeyle (geri almanın dokunmadığı alanlar dışında) aynı olmalı. Boş
    /// tampon geçerli sayılır (düşürülecek bir şey yok).
    func isStillValid(current: Document) -> Bool {
        guard let entry else { return true }
        return Self.matches(entry.after, current)
    }

    /// Belge kayıttan sonra başka bir yoldan değiştiyse kaydı düşürür.
    mutating func invalidate(ifChangedFrom current: Document) {
        if !isStillValid(current: current) { entry = nil }
    }

    /// İki belge geri alma açısından aynı mı? Açık/kapalı anahtarı ve
    /// tanınan ekranlar işlemle ilgisizdir, geri almada da şu anki değerleri
    /// korunur; aktif profilin kayıtlı kuralları üst düzey `rules` ile
    /// eşitlenip karşılaştırılır (gecikmeli `syncActiveProfile` kaydı
    /// düşürmesin).
    static func matches(_ a: Document, _ b: Document) -> Bool {
        var a = a, b = b
        a.enabled = b.enabled
        a.screens = b.screens
        a.syncActiveProfile()
        b.syncActiveProfile()
        return a == b
    }
}
