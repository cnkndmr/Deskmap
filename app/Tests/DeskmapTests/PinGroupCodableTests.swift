import Foundation
import Testing
@testable import Deskmap

/// Pin grupları `rules.json`'da: isteğe bağlı alanlar (`Rule.groupID`,
/// `profiles[].pinGroups`), eski dosyalar bozulmadan okunur, boşken yazılmaz.
struct PinGroupCodableTests {

    private func decode(_ json: String) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    }

    /// Grupsuz eski şema 6 dosyası: okunur, yeniden yazılınca yeni anahtar
    /// çıkmaz ve ikinci gidiş-dönüş bayt düzeyinde aynıdır.
    @Test func groupFreeV6FileRoundTripsByteForByte() throws {
        let json = """
        {"version": 6, "enabled": true, "screens": [], "activeProfileID": "p",
         "rules": [{"id": "r1", "appName": "Preview", "bundleID": "com.apple.Preview",
                    "tokens": ["a"], "docked": {"screen": "builtin", "desktop": 3,
                    "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}}],
         "profiles": [{"id": "p", "name": "Desk", "rules": []}]}
        """
        let doc = try decode(json)
        #expect(doc.rules.count == 1)
        #expect(doc.rules[0].groupID == nil)
        #expect(doc.activeProfile?.pinGroups.isEmpty == true)
        #expect(!doc.isFromNewerVersion)
        let first = try Store.encode(doc)
        let text = String(decoding: first, as: UTF8.self)
        #expect(!text.contains("groupID"))
        #expect(!text.contains("pinGroups"))
        let second = try Store.encode(try JSONDecoder().decode(Document.self, from: first))
        #expect(first == second)
    }

    /// Grup ve üyelik gidip gelir; sürüm 6 kalır.
    @Test func groupsRoundTrip() throws {
        var doc = Document()
        doc.rules = [Rule(id: "r1", appName: "Preview", bundleID: "p", tokens: ["a"],
                          docked: Destination(screen: "builtin", desktop: 3), groupID: "g1")]
        // Çalışma kopyası tek kaynak: yazarken aktif profile işlenir.
        doc.pinGroups = [PinGroup(id: "g1", name: "Nova drafts")]
        let data = try Store.encode(doc)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.rules[0].groupID == "g1")
        #expect(back.activeProfile?.pinGroups == [PinGroup(id: "g1", name: "Nova drafts")])
        #expect(back.pinGroups == [PinGroup(id: "g1", name: "Nova drafts")])
        // Üst düzeyde ayrıca yazılmaz.
        let top = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(top?["pinGroups"] == nil)
        #expect(back.version == 6 && !back.isFromNewerVersion)
        #expect(back.rules[0].routingProjection.groupID == nil)
    }

    /// Bozuk grup kayıtları (ad yok, yanlış tip, boş kimlik, yinelenen
    /// kimlik) belgeyi düşürmez; yinelenen kimlik tekilleşir.
    @Test func brokenGroupEntriesAreSkipped() throws {
        let json = """
        {"version": 6, "activeProfileID": "p",
         "rules": [{"id": "r1", "appName": "A", "bundleID": "a", "tokens": [], "groupID": 5},
                   {"id": "r2", "appName": "B", "bundleID": "b", "tokens": [], "groupID": ""},
                   {"id": "r3", "appName": "C", "bundleID": "c", "tokens": [], "groupID": "gone"}],
         "profiles": [{"id": "p", "name": "Desk", "rules": [],
                       "pinGroups": [{"id": "g1"}, 7, {"id": "", "name": "x"},
                                     {"id": "g2", "name": "Two"}, {"id": "g2", "name": "Dup"},
                                     {"id": "g3", "name": "Three"}]}]}
        """
        let doc = try decode(json)
        #expect(doc.rules.count == 3)
        #expect(doc.rules[0].groupID == nil)
        #expect(doc.rules[1].groupID == nil)
        // Bilinmeyen grup kimliği okunurken korunur.
        #expect(doc.rules[2].groupID == "gone")
        #expect(doc.activeProfile?.pinGroups.map(\.id) == ["g2", "g3"])
        #expect(doc.activeProfile?.pinGroups.first?.name == "Two")
        // Dizi olmayan alan da belgeyi düşürmez.
        let other = try decode(#"{"profiles": [{"id": "p", "name": "P", "pinGroups": "x"}]}"#)
        #expect(other.profiles.count == 1)
        #expect(other.profiles[0].pinGroups.isEmpty)
        #expect(!doc.isFromNewerVersion)
    }

    /// K10: boş ya da yalnız boşluk olan ad okunurken kırpılır ve ilk
    /// boşta varsayılan adı alır; dolu ad kırpılır, kayıt düşmez.
    @Test func blankGroupNamesGetDefaultNames() throws {
        let json = """
        {"version": 6, "activeProfileID": "p", "rules": [],
         "profiles": [{"id": "p", "name": "Desk", "rules": [],
                       "pinGroups": [{"id": "g1", "name": ""}, {"id": "g2", "name": "Group 1"},
                                     {"id": "g3", "name": "   "}, {"id": "g4", "name": "  Nova  "}]}]}
        """
        let doc = try decode(json)
        #expect(doc.activeProfile?.pinGroups.map(\.name) == ["Group 2", "Group 1", "Group 3", "Nova"])
        #expect(doc.activeProfile?.pinGroups.map(\.id) == ["g1", "g2", "g3", "g4"])
    }

    @Test func deduplicatedKeepsTheFirst() {
        let groups = [PinGroup(id: "a", name: "1"), PinGroup(id: "b", name: "2"), PinGroup(id: "a", name: "3")]
        #expect(PinGroup.deduplicated(groups) == [PinGroup(id: "a", name: "1"), PinGroup(id: "b", name: "2")])
    }

    /// Yönlendirme izdüşümü yalnız grubu atar; yer değişimi farkı korunur.
    @Test func routingProjectionIgnoresOnlyTheGroup() {
        let base = Rule(id: "r", appName: "A", bundleID: "a", tokens: ["x"],
                        docked: Destination(screen: "builtin", desktop: 1))
        var grouped = base
        grouped.groupID = "g"
        #expect(grouped != base)
        #expect(grouped.routingProjection == base.routingProjection)
        var moved = base
        moved.docked = Destination(screen: "builtin", desktop: 2)
        #expect(moved.routingProjection != base.routingProjection)
        #expect(grouped.sameKey(as: base))
    }
}
