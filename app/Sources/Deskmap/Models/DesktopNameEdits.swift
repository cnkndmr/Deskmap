import Foundation

// Şema 6 belge işlemleri (docs/desktop-names-v2.md, B tablosu). Fiziksel
// olaylar (silme, Deskmap'in taşımaları) bütün profillere uygulanır; ad ve
// plan düzenlemeleri yalnız etkin profilin çalışma kopyasına.

/// Mission Control'de (ya da Deskmap içinden) silinen bir gerçek masaüstü.
struct DesktopDeletion: Equatable {
    var role: String
    /// Silindiği andaki sırası (aynı turdaki önceki silmeler düşülmüş).
    var desktop: Int
    var space: UInt64
}

extension Document {

    static func otherMode(_ mode: Mode) -> Mode { mode == .docked ? .undocked : .docked }

    // MARK: - Silme (B satırları 8, 9, 14)

    /// Gerçek bir masaüstü silindi (Mission Control'de kullanıcı ya da
    /// Deskmap'te "Masaüstünü sil"). Bütün profillere kendi adları ve
    /// pinleriyle uygulanır: o space'e bağlı ad ve ad pinleri hayalete, o
    /// sıradaki numara pinleri hayalete, sonraki numara pinleri bir yukarı
    /// (etkin kurulum; laptop ekranında iki kurulum). Ad iki kurulumun
    /// planından düşer; adsız masaüstünde yalnız etkin kurulumun planındaki
    /// "" girdisi. Etkin profilin hayaleti döner.
    @discardableResult
    mutating func recordDeletion(space: UInt64?, role: String, desktop: Int, mode: Mode,
                                 shiftModes: [Mode]? = nil, now: Date = Date()) -> GhostDesktop? {
        if !profiles.contains(where: { $0.id == activeProfileID }) { syncActiveProfile() }
        var activeGhost: GhostDesktop?
        let modes = shiftModes ?? (role == "builtin" ? Mode.allCases : [mode])
        for profile in profiles {
            let ghost = inProfileScope(profile.id) {
                $0.deleteOwnDesktop(space: space, role: role, desktop: desktop, mode: mode,
                                    shiftModes: modes, now: now)
            } ?? nil
            if profile.id == activeProfileID { activeGhost = ghost }
        }
        return activeGhost
    }

    /// `recordDeletion`'ın tek profil çekirdeği (`inProfileScope` içinde).
    private mutating func deleteOwnDesktop(space: UInt64?, role: String, desktop: Int, mode: Mode,
                                           shiftModes: [Mode], now: Date) -> GhostDesktop? {
        let record = space.flatMap { nameRecord(space: $0) }
        var pins: [GhostDesktop.Pin] = []
        var kept: [Rule] = []
        for original in rules {
            var rule = original
            for m in Mode.allCases {
                guard var destination = rule[m] else { continue }
                if let id = destination.nameID {
                    if id == record?.id {
                        pins.append(.init(profileID: activeProfileID, mode: m, rule: original,
                                          destination: destination))
                        rule[m] = nil
                    }
                    continue
                }
                guard shiftModes.contains(m), destination.screen == role else { continue }
                if destination.desktop == desktop {
                    pins.append(.init(profileID: activeProfileID, mode: m, rule: original,
                                      destination: destination))
                    rule[m] = nil
                } else if destination.desktop > desktop {
                    destination.desktop -= 1
                    rule[m] = destination
                }
            }
            if rule.docked != nil || rule.undocked != nil { kept.append(rule) }
        }
        if kept != rules { rules = kept }
        if let record {
            names.removeAll { $0.id == record.id }
            plans.remove(record.id, mode: .docked, collapse: true)
            plans.remove(record.id, mode: .undocked, collapse: true)
        } else {
            var entries = plans.entries(mode, role)
            if desktop >= 1, desktop <= entries.count, entries[desktop - 1].isEmpty {
                entries.remove(at: desktop - 1)
                plans.set(entries, mode, role)
            }
        }
        guard record != nil || !pins.isEmpty else { return nil }
        if let record, let i = ghostDesktops.firstIndex(where: {
            $0.name.map(Self.normalizedName) == Self.normalizedName(record.name)
        }) {
            ghostDesktops[i].pins = Self.mergedPins(ghostDesktops[i].pins, pins)
            ghostDesktops[i].nameID = record.id
            return ghostDesktops[i]
        }
        let ghost = GhostDesktop(screen: role, name: record?.name, desktop: desktop, deletedAt: now,
                                 pins: pins, nameID: record?.id, cause: GhostDesktop.deletedCause)
        ghostDesktops.append(ghost)
        return ghost
    }

    // MARK: - Mission Control'ü izleme (B satırları 8–12)

    /// Kararlı durumda (ekran kümesi aynı, geçiş yok) canlı masaüstü
    /// listesi değişti: `before` son kaydedilen liste, `after` şimdiki.
    /// `ownRemovals`: Deskmap'in kendi sildiği (kaydı zaten işlenmiş)
    /// space'ler. Silinen her space bir silmedir (R3); sonra etkin kurulumun
    /// planı yeni sıraya göre yeniden yazılır (P3: yalnız etkin kurulum).
    /// Silmeler döner (oturum pinlerini kaydırmak için).
    @discardableResult
    mutating func followMissionControl(before: [String: [UInt64]], after: [String: [UInt64]],
                                       mode: Mode, ownRemovals: Set<UInt64> = [],
                                       now: Date = Date()) -> [DesktopDeletion] {
        let afterAll = Set(after.values.joined())
        var deletions: [DesktopDeletion] = []
        var remaining: [String: [UInt64]] = [:]
        for (role, list) in before {
            let counted = list.filter { !ownRemovals.contains($0) }
            guard after[role] != nil else { remaining[role] = counted; continue }
            for (index, space) in counted.enumerated() where !afterAll.contains(space) {
                deletions.append(DesktopDeletion(role: role, desktop: index + 1, space: space))
            }
            remaining[role] = counted.filter { afterAll.contains($0) }
        }
        deletions.sort { ($0.role, -$0.desktop) < ($1.role, -$1.desktop) }
        for deletion in deletions {
            recordDeletion(space: deletion.space, role: deletion.role, desktop: deletion.desktop,
                           mode: mode, now: now)
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) { syncActiveProfile() }
        for profile in profiles {
            inProfileScope(profile.id) {
                $0.rewritePlan(before: remaining, after: after, mode: mode)
            }
        }
        return deletions
    }

    /// Etkin kurulumun planını canlı sıraya göre yeniden yazar (yalnız
    /// sırası/içeriği değişen roller): ilk kısım canlı sıra (adlı space →
    /// ad, değilse ""), uzunluk eski uzunluk + eklenen − giden; canlı
    /// sayıdan uzun kalan kısım (açılmamış planlı masaüstüleri) korunur.
    mutating func rewritePlan(before: [String: [UInt64]], after: [String: [UInt64]], mode: Mode) {
        let beforeAll = Set(before.values.joined())
        let afterAll = Set(after.values.joined())
        for role in after.keys.sorted() {
            let live = after[role] ?? [], old = before[role] ?? []
            guard live != old else { continue }
            let plan = plans.entries(mode, role)
            let added = live.filter { !beforeAll.contains($0) }
            let movedIn = live.filter { beforeAll.contains($0) && !old.contains($0) }
            let movedOut = old.filter { !live.contains($0) }.count
            var length = plan.count + added.count + movedIn.count - movedOut
            for (index, space) in live.enumerated()
            where nameRecord(space: space) != nil || added.contains(space) || movedIn.contains(space) {
                length = max(length, index + 1)
            }
            length = max(length, 0)
            var entries = (0..<min(length, live.count)).map { nameRecord(space: live[$0])?.id ?? "" }
            // Canlı olmayan adlar (yerleşmemiş ya da açılamamış) planda kalır.
            let present = Set(entries)
            let orphans = plan.filter { id in
                guard !id.isEmpty, !present.contains(id), let record = nameRecord(id) else { return false }
                return record.space.map { !afterAll.contains($0) } ?? true
            }
            var tail = plan.count > old.count ? Array(plan[old.count...]) : []
            tail = tail.filter { $0.isEmpty || orphans.contains($0) }
            for id in orphans where !tail.contains(id) { tail.append(id) }
            if !orphans.isEmpty { length = max(length, live.count + tail.count) }
            while entries.count < length {
                entries.append(tail.isEmpty ? "" : tail.removeFirst())
            }
            plans.set(entries, mode, role)
        }
    }

    // MARK: - Ad verme (B satırı 13)

    /// Masaüstüne ad verir, adı değiştirir ya da (boş ad) kaldırır.
    /// Çakışan ad (aynı profilde başka masaüstünde) reddedilir: false.
    @discardableResult
    mutating func setDesktopName(_ name: String?, screen: String, desktop: Int, mode: Mode,
                                 live: LiveDesktops? = nil) -> Bool {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let id = nameID(screen: screen, desktop: desktop, mode: mode, live: live) {
            if trimmed.isEmpty {
                removeName(id)
                return true
            }
            if let other = nameRecord(named: trimmed), other.id != id { return false }
            if let i = names.firstIndex(where: { $0.id == id }), names[i].name != trimmed {
                names[i].name = trimmed
            }
            return true
        }
        guard !trimmed.isEmpty else { return true }
        guard nameRecord(named: trimmed) == nil else { return false }
        var space: UInt64?
        if let live {
            if live.mode == mode {
                space = live.space(at: Slot(screen: screen, desktop: desktop))
            } else if screen == "builtin", let found = live.space(at: Slot(screen: screen, desktop: desktop)),
                      nameRecord(space: found) == nil {
                // Etkin olmayan kurulumun laptop satırı: laptop masaüstüleri
                // ortak; etkin kurulumda o sıra adsızsa aynı gerçek masaüstü.
                let current = plans.entries(live.mode, "builtin")
                if desktop > current.count || current[desktop - 1].isEmpty { space = found }
            }
        }
        if let found = space, nameRecord(space: found) != nil { space = nil }
        let ghost = ghostDesktops.first { $0.name.map(Self.normalizedName) == Self.normalizedName(trimmed) }
        var id = UUID().uuidString
        if let reused = ghost?.nameID, nameRecord(reused) == nil, !plans.ids(.docked).contains(reused),
           !plans.ids(.undocked).contains(reused) {
            id = reused
        }
        names.append(DesktopName(id: id, name: trimmed, space: space))
        plans.put(id, at: desktop, mode, screen)
        let other = Self.otherMode(mode)
        var twinIndex: Int?
        if screen == "builtin" {
            twinIndex = placeBuiltinTwin(id, desktop: desktop, mode: other)
        } else if mode == .docked {
            // N1: monitördeki ad laptop planının sonuna (macOS çıkarışta oraya koyar).
            var entries = plans.entries(.undocked, "builtin")
            entries.append(id)
            plans.set(entries, .undocked, "builtin")
        }
        // Bu sıradaki numara pinleri ad pini olur (laptop: öbür kurulumda da aynı sıradaysa).
        var list = rules
        for i in list.indices {
            for m in Mode.allCases {
                guard var destination = list[i][m], destination.nameID == nil,
                      destination.screen == screen, destination.desktop == desktop else { continue }
                guard m == mode || (m == other && twinIndex == desktop) else { continue }
                destination.nameID = id
                list[i][m] = destination
            }
        }
        if list != rules { rules = list }
        absorbGhosts(named: trimmed, into: id, live: live)
        return true
    }

    /// Laptop adının öbür kurulumdaki yeri: aynı sıra boşsa (ya da planın
    /// ötesindeyse) oraya, değilse sona. Yazılan sırayı döndürür.
    @discardableResult
    private mutating func placeBuiltinTwin(_ id: String, desktop: Int, mode: Mode) -> Int {
        var entries = plans.entries(mode, "builtin")
        if desktop > entries.count || entries[desktop - 1].isEmpty {
            plans.put(id, at: desktop, mode, "builtin")
            return desktop
        }
        entries.append(id)
        plans.set(entries, mode, "builtin")
        return entries.count
    }

    /// Adı kaldırır (13c): kayıt silinir, plan girdileri "" olur, ad pinleri
    /// bulundukları yerde numara pini olur.
    mutating func removeName(_ id: String) {
        names.removeAll { $0.id == id }
        plans.remove(id, mode: .docked, collapse: false)
        plans.remove(id, mode: .undocked, collapse: false)
        var list = rules
        for i in list.indices {
            for m in Mode.allCases where list[i][m]?.nameID == id { list[i][m]?.nameID = nil }
        }
        if list != rules { rules = list }
    }

    /// Bu adlı hayaletler tüketilir: pinleri ad pini olarak döner.
    mutating func absorbGhosts(named name: String, into id: String, live: LiveDesktops?) {
        let want = Self.normalizedName(name)
        while let index = ghostDesktops.firstIndex(where: { $0.name.map(Self.normalizedName) == want }) {
            let ghost = ghostDesktops.remove(at: index)
            let record = nameRecord(id)
            let plans = self.plans
            applyGhostPins(ghost.pins) { pin in
                var destination = pin.destination
                destination.nameID = id
                var slot: Slot?
                if let live, live.mode == pin.mode, let space = record?.space {
                    slot = live.place(of: space)
                }
                if slot == nil { slot = plans.place(of: id, mode: pin.mode) }
                if let slot {
                    destination.screen = slot.screen
                    destination.desktop = slot.desktop
                }
                return destination
            }
        }
    }

    // MARK: - Uygulama içi silme (B satırı 14)

    /// Masaüstü olmayan (yerleşmemiş) adı siler: kayıt gider, iki planın
    /// girdisi düşer, ad pinleri adlı hayalete.
    @discardableResult
    mutating func deleteName(_ id: String, now: Date = Date()) -> GhostDesktop? {
        guard let record = nameRecord(id) else { return nil }
        let place = plans.place(of: id, mode: .docked) ?? plans.place(of: id, mode: .undocked)
        var pins: [GhostDesktop.Pin] = []
        var kept: [Rule] = []
        for original in rules {
            var rule = original
            for m in Mode.allCases where rule[m]?.nameID == id {
                pins.append(.init(profileID: activeProfileID, mode: m, rule: original,
                                  destination: rule[m]!))
                rule[m] = nil
            }
            if rule.docked != nil || rule.undocked != nil { kept.append(rule) }
        }
        if kept != rules { rules = kept }
        names.removeAll { $0.id == id }
        plans.remove(id, mode: .docked, collapse: true)
        plans.remove(id, mode: .undocked, collapse: true)
        let ghost = GhostDesktop(screen: place?.screen ?? "builtin", name: record.name,
                                 desktop: place?.desktop ?? 1, deletedAt: now, pins: pins,
                                 nameID: id, cause: GhostDesktop.deletedCause)
        ghostDesktops.append(ghost)
        return ghost
    }

    /// Etkin olmayan kurulumun planından satır siler: girdi düşer (sonrakiler
    /// bir yukarı), o kurulumun o sıradaki numara pinleri hayalete, sonrakiler
    /// bir yukarı. Yerleşmemiş adın satırıysa ad silinir (`deleteName`).
    /// Canlı bir masaüstüne bağlı adın satırında ad yaşamaya devam eder;
    /// yalnız bu kurulumun planından çıkar (o kurulumun görüşü kalmaz).
    @discardableResult
    mutating func removePlanEntry(screen: String, desktop: Int, mode: Mode,
                                  now: Date = Date()) -> GhostDesktop? {
        var entries = plans.entries(mode, screen)
        let entry = desktop >= 1 && desktop <= entries.count ? entries[desktop - 1] : ""
        if !entry.isEmpty, let record = nameRecord(entry), record.space == nil {
            return deleteName(entry, now: now)
        }
        var pins: [GhostDesktop.Pin] = []
        var kept: [Rule] = []
        for original in rules {
            var rule = original
            if var destination = rule[mode], destination.nameID == nil, destination.screen == screen {
                if destination.desktop == desktop {
                    pins.append(.init(profileID: activeProfileID, mode: mode, rule: original,
                                      destination: destination))
                    rule[mode] = nil
                } else if destination.desktop > desktop {
                    destination.desktop -= 1
                    rule[mode] = destination
                }
            }
            if rule.docked != nil || rule.undocked != nil { kept.append(rule) }
        }
        if kept != rules { rules = kept }
        if desktop >= 1, desktop <= entries.count {
            entries.remove(at: desktop - 1)
            plans.set(entries, mode, screen)
        }
        guard !pins.isEmpty else { return nil }
        let ghost = GhostDesktop(screen: screen, name: nil, desktop: desktop, deletedAt: now,
                                 pins: pins, nameID: nil, cause: GhostDesktop.deletedCause)
        ghostDesktops.append(ghost)
        return ghost
    }

    // MARK: - Sıralama ve ekranlar arası taşıma (B satırları 15–16)

    /// Bir ekrandaki masaüstünü başka sıraya taşır. `sharedLaptop`: etkin
    /// kurulum (laptop ekranında numara pinleri iki kurulumda kayar, bütün
    /// profiller). `liveSpaces`: pencereler gerçekten taşındıysa ekranın
    /// sıralı space'leri: içerik `old → mapping[old]` taşındı, her profilin
    /// adları içerikle gider (R5) ve her profilin etkin kurulum planı aynı
    /// permütasyonla döner. Değilse yalnız etkin profilin planı döner.
    /// Ad pinleri kaymaz (önbellekleri sonra yenilenir).
    mutating func moveDesktop(on screen: String, from: Int, to: Int, count: Int, mode: Mode,
                              sharedLaptop: Bool = false, liveSpaces: [UInt64]? = nil) {
        guard let mapping = Self.desktopMapping(from: from, to: to, count: count) else { return }
        let modes = sharedLaptop && screen == "builtin" ? Mode.allCases : [mode]
        let active = activeProfileID
        func remap(_ list: inout [Rule], _ profileID: String) {
            guard sharedLaptop || profileID == active else { return }
            for i in list.indices {
                for m in modes {
                    guard var destination = list[i][m], destination.nameID == nil,
                          destination.screen == screen,
                          let updated = mapping[destination.desktop] else { continue }
                    destination.desktop = updated
                    list[i][m] = destination
                }
            }
        }
        mapAllRules(remap)
        if let liveSpaces {
            var table: [UInt64: UInt64] = [:]
            for (old, new) in mapping where old >= 1 && new >= 1
                && old <= liveSpaces.count && new <= liveSpaces.count {
                table[liveSpaces[old - 1]] = liveSpaces[new - 1]
            }
            applySpaceMap(table)
        }
        func permute(_ plans: inout DesktopPlans) {
            let entries = plans.entries(mode, screen)
            guard !entries.isEmpty else { return }
            let total = max(count, entries.count, from, to)
            var padded = entries + Array(repeating: "", count: total - entries.count)
            var result = Array(repeating: "", count: total)
            for (index, entry) in padded.enumerated() {
                result[(mapping[index + 1] ?? index + 1) - 1] = entry
            }
            padded = result
            let lastNamed = padded.lastIndex { !$0.isEmpty }.map { $0 + 1 } ?? 0
            plans.set(Array(padded.prefix(max(entries.count, lastNamed))), mode, screen)
        }
        permute(&plans)
        if liveSpaces != nil {
            for i in profiles.indices where profiles[i].id != activeProfileID {
                var other = profiles[i].plans
                permute(&other)
                if other != profiles[i].plans { profiles[i].plans = other }
            }
        }
    }

    /// Bir masaüstünü başka ekranın `to` sırasına taşır: numara pinleri
    /// `acrossPlacement` ile, plan girdisi kaynak listeden hedef listeye.
    /// `spaceMap`: etkin kurulumda içerik gerçekten taşındıysa eski → yeni
    /// space (R5, bütün profiller; planlar da bütün profillerde taşınır).
    mutating func moveDesktopAcross(from fromScreen: String, desktop from: Int,
                                    to toScreen: String, at to: Int, toCount: Int, mode: Mode,
                                    spaceMap: [UInt64: UInt64]? = nil) {
        guard fromScreen != toScreen, from >= 1, to >= 1 else { return }
        let physical = spaceMap != nil
        let active = activeProfileID
        mapAllRules { list, profileID in
            guard physical || profileID == active else { return }
            for i in list.indices {
                guard var destination = list[i][mode], destination.nameID == nil,
                      let next = Self.acrossPlacement(
                        screen: destination.screen, desktop: destination.desktop,
                        from: fromScreen, desktop: from, to: toScreen, at: to)
                else { continue }
                destination.screen = next.screen
                destination.desktop = next.desktop
                list[i][mode] = destination
            }
        }
        if let spaceMap { applySpaceMap(spaceMap) }
        func move(_ plans: inout DesktopPlans) {
            var source = plans.entries(mode, fromScreen)
            var target = plans.entries(mode, toScreen)
            while source.count < from { source.append("") }
            let entry = source.remove(at: from - 1)
            while target.count < max(toCount, to - 1) { target.append("") }
            target.insert(entry, at: min(to - 1, target.count))
            plans.set(source, mode, fromScreen)
            plans.set(target, mode, toScreen)
        }
        move(&plans)
        if physical {
            for i in profiles.indices where profiles[i].id != activeProfileID {
                var other = profiles[i].plans
                move(&other)
                if other != profiles[i].plans { profiles[i].plans = other }
            }
        }
    }

    /// Etkin olmayan kurulumda masaüstü ekler: plan "" ile `count`'a uzar.
    mutating func planDesktop(on screen: String, mode: Mode, count: Int) {
        var entries = plans.entries(mode, screen)
        guard count > entries.count else { return }
        while entries.count < count { entries.append("") }
        plans.set(entries, mode, screen)
    }

    // MARK: - Hayaleti geri getirme

    /// Hayaleti `desktop` numaralı (yeni açılmış) masaüstüne geri getirir.
    /// Adlı hayalet: ad (aynı adlı canlı ad varsa o) yeniden kurulur ve
    /// bütün pinleri ad pini olur. Adsız: yalnız bu kurulumun pinleri o
    /// masaüstüne numara pini olarak döner, öbürleri hayalette kalır.
    mutating func restoreGhost(_ id: String, desktop: Int, space: UInt64? = nil, mode: Mode = .docked,
                               live: LiveDesktops? = nil) {
        guard let index = ghostDesktops.firstIndex(where: { $0.id == id }) else { return }
        var ghost = ghostDesktops.remove(at: index)
        let screen = ghost.screen
        if let name = ghost.name {
            var record = nameRecord(named: name)
            if record == nil {
                var reusedID = UUID().uuidString
                if let old = ghost.nameID, nameRecord(old) == nil { reusedID = old }
                let created = DesktopName(id: reusedID, name: name,
                                          space: space.flatMap { nameRecord(space: $0) == nil ? $0 : nil })
                names.append(created)
                plans.put(created.id, at: desktop, mode, screen)
                if screen == "builtin" {
                    placeBuiltinTwin(created.id, desktop: desktop, mode: Self.otherMode(mode))
                } else if mode == .docked, plans.place(of: created.id, mode: .undocked) == nil {
                    var entries = plans.entries(.undocked, "builtin")
                    entries.append(created.id)
                    plans.set(entries, .undocked, "builtin")
                }
                record = created
            }
            guard let record else { return }
            let plans = self.plans
            applyGhostPins(ghost.pins) { pin in
                var destination = pin.destination
                destination.nameID = record.id
                var slot: Slot?
                if let live, live.mode == pin.mode, let bound = record.space { slot = live.place(of: bound) }
                if slot == nil { slot = plans.place(of: record.id, mode: pin.mode) }
                if pin.mode == mode, slot == nil { slot = Slot(screen: screen, desktop: desktop) }
                if let slot {
                    destination.screen = slot.screen
                    destination.desktop = slot.desktop
                }
                return destination
            }
            return
        }
        let own = ghost.pins.filter { $0.mode == mode }
        let others = ghost.pins.filter { $0.mode != mode }
        applyGhostPins(own) { pin in
            var destination = pin.destination
            destination.screen = screen
            destination.desktop = desktop
            destination.nameID = nil
            return destination
        }
        if !others.isEmpty {
            ghost.pins = others
            ghostDesktops.insert(ghost, at: min(index, ghostDesktops.count))
        }
    }

    mutating func discardGhost(_ id: String) {
        ghostDesktops.removeAll { $0.id == id }
    }

    // MARK: - Planı kopyalama (B satırı 20)

    /// Kaynak kurulumun laptop planı hedefin laptop planı olur; o adlar
    /// hedefin öbür ekran planlarından "" olarak düşer. Adlar kopyalanmaz
    /// (kuruluma bağlı değiller).
    mutating func copyPlan(from source: Mode, to target: Mode) {
        guard source != target else { return }
        let laptop = plans.entries(source, "builtin")
        guard !laptop.isEmpty || !plans.entries(target, "builtin").isEmpty else { return }
        let ids = Set(laptop.filter { !$0.isEmpty })
        for (role, list) in plans[target] where role != "builtin" {
            plans.set(list.map { ids.contains($0) ? "" : $0 }, target, role)
        }
        plans.set(laptop, target, "builtin")
    }

    // MARK: - R4: kanıt yok

    /// Space'i canlı olmayan adlar (yeniden başlatma, geri yükleme, içe
    /// aktarma): etkin kurulumun planındaki yerindeki masaüstüne, o masaüstü
    /// profilin başka adına bağlı değilse bağlanır; değilse yerleşmemiş.
    /// Bütün profiller (her biri kendi planıyla).
    mutating func bindByPlan(live: LiveDesktops) {
        func bind(_ names: inout [DesktopName], _ plans: DesktopPlans) {
            let alive = live.all
            var claimed = Set(names.compactMap { $0.space.flatMap { alive.contains($0) ? $0 : nil } })
            for i in names.indices {
                if let space = names[i].space, alive.contains(space) { continue }
                names[i].space = nil
                guard let slot = plans.place(of: names[i].id, mode: live.mode),
                      let space = live.space(at: slot), !claimed.contains(space) else { continue }
                names[i].space = space
                claimed.insert(space)
            }
        }
        var active = names
        bind(&active, plans)
        if active != names { names = active }
        for i in profiles.indices where profiles[i].id != activeProfileID {
            var other = profiles[i].names
            bind(&other, profiles[i].plans)
            if other != profiles[i].names { profiles[i].names = other }
        }
    }
}
