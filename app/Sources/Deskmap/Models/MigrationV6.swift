import CoreGraphics
import Foundation

/// Şema 5 → 6 geçişinin canlı kanıtı (docs/desktop-names-v2.md §A.8):
/// ekranlar yatışmışken etkin kurulum, rol başına canlı masaüstü sırası ve
/// tek masaüstündeki canlı pencereler.
struct MigrationEvidence: Equatable {
    struct Window: Equatable {
        var id: CGWindowID
        var space: UInt64
        var bundleID: String
        var appName: String
        var title: String
        var document: String? = nil
    }
    var live: LiveDesktops
    var windows: [Window]
}

/// Geçişin raporu (alt çubuktaki kart ve günlük).
struct MigrationReport: Equatable, Codable {
    struct Bound: Equatable, Codable {
        var name: String
        var screen: String
        var desktop: Int
        var space: UInt64
    }
    struct ProfileReport: Equatable, Codable {
        var profileID: String
        var profileName: String
        var bound: [Bound] = []
        var unplaced: [String] = []
        var ghostsRemoved = 0
        var pinsRestored = 0
    }
    var profiles: [ProfileReport] = []
    /// Etkin kurulumda planın ötesindeki boş masaüstüleri (M1: silinmez,
    /// kart "N boş masaüstünü kaldır" önerir). Rol → space'ler.
    var emptyBeyondPlan: [String: [UInt64]] = [:]
    var withEvidence = false

    var emptyCount: Int { emptyBeyondPlan.values.reduce(0) { $0 + $1.count } }
}

enum MigrationV6 {

    /// Belgeyi şema 6'ya çevirir (saf). Hiç pencere taşımaz, masaüstü
    /// açmaz/silmez. `evidence` yoksa (ilk okuma, kanıtsız) adlar etkin
    /// kurulumun eski bağına bağlanır, kurallar ve planlar yalnız eski
    /// tablolardan çevrilir; sonuç geçicidir (kaydedilmez).
    static func migrate(_ source: Document, evidence: MigrationEvidence?)
        -> (document: Document, report: MigrationReport) {
        var doc = source
        doc.syncActiveProfile()
        var report = MigrationReport(withEvidence: evidence != nil)
        let mode = evidence?.live.mode ?? .docked
        // Adım 2-4: her profilin adları.
        var profileNames: [String: [DesktopName]] = [:]
        var profileRules: [String: [Rule]] = [:]
        var profilePlans: [String: DesktopPlans] = [:]
        for profile in doc.profiles {
            let legacy = profile.legacy ?? LegacyNames()
            let assigned = assign(legacy: legacy, rules: profile.rules, mode: mode, evidence: evidence)
            profileNames[profile.id] = assigned
            let rules = convertRules(profile.rules, legacy: legacy, names: assigned, mode: mode,
                                     evidence: evidence)
            profileRules[profile.id] = rules
            profilePlans[profile.id] = buildPlans(legacy: legacy, names: assigned, rules: rules,
                                                  mode: mode, evidence: evidence)
        }

        // Adım 1 ve 7: hayalet olayları; adı canlı olan hayaletin olayı çöptür.
        struct EventKey: Hashable { var ms: Int64; var screen: String; var desktop: Int }
        func key(_ ghost: GhostDesktop) -> EventKey {
            EventKey(ms: Int64((ghost.deletedAt.timeIntervalSinceReferenceDate * 1000).rounded()),
                     screen: ghost.screen, desktop: ghost.desktop)
        }
        var junkEvents = Set<EventKey>()
        for profile in doc.profiles {
            let names = profileNames[profile.id] ?? []
            for ghost in profile.ghostDesktops {
                guard let name = ghost.name,
                      names.contains(where: { Document.normalizedName($0.name) == Document.normalizedName(name) })
                else { continue }
                junkEvents.insert(key(ghost))
            }
        }

        var profiles: [Profile] = []
        for var profile in doc.profiles {
            var names = profileNames[profile.id] ?? []
            var rules = profileRules[profile.id] ?? profile.rules
            let plans = profilePlans[profile.id] ?? DesktopPlans()
            var entry = MigrationReport.ProfileReport(profileID: profile.id, profileName: profile.name)
            var kept: [GhostDesktop] = []
            for ghost in profile.ghostDesktops {
                guard junkEvents.contains(key(ghost)) else {
                    var copy = ghost
                    if copy.cause == nil { copy.cause = GhostDesktop.deletedCause }
                    kept.append(copy)
                    continue
                }
                // Önce olayın kaydırmasının tersi (numara hedefleri), sonra pinler.
                let modes: [Mode] = ghost.screen == "builtin" ? Mode.allCases : [.docked]
                for i in rules.indices {
                    for m in modes {
                        rules[i].mapPlaces(m) { _, destination in
                            guard destination.nameID == nil, destination.screen == ghost.screen,
                                  destination.desktop >= ghost.desktop else { return destination }
                            var destination = destination
                            destination.desktop += 1
                            return destination
                        }
                    }
                }
                let live = ghost.name.flatMap { name in
                    names.first { Document.normalizedName($0.name) == Document.normalizedName(name) }
                }
                for pin in ghost.pins {
                    var destination = pin.destination
                    if let live {
                        destination.nameID = live.id
                    } else {
                        destination = convertDestination(destination, mode: pin.mode, current: mode,
                                                         legacy: profile.legacy ?? LegacyNames(),
                                                         names: names, evidence: evidence)
                    }
                    let index = rules.firstIndex { $0.id == pin.rule.id }
                        ?? rules.firstIndex { $0.sameKey(as: pin.rule) }
                    if let index {
                        guard rules[index][pin.mode] == nil else { continue }
                        rules[index][pin.mode] = destination
                    } else {
                        var rule = pin.rule
                        rule.setPlaces([], mode: .docked)
                        rule.undocked = nil
                        rule[pin.mode] = destination
                        rules.append(rule)
                    }
                    entry.pinsRestored += 1
                }
                entry.ghostsRemoved += 1
            }
            // Ad hedeflerinin önbelleği: canlı yer ya da plandaki yer.
            var scratch = Document()
            scratch.profiles = [Profile(id: profile.id, name: profile.name, rules: rules,
                                        names: names, plans: plans)]
            scratch.activeProfileID = profile.id
            scratch.loadProfileState(scratch.profiles[0])
            scratch.refreshNameCaches(live: evidence?.live)
            rules = scratch.rules
            names.sort { (a, b) in
                let pa = evidence?.live.place(of: a.space ?? 0), pb = evidence?.live.place(of: b.space ?? 0)
                return (pa?.screen ?? "~", pa?.desktop ?? .max, a.name) < (pb?.screen ?? "~", pb?.desktop ?? .max, b.name)
            }
            for name in names {
                if let space = name.space, let place = evidence?.live.place(of: space) {
                    entry.bound.append(.init(name: name.name, screen: place.screen,
                                             desktop: place.desktop, space: space))
                } else if name.space == nil {
                    entry.unplaced.append(name.name)
                }
            }
            profile.rules = rules
            profile.names = names
            profile.plans = plans
            profile.ghostDesktops = kept
            profile.legacy = nil
            profiles.append(profile)
            report.profiles.append(entry)
        }
        doc.profiles = profiles
        if let active = profiles.first(where: { $0.id == doc.activeProfileID }) {
            doc.loadProfileState(active)
        }
        doc.fileVersion = Document.currentVersion
        doc.version = Document.currentVersion
        // M1: planın ötesindeki boş masaüstüleri (etkin profilin etkin kurulumu).
        if let evidence {
            let occupied = Set(evidence.windows.map(\.space))
            let named = doc.namedSpacesInAnyProfile
            for (role, list) in evidence.live.spaces {
                let length = doc.plans.entries(mode, role).count
                let empty = list.enumerated().filter { $0.offset >= length }
                    .map(\.element).filter { !occupied.contains($0) && !named.contains($0) }
                if !empty.isEmpty { report.emptyBeyondPlan[role] = empty }
            }
        }
        return (doc, report)
    }

    // MARK: - Adım 2-4: adların masaüstüleri

    /// Profilin eski adları (normalleştirilmiş ad → görünen ad), önce etkin kurulumunkiler.
    private static func legacyNames(_ legacy: LegacyNames, mode: Mode) -> [(key: String, name: String)] {
        var result: [(String, String)] = []
        var seen = Set<String>()
        for m in [mode, Document.otherMode(mode)] {
            for key in legacy.desktopNames.keys.sorted() where Document.splitNameKey(key)?.mode == m {
                let list = legacy.desktopNames[key] ?? [:]
                for slot in list.keys.sorted(by: { (Int($0) ?? .max) < (Int($1) ?? .max) }) {
                    guard let name = list[slot] else { continue }
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalized = Document.normalizedName(trimmed)
                    guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                    result.append((normalized, trimmed))
                }
            }
        }
        return result
    }

    /// Adın eski tabloda bir kurulumdaki (ilk) yeri ve bağı.
    private static func legacySlot(_ legacy: LegacyNames, name: String, mode: Mode)
        -> (slot: Slot, space: UInt64?)? {
        for key in legacy.desktopNames.keys.sorted() {
            guard let parts = Document.splitNameKey(key), parts.mode == mode else { continue }
            let list = legacy.desktopNames[key] ?? [:]
            for slot in list.keys.sorted(by: { (Int($0) ?? .max) < (Int($1) ?? .max) }) {
                guard let value = list[slot], Document.normalizedName(value) == name,
                      let desktop = Int(slot) else { continue }
                return (Slot(screen: parts.screen, desktop: desktop), legacy.desktopNameSpaces[key]?[slot])
            }
        }
        return nil
    }

    /// Hedefin eski tablodaki adı (normalleştirilmiş).
    private static func slotName(_ legacy: LegacyNames, _ destination: Destination?, mode: Mode) -> String? {
        guard let destination else { return nil }
        return legacy.desktopNames[Document.planKey(mode: mode, screen: destination.screen)]?[
            String(destination.desktop)].map(Document.normalizedName)
    }

    static func assign(legacy: LegacyNames, rules: [Rule], mode: Mode,
                       evidence: MigrationEvidence?) -> [DesktopName] {
        let all = legacyNames(legacy, mode: mode)
        guard !all.isEmpty else { return [] }
        let other = Document.otherMode(mode)
        var spaceOf: [String: UInt64] = [:]
        var taken = Set<UInt64>()
        if let evidence {
            let alive = evidence.live.all
            // Adım 3: kanıt.
            var score: [String: [UInt64: Double]] = [:]
            for window in evidence.windows {
                guard let match = Routing.select(
                        rules: rules, sessionPins: [:], mode: mode, windowID: window.id,
                        bundleID: window.bundleID, appName: window.appName, title: window.title,
                        document: window.document),
                      let rule = match.rule else { continue }
                let owners = Set([slotName(legacy, rule[mode], mode: mode),
                                  slotName(legacy, rule[other], mode: other)].compactMap { $0 })
                for owner in owners { score[owner, default: [:]][window.space, default: 0] += 1 }
            }
            for (key, _) in all {
                if let bound = legacySlot(legacy, name: key, mode: mode)?.space, alive.contains(bound) {
                    score[key, default: [:]][bound, default: 0] += 0.5
                }
                if let bound = legacySlot(legacy, name: key, mode: other)?.space, alive.contains(bound) {
                    score[key, default: [:]][bound, default: 0] += 0.25
                }
            }
            // Adım 4: puan sırasıyla eşleştirme.
            func order(_ space: UInt64) -> (String, Int) {
                let place = evidence.live.place(of: space)
                return (place?.screen ?? "~", place?.desktop ?? .max)
            }
            var pairs: [(name: String, space: UInt64, score: Double)] = []
            for (name, list) in score {
                for (space, value) in list where value >= 1 && alive.contains(space) {
                    pairs.append((name, space, value))
                }
            }
            pairs.sort { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.name != b.name { return a.name < b.name }
                return order(a.space) < order(b.space)
            }
            for pair in pairs where spaceOf[pair.name] == nil && !taken.contains(pair.space) {
                spaceOf[pair.name] = pair.space
                taken.insert(pair.space)
            }
            for (key, _) in all where spaceOf[key] == nil {
                let current = legacySlot(legacy, name: key, mode: mode)
                let previous = legacySlot(legacy, name: key, mode: other)
                var candidates: [UInt64] = []
                if let bound = current?.space { candidates.append(bound) }
                if let bound = previous?.space { candidates.append(bound) }
                if let slot = current?.slot, let space = evidence.live.space(at: slot) {
                    candidates.append(space)
                }
                if let found = candidates.first(where: { alive.contains($0) && !taken.contains($0) }) {
                    spaceOf[key] = found
                    taken.insert(found)
                }
            }
        } else {
            for (key, _) in all {
                let candidates = [legacySlot(legacy, name: key, mode: mode)?.space,
                                  legacySlot(legacy, name: key, mode: other)?.space].compactMap { $0 }
                if let found = candidates.first(where: { !taken.contains($0) }) {
                    spaceOf[key] = found
                    taken.insert(found)
                }
            }
        }
        return all.map { DesktopName(name: $0.name, space: spaceOf[$0.key]) }
    }

    // MARK: - Adım 5: kurallar

    private static func convertDestination(_ destination: Destination, mode m: Mode, current: Mode,
                                           legacy: LegacyNames, names: [DesktopName],
                                           evidence: MigrationEvidence?) -> Destination {
        var destination = destination
        guard destination.nameID == nil else { return destination }
        if let evidence, m == current {
            if let space = evidence.live.space(at: Slot(screen: destination.screen,
                                                         desktop: destination.desktop)),
               let record = names.first(where: { $0.space == space }) {
                destination.nameID = record.id
            }
            return destination
        }
        if let name = slotName(legacy, destination, mode: m),
           let record = names.first(where: { Document.normalizedName($0.name) == name }) {
            destination.nameID = record.id
        }
        return destination
    }

    static func convertRules(_ rules: [Rule], legacy: LegacyNames, names: [DesktopName], mode: Mode,
                             evidence: MigrationEvidence?) -> [Rule] {
        rules.map { rule in
            var rule = rule
            for m in Mode.allCases {
                rule.mapPlaces(m) { _, destination in
                    convertDestination(destination, mode: m, current: mode, legacy: legacy,
                                       names: names, evidence: evidence)
                }
            }
            return rule
        }
    }

    // MARK: - Adım 6: planlar

    static func buildPlans(legacy: LegacyNames, names: [DesktopName], rules: [Rule], mode: Mode,
                           evidence: MigrationEvidence?) -> DesktopPlans {
        var plans = DesktopPlans()
        func numberMax(_ m: Mode, _ role: String) -> Int {
            rules.flatMap { $0.places(m) }.filter { $0.nameID == nil && $0.screen == role }
                .map(\.desktop).max() ?? 0
        }
        func idOf(_ normalized: String) -> String? {
            names.first { Document.normalizedName($0.name) == normalized }?.id
        }
        var tableModes = Mode.allCases
        if let evidence {
            tableModes = [Document.otherMode(mode)]
            let occupied = Set(evidence.windows.map(\.space))
            for (role, list) in evidence.live.spaces {
                var length = max(numberMax(mode, role),
                                 legacy.plannedDesktops[Document.planKey(mode: mode, screen: role)] ?? 0)
                for (index, space) in list.enumerated()
                where occupied.contains(space) || names.contains(where: { $0.space == space }) {
                    length = max(length, index + 1)
                }
                guard length > 0 else { continue }
                let entries = (0..<length).map { index -> String in
                    guard index < list.count else { return "" }
                    return names.first { $0.space == list[index] }?.id ?? ""
                }
                plans.set(entries, mode, role)
            }
        }
        for m in tableModes {
            var roles = Set<String>()
            for key in legacy.desktopNames.keys { if let p = Document.splitNameKey(key), p.mode == m { roles.insert(p.screen) } }
            for key in legacy.plannedDesktops.keys { if let p = Document.splitNameKey(key), p.mode == m { roles.insert(p.screen) } }
            var placed = Set<String>()
            for role in roles.sorted(by: { ($0 == "builtin" ? 1 : 0, $0) < ($1 == "builtin" ? 1 : 0, $1) }) {
                let table = legacy.desktopNames[Document.planKey(mode: m, screen: role)] ?? [:]
                let highest = table.keys.compactMap(Int.init).max() ?? 0
                let length = max(highest, numberMax(m, role),
                                 legacy.plannedDesktops[Document.planKey(mode: m, screen: role)] ?? 0)
                guard length > 0 else { continue }
                var entries = Array(repeating: "", count: length)
                for (slot, name) in table {
                    guard let desktop = Int(slot), desktop >= 1, desktop <= length,
                          let id = idOf(Document.normalizedName(name)), placed.insert(id).inserted
                    else { continue }
                    entries[desktop - 1] = id
                }
                plans.set(entries, m, role)
            }
        }
        // Bir kurulumun tablosunda olmayan laptop adları öbür kurulumda aynı sıraya (boşsa).
        if let evidence {
            let other = Document.otherMode(mode)
            let present = plans.ids(other)
            for (index, space) in (evidence.live.spaces["builtin"] ?? []).enumerated() {
                guard let record = names.first(where: { $0.space == space }),
                      !present.contains(record.id) else { continue }
                var entries = plans.entries(other, "builtin")
                if index < entries.count {
                    guard entries[index].isEmpty else { continue }
                    entries[index] = record.id
                } else {
                    while entries.count < index { entries.append("") }
                    entries.append(record.id)
                }
                plans.set(entries, other, "builtin")
            }
        }
        return plans
    }

    // MARK: - Kanıtsız tablo çevirisi (sürüm 3 içe aktarma)

    /// Eski ad tablolarını şema 6'ya çevirir: adlar yerleşmemiş, planlar
    /// tablolardan, kurallar eski yerlerindeki adlara bağlı.
    static func convertTables(_ legacy: LegacyNames, rules: [Rule])
        -> (names: [DesktopName], plans: DesktopPlans, rules: [Rule]) {
        var names = assign(legacy: legacy, rules: rules, mode: .docked, evidence: nil)
        for i in names.indices { names[i].space = nil }
        let converted = convertRules(rules, legacy: legacy, names: names, mode: .docked, evidence: nil)
        let plans = buildPlans(legacy: legacy, names: names, rules: converted, mode: .docked, evidence: nil)
        return (names, plans, converted)
    }
}
