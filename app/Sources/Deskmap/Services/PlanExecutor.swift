import CoreGraphics
import Foundation

/// Plan yürütücüsü (docs/desktop-names-v2.md §P.1 adım 5, C1–C7): açılışlar
/// (Mission Control, doğrulanmış), taşımalar (SkyLight, doğrulanmış), bağlar,
/// silmeler. Dünyaya erişim `PlanWorld` kapanışlarıyla: Router'da gerçek
/// Mission Control ve SkyLight, testte sahte masaüstüleri.
enum PlanExecutor {

    struct ResolvedMove: Equatable, Hashable {
        var window: CGWindowID
        var space: UInt64
    }

    /// Yürütücünün dış dünyası. Bütün çağrılar ana aktörde.
    struct World {
        /// Bağlı rollerin taze masaüstü sırası (yalnız normal masaüstüleri).
        var liveSpaces: @MainActor () -> [String: [UInt64]]
        /// Role bir masaüstü ekler (sona); sayı artışıyla doğrulanmış.
        var addDesktop: @MainActor (String) async -> Bool
        /// Doğrulanmış taşıma; taşınamayan pencereleri döndürür.
        var move: @MainActor ([ResolvedMove]) async -> [CGWindowID]
        /// C1: space boş mu; nil = bilinmiyor (boş sayılmaz).
        var isEmpty: @MainActor (UInt64) -> Bool?
        /// `desktop`. masaüstünü siler; o sıradaki space `expected` değilse dokunmaz.
        var removeDesktop: @MainActor (_ role: String, _ desktop: Int, _ expected: UInt64) async -> Bool
        /// Ekran değişti, duraklatıldı, süre doldu ya da erişilebilirlik gitti.
        var shouldAbort: @MainActor () -> Bool
        /// Taşımalar yürütülmeden önce günlüğe (C6): taşımalar, adların
        /// bağlanacağı space'ler ve taşıma haritası.
        var journal: @MainActor (_ moves: [ResolvedMove], _ rebinds: [String: UInt64],
                                 _ spaceMap: [UInt64: UInt64]) -> Void = { _, _, _ in }
    }

    struct Outcome: Equatable {
        var created = 0
        /// Bu uygulamanın açtığı space'ler (yarıda kalsa da).
        var createdSpaces: [UInt64] = []
        var failedCreates: [String] = []
        var moved = 0
        var failedMoves: [CGWindowID] = []
        /// Ad kimliği → bağlandığı space (taşımalar yapıldıysa; yarıda kalsa da kaydedilir).
        var rebinds: [String: UInt64] = [:]
        /// İçeriği taşınan space → yeni space (R5).
        var spaceMap: [UInt64: UInt64] = [:]
        var removed = 0
        var removedSpaces: [UInt64] = []
        var aborted = false
        var abortReason: String?
    }

    /// Çökmeden kalan günlük (C6, saf): günlükteki taşımaların çoğu (yaşayan
    /// pencerelerden) hedefinde ise taşımalar yapılmıştı, bağlar ve taşıma
    /// haritası kaydedilmeli; değilse hiçbiri (plan yeniden hesaplanır).
    static func journalDone(_ moves: [ResolvedMove], windowSpaces: [CGWindowID: UInt64]) -> Bool {
        let alive = moves.filter { windowSpaces[$0.window] != nil }
        guard !alive.isEmpty else { return false }
        let done = alive.filter { windowSpaces[$0.window] == $0.space }.count
        return done * 2 > alive.count
    }

    /// Bu uygulamanın artıkları (saf): girdinin artıkları, boşalttığı
    /// (taşıma haritasının kaynakları), açtığı ve silmeyi planlayıp
    /// silmediği space'ler. Yarıda kalan geçiş bunları kaydeder, yeniden
    /// başlayınca artık sayar (ilk turun boşalttığı masaüstü artık
    /// "boşaltılan" görünmez); biten geçişten sonra temizlik bunlara bakar.
    static func leftovers(of plan: PlanApply.Output, input: PlanApply.Input,
                          outcome: Outcome) -> Set<UInt64> {
        var result = input.leftovers.union(plan.spaceMap.keys).union(plan.removals)
            .union(outcome.createdSpaces)
        result.subtract(outcome.removedSpaces)
        return result
    }

    /// Açılışlardan sonra canlı sıra hesaplanan sırayla uyumlu mu (saf):
    /// aynı roller, her rolün eski sırası değişmemiş (yeni masaüstüleri yalnız sonda).
    static func consistent(_ live: [String: [UInt64]], with expected: [String: [UInt64]]) -> Bool {
        guard Set(live.keys) == Set(expected.keys) else { return false }
        for (role, list) in expected {
            guard let now = live[role], now.count >= list.count,
                  Array(now.prefix(list.count)) == list else { return false }
        }
        return true
    }

    /// Planı yürütür. `expected` planın hesaplandığı canlı sıra; yürütmeden
    /// önce masaüstüleri değiştiyse hiçbir şey yapılmaz (yarıda kalır,
    /// geçiş yeniden hesaplar). Her adımdan önce `shouldAbort`; yarıda
    /// kaldıktan sonra hiçbir şey silinmez. Taşımalar yapıldıysa bağlar ve
    /// taşıma haritası yarıda kalsa da sonuçta döner (çağıran kaydeder).
    @MainActor
    static func run(_ plan: PlanApply.Output, expected: [String: [UInt64]],
                    windowSpaces: [CGWindowID: UInt64], allowRemovals: Bool,
                    world: World) async -> Outcome {
        var outcome = Outcome()
        guard !plan.isEmpty else { return outcome }
        let known = Set(expected.values.joined())
        func newSpaces() -> [UInt64] {
            let live = world.liveSpaces()
            return live.keys.sorted().flatMap { live[$0]!.filter { !known.contains($0) } }
        }
        func stop(_ reason: String) -> Outcome {
            var result = outcome
            if result.created > 0 { result.createdSpaces = newSpaces() }
            result.aborted = true
            result.abortReason = reason
            Log.app.notice("Plan: stopped (\(reason, privacy: .public)) after \(result.created) created, \(result.moved) moved, \(result.removed) removed")
            return result
        }
        if world.shouldAbort() { return stop("interrupted") }
        guard world.liveSpaces() == expected else { return stop("desktops changed before applying") }
        for role in plan.creates.keys.sorted() {
            for _ in 0..<(plan.creates[role] ?? 0) {
                if world.shouldAbort() { return stop("interrupted") }
                let before = Set(world.liveSpaces()[role] ?? [])
                if await world.addDesktop(role) {
                    outcome.created += 1
                    let added = (world.liveSpaces()[role] ?? []).filter { !before.contains($0) }
                    Log.app.notice("Plan: created a desktop on \(role, privacy: .public) (space \(added.map(String.init).joined(separator: ","), privacy: .public); now \(before.count + 1))")
                } else {
                    outcome.failedCreates.append(role)
                    Log.app.error("Plan: could not create a desktop on \(role, privacy: .public) (Mission Control did not add one; \(before.count) desktops)")
                    break
                }
            }
        }
        if world.shouldAbort() { return stop("interrupted") }
        let live = world.liveSpaces()
        if outcome.created > 0 { outcome.createdSpaces = newSpaces() }
        // Açılan masaüstü sona gelmediyse ya da sıra kaydıysa sıra numaraları
        // yanlış masaüstünü gösterir: taşıma yapılmaz.
        guard consistent(live, with: expected) else { return stop("desktops changed while adding") }
        func resolve(_ slot: Slot) -> UInt64? {
            guard let list = live[slot.screen], slot.desktop >= 1, slot.desktop <= list.count
            else { return nil }
            return list[slot.desktop - 1]
        }
        var moves: [ResolvedMove] = []
        for move in plan.moves {
            guard let target = resolve(move.to) else {
                outcome.failedMoves.append(move.window)
                Log.app.error("Plan: window \(move.window) not moved: desktop \(move.to.desktop) on \(move.to.screen, privacy: .public) does not exist")
                continue
            }
            moves.append(ResolvedMove(window: move.window, space: target))
        }
        // Taşınamayan pencere olsa da ad planladığı masaüstüne bağlanır (C2).
        var rebinds: [String: UInt64] = [:]
        var spaceMap: [UInt64: UInt64] = [:]
        for (id, slot) in plan.rebinds { if let space = resolve(slot) { rebinds[id] = space } }
        for (space, slot) in plan.spaceMap {
            if let target = resolve(slot), target != space { spaceMap[space] = target }
        }
        if !moves.isEmpty {
            world.journal(moves, rebinds, spaceMap)
            let failed = await world.move(moves)
            outcome.moved = moves.count - failed.count
            outcome.failedMoves += failed
            let targets = Dictionary(moves.map { ($0.window, $0.space) }, uniquingKeysWith: { a, _ in a })
            for window in failed {
                Log.app.error("Plan: window \(window) could not be moved from space \(windowSpaces[window].map(String.init) ?? "?", privacy: .public) to space \(targets[window].map(String.init) ?? "?", privacy: .public)")
            }
        }
        outcome.rebinds = rebinds
        outcome.spaceMap = spaceMap
        guard allowRemovals, !plan.removals.isEmpty else { return outcome }
        // Taşınamayan pencerenin kaynağı boş değildir, silinmez (C2).
        let removals = PlanApply.removalsAfterFailures(plan.removals, failed: outcome.failedMoves,
                                                       contents: windowSpaces)
        for space in plan.removals where !removals.contains(space) {
            Log.app.notice("Plan: space \(space) kept (a window failed to leave it)")
        }
        for space in removals {
            if world.shouldAbort() {
                outcome.aborted = true
                outcome.abortReason = "interrupted while removing"
                break
            }
            let current = world.liveSpaces()
            guard let role = current.keys.sorted().first(where: { current[$0]?.contains(space) == true }),
                  let list = current[role], list.count > 1,
                  let index = list.firstIndex(of: space) else {
                Log.app.notice("Plan: space \(space) kept (gone or the last desktop of its display)")
                continue
            }
            let empty = world.isEmpty(space)
            guard empty == true else {
                Log.app.notice("Plan: desktop \(index + 1) on \(role, privacy: .public) (space \(space)) kept (\(empty == nil ? "emptiness unknown" : "not empty", privacy: .public))")
                continue
            }
            if await world.removeDesktop(role, index + 1, space) {
                outcome.removed += 1
                outcome.removedSpaces.append(space)
                Log.app.notice("Plan: removed empty desktop \(index + 1) on \(role, privacy: .public) (space \(space))")
            } else {
                Log.app.error("Plan: could not remove desktop \(index + 1) on \(role, privacy: .public) (space \(space); Mission Control refused or the order changed)")
            }
        }
        return outcome
    }
}
