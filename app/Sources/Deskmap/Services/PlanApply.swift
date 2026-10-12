import CoreGraphics
import Foundation

/// Planın uygulanması (docs/desktop-names-v2.md §P): etkin profilin etkin
/// kurulum planına göre hangi masaüstülerinin açılacağı, hangi pencerelerin
/// nereye taşınacağı, adların hangi masaüstüne bağlanacağı ve hangi artık
/// masaüstülerinin silineceği. Saf; yürütme Router'da.
enum PlanApply {

    /// Monitör çıkınca adsız monitör masaüstündeki pencere (B satırı 1);
    /// aynı rol geri gelince yerine döner (P2: monitörün kimliği önemsiz).
    struct Parked: Codable, Equatable, Hashable {
        var window: CGWindowID
        var pid: pid_t = 0
        var bundleID: String = ""
        var role: String
        var displayUUID: String = ""
        var desktop: Int
        var space: UInt64
        var since: Date = Date()
    }

    struct Input {
        var mode: Mode
        /// Bağlı rollerin canlı masaüstü sırası.
        var live: [String: [UInt64]]
        /// Canlı space → yalnız o space'teki pencereler.
        var contents: [UInt64: [CGWindowID]]
        /// Etkin profilin adları (ardıllar çözülmüş).
        var names: [DesktopName]
        /// Etkin kurulumun planı (rol → girdiler).
        var plans: [String: [String]]
        /// Ad kimliği → tahliye kümesi (R2).
        var evacuation: [String: [CGWindowID]] = [:]
        /// Rol → bu role yerleşecek adsız pencere grupları (çıkarılan
        /// monitörün adsız masaüstüleri, eski sırasıyla).
        var arriving: [String: [[CGWindowID]]] = [:]
        /// Geri dönen role ait park edilmiş pencereler.
        var parked: [Parked] = []
        /// Bu geçişte macOS'un açtığı ya da ekranlar arası taşıdığı space'ler.
        var leftovers: Set<UInt64> = []
        /// Öbür profillerde ada bağlı space'ler (taşıma haritası sonrası denetlenir).
        var otherNamed: Set<UInt64> = []
        /// Kuyruktaki silmeler: asla otomatik silinmez.
        var pending: Set<UInt64> = []
        var allowRemovals = true
        var allowMoves = true
        var maxCreatesPerRole = 8
        var maxRemovals = 8
        var maxMoves = 400
    }

    struct Move: Equatable, Hashable {
        var window: CGWindowID
        var to: Slot
    }

    struct Output: Equatable {
        var creates: [String: Int] = [:]
        var moves: [Move] = []
        /// Ad kimliği → bağlanacağı yer (açılışlardan sonra space'e çözülür).
        var rebinds: [String: Slot] = [:]
        /// İçeriği bütünüyle taşınan space → yeni yeri (R5, bütün profiller).
        var spaceMap: [UInt64: Slot] = [:]
        /// Silinecek space'ler; rol başına büyük sıradan küçüğe.
        var removals: [UInt64] = []
        /// Masaüstü açılamayacağı için yerinde kalan adlar.
        var skippedNames: [String] = []
        /// Bir sınır aşıldı: kalan iş sonraki tura.
        var truncated = false
        /// Taşınacak adlı masaüstü sayısı (günlük için).
        var movedNames = 0

        var isEmpty: Bool {
            creates.values.allSatisfy { $0 == 0 } && moves.isEmpty && rebinds.isEmpty && removals.isEmpty
        }
    }

    private struct Group {
        var windows: [CGWindowID]
        var source: UInt64?
        var name: String?
        var role: String
        var target: Slot?
        var origin: Int
    }

    /// Space boş mu (C1, saf): `windowSpaces` pencere sunucusundaki katman 0
    /// pencerelerinin space listeleri (okunamayan nil). Liste boşsa ya da
    /// okunamayan bir pencere varsa bilinmiyor (nil = boş değil sayılır).
    /// Yalnız bu space'te olan pencere doluluk; birden çok space'teki
    /// ("All Desktops") pencere saymaz.
    static func isEmpty(_ space: UInt64, windowSpaces: [[UInt64]?]) -> Bool? {
        guard !windowSpaces.isEmpty else { return nil }
        var unknown = false
        for spaces in windowSpaces {
            guard let spaces else { unknown = true; continue }
            if spaces == [space] { return false }
        }
        return unknown ? nil : true
    }

    /// Taşınamayan pencerelerin kaynağı silinmez (C2, saf): `location`
    /// taşıma öncesi pencere → space.
    static func removalsAfterFailures(_ removals: [UInt64], failed: [CGWindowID],
                                      contents: [CGWindowID: UInt64]) -> [UInt64] {
        let blocked = Set(failed.compactMap { contents[$0] })
        return removals.filter { !blocked.contains($0) }
    }

    /// Geçişin plana ek girdileri (saf, §P.1 adım 3).
    struct TransitionExtras: Equatable {
        /// Rol → bu role yerleşecek adsız pencere grupları.
        var arriving: [String: [[CGWindowID]]] = [:]
        /// Güncel park kayıtları (eskiler + bu geçişte eklenenler).
        var parked: [Parked] = []
        /// Bu geçişte rol değiştiren ya da yeni açılan space'ler.
        var leftovers: Set<UInt64> = []
    }

    /// `from`/`fromContents`/`fromMode`: kayıtlı "önce" durumu; `live` şimdiki
    /// ekranlar; `windowSpaces` yaşayan pencerelerin tek space'i;
    /// `namedBefore` etkin profilde ardıllardan önce adlı space'ler; `ruled`
    /// kurala ya da oturum pinine uyan pencereler (yönlendirme taşır).
    /// Monitör çıkınca (docked → undocked) adsız monitör masaüstlerinin
    /// kuralsız pencereleri eski sırasıyla gruplanır ve park edilir (B 1).
    static func transitionExtras(from: [DesktopStateFile.Display],
                                 fromContents: [String: [DesktopStateFile.WindowRef]],
                                 fromMode: Mode, mode: Mode,
                                 live: [DesktopStateFile.Display],
                                 windowSpaces: [CGWindowID: UInt64],
                                 namedBefore: Set<UInt64>, ruled: Set<CGWindowID>,
                                 parked existing: [Parked], now: Date) -> TransitionExtras {
        var extras = TransitionExtras()
        extras.parked = DesktopStateFile.prunedParked(existing, alive: Set(windowSpaces.keys), now: now)
        if fromMode == .docked, mode == .undocked {
            for display in from where display.role != "builtin" {
                for (index, space) in display.spaces.enumerated() where !namedBefore.contains(space) {
                    let refs = (fromContents[String(space)] ?? []).filter {
                        windowSpaces[$0.id] != nil && !ruled.contains($0.id)
                    }
                    guard !refs.isEmpty else { continue }
                    for ref in refs where !extras.parked.contains(where: { $0.window == ref.id }) {
                        extras.parked.append(Parked(
                            window: ref.id, pid: ref.pid, bundleID: ref.bundleID, role: display.role,
                            displayUUID: display.uuid, desktop: index + 1, space: space, since: now))
                    }
                    extras.arriving["builtin", default: []].append(refs.map(\.id))
                }
            }
        }
        var fromRole: [UInt64: String] = [:]
        for display in from { for space in display.spaces { fromRole[space] = display.role } }
        for display in live {
            for space in display.spaces where fromRole[space] != display.role { extras.leftovers.insert(space) }
        }
        return extras
    }

    static func compute(_ input: Input) -> Output {
        var output = Output()
        guard input.allowMoves else { return output }
        let roles = input.live.keys.sorted()
        let byID = Dictionary(input.names.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let alive = Set(input.live.values.joined())
        var nameOfSpace: [UInt64: DesktopName] = [:]
        for name in input.names { if let space = name.space { nameOfSpace[space] = name } }
        func space(_ slot: Slot) -> UInt64? {
            guard let list = input.live[slot.screen], slot.desktop >= 1, slot.desktop <= list.count
            else { return nil }
            return list[slot.desktop - 1]
        }
        func slot(of space: UInt64) -> Slot? {
            for role in roles {
                if let index = input.live[role]?.firstIndex(of: space) {
                    return Slot(screen: role, desktop: index + 1)
                }
            }
            return nil
        }
        var location: [CGWindowID: UInt64] = [:]
        for (space, windows) in input.contents where alive.contains(space) {
            for window in windows { location[window] = space }
        }
        let evacuated = Set(input.evacuation.values.joined())
        let arrivingWindows = Set(input.arriving.values.joined().joined())
        func content(_ space: UInt64) -> [CGWindowID] {
            (input.contents[space] ?? []).filter { !evacuated.contains($0) && !arrivingWindows.contains($0) }
        }

        // 1. Planlı adların yerleri.
        var claimed: [Slot: String] = [:]
        var plannedIDs = Set<String>()
        for role in roles {
            for (index, entry) in (input.plans[role] ?? []).enumerated()
            where !entry.isEmpty && byID[entry] != nil && !plannedIDs.contains(entry) {
                claimed[Slot(screen: role, desktop: index + 1)] = entry
                plannedIDs.insert(entry)
            }
        }
        var staying = Set<Slot>()
        var arrivals: [Slot: Int] = [:]
        var groups: [Group] = []
        var origin = 0
        for (target, id) in claimed.sorted(by: { ($0.key.screen, $0.key.desktop) < ($1.key.screen, $1.key.desktop) }) {
            guard let name = byID[id] else { continue }
            if let bound = name.space, bound == space(target), input.evacuation[id] == nil {
                staying.insert(target)
                continue
            }
            var windows: [CGWindowID] = []
            var source: UInt64?
            if let evacuation = input.evacuation[id] {
                windows = evacuation
            } else if let bound = name.space, alive.contains(bound) {
                windows = content(bound)
                source = bound
            }
            groups.append(Group(windows: windows, source: source, name: id, role: target.screen,
                                target: target, origin: origin))
            origin += 1
            arrivals[target, default: 0] += 1
        }

        // 2. Adın yerindeki başka içerik yerinden olur; öbürleri kalır.
        let arrivingSources = Set(input.arriving.values.joined().compactMap { group -> UInt64? in
            guard let first = group.first, let space = location[first] else { return nil }
            return group.allSatisfy({ location[$0] == space })
                && Set(input.contents[space] ?? []).isSubset(of: Set(group)) ? space : nil
        })
        for role in roles {
            for (index, space) in (input.live[role] ?? []).enumerated() {
                let here = Slot(screen: role, desktop: index + 1)
                if let owner = nameOfSpace[space], plannedIDs.contains(owner.id) { continue }
                if arrivingSources.contains(space) { continue }
                let windows = content(space)
                let unplanned = nameOfSpace[space]
                guard let owner = claimed[here], byID[owner]?.space != space else {
                    if !windows.isEmpty || unplanned != nil { staying.insert(here) }
                    continue
                }
                guard !windows.isEmpty || unplanned != nil else { continue }
                groups.append(Group(windows: windows, source: space, name: unplanned?.id, role: role,
                                    target: nil, origin: origin))
                origin += 1
            }
        }

        // 3. Park edilmiş pencereler (aynı role dönüş).
        var parkedMoves: [Move] = []
        for entry in input.parked {
            guard let list = input.live[entry.role], let current = location[entry.window] else { continue }
            if list.contains(current) { continue }
            var target: Slot?
            if let index = list.firstIndex(of: entry.space) {
                let candidate = Slot(screen: entry.role, desktop: index + 1)
                if claimed[candidate] == nil, nameOfSpace[entry.space] == nil { target = candidate }
            }
            if target == nil {
                let candidate = Slot(screen: entry.role, desktop: entry.desktop)
                let planned = (input.plans[entry.role] ?? []).count
                if claimed[candidate] == nil, entry.desktop <= max(list.count, planned),
                   space(candidate).map({ nameOfSpace[$0] == nil }) ?? true {
                    target = candidate
                }
            }
            if target == nil, let index = list.indices.reversed().first(where: { i in
                claimed[Slot(screen: entry.role, desktop: i + 1)] == nil && nameOfSpace[list[i]] == nil
            }) {
                target = Slot(screen: entry.role, desktop: index + 1)
            }
            guard let target else { continue }
            parkedMoves.append(Move(window: entry.window, to: target))
            arrivals[target, default: 0] += 1
        }

        // 4. Yerinden olan ve gelen adsız gruplar: soldan sağa ilk boş "" yer.
        for role in roles {
            for group in input.arriving[role] ?? [] where !group.isEmpty {
                let first = group.first.flatMap { location[$0] }
                groups.append(Group(windows: group,
                                    source: first.flatMap { arrivingSources.contains($0) ? $0 : nil },
                                    name: nil, role: role, target: nil, origin: origin))
                origin += 1
            }
        }
        let leaving = Set(groups.compactMap(\.source))
        func isFree(_ here: Slot) -> Bool {
            let plan = input.plans[here.screen] ?? []
            if here.desktop <= plan.count, !plan[here.desktop - 1].isEmpty,
               byID[plan[here.desktop - 1]] != nil { return false }
            if claimed[here] != nil || staying.contains(here) || arrivals[here, default: 0] > 0 { return false }
            if let existing = space(here), !leaving.contains(existing),
               !content(existing).isEmpty || nameOfSpace[existing] != nil { return false }
            return true
        }
        for i in groups.indices where groups[i].target == nil {
            var desktop = 1
            while !isFree(Slot(screen: groups[i].role, desktop: desktop)) { desktop += 1 }
            let target = Slot(screen: groups[i].role, desktop: desktop)
            groups[i].target = target
            arrivals[target, default: 0] += 1
        }

        // 5. Açılacak masaüstüleri (rol başına sınırlı).
        var limit: [String: Int] = [:]
        for role in roles {
            let count = input.live[role]?.count ?? 0
            var needed = (input.plans[role] ?? []).count
            for group in groups where group.target?.screen == role { needed = max(needed, group.target!.desktop) }
            for move in parkedMoves where move.to.screen == role { needed = max(needed, move.to.desktop) }
            let create = min(max(0, needed - count), input.maxCreatesPerRole)
            if create > 0 { output.creates[role] = create }
            limit[role] = count + create
        }
        func reachable(_ here: Slot) -> Bool { here.desktop <= (limit[here.screen] ?? 0) }
        // Açılamayacak yere giden ad yerinde kalır; yerinden edeceği içerik de.
        var blockedSlots = Set<Slot>()
        for group in groups where group.name != nil && group.target.map(reachable) == false {
            if let target = group.target { blockedSlots.insert(target) }
            if let name = group.name { output.skippedNames.append(name) }
        }
        for group in groups where group.target.map(reachable) == false && group.name == nil {
            if let source = group.source, let here = slot(of: source), let owner = claimed[here] {
                blockedSlots.insert(here)
                if !output.skippedNames.contains(owner) { output.skippedNames.append(owner) }
            }
        }
        groups = groups.filter { group in
            guard let target = group.target, reachable(target) else { return false }
            if let name = group.name, output.skippedNames.contains(name) { return false }
            if let source = group.source, let here = slot(of: source), blockedSlots.contains(here),
               group.name == nil || !plannedIDs.contains(group.name!) { return false }
            return true
        }

        // 6. Taşımalar, bağlar, taşıma haritası.
        var movedWindows = Set<CGWindowID>()
        var count = 0
        for group in groups.sorted(by: { $0.origin < $1.origin }) {
            guard let target = group.target else { continue }
            let pending = group.windows.filter { window in
                !movedWindows.contains(window) && location[window] != space(target)
            }
            if count + pending.count > input.maxMoves {
                output.truncated = true
                break
            }
            for window in pending {
                output.moves.append(Move(window: window, to: target))
                movedWindows.insert(window)
            }
            count += pending.count
            if let name = group.name {
                output.rebinds[name] = target
                if plannedIDs.contains(name) { output.movedNames += 1 }
            }
            if let source = group.source, space(target) != source { output.spaceMap[source] = target }
        }
        for move in parkedMoves where !movedWindows.contains(move.window) && count < input.maxMoves {
            output.moves.append(move)
            movedWindows.insert(move.window)
            count += 1
        }

        // 7. Artık masaüstülerini silme: yalnız planın ötesinde, boş kalacak,
        // hiçbir profilde adlı olmayan, kuyrukta olmayan, bu geçişin artığı.
        guard input.allowRemovals, !output.truncated else { return output }
        let vacated = Set(output.spaceMap.keys)
        let reboundSpaces = Set(output.rebinds.values.compactMap(space))
        var keptNamed = Set<UInt64>()
        for name in input.names {
            guard let bound = name.space else { continue }
            if output.rebinds[name.id] == nil { keptNamed.insert(bound) }
        }
        let otherStill = input.otherNamed.filter { output.spaceMap[$0] == nil }
        var removals: [UInt64] = []
        for role in roles {
            let list = input.live[role] ?? []
            let planned = (input.plans[role] ?? []).count
            var remaining = (limit[role] ?? list.count)
            for index in list.indices.reversed() {
                let space = list[index]
                let here = Slot(screen: role, desktop: index + 1)
                guard index + 1 > max(1, planned), remaining > 1,
                      input.leftovers.contains(space) || vacated.contains(space),
                      arrivals[here, default: 0] == 0, !staying.contains(here),
                      !keptNamed.contains(space), !reboundSpaces.contains(space),
                      !otherStill.contains(space), !input.pending.contains(space)
                else { continue }
                let stays = (input.contents[space] ?? []).filter { !movedWindows.contains($0) }
                guard stays.isEmpty else { continue }
                guard removals.count < input.maxRemovals else { output.truncated = true; break }
                removals.append(space)
                remaining -= 1
            }
        }
        output.removals = removals
        return output
    }
}
