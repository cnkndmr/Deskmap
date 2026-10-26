import Foundation

// MARK: - Pin grupları (saf belge işlemleri)

/// Kullanıcı tanımlı pin grupları. Kayıt (`pinGroups`, ad ve kimlik)
/// aktif profilin çalışma kopyasında, üyelik kuralda (`Rule.groupID`).
/// Değişmezler (docs/architecture.md):
/// - Üyelik moda ve masaüstüne bağlı değil; bir moddaki üyeler o modda yeri
///   olan kurallardır (K2).
/// - Boş grup kendiliğinden silinmez: yükleme, masaüstü silme, profil ve
///   geri yükleme yolları kayda dokunmaz. Yalnız açık grup işlemlerinin
///   sonunda `dropEmptyPinGroups` düşürür (K7); yeniden adlandırma hariç
///   (boş grubu adlandırmak onu silmesin).
/// - Okuyan taraf bilinmeyen `groupID`'yi grupsuz sayar.
extension Document {

    /// Yeni grubun varsayılan adı: "Grup N", N ilk boş numara (>= 1).
    func defaultPinGroupName() -> String {
        PinGroup.defaultName(taken: Set(pinGroups.map { $0.name.lowercased() }))
    }

    /// Ad baştan ve sondan kırpılır; boşsa nil (saf).
    static func normalizedGroupName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func pinGroup(_ id: String) -> PinGroup? {
        pinGroups.first { $0.id == id }
    }

    /// Bu moddaki üyeler (kural sırasıyla): `groupID` eşleşen ve bu modda
    /// yeri olan kurallar.
    func pinGroupMembers(_ id: String, mode: Mode) -> [Rule] {
        rules.filter { $0.groupID == id && $0[mode] != nil }
    }

    /// Bir kimliği ya da harf duyarsız tam adı çözer. Aynı adlı birden çok
    /// grup varsa `.ambiguous` (kimlik verilmeli).
    func resolvePinGroup(_ text: String) -> PinGroupLookup {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if pinGroups.contains(where: { $0.id == trimmed }) { return .found(trimmed) }
        let hits = pinGroups.filter { $0.name.lowercased() == trimmed.lowercased() }
        switch hits.count {
        case 0: return .missing
        case 1: return .found(hits[0].id)
        default: return .ambiguous(hits.map(\.id))
        }
    }

    /// Var olan kural kimlikleri (tekrarsız, verilen sırayla).
    private func knownRuleIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let known = Set(rules.map(\.id))
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// Kuralları gruba alır; başka (var olan) bir gruptan çekilenlerin sayısı.
    private mutating func assign(_ ids: [String], to group: String) -> Int {
        let wanted = Set(ids)
        let known = Set(pinGroups.map(\.id))
        var pulled = 0
        for i in rules.indices where wanted.contains(rules[i].id) && rules[i].groupID != group {
            if let old = rules[i].groupID, known.contains(old) { pulled += 1 }
            rules[i].groupID = group
        }
        return pulled
    }

    /// Yeni grup kurar. Var olan kural kimlikleri üye olur (başka gruptaysa
    /// oradan çıkar). Geçerli kural yoksa nil. Dönen: yeni grup kimliği ve
    /// başka gruptan çekilen pin sayısı. Boş ad varsayılan adı alır.
    mutating func createPinGroup(name: String?, ruleIDs: [String]) -> (id: String, pulled: Int)? {
        let ids = knownRuleIDs(ruleIDs)
        guard !ids.isEmpty else { return nil }
        // Önce boş gruplar düşer: aynı işlemde silinecek boş "Grup 1" yeni
        // grubun varsayılan adından numara kapmasın.
        dropEmptyPinGroups()
        let group = PinGroup(name: name.flatMap(Self.normalizedGroupName) ?? defaultPinGroupName())
        pinGroups.append(group)
        let pulled = assign(ids, to: group.id)
        dropEmptyPinGroups()
        return (group.id, pulled)
    }

    /// Grubu yeniden adlandırır. Boş ad ya da olmayan grup: false, belge
    /// değişmez. Yinelenen ad kabul edilir (kimlik UUID). Budama yok: aynı
    /// adla onay belgeyi değiştirmez (geri alma kaydı düşmez) ve boş bir
    /// grubu yeniden adlandırmak onu silmez; başka boş grupları da düşürmez.
    @discardableResult
    mutating func renamePinGroup(_ id: String, to raw: String) -> Bool {
        guard let name = Self.normalizedGroupName(raw),
              let i = pinGroups.firstIndex(where: { $0.id == id }) else { return false }
        if pinGroups[i].name != name { pinGroups[i].name = name }
        return true
    }

    /// Kuralları var olan gruba ekler. Grup yoksa nil; dönen: başka gruptan
    /// çekilen pin sayısı.
    @discardableResult
    mutating func addToPinGroup(_ id: String, ruleIDs: [String]) -> Int? {
        guard pinGroup(id) != nil else { return nil }
        let pulled = assign(knownRuleIDs(ruleIDs), to: id)
        dropEmptyPinGroups()
        return pulled
    }

    /// Kuralları bulundukları gruptan çıkarır (pinler kalır).
    mutating func removeFromPinGroup(ruleIDs: [String]) {
        let wanted = Set(ruleIDs)
        for i in rules.indices where wanted.contains(rules[i].id) && rules[i].groupID != nil {
            rules[i].groupID = nil
        }
        dropEmptyPinGroups()
    }

    /// Tek adımda ekleme ve çıkarma (URL `group-set`): önce `remove`
    /// (yalnız bu grubun üyeleri), sonra `add`. Grup yoksa nil; dönen:
    /// başka gruptan çekilen pin sayısı.
    @discardableResult
    mutating func editPinGroupMembers(_ id: String, add: [String], remove: [String]) -> Int? {
        guard pinGroup(id) != nil else { return nil }
        let removing = Set(remove)
        for i in rules.indices where removing.contains(rules[i].id) && rules[i].groupID == id {
            rules[i].groupID = nil
        }
        let pulled = assign(knownRuleIDs(add), to: id)
        dropEmptyPinGroups()
        return pulled
    }

    /// Grubu dağıtır: üyeler pinli kalır, grup kimlikleri (hayalet pin
    /// kopyaları dahil) temizlenir, kayıt silinir.
    mutating func dissolvePinGroup(_ id: String) {
        guard pinGroups.contains(where: { $0.id == id }) else { return }
        pinGroups.removeAll { $0.id == id }
        dropEmptyPinGroups()
    }

    /// K7: sahipsiz `groupID`'leri (kurallar ve hayalet pin kopyaları) nil
    /// yapar, sonra hiç başvurusu (kural ya da hayalet) olmayan grupları
    /// düşürür. Yalnız aktif profilde (çalışma kopyası); yalnız açık grup
    /// işlemlerinin sonunda çağrılır.
    mutating func dropEmptyPinGroups() {
        let known = Set(pinGroups.map(\.id))
        for i in rules.indices {
            if let group = rules[i].groupID, !known.contains(group) { rules[i].groupID = nil }
        }
        for g in ghostDesktops.indices {
            for p in ghostDesktops[g].pins.indices {
                if let group = ghostDesktops[g].pins[p].rule.groupID, !known.contains(group) {
                    ghostDesktops[g].pins[p].rule.groupID = nil
                }
            }
        }
        var used = Set(rules.compactMap(\.groupID))
        for ghost in ghostDesktops { used.formUnion(ghost.pins.compactMap(\.rule.groupID)) }
        if pinGroups.contains(where: { !used.contains($0.id) }) {
            pinGroups.removeAll { !used.contains($0.id) }
        }
    }
}
