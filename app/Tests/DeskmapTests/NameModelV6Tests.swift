import Foundation
import Testing
@testable import Deskmap

/// Şema 6 veri modeli: kodlama, profil yalıtımı, dışa/içe aktarma, durum dosyası.
struct NameModelV6Tests {

    private func richDocument() -> Document {
        V6.document(rules: [V6.rule("A", docked: V6.at("external", 2, name: "M"))],
                    names: [DesktopName(id: "M", name: "Nova", space: 20)],
                    plans: DesktopPlans(docked: ["external": ["", "M"]], undocked: ["builtin": ["", "M"]]))
    }

    @Test func roundTripKeepsNamesPlansAndNameTargets() throws {
        var d = richDocument()
        d.ghostDesktops = [GhostDesktop(screen: "external", name: "Old", desktop: 5,
                                        deletedAt: Date(timeIntervalSince1970: 0), nameID: "O", cause: "deleted")]
        let data = try Store.encode(d)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("desktopNames") && !text.contains("desktopNameSpaces") && !text.contains("plannedDesktops"))
        #expect(text.contains("\"version\" : 6"))
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.names == d.names && back.plans == d.plans)
        #expect(back.rules.first?.docked?.nameID == "M")
        #expect(back.ghostDesktops.first?.nameID == "O")
        #expect(!back.needsNameMigration)
    }

    @Test func numberTargetsEncodeWithoutNameID() throws {
        let data = try JSONEncoder().encode(V6.e(2))
        #expect(!String(decoding: data, as: UTF8.self).contains("nameID"))
    }

    // MARK: - Profil yalıtımı

    @Test func newProfileStartsEmpty() {
        var d = richDocument()
        d.addProfile(named: "Fresh")
        #expect(d.names.isEmpty && d.plans.isEmpty && d.rules.isEmpty && d.ghostDesktops.isEmpty)
    }

    @Test func duplicateCopiesAndIsIndependent() throws {
        var d = richDocument()
        let first = d.activeProfileID
        d.addProfile(named: "Copy", copyingCurrent: true)
        #expect(d.names == [DesktopName(id: "M", name: "Nova", space: 20)])
        d.setDesktopName("Deney", screen: "external", desktop: 2, mode: .docked)
        d.switchProfile(to: first)
        #expect(d.names.first?.name == "Nova")
    }

    @Test func renameAndDeletionOnlyTouchTheirProfiles() {
        var d = richDocument()
        let first = d.activeProfileID
        d.addProfile(named: "Other", activate: true)
        d.names = [DesktopName(id: "Z", name: "Zeta", space: 30)]
        d.syncActiveProfile()
        d.switchProfile(to: first)
        d.setDesktopName("Renamed", screen: "external", desktop: 2, mode: .docked)
        #expect(d.profiles.first { $0.id != first }?.names.first?.name == "Zeta")
        // Gerçek silme: her profil kendi adını hayalete taşır.
        d.recordDeletion(space: 30, role: "external", desktop: 3, mode: .docked)
        #expect(d.profiles.first { $0.id != first }?.ghostDesktops.first?.name == "Zeta")
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func twoProfilesMayNameTheSameSpaceDifferently() {
        var d = richDocument()
        d.addProfile(named: "B")
        let ok1 = d.setDesktopName("Notes", screen: "external", desktop: 2, mode: .docked,
                                 live: LiveDesktops(mode: .docked, spaces: ["external": [10, 20]])); #expect(ok1)
        #expect(d.names.first?.space == 20)
        #expect(d.profiles.first { $0.name != "B" }?.names.first?.space == 20)
    }

    // MARK: - Dışa / içe aktarma

    /// Sürüm 5 (isteğe bağlı pin grupları) sürüm 4'ün alanlarını aynen taşır.
    @Test func exportV5KeepsV4Fields() throws {
        let d = richDocument()
        let data = try d.exportData(for: d.activeProfileID)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"version\" : 5"))
        #expect(!text.contains("pinGroups"))
        #expect(!text.contains("\"space\""))
        var other = Document()
        let imported = try other.importProfile(from: data)
        #expect(imported.names.count == 1 && imported.names[0].space == nil)
        #expect(imported.names[0].id != "M")
        #expect(imported.rules.first?.docked?.nameID == imported.names[0].id)
        #expect(imported.plans.entries(.docked, "external") == ["", imported.names[0].id])
    }

    @Test func importV3CreatesUnplacedNames() throws {
        let json = """
        {"kind": "deskmap-profile", "version": 3, "name": "Old",
         "rules": [{"id": "r", "appName": "Code", "bundleID": "b", "tokens": [],
                    "docked": {"screen": "external", "desktop": 2, "layout": {"x":0,"y":0,"w":1,"h":1}}}],
         "desktopNames": {"docked|external": {"2": "Paper"}, "undocked|builtin": {"5": "Paper"}},
         "plannedDesktops": {"docked|external": 3}}
        """
        var d = Document()
        let p = try d.importProfile(from: Data(json.utf8))
        #expect(p.names.map(\.name) == ["Paper"] && p.names[0].space == nil)
        #expect(V6.named(p.plans.entries(.docked, "external"), p) == ["", "Paper", ""])
        #expect(V6.named(p.plans.entries(.undocked, "builtin"), p) == ["", "", "", "", "Paper"])
        #expect(p.rules[0].docked?.nameID == p.names[0].id)
        // R4: ilk uygulamada plandaki yerine bağlanır.
        d.bindByPlan(live: LiveDesktops(mode: .docked, spaces: ["external": [7, 8, 9]]))
        #expect(d.names.first?.space == 8)
    }

    // MARK: - Durum dosyası

    @Test func statusNamesShowLiveAndPlannedPlaces() {
        let d = richDocument()
        let names = StatusFile.names(d, live: LiveDesktops(mode: .docked, spaces: ["external": [10, 20]]))
        #expect(names.first?.screen == "external" && names.first?.desktop == 2)
        #expect(names.first?.planned == ["docked": "external/2", "undocked": "builtin/2"])
        #expect(d.desktopNames(for: .undocked) == ["builtin": ["2": "Nova"]])
    }
}

/// `desktop-state.json` (docs/desktop-names-v2.md §A.4).
struct DesktopStateFileTests {

    @Test func roundTripAndLegacyRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-ds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(DesktopStateFile.read(directory: dir) == nil)
        try Data(#"{"external":[1681,1674],"builtin":[5,4]}"#.utf8)
            .write(to: dir.appendingPathComponent("desktop-spaces.json"))
        let legacy = try #require(DesktopStateFile.readLegacy(directory: dir))
        #expect(legacy.spaces == ["external": [1681, 1674], "builtin": [5, 4]])
        #expect(legacy.mode == .docked)
        let state = DesktopStateFile(mode: .undocked, displays: [.init(role: "builtin", uuid: "B", spaces: [5])],
                                     contents: ["5": [.init(id: 1, pid: 2, bundleID: "x")]],
                                     parked: [.init(window: 1, role: "external", desktop: 2, space: 9)])
        try state.write(directory: dir)
        let back = try #require(DesktopStateFile.read(directory: dir))
        #expect(back.displays == state.displays && back.contents == state.contents)
        #expect(back.parked.map(\.window) == [1])
        #expect(back.snapshot.contents == [5: [1]])
    }

    @Test func sameDisplaysComparesRolesAndMonitors() {
        let state = DesktopStateFile(mode: .docked, displays: [.init(role: "builtin", uuid: "B", spaces: []),
                                                              .init(role: "external", uuid: "E1", spaces: [])])
        #expect(state.sameDisplays(as: [.init(role: "external", uuid: "E1", spaces: [9]),
                                         .init(role: "builtin", uuid: "B", spaces: [1])]))
        #expect(!state.sameDisplays(as: [.init(role: "external", uuid: "E2", spaces: []),
                                          .init(role: "builtin", uuid: "B", spaces: [])]))
        #expect(!state.sameDisplays(as: [.init(role: "builtin", uuid: "B", spaces: [])]))
    }

    @Test func parkedEntriesExpire() {
        let now = Date()
        let parked: [PlanApply.Parked] = [
            .init(window: 1, role: "external", desktop: 1, space: 1, since: now),
            .init(window: 2, role: "external", desktop: 1, space: 1, since: now.addingTimeInterval(-15 * 24 * 3600)),
            .init(window: 3, role: "external", desktop: 1, space: 1, since: now),
        ]
        #expect(DesktopStateFile.prunedParked(parked, alive: [1, 2], now: now).map(\.window) == [1])
        #expect(DesktopStateFile.prunedParked(parked, alive: nil, now: now).map(\.window) == [1, 3])
    }
}
