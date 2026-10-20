import CoreGraphics
import Foundation

/// Mission Control'de başka ekrana sürüklenen masaüstünü geri almak
/// (Tablo E). macOS'ta bir space'i kimliğiyle başka ekrana taşıyan SIP'siz
/// çağrı yok; geri alma "eski ekrana masaüstü ekle + pencereleri taşı +
/// taşınanı sil" planıdır ve `PlanExecutor` ile yürür. Sayı ve oturum
/// pinleri değişmez (Mission Control taşıması onları da kaydırmadı); yalnız
/// adlar içerikle gider (R5) ve izlemenin (P3) taşıdığı plan girdisi geri döner.
enum DesktopRevert {

    /// Ayarlar: Mission Control'de başka ekrana sürüklenen masaüstü.
    enum Setting: String, Codable, CaseIterable, Sendable {
        /// Kendiliğinden geri al (SE1, varsayılan).
        case revert
        /// Kart göster, "Geri al" düğmesiyle.
        case ask
        /// Bugünkü izleme (B.2 satır 12, SE7).
        case leave

        static let defaultValue: Setting = .revert
    }

    /// Ekran değiştiren masaüstü: `from` rolünün `fromDesktop`. sırasından
    /// `to` rolünün `toDesktop`. sırasına (1 tabanlı, normal masaüstüleri).
    struct Crossing: Equatable, Hashable, Sendable {
        var space: UInt64
        var from: String
        var fromDesktop: Int
        var to: String
        var toDesktop: Int
    }

    enum Decision: Equatable {
        case revert
        /// Kart, "Geri al" düğmesiyle (Sor ayarı ya da Deskmap kapalıyken).
        case ask
        /// İzle (bugünkü davranış), kart yok.
        case leave
        /// Geri alınmalıydı ama masaüstü taşıma kapalı: kart, işlem yok.
        case blocked
    }

    struct Context {
        var setting: Setting
        /// Değişikliği Deskmap çalışırken gördü (açılıştaki ilk karşılaştırma değil).
        var observedLive: Bool
        var movesAllowed: Bool
        var readOnly: Bool
        /// Onay bekleyen monitör rolleri (K6).
        var heldRoles: Set<String>
        var lastScreenChange: Date?
        var lastWake: Date?
        /// Geri almanın açtığı space → zamanı (SE3).
        var recentReverts: [UInt64: Date]
        var now: Date
    }

    /// Ekran bildiriminden sonra bu kadar geri alma yok (E3.5).
    static let screenQuiet: TimeInterval = 15
    /// Uyanmadan sonra bu kadar geri alma yok (E3.4).
    static let wakeQuiet: TimeInterval = 60
    /// Geri alınan masaüstü bu süre içinde yine taşınırsa kasıtlı (SE3).
    static let repeatWindow: TimeInterval = 60

    /// Kayıtlı ve canlı rol → masaüstü listelerinden ekran değiştiren
    /// space'ler (saf). Yalnız iki listede de olan roller sayılır: rolü
    /// kaybolan ya da yeni gelen ekran bir geçiştir, taşıma değil.
    static func crossings(before: [String: [UInt64]], after: [String: [UInt64]]) -> [Crossing] {
        var place: [UInt64: (role: String, desktop: Int)] = [:]
        for (role, list) in after where before[role] != nil {
            for (index, space) in list.enumerated() { place[space] = (role, index + 1) }
        }
        var result: [Crossing] = []
        for role in before.keys.sorted() where after[role] != nil {
            for (index, space) in (before[role] ?? []).enumerated() {
                guard let now = place[space], now.role != role else { continue }
                result.append(Crossing(space: space, from: role, fromDesktop: index + 1,
                                       to: now.role, toDesktop: now.desktop))
            }
        }
        return result
    }

    /// Ne yapılacağı (saf, Tablo E kararları SE1–SE7).
    static func decide(_ crossing: Crossing, _ context: Context) -> Decision {
        if context.setting == .leave || context.readOnly { return .leave }
        if context.heldRoles.contains(crossing.from) || context.heldRoles.contains(crossing.to) {
            return .leave
        }
        // Deskmap kapalıyken oldu (SE2): yalnız kart; nedeni (kullanıcı mı,
        // macOS mu) bilinmediği için ekran/uyanma süreleri burada sayılmaz.
        if !context.observedLive { return context.movesAllowed ? .ask : .blocked }
        if let change = context.lastScreenChange,
           context.now.timeIntervalSince(change) < screenQuiet { return .leave }
        if let wake = context.lastWake, context.now.timeIntervalSince(wake) < wakeQuiet { return .leave }
        if let reverted = context.recentReverts[crossing.space],
           context.now.timeIntervalSince(reverted) < repeatWindow { return .leave }
        if !context.movesAllowed { return .blocked }
        if context.setting == .ask { return .ask }
        return .revert
    }

    /// Geri alma planı (saf): `from` rolünün sonuna bir masaüstü; o rolün
    /// `fromDesktop`. sırası ve sonrasının içeriği birer kayar (SE4); taşınan
    /// masaüstünün içeriği eski sırasına; taşınan masaüstü silinir (boşsa,
    /// yürütücü denetler, SE5). Masaüstü artık `to` rolünde değilse ya da
    /// oranın tek masaüstüyse nil.
    static func plan(_ crossing: Crossing, live: [String: [UInt64]],
                     contents: [UInt64: [CGWindowID]]) -> PlanApply.Output? {
        guard let source = live[crossing.to], source.contains(crossing.space), source.count > 1,
              let home = live[crossing.from], !home.contains(crossing.space) else { return nil }
        let target = min(max(crossing.fromDesktop, 1), home.count + 1)
        var plan = PlanApply.Output()
        plan.creates = [crossing.from: 1]
        func carry(_ space: UInt64, to desktop: Int) {
            let slot = Slot(screen: crossing.from, desktop: desktop)
            plan.spaceMap[space] = slot
            for window in contents[space] ?? [] { plan.moves.append(.init(window: window, to: slot)) }
        }
        for index in (target - 1)..<home.count { carry(home[index], to: index + 2) }
        carry(crossing.space, to: target)
        plan.removals = [crossing.space]
        plan.decisions = ["revert a desktop moved from \(crossing.from) to \(crossing.to) in Mission Control"]
        return plan
    }

    /// Geri almayı yürütür: önce masaüstü açılır (açılamazsa hiçbir şeye
    /// dokunulmaz, E2.7: `PlanExecutor` başarısız açılıştan sonra da taşırdı,
    /// kayan içerik yanlış masaüstüne giderdi), sonra plan yeni canlı sırayla
    /// yeniden kurulup açılışsız yürütülür. Plan kurulamazsa nil.
    @MainActor
    static func run(_ crossing: Crossing, contents: [UInt64: [CGWindowID]],
                    windowSpaces: [CGWindowID: UInt64],
                    world: PlanExecutor.World) async -> PlanExecutor.Outcome? {
        let live = world.liveSpaces()
        guard plan(crossing, live: live, contents: contents) != nil else { return nil }
        var failed = PlanExecutor.Outcome()
        if world.shouldAbort() {
            failed.aborted = true
            failed.abortReason = "interrupted"
            return failed
        }
        guard await world.addDesktop(crossing.from) else {
            failed.failedCreates = [crossing.from]
            Log.app.error("Revert: could not add a desktop to \(crossing.from, privacy: .public); nothing changed")
            return failed
        }
        let added = world.liveSpaces()
        // Açılan masaüstü sona gelmediyse ya da sıra kaydıysa sıralar yanlış
        // masaüstünü gösterir: taşıma yapılmaz.
        guard PlanExecutor.consistent(added, with: live),
              (added[crossing.from]?.count ?? 0) == (live[crossing.from]?.count ?? 0) + 1,
              // Sıralar açılıştan önceki listeye göre; yürütücü yeni listede çözer.
              var next = plan(crossing, live: live, contents: contents)
        else {
            failed.created = 1
            failed.createdSpaces = (added[crossing.from] ?? []).filter { !(live[crossing.from] ?? []).contains($0) }
            failed.aborted = true
            failed.abortReason = "desktops changed while adding"
            return failed
        }
        next.creates = [:]
        var outcome = await PlanExecutor.run(next, expected: added, windowSpaces: windowSpaces,
                                             allowRemovals: true, world: world)
        outcome.created += 1
        outcome.createdSpaces = (added[crossing.from] ?? []).filter { !(live[crossing.from] ?? []).contains($0) }
        return outcome
    }

    enum Result: Equatable {
        /// Geri alındı; ad bu space'te.
        case reverted(newSpace: UInt64)
        /// Geri alındı ama taşınan masaüstü boşalmadı, silinmedi (SE5).
        case partial(newSpace: UInt64, stayed: Int)
        /// Hiçbir şey değişmedi ya da pencereler taşınamadan kesildi.
        case failed
    }

    /// Yürütme sonucu (saf).
    static func result(_ outcome: PlanExecutor.Outcome, crossing: Crossing) -> Result {
        guard outcome.created > 0, let newSpace = outcome.spaceMap[crossing.space] else { return .failed }
        if outcome.removedSpaces.contains(crossing.space) { return .reverted(newSpace: newSpace) }
        return .partial(newSpace: newSpace, stayed: max(outcome.failedMoves.count, 1))
    }

    /// "Böyle kalsın" (E4.4): geri alınanı kullanıcının bıraktığı yere
    /// götüren ters taşıma; aynı pin kaydırmasız yolla yürür.
    static func reverse(_ crossing: Crossing, newSpace: UInt64) -> Crossing {
        Crossing(space: newSpace, from: crossing.to, fromDesktop: crossing.toDesktop,
                 to: crossing.from, toDesktop: crossing.fromDesktop)
    }
}

extension Document {

    /// Tablo E (E5.2): izlemenin (P3) `source` listesinin `desktop`. sırasına
    /// taşıdığı plan girdisini `target` listesinin `index`. sırasına geri
    /// koyar; bütün profillerde (izleme de bütün profilleri yazar). Sayı
    /// pinlerine dokunmaz.
    mutating func returnPlanEntry(from source: String, desktop: Int, to target: String, at index: Int,
                                  mode: Mode) {
        guard source != target, index >= 1 else { return }
        for profile in profiles {
            inProfileScope(profile.id) { doc in
                var from = doc.plans.entries(mode, source)
                let entry = desktop >= 1 && desktop <= from.count ? from.remove(at: desktop - 1) : ""
                var to = doc.plans.entries(mode, target)
                while to.count < index - 1 { to.append("") }
                to.insert(entry, at: min(index - 1, to.count))
                doc.plans.set(from, mode, source)
                doc.plans.set(to, mode, target)
            }
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) { syncActiveProfile() }
    }
}
