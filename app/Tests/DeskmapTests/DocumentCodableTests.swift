import Foundation
import Testing
@testable import Deskmap

/// `rules.json` çözümleme: eski şemalar, varsayılanlar, hoşgörülü okuma.
struct DocumentCodableTests {

    private func decode(_ json: String) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(json.utf8))
    }

    @Test func plannedDesktopsRoundTripAndDefaultToEmpty() throws {
        var doc = try decode("{}")
        #expect(doc.plannedDesktops.isEmpty)
        #expect(doc.plannedDesktops(mode: .undocked, screen: "builtin") == 0)
        doc.setPlannedDesktops(10, mode: .undocked, screen: "builtin")
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.plannedDesktops(mode: .undocked, screen: "builtin") == 10)
        #expect(back.plannedDesktops(mode: .docked, screen: "builtin") == 0)
        doc.setPlannedDesktops(0, mode: .undocked, screen: "builtin")
        #expect(doc.plannedDesktops.isEmpty)
        // Bozuk alan belgeyi düşürmez.
        #expect(try decode(#"{"plannedDesktops": "x"}"#).plannedDesktops.isEmpty)
    }

    @Test func removingADesktopShiftsPinsAndPlan() {
        #expect(Document.removalMapping(desktop: 2, removed: 3) == 2)
        #expect(Document.removalMapping(desktop: 3, removed: 3) == 2)
        #expect(Document.removalMapping(desktop: 4, removed: 3) == 3)
        #expect(Document.removalMapping(desktop: 1, removed: 1) == 1)
        var doc = Document()
        doc.setPlannedDesktops(5, mode: .docked, screen: "external")
        doc.removeDesktop(on: "external", desktop: 2, mode: .docked)
        #expect(doc.plannedDesktops(mode: .docked, screen: "external") == 4)
        doc.removeDesktop(on: "builtin", desktop: 2, mode: .docked)
        #expect(doc.plannedDesktops(mode: .docked, screen: "external") == 4)
    }

    @Test func inactiveRemovalShiftsPinsNowAndQueuesRealRemoval() throws {
        var doc = Document()
        doc.rules = [Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                          undocked: Destination(screen: "builtin", desktop: 4))]
        doc.removeDesktopLater(on: "builtin", desktop: 2, mode: .undocked, existing: true, space: 5)
        #expect(doc.rules[0].undocked?.desktop == 3)
        #expect(doc.pendingRemovals(mode: .undocked, screen: "builtin")
                == [PendingRemoval(desktop: 2, space: 5)])
        // Gerçekte olmayan satır: yalnız numaralar kayar, sıraya girmez.
        doc.removeDesktopLater(on: "builtin", desktop: 3, mode: .undocked, existing: false, space: nil)
        #expect(doc.rules[0].undocked?.desktop == 2)
        #expect(doc.pendingRemovals(mode: .undocked, screen: "builtin").count == 1)
        let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(doc))
        #expect(back.pendingRemovals == doc.pendingRemovals)
        doc.clearPendingRemovals(mode: .undocked, screen: "builtin")
        #expect(doc.pendingRemovals.isEmpty)
    }

    @Test func realRemovalShiftsEveryModeAndProfile() {
        var doc = Document()
        let pin = Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                       docked: Destination(screen: "builtin", desktop: 4),
                       undocked: Destination(screen: "builtin", desktop: 5))
        doc.rules = [pin]
        doc.syncActiveProfile()
        doc.addProfile(named: "B", copyingCurrent: true)   // B etkin, A arkada
        doc.removeDesktop(on: "builtin", desktop: 2, modes: Mode.allCases)
        #expect(doc.rules[0].docked?.desktop == 3)
        #expect(doc.rules[0].undocked?.desktop == 4)
        let other = doc.profiles.first { $0.id != doc.activeProfileID }!
        #expect(other.rules[0].docked?.desktop == 3)
        #expect(other.rules[0].undocked?.desktop == 4)
    }

    @Test func pendingQueueDropsOnlyTheFirstEntry() {
        var doc = Document()
        doc.removeDesktopLater(on: "builtin", desktop: 2, mode: .undocked, existing: true, space: 5)
        doc.removeDesktopLater(on: "builtin", desktop: 3, mode: .undocked, existing: true, space: 9)
        doc.dropFirstPendingRemoval(mode: .undocked, screen: "builtin")
        #expect(doc.pendingRemovals(mode: .undocked, screen: "builtin")
                == [PendingRemoval(desktop: 3, space: 9)])
        doc.dropFirstPendingRemoval(mode: .undocked, screen: "builtin")
        #expect(doc.pendingRemovals.isEmpty)
    }

    @Test func windowsReorderOnlyBetweenRealDesktops() {
        #expect(Router.canReorderWindows(from: 1, to: 3, realCount: 3))
        #expect(!Router.canReorderWindows(from: 1, to: 5, realCount: 3))
        #expect(!Router.canReorderWindows(from: 4, to: 1, realCount: 3))
    }

    @Test func pendingRemovalFindsSpaceByIDFirst() {
        // macOS monitör masaüstülerini sona ekledi: kimlik yine doğru sırayı bulur.
        #expect(Router.pendingIndex(PendingRemoval(desktop: 2, space: 5), desktops: [4, 5, 6, 34]) == 2)
        #expect(Router.pendingIndex(PendingRemoval(desktop: 2, space: 99), desktops: [4, 5]) == nil)
        #expect(Router.pendingIndex(PendingRemoval(desktop: 2, space: nil), desktops: [4, 5]) == 2)
        #expect(Router.pendingIndex(PendingRemoval(desktop: 3, space: nil), desktops: [4, 5]) == nil)
    }

    @Test func v1SchemaMigrates() throws {
        let doc = try decode("""
        {
          "settings": { "enabled": false },
          "screens": [ { "uuid": "ABC", "role": "builtin" } ],
          "rules": [
            { "app": "Safari", "match": { "type": "title", "value": "Work" },
              "docked": { "screen": "external", "desktop": 2 } },
            { "app": { "name": "Code", "bundleID": "com.microsoft.VSCode" },
              "match": { "type": "title", "value": "" } }
          ]
        }
        """)
        #expect(doc.enabled == false)
        #expect(doc.fileVersion == 1)
        #expect(doc.version == Document.currentVersion)
        // v1 ekran kayıtları (uuid/role) okunmaz, yeniden keşfedilir.
        #expect(doc.screens.isEmpty)
        #expect(doc.rules.count == 2)
        #expect(doc.rules[0].appName == "Safari")
        #expect(doc.rules[0].bundleID == "")
        #expect(doc.rules[0].tokens == ["Work"])
        #expect(doc.rules[0].docked == Destination(screen: "external", desktop: 2))
        #expect(doc.rules[1].appName == "Code")
        #expect(doc.rules[1].bundleID == "com.microsoft.VSCode")
        #expect(doc.rules[1].isAppWide)
        // Profil yoksa kurallar "Varsayılan" profil olur.
        #expect(doc.profiles.count == 1)
        #expect(doc.profiles[0].name == Document.defaultProfileName)
        #expect(doc.profiles[0].rules == doc.rules)
        #expect(doc.activeProfileID == doc.profiles[0].id)
    }

    @Test func v2SchemaGetsDefaultProfile() throws {
        let doc = try decode("""
        {
          "version": 2, "enabled": true,
          "screens": [ { "id": "builtin", "name": "Dahili", "aspect": 1.55 } ],
          "rules": [ { "id": "r1", "appName": "Code", "bundleID": "c", "tokens": ["A"],
                       "undocked": { "screen": "builtin", "desktop": 1 } } ]
        }
        """)
        #expect(doc.fileVersion == 2)
        #expect(doc.screens == [KnownScreen(id: "builtin", name: "Dahili", aspect: 1.55)])
        #expect(doc.profiles.count == 1)
        #expect(doc.profiles[0].rules.map(\.id) == ["r1"])
        #expect(doc.activeProfileID == doc.profiles[0].id)
    }

    @Test func v3RoundTrip() throws {
        var doc = Document()
        doc.enabled = false
        doc.setupNoticeDismissed = true
        doc.screens = [KnownScreen(id: "builtin", name: "Dahili", aspect: 1.55),
                       KnownScreen(id: "external", name: "LG", aspect: 1.78)]
        doc.rules = [Rule(id: "r1", appName: "Code", bundleID: "c", tokens: ["A", "B"],
                          docked: Destination(screen: "external", desktop: 3, layout: .leftHalf),
                          undocked: Destination(screen: "builtin", desktop: 2,
                                                layout: WindowLayout(x: 0.1, y: 0.2, w: 0.3, h: 0.4)))]
        doc.syncActiveProfile()
        doc.profiles.append(Profile(id: "p2", name: "İş", rules: [
            Rule(id: "r2", appName: "Safari", bundleID: "", tokens: [])]))

        let data = try JSONEncoder().encode(doc)
        let back = try decode(String(decoding: data, as: UTF8.self))
        #expect(back == doc)
        #expect(back.fileVersion == 3)
        #expect(back.droppedRuleCount == 0)
        // Yazılmayan alanlar dosyada yok.
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("fileVersion"))
        #expect(!text.contains("droppedRuleCount"))
        #expect(text.contains("\"version\":3"))
    }

    @Test func destinationDefaultsAndDesktopClamp() throws {
        let doc = try decode("""
        { "rules": [
            { "appName": "A", "docked": {} },
            { "appName": "B", "docked": { "screen": "external", "desktop": 0 } },
            { "appName": "C", "undocked": { "desktop": -4,
                                             "layout": { "x": 0.5, "y": 0, "w": 0.5, "h": 1 } } },
            { "appName": "D", "undocked": { "layout": { "x": 0.5 } } }
        ] }
        """)
        #expect(doc.rules[0].docked == Destination(screen: "builtin", desktop: 1, layout: .full))
        #expect(doc.rules[1].docked?.desktop == 1)
        #expect(doc.rules[2].undocked?.desktop == 1)
        #expect(doc.rules[2].undocked?.layout == .rightHalf)
        // Eksik alanlı düzen kuralı okunmaz kılar; kural atlanır, belge kalır.
        #expect(doc.rules.count == 3)
        #expect(doc.droppedRuleCount == 1)
        // Kural kimliği yoksa üretilir; parçalar boş sayılır.
        #expect(!doc.rules[0].id.isEmpty)
        #expect(doc.rules[0].tokens.isEmpty)
        #expect(Destination(screen: "x", desktop: 0).desktop == 1)
    }

    @Test func unknownActiveProfileFallsBackToFirst() throws {
        let doc = try decode("""
        { "version": 3, "activeProfileID": "missing",
          "rules": [ { "id": "stale", "appName": "S", "bundleID": "", "tokens": [] } ],
          "profiles": [
            { "id": "p1", "name": "Bir", "rules": [ { "id": "r1", "appName": "A", "bundleID": "", "tokens": [] } ] },
            { "id": "p2", "name": "İki", "rules": [] }
          ] }
        """)
        #expect(doc.activeProfileID == "p1")
        #expect(doc.rules.map(\.id) == ["r1"])
    }

    @Test func missingRulesKeyUsesActiveProfileRules() throws {
        let doc = try decode("""
        { "version": 3, "activeProfileID": "p2",
          "profiles": [
            { "id": "p1", "name": "Bir", "rules": [] },
            { "id": "p2", "name": "İki", "rules": [ { "id": "r2", "appName": "A", "bundleID": "", "tokens": [] } ] }
          ] }
        """)
        #expect(doc.activeProfileID == "p2")
        #expect(doc.rules.map(\.id) == ["r2"])
    }

    @Test func topLevelRulesWinOverActiveProfileWhenPresent() throws {
        // Yarım kalan yazım: üst düzey `rules` daha güncel kabul edilir.
        let doc = try decode("""
        { "version": 3, "activeProfileID": "p1",
          "rules": [ { "id": "fresh", "appName": "A", "bundleID": "", "tokens": [] } ],
          "profiles": [ { "id": "p1", "name": "Bir", "rules": [] } ] }
        """)
        #expect(doc.rules.map(\.id) == ["fresh"])
        #expect(doc.profiles[0].rules.isEmpty)
    }

    @Test func malformedRuleIsDroppedNotFatal() throws {
        let doc = try decode("""
        { "version": 3, "activeProfileID": "p1",
          "rules": [
            { "id": "ok1", "appName": "A", "bundleID": "", "tokens": [] },
            { "id": "bad", "appName": "B", "bundleID": "", "tokens": [],
              "docked": { "screen": "external", "desktop": "x" } },
            "not even an object",
            { "id": "ok2", "appName": "C", "bundleID": "", "tokens": [] }
          ],
          "profiles": [
            { "id": "p1", "name": "Bir", "rules": [
                { "id": "ok1", "appName": "A", "bundleID": "", "tokens": [] },
                { "id": "bad", "appName": "B", "bundleID": "", "tokens": [], "docked": { "desktop": "x" } }
            ] },
            { "id": "p2", "name": "İki", "rules": [ 42 ] }
          ] }
        """)
        #expect(doc.rules.map(\.id) == ["ok1", "ok2"])
        #expect(doc.profiles[0].rules.map(\.id) == ["ok1"])
        #expect(doc.profiles[1].rules.isEmpty)
        // 2 üst düzey + 1 + 1 profil kuralı.
        #expect(doc.droppedRuleCount == 4)
    }

    @Test func newerFileVersionIsDetected() throws {
        let doc = try decode("""
        { "version": 4, "enabled": true, "futureField": { "x": 1 },
          "rules": [ { "id": "r1", "appName": "A", "bundleID": "", "tokens": [] } ] }
        """)
        #expect(doc.fileVersion == 4)
        #expect(doc.isFromNewerVersion)
        // Kurallar yine okunur; yalnızca yazma kapanır.
        #expect(doc.rules.count == 1)
        #expect(!Document().isFromNewerVersion)
        #expect(!(try decode("{ \"version\": 3 }")).isFromNewerVersion)
        // Sayı olmayan sürüm eski dosya sayılır, belgeyi düşürmez.
        #expect(try decode("{ \"version\": \"3\" }").fileVersion == 1)
    }

    @Test func profileWithoutRulesKeyInvalidatesProfilesLikeBefore() throws {
        // `Profile` şeması bozuksa (zorunlu alan eksik) profiller okunmaz,
        // v1/v2 yolu izlenir: kurallardan "Varsayılan" profil üretilir.
        let doc = try decode("""
        { "version": 3, "rules": [ { "id": "r1", "appName": "A", "bundleID": "", "tokens": [] } ],
          "profiles": [ { "id": "p1", "name": "Eksik" } ] }
        """)
        #expect(doc.profiles.count == 1)
        #expect(doc.profiles[0].name == Document.defaultProfileName)
        #expect(doc.profiles[0].rules.map(\.id) == ["r1"])
    }
}
