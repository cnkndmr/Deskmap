import Foundation
import Testing
@testable import Deskmap

/// Oturumluk ayar geçmişi: çok adımlı geri al / yinele, dal silme ve geri
/// getirme, satıra dönüş, 50 sınırı, gürültü ve kayıtsız değişimler.
struct ChangeHistoryTests {

    /// Profil kimliği her `Document()`'ta yeni; karşılaştırmalar için sabit taban.
    private static let base = Document()

    private func document(rules: Int) -> Document {
        var doc = Self.base
        doc.rules = (0..<rules).map {
            Rule(id: "r\($0)", appName: "Code", bundleID: "com.microsoft.VSCode",
                 tokens: ["t\($0)"], docked: Destination(screen: "external"))
        }
        return doc
    }

    /// 0 kuraldan başlayıp her adımda bir kural ekleyen geçmiş.
    private func history(steps: Int) -> ChangeHistory {
        var history = ChangeHistory(origin: document(rules: 0))
        for i in 0..<steps {
            history.record("Step \(i + 1)", before: document(rules: i), after: document(rules: i + 1))
        }
        return history
    }

    // MARK: Saf zaman çizgisi

    @Test func startsAtOriginWithNothingToUndo() {
        let history = ChangeHistory(origin: document(rules: 1))
        #expect(!history.canUndo && !history.canRedo)
        #expect(history.cursor == 0 && history.entries.isEmpty)
        #expect(history.document(at: 0) == document(rules: 1))
        #expect(history.undoEntry == nil && history.redoEntry == nil)
    }

    @Test func multiStepUndoAndRedo() {
        var h = history(steps: 3)
        #expect(h.cursor == 3 && h.undoEntry?.label == "Step 3")
        #expect(h.undo()?.document == document(rules: 2))
        #expect(h.undo()?.document == document(rules: 1))
        #expect(h.cursor == 1 && h.canRedo && h.redoEntry?.label == "Step 2")
        #expect(h.redo()?.document == document(rules: 2))
        #expect(h.undo()?.document == document(rules: 1))
        #expect(h.undo()?.document == document(rules: 0))
        #expect(!h.canUndo)
        #expect(h.undo() == nil)
        #expect(h.redo()?.document == document(rules: 1))
    }

    @Test func newChangeDiscardsRedoBranchAndUndoBringsItBack() {
        var h = history(steps: 3)
        _ = h.undo(); _ = h.undo()                       // imleç 1
        h.record("Other", before: document(rules: 1), after: document(rules: 5))
        #expect(h.entries.map(\.label) == ["Step 1", "Other"])
        #expect(!h.canRedo)
        #expect(h.discarded?.entries.count == 2)
        #expect(h.discardNoticeVisible(at: Date()))

        // Yeni değişikliği geri almak silinen dalı geri getirir.
        #expect(h.undo()?.document == document(rules: 1))
        #expect(h.discarded == nil)
        #expect(h.entries.map(\.label) == ["Step 1", "Step 2", "Step 3"])
        #expect(h.cursor == 1)
        #expect(h.redo()?.document == document(rules: 2))
        #expect(h.redo()?.document == document(rules: 3))
    }

    @Test func anotherChangeMakesDiscardPermanent() {
        var h = history(steps: 2)
        _ = h.undo()
        h.record("A", before: document(rules: 1), after: document(rules: 7))
        h.record("B", before: document(rules: 7), after: document(rules: 8))
        #expect(h.discarded == nil)
        _ = h.undo(); _ = h.undo()
        #expect(h.entries.map(\.label) == ["Step 1", "A", "B"])
    }

    @Test func discardNoticeExpires() {
        var h = history(steps: 1)
        _ = h.undo()
        let t0 = Date(timeIntervalSince1970: 1_000)
        h.record("X", before: document(rules: 0), after: document(rules: 4), at: t0)
        #expect(h.discardNoticeVisible(at: t0.addingTimeInterval(1)))
        #expect(!h.discardNoticeVisible(at: t0.addingTimeInterval(ChangeHistory.discardNoticeFor)))
        #expect(h.discardNoticeExpiry == t0.addingTimeInterval(ChangeHistory.discardNoticeFor))
    }

    @Test func returnToRowMovesBackAndForwardWithoutNewEntries() {
        var h = history(steps: 4)
        #expect(h.move(to: 1)?.document == document(rules: 1))
        #expect(h.cursor == 1 && h.entries.count == 4)
        #expect(h.move(to: 3)?.document == document(rules: 3))   // soluk satırla ileri
        #expect(h.move(to: 0)?.document == document(rules: 0))   // açılış durumu
        #expect(h.move(to: 0) == nil)                             // zaten orada
        #expect(h.move(to: 9) == nil)
        #expect(h.move(to: 4)?.document == document(rules: 4))
        #expect(h.entries.count == 4)
    }

    @Test func limitDropsOldestAndShiftsOrigin() {
        var h = history(steps: ChangeHistory.limit + 3)
        #expect(h.entries.count == ChangeHistory.limit)
        #expect(h.cursor == ChangeHistory.limit)
        #expect(h.originTrimmed)
        #expect(h.origin == document(rules: 3))
        #expect(h.entries.first?.label == "Step 4")
        #expect(h.move(to: 0)?.document == document(rules: 3))
    }

    @Test func companionEntryUndoesButDoesNotRedo() {
        var ran = 0
        var h = history(steps: 1)
        h.record("Temporary pin moved", before: document(rules: 1), after: document(rules: 1),
                 companion: { ran += 1 })
        h.record("Step 2", before: document(rules: 1), after: document(rules: 2))
        let move = h.move(to: 1)
        #expect(move?.companions.count == 1)
        move?.companions.forEach { $0() }
        #expect(ran == 1)
        #expect(h.redoEntry?.isRedoable == false)
        #expect(!h.canRedo)
        #expect(h.redo() == nil)
        #expect(!h.canMove(to: 3))       // yol yinelenemeyen girişten geçer
    }

    @Test func coalescingMergesConsecutiveAutomaticChanges() {
        var h = history(steps: 1)
        h.record("Desktop names updated", before: document(rules: 1), after: document(rules: 2),
                 coalesce: true)
        h.record("Desktop names updated", before: document(rules: 2), after: document(rules: 3),
                 coalesce: true)
        #expect(h.entries.count == 2)
        #expect(h.undo()?.document == document(rules: 1))
    }

    // MARK: Gürültü

    @Test func matchesIgnoresEnabledAndScreens() {
        let a = document(rules: 2)
        var b = a
        b.enabled = false
        b.screens = [KnownScreen(id: "external", name: "Dell", aspect: 1.78)]
        #expect(ChangeHistory.matches(a, b))

        var c = a
        c.rules.removeLast()
        #expect(!ChangeHistory.matches(a, c))
        var d = a
        d.setupNoticeDismissed = true
        #expect(!ChangeHistory.matches(a, d))
        var e = a
        e.addProfile(named: "Ofis")
        #expect(!ChangeHistory.matches(a, e))
    }

    @Test func matchesTreatsDelayedProfileSyncAsSame() {
        let after = document(rules: 2)             // profiles[0].rules hâlâ boş
        var synced = after
        synced.syncActiveProfile()
        #expect(synced != after)
        #expect(ChangeHistory.matches(after, synced))
    }

    // MARK: Store

    @MainActor @Test func storeNoiseDoesNotCreateEntries() {
        let store = Store(demo: document(rules: 1))
        store.document.enabled = false
        store.remember([KnownScreen(id: "external", name: "Dell", aspect: 1.78)])
        store.document.syncActiveProfile()
        store.refreshNameCaches()
        #expect(store.history.entries.isEmpty)
    }

    @MainActor @Test func storeUntrackedChangeBecomesEntry() {
        var start = document(rules: 1)
        start.addProfile(named: "Ofis", activate: false)
        let store = Store(demo: start)
        store.document.setupNoticeDismissed = true
        #expect(store.history.undoEntry?.label == "Settings changed")
        store.switchProfile(to: store.profiles[1].id)
        #expect(store.history.undoEntry?.label == "Profile switched: Ofis")
        #expect(store.history.entries.count == 2)
        store.undo()
        #expect(store.document.activeProfileID == store.profiles[0].id)
        store.undo()
        #expect(!store.document.setupNoticeDismissed)
        store.redo()
        #expect(store.document.setupNoticeDismissed)
    }

    @MainActor @Test func storeNavigationKeepsEnabledAndAddsNoEntries() {
        let store = Store(demo: document(rules: 0))
        store.add(Rule(id: "a", appName: "A", bundleID: "a", tokens: ["x"]))
        store.add(Rule(id: "b", appName: "B", bundleID: "b", tokens: ["y"]))
        let count = store.history.entries.count
        #expect(count == 2)
        store.document.enabled = false
        store.returnTo(0)
        #expect(store.document.rules.isEmpty)
        #expect(store.document.enabled == false)
        store.returnTo(2)
        #expect(store.document.rules.count == 2)
        #expect(store.history.entries.count == count)
    }

    @MainActor @Test func storeSessionChangeUndoesButDoesNotRedo() {
        let store = Store(demo: document(rules: 0))
        var undone = 0
        store.recordSessionChange("Temporary pin moved") { undone += 1 }
        store.undo()
        #expect(undone == 1)
        #expect(!store.history.canRedo)
        store.redo()
        #expect(undone == 1)
    }
}
