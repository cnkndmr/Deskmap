import Foundation
import Testing
@testable import Deskmap

/// Pin gruplarının saf belge işlemleri: oluşturma, ad, üyelik, dağıtma,
/// K7 (boş grup yalnız açık işlemle düşer), hayalet ve profil yolları.
struct PinGroupModelTests {

    private func at(_ screen: String, _ desktop: Int) -> Destination {
        Destination(screen: screen, desktop: desktop)
    }

    private func pdf(_ id: String, desktop: Int = 3, undocked: Int? = nil,
                     group: String? = nil) -> Rule {
        Rule(id: id, appName: "Preview", bundleID: "com.apple.Preview", tokens: [id],
             docked: at("builtin", desktop), undocked: undocked.map { at("builtin", $0) },
             groupID: group)
    }

    /// `#require` makrosu değiştiren çağrıyı sarmalayamıyor; değer önce hesaplanır.
    private func req<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }

    private func document(_ rules: [Rule]) -> Document {
        var d = Document()
        d.rules = rules
        d.syncActiveProfile()
        return d
    }

    // MARK: - Oluşturma

    @Test func createSkipsUnknownRulesAndNeedsOneValid() throws {
        var d = document([pdf("a"), pdf("b")])
        let r1 = d.createPinGroup(name: "X", ruleIDs: ["nope"])
        #expect(r1 == nil)
        #expect(d.pinGroups.isEmpty)
        let made = try req(d.createPinGroup(name: "  Nova drafts  ", ruleIDs: ["a", "nope", "b", "a"]))
        #expect(made.pulled == 0)
        #expect(d.pinGroup(made.id)?.name == "Nova drafts")
        #expect(d.rules.map(\.groupID) == [made.id, made.id])
    }

    @Test func createPullsFromAnotherGroupAndDropsTheEmptiedOne() throws {
        var d = document([pdf("a"), pdf("b")])
        let first = try req(d.createPinGroup(name: "One", ruleIDs: ["a"]))
        let second = try req(d.createPinGroup(name: "Two", ruleIDs: ["a", "b"]))
        #expect(second.pulled == 1)
        #expect(d.pinGroup(first.id) == nil)
        #expect(d.pinGroups.map(\.name) == ["Two"])
    }

    // MARK: - Ad

    @Test func namesAreTrimmedDefaultedAndMayRepeat() throws {
        var d = document([pdf("a"), pdf("b"), pdf("c")])
        let g1 = try req(d.createPinGroup(name: "   ", ruleIDs: ["a"]))
        #expect(d.pinGroup(g1.id)?.name == "Group 1")
        let g2 = try req(d.createPinGroup(name: nil, ruleIDs: ["b"]))
        #expect(d.pinGroup(g2.id)?.name == "Group 2")
        // İlk boş numara: "Group 1" yeniden adlanınca 1 boşalır.
        let r2 = d.renamePinGroup(g1.id, to: "Docs")
        #expect(r2)
        #expect(d.defaultPinGroupName() == "Group 1")
        // Boş ad reddedilir, eski ad kalır.
        let before = d
        let r3 = d.renamePinGroup(g1.id, to: " \n ")
        #expect(!r3)
        #expect(d == before)
        let r4 = d.renamePinGroup("missing", to: "X")
        #expect(!r4)
        // Yinelenen ad kabul edilir.
        let r5 = d.renamePinGroup(g2.id, to: "Docs")
        #expect(r5)
        #expect(d.pinGroups.map(\.name) == ["Docs", "Docs"])
        _ = try req(d.createPinGroup(name: "Docs", ruleIDs: ["c"]))
        #expect(d.pinGroups.count == 3)
    }

    // MARK: - Dağıtma ve çıkarma

    @Test func dissolveKeepsPinsAndClearsMembership() throws {
        var d = document([pdf("a"), pdf("b")])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a", "b"]))
        d.dissolvePinGroup(g.id)
        #expect(d.pinGroups.isEmpty)
        #expect(d.rules.count == 2)
        #expect(d.rules.allSatisfy { $0.groupID == nil })
    }

    @Test func removeAndAdd() throws {
        var d = document([pdf("a"), pdf("b"), pdf("c")])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a", "b"]))
        d.removeFromPinGroup(ruleIDs: ["a"])
        #expect(d.rule("a")?.groupID == nil)
        let r6 = d.addToPinGroup(g.id, ruleIDs: ["c", "nope"])
        #expect(r6 == 0)
        #expect(d.rule("c")?.groupID == g.id)
        let r7 = d.addToPinGroup("missing", ruleIDs: ["a"])
        #expect(r7 == nil)
        // Ekleme/çıkarma tek işlemde; başka grubun üyesi `remove`'da çıkmaz.
        let other = try req(d.createPinGroup(name: "H", ruleIDs: ["a"]))
        let r8 = d.editPinGroupMembers(g.id, add: ["a"], remove: ["b"])
        #expect(r8 == 1)
        #expect(d.rule("a")?.groupID == g.id)
        #expect(d.rule("b")?.groupID == nil)
        #expect(d.pinGroup(other.id) == nil)
        d.removeFromPinGroup(ruleIDs: ["a", "c"])
        #expect(d.pinGroups.isEmpty)
    }

    // MARK: - K7: boş grup yalnız açık işlemle düşer

    @Test func lastMemberGoingAwayKeepsTheRecordUntilTheNextGroupAction() throws {
        var d = document([pdf("a"), pdf("b")])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a"]))
        d.unpin("a", mode: .docked)
        #expect(d.rule("a") == nil)
        #expect(d.pinGroup(g.id) != nil)
        #expect(d.pinGroupMembers(g.id, mode: .docked).isEmpty)
        // Bir sonraki açık işlem düşürür.
        _ = d.createPinGroup(name: "Other", ruleIDs: ["b"])
        #expect(d.pinGroup(g.id) == nil)
    }

    @Test func aGroupReferencedOnlyByAGhostSurvives() throws {
        var d = document([pdf("a", desktop: 3), pdf("b", desktop: 1)])
        let g = try req(d.createPinGroup(name: "Nova drafts", ruleIDs: ["a"]))
        let ghost = try req(d.recordDeletion(space: nil, role: "builtin", desktop: 3, mode: .docked))
        #expect(d.rule("a") == nil)
        #expect(ghost.pins.first?.rule.groupID == g.id)
        d.dropEmptyPinGroups()
        #expect(d.pinGroup(g.id) != nil)
        _ = d.createPinGroup(name: "Other", ruleIDs: ["b"])
        #expect(d.pinGroup(g.id) != nil)
    }

    /// Bütün üyeleri tek masaüstündeki grup: masaüstü silinir, hayalet geri
    /// getirilir; ad ve üyelik geri gelir.
    @Test func ghostRoundTripBringsNameAndMembershipBack() throws {
        var d = document([pdf("a"), pdf("b"), pdf("c", desktop: 1)])
        let g = try req(d.createPinGroup(name: "Nova drafts", ruleIDs: ["a", "b"]))
        let ghost = try req(d.recordDeletion(space: nil, role: "builtin", desktop: 3, mode: .docked))
        #expect(d.rules.map(\.id) == ["c"])
        #expect(d.pinGroup(g.id)?.name == "Nova drafts")
        d.restoreGhost(ghost.id, desktop: 3)
        #expect(Set(d.pinGroupMembers(g.id, mode: .docked).map(\.id)) == ["a", "b"])
        #expect(d.pinGroup(g.id)?.name == "Nova drafts")
        // Kayda da işlenir.
        d.syncActiveProfile()
        #expect(d.activeProfile?.pinGroups.map(\.id) == [g.id])
    }

    /// Hayalet öncesi grubu dağıtılmışsa geri gelen kuralın kimliği sahipsiz
    /// kalır: grupsuz sayılır, sonraki açık işlem temizler.
    @Test func dissolvedBeforeRestoreLeavesAnOrphanThatReadsAsUngrouped() throws {
        var d = document([pdf("a"), pdf("c", desktop: 1)])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a"]))
        let ghost = try req(d.recordDeletion(space: nil, role: "builtin", desktop: 3, mode: .docked))
        d.dissolvePinGroup(g.id)
        // Dağıtma hayalet kopyasını da temizler.
        #expect(d.ghostDesktops.first?.pins.first?.rule.groupID == nil)
        d.restoreGhost(ghost.id, desktop: 3)
        #expect(d.rule("a")?.groupID == nil)
    }

    /// `inProfileScope` çalışma kopyasının gruplarını da taşır: senkronize
    /// edilmemiş grup ilgisiz masaüstü silmesinde kaybolmaz.
    @Test func profileScopeKeepsUnsyncedGroups() throws {
        var d = document([pdf("a"), pdf("c", desktop: 1)])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a"]))
        // syncActiveProfile çağrılmadı: kayıtta grup yok.
        #expect(d.activeProfile?.pinGroups.isEmpty == true)
        d.recordDeletion(space: nil, role: "external", desktop: 2, mode: .docked)
        #expect(d.pinGroup(g.id) != nil)
        #expect(d.rule("a")?.groupID == g.id)
        // Etkisiz kapsam belgeyi değiştirmez.
        let before = d
        d.inProfileScope(d.activeProfileID) { _ in }
        #expect(d == before)
    }

    // MARK: - Profiller

    @Test func duplicateAndCopyRenewGroupIDsAndKeepTheMapping() throws {
        var d = document([pdf("a"), pdf("b", desktop: 1)])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a", "b"]))
        // Hayalet pin kopyası da eşlenmeli.
        d.recordDeletion(space: nil, role: "builtin", desktop: 3, mode: .docked)
        d.syncActiveProfile()
        let source = try #require(d.activeProfile)
        let copy = try req(d.duplicateProfile(d.activeProfileID, named: "Copy"))
        let newGroup = try #require(copy.pinGroups.first)
        #expect(copy.pinGroups.count == 1)
        #expect(newGroup.id != g.id)
        #expect(newGroup.name == "G")
        #expect(copy.rules.allSatisfy { $0.groupID == newGroup.id })
        #expect(copy.ghostDesktops.flatMap(\.pins).allSatisfy { $0.rule.groupID == newGroup.id })
        // Kaynak değişmez.
        #expect(d.profiles.first { $0.id == source.id } == source)
        // Eşlenmeyen kimlik düşer.
        var orphan = source
        orphan.rules[0].groupID = "unknown"
        var target = Profile(name: "T")
        Document.copyState(of: orphan, into: &target)
        #expect(target.rules[0].groupID == nil)
    }

    @Test func switchingProfilesKeepsGroups() throws {
        var d = document([pdf("a")])
        let home = d.activeProfileID
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a"]))
        let other = d.addProfile(named: "Other", activate: true)
        #expect(d.pinGroups.isEmpty)
        d.switchProfile(to: home)
        #expect(d.pinGroup(g.id)?.name == "G")
        #expect(d.rule("a")?.groupID == g.id)
        _ = other
    }

    /// `upsertProfile`: var olan aktif profilde yalnız kurallar değişir;
    /// senkronize edilmemiş gruplar korunur, `groupID`'li kural gelirse
    /// üyelik görünür.
    @Test func upsertKeepsUnsyncedGroupsOfTheActiveProfile() throws {
        var d = document([pdf("a"), pdf("b")])
        let name = try #require(d.activeProfile?.name)
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a"]))
        let incoming = Profile(name: name, rules: [pdf("a", group: g.id), pdf("b"), pdf("n", group: g.id)])
        let target = d.upsertProfile(incoming, activate: false)
        // Önce-senkron (§1.3): elle senkron olmadan profil kaydı ve dönen
        // profil grupları taşımalı; o satır silinirse ikisi de boş kalır.
        #expect(target.pinGroups.map(\.id) == [g.id])
        #expect(d.activeProfile?.pinGroups.map(\.id) == [g.id])
        #expect(d.pinGroup(g.id)?.name == "G")
        #expect(Set(d.pinGroupMembers(g.id, mode: .docked).map(\.id)) == ["a", "n"])
        // Kaydedilip okununca da durur.
        let back = try JSONDecoder().decode(Document.self, from: Store.encode(d))
        #expect(back.pinGroup(g.id) != nil)
    }

    @Test func movingADesktopKeepsMembership() throws {
        var d = document([pdf("a"), pdf("b")])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a", "b"]))
        d.moveDesktop(on: "builtin", from: 3, to: 1, count: 4, mode: .docked)
        #expect(d.rules.allSatisfy { $0.groupID == g.id })
        #expect(d.rule("a")?.docked?.desktop == 1)
    }

    @Test func membersOfAModeNeedAPlaceThere() throws {
        var d = document([pdf("a", undocked: 2), pdf("b")])
        let g = try req(d.createPinGroup(name: "G", ruleIDs: ["a", "b"]))
        #expect(d.pinGroupMembers(g.id, mode: .docked).map(\.id) == ["a", "b"])
        #expect(d.pinGroupMembers(g.id, mode: .undocked).map(\.id) == ["a"])
    }

    @Test func resolveByIDNameAmbiguousAndMissing() throws {
        var d = document([pdf("a"), pdf("b"), pdf("c")])
        let g1 = try req(d.createPinGroup(name: "Nova", ruleIDs: ["a"]))
        let g2 = try req(d.createPinGroup(name: "Same", ruleIDs: ["b"]))
        let g3 = try req(d.createPinGroup(name: "same", ruleIDs: ["c"]))
        #expect(d.resolvePinGroup(g1.id) == .found(g1.id))
        #expect(d.resolvePinGroup(" nOVA ") == .found(g1.id))
        #expect(d.resolvePinGroup("SAME") == .ambiguous([g2.id, g3.id]))
        #expect(d.resolvePinGroup("Nov") == .missing)
    }

    // MARK: - Dışa / içe aktarma

    @Test func exportV5RoundTripsAndImportRenewsIDs() throws {
        var d = document([pdf("a"), pdf("b")])
        let g = try req(d.createPinGroup(name: "Nova drafts", ruleIDs: ["a"]))
        let data = try d.exportData(for: d.activeProfileID)
        let payload = try JSONDecoder.iso.decode(ProfileExport.self, from: data)
        #expect(payload.version == 5)
        #expect(payload.pinGroups == [PinGroup(id: g.id, name: "Nova drafts")])
        let imported = try d.importProfile(from: data)
        let group = try #require(imported.pinGroups.first)
        #expect(group.id != g.id && group.name == "Nova drafts")
        #expect(imported.rules.filter { $0.groupID == group.id }.count == 1)
        #expect(imported.rules.filter { $0.groupID != nil }.count == 1)
        #expect(d.pinGroup(group.id) != nil)
    }

    /// İçe aktarılan dosyadaki boş grup adı varsayılan adla gelir (K10).
    @Test func importFillsBlankGroupNames() throws {
        let json = """
        {"kind": "deskmap-profile", "version": 5, "name": "Blank", "exportedAt": "2026-01-01T00:00:00Z",
         "screens": [], "pinGroups": [{"id": "g", "name": "  "}],
         "rules": [{"id": "r", "appName": "Preview", "bundleID": "p", "tokens": ["x"], "groupID": "g",
                    "docked": {"screen": "builtin", "desktop": 1,
                               "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}}]}
        """
        var d = Document()
        let imported = try d.importProfile(from: Data(json.utf8))
        let group = try #require(imported.pinGroups.first)
        #expect(group.name == "Group 1")
        #expect(imported.rules[0].groupID == group.id)
    }

    @Test func v4ExportImportsWithoutGroups() throws {
        let json = """
        {"kind": "deskmap-profile", "version": 4, "name": "Old", "exportedAt": "2026-01-01T00:00:00Z",
         "screens": [], "rules": [{"id": "r", "appName": "Preview", "bundleID": "p", "tokens": ["x"],
                                   "groupID": "dangling",
                                   "docked": {"screen": "builtin", "desktop": 1,
                                              "layout": {"x": 0, "y": 0, "w": 1, "h": 1}}}]}
        """
        var d = Document()
        let imported = try d.importProfile(from: Data(json.utf8))
        #expect(imported.pinGroups.isEmpty)
        #expect(imported.rules.count == 1)
        #expect(imported.rules[0].groupID == nil)
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
