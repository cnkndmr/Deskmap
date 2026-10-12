import Foundation
import Testing
@testable import Deskmap

/// Per-profile desktop state (spec: docs/profile-desktop-state.md).
/// Names, bindings, ghosts and plans belong to a profile; pendingRemovals
/// and physical desktops are shared. Every cell of the operation x state
/// table, migration of old shared state, file format and visible surfaces.
struct ProfileDesktopStateTests {

    private let D = Mode.docked, U = Mode.undocked

    private func rule(_ app: String, _ desktop: Int, screen: String = "external",
                      mode: Mode = .docked) -> Rule {
        var r = Rule(appName: app, bundleID: "b.\(app)", tokens: [])
        r[mode] = Destination(screen: screen, desktop: desktop)
        return r
    }

    private func profile(_ d: Document, _ id: String) throws -> Profile {
        try #require(d.profiles.first { $0.id == id })
    }

    /// Profile A (active, synced): rule on external/2, name "Nova" bound to
    /// space 20, plan 4 on docked|external, one ghost.
    private func richDocument() -> (Document, String) {
        var d = Document()
        d.rules = [rule("A", 2)]
        d.setDesktopName("Nova", screen: "external", desktop: 2, mode: D, space: 20)
        d.setPlannedDesktops(4, mode: D, screen: "external")
        d.ghostDesktops = [GhostDesktop(screen: "external", name: "Old", desktop: 5,
                                        deletedAt: Date(timeIntervalSince1970: 0))]
        d.syncActiveProfile()
        return (d, d.activeProfileID)
    }

    // MARK: - New profile

    @Test func newProfileStartsEmpty() {
        var (d, _) = richDocument()
        let fresh = d.addProfile(named: "Fresh")
        #expect(d.activeProfileID == fresh.id)
        #expect(d.rules.isEmpty)
        #expect(d.desktopNames.isEmpty)
        #expect(d.desktopNameSpaces.isEmpty)
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.plannedDesktops.isEmpty)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == nil)
        #expect(fresh.desktopNames.isEmpty && fresh.ghostDesktops.isEmpty
                && fresh.plannedDesktops.isEmpty && fresh.desktopNameSpaces.isEmpty)
    }

    @Test func newProfileKeepsSharedPendingRemovals() {
        var (d, _) = richDocument()
        d.pendingRemovals[Document.planKey(mode: D, screen: "external")] = [PendingRemoval(desktop: 3)]
        d.addProfile(named: "Fresh")
        #expect(d.pendingRemovals(mode: D, screen: "external").count == 1)
    }

    // MARK: - Delete profile

    /// Profil silinince adları, bağları, hayaletleri ve planı da gider;
    /// kalan profilin durumu değişmez, gerçek masaüstü silme sıraya girmez.
    @Test func deleteProfileDropsItsStateAndQueuesNoRemoval() {
        var (d, first) = richDocument()
        let firstNames = d.desktopNames, firstPlan = d.plannedDesktops
        let copy = d.addProfile(named: "Copy", copyingCurrent: true)
        d.setDesktopName("Only in copy", screen: "builtin", desktop: 2, mode: D)
        let removalsBefore = d.pendingRemovals
        d.deleteProfile(copy.id)
        #expect(!d.profiles.contains { $0.id == copy.id })
        #expect(d.activeProfileID == first)
        #expect(d.desktopNames == firstNames)
        #expect(d.plannedDesktops == firstPlan)
        #expect(d.desktopName(screen: "builtin", desktop: 2, mode: D) != "Only in copy")
        #expect(d.pendingRemovals == removalsBefore)
        #expect(!d.profiles.contains { $0.desktopNames.values.contains { $0.values.contains("Only in copy") } })
    }

    // MARK: - Duplicate profile

    @Test func duplicateCopiesEverything() throws {
        var (d, first) = richDocument()
        let copy = d.addProfile(named: "Copy", copyingCurrent: true)
        #expect(d.rules.map(\.appName) == ["A"])
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.desktopNameSpaces[Document.planKey(mode: D, screen: "external")]?["2"] == 20)
        #expect(d.ghostDesktops.map(\.name) == ["Old"])
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
        #expect(copy.desktopNames == (try profile(d, first)).desktopNames)
    }

    @Test func duplicateIsIndependentAfterwards() throws {
        var (d, first) = richDocument()
        d.addProfile(named: "Copy", copyingCurrent: true)
        d.setDesktopName("Deney", screen: "external", desktop: 2, mode: D)
        d.switchProfile(to: first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
    }

    /// Ayarlar › Profiller › Çoğalt (ui-redesign): tıklanan profilin her
    /// şeyi kopyalanır, etkin profil ve çalışma kopyası değişmez.
    @Test func duplicateInactiveProfileCopiesItsOwnStateWithoutSwitching() throws {
        var (d, first) = richDocument()
        let other = d.addProfile(named: "Other")
        d.rules = [rule("B", 3)]
        d.setDesktopName("Notes", screen: "external", desktop: 3, mode: D, space: 30)
        d.syncActiveProfile()
        let before = d
        let duplicated = d.duplicateProfile(first, named: "First copy")
        let copy = try #require(duplicated)
        #expect(d.activeProfileID == other.id)
        #expect(d.rules == before.rules && d.desktopNames == before.desktopNames)
        let stored = try profile(d, copy.id)
        let source = try profile(d, first)
        #expect(stored.rules.map(\.appName) == ["A"])
        #expect(stored.rules.map(\.id) != source.rules.map(\.id))
        #expect(stored.desktopNames == source.desktopNames)
        #expect(stored.desktopNameSpaces == source.desktopNameSpaces)
        #expect(stored.plannedDesktops == source.plannedDesktops)
        #expect(stored.ghostDesktops.map(\.name) == ["Old"])
        #expect(stored.ghostDesktops.map(\.id) != source.ghostDesktops.map(\.id))
    }

    @Test func duplicateActiveProfileUsesUnsyncedWorkingCopy() throws {
        var (d, first) = richDocument()
        d.setDesktopName("Fresh", screen: "external", desktop: 3, mode: D, space: 30)
        let duplicated = d.duplicateProfile(first, named: "Copy")
        let copy = try #require(duplicated)
        #expect(d.activeProfileID == first)
        #expect(try profile(d, copy.id).desktopNames[Document.planKey(mode: D, screen: "external")]
                == ["2": "Nova", "3": "Fresh"])
    }

    @Test func newProfileWithoutActivatingKeepsWorkingCopy() throws {
        var (d, first) = richDocument()
        let fresh = d.addProfile(named: "Fresh", activate: false)
        #expect(d.activeProfileID == first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
        let stored = try profile(d, fresh.id)
        #expect(stored.rules.isEmpty && stored.desktopNames.isEmpty && stored.ghostDesktops.isEmpty
                && stored.plannedDesktops.isEmpty && stored.desktopNameSpaces.isEmpty)
    }

    // MARK: - Switch profile

    @Test func switchLoadsThatProfilesState() {
        var (d, first) = richDocument()
        let second = d.addProfile(named: "B")
        d.rules = [rule("Z", 2)]
        d.setDesktopName("Deney", screen: "external", desktop: 2, mode: D, space: 20)
        d.setPlannedDesktops(2, mode: D, screen: "external")
        d.switchProfile(to: first)
        #expect(d.rules.map(\.appName) == ["A"])
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.ghostDesktops.map(\.name) == ["Old"])
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
        d.switchProfile(to: second.id)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Deney")
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.plannedDesktops(mode: D, screen: "external") == 2)
    }

    @Test func switchSavesUnsyncedWorkingCopy() throws {
        var (d, first) = richDocument()
        d.setDesktopName("Renamed", screen: "external", desktop: 2, mode: D)
        let second = d.addProfile(named: "B")
        #expect(try profile(d, first).desktopNames[Document.planKey(mode: D, screen: "external")]?["2"] == "Renamed")
        d.switchProfile(to: first)
        d.switchProfile(to: second.id)
        #expect(d.desktopNames.isEmpty)
    }

    @Test func switchNeverQueuesPhysicalRemovals() {
        var (d, first) = richDocument()
        d.addProfile(named: "B")
        d.setPlannedDesktops(1, mode: D, screen: "external")
        d.switchProfile(to: first)
        d.switchProfile(to: d.profiles[1].id)
        // Fewer planned desktops never deletes anything physical.
        #expect(d.pendingRemovals.isEmpty)
    }

    @Test func switchShowsPlanOfTargetSoMissingDesktopsGetCreated() {
        var (d, first) = richDocument()
        d.addProfile(named: "B")
        d.switchProfile(to: first)
        // Router creates up to this count; it is the target profile's plan.
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
    }

    // MARK: - Delete profile

    @Test func deleteRemovesAllItsStateButNoPhysicalDesktop() throws {
        var (d, first) = richDocument()
        let second = d.addProfile(named: "B")
        d.setDesktopName("Deney", screen: "external", desktop: 3, mode: D)
        d.setPlannedDesktops(6, mode: D, screen: "external")
        d.deleteProfile(second.id)
        #expect(d.activeProfileID == first)
        #expect(d.profiles.count == 1)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == nil)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
        #expect(d.pendingRemovals.isEmpty)
    }

    @Test func deleteInactiveLeavesActiveUntouched() {
        var (d, first) = richDocument()
        let second = d.addProfile(named: "B")
        d.switchProfile(to: first)
        let before = d
        d.deleteProfile(second.id)
        #expect(d.desktopNames == before.desktopNames)
        #expect(d.ghostDesktops == before.ghostDesktops)
        #expect(d.plannedDesktops == before.plannedDesktops)
    }

    // MARK: - Export / import

    @Test func exportCarriesNamesAndPlanNotBindingsOrGhosts() throws {
        let (d, first) = richDocument()
        let data = try d.exportData(for: first)
        let payload = try JSONDecoder.iso.decode(ProfileExport.self, from: data)
        #expect(payload.desktopNames[Document.planKey(mode: D, screen: "external")]?["2"] == "Nova")
        #expect(payload.plannedDesktops[Document.planKey(mode: D, screen: "external")] == 4)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("desktopNameSpaces"))
        #expect(!json.contains("ghostDesktops"))
    }

    @Test func importBringsNamesAndPlanWithoutBindingsOrGhosts() throws {
        let (source, first) = richDocument()
        let data = try source.exportData(for: first)
        var d = Document()
        let imported = try d.importProfile(from: data)
        #expect(d.activeProfileID == imported.id)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.desktopNameSpaces.isEmpty)
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
    }

    @Test func importDoesNotTouchOtherProfiles() throws {
        let (source, first) = richDocument()
        let data = try source.exportData(for: first)
        var d = Document()
        let original = d.activeProfileID
        try d.importProfile(from: data)
        d.switchProfile(to: original)
        #expect(d.desktopNames.isEmpty)
        #expect(d.plannedDesktops.isEmpty)
    }

    @Test func oldExportWithoutNamesStillImports() throws {
        let old = #"{"kind":"deskmap-profile","version":2,"name":"Old","rules":[]}"#
        var d = Document()
        try d.importProfile(from: Data(old.utf8))
        #expect(d.desktopNames.isEmpty)
    }

    // MARK: - Copy laptop layout

    @Test func copyLayoutCopiesLaptopNamesAndRemovesDuplicateInDocked() {
        var d = Document()
        d.rules = [rule("A", 3, screen: "builtin", mode: U)]
        // setDesktopName would write builtin names to both setups and then
        // refuse the docked duplicate; build the state directly.
        d.desktopNames = ["undocked|builtin": ["3": "Lab"], "docked|external": ["1": "Lab"]]
        d.copyLayout(from: U, to: D)
        #expect(d.desktopName(screen: "builtin", desktop: 3, mode: D) == "Lab")
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == nil)
    }

    @Test func copyLayoutOnlyAffectsActiveProfile() {
        var d = Document()
        let first = d.activeProfileID
        d.rules = [rule("A", 3, screen: "builtin", mode: U)]
        d.setDesktopName("Lab", screen: "builtin", desktop: 3, mode: U)
        d.addProfile(named: "B")
        d.setDesktopName("Other", screen: "external", desktop: 1, mode: D)
        d.switchProfile(to: first)
        d.copyLayout(from: U, to: D)
        d.switchProfile(to: d.profiles[1].id)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == "Other")
        #expect(d.desktopName(screen: "builtin", desktop: 3, mode: D) == nil)
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func copyLayoutGrowsActivePlan() {
        var d = Document()
        d.rules = [rule("A", 5, screen: "builtin", mode: U)]
        d.setPlannedDesktops(5, mode: U, screen: "builtin")
        d.copyLayout(from: U, to: D)
        #expect(d.plannedDesktops(mode: D, screen: "builtin") >= 5)
    }

    @Test func copyLayoutExtendsPlanForScreenWithoutNames() {
        var d = Document()
        d.setPlannedDesktops(6, mode: U, screen: "builtin")
        #expect(d.hasLayout(in: U))
        let changed = d.copyLayout(from: U, to: D)
        #expect(changed)
        #expect(d.plannedDesktops(mode: D, screen: "builtin") == 6)
    }

    @Test func copyLayoutScreenOnlyInSourceMode() {
        var d = Document()
        d.desktopNames = ["undocked|external-2": ["1": "Side"]]
        let changed = d.copyLayout(from: U, to: D)
        #expect(changed)
        #expect(d.desktopName(screen: "external-2", desktop: 1, mode: D) == "Side")
        #expect(d.plannedDesktops(mode: D, screen: "external-2") == 1)
    }

    @Test func copyLayoutNamesIdenticalButRulesDiffer() {
        var d = Document()
        d.rules = [rule("A", 2, screen: "builtin", mode: U)]
        d.desktopNames = ["undocked|builtin": ["2": "AI"], "docked|builtin": ["2": "AI"]]
        let names = d.desktopNames
        let changed = d.copyLayout(from: U, to: D)
        #expect(changed)
        #expect(d.desktopNames == names)
        #expect(d.rules.first?.docked == Destination(screen: "builtin", desktop: 2))
        let again = d.copyLayout(from: U, to: D)
        #expect(!again)
    }

    @Test func copyLayoutNameChangingSlotDropsStaleBinding() {
        var d = Document()
        d.desktopNames = ["undocked|external": ["3": "Lab"], "docked|external": ["1": "Lab"]]
        d.desktopNameSpaces = ["docked|external": ["1": 11]]
        d.copyLayout(from: U, to: D)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == "Lab")
        #expect(d.desktopNameSpaces["docked|external"] == nil)
    }

    @Test func copyLayoutTakesLaptopBindingFromSource() {
        var d = Document()
        d.desktopNames = ["undocked|builtin": ["3": "Lab"], "docked|builtin": ["1": "Lab"]]
        d.desktopNameSpaces = ["undocked|builtin": ["3": 33], "docked|builtin": ["1": 11]]
        d.copyLayout(from: U, to: D)
        #expect(d.desktopNames["docked|builtin"] == ["3": "Lab"])
        #expect(d.desktopNameSpaces["docked|builtin"] == ["3": 33])
    }

    // MARK: - Rename / delete / move inside the app

    @Test func renameOnlyInActiveProfile() {
        var (d, first) = richDocument()
        d.addProfile(named: "B", copyingCurrent: true)
        d.setDesktopName("Deney", screen: "external", desktop: 2, mode: D)
        d.switchProfile(to: first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
    }

    @Test func sameNameAllowedInDifferentProfilesForDifferentDesktops() {
        var (d, _) = richDocument()
        d.addProfile(named: "B")
        let accepted = d.setDesktopName("Nova", screen: "external", desktop: 4, mode: D)
        #expect(accepted)
    }

    @Test func moveDesktopShiftsOnlyActiveNames() {
        var (d, first) = richDocument()
        d.addProfile(named: "B", copyingCurrent: true)
        d.moveDesktop(on: "external", from: 2, to: 3, count: 4, mode: D)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == "Nova")
        d.switchProfile(to: first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
    }

    @Test func removeDesktopOnlyActiveProfileNamesGhostsPlan() {
        var (d, first) = richDocument()
        d.addProfile(named: "B", copyingCurrent: true)
        d.removeDesktop(on: "external", desktop: 2, modes: [D])
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == nil)
        d.switchProfile(to: first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
    }

    @Test func restoreGhostOnlyInActiveProfile() throws {
        var (d, first) = richDocument()
        d.addProfile(named: "B", copyingCurrent: true)
        let ghost = try #require(d.ghostDesktops.first)
        d.restoreGhost(ghost.id, desktop: 5)
        #expect(d.ghostDesktops.isEmpty)
        d.switchProfile(to: first)
        #expect(d.ghostDesktops.count == 1)
    }

    @Test func planChangeOnlyInActiveProfile() {
        var (d, first) = richDocument()
        d.addProfile(named: "B", copyingCurrent: true)
        d.setPlannedDesktops(7, mode: D, screen: "external")
        d.switchProfile(to: first)
        #expect(d.plannedDesktops(mode: D, screen: "external") == 4)
    }

    // MARK: - Mission Control (outside the app)

    /// A names external/2 "Nova", B names the same physical space "Deney".
    private func twoProfilesOnSpace20() -> (Document, String, String) {
        var (d, first) = richDocument()
        let second = d.addProfile(named: "B")
        d.rules = [rule("Z", 2)]
        d.setDesktopName("Deney", screen: "external", desktop: 2, mode: D, space: 20)
        d.switchProfile(to: first)
        return (d, first, second.id)
    }

    @Test func missionControlMoveReconcilesAllProfiles() throws {
        var (d, first, second) = twoProfilesOnSpace20()
        let changed = d.reconcileDesktopNames(spaces: ["external": [10, 30, 20]],
                                              seen: [10, 20, 30], mode: D)
        #expect(changed)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == "Nova")
        let key = Document.planKey(mode: D, screen: "external")
        let other = try profile(d, second)
        #expect(other.desktopNames[key]?["3"] == "Deney")
        #expect(other.desktopNames[key]?["2"] == nil)
        #expect(other.desktopNameSpaces[key]?["3"] == 20)
        d.switchProfile(to: second)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == "Deney")
        _ = first
    }

    @Test func missionControlDeleteOpensGhostInEveryNamingProfile() throws {
        var (d, _, second) = twoProfilesOnSpace20()
        let third = d.addProfile(named: "C") // names nothing there
        d.switchProfile(to: d.profiles[0].id)
        d.ghostDesktop(on: "external", desktop: 2, modes: Mode.allCases, droppedSpace: 20)
        #expect(d.ghostDesktops.contains { $0.name == "Nova" })
        #expect(try profile(d, second).ghostDesktops.contains { $0.name == "Deney" })
        #expect(try profile(d, third.id).ghostDesktops.isEmpty)
        // Names do not silently shift onto the next desktop in any profile.
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == nil)
        #expect(try profile(d, second).desktopNames[Document.planKey(mode: D, screen: "external")]?["2"] == nil)
    }

    @Test func missionControlDeleteKeepsUnrelatedNamesInPlace() throws {
        var (d, _, second) = twoProfilesOnSpace20()
        d.switchProfile(to: second)
        d.setDesktopName("Later", screen: "external", desktop: 3, mode: D, space: 30)
        d.switchProfile(to: d.profiles[0].id)
        d.reconcileDesktopNames(spaces: ["external": [10, 30]], seen: [10, 20, 30], mode: D)
        let key = Document.planKey(mode: D, screen: "external")
        #expect(try profile(d, second).desktopNames[key]?["2"] == "Later")
    }

    @Test func reconcileReportsOtherProfilesDropsGroupedBySpace() throws {
        var (d, _, second) = twoProfilesOnSpace20()
        let result = d.reconcileNames(spaces: ["external": [10, 30]], seen: [10, 20, 30], mode: D,
                                       previous: ["external": [10, 20, 30]])
        #expect(result.dropped.map(\.name) == ["Nova"])
        #expect(result.otherDropped[second]?.map(\.name) == ["Deney"])
        let groups = result.ghostGroups
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.space == 20 && group.active?.name == "Nova" && group.others[second]?.name == "Deney")
        d.ghostDesktop(on: group.screen, desktop: group.desktop, modes: Mode.allCases,
                       name: group.active?.name, droppedSpace: group.space,
                       droppedMode: group.active?.place.mode, otherDropped: group.others)
        #expect(d.ghostDesktops.map(\.name) == ["Old", "Nova"])
        let other = try profile(d, second)
        #expect(other.ghostDesktops.map(\.name) == ["Deney"])
        // Each profile's pin on the deleted desktop moved into its own ghost, once.
        #expect(d.rules.isEmpty && other.rules.isEmpty)
    }

    @Test func dropOnlyInInactiveProfileStillOpensItsGhost() throws {
        var (d, first, second) = twoProfilesOnSpace20()
        // A's name sits on another desktop; only B named space 20.
        d.setDesktopName(nil, screen: "external", desktop: 2, mode: D)
        d.setDesktopName("Nova", screen: "external", desktop: 1, mode: D, space: 10)
        let result = d.reconcileNames(spaces: ["external": [10, 30]], seen: [10, 20, 30], mode: D,
                                       previous: ["external": [10, 20, 30]])
        #expect(result.dropped.isEmpty)
        let group = try #require(result.ghostGroups.first)
        #expect(group.active == nil)
        d.ghostDesktop(on: group.screen, desktop: group.desktop, modes: Mode.allCases,
                       droppedSpace: group.space, otherDropped: group.others)
        #expect(try profile(d, second).ghostDesktops.map(\.name) == ["Deney"])
        // A keeps its name where reconcile put it.
        #expect(d.activeProfileID == first)
        #expect(d.desktopName(screen: "external", desktop: 1, mode: D) == "Nova")
    }

    // MARK: - Restore from backup

    @MainActor @Test func restoreBackupRestoresAllProfilesState() throws {
        var backup = twoProfilesOnSpace20().0
        backup.syncActiveProfile()
        let store = Store(demo: Document())
        store.restoreBackup(backup)
        let restored = store.document
        for p in backup.profiles {
            let r = try #require(restored.profiles.first { $0.id == p.id })
            #expect(r.desktopNames == p.desktopNames)
            #expect(r.desktopNameSpaces == p.desktopNameSpaces)
            #expect(r.ghostDesktops == p.ghostDesktops)
            #expect(r.plannedDesktops == p.plannedDesktops)
        }
        #expect(restored.desktopNames == backup.desktopNames)
    }

    // MARK: - Migration of old shared state

    /// Writes `d` as a schema-4 file: shared names/ghosts/plans at the top,
    /// no per-profile fields.
    private func oldFile(_ d: Document) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: Store.encode(d)) as? [String: Any])
        json["version"] = 4
        json["profiles"] = (json["profiles"] as? [[String: Any]])?.map { p in
            p.filter { ["id", "name", "rules"].contains($0.key) }
        }
        // Schema 4 kept the shared state at the top level.
        func object<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
        }
        if !d.desktopNames.isEmpty { json["desktopNames"] = try object(d.desktopNames) }
        if !d.desktopNameSpaces.isEmpty { json["desktopNameSpaces"] = try object(d.desktopNameSpaces) }
        if !d.ghostDesktops.isEmpty { json["ghostDesktops"] = try object(d.ghostDesktops) }
        if !d.plannedDesktops.isEmpty { json["plannedDesktops"] = try object(d.plannedDesktops) }
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Same decoder as `Store.load` (rules.json dates use the default strategy).
    private func load(_ data: Data) throws -> Document {
        try JSONDecoder().decode(Document.self, from: data)
    }

    /// Old shared state: names on external/2 ("Nova"), external/3 ("Deney"),
    /// builtin/1 ("Mail"); plan docked|external = 4; a ghost with B's pin.
    /// Profile A uses external/2; B uses external/3 and builtin/1; C is empty.
    private func legacy() throws -> (Data, a: String, b: String, c: String) {
        var d = Document()
        let a = d.activeProfileID
        d.rules = [rule("A", 2)]
        let b = d.addProfile(named: "B").id
        d.rules = [rule("B", 3), rule("M", 1, screen: "builtin")]
        let c = d.addProfile(named: "C").id
        d.switchProfile(to: a)
        var shared = d
        shared.desktopNames = [
            "docked|external": ["2": "Nova", "3": "Deney"],
            "docked|builtin": ["1": "Mail"], "undocked|builtin": ["1": "Mail"]]
        shared.desktopNameSpaces = ["docked|external": ["2": 20, "3": 30]]
        shared.plannedDesktops = ["docked|external": 4]
        shared.ghostDesktops = [GhostDesktop(
            screen: "external", name: nil, desktop: 6, deletedAt: Date(timeIntervalSince1970: 0),
            pins: [.init(profileID: b, mode: D, rule: rule("G", 6),
                         destination: Destination(screen: "external", desktop: 6))])]
        // Shared state lives on the document only (old layout).
        for i in shared.profiles.indices {
            shared.profiles[i].desktopNames = [:]
            shared.profiles[i].desktopNameSpaces = [:]
            shared.profiles[i].ghostDesktops = []
            shared.profiles[i].plannedDesktops = [:]
        }
        return (try oldFile(shared), a, b, c)
    }

    @Test func migrationGivesNamesOnlyToProfilesUsingThatDesktop() throws {
        let (data, a, b, c) = try legacy()
        let d = try load(data)
        let pa = try profile(d, a), pb = try profile(d, b), pc = try profile(d, c)
        #expect(pa.desktopNames == ["docked|external": ["2": "Nova"]])
        #expect(pb.desktopNames["docked|external"] == ["3": "Deney"])
        #expect(pb.desktopNames["docked|builtin"]?["1"] == "Mail")
        #expect(pc.desktopNames.isEmpty)
        // Active working copy is A's.
        #expect(d.activeProfileID == a)
        #expect(d.desktopName(screen: "external", desktop: 3, mode: D) == nil)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
    }

    @Test func migrationMovesBindingsWithNames() throws {
        let (data, a, b, c) = try legacy()
        let d = try load(data)
        #expect(try profile(d, a).desktopNameSpaces == ["docked|external": ["2": 20]])
        #expect(try profile(d, b).desktopNameSpaces["docked|external"] == ["3": 30])
        #expect(try profile(d, c).desktopNameSpaces.isEmpty)
    }

    @Test func migrationGivesGhostsOnlyToReferencingProfiles() throws {
        let (data, a, b, c) = try legacy()
        let d = try load(data)
        #expect(try profile(d, b).ghostDesktops.count == 1)
        #expect(try profile(d, a).ghostDesktops.isEmpty)
        #expect(try profile(d, c).ghostDesktops.isEmpty)
    }

    /// A name-only ghost (named desktop deleted in Mission Control, no pins)
    /// is not lost: a single-profile schema-4 file keeps it.
    @Test func migrationKeepsPinlessGhostWithSingleProfile() throws {
        let json = """
        {"version":4,"activeProfileID":"p","rules":[{"id":"r","appName":"A","bundleID":"b.A","tokens":[],
          "docked":{"screen":"external","desktop":2}}],
         "profiles":[{"id":"p","name":"P","rules":[{"id":"r","appName":"A","bundleID":"b.A","tokens":[],
          "docked":{"screen":"external","desktop":2}}]}],
         "ghostDesktops":[{"id":"G","screen":"external","name":"Lab","desktop":3,"deletedAt":0,"pins":[]}]}
        """
        let d = try load(Data(json.utf8))
        #expect(d.ghostDesktops.map(\.name) == ["Lab"])
        #expect(try profile(d, "p").ghostDesktops.map(\.name) == ["Lab"])
    }

    /// A pinless ghost goes to profiles that use its screen; when none does,
    /// to the active profile.
    @Test func migrationGivesPinlessGhostsToProfilesUsingThatScreen() throws {
        var d = Document()
        let a = d.activeProfileID
        d.rules = [rule("A", 2)]
        let b = d.addProfile(named: "B").id
        d.rules = [rule("M", 1, screen: "builtin", mode: U)]
        let c = d.addProfile(named: "C").id
        d.switchProfile(to: a)
        var shared = d
        let epoch = Date(timeIntervalSince1970: 0)
        shared.ghostDesktops = [
            GhostDesktop(id: "L", screen: "builtin", name: "Lab", desktop: 3, deletedAt: epoch),
            GhostDesktop(id: "X", screen: "other", name: "Nowhere", desktop: 1, deletedAt: epoch),
        ]
        for i in shared.profiles.indices { shared.profiles[i].ghostDesktops = [] }
        let loaded = try load(try oldFile(shared))
        #expect(try profile(loaded, b).ghostDesktops.map(\.id) == ["L"])
        #expect(try profile(loaded, a).ghostDesktops.map(\.id) == ["X"])
        #expect(try profile(loaded, c).ghostDesktops.isEmpty)
    }

    @Test func migrationGivesPlansToProfilesUsingThatScreen() throws {
        let (data, a, b, c) = try legacy()
        let d = try load(data)
        #expect(try profile(d, a).plannedDesktops == ["docked|external": 4])
        #expect(try profile(d, b).plannedDesktops["docked|external"] == 4)
        #expect(try profile(d, c).plannedDesktops.isEmpty)
    }

    @Test func migrationEmptyProfileGetsNothing() throws {
        let (data, _, _, c) = try legacy()
        var d = try load(data)
        d.switchProfile(to: c)
        #expect(d.desktopNames.isEmpty && d.desktopNameSpaces.isEmpty)
        #expect(d.ghostDesktops.isEmpty && d.plannedDesktops.isEmpty)
    }

    @Test func migrationKeepsPendingRemovalsShared() throws {
        var d = Document()
        d.pendingRemovals = ["undocked|builtin": [PendingRemoval(desktop: 2, space: 9)]]
        d.addProfile(named: "B")
        let loaded = try load(try oldFile(d))
        #expect(loaded.pendingRemovals == d.pendingRemovals)
    }

    @Test func migrationOfV1V2FileWithoutProfiles() throws {
        let json = """
        {"version":2,"rules":[{"id":"r","appName":"A","bundleID":"b.A","tokens":[],
          "docked":{"screen":"external","desktop":2}}],
         "desktopNames":{"external":{"2":"Nova","5":"Unused"}}}
        """
        let d = try load(Data(json.utf8))
        #expect(d.profiles.count == 1)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
        #expect(d.desktopName(screen: "external", desktop: 5, mode: D) == nil)
    }

    @Test func migrationIsIdempotentAfterSave() throws {
        let (data, _, _, _) = try legacy()
        let once = try load(data)
        let twice = try load(try Store.encode(once))
        #expect(twice.profiles == once.profiles)
        #expect(twice.desktopNames == once.desktopNames)
    }

    // MARK: - File format

    @Test func roundTripKeepsPerProfileState() throws {
        let (d, _, _) = twoProfilesOnSpace20()
        var saved = d
        saved.syncActiveProfile()
        let loaded = try load(try Store.encode(saved))
        #expect(loaded.profiles == saved.profiles)
        #expect(loaded.desktopNames == saved.desktopNames)
        #expect(loaded.desktopNameSpaces == saved.desktopNameSpaces)
        #expect(loaded.ghostDesktops == saved.ghostDesktops)
        #expect(loaded.plannedDesktops == saved.plannedDesktops)
        #expect(loaded.pendingRemovals == saved.pendingRemovals)
    }

    @Test func profileFieldsAreWrittenPerProfile() throws {
        let (d, _, _) = twoProfilesOnSpace20()
        let json = try #require(try JSONSerialization.jsonObject(with: Store.encode(d)) as? [String: Any])
        let profiles = try #require(json["profiles"] as? [[String: Any]])
        #expect(profiles.allSatisfy { $0["desktopNames"] != nil })
    }

    @Test func schemaVersionBumpedSoOldAppOpensReadOnly() throws {
        #expect(Document.currentVersion >= 5)
        let json = try #require(try JSONSerialization.jsonObject(with: Store.encode(Document())) as? [String: Any])
        #expect(json["version"] as? Int == Document.currentVersion)
    }

    @Test func newerFileIsFlaggedAndNotMigrated() throws {
        var json = try #require(try JSONSerialization.jsonObject(
            with: Store.encode(twoProfilesOnSpace20().0)) as? [String: Any])
        json["version"] = Document.currentVersion + 1
        let d = try load(try JSONSerialization.data(withJSONObject: json))
        #expect(d.isFromNewerVersion)
    }

    @Test func oldFileLoadsWithoutPerProfileFields() throws {
        let json = #"{"version":4,"profiles":[{"id":"p","name":"P","rules":[]}],"activeProfileID":"p"}"#
        let d = try load(Data(json.utf8))
        #expect(d.profiles.first?.desktopNames.isEmpty == true)
        #expect(d.desktopNames.isEmpty)
    }

    // MARK: - Visible surfaces (status.json, CLI, menu, map)

    @Test func statusAndCLINamesAreActiveProfileOnly() {
        var (d, first, second) = twoProfilesOnSpace20()
        #expect(d.desktopNames(for: D)["external"] == ["2": "Nova"])
        d.switchProfile(to: second)
        #expect(d.desktopNames(for: D)["external"] == ["2": "Deney"])
        #expect(!d.desktopNames(for: D).values.contains { $0.values.contains("Nova") })
        d.switchProfile(to: first)
        #expect(d.desktopName(screen: "external", desktop: 2, mode: D) == "Nova")
    }

    @Test func ghostsShownAreActiveProfileOnly() {
        var (d, _, second) = twoProfilesOnSpace20()
        #expect(d.ghosts(on: "external", mode: D).map(\.name) == ["Old"])
        d.switchProfile(to: second)
        #expect(d.ghosts(on: "external", mode: D).isEmpty)
    }

    @MainActor @Test func storeSwitchUpdatesPublishedNamesImmediately() {
        let (d, _, second) = twoProfilesOnSpace20()
        let store = Store(demo: d)
        store.switchProfile(to: second)
        #expect(store.desktopName(screen: "external", desktop: 2, mode: D) == "Deney")
        #expect(store.document.desktopNames(for: D)["external"]?["2"] == "Deney")
    }

    @Test func noProfileSeesNameItDidNotGive() {
        var (d, _, _) = twoProfilesOnSpace20()
        let fresh = d.addProfile(named: "Fresh")
        #expect(d.activeProfileID == fresh.id)
        for mode in Mode.allCases { #expect(d.desktopNames(for: mode).isEmpty) }
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
