import Foundation
import Testing
@testable import Deskmap

/// Pin grubu Store işlemleri: her biri tek geri alma adımı, doğru etiket,
/// geri alma ve yineleme çalışır; etkisiz çağrı kayıt bırakmaz.
@MainActor
struct PinGroupStoreTests {

    private func pdf(_ id: String, desktop: Int = 3) -> Rule {
        Rule(id: id, appName: "Preview", bundleID: "com.apple.Preview", tokens: [id],
             docked: Destination(screen: "builtin", desktop: desktop, layout: .leftHalf))
    }

    private func store(_ rules: [Rule]) -> Store {
        var d = Document()
        d.rules = rules
        d.syncActiveProfile()
        return Store(demo: d)
    }

    @Test func everyActionIsOneLabelledUndoStep() throws {
        let s = store([pdf("a"), pdf("b"), pdf("c")])
        let made = s.createPinGroup(name: "Nova drafts", ruleIDs: ["a", "b"])
        let id = try #require(made)
        #expect(s.history.entries.map(\.label) == ["Pin group created"])
        #expect(s.renamePinGroup(id, to: "Drafts"))
        #expect(s.history.undoEntry?.label == "Pin group renamed")
        #expect(s.addToPinGroup(id, ruleIDs: ["c"]))
        #expect(s.history.undoEntry?.label == "Added to group")
        s.removeFromPinGroup(ruleIDs: ["a"])
        #expect(s.history.undoEntry?.label == "Removed from group")
        #expect(s.editPinGroupMembers(id, add: ["a"], remove: ["c"]))
        #expect(s.history.undoEntry?.label == "Pin group changed")
        s.dissolvePinGroup(id)
        #expect(s.history.undoEntry?.label == "Pin group ungrouped")
        #expect(s.history.entries.count == 6)
        #expect(!s.history.entries.contains { $0.label == "Settings changed" })
        #expect(s.document.pinGroups.isEmpty)
        // Geri alma ve yineleme.
        s.undo()
        #expect(s.document.pinGroup(id)?.name == "Drafts")
        #expect(Set(s.document.rules.filter { $0.groupID == id }.map(\.id)) == ["a", "b"])
        s.redo()
        #expect(s.document.pinGroups.isEmpty)
        for _ in 0..<6 { s.undo() }
        #expect(s.document.pinGroups.isEmpty)
        #expect(s.document.rules.allSatisfy { $0.groupID == nil })
    }

    @Test func noOpCallsLeaveNoEntry() throws {
        let s = store([pdf("a")])
        #expect(s.createPinGroup(name: "X", ruleIDs: ["missing"]) == nil)
        #expect(!s.renamePinGroup("missing", to: "X"))
        #expect(!s.addToPinGroup("missing", ruleIDs: ["a"]))
        s.dissolvePinGroup("missing")
        s.removeFromPinGroup(ruleIDs: ["a"])
        #expect(s.history.entries.isEmpty)
        let made = s.createPinGroup(name: "G", ruleIDs: ["a"])
        let id = try #require(made)
        #expect(!s.renamePinGroup(id, to: "   "))
        #expect(s.renamePinGroup(id, to: "G"))
        #expect(s.history.entries.count == 1)
        #expect(s.document.pinGroup(id)?.name == "G")
    }

    @Test func movingAPinGroupIsOneStep() throws {
        let s = store([pdf("a"), pdf("b", desktop: 2)])
        let made = s.createPinGroup(name: "G", ruleIDs: ["a", "b"])
        let id = try #require(made)
        let target = Destination(screen: "builtin", desktop: 1, layout: .leftHalf)
        s.movePinGroup([.init(id: "a", destination: target), .init(id: "b", destination: target)],
                       mode: .docked)
        #expect(s.history.undoEntry?.label == "Pin group moved")
        #expect(s.document.rules.allSatisfy { $0.docked?.desktop == 1 })
        #expect(s.document.rules.allSatisfy { $0.docked?.layout == .leftHalf })
        #expect(s.document.rules.allSatisfy { $0.groupID == id })
        s.undo()
        #expect(s.document.rule("a")?.docked?.desktop == 3)
        #expect(s.document.rule("b")?.docked?.desktop == 2)
        s.movePinGroup([], mode: .docked)
        #expect(s.history.entries.count == 2)
    }

    /// K12: zaten pinli kuralın yeri değişmez; yeni pencereler pinlenir;
    /// tek adım. Başka gruptan çekmede bildirim çıkar.
    @Test func pinAsGroupKeepsExistingPlacesAndReportsPulls() throws {
        let s = store([pdf("a"), pdf("b")])
        let other = s.createPinGroup(name: "Old", ruleIDs: ["a"])
        let old = try #require(other)
        let before = try #require(s.document.rule("a"))
        let draft = Rule(id: "new", appName: "Preview", bundleID: "com.apple.Preview", tokens: ["n"])
        let made = s.pinAsGroup(new: [(rule: draft, destination: Destination(screen: "builtin", desktop: 3))],
                                existing: ["a", "b"], mode: .docked)
        let id = try #require(made)
        #expect(s.history.undoEntry?.label == "Windows pinned as group")
        #expect(s.document.rule("a")?.docked == before.docked)
        #expect(s.document.rule("new")?.docked?.desktop == 3)
        #expect(Set(s.document.pinGroupMembers(id, mode: .docked).map(\.id)) == ["a", "b", "new"])
        #expect(s.document.pinGroup(old) == nil)
        #expect(s.lastError == "Moved 1 pin from another group")
        s.undo()
        #expect(s.document.rule("new") == nil)
        #expect(s.document.pinGroup(old) != nil)
        #expect(s.document.rule("a")?.groupID == old)
    }

    @Test func pinAsGroupRunsItsCompanionOnUndo() throws {
        let s = store([pdf("a")])
        var undone = false
        _ = s.pinAsGroup(new: [], existing: ["a"], mode: .docked, companion: { undone = true })
        s.undo()
        #expect(undone)
        #expect(s.document.pinGroups.isEmpty)
    }
}
