import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `status.json` üretimi: alanlar, kararlılık, hata yolu. Yalnız geçici
/// dizine yazılır; canlı Deskmap dosyasına dokunulmaz. (Gerçek yola yazan
/// `StatusFile` kurulumu AppModel'de olduğundan o yol denenmez.)
@MainActor
struct StatusFileTests {

    @MainActor final class Setup {
        let store: Store
        let screens: ScreenService
        let router: Router
        let dir: URL
        var url: URL { dir.appendingPathComponent("status.json") }
        let status: StatusFile
        var displays: [ScreenService.RawDisplay]

        init(rules: [Rule] = [], profiles: [Profile]? = nil, docked: Bool = true,
             windows: [Router.WindowSnapshot] = [], document: Document? = nil) throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("deskmap-status-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var doc = document ?? Document()
            if document == nil {
                doc.rules = rules
                if let profiles {
                    doc.profiles = profiles
                    doc.activeProfileID = profiles[0].id
                    doc.rules = profiles[0].rules
                }
            }
            let list = docked ? [RouterHarness.builtin, RouterHarness.monitor] : [RouterHarness.builtin]
            displays = list
            store = Store(demo: doc)
            screens = ScreenService(displays: { list })
            router = Router(store: store, screens: screens, demoWindows: windows)
            status = StatusFile(url: dir.appendingPathComponent("status.json"),
                                store: store, router: router, screens: screens)
        }

        deinit { try? FileManager.default.removeItem(at: dir) }

        func read() throws -> StatusFile.Snapshot {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StatusFile.Snapshot.self, from: Data(contentsOf: url))
        }

        func raw() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
    }

    static func window(_ id: CGWindowID, app: String = "Notlar", title: String = "Taslak",
                       placement: Router.Placement? = nil, frame: CGRect? = nil,
                       minimized: Bool = false, document: String? = nil) -> Router.WindowSnapshot {
        .init(id: id, pid: 1, appName: app, bundleID: "b.\(app)", title: title,
              placement: placement, frame: frame, isMinimized: minimized, document: document)
    }

    // MARK: - Üst düzey alanlar

    @Test func writesTopLevelFields() throws {
        let rule = V6.rule("Mail", docked: V6.b(1), undocked: V6.b(1))
        let s = try Setup(profiles: [Profile(id: "A", name: "Çalışma", rules: [rule]),
                                     Profile(id: "B", name: "Ev", rules: [])])
        s.status.write(request: "r1")
        let snap = try s.read()
        #expect(snap.pid == ProcessInfo.processInfo.processIdentifier)
        #expect(abs(snap.updated.timeIntervalSinceNow) < 30)
        #expect(snap.request == "r1")
        #expect(snap.enabled)
        #expect(snap.mode == "docked")
        #expect(snap.profile == "Çalışma")
        #expect(snap.profiles == ["Çalışma", "Ev"])
        #expect(snap.lastError == nil)
        #expect(snap.rules.map(\.appName) == ["Mail"])
        #expect(["on", "held", "reduced", "unavailable"].contains(snap.desktopMoves))
        #expect(snap.heldRoles.isEmpty)
        #expect(snap.windows.isEmpty)
    }

    @Test func requestFieldOmittedWhenNil() throws {
        let s = try Setup()
        s.status.write(request: nil)
        #expect(try s.raw()["request"] == nil)
        #expect(try s.read().request == nil)
        s.status.write(request: "")
        #expect(try s.read().request == "")
    }

    @Test func reflectsPausedStateAndLastError() throws {
        let s = try Setup()
        s.store.document.enabled = false
        s.store.report("Bir şey ters gitti: ğüşiöç")
        s.status.write(request: nil)
        let snap = try s.read()
        #expect(!snap.enabled)
        #expect(snap.lastError == "Bir şey ters gitti: ğüşiöç")
    }

    @Test func modeFollowsDisplays() throws {
        let docked = try Setup(docked: true)
        docked.status.write(request: nil)
        #expect(try docked.read().mode == "docked")
        let laptop = try Setup(docked: false)
        laptop.status.write(request: nil)
        let snap = try laptop.read()
        #expect(snap.mode == "undocked")
        #expect(snap.screens.map(\.id) == ["builtin"])
    }

    // MARK: - Ekranlar

    @Test func screenEntriesCarryGeometryAndPlans() throws {
        var doc = Document()
        doc.plans = DesktopPlans(docked: ["external": ["", ""]], undocked: ["builtin": ["", "", ""]])
        let s = try Setup(document: doc)
        s.status.write(request: nil)
        let snap = try s.read()
        let builtin = try #require(snap.screens.first { $0.id == "builtin" })
        let external = try #require(snap.screens.first { $0.id == "external" })
        #expect(builtin.builtin && !external.builtin)
        #expect(builtin.uuid == "BUILTIN" && external.uuid == "MONITOR")
        #expect(builtin.name == "Built-in")
        #expect(builtin.frame == [0, 0, 1710, 1112])
        #expect(builtin.visible == [0, 0, 1710, 1074])
        #expect(external.frame == [0, 1112, 1920, 1080])
        #expect(external.visible == [0, 1112, 1920, 1050])
        #expect(builtin.desktops == nil && external.desktops == nil) // demo: canlı sayı yok
        #expect(Set(builtin.planned.keys) == Set(Mode.allCases.map(\.rawValue)))
        #expect(builtin.planned["undocked"] == 3 && builtin.planned["docked"] == 0)
        #expect(external.planned["docked"] == 2 && external.planned["undocked"] == 0)
        // Dahili ekran (0,0) kökünde: yükseklik primaryHeight.
        #expect(snap.primaryHeight == 1112)
    }

    @Test func primaryHeightNilWithoutOriginScreen() throws {
        let s = try Setup()
        // Yalnız (0,0) dışında bir ekran verilirse birincil ekran yoktur.
        let shifted = ScreenService.RawDisplay(
            uuid: "ONLY", name: "Only", isBuiltin: false,
            frame: CGRect(x: 100, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: 100, y: 0, width: 800, height: 600))
        let screens = ScreenService(displays: { [shifted] })
        let router = Router(store: s.store, screens: screens, demoWindows: [])
        let file = s.dir.appendingPathComponent("shifted.json")
        StatusFile(url: file, store: s.store, router: router, screens: screens).write(request: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(StatusFile.Snapshot.self, from: Data(contentsOf: file))
        #expect(snap.primaryHeight == nil)
        #expect(snap.screens.count == 1)
    }

    // MARK: - Pencereler

    @Test func windowEntriesMirrorSnapshots() throws {
        let w1 = Self.window(10, app: "Şablon", title: "Rapor – Çalışma Ö",
                             placement: .init(screen: "external", desktop: 2),
                             frame: CGRect(x: 10, y: 20, width: 300, height: 400))
        let w2 = Self.window(11, app: "Mail", title: "Gelen", minimized: true)
        let s = try Setup(windows: [w1, w2])
        s.status.write(request: nil)
        let snap = try s.read()
        #expect(snap.windows.map(\.id) == [10, 11])
        let a = snap.windows[0], b = snap.windows[1]
        #expect(a.app == "Şablon" && a.bundleID == "b.Şablon" && a.title == "Rapor – Çalışma Ö")
        #expect(a.screen == "external" && a.desktop == 2)
        #expect(a.frame == [10, 20, 300, 400])
        #expect(!a.minimized && !a.fullscreen && a.pinned == nil && a.free == nil)
        #expect(b.minimized && b.screen == nil && b.desktop == nil && b.frame == nil)
    }

    @Test func pinnedWindowShowsPin() throws {
        let s = try Setup(windows: [Self.window(10), Self.window(11)])
        s.router.pinSession(10, destination: V6.at("builtin", 3))
        s.status.write(request: nil)
        let snap = try s.read()
        let pinned = try #require(snap.windows.first { $0.id == 10 })
        #expect(pinned.pinned?.screen == "builtin" && pinned.pinned?.desktop == 3)
        #expect(snap.windows.first { $0.id == 11 }?.pinned == nil)
    }

    @Test func freeMoveFieldLockOrISODate() throws {
        let s = try Setup(windows: [Self.window(10), Self.window(11)])
        s.router.pinSession(10, destination: V6.b(1))
        s.router.pinSession(11, destination: V6.b(1))
        s.router.allowFreeMove([10], for: 600)
        s.router.allowFreeMove([11], for: Router.freeMoveUntilLock)
        s.status.write(request: nil)
        let snap = try s.read()
        let timed = try #require(snap.windows.first { $0.id == 10 }?.free)
        let date = try #require(ISO8601DateFormatter().date(from: timed))
        #expect(abs(date.timeIntervalSinceNow - 600) < 5)
        #expect(snap.windows.first { $0.id == 11 }?.free == "lock")
    }

    /// Belge yolu alanı yazılır; ama henüz kararlılığı görülmemiş belge
    /// "file:" anahtarına dönüşmez (başlık sezgisine düşer).
    @Test func documentPathReportedButNotTrustedWithoutHistory() throws {
        let doc = Self.window(10, app: "Editör", title: "a.txt", document: "/tmp/çalışma/a.txt")
        let plain = Self.window(11, app: "Hesap", title: "")
        let s = try Setup(windows: [doc, plain])
        s.status.write(request: nil)
        let snap = try s.read()
        #expect(snap.windows[0].document == "/tmp/çalışma/a.txt")
        #expect(snap.windows[0].key?.hasPrefix("file:") != true)
        #expect(snap.windows[1].document == nil)
        #expect(snap.windows[1].key == nil)
    }

    @Test func windowKeyFromTitleTokens() throws {
        let s = try Setup(windows: [Self.window(10, app: "Editör", title: "notlar.md — proje-alfa")])
        s.status.write(request: nil)
        let key = try #require(try s.read().windows[0].key)
        #expect(key.hasPrefix("title:"))
        #expect(key.contains("proje-alfa"))
    }

    // MARK: - Kurallar, adlar, planlar

    @Test func namesPlansAndDesktopNamesAreWritten() throws {
        let names = [DesktopName(id: "N1", name: "Araştırma", space: 77),
                     DesktopName(id: "N2", name: "Posta")]
        var plans = DesktopPlans(docked: ["external": ["N1", "N2"]])
        plans.docked = ["external": ["N1", "N2"]]
        let doc = V6.document(rules: [V6.rule("Mail", docked: V6.e(1))], names: names, plans: plans)
        let s = try Setup(document: doc)
        s.status.write(request: nil)
        let snap = try s.read()
        #expect(snap.names.map(\.name) == ["Araştırma", "Posta"])
        #expect(snap.names[0].planned["docked"] == "external/1")
        #expect(snap.names[1].planned["docked"] == "external/2")
        #expect(snap.names[0].space == 77 && snap.names[1].space == nil)
        #expect(snap.plans.docked["external"] == ["N1", "N2"])
        #expect(snap.deletedDesktops.isEmpty)
        #expect(snap.rules.count == 1)
    }

    @Test func staticNamesWithLiveSpaces() {
        let names = [DesktopName(id: "A", name: "Bir", space: 20), DesktopName(id: "B", name: "Yok", space: 99)]
        let doc = V6.document(names: names)
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 20]])
        let list = StatusFile.names(doc, live: live)
        #expect(list.map(\.id) == ["A", "B"])
        #expect(list[0].screen == "external" && list[0].desktop == 2)
        #expect(list[1].screen == nil && list[1].desktop == nil)
        #expect(StatusFile.names(doc, live: nil).allSatisfy { $0.screen == nil && $0.desktop == nil })
        #expect(StatusFile.names(V6.document(), live: live).isEmpty)
    }

    // MARK: - Kararlılık ve hata yolu

    @Test func repeatedWritesAreIdenticalExceptTimestamp() throws {
        let s = try Setup(rules: [V6.rule("Mail", docked: V6.b(1))],
                          windows: [Self.window(10), Self.window(11, app: "Çizim")])
        s.router.pinSession(10, destination: V6.b(2))
        func stripped() throws -> String {
            var json = try s.raw()
            json["updated"] = nil
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }
        s.status.write(request: "x")
        let first = try stripped()
        s.status.write(request: "x")
        #expect(try stripped() == first)
    }

    @Test func outputIsPrettyPrintedWithSortedKeysAndISODate() throws {
        let s = try Setup()
        s.status.write(request: "q")
        let text = try String(contentsOf: s.url, encoding: .utf8)
        #expect(text.contains("\n  \"")) // prettyPrinted
        let order = ["\"desktopMoves\"", "\"enabled\"", "\"mode\"", "\"pid\"", "\"profiles\"", "\"rules\"", "\"screens\"", "\"windows\""]
        let positions = order.compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == order.count)
        #expect(positions == positions.sorted())
        let updated = try #require(try s.raw()["updated"] as? String)
        #expect(ISO8601DateFormatter().date(from: updated) != nil)
    }

    @Test func overwritesPreviousContentAtomically() throws {
        let s = try Setup(windows: [Self.window(10)])
        s.status.write(request: "bir")
        #expect(try s.read().windows.count == 1)
        s.store.document.enabled = false
        s.status.write(request: "iki")
        let snap = try s.read()
        #expect(snap.request == "iki" && !snap.enabled)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: s.dir.path)
        #expect(leftovers == ["status.json"])
    }

    @Test func writeFailureDoesNotCrashOrCreateFile() throws {
        let s = try Setup()
        let missing = s.dir.appendingPathComponent("yok/alt/status.json")
        let status = StatusFile(url: missing, store: s.store, router: s.router, screens: s.screens)
        status.write(request: "z")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func debouncedChangeWritesFile() async throws {
        let s = try Setup()
        #expect(!FileManager.default.fileExists(atPath: s.url.path))
        s.store.document.enabled = false
        var snap: StatusFile.Snapshot?
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if FileManager.default.fileExists(atPath: s.url.path), let read = try? s.read() {
                snap = read
                break
            }
        }
        let written = try #require(snap)
        #expect(!written.enabled)
        #expect(written.request == nil)
    }
}
