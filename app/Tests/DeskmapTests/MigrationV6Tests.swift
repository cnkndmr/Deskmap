import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Şema 5 → 6 geçişi (docs/desktop-names-v2.md §A.8).
struct MigrationV6Tests {

    private func profile(_ d: Document, _ id: String) throws -> Profile {
        var synced = d
        synced.syncActiveProfile()
        return try #require(synced.profiles.first { $0.id == id })
    }

    private func migrated() -> (Document, MigrationReport) {
        let result = MigrationV6.migrate(V6.incidentDocument(), evidence: V6.evidence(V6.normalProfilWindows()))
        return (result.document, result.report)
    }

    // MARK: - Walkthrough: work profile

    /// §A.8 walkthrough: Orion→1681, Nova Ek→1674, Lumen→1672,
    /// AI Setup→8, Notes Hub→1652, Nova Project→1653.
    @Test func normalProfil20261012() throws {
        let (d, report) = migrated()
        let normal = try profile(d, V6.normalID)
        #expect(V6.bindings(normal) == [
            "Orion": 1681, "Nova Ek": 1674, "Lumen": 1672, "AI Setup": 8, "Notes Hub": 1652,
            "Nova Project": 1653,
        ])
        #expect(V6.named(normal.plans.entries(.docked, "builtin"), normal)
                == ["", "", "", "AI Setup", "Notes Hub", "Nova Project"])
        #expect(V6.named(normal.plans.entries(.docked, "external"), normal)
                == ["Orion", "Nova Ek", "", "Lumen"])
        #expect(V6.named(normal.plans.entries(.undocked, "builtin"), normal)
                == ["", "", "", "AI Setup", "Notes Hub", "Nova Project",
                    "Nova Ek", "Lumen", "Orion", ""])
        func target(_ app: String, _ token: String, _ mode: Mode) -> String? {
            let rule = normal.rules.first { $0.appName == app && $0.tokens == [token] }
            return rule?[mode]?.nameID.flatMap { id in normal.names.first { $0.id == id }?.name }
        }
        #expect(target("Code", "orion-code", .docked) == "Orion")
        #expect(target("Code", "orion-code", .undocked) == "Orion")
        #expect(target("Word", "comet1", .docked) == "Nova Ek")
        #expect(target("Word", "comet1", .undocked) == "Nova Ek")
        #expect(target("Code", "lumen-code", .docked) == "Lumen")
        #expect(target("Code", "lumen-code", .undocked) == "Lumen")
        #expect(target("ChatGPT", "", .docked) == nil)
        let ai = normal.rules.first { $0.appName == "ChatGPT" }
        #expect(ai?.docked?.nameID == normal.names.first { $0.name == "AI Setup" }?.id)
        #expect(target("cmux", "hub", .docked) == "Notes Hub")
        #expect(target("Excel", "nova-1", .undocked) == "Nova Project")
        // Builtin 1–3 ve Terminal (b10) numara hedefi kalır.
        let mail = try #require(normal.rules.first { $0.tokens == ["mail"] })
        #expect(mail.docked?.nameID == nil && mail.docked?.desktop == 1)
        let terminal = try #require(normal.rules.first { $0.appName == "Terminal" })
        #expect(terminal.undocked?.nameID == nil && terminal.undocked?.desktop == 10)
        // M2: çöp "Notes Hub" hayaletinin Terminal pini Notes Hub'ye ad pini, düzeniyle.
        #expect(terminal.docked?.nameID == normal.names.first { $0.name == "Notes Hub" }?.id)
        #expect(terminal.docked?.layout.w == 1.0 / 6)
        #expect(terminal.docked?.screen == "builtin" && terminal.docked?.desktop == 5)
        #expect(normal.ghostDesktops.isEmpty)
        // Önbellek: ad hedefi canlı yerini gösterir.
        let orion = try #require(normal.rules.first { $0.tokens == ["orion-code"] })
        #expect(orion.docked?.screen == "external" && orion.docked?.desktop == 1)
        #expect(orion.undocked?.screen == "builtin" && orion.undocked?.desktop == 9)
        let entry = try #require(report.profiles.first { $0.profileID == V6.normalID })
        #expect(entry.bound.count == 6 && entry.unplaced.isEmpty)
        #expect(entry.ghostsRemoved == 1 && entry.pinsRestored == 1)
        #expect(d.fileVersion == Document.currentVersion)
        #expect(d.profiles.allSatisfy { $0.legacy == nil })
    }

    /// M1: planın ötesindeki boş masaüstüleri raporda (silinmez).
    @Test func emptyDesktopsBeyondPlanAreReportedNotRemoved() {
        let (d, report) = migrated()
        #expect(report.emptyBeyondPlan["builtin"] == [1678, 1679, 1680])
        #expect(report.emptyBeyondPlan["external"] == [1032])
        #expect(report.emptyCount == 4)
        _ = d
    }

    // MARK: - Öbür profiller

    @Test func copyProfileKeepsRealDeletionsAndRestoresJunkPins() throws {
        let (d, report) = migrated()
        let copy = try profile(d, V6.copyID)
        #expect(V6.bindings(copy) == ["AI Setup": 8])
        #expect(Set(copy.ghostDesktops.compactMap(\.name)) == ["Orion Projesi", "Notes Hub"])
        #expect(copy.ghostDesktops.allSatisfy { $0.cause == GhostDesktop.deletedCause })
        let mail = try #require(copy.rules.first { $0.appName == "Mail" })
        #expect(mail.docked?.screen == "external" && mail.docked?.desktop == 1 && mail.docked?.nameID == nil)
        #expect(copy.rules.contains { $0.appName == "Music" })
        #expect(report.profiles.first { $0.profileID == V6.copyID }?.ghostsRemoved == 1)
    }

    @Test func denemeWithoutEvidenceUsesCurrentBinding() throws {
        let (d, _) = migrated()
        let deneme = try profile(d, V6.denemeID)
        #expect(V6.bindings(deneme) == ["AI Setup": 8, "Nova Ek": 1672])
        #expect(V6.named(deneme.plans.entries(.docked, "builtin"), deneme) == ["", "", "", "AI Setup", "", ""])
        #expect(V6.named(deneme.plans.entries(.docked, "external"), deneme) == ["", "", "", "Nova Ek"])
        #expect(V6.named(deneme.plans.entries(.undocked, "builtin"), deneme)
                == ["", "", "", "AI Setup", "", "", "Nova Ek"])
        #expect(deneme.ghostDesktops.map(\.name) == ["Lumen Makale"])
    }

    /// Çöp olay grubu: aynı an, ekran, sıra; bir üyesi adı canlı hayaletse
    /// grubun bütün hayaletleri (başka profillerin adsızları da) çöptür.
    @Test func junkGhostEventGroup() throws {
        let (d, _) = migrated()
        for id in [V6.normalID, V6.copyID, V6.denemeID] {
            #expect(try profile(d, id).ghostDesktops.allSatisfy {
                abs($0.deletedAt.timeIntervalSince(V6.incident)) > 0.001
            })
        }
    }

    /// Çöp hayaletin kaydırmasının tersi: numara hedefleri bir geri gelir
    /// (adlara dönüşenler değil), pinler kayıtlı yerlerine.
    @Test func junkGhostReversesShiftOfNumberTargets() throws {
        var d = Document()
        let pid = d.activeProfileID
        d.profiles[0].rules = [V6.rule("Left", docked: V6.e(2)), V6.rule("Named", docked: V6.e(3))]
        d.profiles[0].legacy = LegacyNames(desktopNames: ["docked|external": ["3": "N"]],
                                           desktopNameSpaces: ["docked|external": ["3": 30]])
        d.profiles[0].ghostDesktops = [GhostDesktop(
            screen: "external", name: "N", desktop: 1, deletedAt: V6.incident,
            pins: [GhostDesktop.Pin(profileID: pid, mode: .docked, rule: V6.rule("Back"),
                                    destination: V6.e(1))])]
        d.loadProfileState(d.profiles[0])
        d.fileVersion = 5
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 20, 30, 40], "builtin": [1]])
        let result = MigrationV6.migrate(d, evidence: MigrationEvidence(live: live, windows: []))
        let rules = result.document.rules
        #expect(rules.first { $0.appName == "Left" }?.docked?.desktop == 3)
        #expect(rules.first { $0.appName == "Named" }?.docked?.nameID != nil)
        let back = try #require(rules.first { $0.appName == "Back" })
        #expect(back.docked?.nameID == result.document.names.first?.id)
    }

    // MARK: - Kanıtsız

    @Test func noEvidenceFallback() {
        let result = MigrationV6.migrate(V6.incidentDocument(), evidence: nil)
        let normal = result.document.profiles.first { $0.id == V6.normalID }!
        // Kanıt yok: etkin kurulumun (docked) eski bağı.
        #expect(V6.bindings(normal)["Orion"] == 1674)
        #expect(V6.bindings(normal)["Nova Ek"] == 1673)
        #expect(V6.bindings(normal)["Lumen"] == 1032)
        #expect(!result.report.withEvidence)
        // Kurallar eski tablolarla ada bağlanır.
        let word = normal.rules.first { $0.tokens == ["comet1"] }
        #expect(word?.docked?.nameID == normal.names.first { $0.name == "Orion" }?.id)
        #expect(word?.undocked?.nameID == normal.names.first { $0.name == "Nova Ek" }?.id)
    }

    @Test func v6NeverWritesLegacyTables() throws {
        var source = V6.incidentDocument()
        source.syncActiveProfile()
        let data = try Store.encode(source)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        #expect(decoded.fileVersion == Document.currentVersion)
        // Kaydedilen dosya v6'dır; v5 kaynağı yeniden okununca `legacy` gelmez.
        #expect(decoded.profiles.allSatisfy { $0.legacy == nil })
    }

    // MARK: - Güvenlik

    @Test func neverMovesOrRemoves() {
        let before = V6.incidentDocument()
        let result = MigrationV6.migrate(before, evidence: V6.evidence(V6.normalProfilWindows()))
        #expect(result.document.pendingRemovals == before.pendingRemovals)
        #expect(result.document.screens == before.screens)
        #expect(result.document.enabled == before.enabled)
        // Saf işlev: masaüstü sayısı ya da pencere bilgisi döndürmez, yalnız belge ve rapor.
        #expect(result.report.emptyCount == 4)
    }

    @Test func backupWrittenFirst() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rules = Data("{\"version\":5}".utf8)
        try rules.write(to: dir.appendingPathComponent("rules.json"))
        try Data("{\"builtin\":[1]}".utf8).write(to: dir.appendingPathComponent("desktop-spaces.json"))
        let now = Date(timeIntervalSince1970: 1_791_820_000)
        let url = try Store.writePreMigrationBackup(at: now, directory: dir)
        #expect(try Data(contentsOf: url) == rules)
        #expect(url.lastPathComponent.hasPrefix("rules-v5-"))
        let folder = dir.appendingPathComponent("Backups/pre-migration")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("desktop-spaces-") })
    }

    @Test func backupFailureStopsMigration() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-migration-\(UUID().uuidString)", isDirectory: true)
        // rules.json yok: kopya yazılamaz.
        #expect(throws: (any Error).self) {
            try Store.writePreMigrationBackup(at: Date(), directory: dir)
        }
    }

    /// Satır 22: şema 5 yedeği geri yüklenince geçiş canlı kanıtla tamamlanır.
    @MainActor @Test func restoreV5Migrates() throws {
        let store = Store(demo: Document())
        #expect(store.restoreBackup(V6.incidentDocument()))
        #expect(store.migrationPending)
        #expect(store.completeMigration(evidence: V6.evidence(V6.normalProfilWindows())))
        #expect(!store.migrationPending)
        #expect(V6.bindings(try #require(store.document.activeProfile.map { _ in
            Profile(name: "x", names: store.document.names) }))["Orion"] == 1681)
        #expect(store.migrationReport?.emptyCount == 4)
        store.undo()
        #expect(store.document.names.first { $0.name == "Orion" }?.space != 1681)
    }

    /// v6 yedeği: masaüstü canlı olmayan adlar plana göre bağlanır (R4).
    @MainActor @Test func restoreV6() {
        let store = Store(demo: Document())
        store.setLive(LiveDesktops(mode: .docked, spaces: ["external": [7, 8]]))
        var backup = V6.document(names: [DesktopName(id: "K", name: "K", space: 999)],
                                 plans: DesktopPlans(docked: ["external": ["", "K"]]))
        backup.fileVersion = 6
        #expect(store.restoreBackup(backup))
        #expect(store.document.names.first?.space == 8)
    }

    // MARK: - v<5 dosyası

    @Test func schemaFourSharedStateMigratesThroughLegacy() throws {
        let json = """
        {"version": 4, "activeProfileID": "P", "rules": [
            {"id": "r1", "appName": "Code", "bundleID": "b.Code", "tokens": [],
             "docked": {"screen": "external", "desktop": 2, "layout": {"x":0,"y":0,"w":1,"h":1}}}],
         "profiles": [{"id": "P", "name": "Main", "rules": []}],
         "desktopNames": {"external": {"2": "Paper"}},
         "desktopNameSpaces": {"external": {"2": 42}}}
        """
        let decoded = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        #expect(decoded.needsNameMigration)
        #expect(decoded.profiles[0].legacy?.desktopNames["docked|external"]?["2"] == "Paper")
        let live = LiveDesktops(mode: .docked, spaces: ["external": [41, 42], "builtin": [1]])
        let result = MigrationV6.migrate(decoded, evidence: MigrationEvidence(live: live, windows: []))
        #expect(result.document.names.map(\.name) == ["Paper"])
        #expect(result.document.names.first?.space == 42)
        #expect(result.document.rules.first?.docked?.nameID == result.document.names.first?.id)
        #expect(V6.named(result.document.plans.entries(.docked, "external"),
                         result.document.profiles[0]) == ["", "Paper"])
    }

    // MARK: - Canlı veri kopyası (yalnız ortam değişkeniyle)

    /// `DESKMAP_V6_LIVE_DIR` bir klasörü gösteriyorsa (rules.json,
    /// desktop-spaces.json, status.json kopyaları) geçişi o kopyada çalıştırır
    /// ve sonucu yazdırır; yoksa atlanır. Kullanıcının dosyalarına dokunmaz.
    @Test func liveCopyHarness() throws {
        guard let path = ProcessInfo.processInfo.environment["DESKMAP_V6_LIVE_DIR"], !path.isEmpty
        else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let source = try JSONDecoder().decode(Document.self,
                                              from: Data(contentsOf: dir.appendingPathComponent("rules.json")))
        let spaces = try JSONDecoder().decode([String: [UInt64]].self,
                                              from: Data(contentsOf: dir.appendingPathComponent("desktop-spaces.json")))
        struct Status: Decodable {
            struct Window: Decodable {
                var id: UInt32; var app: String; var bundleID: String; var title: String
                var screen: String?; var desktop: Int?; var document: String?; var fullscreen: Bool
            }
            var mode: String
            var windows: [Window]
        }
        let status = try JSONDecoder().decode(Status.self,
                                              from: Data(contentsOf: dir.appendingPathComponent("status.json")))
        let live = LiveDesktops(mode: Mode(rawValue: status.mode) ?? .docked, spaces: spaces)
        let windows = status.windows.compactMap { w -> MigrationEvidence.Window? in
            guard !w.fullscreen, let screen = w.screen, let desktop = w.desktop,
                  let space = live.space(at: Slot(screen: screen, desktop: desktop)) else { return nil }
            return .init(id: w.id, space: space, bundleID: w.bundleID, appName: w.app, title: w.title,
                         document: w.document)
        }
        let result = MigrationV6.migrate(source, evidence: MigrationEvidence(live: live, windows: windows))
        var out = "LIVE COPY MIGRATION (mode \(live.mode.rawValue))\n"
        var doc = result.document
        doc.syncActiveProfile()
        for profile in doc.profiles {
            out += "== \(profile.name)\n"
            for name in profile.names {
                let place = name.space.flatMap { live.place(of: $0) }
                out += "  name \(name.name) -> \(name.space.map(String.init) ?? "unplaced")"
                    + (place.map { " (\($0.screen)/\($0.desktop))" } ?? "") + "\n"
            }
            for mode in Mode.allCases {
                for role in profile.plans[mode].keys.sorted() {
                    out += "  plan \(mode.rawValue)/\(role): \(V6.named(profile.plans.entries(mode, role), profile))\n"
                }
            }
            var counts: [String: Int] = [:]
            for rule in profile.rules {
                for mode in Mode.allCases {
                    guard let d = rule[mode] else { continue }
                    let label = d.nameID.flatMap { id in profile.names.first { $0.id == id }?.name }
                        .map { "name:\($0)" } ?? "number:\(d.screen)/\(d.desktop)"
                    counts["\(mode.rawValue) \(label)", default: 0] += 1
                }
            }
            for key in counts.keys.sorted() { out += "  rules \(key) ×\(counts[key]!)\n" }
            out += "  ghosts kept: \(profile.ghostDesktops.map { $0.name ?? "(unnamed \($0.screen)/\($0.desktop))" })\n"
        }
        for entry in result.report.profiles {
            out += "report \(entry.profileName): ghostsRemoved=\(entry.ghostsRemoved) pinsRestored=\(entry.pinsRestored) unplaced=\(entry.unplaced)\n"
        }
        out += "empty beyond plan: \(result.report.emptyBeyondPlan)\n"
        try out.write(to: dir.appendingPathComponent("migration-result.txt"), atomically: true, encoding: .utf8)
        print(out)
    }
}
