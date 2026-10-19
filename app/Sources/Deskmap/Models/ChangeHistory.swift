import Foundation

/// Oturumluk ayar geçmişi (çok adımlı geri al / yinele). Uygulamada onay
/// diyaloğu yok; her ayar değişikliği burada bir giriş olur ve ⌘Z / ⇧⌘Z ya
/// da "Son hareketler › Değişiklikler" listesiyle herhangi bir ana dönülür.
/// Diske yazılmaz; Deskmap kapanınca biter.
///
/// Zaman çizgisi: başlangıç durumu (`origin`, "Deskmap açıldı") ve onu
/// izleyen girişler, en eskisi başta. `cursor` uygulanmış giriş sayısıdır:
/// 0 = başlangıç durumu, `entries.count` = en yeni değişiklik. İmlecin
/// ötesindekiler yinelenebilir; imleç gerideyken gelen yeni değişiklik o dalı
/// siler, ama silinen dal saklanır: yeni değişikliği geri almak dalı geri
/// getirir.
struct ChangeHistory {

    struct Entry: Identifiable {
        let id: Int
        /// Listede ve alt çubukta gösterilen kısa açıklama ("Pin kaldırıldı").
        let label: String
        let at: Date
        /// İşlemden önceki ve hemen sonraki belge.
        let before: Document
        var after: Document
        /// Belge dışında kalan durumu (oturum pinleri, geçiş dosyası) geri
        /// alan eşlik kapanışı; geri almada belge yüklendikten sonra çalışır.
        /// Kapanışlı giriş geri alınabilir ama yinelenemez.
        let companion: (() -> Void)?
        /// Kendiliğinden gelen ardışık değişiklikler (ad bağları, plan
        /// kuyruğu) aynı etiketle tek girişte birleşir.
        let coalesces: Bool

        var isRedoable: Bool { companion == nil }
    }

    /// Silinen yinele dalı: yeni değişiklik (`causeID`) geri alınınca yerine gelir.
    struct Discarded {
        let entries: [Entry]
        let causeID: Int
        let at: Date
    }

    /// İmlecin taşınması için Store'un uygulayacağı adım.
    struct Move {
        /// Yüklenecek belge (açık/kapalı ve ekranlar Store'da korunur).
        let document: Document
        /// Geri alınan girişlerin eşlik kapanışları, en yenisi başta.
        let companions: [() -> Void]
    }

    /// En fazla bu kadar giriş tutulur; en eski düşer, başlangıç satırı en
    /// eski korunan duruma kayar.
    static let limit = 50
    /// "N adım silindi · Geri al" uyarısı alt çubukta bu kadar kalır.
    static let discardNoticeFor: TimeInterval = 6

    private(set) var origin: Document
    private(set) var originAt: Date
    /// Başlangıç satırı artık açılış durumu değil (sınır yüzünden kaydı).
    private(set) var originTrimmed = false
    private(set) var entries: [Entry] = []
    private(set) var cursor = 0
    private(set) var discarded: Discarded?
    private var nextID = 1

    init(origin: Document = Document(), at: Date = Date()) {
        self.origin = origin
        self.originAt = at
    }

    // MARK: - Durum

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < entries.count && entries[cursor].isRedoable }
    /// ⌘Z'nin geri alacağı giriş.
    var undoEntry: Entry? { cursor > 0 ? entries[cursor - 1] : nil }
    /// ⇧⌘Z'nin yineleyeceği giriş (yinelenemiyorsa da verilir).
    var redoEntry: Entry? { cursor < entries.count ? entries[cursor] : nil }

    /// `position` konumuna (0 = başlangıç, i = i. girişten hemen sonra)
    /// gidilebilir mi? İleri giderken yolda yinelenemeyen giriş olmamalı.
    func canMove(to position: Int) -> Bool {
        guard (0...entries.count).contains(position), position != cursor else { return false }
        if position < cursor { return true }
        return entries[cursor..<position].allSatisfy(\.isRedoable)
    }

    /// Alt çubuktaki dal silme uyarısı gösterilmeli mi?
    func discardNoticeVisible(at now: Date) -> Bool {
        guard let discarded else { return false }
        return now.timeIntervalSince(discarded.at) < Self.discardNoticeFor
    }

    var discardNoticeExpiry: Date? { discarded?.at.addingTimeInterval(Self.discardNoticeFor) }

    // MARK: - Kayıt

    /// Yeni değişiklik. İmleç gerideyse yinele dalı silinir (saklanır);
    /// `coalesce` ise en yeni giriş aynı etiketli birleşen girişse ona eklenir.
    mutating func record(_ label: String, before: Document, after: Document,
                         companion: (() -> Void)? = nil, coalesce: Bool = false,
                         at: Date = Date()) {
        if coalesce, companion == nil, cursor == entries.count, cursor > 0,
           entries[cursor - 1].coalesces, entries[cursor - 1].label == label {
            entries[cursor - 1].after = after
            return
        }
        let entry = Entry(id: nextID, label: label, at: at, before: before, after: after,
                          companion: companion, coalesces: coalesce)
        nextID += 1
        if cursor < entries.count {
            discarded = Discarded(entries: Array(entries[cursor...]), causeID: entry.id, at: at)
            entries.removeSubrange(cursor...)
        } else {
            discarded = nil
        }
        entries.append(entry)
        cursor = entries.count
        if entries.count > Self.limit {
            let dropped = entries.removeFirst()
            origin = dropped.after
            originAt = dropped.at
            originTrimmed = true
            cursor -= 1
        }
    }

    // MARK: - Gezinme

    /// Bir adım geri.
    mutating func undo() -> Move? { move(to: cursor - 1) }

    /// Bir adım ileri (yinelenebilir giriş varsa).
    mutating func redo() -> Move? { move(to: cursor + 1) }

    /// İmleci `position` konumuna taşır (birden çok adım; yeni giriş yok).
    /// Silinmiş bir dal varken dalı silen değişiklik geri alınırsa dal geri gelir.
    mutating func move(to position: Int) -> Move? {
        guard canMove(to: position) else { return nil }
        var companions: [() -> Void] = []
        var target = position
        if target < cursor, let discarded, cursor == entries.count,
           entries.last?.id == discarded.causeID {
            let cause = entries.removeLast()
            cause.companion.map { companions.append($0) }
            cursor -= 1
            entries.append(contentsOf: discarded.entries)
            self.discarded = nil
            target = min(target, cursor)
        } else if target != cursor {
            discarded = nil
        }
        if target < cursor {
            for i in stride(from: cursor - 1, through: target, by: -1) {
                entries[i].companion.map { companions.append($0) }
            }
        }
        cursor = target
        return Move(document: document(at: target), companions: companions)
    }

    /// `position` konumundaki belge (0 = başlangıç durumu).
    func document(at position: Int) -> Document {
        position == 0 ? origin : entries[position - 1].after
    }

    // MARK: - Gürültü

    /// İki belge geçmiş açısından aynı mı? Açık/kapalı anahtarı ve tanınan
    /// ekranlar ayar değildir (gezinmede şu anki değerleri korunur); aktif
    /// profilin kayıtlı kuralları üst düzey `rules` ile eşitlenir (gecikmeli
    /// `syncActiveProfile` giriş üretmesin) ve ad önbellekleri aynı canlı
    /// durumla yenilenip karşılaştırılır.
    static func matches(_ a: Document, _ b: Document, live: LiveDesktops? = nil) -> Bool {
        var a = a, b = b
        a.enabled = b.enabled
        a.screens = b.screens
        a.displayRoles = b.displayRoles
        a.syncActiveProfile()
        b.syncActiveProfile()
        if a == b { return true }
        a.refreshNameCaches(live: live)
        b.refreshNameCaches(live: live)
        a.syncActiveProfile()
        b.syncActiveProfile()
        return a == b
    }
}
