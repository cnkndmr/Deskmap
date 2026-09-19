import CoreGraphics
import Foundation

/// Masaüstü taşımasının bu Mac'te gerçekten çalışıp çalışmadığı (saf).
///
/// SkyLight'ın taşıma yolları sessizce başarı döndürüp pencereyi
/// taşımayabilir (Hammerspoon #3698, yabai #2788). Her taşıma sonraki
/// taramada `spaces(of:)` ile doğrulanır; farklı pencerelerde art arda
/// doğrulanamayan taşımalar devre kesiciyi açar ve düşük moda geçilir:
/// ekran ve düzen uygulanmaya devam eder, masaüstü taşıma durur.
struct MoveHealth: Equatable {

    enum State: Equatable {
        /// Henüz doğrulanmış ya da başarısız taşıma yok.
        case unknown
        /// En az bir taşıma doğrulandı.
        case working
        /// Devre kesici açık: masaüstü taşıması durduruldu.
        case degraded
    }

    private(set) var state: State = .unknown
    /// Son doğrulanmış taşımadan bu yana doğrulanamayan taşıma sayısı.
    private(set) var consecutiveFailures = 0
    /// Bu başarısızlıkların ait olduğu pencereler.
    private(set) var failedWindows: Set<CGWindowID> = []

    /// Bu kadar art arda doğrulanamayan taşıma...
    static let failureLimit = 4
    /// ...en az bu kadar farklı pencerede olursa devre açılır. Tek bir
    /// inatçı pencere (taşımayı reddeden uygulama) bütün taşımayı durdurmasın.
    static let minDistinctWindows = 2

    var movesAllowed: Bool { state != .degraded }

    /// Bir taşımanın doğrulama sonucunu işler. Durum değiştiyse true.
    @discardableResult
    mutating func record(window: CGWindowID, verified: Bool) -> Bool {
        let before = state
        if verified {
            consecutiveFailures = 0
            failedWindows = []
            if state == .unknown { state = .working }
        } else if state != .degraded {
            consecutiveFailures += 1
            failedWindows.insert(window)
            if consecutiveFailures >= Self.failureLimit,
               failedWindows.count >= Self.minDistinctWindows {
                state = .degraded
            }
        }
        return state != before
    }

    /// Kullanıcı "yeniden dene" dedi: devre kapanır, sayaç sıfırlanır.
    mutating func reset() {
        self = MoveHealth()
    }
}

/// Doğrulanmayı bekleyen bir taşıma.
struct PendingMove: Equatable {
    let space: UInt64
    let issuedAt: Date

    /// Eşzamansız taşımanın yerleşmesi için beklenen en kısa süre.
    static let settleDelay: TimeInterval = 0.5
    /// Bu süre içinde pencerenin space durumu okunamazsa doğrulamadan
    /// vazgeçilir (sayılmaz): pencere kapanmış ya da görünmüyor olabilir.
    static let expiry: TimeInterval = 10

    /// Bekleyen taşımaları bu taramada okunan space'lerle karşılaştırır
    /// (saf). `observed[id]` nil ya da boşsa durum bilinmiyor demektir;
    /// süre dolana kadar beklenir. Dönen `results` sırası pencere
    /// numarasına göredir.
    static func verify(
        pending: [CGWindowID: PendingMove], observed: [CGWindowID: [UInt64]], now: Date
    ) -> (results: [(window: CGWindowID, verified: Bool)], remaining: [CGWindowID: PendingMove]) {
        var results: [(window: CGWindowID, verified: Bool)] = []
        var remaining: [CGWindowID: PendingMove] = [:]
        for (id, move) in pending.sorted(by: { $0.key < $1.key }) {
            let age = now.timeIntervalSince(move.issuedAt)
            if age < settleDelay {
                remaining[id] = move
                continue
            }
            guard let spaces = observed[id], !spaces.isEmpty else {
                if age < expiry { remaining[id] = move }
                continue
            }
            results.append((id, spaces.contains(move.space)))
        }
        return (results, remaining)
    }
}
