import Foundation
import Testing
@testable import Deskmap

/// Pin grubu URL komutları (ayrıştırma ve çalıştırma) ve `status.json` alanı.
struct PinGroupURLParseTests {

    private func parse(_ text: String) -> URLCommand? { URLCommand.parse(URL(string: text)!) }

    @Test func groupAdd() {
        #expect(parse("deskmap://group-add?name=Nova%20drafts&rules=a,b")
                == .groupAdd(name: "Nova drafts", rules: ["a", "b"]))
        #expect(parse("deskmap://group-add?rules=a,%20,b") == .groupAdd(name: nil, rules: ["a", "b"]))
        #expect(parse("deskmap://group-add?name=&rules=a") == .groupAdd(name: nil, rules: ["a"]))
        #expect(parse("deskmap://group-add?name=X") == nil)
        #expect(parse("deskmap://group-add?name=X&rules=") == nil)
        #expect(parse("deskmap://group-add/extra?rules=a") == nil)
    }

    @Test func groupRename() {
        #expect(parse("deskmap://group-rename/G1?name=Drafts") == .groupRename(group: "G1", name: "Drafts"))
        #expect(parse("deskmap://group-rename/Nova%20drafts?name=X")
                == .groupRename(group: "Nova drafts", name: "X"))
        // Boş ad ayrıştırılır, çalıştırma reddeder; ad yoksa komut yok.
        #expect(parse("deskmap://group-rename/G1?name=") == .groupRename(group: "G1", name: ""))
        #expect(parse("deskmap://group-rename/G1") == nil)
        #expect(parse("deskmap://group-rename?name=X") == nil)
    }

    @Test func groupRemoveAndSet() {
        #expect(parse("deskmap://group-remove/G1") == .groupRemove(group: "G1"))
        #expect(parse("deskmap://group-remove") == nil)
        #expect(parse("deskmap://group-set/G1?add=a,b&remove=c")
                == .groupMembers(group: "G1", add: ["a", "b"], remove: ["c"]))
        #expect(parse("deskmap://group-set/G1?remove=c") == .groupMembers(group: "G1", add: [], remove: ["c"]))
        #expect(parse("deskmap://group-set/G1") == nil)
        #expect(parse("deskmap://group-set?add=a") == nil)
    }
}

@MainActor
struct PinGroupURLRunTests {

    private func pdf(_ id: String) -> Rule {
        Rule(id: id, appName: "Preview", bundleID: "com.apple.Preview", tokens: [id],
             docked: Destination(screen: "builtin", desktop: 3))
    }

    private func make() -> (Store, Router) {
        var d = Document()
        d.rules = [pdf("a"), pdf("b"), pdf("c")]
        d.syncActiveProfile()
        let store = Store(demo: d)
        let router = Router(store: store, screens: ScreenService(demo: []), demoWindows: [])
        return (store, router)
    }

    @Test func runCreatesRenamesEditsAndRemoves() throws {
        let (store, router) = make()
        URLCommands.run(.groupAdd(name: "Nova", rules: ["a", "b"]), store: store, router: router)
        let id = try #require(store.document.pinGroups.first?.id)
        #expect(store.lastError == nil)
        URLCommands.run(.groupRename(group: "nova", name: "Drafts"), store: store, router: router)
        #expect(store.document.pinGroup(id)?.name == "Drafts")
        URLCommands.run(.groupRename(group: id, name: "  "), store: store, router: router)
        #expect(store.lastError == "Group name can't be empty")
        #expect(store.document.pinGroup(id)?.name == "Drafts")
        store.clearError()
        URLCommands.run(.groupMembers(group: id, add: ["c"], remove: ["a"]), store: store, router: router)
        #expect(Set(store.document.pinGroupMembers(id, mode: .docked).map(\.id)) == ["b", "c"])
        #expect(store.history.undoEntry?.label == "Pin group changed")
        URLCommands.run(.groupRemove(group: "Drafts"), store: store, router: router)
        #expect(store.document.pinGroups.isEmpty)
        #expect(store.document.rules.count == 3)
    }

    @Test func runReportsMissingAmbiguousAndUnknownRules() throws {
        let (store, router) = make()
        URLCommands.run(.groupAdd(name: nil, rules: ["nope"]), store: store, router: router)
        #expect(store.lastError == "Rule not found: nope")
        #expect(store.document.pinGroups.isEmpty)
        URLCommands.run(.groupRemove(group: "x"), store: store, router: router)
        #expect(store.lastError == "No pin group x")
        URLCommands.run(.groupAdd(name: "Same", rules: ["a"]), store: store, router: router)
        URLCommands.run(.groupAdd(name: "same", rules: ["b"]), store: store, router: router)
        store.clearError()
        URLCommands.run(.groupRename(group: "SAME", name: "Y"), store: store, router: router)
        #expect(store.lastError == "Several pin groups are named SAME; use the id")
        // Başka gruptan çekme URL'de hata sayılmaz (komut satırı aracı iletiyi hata sanardı).
        store.clearError()
        URLCommands.run(.groupAdd(name: "Third", rules: ["a"]), store: store, router: router)
        #expect(store.lastError == nil)
        #expect(store.document.pinGroups.map(\.name).contains("Third"))
    }

    /// Bilinmeyen bir kimlik komutun tamamını reddeder: hata bildirip
    /// değişikliği yine yapmak komut satırı aracını yanıltırdı.
    @Test func unknownRuleRejectsTheWholeCommand() throws {
        let (store, router) = make()
        URLCommands.run(.groupAdd(name: "Nova", rules: ["a", "stale"]), store: store, router: router)
        #expect(store.lastError == "Rule not found: stale")
        #expect(store.document.pinGroups.isEmpty)
        #expect(store.history.undoEntry == nil)
        store.clearError()
        URLCommands.run(.groupAdd(name: "Nova", rules: ["a", "b"]), store: store, router: router)
        let id = try #require(store.document.pinGroups.first?.id)
        URLCommands.run(.groupMembers(group: id, add: ["stale"], remove: ["a"]), store: store, router: router)
        #expect(store.lastError == "Rule not found: stale")
        #expect(Set(store.document.pinGroupMembers(id, mode: .docked).map(\.id)) == ["a", "b"])
        store.clearError()
        URLCommands.run(.groupMembers(group: id, add: ["c"], remove: ["stale"]), store: store, router: router)
        #expect(store.lastError == "Rule not found: stale")
        #expect(Set(store.document.pinGroupMembers(id, mode: .docked).map(\.id)) == ["a", "b"])
    }

    @Test func statusListsGroupsIncludingEmptyOnes() throws {
        var d = Document()
        d.rules = [pdf("a"), pdf("b")]
        let made = d.createPinGroup(name: "Nova", ruleIDs: ["a", "b"])
        let id = try #require(made).id
        d.unpin("a", mode: .docked)
        d.unpin("b", mode: .docked)
        #expect(StatusFile.pinGroups(d) == [StatusFile.GroupStatus(id: id, name: "Nova", rules: [])])
        var full = Document()
        full.rules = [pdf("a"), pdf("b")]
        let other = full.createPinGroup(name: "G", ruleIDs: ["b"])
        let gid = try #require(other).id
        #expect(StatusFile.pinGroups(full) == [StatusFile.GroupStatus(id: gid, name: "G", rules: ["b"])])
        // Üyelik kuralın kendisinde de çıkar.
        let rules = try JSONSerialization.jsonObject(with: JSONEncoder().encode(full.rules)) as? [[String: Any]]
        #expect(rules?[1]["groupID"] as? String == gid)
        #expect(rules?[0]["groupID"] == nil)
    }
}
