import CoreGraphics
import Foundation

/// Ekran değişiminde kaybolan space'lerin adlarının yeni yeri (R2) ve
/// kanıt yokken plana göre bağlama (R4); docs/desktop-names-v2.md §A.7.
/// Saf: Router her profile ayrı uygular.
enum Succession {

    /// Son kaydedilen kararlı durum: rol başına space sırası ve her
    /// space'in içeriği (yalnız o space'teki pencereler).
    struct Snapshot: Equatable {
        var spaces: [String: [UInt64]]
        var contents: [UInt64: [CGWindowID]]

        var all: Set<UInt64> { Set(spaces.values.joined()) }

        func place(of space: UInt64) -> Slot? {
            for role in spaces.keys.sorted() {
                if let index = spaces[role]?.firstIndex(of: space) {
                    return Slot(screen: role, desktop: index + 1)
                }
            }
            return nil
        }
    }

    struct Result: Equatable {
        var names: [DesktopName]
        /// Masaüstü macOS'ça başka masaüstüne katıldı: ad yerleşmemiş, bu
        /// pencereler plan uygulamasında adın yeni masaüstüne taşınır.
        var evacuation: [String: [CGWindowID]] = [:]
        /// Yeni space'e geçen adlar (ad kimliği → space).
        var succeeded: [String: UInt64] = [:]
    }

    /// Bir profilin adlarını yeni canlı duruma göre çözer.
    /// - Canlı space'e bağlı ad orada kalır (R1).
    /// - Kayıtlı durumda olup artık olmayan space: yaşayan pencerelerinin
    ///   çoğunun bulunduğu canlı space ardıldır; o space bu profilde başka
    ///   ada bağlı değilse ve kayıtlı durumda içeriği olan bir space değilse
    ///   (birleşme hedefi). Eşitlikte kayıtlı durumda olmayan, sonra küçük
    ///   sıra. Ardıl yoksa ad yerleşmemiş olur; pencereleri yaşıyorsa
    ///   tahliye kümesiyle (R2).
    /// - Kayıtlı durumda da olmayan space (kanıt yok): planın etkin
    ///   kurulumdaki yerine bağlanır (R4).
    /// `windowSpaces`: yaşayan pencerelerin tek (normal) space'i.
    static func resolve(names: [DesktopName], snapshot: Snapshot, live: LiveDesktops,
                        windowSpaces: [CGWindowID: UInt64], plans: DesktopPlans,
                        carried: [String: [CGWindowID]] = [:]) -> Result {
        let alive = live.all
        let before = snapshot.all
        var result = Result(names: names)
        var bound = Set(names.compactMap { $0.space.flatMap { alive.contains($0) ? $0 : nil } })
        func liveOrder(_ space: UInt64) -> (String, Int) {
            let place = live.place(of: space)
            return (place?.screen ?? "~", place?.desktop ?? .max)
        }
        let vanished = names.indices.filter { i in
            guard let space = names[i].space else { return false }
            return !alive.contains(space)
        }.sorted { a, b in
            let pa = snapshot.place(of: names[a].space!), pb = snapshot.place(of: names[b].space!)
            return (pa?.screen ?? "~", pa?.desktop ?? .max, names[a].name)
                < (pb?.screen ?? "~", pb?.desktop ?? .max, names[b].name)
        }
        var noEvidence: [Int] = []
        for i in vanished {
            let space = names[i].space!
            guard before.contains(space) else { noEvidence.append(i); continue }
            let windows = (snapshot.contents[space] ?? []).filter { windowSpaces[$0] != nil }
            var counts: [UInt64: Int] = [:]
            for window in windows {
                if let target = windowSpaces[window], alive.contains(target) { counts[target, default: 0] += 1 }
            }
            let best = counts.values.max() ?? 0
            let tied = counts.filter { $0.value == best && best > 0 }.map(\.key).sorted { a, b in
                let fa = before.contains(a) ? 1 : 0, fb = before.contains(b) ? 1 : 0
                if fa != fb { return fa < fb }
                return liveOrder(a) < liveOrder(b)
            }
            let successor = tied.first { candidate in
                guard !bound.contains(candidate) else { return false }
                let mergeTarget = before.contains(candidate) && !(snapshot.contents[candidate] ?? []).isEmpty
                return !mergeTarget
            }
            if let successor {
                result.names[i].space = successor
                result.succeeded[names[i].id] = successor
                bound.insert(successor)
            } else {
                result.names[i].space = nil
                if !windows.isEmpty { result.evacuation[names[i].id] = windows }
            }
        }
        // R4: kayıtlı durumda da olmayan (kanıtsız) bağlar.
        for i in noEvidence {
            result.names[i].space = nil
            guard let slot = plans.place(of: names[i].id, mode: live.mode),
                  let space = live.space(at: slot), !bound.contains(space) else { continue }
            result.names[i].space = space
            bound.insert(space)
        }
        // Yarıda kalan geçişin tahliye kümesi (Transition.evacuation): ad hâlâ
        // yerleşmemişse pencereleri yine onunla gider (yoksa yeniden hesap
        // adı boş yere bağlar, pencereleri adsız içerik sayılırdı).
        for i in result.names.indices where result.names[i].space == nil {
            let id = result.names[i].id
            guard result.evacuation[id] == nil, let saved = carried[id] else { continue }
            let windows = saved.filter { windowSpaces[$0] != nil }
            if !windows.isEmpty { result.evacuation[id] = windows }
        }
        return result
    }
}
