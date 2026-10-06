import Foundation
import Testing
@testable import Deskmap

/// `deskmap://` (birincil) ve eski `spacerouter://` (Deskmap'in eski adı)
/// şemalarının aynı komutlara çözüldüğünü doğrular; ikisi de kalıcı olarak
/// kabul edilir (Shortcuts/Raycast gibi dış kurulumlar bozulmasın).
struct URLCommandTests {

    @Test func primarySchemeParsesKnownCommands() {
        #expect(URLCommand.parse(URL(string: "deskmap://reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "deskmap://pause")!) == .pause)
        #expect(URLCommand.parse(URL(string: "deskmap://resume")!) == .resume)
        #expect(URLCommand.parse(URL(string: "deskmap://toggle")!) == .toggle)
        #expect(URLCommand.parse(URL(string: "deskmap://next-profile")!) == .nextProfile)
        #expect(URLCommand.parse(URL(string: "deskmap://profile/Ofis")!) == .profile(name: "Ofis"))
        #expect(URLCommand.parse(URL(string: "deskmap://add-desktop/External")!)
                == .addDesktop(screen: "external"))
        #expect(URLCommand.parse(URL(string: "deskmap:add-desktop/builtin")!)
                == .addDesktop(screen: "builtin"))
        #expect(URLCommand.parse(URL(string: "deskmap://add-desktop")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external/3")!)
                == .removeDesktop(screen: "external", desktop: 3))
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external/0")!) == nil)
    }

    @Test func legacySchemeStillParsesTheSameCommands() {
        #expect(URLCommand.parse(URL(string: "spacerouter://reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "spacerouter://pause")!) == .pause)
        #expect(URLCommand.parse(URL(string: "spacerouter://resume")!) == .resume)
        #expect(URLCommand.parse(URL(string: "spacerouter://toggle")!) == .toggle)
        #expect(URLCommand.parse(URL(string: "spacerouter://next-profile")!) == .nextProfile)
        #expect(URLCommand.parse(URL(string: "spacerouter://profile/Ofis")!) == .profile(name: "Ofis"))
    }

    @Test func legacySchemeIsCaseInsensitiveAndHostless() {
        #expect(URLCommand.parse(URL(string: "SpaceRouter://Reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "spacerouter:profile/Ofis")!) == .profile(name: "Ofis"))
    }

    @Test func unknownSchemeReturnsNil() {
        #expect(URLCommand.parse(URL(string: "hammerspoon://reapply")!) == nil)
    }

    @Test func schemeConstantsAreDistinct() {
        #expect(URLCommand.scheme == "deskmap")
        #expect(URLCommand.legacyScheme == "spacerouter")
        #expect(URLCommand.scheme != URLCommand.legacyScheme)
    }
}

/// Komut satırı aracının (`deskmap`) kullandığı komutlar.
struct URLCommandCLITests {

    @Test func windowCommands() {
        #expect(URLCommand.parse(URL(string: "deskmap://pin/1234/External/2?req=7")!)
                == .pin(window: 1234, screen: "external", desktop: 2))
        #expect(URLCommand.parse(URL(string: "deskmap://move/1234/builtin/1")!)
                == .move(window: 1234, screen: "builtin", desktop: 1))
        #expect(URLCommand.parse(URL(string: "deskmap://unpin/1234")!) == .unpin(window: 1234))
        #expect(URLCommand.parse(URL(string: "deskmap://pin/abc/builtin/1")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://move/1234/builtin/0")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://pin/1234/builtin")!) == nil)
    }

    @Test func reloadStatusAndRuleRemove() {
        #expect(URLCommand.parse(URL(string: "deskmap://reload")!) == .reload)
        #expect(URLCommand.parse(URL(string: "deskmap://status?req=x1")!) == .status)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-remove/ABC-1")!) == .removeRule(id: "ABC-1"))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-remove")!) == nil)
    }

    @Test func ruleAddDecodesJSON() throws {
        let json = #"{"id":"R1","appName":"cmux","bundleID":"","tokens":[],"docked":{"screen":"external","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}}}"#
        var components = URLComponents(string: "deskmap://rule-add")!
        components.queryItems = [URLQueryItem(name: "json", value: json), URLQueryItem(name: "req", value: "9")]
        guard case .addRule(let rule)? = URLCommand.parse(components.url!) else {
            Issue.record("rule-add did not parse"); return
        }
        #expect(rule.id == "R1" && rule.appName == "cmux")
        #expect(rule.docked?.screen == "external" && rule.docked?.desktop == 2)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-add?json=notjson")!) == nil)
    }

    @Test func requestIDIsRead() {
        #expect(URLCommands.requestID(URL(string: "deskmap://pause?req=42")!) == "42")
        #expect(URLCommands.requestID(URL(string: "deskmap://pause")!) == nil)
    }
}

struct URLCommandProfileAndPlanTests {

    private func setURL(_ json: String, extra: String = "") -> URL {
        var c = URLComponents(string: "deskmap://profile-set")!
        c.queryItems = [URLQueryItem(name: "json", value: json)]
            + (extra.isEmpty ? [] : [URLQueryItem(name: "activate", value: extra)])
        return c.url!
    }

    @Test func profileSetParses() {
        guard case .setProfile(let p, let activate)? =
                URLCommand.parse(setURL(#"{"name":"Ofis","rules":[]}"#, extra: "1")) else {
            Issue.record("profile-set did not parse"); return
        }
        #expect(p.name == "Ofis" && p.rules.isEmpty && activate)
        guard case .setProfile(let q, let a2)? =
                URLCommand.parse(setURL(#"{"id":"X","name":"Ev","rules":[]}"#)) else {
            Issue.record("profile-set did not parse"); return
        }
        #expect(q.id == "X" && !a2)
        #expect(URLCommand.parse(setURL("nope")) == nil)
        #expect(URLCommand.parse(setURL(#"{"name":" ","rules":[]}"#)) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://profile-set")!) == nil)
    }

    @Test func planDesktopsParses() {
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/External/4?mode=docked&req=1")!)
                == .planDesktops(screen: "external", count: 4, mode: .docked))
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/builtin/2")!)
                == .planDesktops(screen: "builtin", count: 2, mode: nil))
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/builtin/0")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/builtin/17")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/builtin")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://plan-desktops/builtin/2?mode=x")!) == nil)
    }

    private func rule(_ id: String, desktop: Int) -> Rule {
        var r = Rule(appName: id, bundleID: "", tokens: [])
        r.id = id
        r.docked = Destination(screen: "external", desktop: desktop)
        return r
    }

    private func document() -> Document {
        var doc = Document()
        doc.profiles = [Profile(id: "A", name: "A", rules: [rule("a", desktop: 1)]),
                        Profile(id: "B", name: "B", rules: [rule("b", desktop: 3)])]
        doc.activeProfileID = "A"
        doc.rules = doc.profiles[0].rules
        return doc
    }

    @Test func upsertCreatesNew() {
        var doc = document()
        doc.upsertProfile(Profile(name: "C", rules: [rule("c", desktop: 2)]), activate: false)
        #expect(doc.profiles.count == 3 && doc.profiles[2].name == "C")
        #expect(doc.activeProfileID == "A" && doc.rules.map(\.id) == ["a"])
    }

    @Test func upsertReplacesByNameKeepingID() {
        var doc = document()
        doc.upsertProfile(Profile(id: "ZZ", name: "B", rules: []), activate: false)
        #expect(doc.profiles.count == 2)
        #expect(doc.profiles[1].id == "B" && doc.profiles[1].rules.isEmpty)
        #expect(doc.profiles[0].rules.map(\.id) == ["a"])
    }

    @Test func upsertActiveUpdatesLiveRules() {
        var doc = document()
        doc.upsertProfile(Profile(name: "A", rules: [rule("n", desktop: 2)]), activate: false)
        #expect(doc.rules.map(\.id) == ["n"] && doc.profiles[0].rules.map(\.id) == ["n"])
        #expect(doc.profiles[1].rules.map(\.id) == ["b"])
    }

    @Test func upsertActivateSwitches() {
        var doc = document()
        doc.upsertProfile(Profile(name: "B", rules: [rule("q", desktop: 1)]), activate: true)
        #expect(doc.activeProfileID == "B" && doc.rules.map(\.id) == ["q"])
        #expect(doc.profiles[0].rules.map(\.id) == ["a"])
    }

    @Test func removalBlockedByPinnedRules() {
        let doc = document()
        #expect(doc.desktopBlockingRemoval(on: "external", mode: .docked, keeping: 2, total: 4) == 3)
        #expect(doc.desktopBlockingRemoval(on: "external", mode: .docked, keeping: 3, total: 4) == nil)
        #expect(doc.desktopBlockingRemoval(on: "builtin", mode: .docked, keeping: 1, total: 4) == nil)
    }
}

/// Profil adı, dışa aktarma, masaüstü sırası, şu anki boyutu kullan.
struct URLCommandEditingTests {

    @Test func profileRenameAndExport() {
        #expect(URLCommand.parse(URL(string: "deskmap://profile-rename/Ofis?name=Ev%20Masas%C4%B1")!)
                == .renameProfile(from: "Ofis", to: "Ev Masası"))
        #expect(URLCommand.parse(URL(string: "deskmap://profile-rename/Ofis")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://profile-rename?name=X")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://profile-export?path=/tmp/a.deskmap.json")!)
                == .exportProfile(name: nil, path: "/tmp/a.deskmap.json"))
        #expect(URLCommand.parse(URL(string: "deskmap://profile-export?path=/tmp/a.json&name=Ofis")!)
                == .exportProfile(name: "Ofis", path: "/tmp/a.json"))
        #expect(URLCommand.parse(URL(string: "deskmap://profile-export?path=relative.json")!) == nil)
    }

    @Test func desktopMove() {
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-move/External/1/3")!)
                == .moveDesktop(screen: "external", from: 1, to: 3, mode: nil))
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-move/builtin/2/1?mode=undocked")!)
                == .moveDesktop(screen: "builtin", from: 2, to: 1, mode: .undocked))
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-move/builtin/2/2")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-move/builtin/0/2")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://desktop-move/builtin/1/2?mode=x")!) == nil)
    }

    @Test func saveLayout() {
        #expect(URLCommand.parse(URL(string: "deskmap://rule-save-layout/R1")!)
                == .saveLayout(rule: "R1", window: nil))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-save-layout/R1?window=42")!)
                == .saveLayout(rule: "R1", window: 42))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-save-layout/R1?window=x")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-save-layout")!) == nil)
    }
}
