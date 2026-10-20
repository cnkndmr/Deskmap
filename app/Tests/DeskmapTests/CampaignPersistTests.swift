import Foundation
import Testing
@testable import Deskmap

/// Kayıt kampanyası (Tablo D6, D5.7, D6.5): sıralı yer listesi (`docked` +
/// `dockedNext`), ekran rolü ek alanları, yedekten geri yükleme, profil
/// dışa/içe aktarma, kopyalama, upsert ve daha yeni sürüm dosyası. Her test
/// bellekte çalışır (Store(demo:)); gerçek veri klasörüne dokunmaz.
struct CampaignPersistTests {

    // MARK: Yardımcılar

    private static let dell = Destination(screen: "external", desktop: 2, layout: .leftHalf)
    private static let lg = Destination(screen: "external-2", desktop: 1, layout: .full)
    private static let book = Destination(screen: "builtin", desktop: 3, layout: .rightHalf)

    private func safari(id: String = "safari", places: [Destination]) -> Rule {
        var rule = Rule(id: id, appName: "Safari", bundleID: "com.apple.Safari", tokens: [])
        rule.setPlaces(places, mode: .docked)
        return rule
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeRule(_ json: String) throws -> Rule {
        try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
    }

    private func decodeDocument(_ json: String) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    }

    private func roundTrip(_ doc: Document) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Store.encode(doc))
    }

    private func document(rules: [Rule], name: String = "Work") -> Document {
        var doc = Document()
        doc.profiles[0].name = name
        doc.rules = rules
        doc.syncActiveProfile()
        return doc
    }

    // MARK: Kural kodlama ve çözme (D6.1 - D6.4)

    /// D6.1: `docked` listenin ilk yeri, geri kalanı `dockedNext`'te, sırayla.
    @Test func d6_1_encodesFirstPlaceInDockedAndRestInDockedNext() throws {
        let rule = safari(places: [Self.lg, Self.dell, Self.book])
        let object = try encodeJSON(rule)
        let docked = try #require(object["docked"] as? [String: Any])
        #expect(docked["screen"] as? String == "external-2")
        let next = try #require(object["dockedNext"] as? [[String: Any]])
        #expect(next.map { $0["screen"] as? String } == ["external", "builtin"])
    }

    @Test func emptyDockedNextIsNotWritten() throws {
        let single = try encodeJSON(safari(places: [Self.dell]))
        #expect(single["dockedNext"] == nil)
        #expect(single["docked"] != nil)
        // Liste boşaltılınca da alan kalmaz.
        var rule = safari(places: [Self.dell, Self.lg])
        rule.removePlace(at: 1, mode: .docked)
        #expect(try encodeJSON(rule)["dockedNext"] == nil)
    }

    @Test func rulePlacesRoundTripKeepOrderLayoutAndNameID() throws {
        var named = Self.book
        named.nameID = "NAME-1"
        let rule = safari(places: [Self.lg, named, Self.dell])
        let back = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        #expect(back.places(.docked) == [Self.lg, named, Self.dell])
        #expect(back.places(.docked)[1].nameID == "NAME-1")
        #expect(back.places(.docked)[2].layout == .leftHalf)
    }

    /// D6.2: 0.5.0 dosyası (yalnız `docked`) tek yerli liste olur.
    @Test func d6_2_oldFileWithoutDockedNextIsSinglePlaceList() throws {
        let rule = try decodeRule("""
        {"id":"a","appName":"Safari","bundleID":"com.apple.Safari","tokens":[],
         "docked":{"screen":"external","desktop":2,"layout":{"x":0,"y":0,"w":0.5,"h":1}}}
        """)
        #expect(rule.places(.docked).count == 1)
        #expect(rule.dockedNext.isEmpty)
        #expect(rule.docked?.desktop == 2)
    }

    /// D6.3/D6.4: eski sürüm yalnız `docked`'ı görüp kaydeder; yeni sürüm
    /// açınca liste `1. LG · 1`'e düşmüştür (belgelenmiş kayıp), bozulmaz.
    @Test func d6_4_oldVersionSaveDropsDockedNextButKeepsFirstPlace() throws {
        let rule = safari(places: [Self.lg, Self.dell])
        var object = try encodeJSON(rule)
        object["dockedNext"] = nil // eski sürümün yeniden yazımı
        let data = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Rule.self, from: data)
        #expect(back.places(.docked) == [Self.lg])
        #expect(back.id == rule.id)
    }

    @Test func d6_1_corruptDockedNextItemsAreSkippedOthersKeepOrder() throws {
        let rule = try decodeRule("""
        {"id":"a","appName":"Safari","bundleID":"b","tokens":[],
         "docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},
         "dockedNext":[{"screen":"external-2","desktop":"x","layout":{"x":0,"y":0,"w":1,"h":1}},
                       null, 7,
                       {"screen":"builtin","desktop":4,"layout":{"x":0,"y":0,"w":1,"h":1}},
                       {"screen":"external-3","desktop":2,"layout":"nonsense"}]}
        """)
        #expect(rule.places(.docked).map(\.screen) == ["external", "builtin"])
        #expect(rule.dockedNext.first?.desktop == 4)
    }

    @Test func dockedNextOfWrongTypeDoesNotLoseTheRule() throws {
        for bad in [#""oops""#, "5", #"{"a":1}"#, "null"] {
            let rule = try decodeRule("""
            {"id":"a","appName":"Safari","bundleID":"b","tokens":["x"],
             "docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},"dockedNext":\(bad)}
            """)
            #expect(rule.places(.docked).count == 1, "bad=\(bad)")
            #expect(rule.tokens == ["x"])
        }
    }

    /// `docked` yok ama `dockedNext` var (elle düzenlenmiş dosya): sıradaki
    /// ilk yer olur, yer kaybolmaz.
    @Test func dockedNextWithoutDockedPromotesFirstEntry() throws {
        let rule = try decodeRule("""
        {"id":"a","appName":"Safari","bundleID":"b","tokens":[],
         "dockedNext":[{"screen":"external","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}},
                       {"screen":"builtin","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}}]}
        """)
        #expect(rule.docked?.screen == "external")
        #expect(rule.dockedNext.map(\.screen) == ["builtin"])
        #expect(rule.places(.docked).count == 2)
    }

    @Test func initIgnoresDockedNextWhenThereIsNoDocked() {
        let rule = Rule(appName: "Safari", bundleID: "b", tokens: [],
                        docked: nil, undocked: Self.book, dockedNext: [Self.dell])
        #expect(rule.dockedNext.isEmpty)
        #expect(rule.places(.docked).isEmpty)
        #expect(rule.places(.undocked) == [Self.book])
    }

    /// Doğrudan atanmış tutarsız durum (docked yok, dockedNext var) yazılır
    /// ve okununca kendini toparlar; yer kaybolmaz.
    @Test func inconsistentInMemoryRuleHealsOnRoundTrip() throws {
        var rule = safari(places: [Self.dell])
        rule.docked = nil
        rule.dockedNext = [Self.lg]
        let back = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        #expect(back.places(.docked) == [Self.lg])
    }

    @Test func dockedNextDesktopNumbersClampToOne() throws {
        let rule = try decodeRule("""
        {"id":"a","appName":"Safari","bundleID":"b","tokens":[],
         "docked":{"screen":"external","desktop":0,"layout":{"x":0,"y":0,"w":1,"h":1}},
         "dockedNext":[{"screen":"builtin","desktop":-3,"layout":{"x":0,"y":0,"w":1,"h":1}}]}
        """)
        #expect(rule.places(.docked).map(\.desktop) == [1, 1])
    }

    @Test func undockedPlaceIsIndependentOfDockedList() throws {
        var rule = safari(places: [Self.lg, Self.dell])
        rule.undocked = Self.book
        let back = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        #expect(back.places(.undocked) == [Self.book])
        #expect(back.places(.docked) == [Self.lg, Self.dell])
        // Laptop modunda liste tek yerdir; dockedNext oraya sızmaz.
        #expect(back.places(.undocked).count == 1)
    }

    // MARK: Belge düzeyi gidiş dönüş

    @Test func documentRoundTripKeepsListsInActiveAndInactiveProfiles() throws {
        var doc = document(rules: [safari(id: "a", places: [Self.lg, Self.dell])])
        let other = doc.addProfile(named: "Home", activate: false)
        doc.profiles[doc.profiles.firstIndex { $0.id == other.id }!].rules =
            [safari(id: "b", places: [Self.dell, Self.book, Self.lg])]
        let back = try roundTrip(doc)
        #expect(back.rules.first?.places(.docked) == [Self.lg, Self.dell])
        let home = try #require(back.profiles.first { $0.name == "Home" })
        #expect(home.rules.first?.places(.docked) == [Self.dell, Self.book, Self.lg])
    }

    @Test func oneCorruptRuleDoesNotAffectNeighbourListsAndIsCounted() throws {
        let doc = try decodeDocument("""
        {"version":6,"rules":[
          {"id":"a","appName":"Safari","bundleID":"b","tokens":[],
           "docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},
           "dockedNext":[{"screen":"builtin","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}}]},
          "garbage",
          {"id":"c","appName":"Mail","bundleID":"m","tokens":[],
           "docked":{"screen":"external-2","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},
           "dockedNext":[{"screen":"external","desktop":3,"layout":{"x":0,"y":0,"w":1,"h":1}}]}]}
        """)
        #expect(doc.droppedRuleCount == 1)
        #expect(doc.rules.map { $0.places(.docked).count } == [2, 2])
        #expect(doc.rules[1].dockedNext.first?.desktop == 3)
    }

    // MARK: Ekran rolü ek alanları

    @Test func defaultDisplayRolesWritesNoOptionalFields() throws {
        let roles = DisplayRoles()
        let object = try encodeJSON(roles)
        #expect(object["lastDesktopCount"] == nil)
        #expect(object["monitorNames"] == nil)
        // Belge düzeyinde de hiçbir yeni alan çıkmaz.
        let doc = try encodeJSON(document(rules: []))
        #expect(doc["displayRoles"] == nil)
        #expect(doc["missionControlMoves"] == nil)
    }

    @Test func learnedRolesWithoutOptionalFieldsOmitThem() throws {
        let roles = DisplayRoles(remembered: ["external": ["AAA"]])
        let object = try encodeJSON(roles)
        #expect(object["remembered"] != nil)
        #expect(object["lastDesktopCount"] == nil && object["monitorNames"] == nil)
    }

    @Test func desktopCountsAndNamesRoundTripNormalized() throws {
        var roles = DisplayRoles(remembered: ["external": ["AAA"]])
        roles.lastDesktopCount = ["AAA": 3]
        roles.monitorNames = ["AAA": "Acme View 27"]
        let back = try JSONDecoder().decode(DisplayRoles.self, from: JSONEncoder().encode(roles))
        #expect(back == roles)
        // Elle yazılmış süslü parantezli, küçük harfli anahtar normalleşir.
        let loose = try JSONDecoder().decode(DisplayRoles.self, from: Data("""
        {"remembered":{"external":["{aaa}"]},"lastDesktopCount":{"{aaa}":4},
         "monitorNames":{" bbb ":"LG UltraFine"}}
        """.utf8))
        #expect(loose.lastDesktopCount == ["AAA": 4])
        #expect(loose.monitorNames == ["BBB": "LG UltraFine"])
        #expect(loose.lastDesktopCount(role: "external") == 4)
    }

    @Test func invalidCountsAndEmptyNamesAreDroppedOnRead() throws {
        let roles = try JSONDecoder().decode(DisplayRoles.self, from: Data("""
        {"remembered":{},"lastDesktopCount":{"A":0,"B":-2,"C":5},
         "monitorNames":{"A":"","B":"Dell U2723"}}
        """.utf8))
        #expect(roles.lastDesktopCount == ["C": 5])
        #expect(roles.monitorNames == ["B": "Dell U2723"])
    }

    @Test func malformedOptionalFieldsDoNotDiscardRememberedRoles() throws {
        let roles = try JSONDecoder().decode(DisplayRoles.self, from: Data("""
        {"remembered":{"external":["AAA"]},"lastDesktopCount":"x","monitorNames":[1,2]}
        """.utf8))
        #expect(roles.remembered == ["external": ["AAA"]])
        #expect(roles.lastDesktopCount.isEmpty && roles.monitorNames.isEmpty)
    }

    @Test func keysCollidingAfterNormalizationDoNotCrash() throws {
        let roles = try JSONDecoder().decode(DisplayRoles.self, from: Data("""
        {"remembered":{},"lastDesktopCount":{"{abc}":2,"ABC":3},"monitorNames":{"{abc}":"A","ABC":"B"}}
        """.utf8))
        #expect(roles.lastDesktopCount.count == 1)
        #expect(roles.monitorNames.count == 1)
    }

    /// Yalnız masaüstü sayısı öğrenilmiş (rol yok) belge de yazılır.
    @Test func documentWithOnlyDesktopCountsStillWritesDisplayRoles() throws {
        var doc = document(rules: [])
        doc.displayRoles.lastDesktopCount = ["AAA": 2]
        let back = try roundTrip(doc)
        #expect(back.displayRoles.lastDesktopCount == ["AAA": 2])
    }

    @Test func oldDisplayRolesFileDecodesWithEmptyNewFields() throws {
        let doc = try decodeDocument("""
        {"version":6,"rules":[],"displayRoles":{"remembered":{"external":["AAA"]},
         "fallbackToFirstExternal":false,"learnedOnce":true}}
        """)
        #expect(doc.displayRoles.remembered == ["external": ["AAA"]])
        #expect(doc.displayRoles.fallbackToFirstExternal == false)
        #expect(doc.displayRoles.lastDesktopCount.isEmpty)
    }

    @Test func missionControlSettingDefaultNotWrittenOthersRoundTrip() throws {
        var doc = document(rules: [])
        #expect(doc.missionControlMoves == .revert)
        for setting in [DesktopRevert.Setting.ask, .leave] {
            doc.missionControlMoves = setting
            let object = try JSONSerialization.jsonObject(with: Store.encode(doc)) as? [String: Any]
            #expect(object?["missionControlMoves"] as? String == setting.rawValue)
            #expect(try roundTrip(doc).missionControlMoves == setting)
        }
        doc.missionControlMoves = .revert
        let object = try JSONSerialization.jsonObject(with: Store.encode(doc)) as? [String: Any]
        #expect(object?["missionControlMoves"] == nil)
    }

    @Test func unknownMissionControlSettingFallsBackToDefault() throws {
        let doc = try decodeDocument(#"{"version":6,"rules":[],"missionControlMoves":"teleport"}"#)
        #expect(doc.missionControlMoves == .revert)
        #expect(try decodeDocument(#"{"version":6,"rules":[],"missionControlMoves":5}"#)
            .missionControlMoves == .revert)
    }

    // MARK: Yedekten geri yükleme (D6.5)

    @MainActor @Test func d6_5_restoreKeepsListsAndOrderFromBackupInEveryProfile() throws {
        var backup = document(rules: [safari(id: "a", places: [Self.lg, Self.dell, Self.book])],
                              name: "Office")
        let home = backup.addProfile(named: "Home", activate: false)
        backup.profiles[backup.profiles.firstIndex { $0.id == home.id }!].rules =
            [safari(id: "b", places: [Self.book, Self.dell])]
        // Dosya üzerinden: yedek baytları aynı yoldan geçer.
        let restoredBackup = try roundTrip(backup)
        let store = Store(demo: document(rules: [safari(places: [Self.dell])], name: "Other"))
        #expect(store.restoreBackup(restoredBackup))
        #expect(store.document.rules[0].places(.docked) == [Self.lg, Self.dell, Self.book])
        let restoredHome = try #require(store.document.profiles.first { $0.name == "Home" })
        #expect(restoredHome.rules[0].places(.docked) == [Self.book, Self.dell])
    }

    /// Roller bu Mac'in monitörlerine aittir: yedekteki roller ve ekranlar
    /// canlı olanı ezmez.
    @MainActor @Test func restoreKeepsCurrentDisplayRolesAndScreens() throws {
        var backup = document(rules: [safari(places: [Self.lg, Self.dell])])
        backup.displayRoles = DisplayRoles(remembered: ["external": ["OLD-MONITOR"]])
        backup.displayRoles.lastDesktopCount = ["OLD-MONITOR": 9]
        backup.screens = [KnownScreen(id: "external", name: "Old", aspect: 1.5)]
        var current = document(rules: [])
        current.displayRoles = DisplayRoles(remembered: ["external": ["NEW-MONITOR"]])
        current.displayRoles.lastDesktopCount = ["NEW-MONITOR": 2]
        current.screens = [KnownScreen(id: "external", name: "Current", aspect: 1.78)]
        let store = Store(demo: current)
        #expect(store.restoreBackup(backup))
        #expect(store.document.displayRoles.remembered == ["external": ["NEW-MONITOR"]])
        #expect(store.document.displayRoles.lastDesktopCount == ["NEW-MONITOR": 2])
        #expect(store.document.screens.map(\.name) == ["Current"])
        #expect(store.document.rules[0].places(.docked) == [Self.lg, Self.dell])
    }

    @MainActor @Test func restoreUndoBringsBackPreviousLists() throws {
        let store = Store(demo: document(rules: [safari(places: [Self.dell, Self.lg])]))
        let backup = document(rules: [safari(places: [Self.book])])
        #expect(store.restoreBackup(backup))
        #expect(store.document.rules[0].places(.docked) == [Self.book])
        store.undo()
        #expect(store.document.rules[0].places(.docked) == [Self.dell, Self.lg])
        store.redo()
        #expect(store.document.rules[0].places(.docked) == [Self.book])
    }

    /// Daha yeni sürümün dosyasından gelen yedek reddedilir, belge değişmez.
    @MainActor @Test func restoreRejectedWhenBackupIsFromNewerVersionKeepsDocument() throws {
        let original = document(rules: [safari(places: [Self.dell, Self.lg])])
        let store = Store(demo: original)
        var newer = document(rules: [safari(places: [Self.book])])
        newer.fileVersion = Document.currentVersion + 1
        #expect(!store.restoreBackup(newer))
        #expect(store.document.rules[0].places(.docked) == [Self.dell, Self.lg])
        #expect(!store.history.canUndo)
    }

    /// Salt okunur oturumda (dosya daha yeni sürümden) yedek yüklenmez.
    @MainActor @Test func readOnlyStoreRefusesRestoreAndReportsNewerVersion() throws {
        var newerDoc = document(rules: [safari(places: [Self.dell, Self.lg])])
        newerDoc.fileVersion = Document.currentVersion + 1
        let store = Store(demo: newerDoc)
        #expect(store.isReadOnly)
        #expect(!store.restoreBackup(document(rules: [])))
        #expect(store.lastError == Store.newerVersionMessage)
        #expect(store.document.rules[0].places(.docked) == [Self.dell, Self.lg])
    }

    // MARK: Daha yeni sürüm dosyası

    @Test func newerVersionFileKeepsListsReadsUnknownFieldsHarmlesslyAndIsFlagged() throws {
        let doc = try decodeDocument("""
        {"version":7,"futureField":{"a":1},"rules":[
          {"id":"a","appName":"Safari","bundleID":"b","tokens":[],"futureRuleField":true,
           "docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1},"extra":1},
           "dockedNext":[{"screen":"builtin","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}}]}]}
        """)
        #expect(doc.isFromNewerVersion)
        #expect(!doc.needsNameMigration)
        #expect(doc.rules[0].places(.docked).count == 2)
        #expect(doc.droppedRuleCount == 0)
    }

    @Test func nonNumericVersionIsTreatedAsOldNotNewer() throws {
        let doc = try decodeDocument(#"{"version":"7","rules":[]}"#)
        #expect(!doc.isFromNewerVersion)
        #expect(doc.fileVersion == 1)
    }

    // MARK: Eski şema yükseltmesiyle etkileşim

    /// Şema 5 dosyasının sıralı yerleri geçişte (kanıtsız) kaybolmaz.
    @Test func schemaFiveMigrationKeepsNumberTargetsInDockedNext() throws {
        let doc = try decodeDocument("""
        {"version":5,"rules":[
          {"id":"a","appName":"Safari","bundleID":"b","tokens":[],
           "docked":{"screen":"external-2","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}},
           "dockedNext":[{"screen":"external","desktop":2,"layout":{"x":0,"y":0,"w":0.5,"h":1}}]}]}
        """)
        #expect(doc.needsNameMigration)
        let migrated = MigrationV6.migrate(doc, evidence: nil).document
        #expect(migrated.rules[0].places(.docked).map(\.screen) == ["external-2", "external"])
        #expect(migrated.rules[0].places(.docked).map(\.desktop) == [1, 2])
    }

    // MARK: Profil dışa / içe aktarma

    private func exportImport(_ source: Document, profile: String? = nil,
                              into target: Document) throws -> (Document, Profile) {
        let id = profile ?? source.activeProfileID
        let data = try source.exportData(for: id)
        var target = target
        let imported = try target.importProfile(from: data)
        return (target, imported)
    }

    @Test func exportImportKeepsListOrderWithFreshRuleIDs() throws {
        let source = document(rules: [safari(id: "orig", places: [Self.lg, Self.dell, Self.book])])
        let (target, imported) = try exportImport(source, into: Document())
        #expect(imported.rules.count == 1)
        #expect(imported.rules[0].places(.docked) == [Self.lg, Self.dell, Self.book])
        #expect(imported.rules[0].id != "orig")
        #expect(target.rules[0].places(.docked) == [Self.lg, Self.dell, Self.book])
        #expect(target.activeProfileID == imported.id)
    }

    /// Ad kimlikleri `dockedNext` içinde de yeni kimliğe eşlenir (yalnız
    /// `docked` değil).
    @Test func importRemapsNameIDsInsideDockedNext() throws {
        var source = document(rules: [])
        var first = Self.lg; first.nameID = "N-MAIL"
        var second = Self.dell; second.nameID = "N-CHAT"
        source.rules = [safari(places: [first, second])]
        source.names = [DesktopName(id: "N-MAIL", name: "Mail"), DesktopName(id: "N-CHAT", name: "Chat")]
        source.plans.put("N-MAIL", at: 1, .docked, "external-2")
        source.plans.put("N-CHAT", at: 2, .docked, "external")
        source.syncActiveProfile()
        let (_, imported) = try exportImport(source, into: Document())
        let ids = Set(imported.names.map(\.id))
        #expect(imported.names.map(\.name).sorted() == ["Chat", "Mail"])
        let places = imported.rules[0].places(.docked)
        #expect(places.count == 2)
        for place in places {
            let id = try #require(place.nameID)
            #expect(ids.contains(id))
            #expect(id != "N-MAIL" && id != "N-CHAT")
        }
        #expect(places[0].nameID != places[1].nameID)
        let mail = try #require(imported.names.first { $0.name == "Mail" })
        #expect(places[0].nameID == mail.id)
        #expect(imported.names.allSatisfy { $0.space == nil })
    }

    /// Dosyada adı olmayan bir ad kimliği: yer numara hedefine döner
    /// (kimlik taşınmaz), liste ve sıra bozulmaz.
    @Test func importDropsUnknownNameIDButKeepsPlaceInList() throws {
        var source = document(rules: [])
        var ghost = Self.dell; ghost.nameID = "NOT-IN-FILE"
        source.rules = [safari(places: [Self.lg, ghost])]
        source.names = [DesktopName(id: "OTHER", name: "Other")]
        source.syncActiveProfile()
        let (_, imported) = try exportImport(source, into: Document())
        let places = imported.rules[0].places(.docked)
        #expect(places.count == 2)
        #expect(places[1].nameID == nil)
        #expect(places[1].screen == "external" && places[1].desktop == 2)
    }

    @Test func exportUsesLiveWorkingCopyWithoutPriorSync() throws {
        var source = document(rules: [safari(places: [Self.dell])])
        source.rules[0].setPlaces([Self.dell, Self.lg], mode: .docked) // profil kaydı henüz eski
        let (_, imported) = try exportImport(source, into: Document())
        #expect(imported.rules[0].places(.docked) == [Self.dell, Self.lg])
    }

    @Test func exportCarriesNoMonitorIdentityOrSettings() throws {
        var source = document(rules: [safari(places: [Self.lg, Self.dell])])
        source.displayRoles = DisplayRoles(remembered: ["external": ["SERIAL-AAA"]])
        source.displayRoles.lastDesktopCount = ["SERIAL-AAA": 3]
        source.displayRoles.monitorNames = ["SERIAL-AAA": "Acme View"]
        source.missionControlMoves = .leave
        let text = String(decoding: try source.exportData(for: source.activeProfileID), as: UTF8.self)
        #expect(!text.contains("SERIAL-AAA"))
        #expect(!text.contains("displayRoles"))
        #expect(!text.contains("missionControlMoves"))
        #expect(!text.contains("lastDesktopCount"))
        #expect(text.contains("dockedNext"))
    }

    /// İçe aktarma hedefin ekran rollerine, ayarlarına ve masaüstü sayılarına
    /// dokunmaz.
    @Test func importLeavesTargetDisplayRolesAndSettingsAlone() throws {
        let source = document(rules: [safari(places: [Self.lg, Self.dell])])
        var target = Document()
        target.displayRoles = DisplayRoles(remembered: ["external": ["MINE"]])
        target.displayRoles.lastDesktopCount = ["MINE": 4]
        target.missionControlMoves = .ask
        let (result, _) = try exportImport(source, into: target)
        #expect(result.displayRoles == target.displayRoles)
        #expect(result.missionControlMoves == .ask)
    }

    @Test func importTwiceGivesDistinctProfilesAndRuleIDs() throws {
        let source = document(rules: [safari(places: [Self.lg, Self.dell])], name: "Trip")
        let data = try source.exportData(for: source.activeProfileID)
        var target = Document()
        let a = try target.importProfile(from: data)
        let b = try target.importProfile(from: data)
        #expect(a.name == "Trip" && b.name != "Trip")
        #expect(a.id != b.id)
        #expect(a.rules[0].id != b.rules[0].id)
        #expect(b.rules[0].places(.docked) == [Self.lg, Self.dell])
        // İlk profilin kuralları ikinci içe aktarmada değişmez.
        let stored = try #require(target.profiles.first { $0.id == a.id })
        #expect(stored.rules[0].places(.docked) == [Self.lg, Self.dell])
    }

    @Test func importOfFileWithoutDockedNextGivesSinglePlaceLists() throws {
        let data = Data("""
        {"kind":"deskmap-profile","version":2,"name":"Legacy","rules":[
          {"id":"x","appName":"Safari","bundleID":"b","tokens":[],
           "docked":{"screen":"external","desktop":1,"layout":{"x":0,"y":0,"w":1,"h":1}}}]}
        """.utf8)
        var target = Document()
        let imported = try target.importProfile(from: data)
        #expect(imported.rules[0].places(.docked).count == 1)
        #expect(imported.rules[0].id != "x")
    }

    @Test func importOfInvalidJSONThrowsAndLeavesDocumentUntouched() throws {
        var target = document(rules: [safari(places: [Self.dell, Self.lg])])
        let before = target
        #expect(throws: (any Error).self) {
            try target.importProfile(from: Data("not json".utf8))
        }
        #expect(target == before)
    }

    /// Profil olmayan ama geçerli bir JSON nesnesi "Bu bir Deskmap profili
    /// değil" hatasını vermeli; kind alanı yokken varsayılan değere
    /// düştüğü için koruma hiç tetiklenmiyor, boş bir "Imported" profili
    /// eklenip etkinleştiriliyor.
    @Test func importOfForeignJSONObjectIsRejectedWithoutChangingDocument() throws {
        var target = document(rules: [safari(places: [Self.dell, Self.lg])])
        let before = target
        withKnownIssue("campaign: foreign JSON object imports as an empty profile (kind defaults)") {
            #expect(throws: (any Error).self) {
                try target.importProfile(from: Data(#"{"hello":"world"}"#.utf8))
            }
            #expect(target == before)
        }
    }

    @MainActor @Test func storeImportIsOneUndoStepAndKeepsLists() throws {
        let source = document(rules: [safari(places: [Self.lg, Self.dell])], name: "Imported")
        let data = try source.exportData(for: source.activeProfileID)
        let store = Store(demo: document(rules: [safari(places: [Self.book])], name: "Mine"))
        let imported = try store.importProfile(from: data)
        #expect(store.document.activeProfileID == imported.id)
        #expect(store.document.rules[0].places(.docked) == [Self.lg, Self.dell])
        store.undo()
        #expect(store.document.profiles.map(\.name) == ["Mine"])
        #expect(store.document.rules[0].places(.docked) == [Self.book])
    }

    // MARK: Profil kopyası / çoğaltma (D5.7)

    @Test func d5_7_duplicateCopiesListsInSameOrderWithNewRuleIDs() throws {
        var doc = document(rules: [
            safari(id: "a", places: [Self.lg, Self.dell, Self.book]),
            safari(id: "b", places: [Self.dell]),
        ])
        let sourceID = doc.activeProfileID
        let made = doc.duplicateProfile(sourceID, named: "Work copy")
        let copy = try #require(made)
        #expect(copy.rules.map { $0.places(.docked) }
                == [[Self.lg, Self.dell, Self.book], [Self.dell]])
        let sourceIDs = Set(doc.rules.map(\.id))
        #expect(copy.rules.allSatisfy { !sourceIDs.contains($0.id) })
        #expect(Set(copy.rules.map(\.id)).count == 2)
        #expect(doc.activeProfileID == sourceID) // etkin profil değişmez
    }

    @Test func duplicateIsIndependentOfSourceWhenEditedAfterwards() throws {
        var doc = document(rules: [safari(id: "a", places: [Self.lg, Self.dell])])
        let made = doc.duplicateProfile(doc.activeProfileID, named: "Copy")
        let copy = try #require(made)
        let copyIndex = try #require(doc.profiles.firstIndex { $0.id == copy.id })
        doc.profiles[copyIndex].rules[0].removePlace(at: 0, mode: .docked)
        doc.profiles[copyIndex].rules[0].dockedNext.append(Self.book)
        #expect(doc.rules[0].places(.docked) == [Self.lg, Self.dell])
        #expect(doc.profiles[copyIndex].rules[0].places(.docked) == [Self.dell, Self.book])
    }

    @Test func duplicateCopiesUnsyncedWorkingRules() throws {
        var doc = document(rules: [safari(places: [Self.dell])])
        doc.rules[0].setPlaces([Self.dell, Self.lg], mode: .docked)
        let made = doc.duplicateProfile(doc.activeProfileID, named: "Copy")
        let copy = try #require(made)
        #expect(copy.rules[0].places(.docked) == [Self.dell, Self.lg])
    }

    @Test func copyStateRemapsGhostPinRuleIDsAndKeepsPinLists() {
        let rule = safari(id: "old", places: [Self.lg, Self.dell])
        var source = Profile(id: "SRC", name: "Src", rules: [rule])
        let pin = GhostDesktop.Pin(profileID: "SRC", mode: .docked, rule: rule,
                                   destination: Self.dell, order: 1)
        source.ghostDesktops = [GhostDesktop(id: "G", screen: "external", desktop: 2,
                                             deletedAt: Date(timeIntervalSince1970: 0), pins: [pin])]
        var target = Profile(id: "DST", name: "Dst")
        Document.copyState(of: source, into: &target)
        let newRule = target.rules[0]
        #expect(newRule.id != "old")
        let ghost = target.ghostDesktops[0]
        #expect(ghost.id != "G")
        #expect(ghost.pins[0].profileID == "DST")
        #expect(ghost.pins[0].rule.id == newRule.id)
        #expect(ghost.pins[0].rule.places(.docked) == [Self.lg, Self.dell])
        #expect(ghost.pins[0].order == 1)
        // Kaynak dokunulmamış.
        #expect(source.rules[0].id == "old")
        #expect(source.ghostDesktops[0].pins[0].profileID == "SRC")
    }

    @Test func addProfileCopyingCurrentCarriesListsAndSurvivesRoundTrip() throws {
        var doc = document(rules: [safari(places: [Self.lg, Self.dell])])
        let added = doc.addProfile(named: "Next", copyingCurrent: true, activate: true)
        #expect(added.rules[0].places(.docked) == [Self.lg, Self.dell])
        #expect(doc.rules[0].places(.docked) == [Self.lg, Self.dell])
        let back = try roundTrip(doc)
        #expect(back.profiles.count == 2)
        #expect(back.profiles.allSatisfy { $0.rules[0].places(.docked) == [Self.lg, Self.dell] })
    }

    @MainActor @Test func storeDuplicateUndoRemovesCopyAndKeepsSourceLists() throws {
        let store = Store(demo: document(rules: [safari(places: [Self.lg, Self.dell])]))
        let copy = try #require(store.duplicateProfile(store.document.activeProfileID, named: "Copy"))
        #expect(store.document.profiles.count == 2)
        store.undo()
        #expect(!store.document.profiles.contains { $0.id == copy.id })
        #expect(store.document.rules[0].places(.docked) == [Self.lg, Self.dell])
    }

    // MARK: upsertProfile

    @Test func upsertReplacesRulesByNameIncludingDockedNextAndKeepsID() {
        var doc = document(rules: [safari(places: [Self.dell])], name: "Work")
        let workID = doc.activeProfileID
        let home = doc.addProfile(named: "Home", activate: false)
        let incoming = Profile(name: "Work", rules: [safari(id: "n", places: [Self.lg, Self.dell, Self.book])])
        let result = doc.upsertProfile(incoming, activate: false)
        #expect(result.id == workID)
        #expect(doc.rules[0].places(.docked) == [Self.lg, Self.dell, Self.book]) // etkin: canlı kopya
        #expect(doc.profiles.first { $0.id == workID }?.rules[0].places(.docked).count == 3)
        #expect(doc.profiles.first { $0.id == home.id }?.rules.isEmpty == true)
    }

    /// Gelen profilde liste yoksa eski profilin uzun listesi kalmaz
    /// (kurallar bütünüyle değişir, birleştirilmez).
    @Test func upsertWithSinglePlaceRuleDropsStaleDockedNext() {
        var doc = document(rules: [safari(id: "a", places: [Self.lg, Self.dell, Self.book])])
        doc.upsertProfile(Profile(name: "Work", rules: [safari(id: "a", places: [Self.dell])]),
                          activate: false)
        #expect(doc.rules[0].places(.docked) == [Self.dell])
        #expect(doc.rules[0].dockedNext.isEmpty)
    }

    @Test func upsertIntoInactiveProfileLeavesWorkingRulesAlone() {
        var doc = document(rules: [safari(places: [Self.lg, Self.dell])], name: "Work")
        let home = doc.addProfile(named: "Home", activate: false)
        doc.upsertProfile(Profile(name: "Home", rules: [safari(places: [Self.book, Self.lg])]),
                          activate: false)
        #expect(doc.rules[0].places(.docked) == [Self.lg, Self.dell])
        #expect(doc.profiles.first { $0.id == home.id }?.rules[0].places(.docked) == [Self.book, Self.lg])
        #expect(doc.activeProfileID != home.id)
    }

    @Test func upsertNewNameWithClashingIDGetsFreshIDAndKeepsLists() {
        var doc = document(rules: [safari(places: [Self.dell])], name: "Work")
        let clashing = Profile(id: doc.activeProfileID, name: "Brand new",
                               rules: [safari(places: [Self.lg, Self.book])])
        let result = doc.upsertProfile(clashing, activate: true)
        #expect(result.id != clashing.id)
        #expect(doc.activeProfileID == result.id)
        #expect(doc.rules[0].places(.docked) == [Self.lg, Self.book])
        #expect(doc.profiles.count == 2)
        // Eski etkin profilin listesi, geçişte kendi kaydına yazılmış kalır.
        #expect(doc.profiles.first { $0.name == "Work" }?.rules[0].places(.docked) == [Self.dell])
    }

    @Test func upsertMatchesNameExactlyNotCaseInsensitively() {
        var doc = document(rules: [safari(places: [Self.dell])], name: "Work")
        doc.upsertProfile(Profile(name: "work", rules: [safari(places: [Self.lg])]), activate: false)
        #expect(doc.profiles.count == 2)
        #expect(doc.rules[0].places(.docked) == [Self.dell])
    }

    @MainActor @Test func storeUpsertActivateSwitchesAndLoadsListsInOneUndoStep() throws {
        let store = Store(demo: document(rules: [safari(places: [Self.dell])], name: "Work"))
        store.upsertProfile(Profile(name: "Trip", rules: [safari(places: [Self.lg, Self.book])]),
                            activate: true)
        #expect(store.document.rules[0].places(.docked) == [Self.lg, Self.book])
        store.undo()
        #expect(store.document.profiles.map(\.name) == ["Work"])
        #expect(store.document.rules[0].places(.docked) == [Self.dell])
    }
}
