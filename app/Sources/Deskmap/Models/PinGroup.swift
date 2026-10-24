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
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
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
}

/// `pinGroups` alanının hoşgörülü okunuşu: dizi değilse ya da öğeleri
/// bozuksa belge düşmez, okunabilen gruplar (kimlikleri tekil) kalır.
struct LenientPinGroups: Decodable {
    var groups: [PinGroup] = []

    init(from decoder: Decoder) throws {
        groups = PinGroup.deduplicated((try? LossyArray<PinGroup>(from: decoder))?.elements ?? [])
    }
}

/// `Document.resolvePinGroup` sonucu: kimlik ya da ad bir gruba çözülür.
enum PinGroupLookup: Equatable {
    case found(String)
    case missing
    /// Aynı adlı birden çok grup: kimlik verilmeli.
    case ambiguous([String])
}
