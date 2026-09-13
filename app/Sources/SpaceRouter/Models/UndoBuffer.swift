import Foundation

/// Tek seviyeli geri alma. Uygulamada onay diyaloğu yok; pin kaldırma,
/// profil silme gibi yıkıcı işlemlerden hemen önce belgenin tamamı burada
/// saklanır ve alt çubukta kısa süre "Geri al" gösterilir. Yeni bir kayıt
/// öncekinin yerini alır; geri alınca tampon boşalır.
struct UndoBuffer: Equatable {

    struct Entry: Equatable {
        /// Alt çubukta gösterilen kısa açıklama ("Pin kaldırıldı").
        let label: String
        /// İşlemden önceki belge.
        let document: Document
        let at: Date
    }

    private(set) var entry: Entry?

    /// "Geri al" alt çubukta bu kadar süre görünür; sonrası sessizce düşer.
    static let visibleFor: TimeInterval = 10

    var isEmpty: Bool { entry == nil }

    /// Yıkıcı işlemden hemen önce çağrılır; önceki kaydın yerine geçer.
    mutating func record(_ label: String, document: Document, at: Date = Date()) {
        entry = Entry(label: label, document: document, at: at)
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
}
