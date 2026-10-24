import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `Store` mutasyonları, geri alma geçmişi ve değişmezler. Diske yazmayan
/// `Store(demo:)` ile çalışır; hiçbir dosyaya dokunmaz.
@MainActor
struct StoreMutationTests {

    private func rule(_ id: String, _ token: String = "", docked: Destination? = nil,
                      undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "App-\(id)", bundleID: "b.\(id)", tokens: token.isEmpty ? [] : [token],
             docked: docked, undocked: undocked)
    }

    /// `rule(id, token)` ile aynı anahtarlı (uygulama + parça) ama başka kimlikli taslak.
    private func sameApp(as id: String, _ token: String) -> Rule {
        Rule(id: "draft-\(id)", appName: "App-\(id)", bundleID: "b.\(id)", tokens: [token])
    }

    private func store(rules: [Rule] = [], names: [DesktopName] = [],
                       plans: DesktopPlans = DesktopPlans()) -> Store {
        Store(demo: V6.document(rules: rules, names: names, plans: plans))
    }

    private func nameOrphans(_ store: Store) -> [String] {
        let ids = Set(store.document.names.map(\.id))
        return store.document.rules.flatMap { rule in
            Mode.allCases.flatMap { rule.places($0) }.compactMap { $0.nameID }.filter { !ids.contains($0) }
        }
    }

    // MARK: - Kurallar

    @Test func removeIsUndoableAndIgnoresUnknownIDs() {
        let s = store(rules: [rule("a", docked: V6.b(1)), rule("b", "x", docked: V6.b(2))])
        s.remove("nope")
        #expect(!s.history.canUndo)
        s.remove("a")
        #expect(s.document.rules.map(\.id) == ["b"])
        #expect(s.history.undoEntry?.label == L("Pin deleted"))
        s.undo()
        #expect(s.document.rules.map(\.id) == ["a", "b"])
        s.redo()
        #expect(s.document.rules.map(\.id) == ["b"])
    }

    @Test func addAndUpdateReplaceByIDOnly() {
        let s = store(rules: [rule("a", docked: V6.b(1))])
        s.add(rule("c", "z", docked: V6.e(2)))
        #expect(s.document.rules.count == 2 && s.rule("c")?.docked?.desktop == 2)
        var changed = rule("a", docked: V6.b(3))
        changed.undocked = V6.b(4)
        s.update(changed)
        #expect(s.rule("a")?.docked?.desktop == 3 && s.rule("a")?.undocked?.desktop == 4)
        s.update(rule("ghost", docked: V6.b(9))) // olmayan kural eklenmez
        #expect(s.rule("ghost") == nil && s.document.rules.count == 2)
    }

    @Test func pinSameKeyUpdatesExistingRuleAndIsUndoable() {
        let s = store(rules: [rule("a", "mail", docked: V6.e(1))])
        let id = s.pin(sameApp(as: "a", "mail"), destination: V6.e(3), mode: .docked)
        #expect(id == "a" && s.document.rules.count == 1)
        #expect(s.rule("a")?.docked?.desktop == 3)
        #expect(s.history.undoEntry?.label == L("Pin updated"))
        s.undo()
        #expect(s.rule("a")?.docked?.desktop == 1)
    }

    @Test func pinForTheOtherSetupAddsPlaceWithoutOverwriting() {
        let s = store(rules: [rule("a", "mail", docked: V6.e(1))])
        let id = s.pin(sameApp(as: "a", "mail"), destination: V6.b(2), mode: .undocked)
        #expect(id == "a")
        #expect(s.rule("a")?.docked?.desktop == 1 && s.rule("a")?.undocked?.desktop == 2)
    }

    @Test func pinNewKeyAppendsRuleAndReturnsItsID() {
        let s = store()
        let id = s.pin(rule("n", "x"), destination: V6.b(1), mode: .undocked)
        #expect(id == "n" && s.document.rules.map(\.id) == ["n"])
        #expect(s.rule("n")?.docked == nil)
    }

    @Test func pinManyIsOneUndoStepAndRunsCompanion() {
        let s = store()
        s.pinMany([], mode: .docked)
        #expect(!s.history.canUndo)
        var companionRuns = 0
        s.pinMany([(rule("a", "1"), V6.e(1)), (rule("b", "2"), V6.e(2)), (rule("c", "3"), V6.e(2))],
                  mode: .docked) { companionRuns += 1 }
        #expect(s.document.rules.count == 3)
        #expect(s.history.entries.count == 1)
        s.undo()
        #expect(s.document.rules.isEmpty && companionRuns == 1)
    }

    @Test func moveRuleAndSetDestinationBothWriteButOnlyMoveRuleLabels() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        s.moveRule("a", to: V6.e(4), mode: .docked)
        #expect(s.rule("a")?.docked?.desktop == 4)
        #expect(s.history.undoEntry?.label == L("Pin moved"))
        s.setDestination(V6.e(2), for: "a", mode: .docked)
        #expect(s.rule("a")?.docked?.desktop == 2)
        s.setDestination(nil, for: "a", mode: .docked)
        #expect(s.rule("a")?.docked == nil)
        s.setDestination(V6.e(2), for: "missing", mode: .docked) // sessiz
        #expect(s.rule("missing") == nil)
    }

    @Test func movingARuleToANamedRowBecomesANameTargetAndPinsTheOtherSetupToo() {
        let s = store(rules: [rule("a", docked: V6.e(1), undocked: nil)],
                      names: [DesktopName(id: "N", name: "Nova", space: nil)],
                      plans: DesktopPlans(docked: ["external": ["", "N"]], undocked: ["builtin": ["N"]]))
        s.moveRule("a", to: V6.e(2), mode: .docked)
        #expect(s.rule("a")?.docked?.nameID == "N")
        #expect(s.rule("a")?.undocked?.nameID == "N") // N2: öbür kurulumda hedef yoktu
        #expect(nameOrphans(s).isEmpty)
    }

    @Test func unpinRemovesRuleOnlyWhenNoPlaceRemains() {
        let s = store(rules: [rule("a", docked: V6.e(1), undocked: V6.b(2)),
                              rule("b", "t", docked: V6.e(1))])
        s.unpin("a", mode: .docked)
        #expect(s.rule("a")?.docked == nil && s.rule("a")?.undocked != nil)
        s.unpin("a", mode: .undocked)
        #expect(s.rule("a") == nil)
        s.unpin("b", mode: .undocked) // o modda zaten yok: kural kalır
        #expect(s.rule("b") != nil)
        s.undo()
        #expect(s.rule("a") != nil)
    }

    @Test func removeAndMovePlaceWorkOnOrderedPlaces() {
        var r = rule("m", docked: V6.e(1))
        r.setPlaces([V6.e(1), V6.at("external-2", 2), V6.b(3)], mode: .docked)
        let s = store(rules: [r])
        s.movePlace(from: 2, to: 0, for: "m", mode: .docked)
        #expect(s.rule("m")?.places(.docked).map(\.screen) == ["builtin", "external", "external-2"])
        s.removePlace(at: 0, for: "m", mode: .docked)
        #expect(s.rule("m")?.places(.docked).map(\.screen) == ["external", "external-2"])
        s.removePlace(at: 0, for: "m", mode: .docked)
        s.removePlace(at: 0, for: "m", mode: .docked)
        #expect(s.rule("m") == nil) // son yer gidince kural da gider
    }

    @Test func moveGroupMovesAllRulesInOneStep() {
        let s = store(rules: [rule("a", "1", docked: V6.e(1)), rule("b", "2", docked: V6.e(1))])
        s.moveGroup([], mode: .docked)
        #expect(!s.history.canUndo)
        s.moveGroup([GroupMovePlan.RuleMove(id: "a", destination: V6.e(3)),
                     GroupMovePlan.RuleMove(id: "b", destination: V6.e(4))], mode: .docked)
        #expect(s.rule("a")?.docked?.desktop == 3 && s.rule("b")?.docked?.desktop == 4)
        #expect(s.history.entries.count == 1)
    }

    @Test func moveGroupWithOnlyACompanionStillRecordsAStep() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        var ran = false
        s.moveGroup([], mode: .docked, undoingSessionPins: { ran = true })
        #expect(s.history.canUndo)
        s.undo()
        #expect(ran)
    }

    @Test func setTokensRejectsDuplicateKeysAndKeepsTheDocument() {
        let s = store(rules: [rule("a", "mail", docked: V6.e(1)), rule("b", "news", docked: V6.e(1))])
        // Aynı uygulama olmalı: çakışma yalnız aynı uygulama + parça için.
        var other = rule("c", "alpha", docked: V6.e(1))
        other.appName = "App-a"; other.bundleID = "b.a"
        s.add(other)
        let before = s.document
        let ok = s.setTokens(["mail"], for: "c")
        #expect(!ok && s.document == before)
        let renamed = s.setTokens(["beta", "gamma"], for: "c")
        #expect(renamed && s.rule("c")?.tokens == ["beta", "gamma"])
        s.undo()
        #expect(s.rule("c")?.tokens == ["alpha"])
    }

    @Test func saveLayoutReportsWhetherAnythingChanged() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        #expect(s.saveLayout(.leftHalf, for: "a", mode: .docked))
        #expect(!s.saveLayout(.leftHalf, for: "a", mode: .docked))
        #expect(!s.saveLayout(.leftHalf, for: "a", mode: .undocked)) // o modda hedef yok
        #expect(!s.saveLayout(.leftHalf, for: "zzz", mode: .docked))
        #expect(s.history.entries.count == 1)
    }

    @Test func adoptLayoutResultsCoverEveryBranch() {
        let same = Destination(screen: "builtin", desktop: 2, layout: .full)
        var r = rule("a", docked: Destination(screen: "builtin", desktop: 2, layout: .leftHalf), undocked: same)
        r.id = "a"
        let s = store(rules: [r, rule("only", docked: V6.b(1)), rule("far", docked: V6.b(1), undocked: V6.b(5)),
                              rule("eq", docked: V6.b(1), undocked: V6.b(1))])
        #expect(s.adoptLayout(for: "ghost", from: .docked) == .ruleNotFound)
        #expect(s.adoptLayout(for: "only", from: .docked) == .missingPlan)
        #expect(s.adoptLayout(for: "far", from: .docked) == .notSamePlace)
        #expect(s.adoptLayout(for: "eq", from: .docked) == .alreadyEqual)
        #expect(s.adoptLayout(for: "a", from: .docked) == .copied)
        #expect(s.rule("a")?.undocked?.layout == .leftHalf)
        #expect(s.adoptLayout(for: "a", from: .docked) == .alreadyEqual)
        #expect(s.history.entries.count == 1)
    }

    @Test func copyLayoutCopiesSetupAndIsUndoable() {
        let s = store(rules: [rule("a", docked: V6.e(2)), rule("b", undocked: V6.b(1))])
        #expect(s.copyLayout(from: .docked, to: .undocked))
        #expect(s.rule("a")?.undocked != nil)
        #expect(s.rule("b") == nil) // kaynakta yeri olmayan kuralın hedefi silindi, kural gitti
        #expect(!s.copyLayout(from: .docked, to: .undocked)) // ikincisi değişiklik yapmaz
        s.undo()
        #expect(s.rule("b") != nil && s.rule("a")?.undocked == nil)
    }

    // MARK: - Geri alma geçmişi

    @Test func undoKeepsEnabledSwitchAndScreensButRevertsRules() {
        let s = store()
        s.add(rule("a", docked: V6.e(1)))
        s.remember([KnownScreen(id: "external", name: "Monitor", aspect: 1.78)])
        let enabledBefore = s.document.enabled
        s.pin(rule("b", "t"), destination: V6.e(2), mode: .docked)
        s.document.enabled = !enabledBefore
        s.undo()
        #expect(s.rule("b") == nil)
        #expect(s.document.enabled == !enabledBefore) // anahtar geri alınmaz
        #expect(s.document.screens.map(\.id) == ["external"])
    }

    @Test func returnToJumpsToAnyPointWithoutAddingEntries() {
        let s = store()
        for i in 1...3 { s.pin(rule("r\(i)", "t\(i)"), destination: V6.e(i), mode: .docked) }
        let count = s.history.entries.count
        s.returnTo(1)
        #expect(s.document.rules.count == 1)
        s.returnTo(0)
        #expect(s.document.rules.isEmpty)
        s.returnTo(count)
        #expect(s.document.rules.count == 3)
        #expect(s.history.entries.count == count)
        s.returnTo(99) // geçersiz konum: dokunmaz
        #expect(s.document.rules.count == 3)
    }

    @Test func newChangeAfterUndoDropsTheRedoBranch() {
        let s = store()
        s.pin(rule("a", "1"), destination: V6.e(1), mode: .docked)
        s.pin(rule("b", "2"), destination: V6.e(1), mode: .docked)
        s.undo()
        #expect(s.history.canRedo)
        s.pin(rule("c", "3"), destination: V6.e(1), mode: .docked)
        #expect(!s.history.canRedo)
        #expect(s.document.rules.map(\.id) == ["a", "c"])
    }

    @Test func recordSessionChangeUndoRunsCompanionButCannotBeRedone() {
        let s = store()
        var undone = 0
        s.recordSessionChange("Session pin moved") { undone += 1 }
        #expect(s.history.canUndo)
        s.undo()
        #expect(undone == 1)
        #expect(!s.history.canRedo)
    }

    @Test func untrackedDocumentChangesStillLandInHistoryButNoiseDoesNot() {
        let s = store()
        s.document.rules = [rule("x", docked: V6.e(1))]
        #expect(s.history.entries.count == 1)
        s.remember([KnownScreen(id: "external", name: "Monitor", aspect: 1.78)])
        #expect(s.history.entries.count == 1) // ekran bilgisi gürültüdür
    }

    @Test func enabledChangesCountsOnlyRealSwitchFlips() {
        let s = store()
        #expect(s.enabledChanges == 0)
        s.document.enabled = false
        s.document.enabled = false
        s.document.enabled = true
        #expect(s.enabledChanges == 2)
    }

    // MARK: - Masaüstü adları

    @Test func setDesktopNameRejectsConflictsWithoutHistoryAndReportsAcceptance() {
        let s = store(names: [DesktopName(id: "N", name: "Nova", space: nil)],
                      plans: DesktopPlans(docked: ["external": ["N"]]))
        #expect(!s.setDesktopName(" NOVA ", screen: "external", desktop: 2, mode: .docked))
        #expect(!s.history.canUndo)
        #expect(s.setDesktopName("Orion", screen: "external", desktop: 2, mode: .docked))
        #expect(s.desktopName(screen: "external", desktop: 2, mode: .docked) == "Orion")
        #expect(s.nameID(screen: "external", desktop: 1, mode: .docked) == "N")
        s.undo()
        #expect(s.document.names.map(\.name) == ["Nova"])
    }

    @Test func settingAndClearingNamesNeverLeavesOrphanNamePins() {
        let s = store(rules: [rule("a", docked: V6.e(2))])
        #expect(s.setDesktopName("Mail", screen: "external", desktop: 2, mode: .docked))
        #expect(s.rule("a")?.docked?.nameID != nil)
        #expect(s.setDesktopName("", screen: "external", desktop: 2, mode: .docked))
        #expect(s.rule("a")?.docked?.nameID == nil)
        #expect(nameOrphans(s).isEmpty)
    }

    @Test func deleteNameTurnsPinsIntoAGhostAndRestoreBringsThemBack() {
        let s = store(rules: [rule("a", docked: V6.at("external", 2, name: "W"))],
                      names: [DesktopName(id: "W", name: "Waiting", space: nil)],
                      plans: DesktopPlans(docked: ["external": ["", "W"]]))
        s.deleteName("W")
        #expect(s.document.names.isEmpty && s.rule("a") == nil)
        #expect(s.ghosts(on: "external").count == 1)
        let ghost = s.ghosts(on: "external")[0]
        #expect(s.ghosts(on: "external", mode: .docked).count == 1)
        s.restoreGhost(ghost.id, desktop: 3, space: nil, mode: .docked)
        #expect(s.ghosts(on: "external").isEmpty)
        #expect(s.document.names.map(\.name) == ["Waiting"])
        #expect(s.rule("a")?.docked?.nameID == "W" && s.rule("a")?.docked?.desktop == 3)
        s.undo()
        #expect(s.ghosts(on: "external").count == 1)
        #expect(nameOrphans(s).isEmpty)
    }

    @Test func discardGhostForgetsPinsForGoodButCanBeUndone() {
        let s = store(rules: [rule("a", docked: V6.at("external", 1, name: "W"))],
                      names: [DesktopName(id: "W", name: "Waiting")],
                      plans: DesktopPlans(docked: ["external": ["W"]]))
        s.deleteName("W")
        s.discardGhost(s.ghosts(on: "external")[0].id)
        #expect(s.ghosts(on: "external").isEmpty && s.document.rules.isEmpty)
        s.undo()
        #expect(s.ghosts(on: "external").count == 1)
    }

    @Test func recordDeletionShiftsNumbersAndGhostsNamedDesktop() {
        let s = store(rules: [rule("a", docked: V6.at("external", 2, name: "N")), rule("b", "t", docked: V6.e(3))],
                      names: [DesktopName(id: "N", name: "Nova", space: 21)],
                      plans: DesktopPlans(docked: ["external": ["", "N", ""]]))
        let ghost = s.recordDeletion(space: 21, role: "external", desktop: 2, mode: .docked)
        #expect(ghost?.name == "Nova")
        #expect(s.document.names.isEmpty && s.rule("b")?.docked?.desktop == 2)
        #expect(nameOrphans(s).isEmpty)
        // Aynı masaüstü bir daha silinmez: ikinci çağrı adsız satır olarak kayar ve hayalet açmaz.
        let again = s.recordDeletion(space: 21, role: "external", desktop: 9, mode: .docked)
        #expect(again == nil)
    }

    @Test func followMissionControlThroughTheStoreReturnsDeletions() {
        let s = store(names: [DesktopName(id: "B", name: "Beta", space: 11)],
                      plans: DesktopPlans(docked: ["external": ["", "B", ""]]))
        let deletions = s.followMissionControl(before: ["external": [10, 11, 12]],
                                               after: ["external": [10, 12]], mode: .docked,
                                               ownRemovals: [])
        #expect(deletions.map(\.space) == [11])
        #expect(s.document.names.isEmpty)
        let none = s.followMissionControl(before: ["external": [10, 12]], after: ["external": [10, 12]],
                                          mode: .docked, ownRemovals: [])
        #expect(none.isEmpty)
    }

    @Test func planDesktopAndRemovePlanEntryAreUndoable() {
        let s = store(rules: [rule("a", docked: V6.e(2)), rule("b", "t", docked: V6.e(3))],
                      plans: DesktopPlans(docked: ["external": ["", ""]]))
        s.planDesktop(on: "external", mode: .docked, count: 3)
        #expect(s.document.plans.entries(.docked, "external").count == 3)
        var companion = 0
        s.removePlanEntry(on: "external", desktop: 2, mode: .docked) { companion += 1 }
        #expect(s.document.plans.entries(.docked, "external").count == 2)
        #expect(s.rule("b")?.docked?.desktop == 2 && s.rule("a") == nil)
        s.undo()
        #expect(s.rule("a")?.docked?.desktop == 2 && s.rule("b")?.docked?.desktop == 3)
        #expect(companion == 1)
    }

    @Test func moveDesktopRecordsAStepEvenWhenOnlyTheCompanionMatters() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        var ran = false
        s.moveDesktop(on: "external", from: 1, to: 1, count: 2, mode: .docked) { ran = true }
        #expect(s.history.canUndo && s.rule("a")?.docked?.desktop == 1)
        s.undo()
        #expect(ran)
        s.moveDesktop(on: "external", from: 1, to: 2, count: 2, mode: .docked)
        #expect(s.rule("a")?.docked?.desktop == 2)
    }

    @Test func moveDesktopAcrossThroughTheStoreMovesPinsAndRestoresOnUndo() {
        let s = store(rules: [rule("a", docked: V6.at("external", 2))],
                      plans: DesktopPlans(docked: ["external": ["", "X"], "external-2": [""]]))
        s.moveDesktopAcross(from: "external", desktop: 2, to: "external-2", at: 1, toCount: 1, mode: .docked)
        #expect(s.rule("a")?.docked?.screen == "external-2")
        #expect(s.document.plans.entries(.docked, "external") == [""])
        s.undo()
        #expect(s.rule("a")?.docked?.screen == "external")
        #expect(s.document.plans.entries(.docked, "external") == ["", "X"])
    }

    @Test func bindByPlanAndNameCachesFollowTheLiveDesktops() {
        let s = store(rules: [rule("p", docked: V6.at("external", 9, name: "N"))],
                      names: [DesktopName(id: "N", name: "Nova", space: nil)],
                      plans: DesktopPlans(docked: ["external": ["", "N"]]))
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 11]])
        s.setLive(live)
        #expect(s.rule("p")?.docked?.desktop == 2) // plandaki yer
        s.bindByPlan(live: live)
        #expect(s.document.names.first?.space == 11)
        s.setLive(LiveDesktops(mode: .docked, spaces: ["external": [11, 10]]))
        #expect(s.rule("p")?.docked?.desktop == 1) // canlı sıra değişince önbellek yenilenir
        s.setLive(nil)
        #expect(s.live == nil)
        #expect(s.rule("p")?.docked?.desktop == 2) // canlı bilinmiyor: plandaki yer
    }

    @Test func commitPlanRebindsActiveNamesAndAppliesSpaceMapEverywhere() {
        var d = V6.document(names: [DesktopName(id: "A", name: "Alpha", space: 10),
                                    DesktopName(id: "B", name: "Beta", space: nil)])
        d.addProfile(named: "Other", activate: true)
        d.names = [DesktopName(id: "Z", name: "Zed", space: 10)]
        d.syncActiveProfile()
        d.switchProfile(to: d.profiles[0].id)
        let s = Store(demo: d)
        s.commitPlan(rebinds: ["B": 30], spaceMap: [10: 77])
        #expect(s.document.names.map(\.space) == [77, 30])
        #expect(s.document.profiles.last?.names.first?.space == 77)
    }

    @Test func commitRevertMovesPlanEntryBackAndRebindsNames() {
        let s = store(names: [DesktopName(id: "A", name: "Alpha", space: 10)],
                      plans: DesktopPlans(docked: ["external": [""], "external-2": ["A"]]))
        s.commitRevert(spaceMap: [10: 11], from: "external-2", desktop: 1, to: "external", at: 1, mode: .docked)
        #expect(s.document.names.first?.space == 11)
        #expect(s.document.plans.entries(.docked, "external") == ["A", ""] )
        #expect(s.document.plans.entries(.docked, "external-2").isEmpty)
    }

    @Test func pendingRemovalQueueAcrossTheStore() {
        let s = store()
        s.document.pendingRemovals[Document.planKey(mode: .undocked, screen: "builtin")] =
            [PendingRemoval(desktop: 2, space: 7), PendingRemoval(desktop: 3, space: 8)]
        s.dropFirstPendingRemoval(mode: .undocked, screen: "builtin")
        #expect(s.document.pendingRemovals(mode: .undocked, screen: "builtin").map(\.desktop) == [3])
        s.clearPendingRemovals(mode: .undocked, screen: "builtin")
        #expect(s.document.pendingRemovals.isEmpty)
    }

    @Test func nameTargetAndNamedPlacesRespectTheLiveSetup() {
        let s = store(names: [DesktopName(id: "A", name: "Alpha", space: 11),
                              DesktopName(id: "B", name: "Beta", space: nil)],
                      plans: DesktopPlans(docked: ["external": ["", "A"], "builtin": ["B"]],
                                          undocked: ["builtin": ["B", "A"]]))
        #expect(s.nameTarget(nil, mode: .docked) == nil)
        #expect(s.nameTarget(V6.e(1), mode: .docked) == nil) // numara hedefi
        #expect(s.nameTarget(V6.at("external", 2, name: "GONE"), mode: .docked) == nil)
        // Canlı yokken yer planın yeri.
        #expect(s.nameTarget(V6.at("external", 2, name: "A"), mode: .docked)?.waiting == false)
        #expect(s.namedPlaces(mode: .docked).map(\.name) == ["Beta", "Alpha"]) // builtin < external
        // Canlı kurulumda: space canlı değilse bekliyor.
        s.setLive(LiveDesktops(mode: .docked, spaces: ["external": [10]]))
        #expect(s.nameTarget(V6.at("external", 2, name: "A"), mode: .docked)?.waiting == true)
        s.setLive(LiveDesktops(mode: .docked, spaces: ["external": [10, 11]]))
        let target = s.nameTarget(V6.at("external", 2, name: "A"), mode: .docked)
        #expect(target?.name == "Alpha" && target?.waiting == false)
        // Öbür kurulum için canlıya değil plana bakar.
        #expect(s.nameTarget(V6.at("builtin", 1, name: "B"), mode: .undocked)?.waiting == false)
        // Canlı kurulumda ad bir masaüstüne bağlı değilse bekliyor, planı olsa da.
        #expect(s.nameTarget(V6.at("builtin", 1, name: "B"), mode: .docked)?.waiting == true)
    }

    // MARK: - Profiller

    @Test func profileLifecycleThroughTheStore() {
        let s = store(rules: [rule("a", "t", docked: V6.e(1))])
        let first = s.profiles[0].id
        let copy = s.addProfile(named: "Copy", copyingCurrent: true)
        #expect(s.activeProfile?.id == copy.id && s.document.rules.count == 1)
        #expect(s.document.rules[0].id != "a") // kopya yeni kimlik alır
        s.renameProfile(copy.id, to: "   ") // boş ad yok sayılır
        #expect(s.profiles.last?.name == "Copy")
        s.renameProfile(copy.id, to: " Ofis 🏢 ")
        #expect(s.profiles.last?.name == "Ofis 🏢")
        s.switchProfile(to: first)
        #expect(s.activeProfile?.id == first)
        s.switchProfile(to: "unknown")
        #expect(s.activeProfile?.id == first)
        let dup = s.duplicateProfile(copy.id, named: "Ofis 🏢")
        #expect(dup?.name == "Ofis 🏢 (2)" || dup?.name.hasPrefix("Ofis 🏢") == true)
        #expect(dup?.name != "Ofis 🏢")
        #expect(s.duplicateProfile("nope", named: "X") == nil)
        s.deleteProfile(copy.id)
        #expect(!s.profiles.contains { $0.id == copy.id })
        s.undo()
        #expect(s.profiles.contains { $0.id == copy.id })
    }

    @Test func lastProfileCannotBeDeletedAndLeavesNoHistory() {
        let s = store()
        let only = s.profiles[0].id
        s.deleteProfile(only)
        #expect(s.profiles.count == 1)
        #expect(!s.history.canUndo)
    }

    @Test func deletingTheActiveProfileActivatesAnotherWithItsOwnRules() {
        let s = store(rules: [rule("a", "t", docked: V6.e(1))])
        let first = s.profiles[0].id
        let second = s.addProfile(named: "Second")
        s.add(rule("b", "u", docked: V6.e(2)))
        s.deleteProfile(second.id)
        #expect(s.activeProfile?.id == first)
        #expect(s.document.rules.map(\.id) == ["a"])
    }

    @Test func profilesKeepTheirOwnNamesPlansAndGhosts() {
        let s = store(names: [DesktopName(id: "A", name: "Alpha")],
                      plans: DesktopPlans(docked: ["external": ["A"]]))
        let first = s.profiles[0].id
        s.addProfile(named: "Fresh")
        #expect(s.document.names.isEmpty && s.document.plans.isEmpty)
        #expect(s.setDesktopName("Alpha", screen: "external", desktop: 1, mode: .docked)) // başka profilde çakışmaz
        s.switchProfile(to: first)
        #expect(s.document.names.map(\.id) == ["A"])
    }

    @Test func upsertProfileUpdatesByExactNameKeepingIdentity() {
        let s = store()
        let incoming = Profile(name: "Work", rules: [rule("w", "x", docked: V6.b(1))])
        s.upsertProfile(incoming, activate: false)
        #expect(s.profiles.count == 2)
        let workID = s.profiles.first { $0.name == "Work" }!.id
        var again = Profile(name: "Work", rules: [rule("w2", "y", docked: V6.b(2))])
        again.id = "other-id"
        s.upsertProfile(again, activate: true)
        #expect(s.profiles.count == 2)
        #expect(s.activeProfile?.id == workID)
        #expect(s.document.rules.map(\.id) == ["w2"])
    }

    @Test func exportAndImportRoundTripANamedProfile() throws {
        let s = store(rules: [rule("a", "t", docked: V6.at("external", 2, name: "N"))],
                      names: [DesktopName(id: "N", name: "Nova", space: 99)],
                      plans: DesktopPlans(docked: ["external": ["", "N"]]))
        let data = try s.exportData(for: s.profiles[0].id)
        let imported = try s.importProfile(from: data)
        #expect(s.activeProfile?.id == imported.id)
        #expect(s.document.names.map(\.name) == ["Nova"])
        #expect(s.document.names.first?.id != "N") // kimlikler yenilenir
        #expect(s.document.names.first?.space == nil) // bağlar dışa aktarılmaz
        #expect(s.document.rules.first?.id != "a")
        #expect(s.document.rules.first?.docked?.nameID == s.document.names.first?.id)
        #expect(nameOrphans(s).isEmpty)
        s.undo()
        #expect(s.activeProfile?.id == s.profiles[0].id)
    }

    @Test func importOfForeignDataThrowsAndPublishesNothing() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        let before = s.document
        #expect(throws: (any Error).self) { try s.importProfile(from: Data("{\"bogus\":1}".utf8)) }
        #expect(throws: (any Error).self) { try s.importProfile(from: Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try s.exportData(for: "nope") }
        #expect(s.document == before)
    }

    @Test func importBindsNamesToTheLivePlanWhenLiveStateIsKnown() throws {
        let source = store(names: [DesktopName(id: "N", name: "Nova", space: 5)],
                           plans: DesktopPlans(docked: ["external": ["", "N"]]))
        let data = try source.exportData(for: source.profiles[0].id)
        let target = store()
        target.setLive(LiveDesktops(mode: .docked, spaces: ["external": [40, 41]]))
        try target.importProfile(from: data)
        #expect(target.document.names.first?.space == 41)
    }

    // MARK: - Ekranlar

    @Test func rememberSortsKeepsBuiltinFirstAndSkipsTestDisplays() {
        let s = store()
        s.remember([KnownScreen(id: "external-2", name: "B", aspect: 1.6),
                    KnownScreen(id: "builtin", name: "Built-in", aspect: 1.55),
                    KnownScreen(id: "external", name: "A", aspect: 1.78),
                    KnownScreen(id: "external-9", name: Store.testDisplayName, aspect: 1.78),
                    KnownScreen(id: "external-8", name: Store.testDisplayName + " (2)", aspect: 1.78)])
        #expect(s.document.screens.map(\.id) == ["builtin", "external", "external-2"])
        // Aynı kimlik güncellenir, çoğalmaz.
        s.remember([KnownScreen(id: "external", name: "A2", aspect: 2.0)])
        #expect(s.document.screens.map(\.name) == ["Built-in", "A2", "B"])
        let enough = s.document.screens
        s.remember([]) // değişiklik yok
        #expect(s.document.screens == enough)
    }

    @Test func testDisplayDetectionHonoursTheLearningFlag() {
        #expect(Store.isTestDisplay(Store.testDisplayName, learning: false))
        #expect(Store.isTestDisplay(Store.testDisplayName + " (1)", learning: false))
        #expect(!Store.isTestDisplay(Store.testDisplayName + "X", learning: false))
        #expect(!Store.isTestDisplay("", learning: false))
        #expect(!Store.isTestDisplay(Store.testDisplayName, learning: true))
    }

    @Test func screenListsAndSizesFallBackToDefaults() {
        let s = store()
        #expect(s.screens(for: .undocked).map(\.id) == ["builtin"])
        #expect(s.screens(for: .docked).map(\.id) == ["external", "builtin"])
        #expect(s.screenSize(of: "nowhere") == CGSize(width: 1710, height: 1074))
        var known = KnownScreen(id: "external", name: "M", aspect: 2)
        #expect(known.visibleSize == CGSize(width: 2000, height: 1000))
        known.visibleWidth = 2560; known.visibleHeight = 1415
        s.remember([known])
        #expect(s.screenSize(of: "external") == CGSize(width: 2560, height: 1415))
        #expect(s.screens(for: .docked).map(\.id) == ["external", "builtin"])
        var narrow = KnownScreen(id: "external-3", name: "tall", aspect: 0.1)
        #expect(narrow.visibleSize == CGSize(width: 500, height: 1000)) // en-boy oranı en az 0.5
        narrow.visibleWidth = 0
        narrow.visibleHeight = 10
        #expect(narrow.knownVisibleSize == nil)
    }

    @Test func forgettingDisplayRolesIsANoOpWhenNothingIsRemembered() {
        let s = store()
        let before = s.document.displayRoles
        s.forgetDisplayRoles()
        #expect(s.document.displayRoles == before)
        s.learnDisplayRoles([(role: "external", uuid: "AAA")])
        #expect(s.document.displayRoles.learnedOnce)
        s.forgetDisplayRoles()
        #expect(s.document.displayRoles.remembered.isEmpty && !s.document.displayRoles.learnedOnce)
        s.forgetDisplay("AAA") // bilinmeyen: sorun yok
    }

    // MARK: - Düzen kitaplığı ve geri yükleme

    @Test func changeLayoutsOnlyRecordsRealChanges() {
        let s = store()
        let changed = s.changeLayouts("noop") { _ in false }
        #expect(!changed && !s.history.canUndo)
        let same = s.changeLayouts("same") { _ in true } // değişmeyen kitaplık
        #expect(!same && !s.history.canUndo)
        s.resetLayouts()
        #expect(!s.history.canUndo) // zaten varsayılan
    }

    @Test func restoredLayoutsPrefersBackupUnlessItIsTheDefault() {
        let defaults = LayoutLibrary.defaults
        #expect(Store.restoredLayouts(backup: defaults, current: defaults) == defaults)
    }

    @Test func restoreBackupRefusesNewerVersionsAndKeepsCurrentState() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        var newer = V6.document(rules: [rule("n", docked: V6.e(1))])
        newer.fileVersion = Document.currentVersion + 1
        #expect(!s.restoreBackup(newer))
        #expect(s.lastError == Store.newerVersionMessage)
        #expect(s.rule("a") != nil && s.rule("n") == nil)
    }

    @Test func restoreBackupDoesNotRevertTheSwitchOrScreensAndClearsDroppedCount() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        s.document.enabled = false
        s.remember([KnownScreen(id: "external", name: "M", aspect: 1.78)])
        var backup = V6.document(rules: [rule("b", docked: V6.e(2))])
        backup.enabled = true
        backup.droppedRuleCount = 3
        #expect(s.restoreBackup(backup))
        #expect(s.document.rules.map(\.id) == ["b"])
        #expect(s.document.enabled == false)
        #expect(s.document.screens.map(\.id) == ["external"])
        #expect(s.document.droppedRuleCount == 0)
        #expect(s.history.undoEntry?.label == L("Backup restored"))
    }

    @Test func restoringASchemaFiveBackupWaitsForMigrationThenCompletesWithoutEvidence() {
        let s = store(rules: [rule("keep", docked: V6.e(1))])
        var old = V6.document(rules: [rule("old", docked: V6.b(2))])
        old.fileVersion = 5
        #expect(old.needsNameMigration)
        #expect(s.restoreBackup(old))
        #expect(s.migrationPending)
        #expect(s.completeMigration(evidence: nil))
        #expect(!s.migrationPending && s.migrationReport != nil)
        #expect(s.document.rules.map(\.id) == ["old"])
        s.dismissMigrationReport()
        #expect(s.migrationReport == nil)
        #expect(!s.completeMigration(evidence: nil)) // ikinci kez: iş kalmadı
    }

    @Test func undoUpgradeWithoutBackupReportsInsteadOfCrashing() {
        let s = store()
        s.undoUpgrade()
        #expect(s.lastError == L("The pre-upgrade backup could not be read"))
        #expect(!s.upgradeUndone)
        s.clearError()
        #expect(s.lastError == nil)
        s.report("boom")
        #expect(s.lastError == "boom")
    }

    @Test func demoStoreNeverPersistsAndFlushSucceeds() {
        let s = store(rules: [rule("a", docked: V6.e(1))])
        #expect(s.save())
        #expect(s.flush())
        #expect(!s.isReadOnly)
        #expect(!s.migrationPending)
    }

    @Test func successionWithNothingLostLeavesNamesAndEvacuationUntouched() {
        let s = store(names: [DesktopName(id: "A", name: "Alpha", space: 10)],
                      plans: DesktopPlans(docked: ["external": ["A"]]))
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10]])
        let snapshot = Succession.Snapshot(spaces: ["external": [10]], contents: [:])
        let evacuation = s.resolveSuccession(snapshot: snapshot, live: live, windowSpaces: [:])
        #expect(evacuation.isEmpty)
        #expect(s.document.names.first?.space == 10)
    }
}

/// Önce-geçiş yedeği: yalnız geçici klasör (`directory:` verilir).
struct PreMigrationBackupTests {

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("DeskmapStoreTests-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try body(dir)
    }

    private let moment = Date(timeIntervalSince1970: 1_791_000_000) // 2026-10-03T03:20:00Z

    @Test func copiesRulesAndSpacesWithUTCStamp() throws {
        try withDirectory { dir in
            try Data("v5-rules".utf8).write(to: dir.appendingPathComponent("rules.json"))
            try Data("spaces".utf8).write(to: dir.appendingPathComponent(DesktopStateFile.legacyFileName))
            let url = try Store.writePreMigrationBackup(at: moment, directory: dir)
            #expect(url.deletingLastPathComponent().path.hasSuffix("Backups/pre-migration"))
            #expect(url.lastPathComponent.hasPrefix("rules-v5-") && url.lastPathComponent.hasSuffix("Z.json"))
            #expect(try String(contentsOf: url, encoding: .utf8) == "v5-rules")
            let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            #expect(siblings.count == 2 && siblings.contains { $0.hasPrefix("desktop-spaces-") })
        }
    }

    @Test func overwritesSameSecondCopyAndSkipsMissingSpacesFile() throws {
        try withDirectory { dir in
            let rules = dir.appendingPathComponent("rules.json")
            try Data("first".utf8).write(to: rules)
            _ = try Store.writePreMigrationBackup(at: moment, directory: dir)
            try Data("second".utf8).write(to: rules)
            let url = try Store.writePreMigrationBackup(at: moment, directory: dir)
            #expect(try String(contentsOf: url, encoding: .utf8) == "second")
            let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            #expect(siblings.count == 1)
        }
    }

    @Test func throwsWhenThereIsNoRulesFile() throws {
        try withDirectory { dir in
            #expect(throws: (any Error).self) { try Store.writePreMigrationBackup(at: moment, directory: dir) }
        }
    }
}
