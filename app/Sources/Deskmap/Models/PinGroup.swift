import Foundation

/// Kullanıcının adlandırdığı pin grubu. Üyelik kuralda (`Rule.groupID`) durur;
/// burada yalnız kimlik ve ad var. Dizi sırası çizim sırasıdır. İsteğe bağlı
/// ek alan (`profiles[].pinGroups`), şema 6 değişmez: eski sürüm yok sayar.
struct PinGroup: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case id, name }

    /// Kimliği boş ya da adı olmayan kayıt okunmaz (`LossyArray` atlar).
    /// Ad kırpılır; boş kalan ad `LenientPinGroups`'ta varsayılan adla
    /// doldurulur (K10: grup adı hiç boş değil).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c,
                                                   debugDescription: "empty pin group id")
        }
    }

    /// Aynı kimlik ikinci kez gelirse atlanır (saf): `ForEach` kimlikleri
    /// çakışmasın. İlk görülen kalır.
    static func deduplicated(_ groups: [PinGroup]) -> [PinGroup] {
        var seen = Set<String>()
        return groups.filter { seen.insert($0.id).inserted }
    }

    /// İlk boşta "Grup N" adı (büyük/küçük harf duyarsız, saf).
    static func defaultName(taken: Set<String>) -> String {
        var n = 1
        while taken.contains(L("Group %ld", n).lowercased()) { n += 1 }
        return L("Group %ld", n)
    }

    /// Boş adlı kayıtlara sırayla boşta varsayılan ad verir (saf): elle
    /// düzenlenmiş rules.json ya da içe aktarılan dosya başlıksız kutu çizmesin.
    static func withNames(_ groups: [PinGroup]) -> [PinGroup] {
        var taken = Set(groups.map { $0.name.lowercased() })
        return groups.map { group in
            guard group.name.isEmpty else { return group }
            var named = group
            named.name = defaultName(taken: taken)
            taken.insert(named.name.lowercased())
            return named
        }
    }
}

/// `pinGroups` alanının hoşgörülü okunuşu: dizi değilse ya da öğeleri
/// bozuksa belge düşmez, okunabilen gruplar (kimlikleri tekil) kalır.
struct LenientPinGroups: Decodable {
    var groups: [PinGroup] = []

    init(from decoder: Decoder) throws {
        groups = PinGroup.withNames(
            PinGroup.deduplicated((try? LossyArray<PinGroup>(from: decoder))?.elements ?? []))
    }
}

/// `Document.resolvePinGroup` sonucu: kimlik ya da ad bir gruba çözülür.
enum PinGroupLookup: Equatable {
    case found(String)
    case missing
    /// Aynı adlı birden çok grup: kimlik verilmeli.
    case ambiguous([String])
}
